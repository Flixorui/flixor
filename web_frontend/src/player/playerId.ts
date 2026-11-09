import type { StremioContentIdentity } from '@/stremio';

export type PlayerTarget =
  | { kind: 'plex'; ratingKey: string }
  | { kind: 'stream'; requestId: string; identity: StremioContentIdentity }
  | { kind: 'unsupported'; id: string };

/** Identity from a `stream:` request id: `tt1:1:2` is an episode, `tt1` a movie. */
export function identityFromRequestId(requestId: string): StremioContentIdentity | null {
  if (!requestId) return null;
  const parts = requestId.split(':');
  const season = Number(parts[parts.length - 2]);
  const episode = Number(parts[parts.length - 1]);
  const isEpisode = parts.length >= 3 && Number.isInteger(season) && Number.isInteger(episode);
  const baseId = isEpisode ? parts.slice(0, -2).join(':') : requestId;
  if (!baseId) return null;

  const tmdbMatch = /^tmdb:(\d+)$/.exec(baseId);
  return {
    requestType: isEpisode ? 'series' : 'movie',
    baseId,
    requestId,
    imdbId: baseId.startsWith('tt') ? baseId : undefined,
    tmdbId: tmdbMatch ? Number(tmdbMatch[1]) : undefined,
    seasonNumber: isEpisode ? season : undefined,
    episodeNumber: isEpisode ? episode : undefined,
  };
}

export function parsePlayerId(id: string): PlayerTarget {
  if (id.startsWith('plex:') && id.length > 5) return { kind: 'plex', ratingKey: id.slice(5) };
  if (id.startsWith('stream:')) {
    const requestId = id.slice(7);
    const identity = identityFromRequestId(requestId);
    if (identity) return { kind: 'stream', requestId, identity };
  }
  return { kind: 'unsupported', id };
}

/** Route id for an addon stream. Pass a `StreamPlayerState` as router state. */
export function streamPlayerId(identity: StremioContentIdentity): string {
  return `stream:${identity.requestId}`;
}

export function playerPath(id: string): string {
  return `/player/${encodeURIComponent(id)}`;
}

export function detailsPath(id: string): string {
  return `/details/${encodeURIComponent(id)}`;
}
