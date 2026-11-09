/** Validation of the addon URLs the proxy is asked to fetch. */
import { AppError } from '../../middleware/errorHandler';

const ADDON_RESOURCE_PATH = /(?:^|\/)manifest\.json$|\/(?:stream|subtitles|catalog|meta)\/[^/]+\/.+\.json$/i;

/** The proxy only relays the Stremio addon protocol, not arbitrary JSON endpoints. */
export function assertAddonResourceUrl(input: unknown): string {
  if (typeof input !== 'string' || !input) throw new AppError('Addon URL is required', 400);
  let url: URL;
  try {
    url = new URL(input);
  } catch {
    throw new AppError('Addon URL is not valid', 400);
  }
  if (!ADDON_RESOURCE_PATH.test(url.pathname)) {
    throw new AppError('Not a Stremio addon URL', 400);
  }
  return url.href;
}

/** Builds `<addon base><resource path>`, keeping any query string the manifest URL has. */
export function buildAddonResourceUrl(manifestUrl: string, resourcePath: string): string {
  let url: URL;
  try {
    url = new URL(manifestUrl);
  } catch {
    throw new AppError('Addon URL is not valid', 400);
  }
  url.pathname = url.pathname.replace(/\/manifest\.json$/i, '').replace(/\/$/, '') + resourcePath;
  return url.href;
}

interface AddonStream {
  url?: unknown;
  behaviorHints?: {
    filename?: unknown;
    proxyHeaders?: { request?: unknown };
  };
}

/**
 * Finds the stream the client asked for in the addon's own response. Some addons sign
 * their URLs per request, so an exact match can fail on a stream that is still offered.
 * The position is then used, unless the filename shows that it is a different file.
 */
export function findAddonStream(
  streams: unknown,
  url: unknown,
  streamIndex: unknown,
  filename: unknown,
): (AddonStream & { url: string }) | undefined {
  if (!Array.isArray(streams)) return undefined;
  const typed = streams as AddonStream[];
  const hasUrl = (stream: AddonStream | undefined): stream is AddonStream & { url: string } =>
    typeof stream?.url === 'string';

  const exact = typed.find((stream) => hasUrl(stream) && stream.url === url);
  if (hasUrl(exact)) return exact;

  const positional = typeof streamIndex === 'number' ? typed[streamIndex] : undefined;
  if (!hasUrl(positional)) return undefined;
  const theirs = positional.behaviorHints?.filename;
  if (typeof theirs === 'string' && typeof filename === 'string' && theirs !== filename) {
    return undefined;
  }
  return positional;
}

const FORBIDDEN_REQUEST_HEADERS = new Set([
  'host', 'connection', 'content-length', 'transfer-encoding', 'te', 'trailer', 'upgrade',
  'keep-alive', 'proxy-authorization', 'proxy-connection',
]);

/** Keeps the headers an addon may set on the upstream media request. */
export function sanitizeRequestHeaders(input: unknown): Record<string, string> | undefined {
  if (!input || typeof input !== 'object') return undefined;
  const headers: Record<string, string> = {};
  for (const [name, value] of Object.entries(input as Record<string, unknown>)) {
    if (typeof value === 'string' && !FORBIDDEN_REQUEST_HEADERS.has(name.toLowerCase())) {
      headers[name] = value;
    }
  }
  return Object.keys(headers).length > 0 ? headers : undefined;
}
