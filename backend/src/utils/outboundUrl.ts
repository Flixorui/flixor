/**
 * SSRF guard for server-side requests to user-supplied URLs.
 *
 * Addresses are checked inside the socket's DNS lookup, so the address that is
 * validated is the address that is connected to, which defeats DNS rebinding.
 * Every redirect hop goes through the same check.
 *
 * Private LAN addresses are refused by default. A route can opt in with
 * `allowPrivateNetwork`, and an operator can open specific hosts with
 * FLIXOR_OUTBOUND_PRIVATE_HOSTS. Neither ever reaches loopback, link-local or
 * cloud metadata addresses.
 *
 * Errors never include the URL, because addon URLs can embed debrid keys.
 */
import dns from 'dns';
import http from 'http';
import https from 'https';
import net from 'net';
import { pipeline, Readable, Transform } from 'stream';
import { AppError } from '../middleware/errorHandler';

export type OutboundErrorCode =
  | 'INVALID_URL'
  | 'BLOCKED_ADDRESS'
  | 'DNS_FAILED'
  | 'TOO_MANY_REDIRECTS'
  | 'TIMEOUT'
  | 'RESPONSE_TOO_LARGE'
  | 'UPSTREAM_ERROR';

const ERROR_STATUS: Record<OutboundErrorCode, number> = {
  INVALID_URL: 400,
  BLOCKED_ADDRESS: 403,
  DNS_FAILED: 502,
  TOO_MANY_REDIRECTS: 502,
  TIMEOUT: 504,
  RESPONSE_TOO_LARGE: 502,
  UPSTREAM_ERROR: 502,
};

export class OutboundUrlError extends AppError {
  readonly code: OutboundErrorCode;

  constructor(code: OutboundErrorCode, message: string) {
    super(message, ERROR_STATUS[code]);
    this.name = 'OutboundUrlError';
    this.code = code;
  }
}

const BLOCKED_IPV4 = new net.BlockList();
for (const [network, prefix] of [
  ['0.0.0.0', 8], // "this" network
  ['10.0.0.0', 8], // private
  ['100.64.0.0', 10], // carrier-grade NAT
  ['127.0.0.0', 8], // loopback
  ['169.254.0.0', 16], // link-local, including cloud metadata
  ['172.16.0.0', 12], // private
  ['192.0.0.0', 24], // IETF protocol assignments
  ['192.0.2.0', 24], // documentation
  ['192.88.99.0', 24], // 6to4 relay
  ['192.168.0.0', 16], // private
  ['198.18.0.0', 15], // benchmarking
  ['198.51.100.0', 24], // documentation
  ['203.0.113.0', 24], // documentation
  ['224.0.0.0', 4], // multicast
  ['240.0.0.0', 4], // reserved and broadcast
] as const) {
  BLOCKED_IPV4.addSubnet(network, prefix, 'ipv4');
}

const IPV4_MAPPED = new net.BlockList();
IPV4_MAPPED.addSubnet('::ffff:0:0', 96, 'ipv6');

// Default deny: only global unicast (2000::/3) is reachable. That also covers
// loopback, link-local, unique-local, multicast, NAT64 and IPv4-compatible forms.
const BLOCKED_IPV6 = new net.BlockList();
for (const [network, prefix] of [
  ['::', 3],
  ['4000::', 2],
  ['8000::', 1],
  ['2001::', 23], // IETF assignments, including Teredo
  ['2001:db8::', 32], // documentation
  ['2002::', 16], // 6to4, which embeds an arbitrary IPv4 address
  ['3fff::', 20], // documentation
] as const) {
  BLOCKED_IPV6.addSubnet(network, prefix, 'ipv6');
}

// Reachable with allowPrivateNetwork. Loopback and link-local are left out on purpose.
const PRIVATE_LAN = new net.BlockList();
for (const [network, prefix] of [
  ['10.0.0.0', 8],
  ['100.64.0.0', 10], // carrier-grade NAT, used by Tailscale
  ['172.16.0.0', 12],
  ['192.168.0.0', 16],
] as const) {
  PRIVATE_LAN.addSubnet(network, prefix, 'ipv4');
}
PRIVATE_LAN.addSubnet('fc00::', 7, 'ipv6'); // unique-local

// Metadata services that sit inside otherwise reachable ranges. Always refused.
const CLOUD_METADATA = new net.BlockList();
CLOUD_METADATA.addAddress('100.100.100.200', 'ipv4'); // Alibaba Cloud
CLOUD_METADATA.addAddress('168.63.129.16', 'ipv4'); // Azure platform endpoint
CLOUD_METADATA.addAddress('fd00:ec2::254', 'ipv6'); // AWS IMDS over IPv6

