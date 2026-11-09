/**
 * One place for mark watched and unwatched, remove from Continue Watching, start
 * over, and Trakt ratings. Each action is applied to every backend that owns state
 * for the item:
 *
 *   Plex:  items with a Plex key, or a show key plus season and episode numbers.
 *   Trakt: when Trakt is connected and "Auto-sync watched" is on. Ratings only
 *          need Trakt to be connected.
 *   Local: items with no Plex copy (TMDB and addon titles), kept in this browser.
 *
 * Every action resolves with a WatchStateResult (`.message` is ready for a toast)
 * and emits a change event. When nothing was applied it rejects with a
 * WatchStateError, which carries the same result.
 */
import { getSettings, saveSettings } from '@/state/settings';
import {
  getLocalHistory,
  isLocallyWatched as isStoredWatched,
  markLocallyWatched as markStoredWatched,
  removeLocalHistory,
  unmarkLocallyWatched as unmarkStoredWatched,
  type LocalHistoryEntry,
  type LocalWatchedRef,
} from '@/stremio/localHistory';
import { clearResumeState, getResumeState } from '@/stremio/resumeStore';
import { STORAGE_KEYS, readJson, tryWriteJson } from '@/stremio/storage';
import { API_BASE_URL } from '@/services/api';
import { plexBackendDir, plexBackendMetadata } from '@/services/plex_backend';
import { tmdbExternalIds, tmdbTvSeasonDetails, tmdbTvSeasons } from '@/services/tmdb';
import {
  TraktApiError,
  getTraktTokens,
  traktAddRatings,
  traktGetPlayback,
  traktGetRatings,
  traktItemHistory,
  traktLookupId,
  traktRemovePlayback,
  traktRemoveRatings,
  traktShowProgress,
  traktSyncHistoryAdd,
  traktSyncHistoryRemove,
} from '@/services/trakt';

export interface WatchTarget {
  kind: 'movie' | 'show' | 'season' | 'episode';
  plexRatingKey?: string;
  tmdbId?: number;
  imdbId?: string;
  traktId?: number;
  /** For seasons and episodes: the parent show's TMDB id. */
  showTmdbId?: number;
  /** For seasons and episodes: the parent show's IMDb id. */
  showImdbId?: string;
  /** For seasons and episodes: the parent show's Plex key, if known. */
  showPlexRatingKey?: string;
  tvdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
  title?: string;
}

export type WatchStateAction =
  | 'markWatched'
  | 'markUnwatched'
  | 'removeFromContinueWatching'
  | 'startOver'
  | 'rate'
  | 'removeRating';

export type WatchStateBackend = 'plex' | 'trakt' | 'local';

export interface WatchStateFailure {
  backend?: WatchStateBackend;
  message: string;
}

export interface WatchStateResult {
  action: WatchStateAction;
  target: WatchTarget;
  succeeded: WatchStateBackend[];
  failures: WatchStateFailure[];
  /** Nothing needed changing. Not an error. */
  noChanges: boolean;
  /** Short text for a toast. */
  message: string;
}

export class WatchStateError extends Error {
  readonly result: WatchStateResult;

  constructor(result: WatchStateResult) {
    super(result.message);
    this.name = 'WatchStateError';
    this.result = result;
  }
}

export interface WatchStateChange {
  action: WatchStateAction;
  target: WatchTarget;
  rating: number | null;
  backends: WatchStateBackend[];
}

const CHANGE_EVENT = 'flixor:watch-state-changed';

/** Calls `listener` after any action that changed something. Returns an unsubscribe. */
export function subscribeWatchState(listener: (change: WatchStateChange) => void): () => void {
  const handler = (event: Event) => listener((event as CustomEvent<WatchStateChange>).detail);
  window.addEventListener(CHANGE_EVENT, handler);
  return () => window.removeEventListener(CHANGE_EVENT, handler);
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

const BACKEND_NAME: Record<WatchStateBackend, string> = {
  plex: 'Plex',
  trakt: 'Trakt',
  local: 'this browser',
};

const NO_TRAKT_MATCH = "couldn't match on Trakt";

/** Target with show-level ids and season and episode numbers filled in. */
export interface ResolvedTarget extends WatchTarget {
  /** Movie or show ids. For a season or episode these are the show's. */
  titleTmdbId?: number;
  titleImdbId?: string;
  titleTvdbId?: number;
  titleTraktId?: number;
}

const isMovie = (t: WatchTarget) => t.kind === 'movie';

// --- Capabilities ---

export function isTraktConnected(): boolean {
  return getTraktTokens() != null;
}

function isTraktWatchSyncEnabled(): boolean {
  return isTraktConnected() && getSettings().traktAutoSyncWatched;
}

/** Ratings can be read and written. */
export function canRate(): boolean {
  return isTraktConnected();
}

// --- Plex calls ---

async function plexPost(path: string, ratingKey: string): Promise<void> {
  const response = await fetch(`${API_BASE_URL.replace(/\/$/, '')}/plex${path}`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ratingKey }),
  });
  if (!response.ok) throw new PlexActionError(response.status);
}

