/**
 * Requests to addons: straight from the browser first, so debrid keys stay off the
 * server and requests spread across user IPs, with the backend as the fallback.
 * Error messages never include the URL.
 */
import { API_BASE_URL } from '@/services/api';

const STREMIO_API = `${API_BASE_URL.replace(/\/$/, '')}/stremio`;
const ROUTE_STORAGE_KEY = 'flixor.stremio.proxiedOrigins';

export class AddonRequestError extends Error {}

function proxiedOrigins(): Set<string> {
  try {
    return new Set(JSON.parse(sessionStorage.getItem(ROUTE_STORAGE_KEY) || '[]'));
  } catch {
    return new Set();
  }
}

function rememberProxied(origin: string): void {
  const origins = proxiedOrigins().add(origin);
  try {
    sessionStorage.setItem(ROUTE_STORAGE_KEY, JSON.stringify([...origins]));
  } catch {
    // Only costs one failed direct request next time.
  }
}

/** An https page cannot call an http addon, however the addon sets CORS. */
export function isMixedContent(url: string): boolean {
  return (
    typeof location !== 'undefined' && location.protocol === 'https:' && /^http:/i.test(url)
  );
}

function withTimeout(signal: AbortSignal | undefined, timeoutMs: number) {
  const controller = new AbortController();
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeoutMs);
  const onAbort = () => controller.abort();
  if (signal?.aborted) controller.abort();
  signal?.addEventListener('abort', onAbort, { once: true });
  return {
    signal: controller.signal,
    didTimeOut: () => timedOut,
    done() {
      clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort);
    },
  };
}

function isAbort(err: unknown): boolean {
  return (err as Error)?.name === 'AbortError';
}

async function proxyError(response: Response, fallback: string): Promise<AddonRequestError> {
  try {
    const body = await response.json();
    if (typeof body?.message === 'string' && body.message) return new AddonRequestError(body.message);
  } catch {
    // Not JSON, so use the fallback.
  }
  return new AddonRequestError(fallback);
}

function postToBackend(path: string, body: unknown, signal: AbortSignal): Promise<Response> {
  return fetch(`${STREMIO_API}${path}`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal,
  });
}

interface DirectFirstOptions<T> {
  url: string;
  signal?: AbortSignal;
  timeoutMs: number;
  timeoutMessage: string;
  networkMessage: string;
  direct: (signal: AbortSignal) => Promise<T>;
  viaBackend: (signal: AbortSignal) => Promise<T>;
}

/**
 * Runs `direct`, and on a network-level failure runs `viaBackend`. A browser reports a
 * CORS failure and a network failure identically, so both get one fallback attempt.
 */
async function directFirst<T>(options: DirectFirstOptions<T>): Promise<T> {
  const { url, direct, viaBackend, timeoutMs, timeoutMessage, networkMessage } = options;
  const origin = new URL(url).origin;
  const timeout = withTimeout(options.signal, timeoutMs);
  try {
    if (!isMixedContent(url) && !proxiedOrigins().has(origin)) {
      try {
        return await direct(timeout.signal);
      } catch (err) {
        if (!(err instanceof TypeError)) throw err;
      }
    }
    const result = await viaBackend(timeout.signal);
    rememberProxied(origin);
    return result;
  } catch (err) {
    if (isAbort(err)) {
      if (timeout.didTimeOut()) throw new AddonRequestError(timeoutMessage);
      throw err;
    }
    if (err instanceof AddonRequestError) throw err;
    throw new AddonRequestError(networkMessage);
  } finally {
    timeout.done();
  }
}

/** Fetches addon JSON. Pass the signal through so closed views stop waiting. */
export function fetchAddonJson<T>(
  url: string,
  options: { signal?: AbortSignal; timeoutMs?: number } = {},
): Promise<T> {
  const timeoutMs = options.timeoutMs ?? 60_000;
  return directFirst<T>({
    url,
    signal: options.signal,
    timeoutMs,
    timeoutMessage: `The addon did not answer within ${Math.round(timeoutMs / 1000)} seconds`,
    networkMessage: 'Could not reach the addon',
    async direct(signal) {
      const response = await fetch(url, { headers: { Accept: 'application/json' }, signal });
      if (!response.ok) throw new AddonRequestError(`The addon responded with status ${response.status}`);
      try {
        return (await response.json()) as T;
      } catch (err) {
        if (isAbort(err)) throw err;
        throw new AddonRequestError('The addon sent an invalid response');
      }
    },
    async viaBackend(signal) {
      const response = await postToBackend('/addon', { url }, signal);
      if (!response.ok) throw await proxyError(response, 'Could not reach the addon');
      return (await response.json()) as T;
    },
  });
}

/** Fetches a subtitle file as text, for converting to WebVTT. */
export function fetchSubtitleFile(url: string, signal?: AbortSignal): Promise<string> {
  return directFirst<string>({
    url,
    signal,
    timeoutMs: 15_000,
    timeoutMessage: 'The subtitle host did not answer in time',
    networkMessage: 'Could not download the subtitles',
    async direct(requestSignal) {
      const response = await fetch(url, { signal: requestSignal });
      if (!response.ok) throw new AddonRequestError(`The subtitle host responded with status ${response.status}`);
      return response.text();
    },
    async viaBackend(requestSignal) {
      const response = await postToBackend('/subtitle', { url }, requestSignal);
      if (!response.ok) throw await proxyError(response, 'Could not download the subtitles');
      return response.text();
    },
  });
}

/** Asks the backend for a media proxy URL for a stream an addon offered. */
export async function requestStreamProxyUrl(
  body: {
    manifestUrl: string;
    type: string;
    id: string;
    streamIndex: number;
    url: string;
    filename?: string;
  },
  signal?: AbortSignal,
): Promise<string> {
  const timeout = withTimeout(signal, 75_000);
  try {
    const response = await postToBackend('/stream/token', body, timeout.signal);
    if (!response.ok) throw await proxyError(response, 'The source could not be prepared');
    const { token } = (await response.json()) as { token: string };
    return `${STREMIO_API}/stream/${token}`;
  } catch (err) {
    if (isAbort(err) && timeout.didTimeOut()) throw new AddonRequestError('The source took too long to prepare');
    if (isAbort(err) || err instanceof AddonRequestError) throw err;
    throw new AddonRequestError('The source could not be prepared');
  } finally {
    timeout.done();
  }
}

/** TMDB id for an IMDb id, or null when TMDB has no match. Throws on a failed lookup. */
export async function lookupTmdbId(
  imdbId: string,
  type: string,
  signal?: AbortSignal,
): Promise<number | null> {
  const response = await fetch(
    `${STREMIO_API}/tmdb-id/${encodeURIComponent(imdbId)}?type=${encodeURIComponent(type)}`,
    { credentials: 'include', signal },
  );
  if (!response.ok) throw new AddonRequestError('TMDB lookup failed');
  const { tmdbId } = (await response.json()) as { tmdbId: number | null };
  return tmdbId;
}
