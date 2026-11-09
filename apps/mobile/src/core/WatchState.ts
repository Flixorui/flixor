/**
 * One place for mark watched/unwatched, remove from Continue Watching, start over and
 * Trakt ratings. macOS reference: Services/WatchStateService.swift
 *
 * Each action is applied to every backend that owns state for the item:
 *   Plex  - items with a plexRatingKey.
 *   Trakt - when Trakt is connected.
 *   Local - items without a Plex copy.
 *
 * Every action resolves to a WatchStateResult (never rejects); pass result.message
 * to showToast. Listeners fire when anything changed.
 *
 * Watched-state writes to Trakt follow the traktAutoSyncWatched setting (on unless turned
 * off, as on macOS). Ratings only need Trakt to be connected.
 */

import type { PlexServerService, TraktShowProgress, TraktSyncItems, TraktSyncResult } from '@flixor/core';
import { getFlixorCore } from './index';
import { isStremioOnlyMode } from './AppMode';
import { getAppSettings } from './SettingsData';
import { localLibrary, type LocalTitleQuery } from './LocalLibrary';
import { stremioResumeStore } from '../stremio/StremioResumeStore';

export type WatchStateAction =
  | 'markWatched'
  | 'markUnwatched'
  | 'removeFromContinueWatching'
  | 'startOver'
  | 'rate'
  | 'removeRating';

export type WatchStateBackend = 'plex' | 'trakt' | 'local';

export type WatchStateKind = 'movie' | 'show' | 'season' | 'episode';

export interface WatchStateTarget {
  kind: WatchStateKind;
  /** The item's own Plex ratingKey (movie, show, season or episode). */
  plexRatingKey?: string;
  /** Movie TMDB id, or the SHOW's TMDB id for show, season and episode. */
  tmdbId?: number;
  /** Movie IMDb id, or the SHOW's IMDb id for show, season and episode. */
  imdbId?: string;
  /** Show TVDB id. Helps Trakt matching. */
  tvdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
  title?: string;
  /** Echoed to listeners so rows can find the card to update. */
  sourceItemId?: string;
  /**
   * Set for "Recently added" series cards that stand for new episodes.
   * Whole-show watch-state writes are refused for these.
   */
  isNewEpisodesCard?: boolean;
}

export interface WatchStateFailure {
  backend: WatchStateBackend | null;
  message: string;
}

export interface WatchStateResult {
  action: WatchStateAction;
  target: WatchStateTarget;
  succeeded: WatchStateBackend[];
  failures: WatchStateFailure[];
  /** Nothing needed changing. Not an error. */
  noChanges: boolean;
  /** Everything attempted worked. */
  isSuccess: boolean;
  /** Some backends worked, some failed. */
  isPartialSuccess: boolean;
  /** Short text for a toast. */
  message: string;
}

export interface WatchStateChange {
  action: WatchStateAction;
  target: WatchStateTarget;
  rating?: number;
  backends: WatchStateBackend[];
}

const SUCCESS_TEXT: Record<WatchStateAction, string> = {
  markWatched: 'Marked as watched',
  markUnwatched: 'Marked as unwatched',
  removeFromContinueWatching: 'Removed from Continue Watching',
  startOver: 'Progress reset',
  rate: 'Rating saved',
  removeRating: 'Rating removed',
};

const FAILURE_TEXT: Record<WatchStateAction, string> = {
  markWatched: "Couldn't mark as watched",
  markUnwatched: "Couldn't mark as unwatched",
  removeFromContinueWatching: "Couldn't remove from Continue Watching",
  startOver: "Couldn't reset progress",
  rate: "Couldn't save rating",
  removeRating: "Couldn't remove rating",
};

const NO_CHANGE_TEXT: Record<WatchStateAction, string> = {
  markWatched: 'Already watched',
  markUnwatched: 'Already unwatched',
  removeFromContinueWatching: 'Not in Continue Watching',
  startOver: 'No saved progress',
  rate: 'Nothing to update',
  removeRating: 'Nothing to update',
};