class PlexActionError extends Error {
  readonly status: number;

  constructor(status: number) {
    super(`Plex error ${status}`);
    this.status = status;
  }
}

async function plexMetadata(ratingKey: string): Promise<any | undefined> {
  try {
    const meta: any = await plexBackendMetadata(ratingKey);
    return meta?.MediaContainer?.Metadata?.[0];
  } catch {
    return undefined;
  }
}

async function plexChildKey(parentKey: string, index: number): Promise<string | undefined> {
  const dir: any = await plexBackendDir(`/library/metadata/${parentKey}/children`);
  const child = (dir?.MediaContainer?.Metadata || []).find((m: any) => Number(m.index) === index);
  return child?.ratingKey != null ? String(child.ratingKey) : undefined;
}

function guidIds(meta: any): { tmdbId?: number; imdbId?: string; tvdbId?: number } {
  const guids: string[] = (meta?.Guid || []).map((g: any) => String(g.id || ''));
  if (meta?.guid) guids.push(String(meta.guid));
  const pick = (...schemes: string[]) => {
    for (const guid of guids) {
      for (const scheme of schemes) {
        const match = new RegExp(`${scheme}://([^?/]+)`).exec(guid);
        if (match) return match[1];
      }
    }
    return undefined;
  };
  const tmdb = Number(pick('tmdb', 'themoviedb'));
  const tvdb = Number(pick('tvdb', 'thetvdb'));
  return {
    tmdbId: Number.isFinite(tmdb) && tmdb > 0 ? tmdb : undefined,
    imdbId: pick('imdb'),
    tvdbId: Number.isFinite(tvdb) && tvdb > 0 ? tvdb : undefined,
  };
}

// --- Target resolution ---

/** Fills in show keys, season and episode numbers, and title-level external ids. */
export async function resolveWatchTarget(target: WatchTarget, needTitleIds: boolean): Promise<ResolvedTarget> {
  const t: ResolvedTarget = { ...target };

  if (t.plexRatingKey && (t.kind === 'season' || t.kind === 'episode')) {
    const missingNumbers = t.kind === 'season'
      ? t.seasonNumber == null
      : t.seasonNumber == null || t.episodeNumber == null;
    if (missingNumbers || !t.showPlexRatingKey) {
      const meta = await plexMetadata(t.plexRatingKey);
      if (meta) {
        if (t.kind === 'season') {
          t.seasonNumber = t.seasonNumber ?? numberOrUndefined(meta.index);
          t.showPlexRatingKey = t.showPlexRatingKey ?? stringOrUndefined(meta.parentRatingKey);
        } else {
          t.seasonNumber = t.seasonNumber ?? numberOrUndefined(meta.parentIndex);
          t.episodeNumber = t.episodeNumber ?? numberOrUndefined(meta.index);
          t.showPlexRatingKey = t.showPlexRatingKey ?? stringOrUndefined(meta.grandparentRatingKey);
        }
      }
    }
  }

  if (!t.plexRatingKey && t.showPlexRatingKey) {
    if (t.kind === 'season' && t.seasonNumber != null) {
      t.plexRatingKey = await plexChildKey(t.showPlexRatingKey, t.seasonNumber);
    } else if (t.kind === 'episode' && t.seasonNumber != null && t.episodeNumber != null) {
      const seasonKey = await plexChildKey(t.showPlexRatingKey, t.seasonNumber);
      if (seasonKey) t.plexRatingKey = await plexChildKey(seasonKey, t.episodeNumber);
    }
  }

  if (t.kind === 'movie' || t.kind === 'show') {
    t.titleTmdbId = t.tmdbId;
    t.titleImdbId = t.imdbId;
    t.titleTvdbId = t.tvdbId;
    t.titleTraktId = t.traktId;
  } else {
    t.titleTmdbId = t.showTmdbId ?? t.tmdbId;
    t.titleImdbId = t.showImdbId ?? (t.showTmdbId == null ? t.imdbId : undefined);
    t.titleTraktId = t.traktId;
  }

  if (needTitleIds) {
    if (t.titleTmdbId == null && !t.titleImdbId) {
      const key = t.showPlexRatingKey ?? (t.kind === 'movie' || t.kind === 'show' ? t.plexRatingKey : undefined);
      if (key) {
        const meta = await plexMetadata(key);
        if (meta) {
          const ids = guidIds(meta);
          t.titleTmdbId = ids.tmdbId;
          t.titleImdbId = ids.imdbId;
          t.titleTvdbId = t.titleTvdbId ?? ids.tvdbId;
        }
      }
    }
    if (t.titleTmdbId == null && t.titleImdbId) {
      try {
        const hit = await traktLookupId('imdb', t.titleImdbId, isMovie(t) ? 'movie' : 'show');
        const ids = (isMovie(t) ? hit?.movie : hit?.show)?.ids;
        if (ids?.tmdb) t.titleTmdbId = ids.tmdb;
        if (ids?.trakt) t.titleTraktId = t.titleTraktId ?? ids.trakt;
      } catch {
        // Trakt can still match on the IMDb id.
      }
    }
    if (!t.titleImdbId && t.titleTmdbId != null) {
      try {
        const external: any = await tmdbExternalIds('', isMovie(t) ? 'movie' : 'tv', t.titleTmdbId);
        t.titleImdbId = external?.imdb_id || undefined;
        if (!isMovie(t) && external?.tvdb_id) t.titleTvdbId = t.titleTvdbId ?? external.tvdb_id;
      } catch {
        // Trakt can still match on the TMDB id.
      }
    }
  }
  return t;
}

