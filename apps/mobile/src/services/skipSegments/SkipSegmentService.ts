/**
 * Looks up community skip segments for items without Plex markers. Sources in
 * priority order: IntroDB, AniSkip, Anime-Skip. Results are merged per type (first
 * provider wins) and cached per title for the session. Every failure degrades to
 * "no segments".
 * macOS reference: Services/SkipSegments/SkipSegmentService.swift
 */

import { appLogger } from '../../core/AppLogger';
import { RateLimitedError } from './http';
import {
  animeIdsForShow,
  animeIdsFromSource,
  fetchAniSkip,
  fetchAnimeSkipSegments,
  fetchAnimeSkipShowIds,
  fetchIntroDbEpisode,
  fetchIntroDbMovie,
  type AnimeIds,
} from './providers';
import {
  isSkipLookupPossible,
  isValidSegment,
  skipSegmentCacheKey,
  type SkipSegment,
  type SkipSegmentProvider,
  type SkipSegmentRequest,
  type SkipSegmentType,
} from './types';

const FOUND_TTL_MS = 6 * 60 * 60 * 1000;
const EMPTY_TTL_MS = 30 * 60 * 1000;
const DEFAULT_BACKOFF_MS = 60 * 1000;
const MAX_BACKOFF_MS = 15 * 60 * 1000;

/** One segment per type, first list wins. Credits never jump over a post-credits scene. */
export function mergeSkipSegments(lists: SkipSegment[][]): SkipSegment[] {
  const chosen = new Map<SkipSegmentType, SkipSegment>();
  for (const list of lists) {
    for (const segment of list) {
      if (isValidSegment(segment) && !chosen.has(segment.type)) {
        chosen.set(segment.type, segment);
      }
    }
  }

  const credits = chosen.get('credits');
  const scene = chosen.get('postcredits');
  if (credits && scene && scene.start >= credits.start && scene.start < (credits.end ?? Infinity)) {
    const trimmed: SkipSegment = { ...credits, end: scene.start };
    if (isValidSegment(trimmed)) {
      chosen.set('credits', trimmed);
    } else {
      chosen.delete('credits');
    }
  }
  return Array.from(chosen.values()).sort((left, right) => left.start - right.start);
}

class SkipSegmentService {
  private cache = new Map<string, { segments: SkipSegment[]; expiresAt: number }>();
  private inFlight = new Map<string, Promise<SkipSegment[]>>();
  /** Null value means known not to be anime. */
  private animeIds = new Map<string, AnimeIds | null>();
  private animeSkipShows = new Map<string, string[]>();
  private blockedUntil = new Map<SkipSegmentProvider, number>();

  async segments(request: SkipSegmentRequest): Promise<SkipSegment[]> {
    if (!isSkipLookupPossible(request)) {
      return [];
    }
    const key = skipSegmentCacheKey(request);
    const cached = this.cache.get(key);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.segments;
    }
    const running = this.inFlight.get(key);
    if (running) {
      return running;
    }

    const task = this.fetch(request)
      .catch(() => [] as SkipSegment[])
      .then((segments) => {
        this.inFlight.delete(key);
        this.cache.set(key, {
          segments,
          expiresAt: Date.now() + (segments.length > 0 ? FOUND_TTL_MS : EMPTY_TTL_MS),
        });
        return segments;
      });
    this.inFlight.set(key, task);
    return task;
  }

  private async fetch(request: SkipSegmentRequest): Promise<SkipSegment[]> {
    if (request.isMovie) {
      const imdbId = request.imdbId;
      if (!imdbId) return [];
      return mergeSkipSegments([await this.guarded('introdb', () => fetchIntroDbMovie(imdbId))]);
    }

    const episode = request.episode;
    if (!episode) return [];

    const introDb = this.fetchIntroDb(request);
    const ids = await this.resolveAnimeIds(request);
    const [fromIntroDb, fromAniSkip, fromAnimeSkip] = await Promise.all([
      introDb,
      ids?.malId ? this.guarded('aniskip', () => fetchAniSkip(ids.malId as string, episode)) : Promise.resolve([]),
      this.fetchAnimeSkip(ids?.anilistId, episode, request.animeSkipClientId),
    ]);
    return mergeSkipSegments([fromIntroDb, fromAniSkip, fromAnimeSkip]);
  }

  private fetchIntroDb(request: SkipSegmentRequest): Promise<SkipSegment[]> {
    const { imdbId, season, episode, kitsuId, malId } = request;
    if (!imdbId || season === undefined || !episode || kitsuId || malId) {
      return Promise.resolve([]);
    }
    return this.guarded('introdb', () => fetchIntroDbEpisode(imdbId, season, episode));
  }

  private fetchAnimeSkip(
    anilistId: string | undefined,
    episode: number,
    rawClientId: string
  ): Promise<SkipSegment[]> {
    const clientId = rawClientId.trim();
    if (!anilistId || !clientId) {
      return Promise.resolve([]);
    }
    return this.guarded('animeskip', async () => {
      let showIds = this.animeSkipShows.get(anilistId);
      if (!showIds) {
        showIds = await fetchAnimeSkipShowIds(clientId, anilistId);
        this.animeSkipShows.set(anilistId, showIds);
      }
      for (const showId of showIds.slice(0, 3)) {
        const segments = await fetchAnimeSkipSegments(clientId, showId, episode);
        if (segments.length > 0) return segments;
      }
      return [];
    });
  }

  private async resolveAnimeIds(request: SkipSegmentRequest): Promise<AnimeIds | null> {
    const key = request.malId
      ? `mal:${request.malId}`
      : request.kitsuId
        ? `kitsu:${request.kitsuId}`
        : `show:${request.tmdbId ?? request.imdbId ?? '?'}:${request.season ?? 0}`;
    const known = this.animeIds.get(key);
    if (known !== undefined) {
      return known;
    }

    try {
      let ids: AnimeIds | null = null;
      if (request.malId) {
        // ARM adds the AniList id, but the MAL id alone is enough for AniSkip.
        const mapped = await animeIdsFromSource('myanimelist', request.malId).catch(() => null);
        ids = mapped ?? { malId: request.malId };
      } else if (request.kitsuId) {
        ids = await animeIdsFromSource('kitsu', request.kitsuId);
      } else if (request.season !== undefined) {
        ids = await animeIdsForShow(request.tmdbId, request.imdbId, request.season);
      }
      this.animeIds.set(key, ids);
      return ids;
    } catch {
      // Transient failure: not cached, so the next episode tries again.
      return null;
    }
  }

  /** Runs one provider call; maps errors, including 429 back-off, to an empty result. */
  private async guarded(
    provider: SkipSegmentProvider,
    operation: () => Promise<SkipSegment[]>
  ): Promise<SkipSegment[]> {
    if ((this.blockedUntil.get(provider) ?? 0) > Date.now()) {
      return [];
    }
    try {
      return await operation();
    } catch (error: any) {
      if (error instanceof RateLimitedError) {
        const wait = Math.min(error.retryAfterMs ?? DEFAULT_BACKOFF_MS, MAX_BACKOFF_MS);
        this.blockedUntil.set(provider, Date.now() + Math.max(0, wait));
        appLogger.warn('[SkipSegments] Rate limited', { provider });
      }
      return [];
    }
  }
}

export const skipSegmentService = new SkipSegmentService();