const BACKEND_NAMES: Record<WatchStateBackend, string> = {
  plex: 'Plex',
  trakt: 'Trakt',
  local: 'this device',
};

const NO_TRAKT_MATCH = "couldn't match on Trakt";

const listeners = new Set<(change: WatchStateChange) => void>();

export function addWatchStateListener(listener: (change: WatchStateChange) => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function describeFailure(failure: WatchStateFailure): string {
  return failure.backend ? `${BACKEND_NAMES[failure.backend]}: ${failure.message}` : failure.message;
}

function buildResult(
  action: WatchStateAction,
  target: WatchStateTarget,
  succeeded: WatchStateBackend[],
  failures: WatchStateFailure[],
  noChanges = false
): WatchStateResult {
  const isSuccess = succeeded.length > 0 && failures.length === 0;
  const isPartialSuccess = succeeded.length > 0 && failures.length > 0;
  let message: string;
  if (noChanges) {
    message = NO_CHANGE_TEXT[action];
  } else if (isSuccess) {
    message = SUCCESS_TEXT[action];
  } else if (isPartialSuccess) {
    message = `${SUCCESS_TEXT[action]}, but ${failures.map(describeFailure).join('; ')}`;
  } else {
    message = `${FAILURE_TEXT[action]}: ${failures[0] ? describeFailure(failures[0]) : 'Nothing to update'}`;
  }
  return { action, target, succeeded, failures, noChanges, isSuccess, isPartialSuccess, message };
}

class Outcome {
  succeeded: WatchStateBackend[] = [];
  failures: WatchStateFailure[] = [];
  sawUnchanged = false;

  succeed(backend: WatchStateBackend): void {
    if (!this.succeeded.includes(backend)) this.succeeded.push(backend);
  }

  fail(backend: WatchStateBackend, reason: unknown): void {
    this.failures.push({ backend, message: describeError(reason) });
  }
}

function describeError(reason: unknown): string {
  const message = reason instanceof Error ? reason.message : String(reason);
  const trakt = /^Trakt API error: (\d+)/.exec(message);
  if (trakt) {
    if (trakt[1] === '401') return 'sign-in expired';
    if (trakt[1] === '429') return 'rate limited, try again shortly';
    if (trakt[1] === '404') return NO_TRAKT_MATCH;
    return `error ${trakt[1]}`;
  }
  const plex = /^Plex API error: (\d+)/.exec(message);
  if (plex) return plex[1] === '404' ? 'not supported by this server' : `error ${plex[1]}`;
  return message;
}

function connectedPlex(): PlexServerService | null {
  const core = getFlixorCore();
  return !isStremioOnlyMode() && core.isPlexServerConnected ? core.plexServer : null;
}

function isTraktConnected(): boolean {
  return getFlixorCore().isTraktAuthenticated;
}

/** Watch history and progress changes are pushed to Trakt. Ratings don't depend on this. */
function isTraktWatchSyncEnabled(): boolean {
  const settings: { traktAutoSyncWatched?: boolean } = getAppSettings() as any;
  return isTraktConnected() && settings.traktAutoSyncWatched !== false;
}

function parseGuids(guids?: Array<{ id: string }>): Partial<WatchStateTarget> {
  const ids: Partial<WatchStateTarget> = {};
  for (const { id } of guids ?? []) {
    const [scheme, value] = id.split('://');
    if (!value) continue;
    if (scheme === 'tmdb') ids.tmdbId = Number(value) || undefined;
    else if (scheme === 'imdb') ids.imdbId = value;
    else if (scheme === 'tvdb') ids.tvdbId = Number(value) || undefined;
  }
  return ids;
}

/** Season/episode numbers and title-level ids from the item's own Plex metadata. */
async function resolveFromPlex(target: WatchStateTarget): Promise<WatchStateTarget> {
  const needsIds = target.tmdbId == null && target.imdbId == null && target.tvdbId == null;
  const needsNumbers =
    (target.kind === 'episode' && (target.seasonNumber == null || target.episodeNumber == null)) ||
    (target.kind === 'season' && target.seasonNumber == null);
  if (!target.plexRatingKey || (!needsIds && !needsNumbers)) return target;

  const plex = connectedPlex();
  if (!plex) return target;
  try {
    const item = await plex.getMetadata(target.plexRatingKey, true);
    if (!item) return target;
    const resolved = { ...target };
    if (target.kind === 'episode') {
      resolved.seasonNumber ??= item.parentIndex;
      resolved.episodeNumber ??= item.index;
    } else if (target.kind === 'season') {
      resolved.seasonNumber ??= item.index;
    }
    if (needsIds) {
      const showKey =
        target.kind === 'episode' ? item.grandparentRatingKey : target.kind === 'season' ? item.parentRatingKey : undefined;
      const titleItem = showKey ? await plex.getMetadata(showKey, true) : item;
      Object.assign(resolved, parseGuids(titleItem?.Guid));
    }
    return resolved;
  } catch (e) {
    console.log('[WatchState] resolveTarget error:', e);
    return target;
  }
}

/** Fills whichever of the TMDB and IMDb ids is missing, from the other one. */
async function resolveExternalIds(target: WatchStateTarget): Promise<WatchStateTarget> {
  if ((target.tmdbId == null) === (target.imdbId == null)) return target;
  const tmdb = getFlixorCore().tmdb;
  const isMovie = target.kind === 'movie';
  try {
    if (target.tmdbId == null && target.imdbId) {
      const found = await tmdb.findByImdbId(target.imdbId);
      const match = isMovie ? found.movie_results?.[0] : found.tv_results?.[0];
      return match?.id != null ? { ...target, tmdbId: match.id } : target;
    }
    if (target.tmdbId != null) {
      const ids = isMovie ? await tmdb.getMovieExternalIds(target.tmdbId) : await tmdb.getTVExternalIds(target.tmdbId);
      return ids?.imdb_id ? { ...target, imdbId: ids.imdb_id } : target;
    }
  } catch (e) {
    console.log('[WatchState] resolveExternalIds error:', e);
  }
  return target;
}

/** Fills in season/episode numbers and title-level ids that the caller doesn't know. */
export async function resolveWatchTarget(target: WatchStateTarget): Promise<WatchStateTarget> {
  const resolved = await resolveFromPlex(target);
  return isTraktConnected() || !resolved.plexRatingKey ? resolveExternalIds(resolved) : resolved;
}

function traktIds(t: WatchStateTarget): { tmdb?: number; imdb?: string; tvdb?: number } | null {
  if (t.tmdbId == null && t.imdbId == null && t.tvdbId == null) return null;
  return { tmdb: t.tmdbId, imdb: t.imdbId, tvdb: t.kind === 'movie' ? undefined : t.tvdbId };
}

/** Sync body for a resolved target. Null when an id or number is unknown. */
function traktItems(t: WatchStateTarget, rating?: number): TraktSyncItems | null {
  const ids = traktIds(t);
  if (!ids) return null;
  const rated = rating == null ? {} : { rating };
  switch (t.kind) {
    case 'movie':
      return { movies: [{ ids, ...rated }] };
    case 'show':
      return { shows: [{ ids, ...rated }] };
    case 'season':
      return t.seasonNumber == null ? null : { shows: [{ ids, seasons: [{ number: t.seasonNumber, ...rated }] }] };
    case 'episode':
      return t.seasonNumber == null || t.episodeNumber == null
        ? null
        : {
            shows: [
              { ids, seasons: [{ number: t.seasonNumber, episodes: [{ number: t.episodeNumber, ...rated }] }] },
            ],
          };
  }
}

function idsMatch(ids: { tmdb?: number; imdb?: string; tvdb?: number } | undefined, t: WatchStateTarget): boolean {
  if (!ids) return false;
  return (
    (t.tmdbId != null && ids.tmdb === t.tmdbId) ||
    (!!t.imdbId && ids.imdb?.toLowerCase() === t.imdbId.toLowerCase()) ||
    (t.kind !== 'movie' && t.tvdbId != null && ids.tvdb === t.tvdbId)
  );
}

function countOf(values?: Record<string, unknown>): number {
  return Object.values(values ?? {}).reduce<number>(
    (total, value) => total + (Array.isArray(value) ? value.length : typeof value === 'number' ? value : 0),
    0
  );
}

/** Trakt accepted the request but matched none of the items. */
function matchedNothing(result: TraktSyncResult): boolean {
  return countOf(result.added) + countOf(result.existing) + countOf(result.updated) === 0 && countOf(result.not_found) > 0;
}

/** Trakt allows about one write per second per user. */
const TRAKT_WRITE_SPACING_MS = 1100;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function localQuery(t: WatchStateTarget): LocalTitleQuery {
  return {
    mediaType: t.kind === 'movie' ? 'movie' : 'episode',
    tmdbId: t.tmdbId,
    imdbId: t.imdbId,
    season: t.seasonNumber,
    episode: t.episodeNumber,
  };
}

async function applyPlex(
  t: WatchStateTarget,
  outcome: Outcome,
  action: (plex: PlexServerService, key: string) => Promise<void>
): Promise<void> {
  if (!t.plexRatingKey) return;
  const plex = connectedPlex();
  if (!plex) {
    outcome.fail('plex', isStremioOnlyMode() ? 'not used in Stremio-only mode' : 'no server connected');
    return;
  }
  try {
    await action(plex, t.plexRatingKey);
    outcome.succeed('plex');
  } catch (e) {
    outcome.fail('plex', e);
  }
}

interface PlaybackRemoval {
  removed: number;
  failed: number;
  fetchFailed: boolean;
}

/**
 * Deletes Trakt paused-playback entries that match the target. Deletes are spaced for
 * Trakt's write limit; pass afterWrite when a write has just gone out.
 */
async function removeTraktPlayback(t: WatchStateTarget, afterWrite: boolean): Promise<PlaybackRemoval> {
  const removal: PlaybackRemoval = { removed: 0, failed: 0, fetchFailed: false };
  if (!isTraktWatchSyncEnabled() || !traktIds(t)) return removal;
  const trakt = getFlixorCore().trakt;
  let entries;
  try {
    entries = await trakt.getPlaybackProgress(t.kind === 'movie' ? 'movies' : 'episodes');
  } catch {
    removal.fetchFailed = true;
    return removal;
  }

  const matching = entries.filter((entry) => {
    if (t.kind === 'movie') return idsMatch(entry.movie?.ids, t);
    if (!idsMatch(entry.show?.ids, t)) return false;
    if (t.kind === 'show') return true;
    if (t.seasonNumber == null || entry.episode?.season !== t.seasonNumber) return false;
    return t.kind === 'season' || entry.episode?.number === t.episodeNumber;
  });

  let needsSpacing = afterWrite;
  for (const entry of matching) {
    if (needsSpacing) await sleep(TRAKT_WRITE_SPACING_MS);
    needsSpacing = true;
    try {
      await trakt.removePlaybackProgress(entry.id);
      removal.removed += 1;
    } catch (e) {
      removal.failed += 1;
      console.log('[WatchState] Trakt playback delete failed:', e);
    }
  }
  return removal;
}

function recordPlaybackRemoval(removal: PlaybackRemoval, outcome: Outcome): void {
  if (removal.fetchFailed) {
    outcome.fail('trakt', "couldn't read saved progress");
  } else if (removal.failed > 0) {
    outcome.fail('trakt', `couldn't remove ${removal.failed} saved progress ${removal.failed === 1 ? 'entry' : 'entries'}`);
  }
  if (removal.removed > 0) outcome.succeed('trakt');
}

/** Id accepted by Trakt's show endpoints: the IMDb id when known, else the Trakt id. */
async function traktShowId(t: WatchStateTarget): Promise<string | number | null> {
  if (t.imdbId?.toLowerCase().startsWith('tt')) return t.imdbId;
  if (t.tmdbId == null) return null;
  const show = await getFlixorCore().trakt.lookupByTmdb(t.tmdbId, 'show');
  return show?.ids?.trakt ?? null;
}

async function traktMovieId(t: WatchStateTarget): Promise<number | null> {
  const trakt = getFlixorCore().trakt;
  const movie =
    t.tmdbId != null
      ? await trakt.lookupByTmdb(t.tmdbId, 'movie')
      : t.imdbId
        ? await trakt.lookupByImdb(t.imdbId, 'movie')
        : null;
  return movie?.ids?.trakt ?? null;
}

interface EpisodeNumber {
  season: number;
  episode: number;
}

/**
 * Aired episodes not yet watched that the target covers. Null when the target's numbers
 * are unknown. An episode Trakt doesn't list as aired is returned as-is, since the user
 * is asserting they watched it.
 */
function unwatchedEpisodes(progress: TraktShowProgress, t: WatchStateTarget): EpisodeNumber[] | null {
  const incomplete = (season: TraktShowProgress['seasons'][number]): EpisodeNumber[] =>
    season.episodes.filter((e) => !e.completed).map((e) => ({ season: season.number, episode: e.number }));

  switch (t.kind) {
    case 'show':
      return progress.seasons.filter((s) => s.number > 0).flatMap(incomplete);
    case 'season': {
      if (t.seasonNumber == null) return null;
      const season = progress.seasons.find((s) => s.number === t.seasonNumber);
      return season ? incomplete(season) : [];
    }
    case 'episode': {
      if (t.seasonNumber == null || t.episodeNumber == null) return null;
      const listed = progress.seasons
        .find((s) => s.number === t.seasonNumber)
        ?.episodes.find((e) => e.number === t.episodeNumber);
      return listed?.completed ? [] : [{ season: t.seasonNumber, episode: t.episodeNumber }];
    }
    default:
      return [];
  }
}

/** Adds only what isn't already watched, so repeated taps don't add duplicate plays. */
async function addTraktHistory(t: WatchStateTarget, outcome: Outcome): Promise<void> {
  const ids = traktIds(t);
  if (!ids) {
    outcome.fail('trakt', NO_TRAKT_MATCH);
    return;
  }
  const trakt = getFlixorCore().trakt;
  const watchedAt = new Date().toISOString();
  let items: TraktSyncItems;

  try {
    if (t.kind === 'movie') {
      const movieId = await traktMovieId(t);
      if (movieId == null) {
        outcome.fail('trakt', NO_TRAKT_MATCH);
        return;
      }
      if ((await trakt.getItemHistory('movies', movieId, 1)).length > 0) {
        outcome.sawUnchanged = true;
        return;
      }
      items = { movies: [{ ids, watched_at: watchedAt }] };
    } else {
      const showId = await traktShowId(t);
      if (showId == null) {
        outcome.fail('trakt', NO_TRAKT_MATCH);
        return;
      }
      const progress = await trakt.getShowProgress(showId);
      const missing = unwatchedEpisodes(progress, t);
      if (!missing) {
        outcome.fail('trakt', 'season/episode not known yet');
        return;
      }
      if (missing.length === 0) {
        if (progress.aired === 0 && t.kind === 'show') outcome.fail('trakt', 'no aired episodes on Trakt');
        else outcome.sawUnchanged = true;
        return;
      }
      const seasons = new Map<number, Array<{ number: number; watched_at: string }>>();
      for (const { season, episode } of missing) {
        const episodes = seasons.get(season) ?? [];
        episodes.push({ number: episode, watched_at: watchedAt });
        seasons.set(season, episodes);
      }
      items = {
        shows: [
          {
            ids,
            seasons: [...seasons.entries()]
              .sort(([a], [b]) => a - b)
              .map(([number, episodes]) => ({ number, episodes })),
          },
        ],
      };
    }
  } catch (e) {
    outcome.fail('trakt', e);
    return;
  }

  try {
    if (matchedNothing(await trakt.addToHistory(items))) {
      outcome.fail('trakt', NO_TRAKT_MATCH);
      return;
    }
    outcome.succeed('trakt');
  } catch (e) {
    outcome.fail('trakt', e);
    return;
  }

  const removal = await removeTraktPlayback(t, true);
  if (removal.failed > 0 || removal.fetchFailed) outcome.fail('trakt', "couldn't clear saved progress");
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/** Episode numbers of a season that have aired (air date today or earlier). */
async function airedEpisodes(tvId: number, season: number): Promise<number[]> {
  const details = await getFlixorCore().tmdb.getSeasonDetails(tvId, season);
  const today = todayIso();
  return (details.episodes ?? [])
    .filter((ep) => !!ep.air_date && ep.air_date <= today)
    .map((ep) => ep.episode_number);
}

/** The local watched entries a target stands for. Throws when they can't be worked out. */
async function localWatchedQueries(t: WatchStateTarget): Promise<LocalTitleQuery[]> {
  if (t.tmdbId == null && t.imdbId == null) throw new Error('no TMDB or IMDb id');
  if (t.kind === 'movie' || t.kind === 'episode') return [localQuery(t)];
  if (t.tmdbId == null) throw new Error('no TMDB id');
  const tmdbId = t.tmdbId;
  const forSeason = (season: number, episodes: number[]): LocalTitleQuery[] =>
    episodes.map((episode) => ({ mediaType: 'episode', tmdbId, imdbId: t.imdbId, season, episode }));

  if (t.kind === 'season') {
    if (t.seasonNumber == null) throw new Error('season not known yet');
    return forSeason(t.seasonNumber, await airedEpisodes(tmdbId, t.seasonNumber));
  }

  const details = await getFlixorCore().tmdb.getTVDetails(tmdbId);
  const seasons = (details.seasons ?? []).map((s) => s.season_number).filter((n) => n > 0);
  const queries: LocalTitleQuery[] = [];
  // One season at a time: long-running shows have dozens of seasons
  for (const season of seasons) {
    try {
      queries.push(...forSeason(season, await airedEpisodes(tmdbId, season)));
    } catch (e) {
      console.log('[WatchState] airedEpisodes error:', e);
    }
  }
  return queries;
}

/** Clears local history and resume points. Returns how many entries were removed. */
async function clearLocalProgress(t: WatchStateTarget): Promise<number> {
  if (t.tmdbId == null && t.imdbId == null) return 0;
  if (t.kind === 'episode' && (t.seasonNumber == null || t.episodeNumber == null)) return 0;
  if (t.kind === 'season' && t.seasonNumber == null) return 0;
  const removed = await localLibrary.removeHistoryMatching(localQuery(t));
  await Promise.all(removed.map((contentKey) => stremioResumeStore.clear(contentKey)));
  return removed.length;
}

const inFlight = new Set<string>();

function targetKey(t: WatchStateTarget): string {
  const id = t.plexRatingKey ?? `${t.tmdbId ?? ''}/${t.imdbId ?? ''}`;
  return `${t.kind}:${id}:${t.seasonNumber ?? ''}:${t.episodeNumber ?? ''}`;
}

async function perform(
  action: WatchStateAction,
  target: WatchStateTarget,
  body: (resolved: WatchStateTarget, outcome: Outcome) => Promise<void>,
  rating?: number
): Promise<WatchStateResult> {
  const isWatchWrite = action !== 'rate' && action !== 'removeRating';
  if (isWatchWrite && target.kind === 'show' && target.isNewEpisodesCard) {
    return buildResult(action, target, [], [
      { backend: null, message: 'this card is for new episodes; open the show to pick episodes' },
    ]);
  }

  // Keyed by target only, so opposite actions on one item can't interleave
  const key = targetKey(target);
  if (inFlight.has(key)) {
    return buildResult(action, target, [], [
      { backend: null, message: 'another change to this item is in progress' },
    ]);
  }
  inFlight.add(key);

  try {
    const resolved = await resolveWatchTarget(target);
    const outcome = new Outcome();
    await body(resolved, outcome);

    const nothingHappened = outcome.succeeded.length === 0 && outcome.failures.length === 0;
    if (nothingHappened && !outcome.sawUnchanged && action !== 'startOver' && action !== 'removeFromContinueWatching') {
      outcome.failures.push({ backend: null, message: 'nothing to update for this item' });
    }

    const result = buildResult(
      action,
      resolved,
      outcome.succeeded,
      outcome.failures,
      outcome.succeeded.length === 0 && outcome.failures.length === 0
    );
    if (result.succeeded.length > 0) {
      const change: WatchStateChange = { action, target: resolved, rating, backends: result.succeeded };
      listeners.forEach((listener) => listener(change));
    }
    return result;
  } catch (e) {
    return buildResult(action, target, [], [
      { backend: null, message: e instanceof Error ? e.message : String(e) },
    ]);
  } finally {
    inFlight.delete(key);
  }
}

/** Marks a movie, episode, season or show watched, and clears resume points. */
export function markWatched(target: WatchStateTarget): Promise<WatchStateResult> {
  return perform('markWatched', target, async (t, outcome) => {
    await applyPlex(t, outcome, (plex, key) => plex.scrobble(key));

    if (isTraktWatchSyncEnabled()) await addTraktHistory(t, outcome);

    if (!t.plexRatingKey) {
      try {
        const queries = await localWatchedQueries(t);
        if (queries.length === 0) throw new Error('no aired episodes found');
        if ((await localLibrary.markWatched(queries)) > 0) outcome.succeed('local');
        else outcome.fail('local', 'no TMDB or IMDb id');
      } catch (e) {
        outcome.fail('local', e);
      }
    }

    await clearLocalProgress(t);
  });
}

/** Reverses markWatched on every backend. */
export function markUnwatched(target: WatchStateTarget): Promise<WatchStateResult> {
  return perform('markUnwatched', target, async (t, outcome) => {
    await applyPlex(t, outcome, (plex, key) => plex.unscrobble(key));

    if (isTraktWatchSyncEnabled()) {
      const items = traktItems(t);
      if (!items) {
        outcome.fail('trakt', NO_TRAKT_MATCH);
      } else {
        try {
          await getFlixorCore().trakt.removeFromHistory(items);
          outcome.succeed('trakt');
        } catch (e) {
          outcome.fail('trakt', e);
        }
      }
    }

    if (!t.plexRatingKey) {
      if ((await localLibrary.removeWatched(localQuery(t))) > 0) outcome.succeed('local');
      else outcome.sawUnchanged = true;
    }
  });
}

/** Removes an item from Continue Watching without changing its watched state. */
export function removeFromContinueWatching(target: WatchStateTarget): Promise<WatchStateResult> {
  return perform('removeFromContinueWatching', target, async (t, outcome) => {
    await applyPlex(t, outcome, (plex, key) => plex.removeFromContinueWatching(key));
    recordPlaybackRemoval(await removeTraktPlayback(t, false), outcome);
    if ((await clearLocalProgress(t)) > 0) outcome.succeed('local');
  });
}

/** Resets saved progress so the caller can play from 0. Watched state is unchanged. */
export function startOver(target: WatchStateTarget): Promise<WatchStateResult> {
  return perform('startOver', target, async (t, outcome) => {
    if (t.kind === 'movie' || t.kind === 'episode') {
      await applyPlex(t, outcome, (plex, key) => plex.resetProgress(key));
    }
    recordPlaybackRemoval(await removeTraktPlayback(t, false), outcome);
    if ((await clearLocalProgress(t)) > 0) outcome.succeed('local');
  });
}

function traktRequired(action: WatchStateAction, target: WatchStateTarget): WatchStateResult {
  return buildResult(action, target, [], [{ backend: 'trakt', message: 'connect Trakt in Settings' }]);
}

/** Whether ratings can be read and written. */
export function canRate(): boolean {
  return isTraktConnected();
}

/** Rates a movie, show, season or episode on Trakt (1-10). */
export async function rate(target: WatchStateTarget, rating: number): Promise<WatchStateResult> {
  if (!Number.isInteger(rating) || rating < 1 || rating > 10) {
    return buildResult('rate', target, [], [{ backend: 'trakt', message: 'rating must be 1-10' }]);
  }
  if (!isTraktConnected()) return traktRequired('rate', target);
  return perform(
    'rate',
    target,
    async (t, outcome) => {
      const items = traktItems(t, rating);
      if (!items) {
        outcome.fail('trakt', NO_TRAKT_MATCH);
        return;
      }
      try {
        if (matchedNothing(await getFlixorCore().trakt.addRatings(items))) outcome.fail('trakt', NO_TRAKT_MATCH);
        else outcome.succeed('trakt');
      } catch (e) {
        outcome.fail('trakt', e);
      }
    },
    rating
  );
}

/** Removes the user's Trakt rating for a movie, show, season or episode. */
export async function removeRating(target: WatchStateTarget): Promise<WatchStateResult> {
  if (!isTraktConnected()) return traktRequired('removeRating', target);
  return perform('removeRating', target, async (t, outcome) => {
    const items = traktItems(t);
    if (!items) {
      outcome.fail('trakt', NO_TRAKT_MATCH);
      return;
    }
    try {
      await getFlixorCore().trakt.removeRatings(items);
      outcome.succeed('trakt');
    } catch (e) {
      outcome.fail('trakt', e);
    }
  });
}

const RATING_TYPE: Record<WatchStateKind, 'movies' | 'shows' | 'seasons' | 'episodes'> = {
  movie: 'movies',
  show: 'shows',
  season: 'seasons',
  episode: 'episodes',
};

/** The user's Trakt rating (1-10). Null when unrated, Trakt isn't connected or the lookup fails. */
export async function getUserRating(target: WatchStateTarget): Promise<number | null> {
  if (!isTraktConnected()) return null;
  const t = await resolveWatchTarget(target);
  if (!traktIds(t)) return null;
  try {
    const items = await getFlixorCore().trakt.getRatings(RATING_TYPE[t.kind]);
    const match = items.find((item) => {
      if (t.kind === 'movie') return idsMatch(item.movie?.ids, t);
      if (!idsMatch(item.show?.ids, t)) return false;
      if (t.kind === 'show') return true;
      if (t.kind === 'season') return item.season?.number === t.seasonNumber;
      return item.episode?.season === t.seasonNumber && item.episode?.number === t.episodeNumber;
    });
    return match?.rating ?? null;
  } catch (e) {
    console.log('[WatchState] getUserRating error:', e);
    return null;
  }
}

/** Whether a movie or specific episode without a Plex copy is marked watched on this device. */
export function isWatchedLocally(target: WatchStateTarget): Promise<boolean> {
  return localLibrary.isWatched(localQuery(target));
}

/** Key for a watched-episode set. */
export function episodeWatchKey(season: number, episode: number): string {
  return `${season}:${episode}`;
}

/** Episodes of a show marked watched on this device, keyed with episodeWatchKey. */
export async function locallyWatchedEpisodes(show: { tmdbId?: number; imdbId?: string }, season?: number): Promise<Set<string>> {
  const imdb = show.imdbId?.toLowerCase();
  const entries = await localLibrary.watchedEntries();
  const keys = new Set<string>();
  for (const entry of entries) {
    if (entry.mediaType !== 'episode' || entry.seasonNumber == null || entry.episodeNumber == null) continue;
    const sameShow = (show.tmdbId != null && entry.tmdbId === show.tmdbId) || (!!imdb && entry.imdbId === imdb);
    if (!sameShow || (season != null && entry.seasonNumber !== season)) continue;
    keys.add(episodeWatchKey(entry.seasonNumber, entry.episodeNumber));
  }
  return keys;
}

/** Episodes of a show marked watched on Trakt, keyed with episodeWatchKey. Empty when unavailable. */
export async function traktWatchedEpisodes(show: { tmdbId?: number; imdbId?: string }): Promise<Set<string>> {
  const keys = new Set<string>();
  if (!isTraktWatchSyncEnabled()) return keys;
  try {
    const showId = await traktShowId({ kind: 'show', tmdbId: show.tmdbId, imdbId: show.imdbId });
    if (showId == null) return keys;
    const progress = await getFlixorCore().trakt.getShowProgress(showId);
    for (const season of progress.seasons) {
      for (const episode of season.episodes) {
        if (episode.completed) keys.add(episodeWatchKey(season.number, episode.number));
      }
    }
  } catch (e) {
    console.log('[WatchState] traktWatchedEpisodes error:', e);
  }
  return keys;
}