function numberOrUndefined(value: unknown): number | undefined {
  const n = Number(value);
  return value != null && Number.isFinite(n) ? n : undefined;
}

function stringOrUndefined(value: unknown): string | undefined {
  return value != null && value !== '' ? String(value) : undefined;
}

// --- Trakt helpers ---

function traktIds(t: ResolvedTarget): Record<string, string | number> | undefined {
  if (t.titleTmdbId == null && !t.titleImdbId && t.titleTvdbId == null && t.titleTraktId == null) return undefined;
  const ids: Record<string, string | number> = {};
  if (t.titleImdbId) ids.imdb = t.titleImdbId;
  if (t.titleTmdbId != null) ids.tmdb = t.titleTmdbId;
  if (!isMovie(t) && t.titleTvdbId != null) ids.tvdb = t.titleTvdbId;
  if (t.titleTraktId != null) ids.trakt = t.titleTraktId;
  return ids;
}

/** Sync body for a resolved target. Undefined with no usable id or unknown numbers. */
export function traktSyncItems(t: ResolvedTarget, rating?: number): Record<string, unknown> | undefined {
  const ids = traktIds(t);
  if (!ids) return undefined;
  const rated = rating != null ? { rating } : {};
  switch (t.kind) {
    case 'movie':
      return { movies: [{ ids, ...rated }] };
    case 'show':
      return { shows: [{ ids, ...rated }] };
    case 'season':
      if (t.seasonNumber == null) return undefined;
      return { shows: [{ ids, seasons: [{ number: t.seasonNumber, ...rated }] }] };
    case 'episode':
      if (t.seasonNumber == null || t.episodeNumber == null) return undefined;
      return {
        shows: [{ ids, seasons: [{ number: t.seasonNumber, episodes: [{ number: t.episodeNumber, ...rated }] }] }],
      };
  }
}

function idsMatch(ids: any, t: ResolvedTarget): boolean {
  if (!ids) return false;
  if (t.titleTmdbId != null && ids.tmdb === t.titleTmdbId) return true;
  if (t.titleImdbId && ids.imdb && String(ids.imdb).toLowerCase() === t.titleImdbId.toLowerCase()) return true;
  if (t.titleTvdbId != null && ids.tvdb === t.titleTvdbId) return true;
  return t.titleTraktId != null && ids.trakt === t.titleTraktId;
}

async function traktTitleId(t: ResolvedTarget): Promise<number | undefined> {
  if (t.titleTraktId != null) return t.titleTraktId;
  const type = isMovie(t) ? 'movie' : 'show';
  const hit = t.titleTmdbId != null
    ? await traktLookupId('tmdb', t.titleTmdbId, type)
    : t.titleImdbId
      ? await traktLookupId('imdb', t.titleImdbId, type)
      : null;
  return (isMovie(t) ? hit?.movie : hit?.show)?.ids?.trakt ?? undefined;
}

function describeError(error: unknown, backend: WatchStateBackend): string {
  if (error instanceof TraktApiError) {
    if (error.status === 401) return 'sign-in expired';
    if (error.status === 429) return 'rate limited, try again shortly';
    if (error.status === 404) return NO_TRAKT_MATCH;
    return `error ${error.status}`;
  }
  if (error instanceof PlexActionError) {
    if (error.status === 404) return 'not supported by this server';
    if (error.status === 401) return 'sign-in expired';
    return `error ${error.status}`;
  }
  return backend === 'plex' ? 'server not reachable' : 'network error';
}

// --- Action runner ---

