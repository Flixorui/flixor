/**
 * Continue Watching: the Trakt list with next-up cards, plus what the row needs to
 * combine it with Plex or this device's history.
 * macOS reference: Services/TraktContinueWatchingService.swift, Models/HomeRowModels.swift
 */

import { getVersionString, type ContinueWatchingResult, type PlexMediaItem } from '@flixor/core';
import { getFlixorCore } from './index';
import { getContinueWatchingImageUrl, getPlexImageUrl, getTmdbBackdropWithTitle } from './HomeData';
import { extractImdbIdFromGuids, extractTmdbIdFromGuids } from './DetailsData';
import { localLibrary } from './LocalLibrary';
import { getProfileKey } from './ProfileStorage';
import type { AppSettings, ContinueWatchingSort, ContinueWatchingSource } from './SettingsData';
import type { WatchStateTarget } from './WatchState';
import { stremioResumeStore } from '../stremio/StremioResumeStore';

export type ContinueWatchingEntrySource = 'plex' | 'trakt' | 'local';

/** One card in the Continue Watching row, whichever service it came from. */
export interface ContinueWatchingEntry {
  /** Unique within the row. Also the key for Trakt dismissals. */
  key: string;
  source: ContinueWatchingEntrySource;
  mediaType: 'movie' | 'episode';
  /** Movie title, or the show title for episodes. */
  title: string;
  episodeTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  year?: number;
  positionMs?: number;
  durationMs?: number;
  /** 0-100. */
  progress: number;
  /** An episode the user hasn't started. */
  isUpNext: boolean;
  image?: string;
  backdrop?: string;
  /** Movie TMDB id, or the show's for episodes. */
  tmdbId?: number;
  imdbId?: string;
  plexRatingKey?: string;
  /** Resume key, for entries from this device's history. */
  contentKey?: string;
  /** Epoch ms. Unset for Plex, which reports no activity time. */
  lastActivity?: number;
  plex?: PlexMediaItem;
  /** Edition or resolution, when the item exists in several versions. */
  versionLabel?: string;
}

const CACHE_LIFETIME_MS = 60_000;
/** Shows watched longer ago than this don't get a next-episode card. */
const NEXT_UP_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;
const MAX_NEXT_UP_SHOWS = 20;
const MAX_ENTRIES = 30;
const CONCURRENCY = 6;
const HISTORY_PAGE_SIZE = 100;

interface Candidate {
  isMovie: boolean;
  tmdbId: number;
  imdbId?: string;
  title: string;
  year?: number;
  episodeTitle?: string;
  season?: number;
  episode?: number;
  runtimeMinutes?: number;
  progress?: number;
  activity: number;
}

