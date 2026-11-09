/**
 * Continue Watching: the Plex list, Trakt paused items and next episodes, merged
 * the way the macOS app does it.
 */
import { getSettings } from '@/state/settings';
import type { ContinueWatchingSource } from '@/state/settings';
import { apiClient } from '@/services/api';
import { plexBackendContinue } from '@/services/plex_backend';
import { tmdbDetails, tmdbImage } from '@/services/tmdb';
import {
  traktGetPlayback,
  traktShowProgress,
  traktWatchedShows,
  type TraktPlaybackItem,
  type TraktWatchedShowSummary,
} from '@/services/trakt';
import {
  continueWatchingRowKey,
  isTraktConnected,
  subscribeWatchState,
  type WatchTarget,
} from '@/services/watchState';

export type { ContinueWatchingSource };

export interface ContinueWatchingItem {
  /** Route id for `/details/:id` and `/player/:id`. */
  id: string;
  title: string;
  subtitle?: string;
  image?: string;
  /** 0 to 1. Zero means an up-next episode that has not been started. */
  progress: number;
  positionMs?: number;
  durationMs?: number;
  /** True when this item is the next unwatched episode. */
  isNextUp: boolean;
  origin: 'plex' | 'trakt';
  target: WatchTarget;
}

const CACHE_LIFETIME_MS = 60 * 1000;
/** Shows watched longer ago than this don't get a next-episode card. */
const NEXT_UP_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;
const MAX_NEXT_UP_SHOWS = 20;
const MAX_ENTRIES = 30;
const CONCURRENCY = 6;

interface TraktEntry {
  item: ContinueWatchingItem;
  rowKey: string;
  lastActivity: number;
  /** Title used to spot the same movie or show in the Plex list. */
  matchTitle: string;
  isMovie: boolean;
}

interface Candidate {
  isMovie: boolean;
  tmdbId: number;
  imdbId?: string;
  title: string;
  episodeTitle?: string;
  season?: number;
  episode?: number;
  runtimeMinutes?: number;
  progress?: number;
  activity: number;
}

// --- Trakt ---

let traktCache: { entries: TraktEntry[]; fetchedAt: number } | null = null;
let traktInFlight: Promise<TraktEntry[]> | null = null;
let generation = 0;

/** Forgets cached Trakt entries, for example after a watch-state change. */
export function invalidateContinueWatching() {
  generation += 1;
  traktCache = null;
  traktInFlight = null;
}

if (typeof window !== 'undefined') {
  subscribeWatchState(invalidateContinueWatching);
}

function traktEntries(): Promise<TraktEntry[]> {
  if (traktCache && Date.now() - traktCache.fetchedAt < CACHE_LIFETIME_MS) {
    return Promise.resolve(traktCache.entries);
  }
  if (traktInFlight) return traktInFlight;

  const started = generation;
  const task = fetchTraktEntries()
    .then((entries) => {
      if (started === generation) traktCache = { entries, fetchedAt: Date.now() };
      return entries;
    })
    .finally(() => {
      if (traktInFlight === task) traktInFlight = null;
    });
  traktInFlight = task;
  return task;
}

function parseDate(value?: string): number | undefined {
  if (!value) return undefined;
  const time = Date.parse(value);
  return Number.isNaN(time) ? undefined : time;
}

function candidateFromPlayback(playback: TraktPlaybackItem): Candidate | undefined {
  // Trakt counts 80%+ as watched. Ignore accidental starts and finished items.
  if (!(playback.progress >= 1 && playback.progress < 95)) return undefined;
  const activity = parseDate(playback.paused_at);
  if (activity == null) return undefined;

  if (playback.type === 'movie' && playback.movie?.ids?.tmdb != null) {
    const { movie } = playback;
    return {
      isMovie: true,
      tmdbId: movie.ids.tmdb!,
      imdbId: movie.ids.imdb,
      title: movie.title,
      runtimeMinutes: movie.runtime,
      progress: playback.progress,
      activity,
    };
  }
  if (playback.type === 'episode' && playback.show?.ids?.tmdb != null && playback.episode) {
    const { show, episode } = playback;
    return {
      isMovie: false,
      tmdbId: show.ids.tmdb!,
      imdbId: show.ids.imdb,
      title: show.title,
      episodeTitle: episode.title,
      season: episode.season,
      episode: episode.number,
      runtimeMinutes: episode.runtime ?? show.runtime,
      progress: playback.progress,
      activity,
    };
  }
  return undefined;
}