class Outcome {
  succeeded: WatchStateBackend[] = [];
  failures: WatchStateFailure[] = [];
  sawUnchanged = false;

  succeed(backend: WatchStateBackend) {
    if (!this.succeeded.includes(backend)) this.succeeded.push(backend);
  }

  fail(backend: WatchStateBackend, error: unknown) {
    const message = typeof error === 'string' ? error : describeError(error, backend);
    this.failures.push({ backend, message });
  }
}

const inFlight = new Set<string>();

function actionKey(t: WatchTarget): string {
  const id = t.plexRatingKey ?? t.showPlexRatingKey ?? t.showTmdbId ?? t.tmdbId ?? t.showImdbId ?? t.imdbId ?? t.title ?? '';
  return `${t.kind}:${id}:${t.seasonNumber ?? ''}:${t.episodeNumber ?? ''}`;
}

/** True while an action on this target is running. */
export function isWatchActionInFlight(target: WatchTarget): boolean {
  return inFlight.has(actionKey(target));
}

function failureText(failure: WatchStateFailure): string {
  return failure.backend ? `${BACKEND_NAME[failure.backend]}: ${failure.message}` : failure.message;
}

function buildResult(
  action: WatchStateAction,
  target: WatchTarget,
  outcome: Pick<Outcome, 'succeeded' | 'failures'>,
  noChanges: boolean,
): WatchStateResult {
  const { succeeded, failures } = outcome;
  let message: string;
  if (noChanges) {
    message = NO_CHANGE_TEXT[action];
  } else if (succeeded.length && !failures.length) {
    message = SUCCESS_TEXT[action];
  } else if (succeeded.length) {
    message = `${SUCCESS_TEXT[action]}, but ${failures.map(failureText).join('; ')}`;
  } else {
    message = `${FAILURE_TEXT[action]}: ${failures[0] ? failureText(failures[0]) : 'nothing to update'}`;
  }
  return { action, target, succeeded, failures, noChanges, message };
}

async function perform(
  action: WatchStateAction,
  target: WatchTarget,
  rating: number | null,
  body: (t: ResolvedTarget, outcome: Outcome) => Promise<void>,
): Promise<WatchStateResult> {
  const key = actionKey(target);
  if (inFlight.has(key)) {
    throw new WatchStateError(
      buildResult(action, target, { succeeded: [], failures: [{ message: 'another change to this item is in progress' }] }, false),
    );
  }
  inFlight.add(key);
  try {
    const resolved = await resolveWatchTarget(target, isTraktConnected() || !isPlexItem(target));
    const outcome = new Outcome();
    await body(resolved, outcome);

    const nothingHappened = !outcome.succeeded.length && !outcome.failures.length;
    if (nothingHappened && !outcome.sawUnchanged && action !== 'startOver' && action !== 'removeFromContinueWatching') {
      outcome.failures.push({ message: 'nothing to update for this item' });
    }
    const result = buildResult(action, resolved, outcome, !outcome.succeeded.length && !outcome.failures.length);

    if (result.succeeded.length) {
      const detail: WatchStateChange = { action, target: resolved, rating, backends: result.succeeded };
      window.dispatchEvent(new CustomEvent(CHANGE_EVENT, { detail }));
    }
    if (!result.succeeded.length && !result.noChanges) throw new WatchStateError(result);
    return result;
  } finally {
    inFlight.delete(key);
  }
}

function isPlexItem(t: WatchTarget): boolean {
  return t.plexRatingKey != null || t.showPlexRatingKey != null;
}

async function applyPlex(
  t: ResolvedTarget,
  outcome: Outcome,
  action: (ratingKey: string) => Promise<void>,
): Promise<void> {
  if (!isPlexItem(t)) return;
  if (!t.plexRatingKey) {
    outcome.fail('plex', `couldn't find this ${t.kind} on the server`);
    return;
  }
  try {
    await action(t.plexRatingKey);
    outcome.succeed('plex');
  } catch (error) {
    outcome.fail('plex', error);
  }
}

// --- Actions ---

/**
 * Marks a movie, episode, season or whole show watched. On Trakt only aired
 * episodes that aren't already watched are added, so repeated clicks don't add
 * duplicate plays.
 */
export async function markWatched(target: WatchTarget): Promise<WatchStateResult> {
  return perform('markWatched', target, null, async (t, outcome) => {
    await applyPlex(t, outcome, (key) => plexPost('/scrobble', key));
    if (isTraktWatchSyncEnabled()) await addTraktHistory(t, outcome);
    if (!isPlexItem(t)) {
      try {
        await markLocallyWatched(t);
        outcome.succeed('local');
      } catch (error) {
        outcome.fail('local', error instanceof Error ? error.message : 'unknown error');
      }
    }
    clearLocalProgress(t);
  });
}

