/**
 * Watch progress and watched marks for addon titles, ported from LocalLibraryStore.swift.
 * These titles often have no Plex copy to scrobble, so state is kept in this browser.
 */
import { STORAGE_KEYS, createChangeNotifier, readJson, tryWriteJson } from './storage';

export interface LocalHistoryEntry {
  contentKey: string;
  mediaType: 'movie' | 'episode';
  title: string;
  episodeTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  imdbId?: string;
  tmdbId?: number;
  posterUrl?: string;
  backdropUrl?: string;
  positionMs: number;
  durationMs: number;
  updatedAt: number;
}

export type LocalHistoryItem = Omit<LocalHistoryEntry, 'positionMs' | 'durationMs' | 'updatedAt'>;

export interface LocalWatchedRef {
  mediaType: 'movie' | 'episode';
  tmdbId?: number;
  imdbId?: string;
  seasonNumber?: number;
  episodeNumber?: number;
}

type HistoryIndex = Record<string, LocalHistoryEntry>;

/** Treated as finished, so it drops out of Continue Watching. */
const COMPLETION_THRESHOLD = 0.9;
/** A title the user immediately backed out of should not clutter the row. */
const MINIMUM_POSITION_MS = 15_000;
/** Only rewrite once the position has really moved. */
const WRITE_INTERVAL_MS = 15_000;
const MAX_ENTRIES = 500;

const historyChanges = createChangeNotifier(STORAGE_KEYS.history);
export const subscribeLocalHistory = historyChanges.subscribe;

const readHistory = () => readJson<HistoryIndex>(STORAGE_KEYS.history, {});

function writeHistory(index: HistoryIndex): void {
  tryWriteJson(STORAGE_KEYS.history, index);
  historyChanges.notify();
}

/** Most recently watched first. */
export function getLocalHistory(): LocalHistoryEntry[] {
  return Object.values(readHistory()).sort((a, b) => b.updatedAt - a.updatedAt);
}

export function getLocalHistoryEntry(contentKey: string): LocalHistoryEntry | null {
  return readHistory()[contentKey] ?? null;
}

/**
 * Records playback progress, removing the entry once the title is effectively finished.
 * Pass `force` when playback stops so the final position is always saved.
 */
export function recordLocalProgress(
  item: LocalHistoryItem,
  positionMs: number,
  durationMs: number,
  options: { force?: boolean } = {},
): void {
  if (durationMs <= 0) return;
  if (positionMs / durationMs >= COMPLETION_THRESHOLD) {
    removeLocalHistory(item.contentKey);
    return;
  }
  if (positionMs < MINIMUM_POSITION_MS) return;

  const index = readHistory();
  const existing = index[item.contentKey];
  if (!options.force && existing && Math.abs(positionMs - existing.positionMs) < WRITE_INTERVAL_MS) return;

  index[item.contentKey] = { ...item, positionMs, durationMs, updatedAt: Date.now() };
  const kept = Object.values(index).sort((a, b) => b.updatedAt - a.updatedAt).slice(0, MAX_ENTRIES);
  writeHistory(Object.fromEntries(kept.map((entry) => [entry.contentKey, entry])));
}

export function removeLocalHistory(contentKey: string): void {
  const index = readHistory();
  if (!index[contentKey]) return;
  delete index[contentKey];
  writeHistory(index);
}

export function clearLocalHistory(): void {
  writeHistory({});
}

/** `movie:tmdb:603`, `episode:imdb:tt0903747:1:2`. Null without a usable id. */
export function localWatchedKey(ref: LocalWatchedRef): string | null {
  const id = ref.tmdbId ? `tmdb:${ref.tmdbId}` : ref.imdbId ? `imdb:${ref.imdbId.toLowerCase()}` : null;
  if (!id) return null;
  if (ref.mediaType === 'movie') return `movie:${id}`;
  if (ref.seasonNumber == null || ref.episodeNumber == null) return null;
  return `episode:${id}:${ref.seasonNumber}:${ref.episodeNumber}`;
}

const readWatched = () => readJson<Record<string, number>>(STORAGE_KEYS.watched, {});

export function isLocallyWatched(ref: LocalWatchedRef): boolean {
  const key = localWatchedKey(ref);
  return Boolean(key && readWatched()[key]);
}

export function markLocallyWatched(ref: LocalWatchedRef): void {
  const key = localWatchedKey(ref);
  if (!key) return;
  tryWriteJson(STORAGE_KEYS.watched, { ...readWatched(), [key]: Date.now() });
}

export function unmarkLocallyWatched(ref: LocalWatchedRef): void {
  const key = localWatchedKey(ref);
  if (!key) return;
  const watched = readWatched();
  if (!watched[key]) return;
  delete watched[key];
  tryWriteJson(STORAGE_KEYS.watched, watched);
}