async function inBatches<T, R>(items: T[], work: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = [];
  for (let i = 0; i < items.length; i += CONCURRENCY) {
    results.push(...await Promise.all(items.slice(i, i + CONCURRENCY).map(work)));
  }
  return results;
}

async function nextUpCandidates(shows: TraktWatchedShowSummary[]): Promise<Candidate[]> {
  const cutoff = Date.now() - NEXT_UP_WINDOW_MS;
  const recent = shows
    .map((summary) => ({ show: summary.show, date: parseDate(summary.last_watched_at) }))
    .filter((entry): entry is { show: TraktWatchedShowSummary['show']; date: number } =>
      entry.show?.ids?.tmdb != null && entry.date != null && entry.date > cutoff)
    .sort((a, b) => b.date - a.date)
    .slice(0, MAX_NEXT_UP_SHOWS);

  const results = await inBatches(recent, async ({ show, date }): Promise<Candidate | undefined> => {
    const showId = show.ids.trakt ?? show.ids.slug;
    if (showId == null) return undefined;
    try {
      const next = (await traktShowProgress(showId)).next_episode;
      if (!next) return undefined;
      return {
        isMovie: false,
        tmdbId: show.ids.tmdb!,
        imdbId: show.ids.imdb,
        title: show.title,
        episodeTitle: next.title,
        season: next.season,
        episode: next.number,
        runtimeMinutes: next.runtime ?? show.runtime,
        activity: date,
      };
    } catch {
      return undefined;
    }
  });
  return results.filter((c): c is Candidate => !!c);
}

async function fetchTraktEntries(): Promise<TraktEntry[]> {
  const paused = await traktGetPlayback();
  const candidates = paused.map(candidateFromPlayback).filter((c): c is Candidate => !!c);

  // Next episodes are a bonus: losing them shouldn't lose the paused items.
  try {
    candidates.push(...await nextUpCandidates(await traktWatchedShows()));
  } catch {
    // Keep the paused items.
  }

  const newest = new Map<string, Candidate>();
  for (const candidate of candidates) {
    const key = `${candidate.isMovie ? 'movie' : 'tv'}:${candidate.tmdbId}`;
    const current = newest.get(key);
    if (!current || candidate.activity > current.activity) newest.set(key, candidate);
  }

  const chosen = [...newest.values()].sort((a, b) => b.activity - a.activity).slice(0, MAX_ENTRIES);
  const entries = await inBatches(chosen, async (candidate) => {
    let backdrop: string | undefined;
    let poster: string | undefined;
    try {
      const details: any = await tmdbDetails('', candidate.isMovie ? 'movie' : 'tv', candidate.tmdbId);
      backdrop = details?.backdrop_path;
      poster = details?.poster_path;
    } catch {
      // The card still works without artwork.
    }
    return makeEntry(candidate, backdrop ?? poster);
  });
  return entries.sort((a, b) => b.lastActivity - a.lastActivity);
}

function makeEntry(c: Candidate, artPath?: string): TraktEntry {
  const durationMs = c.runtimeMinutes && c.runtimeMinutes > 0 ? c.runtimeMinutes * 60_000 : undefined;
  const positionMs = c.progress != null && durationMs != null ? Math.round((durationMs * c.progress) / 100) : undefined;
  const episodeLabel = c.episodeTitle || `Episode ${c.episode ?? 0}`;

  const item: ContinueWatchingItem = {
    id: c.isMovie ? `tmdb:movie:${c.tmdbId}` : `tmdb:tv:${c.tmdbId}:s${c.season}e${c.episode}`,
    title: c.title,
    subtitle: c.isMovie ? undefined : `S${c.season} E${c.episode} · ${episodeLabel}`,
    image: tmdbImage(artPath, 'w780'),
    progress: c.progress != null ? c.progress / 100 : 0,
    positionMs,
    durationMs,
    isNextUp: c.progress == null,
    origin: 'trakt',
    target: c.isMovie
      ? { kind: 'movie', tmdbId: c.tmdbId, imdbId: c.imdbId, title: c.title }
      : {
          kind: 'episode',
          showTmdbId: c.tmdbId,
          showImdbId: c.imdbId,
          seasonNumber: c.season,
          episodeNumber: c.episode,
          title: c.title,
        },
  };

  return {
    item,
    rowKey: continueWatchingRowKey({
      isMovie: c.isMovie,
      tmdbId: c.tmdbId,
      seasonNumber: c.season,
      episodeNumber: c.episode,
    }),
    lastActivity: c.activity,
    matchTitle: normalizeTitle(c.title),
    isMovie: c.isMovie,
  };
}