/** Reverses {@link markWatched} on every backend. */
export async function markUnwatched(target: WatchTarget): Promise<WatchStateResult> {
  return perform('markUnwatched', target, null, async (t, outcome) => {
    await applyPlex(t, outcome, (key) => plexPost('/unscrobble', key));
    if (isTraktWatchSyncEnabled()) {
      const items = traktSyncItems(t);
      if (items) {
        try {
          await traktSyncHistoryRemove(items);
          outcome.succeed('trakt');
        } catch (error) {
          outcome.fail('trakt', error);
        }
      } else {
        outcome.fail('trakt', NO_TRAKT_MATCH);
      }
    }
    if (!isPlexItem(t)) {
      if (removeLocallyWatched(t) > 0) outcome.succeed('local');
      else outcome.sawUnchanged = true;
    }
  });
}

/** Removes an item from Continue Watching. Watched state is unchanged. */
export async function removeFromContinueWatching(target: WatchTarget): Promise<WatchStateResult> {
  return perform('removeFromContinueWatching', target, null, async (t, outcome) => {
    await applyPlex(t, outcome, (key) => plexPost('/continue/remove', key));
    if (isTraktWatchSyncEnabled()) recordPlaybackRemoval(await removeTraktPlayback(t, false), outcome);
    // A Trakt next-up card has nothing to delete on Trakt, so this is how it stays gone.
    if (clearLocalProgress(t) > 0) outcome.succeed('local');
    if (recordDismissal(t)) outcome.succeed('local');
  });
}

/**
 * Resets saved progress on Plex and Trakt so the caller can play from 0. Watched
 * state is unchanged. A `noChanges` result means there was no saved progress.
 */
export async function startOver(target: WatchTarget): Promise<WatchStateResult> {
  return perform('startOver', target, null, async (t, outcome) => {
    if (t.kind === 'movie' || t.kind === 'episode') {
      await applyPlex(t, outcome, (key) => plexPost('/progress/reset', key));
    }
    if (isTraktWatchSyncEnabled()) recordPlaybackRemoval(await removeTraktPlayback(t, false), outcome);
    if (clearLocalProgress(t) > 0) outcome.succeed('local');
  });
}

/** Rates on Trakt from 1 to 10, or clears the rating with null. */
export async function rate(target: WatchTarget, rating: number | null): Promise<WatchStateResult> {
  const action: WatchStateAction = rating == null ? 'removeRating' : 'rate';
  if (rating != null && (!Number.isInteger(rating) || rating < 1 || rating > 10)) {
    throw new WatchStateError(
      buildResult(action, target, { succeeded: [], failures: [{ backend: 'trakt', message: 'rating must be 1-10' }] }, false),
    );
  }
  if (!canRate()) {
    throw new WatchStateError(
      buildResult(action, target, { succeeded: [], failures: [{ backend: 'trakt', message: 'connect Trakt in Settings' }] }, false),
    );
  }
  return perform(action, target, rating, async (t, outcome) => {
    const items = traktSyncItems(t, rating ?? undefined);
    if (!items) {
      outcome.fail('trakt', NO_TRAKT_MATCH);
      return;
    }
    try {
      if (rating == null) {
        await traktRemoveRatings(items);
        outcome.succeed('trakt');
      } else {
        const result = await traktAddRatings(items);
        if (countAll(result.added) === 0 && countNotFound(result.not_found) > 0) {
          outcome.fail('trakt', NO_TRAKT_MATCH);
        } else {
          outcome.succeed('trakt');
        }
      }
    } catch (error) {
      outcome.fail('trakt', error);
    }
    ratingsCache.delete(ratingType(t.kind));
  });
}

// --- Ratings read ---

type RatingType = 'movies' | 'shows' | 'seasons' | 'episodes';

const RATINGS_TTL = 5 * 60 * 1000;
const ratingsCache = new Map<RatingType, { fetchedAt: number; items: Promise<any[]> }>();

function ratingType(kind: WatchTarget['kind']): RatingType {
  switch (kind) {
    case 'movie': return 'movies';
    case 'show': return 'shows';
    case 'season': return 'seasons';
    case 'episode': return 'episodes';
  }
}

function userRatings(type: RatingType): Promise<any[]> {
  const cached = ratingsCache.get(type);
  if (cached && Date.now() - cached.fetchedAt < RATINGS_TTL) return cached.items;
  const items = traktGetRatings(type).catch((error) => {
    ratingsCache.delete(type);
    throw error;
  });
  ratingsCache.set(type, { fetchedAt: Date.now(), items });
  return items;
}