export interface AddressPolicy {
  /** Also permit private LAN addresses. Never permits loopback, link-local or metadata. */
  allowPrivateNetwork?: boolean;
}

/**
 * True unless `address` may be connected to under `policy`. By default only public,
 * routable IPs pass. Anything unparseable is blocked.
 */
export function isBlockedAddress(address: string, policy: AddressPolicy = {}): boolean {
  const ip = address.split('%')[0]; // drop any IPv6 zone id
  const family = net.isIP(ip);
  if (family !== 4 && family !== 6) return true;
  const type = family === 4 ? 'ipv4' : 'ipv6';
  try {
    // BlockList applies IPv4 rules to IPv4-mapped addresses.
    if (CLOUD_METADATA.check(ip, type)) return true;
    const isPublic =
      family === 4 || IPV4_MAPPED.check(ip, 'ipv6')
        ? !BLOCKED_IPV4.check(ip, type)
        : !BLOCKED_IPV6.check(ip, 'ipv6');
    if (isPublic) return false;
    return !policy.allowPrivateNetwork || !PRIVATE_LAN.check(ip, type);
  } catch {
    return true;
  }
}

const hostnameOf = (url: URL) => url.hostname.replace(/^\[|\]$/g, '');

/** Hosts the operator opened to the LAN through FLIXOR_OUTBOUND_PRIVATE_HOSTS. */
function operatorPrivateHosts(): Set<string> {
  return new Set(
    (process.env.FLIXOR_OUTBOUND_PRIVATE_HOSTS ?? '')
      .split(',')
      .map((host) => host.trim().replace(/^\[|\]$/g, '').replace(/\.$/, '').toLowerCase())
      .filter(Boolean),
  );
}

/** The policy for one hop. An allowlisted host does not open up the hosts it redirects to. */
function policyFor(url: URL, allowPrivateNetwork: boolean | undefined): AddressPolicy {
  if (allowPrivateNetwork) return { allowPrivateNetwork: true };
  const host = hostnameOf(url).replace(/\.$/, '').toLowerCase();
  return { allowPrivateNetwork: operatorPrivateHosts().has(host) };
}

/** Validates scheme, credentials and any literal IP. Hostnames are checked at connect. */
function parseOutboundUrl(input: string | URL, allowPrivateNetwork: boolean | undefined): URL {
  let url: URL;
  try {
    url = new URL(String(input));
  } catch {
    throw new OutboundUrlError('INVALID_URL', 'URL is not valid');
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new OutboundUrlError('INVALID_URL', 'Only http and https URLs are allowed');
  }
  if (url.username || url.password) {
    throw new OutboundUrlError('INVALID_URL', 'URLs with credentials are not allowed');
  }
  const host = hostnameOf(url).replace(/\.$/, '').toLowerCase();
  const blocked = net.isIP(host)
    ? isBlockedAddress(host, policyFor(url, allowPrivateNetwork))
    : host === 'localhost' || host.endsWith('.localhost');
  if (blocked) throw new OutboundUrlError('BLOCKED_ADDRESS', 'Target address is not allowed');
  return url;
}

function guardedLookup(policy: AddressPolicy): net.LookupFunction {
  return (hostname, options, callback) => {
    dns.lookup(hostname, { ...options, all: true, verbatim: true }, (err, addresses) => {
      if (err) {
        callback(err, '', 0);
      } else if (addresses.length === 0 || addresses.some((a) => isBlockedAddress(a.address, policy))) {
        // Any blocked address rejects the host, so a mixed answer cannot slip through.
        callback(new OutboundUrlError('BLOCKED_ADDRESS', 'Target address is not allowed'), '', 0);
      } else if (options.all) {
        callback(null, addresses);
      } else {
        callback(null, addresses[0].address, addresses[0].family);
      }
    });
  };
}

function toOutboundError(err: unknown): OutboundUrlError {
  if (err instanceof OutboundUrlError) return err;
  const code = (err as NodeJS.ErrnoException)?.code;
  if (code === 'ENOTFOUND' || code === 'EAI_AGAIN' || code === 'ENODATA') {
    return new OutboundUrlError('DNS_FAILED', 'Could not resolve target host');
  }
  return new OutboundUrlError('UPSTREAM_ERROR', 'Upstream request failed');
}

/**
 * Resolves `input` and rejects it if it is not public, for failing early with a
 * clear error. This is not protection on its own: use safeFetch for the request.
 */