// --- Plex ---

interface PlexRow {
  item: ContinueWatchingItem;
  matchTitle: string;
  isMovie: boolean;
}

function toPlexRow(m: any): PlexRow {
  const isMovie = m.type === 'movie';
  const durationMs = Number(m.duration) || undefined;
  const positionMs = Number(m.viewOffset) || undefined;
  const showTitle: string = m.grandparentTitle || m.title || '';
  const art = m.grandparentArt || m.art || m.thumb || m.parentThumb || m.grandparentThumb;
  const season = m.parentIndex != null ? Number(m.parentIndex) : undefined;
  const episode = m.index != null ? Number(m.index) : undefined;

  return {
    isMovie,
    matchTitle: normalizeTitle(isMovie ? m.title : showTitle),
    item: {
      id: `plex:${m.ratingKey}`,
      title: isMovie ? m.title : showTitle,
      subtitle: isMovie ? undefined : `S${season ?? '?'} E${episode ?? '?'} · ${m.title}`,
      image: art ? apiClient.getPlexImageNoToken(art) : undefined,
      progress: durationMs && positionMs ? Math.min(positionMs / durationMs, 1) : 0,
      positionMs,
      durationMs,
      isNextUp: !isMovie && !positionMs,
      origin: 'plex',
      target: isMovie
        ? { kind: 'movie', plexRatingKey: String(m.ratingKey), title: m.title }
        : {
            kind: 'episode',
            plexRatingKey: String(m.ratingKey),
            showPlexRatingKey: m.grandparentRatingKey != null ? String(m.grandparentRatingKey) : undefined,
            seasonNumber: season,
            episodeNumber: episode,
            title: showTitle,
          },
    },
  };
}

async function plexRows(): Promise<PlexRow[]> {
  const data: any = await plexBackendContinue();
  return (data?.MediaContainer?.Metadata || [])
    .filter((m: any) => m?.ratingKey != null && (m.type === 'movie' || m.type === 'episode'))
    .map(toPlexRow);
}

// --- Merging ---

function normalizeTitle(title: string): string {
  return title.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');
}

/**
 * Folds Trakt entries into the Plex list. A title already in the list keeps its
 * one Plex card. Plex items have no activity date, so they stay first in server
 * order, followed by Trakt items, newest first.
 */
function merge(primary: PlexRow[], trakt: TraktEntry[], dismissals: Record<string, number>): ContinueWatchingItem[] {
  const merged = primary.map((row) => row.item);
  const dated: TraktEntry[] = [];
  for (const entry of trakt) {
    const dismissed = dismissals[entry.rowKey];
    if (dismissed != null && entry.lastActivity <= dismissed) continue;
    const inPlex = primary.some((row) => row.isMovie === entry.isMovie && row.matchTitle === entry.matchTitle);
    if (!inPlex) dated.push(entry);
  }
  dated.sort((a, b) => b.lastActivity - a.lastActivity);
  return [...merged, ...dated.map((entry) => entry.item)];
}

export async function getContinueWatching(
  source: ContinueWatchingSource = 'automatic',
): Promise<ContinueWatchingItem[]> {
  const usesTrakt = source !== 'library' && isTraktConnected();
  const usesPlex = source !== 'trakt' || !usesTrakt;

  const [plexResult, traktResult] = await Promise.allSettled([
    usesPlex ? plexRows() : Promise.resolve<PlexRow[]>([]),
    usesTrakt ? traktEntries() : Promise.resolve<TraktEntry[]>([]),
  ]);

  if (plexResult.status === 'rejected' && (traktResult.status === 'rejected' || !usesTrakt)) {
    throw plexResult.reason;
  }

  if (traktResult.status === 'rejected') {
    // Same as macOS: a Trakt failure falls back to Plex, even for the Trakt source.
    return (plexResult.status === 'fulfilled' && usesPlex ? plexResult.value : await plexRows()).map((row) => row.item);
  }

  const primary = plexResult.status === 'fulfilled' ? plexResult.value : [];
  return merge(primary, traktResult.value, getSettings().continueWatchingTraktDismissals);
}