/** The user's Trakt rating from 1 to 10, or null when unrated or unavailable. */
export async function getRating(target: WatchTarget): Promise<number | null> {
  if (!canRate()) return null;
  const t = await resolveWatchTarget(target, true);
  if (!traktIds(t)) return null;
  let items: any[];
  try {
    items = await userRatings(ratingType(t.kind));
  } catch {
    return null;
  }
  const match = items.find((item) => {
    switch (t.kind) {
      case 'movie':
        return idsMatch(item.movie?.ids, t);
      case 'show':
        return idsMatch(item.show?.ids, t);
      case 'season':
        return idsMatch(item.show?.ids, t) && item.season?.number === t.seasonNumber;
      case 'episode':
        return idsMatch(item.show?.ids, t)
          && item.episode?.season === t.seasonNumber
          && item.episode?.number === t.episodeNumber;
    }
  });
  return typeof match?.rating === 'number' ? match.rating : null;
}

// --- Trakt history and playback ---

function countAll(counts?: Record<string, number>): number {
  return Object.values(counts ?? {}).reduce((sum, n) => sum + (typeof n === 'number' ? n : 0), 0);
}

function countNotFound(notFound?: Record<string, unknown[]>): number {
  return Object.values(notFound ?? {}).reduce((sum, list) => sum + (Array.isArray(list) ? list.length : 0), 0);
}

async function addTraktHistory(t: ResolvedTarget, outcome: Outcome): Promise<void> {
  const ids = traktIds(t);
  if (!ids) {
    outcome.fail('trakt', NO_TRAKT_MATCH);
    return;
  }

  let items: Record<string, unknown>;
  try {
    const traktId = await traktTitleId(t);
    if (traktId == null) {
      outcome.fail('trakt', NO_TRAKT_MATCH);
      return;
    }

    if (t.kind === 'movie') {
      const history = await traktItemHistory('movies', traktId, 1);
      if (history.length > 0) {
        outcome.sawUnchanged = true;
        return;
      }
      items = { movies: [{ ids }] };
    } else {
      const progress = await traktShowProgress(traktId);
      const missing = unwatchedEpisodes(progress, t);
      if (!missing) {
        outcome.fail('trakt', 'season or episode not known yet');
        return;
      }
      if (!missing.length) {
        if (progress.aired === 0 && t.kind === 'show') outcome.fail('trakt', 'no aired episodes on Trakt');
        else outcome.sawUnchanged = true;
        return;
      }
      const bySeason = new Map<number, number[]>();
      for (const { season, episode } of missing) {
        bySeason.set(season, [...(bySeason.get(season) ?? []), episode]);
      }
      items = {
        shows: [{
          ids,
          seasons: [...bySeason.entries()]
            .sort(([a], [b]) => a - b)
            .map(([number, episodes]) => ({ number, episodes: episodes.map((n) => ({ number: n })) })),
        }],
      };
    }
  } catch (error) {
    outcome.fail('trakt', error);
    return;
  }

  try {
    const result = await traktSyncHistoryAdd(items);
    if (countAll(result.added) === 0 && countNotFound(result.not_found) > 0) {
      outcome.fail('trakt', NO_TRAKT_MATCH);
      return;
    }
    outcome.succeed('trakt');
  } catch (error) {
    outcome.fail('trakt', error);
    return;
  }

  const removal = await removeTraktPlayback(t, true);
  if (removal.failed > 0 || removal.fetchFailed) outcome.fail('trakt', "couldn't clear saved progress");
}

function unwatchedEpisodes(
  progress: { seasons?: Array<{ number: number; episodes: Array<{ number: number; completed: boolean }> }> },
  t: ResolvedTarget,
): Array<{ season: number; episode: number }> | undefined {
  const seasons = progress.seasons ?? [];
  const incomplete = (season: (typeof seasons)[number]) =>
    season.episodes.filter((e) => !e.completed).map((e) => ({ season: season.number, episode: e.number }));

  switch (t.kind) {
    case 'movie':
      return [];
    case 'show':
      return seasons.filter((s) => s.number > 0).flatMap(incomplete);
    case 'season': {
      if (t.seasonNumber == null) return undefined;
      const season = seasons.find((s) => s.number === t.seasonNumber);
      return season ? incomplete(season) : [];
    }
    case 'episode': {
      if (t.seasonNumber == null || t.episodeNumber == null) return undefined;
      const listed = seasons
        .find((s) => s.number === t.seasonNumber)
        ?.episodes.find((e) => e.number === t.episodeNumber);
      return listed?.completed ? [] : [{ season: t.seasonNumber, episode: t.episodeNumber }];
    }
  }
}

interface PlaybackRemoval {
  removed: number;
  failed: number;
  fetchFailed: boolean;
}