async function withLimit<T, R>(items: T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = [];
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const index = next++;
      results[index] = await fn(items[index]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return results;
}

function parseDate(value?: string | null): number | undefined {
  if (!value) return undefined;
  const time = new Date(value).getTime();
  return Number.isNaN(time) ? undefined : time;
}

function candidateFromPlayback(playback: any): Candidate | null {
  // Trakt counts 80%+ as watched; ignore accidental starts and finished items.
  if (!(playback.progress >= 1 && playback.progress < 95)) return null;
  const activity = parseDate(playback.paused_at);
  if (activity === undefined) return null;

  if (playback.type === 'movie' && playback.movie) {
    const { movie } = playback;
    if (movie.ids?.tmdb == null) return null;
    return {
      isMovie: true,
      tmdbId: movie.ids.tmdb,
      imdbId: movie.ids.imdb ?? undefined,
      title: movie.title,
      year: movie.year ?? undefined,
      runtimeMinutes: movie.runtime ?? undefined,
      progress: playback.progress,
      activity,
    };
  }
  if (playback.type === 'episode' && playback.show && playback.episode) {
    const { show, episode } = playback;
    if (show.ids?.tmdb == null) return null;
    return {
      isMovie: false,
      tmdbId: show.ids.tmdb,
      imdbId: show.ids.imdb ?? undefined,
      title: show.title,
      year: show.year ?? undefined,
      episodeTitle: episode.title ?? undefined,
      season: episode.season,
      episode: episode.number,
      runtimeMinutes: episode.runtime ?? show.runtime ?? undefined,
      progress: playback.progress,
      activity,
    };
  }
  return null;
}

async function nextUpCandidates(): Promise<Candidate[]> {
  const trakt = getFlixorCore().trakt;
  const history = await trakt.getHistory('shows', 1, HISTORY_PAGE_SIZE);

  const cutoff = Date.now() - NEXT_UP_WINDOW_MS;
  const newestByShow = new Map<number, { show: any; activity: number }>();
  for (const item of history as any[]) {
    const tmdbId: number | undefined = item.show?.ids?.tmdb;
    const activity = parseDate(item.watched_at);
    if (tmdbId == null || activity === undefined || activity <= cutoff) continue;
    const current = newestByShow.get(tmdbId);
    if (!current || activity > current.activity) newestByShow.set(tmdbId, { show: item.show, activity });
  }

  const shows = [...newestByShow.values()]
    .sort((a, b) => b.activity - a.activity)
    .slice(0, MAX_NEXT_UP_SHOWS);

  const candidates = await withLimit(shows, CONCURRENCY, async ({ show, activity }): Promise<Candidate | null> => {
    const showId = show.ids?.trakt ?? show.ids?.slug;
    if (showId == null) return null;
    try {
      const progress = await trakt.getShowProgress(showId);
      const episode: any = progress.next_episode;
      if (!episode) return null;
      return {
        isMovie: false,
        tmdbId: show.ids.tmdb,
        imdbId: show.ids.imdb ?? undefined,
        title: show.title,
        year: show.year ?? undefined,
        episodeTitle: episode.title ?? undefined,
        season: episode.season,
        episode: episode.number,
        runtimeMinutes: episode.runtime ?? show.runtime ?? undefined,
        activity,
      };
    } catch {
      return null;
    }
  });
  return candidates.filter((candidate): candidate is Candidate => candidate !== null);
}

function rowKeyFor(isMovie: boolean, tmdbId: number, season?: number, episode?: number): string {
  return isMovie ? `tmdb:movie:${tmdbId}` : `tmdb:tv:${tmdbId}:${season ?? -1}:${episode ?? -1}`;
}

async function toEntry(candidate: Candidate): Promise<ContinueWatchingEntry> {
  const core = getFlixorCore();
  let image: string | undefined;
  let backdrop: string | undefined;
  try {
    const details = candidate.isMovie
      ? await core.tmdb.getMovieDetails(candidate.tmdbId)
      : await core.tmdb.getTVDetails(candidate.tmdbId);
    image = details.poster_path ? core.tmdb.getPosterUrl(details.poster_path, 'w342') : undefined;
    // Matches the Plex cards, which prefer a backdrop with the title in it.
    backdrop = (await getTmdbBackdropWithTitle(candidate.tmdbId, candidate.isMovie ? 'movie' : 'tv')) || undefined;
    if (!backdrop && details.backdrop_path) backdrop = core.tmdb.getBackdropUrl(details.backdrop_path, 'w780');
  } catch {
    // The card still shows its title without artwork.
  }

  const durationMs = candidate.runtimeMinutes && candidate.runtimeMinutes > 0 ? candidate.runtimeMinutes * 60_000 : undefined;
  const positionMs =
    candidate.progress !== undefined && durationMs ? Math.round((durationMs * candidate.progress) / 100) : undefined;

  return {
    key: rowKeyFor(candidate.isMovie, candidate.tmdbId, candidate.season, candidate.episode),
    source: 'trakt',
    mediaType: candidate.isMovie ? 'movie' : 'episode',
    title: candidate.title,
    episodeTitle: candidate.episodeTitle,
    seasonNumber: candidate.season,
    episodeNumber: candidate.episode,
    year: candidate.year,
    positionMs,
    durationMs,
    progress: candidate.progress ?? 0,
    isUpNext: !candidate.isMovie && candidate.progress === undefined,
    image,
    backdrop,
    tmdbId: candidate.tmdbId,
    imdbId: candidate.imdbId,
    lastActivity: candidate.activity,
  };
}

async function fetchEntries(): Promise<ContinueWatchingEntry[]> {
  const trakt = getFlixorCore().trakt;
  const paused = await trakt.getPlaybackProgress();
  const candidates = paused
    .map(candidateFromPlayback)
    .filter((candidate): candidate is Candidate => candidate !== null);

  // Next episodes are a bonus: losing them shouldn't lose the paused items.
  try {
    candidates.push(...(await nextUpCandidates()));
  } catch (e) {
    console.log('[TraktContinueWatching] next-up fetch failed:', e);
  }

  const newest = new Map<string, Candidate>();
  for (const candidate of candidates) {
    const key = `${candidate.isMovie ? 'movie' : 'tv'}:${candidate.tmdbId}`;
    const current = newest.get(key);
    if (!current || candidate.activity > current.activity) newest.set(key, candidate);
  }

  const chosen = [...newest.values()].sort((a, b) => b.activity - a.activity).slice(0, MAX_ENTRIES);
  return withLimit(chosen, CONCURRENCY, toEntry);
}

let cache: { entries: ContinueWatchingEntry[]; fetchedAt: number; profile: string } | null = null;
let pending: { promise: Promise<ContinueWatchingEntry[]>; profile: string } | null = null;

/** Throws when Trakt can't be reached. Results are cached briefly because Home refreshes often. */
export async function fetchTraktContinueWatchingEntries(options?: { force?: boolean }): Promise<ContinueWatchingEntry[]> {
  if (!getFlixorCore().isTraktAuthenticated) return [];
  const profile = getProfileKey('traktContinueWatching');
  if (!options?.force && cache && cache.profile === profile && Date.now() - cache.fetchedAt < CACHE_LIFETIME_MS) {
    return cache.entries;
  }
  if (pending && pending.profile === profile) return pending.promise;

  const promise = fetchEntries()
    .then((entries) => {
      cache = { entries, fetchedAt: Date.now(), profile };
      return entries;
    })
    .finally(() => {
      if (pending?.promise === promise) pending = null;
    });
  pending = { promise, profile };
  return promise;
}

/** Hands a Trakt resume point to addon playback, unless local progress is newer. */
export async function seedTraktResumePoint(entry: ContinueWatchingEntry): Promise<void> {
  if (entry.source !== 'trakt' || !entry.positionMs || !entry.durationMs || !entry.lastActivity) return;
  const bases = [...(entry.imdbId ? [entry.imdbId] : []), `tmdb:${entry.tmdbId}`];
  for (const base of bases) {
    const contentKey =
      entry.mediaType === 'movie'
        ? `movie:${base}`
        : `series:${base}:${entry.seasonNumber ?? 0}:${entry.episodeNumber ?? 0}`;
    const existing = await stremioResumeStore.get(contentKey);
    if (existing && existing.updatedAt >= entry.lastActivity) continue;
    await stremioResumeStore.save({
      contentKey,
      positionMs: entry.positionMs,
      durationMs: entry.durationMs,
      updatedAt: entry.lastActivity,
    });
  }
}

// ---- Other sources ----

/** Entries from this device's history. Items with no TMDB id can't open a details page. */
export async function loadLocalContinueWatchingEntries(): Promise<ContinueWatchingEntry[]> {
  const history = await localLibrary.watchHistory();
  const entries: ContinueWatchingEntry[] = [];
  for (const entry of history) {
    if (entry.tmdbId == null) continue;
    const isMovie = entry.mediaType === 'movie';
    entries.push({
      key: rowKeyFor(isMovie, entry.tmdbId, entry.seasonNumber, entry.episodeNumber),
      source: 'local',
      mediaType: entry.mediaType,
      title: entry.title,
      episodeTitle: entry.episodeTitle,
      seasonNumber: entry.seasonNumber,
      episodeNumber: entry.episodeNumber,
      positionMs: entry.positionMs,
      durationMs: entry.durationMs,
      progress: entry.durationMs > 0 ? Math.min((entry.positionMs / entry.durationMs) * 100, 100) : 0,
      isUpNext: false,
      image: entry.posterUrl,
      backdrop: entry.backdropUrl,
      tmdbId: entry.tmdbId,
      imdbId: entry.imdbId,
      contentKey: entry.contentKey,
      lastActivity: entry.updatedAt,
    });
  }
  return entries;
}

function plexLandscapeImage(item: PlexMediaItem, backdrops: Record<string, string>): string | undefined {
  if (item.ratingKey && backdrops[item.ratingKey]) return backdrops[item.ratingKey];
  const path = item.type === 'episode' ? item.grandparentArt || item.art || item.thumb : item.art || item.thumb;
  return path ? getPlexImageUrl({ ...item, thumb: path } as PlexMediaItem, 600) : undefined;
}

export function mapPlexContinueWatching(
  result: ContinueWatchingResult,
  backdrops: Record<string, string>
): ContinueWatchingEntry[] {
  return result.items.map((item) => {
    const isEpisode = item.type === 'episode';
    const guids = item.Guid || [];
    const tmdb = !isEpisode ? extractTmdbIdFromGuids(guids) : null;
    const progress = item.viewOffset && item.duration ? Math.min((item.viewOffset / item.duration) * 100, 100) : 0;
    return {
      key: `plex:${item.ratingKey}`,
      source: 'plex' as const,
      mediaType: isEpisode ? ('episode' as const) : ('movie' as const),
      title: (isEpisode ? item.grandparentTitle || item.title : item.title) || 'Untitled',
      episodeTitle: isEpisode ? item.title : undefined,
      seasonNumber: isEpisode ? item.parentIndex : undefined,
      episodeNumber: isEpisode ? item.index : undefined,
      year: item.year,
      positionMs: item.viewOffset,
      durationMs: item.duration,
      progress,
      isUpNext: isEpisode && (item.viewOffset ?? 0) <= 0,
      image: getContinueWatchingImageUrl(item, 300) || undefined,
      backdrop: plexLandscapeImage(item, backdrops),
      tmdbId: tmdb ? Number(tmdb) : undefined,
      imdbId: !isEpisode ? extractImdbIdFromGuids(guids) || undefined : undefined,
      plexRatingKey: String(item.ratingKey),
      plex: item,
      versionLabel: result.itemsWithMultipleVersions.has(item.ratingKey)
        ? getVersionString(item.Media) || undefined
        : undefined,
    };
  });
}

// ---- Combining ----

/**
 * The source to use. Profiles that turned on the older Trakt toggle and never picked
 * a source count as Automatic. Library Only Mode keeps Trakt out.
 */
export function effectiveContinueWatchingSource(
  settings: Pick<AppSettings, 'continueWatchingSource' | 'showTraktContinueWatching' | 'discoveryDisabled'>
): ContinueWatchingSource {
  if (settings.discoveryDisabled) return 'library';
  if (settings.continueWatchingSource === 'library' && settings.showTraktContinueWatching) return 'automatic';
  return settings.continueWatchingSource;
}

function normalizedTitle(title: string): string {
  return title.toLowerCase().replace(/[^a-z0-9À-￿]/g, '');
}

function isSameTitle(a: ContinueWatchingEntry, b: ContinueWatchingEntry): boolean {
  if (a.key === b.key) return true;
  if ((a.mediaType === 'movie') !== (b.mediaType === 'movie')) return false;
  return normalizedTitle(a.title) === normalizedTitle(b.title);
}

/**
 * Folds Trakt entries into the Plex or local list. A title already in the list keeps
 * one card: for local items the newer progress wins (Plex has no activity date).
 */
export function mergeContinueWatching(
  primary: ContinueWatchingEntry[],
  trakt: ContinueWatchingEntry[],
  dismissals: Record<string, number>
): ContinueWatchingEntry[] {
  const rows = [...primary];
  for (const entry of trakt) {
    const dismissedAt = dismissals[entry.key];
    if (dismissedAt !== undefined && (entry.lastActivity ?? 0) <= dismissedAt) continue;
    const index = rows.findIndex((row) => isSameTitle(row, entry));
    if (index >= 0) {
      const existing = rows[index].lastActivity;
      if (existing !== undefined && (entry.lastActivity ?? 0) > existing) rows[index] = entry;
      continue;
    }
    rows.push(entry);
  }

  // Items without a date (Plex) keep their server order at the front.
  const undated = rows.filter((row) => row.lastActivity === undefined);
  const dated = rows
    .filter((row) => row.lastActivity !== undefined)
    .sort((a, b) => (b.lastActivity as number) - (a.lastActivity as number));
  return [...undated, ...dated];
}

export function sortContinueWatching(
  entries: ContinueWatchingEntry[],
  sort: ContinueWatchingSort
): ContinueWatchingEntry[] {
  switch (sort) {
    case 'nextEpisodeFirst':
      return [...entries.filter((entry) => entry.isUpNext), ...entries.filter((entry) => !entry.isUpNext)];
    case 'title':
      return [...entries].sort((a, b) => a.title.localeCompare(b.title, undefined, { numeric: true }));
    default:
      return entries;
  }
}

/** Only a real movie or episode can take a watch-state action. */
export function buildWatchStateTarget(entry: ContinueWatchingEntry): WatchStateTarget {
  return {
    kind: entry.mediaType,
    plexRatingKey: entry.plexRatingKey,
    tmdbId: entry.tmdbId,
    imdbId: entry.imdbId,
    seasonNumber: entry.seasonNumber,
    episodeNumber: entry.episodeNumber,
    title: entry.title,
    sourceItemId: entry.key,
  };
}
