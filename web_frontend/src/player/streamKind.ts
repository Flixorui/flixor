import type { StreamKind } from './types';

/** The stream kind if the URL or filename says so, otherwise null. */
export function streamKindFromName(name: string): StreamKind | null {
  const path = name.split(/[?#]/)[0].toLowerCase();
  if (path.endsWith('.m3u8') || path.endsWith('.m3u')) return 'hls';
  if (path.endsWith('.mpd')) return 'dash';
  if (/\.(mp4|m4v|mov|webm|ogv|ogg|mkv|avi|ts)$/.test(path)) return 'direct';
  return null;
}

export function streamKindFromContentType(contentType: string | null): StreamKind | null {
  const type = (contentType || '').split(';')[0].trim().toLowerCase();
  if (!type) return null;
  if (type.includes('mpegurl')) return 'hls';
  if (type.includes('dash+xml')) return 'dash';
  if (type.startsWith('video/') || type.startsWith('audio/')) return 'direct';
  return null;
}

/**
 * Addon URLs often carry no extension. Reading the `Content-Type` needs CORS, and
 * when it is refused the stream is most likely a plain file, which `<video>` can
 * play without CORS. A failed probe therefore means `direct`.
 */
export async function detectStreamKind(url: string, filename?: string): Promise<StreamKind> {
  const named = streamKindFromName(url) ?? (filename ? streamKindFromName(filename) : null);
  if (named) return named;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 4000);
  try {
    // A one-byte GET, because many media hosts reject HEAD.
    const res = await fetch(url, {
      headers: { Range: 'bytes=0-0' },
      signal: controller.signal,
      credentials: 'same-origin', // Backend proxy links need the session; addon hosts must not get it.
      redirect: 'follow',
    });
    const kind = streamKindFromContentType(res.headers.get('content-type'));
    controller.abort();
    return kind ?? 'direct';
  } catch {
    return 'direct';
  } finally {
    clearTimeout(timer);
  }
}