function recordPlaybackRemoval(removal: PlaybackRemoval, outcome: Outcome) {
  if (removal.fetchFailed) outcome.fail('trakt', "couldn't read saved progress");
  else if (removal.failed > 0) outcome.fail('trakt', `couldn't remove ${removal.failed} saved progress entries`);
  if (removal.removed > 0) outcome.succeed('trakt');
}

const TRAKT_WRITE_SPACING_MS = 1100;
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Deletes paused entries matching the target, spaced for Trakt's write limit. */
async function removeTraktPlayback(t: ResolvedTarget, afterWrite: boolean): Promise<PlaybackRemoval> {
  const removal: PlaybackRemoval = { removed: 0, failed: 0, fetchFailed: false };
  if (!isTraktWatchSyncEnabled() || !traktIds(t)) return removal;

  let entries;
  try {
    entries = await traktGetPlayback(isMovie(t) ? 'movies' : 'episodes');
  } catch {
    removal.fetchFailed = true;
    return removal;
  }

  const matching = entries.filter((entry) => {
    switch (t.kind) {
      case 'movie':
        return idsMatch(entry.movie?.ids, t);
      case 'show':
        return idsMatch(entry.show?.ids, t);
      case 'season':
        return t.seasonNumber != null && idsMatch(entry.show?.ids, t) && entry.episode?.season === t.seasonNumber;
      case 'episode':
        return t.seasonNumber != null
          && t.episodeNumber != null
          && idsMatch(entry.show?.ids, t)
          && entry.episode?.season === t.seasonNumber
          && entry.episode?.number === t.episodeNumber;
    }
  });

  let needsSpacing = afterWrite;
  for (const entry of matching) {
    if (needsSpacing) await sleep(TRAKT_WRITE_SPACING_MS);
    needsSpacing = true;
    try {
      await traktRemovePlayback(entry.id);
      removal.removed += 1;
    } catch {
      removal.failed += 1;
    }
  }
  return removal;
}

// --- Continue Watching dismissals ---

const MAX_DISMISSALS = 300;

/** Key for one Continue Watching card, shared by the service and dismissals. */
export function continueWatchingRowKey(item: {
  isMovie: boolean;
  tmdbId: number;
  seasonNumber?: number;
  episodeNumber?: number;
}): string {
  return item.isMovie
    ? `tmdb:movie:${item.tmdbId}`
    : `tmdb:tv:${item.tmdbId}:${item.seasonNumber ?? -1}:${item.episodeNumber ?? -1}`;
}

function recordDismissal(t: ResolvedTarget): boolean {
  if (t.titleTmdbId == null || (t.kind !== 'movie' && t.kind !== 'episode')) return false;
  const key = continueWatchingRowKey({
    isMovie: t.kind === 'movie',
    tmdbId: t.titleTmdbId,
    seasonNumber: t.seasonNumber,
    episodeNumber: t.episodeNumber,
  });
  const entries = Object.entries({ ...getSettings().continueWatchingTraktDismissals, [key]: Date.now() })
    .sort(([, a], [, b]) => b - a)
    .slice(0, MAX_DISMISSALS);
  saveSettings({ continueWatchingTraktDismissals: Object.fromEntries(entries) });
  return true;
}

// --- Local state, for items with no Plex copy ---
// Shares the addon platform's stores, so the player and this service agree.

function watchedRef(t: ResolvedTarget, seasonNumber?: number, episodeNumber?: number): LocalWatchedRef {
  return {
    mediaType: isMovie(t) ? 'movie' : 'episode',
    tmdbId: t.titleTmdbId,
    imdbId: t.titleImdbId,
    seasonNumber,
    episodeNumber,
  };
}

async function airedEpisodes(tvId: number, season: number): Promise<number[]> {
  const data: any = await tmdbTvSeasonDetails('', tvId, season);
  const today = new Date().toISOString().slice(0, 10);
  return (data?.episodes || [])
    .filter((e: any) => e.air_date && e.air_date <= today)
    .map((e: any) => Number(e.episode_number));
}

async function markLocallyWatched(t: ResolvedTarget): Promise<void> {
  if (t.titleTmdbId == null && !t.titleImdbId) throw new Error('no TMDB or IMDb id');

  if (t.kind === 'movie') {
    markStoredWatched(watchedRef(t));
    return;
  }
  if (t.kind === 'episode') {
    if (t.seasonNumber == null || t.episodeNumber == null) throw new Error('season or episode not known yet');
    markStoredWatched(watchedRef(t, t.seasonNumber, t.episodeNumber));
    return;
  }

  if (t.titleTmdbId == null) throw new Error('no TMDB id');
  let seasons: number[];
  if (t.kind === 'season') {
    if (t.seasonNumber == null) throw new Error('season not known yet');
    seasons = [t.seasonNumber];
  } else {
    const details: any = await tmdbTvSeasons('', t.titleTmdbId);
    seasons = (details?.seasons || []).map((s: any) => Number(s.season_number)).filter((n: number) => n > 0);
  }
  let marked = 0;
  for (const season of seasons) {
    const numbers = await airedEpisodes(t.titleTmdbId, season).catch(() => [] as number[]);
    for (const episode of numbers) {
      markStoredWatched(watchedRef(t, season, episode));
      marked += 1;
    }
  }
  if (!marked) throw new Error('no aired episodes found');
}

