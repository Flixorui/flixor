/**
 * Provider-neutral skip segments and the request used to look them up.
 * macOS reference: Services/SkipSegments/SkipSegmentModels.swift
 */

/** `postcredits` is content: it is never skipped, it only moves the credits skip target and next-episode trigger. */
export type SkipSegmentType = 'intro' | 'recap' | 'credits' | 'preview' | 'postcredits';

export type SkipSegmentProvider = 'introdb' | 'aniskip' | 'animeskip';

export interface SkipSegment {
  type: SkipSegmentType;
  /** Seconds from the start of the file. */
  start: number;
  /** Seconds; null when the segment runs to the end of the file. */
  end: number | null;
  provider: SkipSegmentProvider;
}

export interface SkipSegmentRequest {
  /** IMDb id of the movie, or of the SHOW for episodes. */
  imdbId?: string;
  /** TMDB id of the movie, or of the SHOW for episodes. */
  tmdbId?: number;
  isMovie: boolean;
  season?: number;
  episode?: number;
  kitsuId?: string;
  malId?: string;
  /** Anime-Skip is not queried when empty. */
  animeSkipClientId: string;
}

export function isValidSegment(segment: SkipSegment): boolean {
  if (!Number.isFinite(segment.start) || segment.start < 0) return false;
  return segment.end === null || (Number.isFinite(segment.end) && segment.end > segment.start);
}

export function skipSegmentCacheKey(request: SkipSegmentRequest): string {
  if (request.isMovie) {
    return `movie:${request.imdbId ?? (request.tmdbId ? `tmdb${request.tmdbId}` : '?')}`;
  }
  const base = request.malId
    ? `mal${request.malId}`
    : request.kitsuId
      ? `kitsu${request.kitsuId}`
      : request.imdbId ?? (request.tmdbId ? `tmdb${request.tmdbId}` : '?');
  return `episode:${base}:${request.season ?? 0}:${request.episode ?? 0}`;
}

export function isSkipLookupPossible(request: SkipSegmentRequest): boolean {
  if (request.isMovie) return Boolean(request.imdbId);
  if (!request.episode || request.episode <= 0) return false;
  if (request.kitsuId || request.malId) return true;
  return request.season !== undefined && Boolean(request.imdbId || request.tmdbId);
}