export async function assertPublicUrl(
  input: string | URL,
  options: AddressPolicy = {},
): Promise<URL> {
  const url = parseOutboundUrl(input, options.allowPrivateNetwork);
  const host = hostnameOf(url);
  if (!net.isIP(host)) {
    const lookup = guardedLookup(policyFor(url, options.allowPrivateNetwork));
    await new Promise<void>((resolve, reject) => {
      lookup(host, { all: true }, (err) => (err ? reject(toOutboundError(err)) : resolve()));
    });
  }
  return url;
}

export interface SafeFetchOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string | Buffer;
  /** Budget in ms for connecting, redirects and buffer()/text()/json() reads. Default 15000. */
  timeoutMs?: number;
  /** Abort if the connection is silent this long, in ms. Default 30000. */
  idleTimeoutMs?: number;
  /** Response size limit in bytes. Default 10 MiB. Media proxies can pass Infinity. */
  maxBytes?: number;
  /** Default 5. */
  maxRedirects?: number;
  /** Pass one tied to the client connection to stop the upstream on disconnect. */
  signal?: AbortSignal;
  /**
   * Also permit private LAN addresses (RFC1918, CGNAT, IPv6 unique-local) on every
   * hop. Loopback, link-local and cloud metadata stay blocked. Default false.
   */
  allowPrivateNetwork?: boolean;
  /**
   * Reuse connections and TLS sessions across requests (media relay range requests).
   * Each address policy has its own pool, and a pooled socket was checked when it
   * connected, so reuse can't reach an address the policy blocks.
   */
  keepAlive?: boolean;
}

const pools = new Map<string, http.Agent>();

function pooledAgent(protocol: string, allowPrivateNetwork: boolean | undefined): http.Agent {
  const key = `${protocol}:${allowPrivateNetwork ? 'private' : 'public'}`;
  let agent = pools.get(key);
  if (!agent) {
    const options = { keepAlive: true, keepAliveMsecs: 15_000, maxSockets: 16, maxFreeSockets: 8, timeout: 60_000 };
    agent = protocol === 'https:' ? new https.Agent(options) : new http.Agent(options);
    pools.set(key, agent);
  }
  return agent;
}

export interface SafeFetchResponse {
  /** Final URL after redirects. May contain secrets: do not log it. */
  url: string;
  status: number;
  statusText: string;
  headers: http.IncomingHttpHeaders;
  /** Size-limited body stream. Consume it, or call abort(). */
  body: Readable;
  buffer(): Promise<Buffer>;
  text(): Promise<string>;
  json<T = unknown>(): Promise<T>;
  abort(): void;
}

const REDIRECT_STATUSES = new Set([301, 302, 303, 307, 308]);
const CROSS_ORIGIN_SAFE_HEADERS = new Set(['accept', 'accept-language', 'range', 'user-agent']);
const DEFAULT_MAX_BYTES = 10 * 1024 * 1024;

interface Hop {
  url: URL;
  method: string;
  headers: Record<string, string>;
  body?: string | Buffer;
}

/** Fetches a user-supplied URL, blocking private targets on every redirect hop. */
export async function safeFetch(
  input: string | URL,
  options: SafeFetchOptions = {},
): Promise<SafeFetchResponse> {
  const {
    timeoutMs = 15_000,
    idleTimeoutMs = 30_000,
    maxBytes = DEFAULT_MAX_BYTES,
    maxRedirects = 5,
    signal,
    allowPrivateNetwork,
    keepAlive,
  } = options;
  const deadline = Date.now() + timeoutMs;
  const headers: Record<string, string> = {};
  for (const [name, value] of Object.entries(options.headers ?? {})) {
    if (name.toLowerCase() !== 'host') headers[name.toLowerCase()] = value;
  }
  let hop: Hop = {
    url: parseOutboundUrl(input, allowPrivateNetwork),
    method: (options.method ?? 'GET').toUpperCase(),
    headers,
    body: options.body,
  };

  for (let redirects = 0; ; redirects++) {
    const { req, res } = await send(hop, deadline, idleTimeoutMs, signal, allowPrivateNetwork, keepAlive);
    const location = res.headers.location;
    if (!location || !REDIRECT_STATUSES.has(res.statusCode ?? 0)) {
      return toResponse(hop.url, req, res, maxBytes, idleTimeoutMs, deadline);
    }
    res.resume();
    req.destroy();
    if (redirects >= maxRedirects) {
      throw new OutboundUrlError('TOO_MANY_REDIRECTS', 'Too many redirects');
    }
    hop = nextHop(hop, res.statusCode ?? 0, location, allowPrivateNetwork);
  }
}

