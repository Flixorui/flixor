/** HLS helpers for the addon media proxy. */

const URI_ATTRIBUTE = /URI="([^"]*)"/g;

export function isHlsResponse(contentType: string | undefined, url: string): boolean {
  if (contentType && /mpegurl/i.test(contentType)) return true;
  try {
    return /\.m3u8$/i.test(new URL(url).pathname);
  } catch {
    return false;
  }
}

/**
 * Points every URI in a playlist back at the proxy. `wrap` gets the absolute upstream
 * URL and returns the replacement. Non-http URIs (`data:`, `skd:`) are left alone.
 */
export function rewriteHlsPlaylist(
  playlist: string,
  playlistUrl: string,
  wrap: (absoluteUrl: string) => string,
): string {
  const rewrite = (uri: string) => {
    try {
      const absolute = new URL(uri, playlistUrl);
      return absolute.protocol === 'http:' || absolute.protocol === 'https:'
        ? wrap(absolute.href)
        : uri;
    } catch {
      return uri;
    }
  };

  return playlist
    .split(/\r?\n/)
    .map((line) => {
      const trimmed = line.trim();
      if (!trimmed) return line;
      if (trimmed.startsWith('#')) {
        return line.replace(URI_ATTRIBUTE, (_match, uri: string) => `URI="${rewrite(uri)}"`);
      }
      return rewrite(trimmed);
    })
    .join('\n');
}