/** Stored id forms for a show: `episode:tmdb:1:` and `episode:imdb:tt1:`. */
function episodeKeyPrefixes(show: { tmdbId?: number; imdbId?: string }): string[] {
  return [
    show.tmdbId != null ? `episode:tmdb:${show.tmdbId}:` : undefined,
    show.imdbId ? `episode:imdb:${show.imdbId.toLowerCase()}:` : undefined,
  ].filter((prefix): prefix is string => !!prefix);
}

function removeLocallyWatched(t: ResolvedTarget): number {
  if (t.kind === 'movie' || t.kind === 'episode') {
    const ref = watchedRef(t, t.seasonNumber, t.episodeNumber);
    if (!isStoredWatched(ref)) return 0;
    unmarkStoredWatched(ref);
    return 1;
  }
  const watched = readJson<Record<string, number>>(STORAGE_KEYS.watched, {});
  const prefixes = episodeKeyPrefixes({ tmdbId: t.titleTmdbId, imdbId: t.titleImdbId });
  const season = t.kind === 'season' ? `${t.seasonNumber}:` : '';
  const keys = Object.keys(watched).filter((key) => prefixes.some((prefix) => key.startsWith(prefix + season)));
  for (const key of keys) delete watched[key];
  if (keys.length) tryWriteJson(STORAGE_KEYS.watched, watched);
  return keys.length;
}

/** Whether a movie or episode is marked watched in this browser. */
export async function isWatchedLocally(target: WatchTarget): Promise<boolean> {
  const t = await resolveWatchTarget(target, true);
  if (t.kind !== 'movie' && t.kind !== 'episode') return false;
  return isStoredWatched(watchedRef(t, t.seasonNumber, t.episodeNumber));
}

/** `season:episode` strings marked watched in this browser for a show. */
export function locallyWatchedEpisodes(show: { tmdbId?: number; imdbId?: string }, season?: number): Set<string> {
  const prefixes = episodeKeyPrefixes(show);
  const watched = new Set<string>();
  for (const key of Object.keys(readJson<Record<string, number>>(STORAGE_KEYS.watched, {}))) {
    const prefix = prefixes.find((p) => key.startsWith(p));
    if (!prefix) continue;
    const pair = key.slice(prefix.length);
    if (season == null || pair.startsWith(`${season}:`)) watched.add(pair);
  }
  return watched;
}

/** Removes saved addon progress for a target. Returns how many entries were removed. */
function clearLocalProgress(t: ResolvedTarget): number {
  if (t.titleTmdbId == null && !t.titleImdbId) return 0;
  if (t.kind === 'season' && t.seasonNumber == null) return 0;
  if (t.kind === 'episode' && (t.seasonNumber == null || t.episodeNumber == null)) return 0;

  const matchesTitle = (entry: LocalHistoryEntry) =>
    (t.titleTmdbId != null && entry.tmdbId === t.titleTmdbId)
    || (!!t.titleImdbId && entry.imdbId?.toLowerCase() === t.titleImdbId.toLowerCase());

  const entries = getLocalHistory().filter((entry) => {
    if ((entry.mediaType === 'movie') !== isMovie(t) || !matchesTitle(entry)) return false;
    if (t.kind === 'season') return entry.seasonNumber === t.seasonNumber;
    if (t.kind === 'episode') return entry.seasonNumber === t.seasonNumber && entry.episodeNumber === t.episodeNumber;
    return true;
  });
  for (const entry of entries) {
    removeLocalHistory(entry.contentKey);
    clearResumeState(entry.contentKey);
  }

  // A resume point can exist with no history entry, so clear the exact keys too.
  let resumed = 0;
  if (t.kind === 'movie' || t.kind === 'episode') {
    for (const baseId of [t.titleImdbId, t.titleTmdbId != null ? `tmdb:${t.titleTmdbId}` : undefined]) {
      if (!baseId) continue;
      const key = t.kind === 'movie' ? `movie:${baseId}` : `series:${baseId}:${t.seasonNumber}:${t.episodeNumber}`;
      if (getResumeState(key)) {
        clearResumeState(key);
        resumed += 1;
      }
    }
  }
  return entries.length + resumed;
}