function nextHop(
  hop: Hop,
  status: number,
  location: string,
  allowPrivateNetwork: boolean | undefined,
): Hop {
  let target: URL;
  try {
    target = new URL(location, hop.url);
  } catch {
    throw new OutboundUrlError('INVALID_URL', 'Redirect target is not valid');
  }
  const url = parseOutboundUrl(target, allowPrivateNetwork);

  let headers = hop.headers;
  if (url.origin !== hop.url.origin) {
    // API keys and cookies must not follow a redirect to another origin.
    headers = Object.fromEntries(
      Object.entries(headers).filter(([name]) => CROSS_ORIGIN_SAFE_HEADERS.has(name)),
    );
  }

  const becomesGet =
    (status === 303 && hop.method !== 'HEAD') ||
    ((status === 301 || status === 302) && hop.method === 'POST');
  if (!becomesGet) return { url, method: hop.method, headers, body: hop.body };
  const { 'content-type': _type, 'content-length': _length, ...rest } = headers;
  return { url, method: 'GET', headers: rest };
}

function send(
  hop: Hop,
  deadline: number,
  idleTimeoutMs: number,
  signal: AbortSignal | undefined,
  allowPrivateNetwork: boolean | undefined,
  keepAlive?: boolean,
): Promise<{ req: http.ClientRequest; res: http.IncomingMessage }> {
  return new Promise((resolve, reject) => {
    const timeout = () => new OutboundUrlError('TIMEOUT', 'Upstream request timed out');
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      reject(timeout());
      return;
    }
    const transport = hop.url.protocol === 'https:' ? https : http;
    const req = transport.request({
      hostname: hostnameOf(hop.url),
      port: hop.url.port || undefined,
      path: hop.url.pathname + hop.url.search,
      method: hop.method,
      headers: hop.headers,
      // A shared pool could hand out a socket checked under another policy, so only
      // callers that ask get a per-policy pool; everyone else connects fresh.
      agent: keepAlive ? pooledAgent(hop.url.protocol, allowPrivateNetwork) : false,
      lookup: guardedLookup(policyFor(hop.url, allowPrivateNetwork)),
      signal,
    });
    const timer = setTimeout(() => req.destroy(timeout()), remaining);
    req.setTimeout(idleTimeoutMs, () => req.destroy(timeout()));
    req.on('response', (res) => {
      clearTimeout(timer);
      resolve({ req, res });
    });
    req.on('error', (err) => {
      clearTimeout(timer);
      reject(toOutboundError(err));
    });
    req.end(hop.body);
  });
}

function toResponse(
  url: URL,
  req: http.ClientRequest,
  res: http.IncomingMessage,
  maxBytes: number,
  idleTimeoutMs: number,
  deadline: number,
): SafeFetchResponse {
  const tooLarge = () => new OutboundUrlError('RESPONSE_TOO_LARGE', 'Upstream response is too large');
  if (Number(res.headers['content-length']) > maxBytes) {
    req.destroy();
    throw tooLarge();
  }

  let received = 0;
  const body = new Transform({
    transform(chunk: Buffer, _encoding, done) {
      received += chunk.length;
      if (received > maxBytes) done(tooLarge());
      else done(null, chunk);
    },
  });
  pipeline(res, body, () => {});
  // Replaces the pre-response handler, so a stalled body reports TIMEOUT to its reader.
  req.removeAllListeners('timeout');
  req.setTimeout(idleTimeoutMs, () => {
    body.destroy(new OutboundUrlError('TIMEOUT', 'Upstream response stalled'));
  });

  const buffer = async () => {
    const timer = setTimeout(() => {
      body.destroy(new OutboundUrlError('TIMEOUT', 'Upstream response timed out'));
    }, Math.max(0, deadline - Date.now()));
    try {
      const chunks: Buffer[] = [];
      for await (const chunk of body) chunks.push(chunk as Buffer);
      return Buffer.concat(chunks);
    } catch (err) {
      throw toOutboundError(err);
    } finally {
      clearTimeout(timer);
    }
  };

  const text = async () => (await buffer()).toString('utf8');

  return {
    url: url.href,
    status: res.statusCode ?? 0,
    statusText: res.statusMessage ?? '',
    headers: res.headers,
    body,
    buffer,
    text,
    async json<T = unknown>() {
      const raw = await text();
      try {
        return JSON.parse(raw) as T;
      } catch {
        throw new OutboundUrlError('UPSTREAM_ERROR', 'Upstream response is not valid JSON');
      }
    },
    abort: () => req.destroy(),
  };
}
