/**
 * Episode lists and "next episode" for addon series streams, from TMDB first and
 * the addon meta as a fallback.
 * macOS reference: Services/StreamEpisodeNavigator.swift
 */

import { getFlixorCore } from '../core';
import { appLogger } from '../core/AppLogger';
import { stremioService } from './StremioService';
import type { GenericStreamParams, StremioContentIdentity } from './types';

export interface StreamEpisodeInfo {
  season: number;
  episode: number;
  title: string;
  overview?: string;
  /** Absolute image URL (TMDB still or addon thumbnail). */
  stillUrl?: string;
  airDate?: string;
  runtimeMinutes?: number;
  hasAired: boolean;
}

export interface StreamEpisodesResult {
  /** Episodes of the current season, in order. */
  seasonEpisodes: StreamEpisodeInfo[];
  /** The next aired episode: same season, else first episode of the next season. */
  next: StreamEpisodeInfo | null;
}

/** The series and episode behind stream params, parsed from `series:<baseId>:<season>:<episode>`. */
export interface StreamSeriesRef {
  baseId: string;
  season: number;
  episode: number;
  imdbId?: string;
  tmdbId?: number;
  /** Anime-database ids embedded in the base id. */
  kitsuId?: string;
  malId?: string;
}

export function parseStreamSeriesRef(
  params: Pick<GenericStreamParams, 'mediaType' | 'contentKey' | 'seasonNumber' | 'episodeNumber' | 'imdbId' | 'tmdbId'>
): StreamSeriesRef | null {
  if (params.mediaType !== 'episode') {
    return null;
  }
  const parts = params.contentKey.split(':');
  if (parts.length < 4 || parts[0] !== 'series') {
    return null;
  }
  const season = Number(parts[parts.length - 2]) || params.seasonNumber;
  const episode = Number(parts[parts.length - 1]) || params.episodeNumber;
  const baseId = parts.slice(1, -2).join(':');
  if (!season || !episode || !baseId) {
    return null;
  }

  const tmdbFromBase = baseId.startsWith('tmdb:') ? Number(baseId.slice(5)) || undefined : undefined;
  return {
    baseId,
    season,
    episode,
    imdbId: params.imdbId || (baseId.startsWith('tt') ? baseId : undefined),
    tmdbId: params.tmdbId || tmdbFromBase,
    kitsuId: baseId.startsWith('kitsu:') ? baseId.slice(6) : undefined,
    malId: baseId.startsWith('mal:') ? baseId.slice(4) : undefined,
  };
}

/** Stremio request identity for another episode of the same series. */
export function identityForEpisode(
  ref: StreamSeriesRef,
  season: number,
  episode: number
): StremioContentIdentity {
  return {
    requestType: 'series',
    baseId: ref.baseId,
    requestId: `${ref.baseId}:${season}:${episode}`,
    imdbId: ref.imdbId,
    tmdbId: ref.tmdbId,
    seasonNumber: season,
    episodeNumber: episode,
    source: 'player',
  };
}

/** `YYYY-MM-DD…` on or before today (UTC, as macOS compares it). */
function hasAired(raw: string | undefined | null, missingMeansAired: boolean): boolean {
  const day = raw?.trim().slice(0, 10);
  if (!day || !/^\d{4}-\d{2}-\d{2}$/.test(day)) {
    return missingMeansAired;
  }
  return day <= new Date().toISOString().slice(0, 10);
}

const imdbToTmdb = new Map<string, number | null>();

async function resolveTmdbId(ref: StreamSeriesRef): Promise<number | null> {
  if (ref.tmdbId) return ref.tmdbId;
  if (!ref.imdbId) return null;
  const known = imdbToTmdb.get(ref.imdbId);
  if (known !== undefined) return known;
  try {
    const found = await getFlixorCore().tmdb.findByImdbId(ref.imdbId);
    const id = found.tv_results?.[0]?.id ?? null;
    imdbToTmdb.set(ref.imdbId, id);
    return id;
  } catch {
    // Not cached: failures may be transient.
    return null;
  }
}

async function fetchSeason(tmdbId: number, season: number): Promise<StreamEpisodeInfo[]> {
  const core = getFlixorCore();
  const details = await core.tmdb.getSeasonDetails(tmdbId, season);
  return (details.episodes || [])
    .map(
      (episode): StreamEpisodeInfo => ({
        season: episode.season_number ?? season,
        episode: episode.episode_number,
        title: episode.name || `Episode ${episode.episode_number}`,
        overview: episode.overview || undefined,
        stillUrl: episode.still_path ? core.tmdb.getImageUrl(episode.still_path, 'w500') : undefined,
        airDate: episode.air_date,
        runtimeMinutes: episode.runtime,
        // TMDB lists announced episodes without a date; treat those as not aired.
        hasAired: hasAired(episode.air_date, false),
      })
    )
    .sort((left, right) => left.episode - right.episode);
}

