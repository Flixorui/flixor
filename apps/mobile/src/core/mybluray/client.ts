/**
 * MyBluray v2 HTTP client: X-API-Key auth, typed errors, one retry for
 * reads. Writes are never retried except after an expired Blu-ray.com
 * session (refused before anything changed). Same rules as macOS
 * MyBlurayClient; see MYBLURAY_PARITY.md §1.
 */

export const MYBLURAY_BASE_URL = 'https://mybluray-api.devhomelab.app';
export const MYBLURAY_PORTAL_URL = 'https://mybluray.devhomelab.app';
const TIMEOUT_MS = 35000;

export type MyBlurayErrorKind =
  | 'noKey'
  | 'invalidKey'
  | 'scopeNotAllowed'
  | 'collectionNotConnected'
  | 'sessionExpired'
  | 'notFound'
  | 'ambiguous'
  | 'unsupported'
  | 'rateLimited'
  | 'server'
  | 'network'
  | 'invalidResponse'
  | 'http';

export class MyBlurayError extends Error {
  constructor(
    public kind: MyBlurayErrorKind,
    public status?: number,
    public code?: string,
    public quotaExceeded = false,
    message?: string,
  ) {
    super(message || kind);
  }

  /** Worth serving a saved copy for (the service is down or busy). */
  get isTransient(): boolean {
    return ['rateLimited', 'server', 'network', 'invalidResponse', 'sessionExpired'].includes(this.kind)
      || (this.kind === 'http' && (this.status ?? 0) >= 500);
  }
}

export function myblurayErrorMessage(error: unknown): string {
  if (!(error instanceof MyBlurayError)) return 'Couldn’t reach MyBluray. Check your connection.';
  switch (error.kind) {
    case 'noKey': return 'Add your MyBluray key first.';
    case 'invalidKey':
      if (error.code === 'API_KEY_REVOKED') return 'This key was revoked in the portal.';
      if (error.code === 'API_KEY_EXPIRED') return 'This key has expired.';
      return 'MyBluray didn’t accept this key.';
    case 'scopeNotAllowed': return 'This key can’t use that source.';
    case 'collectionNotConnected': return 'Attach your Blu-ray.com login to this key in the MyBluray portal.';
    case 'sessionExpired': return 'Blu-ray.com signed out. Try again in a moment.';
    case 'rateLimited': return error.quotaExceeded ? 'This key has used all its requests.' : 'Too many requests. Try again in a minute.';
    case 'server':
    case 'invalidResponse': return 'MyBluray isn’t responding. Try again later.';
    case 'network': return 'Couldn’t reach MyBluray. Check your connection.';
    default: return error.message;
  }
}

/** Escapes one path segment, keeping `:` so `imdb:tt0468569` stays readable. */
export function segment(value: string): string {
  return encodeURIComponent(value).replace(/%3A/gi, ':');
}

function mapError(status: number, body: string): MyBlurayError {
  let code = '';
  let message: string | undefined;
  try {
    const parsed = JSON.parse(body);
    code = parsed?.error?.code ?? '';
    message = parsed?.error?.message;
  } catch {
    // Cloudflare answers 502s with plain text.
  }
  switch (status) {
    case 401:
      if (code.startsWith('API_KEY_')) return new MyBlurayError('invalidKey', status, code);
      if (code === 'UPSTREAM_SESSION_EXPIRED') return new MyBlurayError('sessionExpired', status, code);
      return new MyBlurayError('collectionNotConnected', status, code); // UNAUTHORIZED, KEY_CREDENTIALS_INVALID
    case 403:
      return code === 'SCOPE_NOT_ALLOWED'
        ? new MyBlurayError('scopeNotAllowed', status, code)
        : new MyBlurayError('http', status, code, false, message);
    case 404: return new MyBlurayError('notFound', status, code);
    case 409: return new MyBlurayError('ambiguous', status, code);
    case 422: return new MyBlurayError('unsupported', status, code);
    case 429: return new MyBlurayError('rateLimited', status, code, code === 'QUOTA_EXCEEDED');
    default:
      if (status >= 500) return new MyBlurayError('server', status, code);
      return new MyBlurayError('http', status, code, false, message);
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export class MyBlurayClient {
  constructor(public apiKey: string, private baseUrl = MYBLURAY_BASE_URL) {}

  private async send(method: string, path: string, query?: Record<string, string>, body?: unknown): Promise<any> {
    if (!this.apiKey) throw new MyBlurayError('noKey');
    const qs = query && Object.keys(query).length
      ? '?' + Object.entries(query).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&')
      : '';
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    let response: Response;
    try {
      response = await fetch(this.baseUrl + path + qs, {
        method,
        headers: {
          'X-API-Key': this.apiKey,
          Accept: 'application/json',
          ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        },
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      });
    } catch {
      throw new MyBlurayError('network');
    } finally {
      clearTimeout(timer);
    }
    const text = await response.text();
    if (!response.ok) throw mapError(response.status, text);
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch {
      throw new MyBlurayError('invalidResponse', response.status);
    }
  }

  /** Reads retry once on a gateway error, a dropped connection or an expired session. */
  async get(path: string, query?: Record<string, string>): Promise<any> {
    try {
      return await this.send('GET', path, query);
    } catch (error) {
      if (!(error instanceof MyBlurayError)) throw error;
      const retry = error.kind === 'sessionExpired'
        || error.kind === 'network'
        || (error.kind === 'server' && [502, 503, 504].includes(error.status ?? 0));
      if (!retry) throw error;
      if (error.kind !== 'sessionExpired') await sleep(600);
      return this.send('GET', path, query);
    }
  }

  /** Writes are not retried: a write may already have been applied. */
  async write(method: 'POST' | 'PATCH' | 'DELETE', path: string, body?: unknown): Promise<any> {
    try {
      return await this.send(method, path, undefined, body ?? (method === 'DELETE' ? undefined : {}));
    } catch (error) {
      if (error instanceof MyBlurayError && error.kind === 'sessionExpired') {
        return this.send(method, path, undefined, body ?? (method === 'DELETE' ? undefined : {}));
      }
      throw error;
    }
  }
}