async function tmdbEpisodes(tmdbId: number, ref: StreamSeriesRef): Promise<StreamEpisodesResult | null> {
  try {
    const current = await fetchSeason(tmdbId, ref.season);
    if (current.length === 0) {
      return null;
    }

    const nextInSeason = current.find((episode) => episode.episode > ref.episode);
    if (nextInSeason) {
      return { seasonEpisodes: current, next: nextInSeason.hasAired ? nextInSeason : null };
    }
    // Season 0 (specials) never rolls over into season 1.
    if (ref.season <= 0) {
      return { seasonEpisodes: current, next: null };
    }

    const details = await getFlixorCore().tmdb.getTVDetails(tmdbId);
    const nextSeason = (details.seasons || [])
      .filter((season) => season.season_number > ref.season && (season.episode_count ?? 0) > 0)
      .map((season) => season.season_number)
      .sort((left, right) => left - right)[0];
    if (nextSeason === undefined) {
      return { seasonEpisodes: current, next: null };
    }
    const first = (await fetchSeason(tmdbId, nextSeason))[0];
    return { seasonEpisodes: current, next: first?.hasAired ? first : null };
  } catch (error: any) {
    appLogger.warn('[StreamNext] TMDB episode lookup failed', {
      tmdbId,
      season: ref.season,
      error: error?.message || String(error),
    });
    return null;
  }
}

async function metaEpisodes(ref: StreamSeriesRef): Promise<StreamEpisodesResult | null> {
  const meta = await stremioService.getMeta('series', ref.baseId);
  const videos = meta?.videos;
  if (!videos?.length) {
    return null;
  }

  const all = videos
    .filter((video) => typeof video.season === 'number' && typeof video.episode === 'number')
    .map(
      (video): StreamEpisodeInfo => ({
        season: video.season as number,
        episode: video.episode as number,
        title: video.title || `Episode ${video.episode}`,
        overview: video.overview,
        stillUrl: video.thumbnail,
        airDate: video.released,
        hasAired: hasAired(video.released, true),
      })
    )
    .sort((left, right) => left.season - right.season || left.episode - right.episode);

  const currentIndex = all.findIndex((item) => item.season === ref.season && item.episode === ref.episode);
  if (currentIndex < 0) {
    return null;
  }

  const candidate = all[currentIndex + 1];
  // Specials don't roll over into regular seasons.
  const next = candidate?.hasAired && (ref.season > 0 || candidate.season === 0) ? candidate : null;
  return { seasonEpisodes: all.filter((item) => item.season === ref.season), next };
}

export async function loadStreamEpisodes(ref: StreamSeriesRef): Promise<StreamEpisodesResult> {
  const tmdbId = await resolveTmdbId(ref);
  const fromTmdb = tmdbId ? await tmdbEpisodes(tmdbId, ref) : null;
  if (fromTmdb) {
    return fromTmdb;
  }
  return (await metaEpisodes(ref)) ?? { seasonEpisodes: [], next: null };
}

/** Season numbers of the series, regular seasons first, specials last. Empty without TMDB. */
export async function loadStreamSeasonNumbers(ref: StreamSeriesRef): Promise<number[]> {
  const tmdbId = await resolveTmdbId(ref);
  if (!tmdbId) {
    return [];
  }
  const details = await getFlixorCore().tmdb.getTVDetails(tmdbId);
  const numbers = (details.seasons || [])
    .filter((season) => (season.episode_count ?? 0) > 0)
    .map((season) => season.season_number);
  return [
    ...numbers.filter((number) => number > 0).sort((left, right) => left - right),
    ...numbers.filter((number) => number === 0),
  ];
}

/** All episodes of one season. */
export async function loadStreamSeasonEpisodes(
  ref: StreamSeriesRef,
  season: number
): Promise<StreamEpisodeInfo[]> {
  const tmdbId = await resolveTmdbId(ref);
  return tmdbId ? fetchSeason(tmdbId, season) : [];
}

/** Resolves the show's TMDB id, for callers that need it outside episode lookups. */
export function resolveStreamTmdbId(ref: StreamSeriesRef): Promise<number | null> {
  return resolveTmdbId(ref);
}
