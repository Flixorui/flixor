/**
 * Watch history, watched items and watchlist stored on this device, per profile.
 * macOS reference: Services/Stremio/LocalLibraryStore.swift
 *
 * Backs Continue Watching, My List and mark-watched when there is no Plex server
 * and no guarantee Trakt is linked.
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { getProfileKey, PROFILE_SCOPED_KEYS } from './ProfileStorage';

export type LocalMediaType = 'movie' | 'episode';

/** What the player knows about the item it is reporting progress for. */
export interface LocalPlaybackItem {
  /** Same key as the Stremio resume state. */
  contentKey: string;
  mediaType: LocalMediaType;
  /** Movie title, or the series title for episodes. */
  title: string;
  episodeTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  imdbId?: string;
  /** Movie TMDB id, or the show's TMDB id for episodes. */
  tmdbId?: number;
  posterUrl?: string;
  backdropUrl?: string;
}

export interface LocalWatchHistoryEntry extends LocalPlaybackItem {
  positionMs: number;
  durationMs: number;
  updatedAt: number;
}

export interface LocalWatchedEntry {
  key: string;
  mediaType: LocalMediaType;
  /** Movie TMDB id, or the show's TMDB id for episodes. */
  tmdbId?: number;
  /** Movie IMDb id, or the show's IMDb id for episodes. Lowercase. */
  imdbId?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  watchedAt: number;
}

export interface LocalWatchlistEntry {
  /** Canonical media id, e.g. `tmdb:movie:123`. */
  id: string;
  title: string;
  type: 'movie' | 'show';
  posterUrl?: string;
  backdropUrl?: string;
  year?: number;
  imdbId?: string;
  tmdbId?: number;
  addedAt: number;
}

/** Identifies a title, and optionally narrows to a season or episode. */
export interface LocalTitleQuery {
  mediaType: LocalMediaType;
  tmdbId?: number;
  imdbId?: string;
  /** Omit to match every episode of the show. */
  season?: number;
  /** Omit to match every episode of the season. */
  episode?: number;
}

export type LocalLibraryChange = 'history' | 'watched' | 'watchlist';

/** Treated as finished; drops out of Continue Watching. */
const COMPLETION_THRESHOLD = 0.9;
/** Ignore the first seconds so a title the user backed out of doesn't clutter the row. */
const MINIMUM_POSITION_MS = 15_000;
/** Only rewrite the index once the position has moved this far. */
const WRITE_INTERVAL_MS = 15_000;

type Index<T> = Record<string, T>;

function normalizeWatchlistId(id: string): string {
  return id.trim().toLowerCase();
}

/**
 * `movie:tmdb:603`, `movie:imdb:tt0133093`, `episode:tmdb:1399:1:2`. TMDB is preferred so
 * the same title marked from different screens collapses to one entry. Null when there
 * is no usable id or episode numbers are missing.
 */
export function localWatchedKey(query: LocalTitleQuery): string | null {
  const idPart =
    query.tmdbId != null ? `tmdb:${query.tmdbId}` : query.imdbId ? `imdb:${query.imdbId.toLowerCase()}` : null;
  if (!idPart) return null;
  if (query.mediaType === 'movie') return `movie:${idPart}`;
  if (query.season == null || query.episode == null) return null;
  return `episode:${idPart}:${query.season}:${query.episode}`;
}

function matches(
  entry: { mediaType: LocalMediaType; tmdbId?: number; imdbId?: string; seasonNumber?: number; episodeNumber?: number },
  query: LocalTitleQuery
): boolean {
  if (entry.mediaType !== query.mediaType) return false;
  const imdb = query.imdbId?.toLowerCase();
  const sameTitle =
    (query.tmdbId != null && entry.tmdbId === query.tmdbId) || (!!imdb && entry.imdbId?.toLowerCase() === imdb);
  if (!sameTitle) return false;
  if (query.mediaType === 'movie') return true;
  if (query.season != null && entry.seasonNumber !== query.season) return false;
  if (query.episode != null && entry.episodeNumber !== query.episode) return false;
  return true;
}

class LocalLibrary {
  private listeners = new Set<(change: LocalLibraryChange) => void>();
  /** Every operation runs in turn, so overlapping read-modify-writes can't lose data. */
  private queue: Promise<unknown> = Promise.resolve();

  private enqueue<T>(work: () => Promise<T>): Promise<T> {
    const result = this.queue.then(work, work);
    this.queue = result.catch(() => undefined);
    return result;
  }

  private async read<T>(baseKey: string): Promise<Index<T>> {
    try {
      const raw = await AsyncStorage.getItem(getProfileKey(baseKey));
      return raw ? (JSON.parse(raw) as Index<T>) : {};
    } catch (e) {
      console.log('[LocalLibrary] read error:', e);
      return {};
    }
  }

  private async write<T>(baseKey: string, index: Index<T>): Promise<void> {
    await AsyncStorage.setItem(getProfileKey(baseKey), JSON.stringify(index));
  }

  private notify(change: LocalLibraryChange): void {
    this.listeners.forEach((listener) => listener(change));
  }

  addListener(listener: (change: LocalLibraryChange) => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  // Watch history

  /** Most recently watched first. */
  watchHistory(): Promise<LocalWatchHistoryEntry[]> {
    return this.enqueue(async () => {
      const index = await this.read<LocalWatchHistoryEntry>(PROFILE_SCOPED_KEYS.LOCAL_WATCH_HISTORY);
      return Object.values(index).sort((a, b) => b.updatedAt - a.updatedAt);
    });
  }

  historyEntry(contentKey: string): Promise<LocalWatchHistoryEntry | null> {
    return this.enqueue(async () => {
      const index = await this.read<LocalWatchHistoryEntry>(PROFILE_SCOPED_KEYS.LOCAL_WATCH_HISTORY);
      return index[contentKey] ?? null;
    });
  }

  /**
   * Records progress for a stream. Removes the entry once it is effectively finished
   * and ignores trivially short positions.
   * @param force bypasses the write interval; use when playback stops.
   */
  recordProgress(
    item: LocalPlaybackItem,
    positionMs: number,
    durationMs: number,
    options?: { force?: boolean }
  ): Promise<void> {
    return this.enqueue(async () => {
      if (durationMs <= 0) return;
      const key = PROFILE_SCOPED_KEYS.LOCAL_WATCH_HISTORY;
      const index = await this.read<LocalWatchHistoryEntry>(key);
      const existing = index[item.contentKey];

      if (positionMs / durationMs >= COMPLETION_THRESHOLD) {
        if (existing) {
          delete index[item.contentKey];
          await this.write(key, index);
          this.notify('history');
        }
        return;
      }
      if (positionMs < MINIMUM_POSITION_MS) return;
      if (!options?.force && existing && Math.abs(positionMs - existing.positionMs) < WRITE_INTERVAL_MS) return;

      index[item.contentKey] = { ...item, positionMs, durationMs, updatedAt: Date.now() };
      await this.write(key, index);
      this.notify('history');
    });
  }

  removeHistory(contentKey: string): Promise<void> {
    return this.enqueue(async () => {
      const key = PROFILE_SCOPED_KEYS.LOCAL_WATCH_HISTORY;
      const index = await this.read<LocalWatchHistoryEntry>(key);
      if (!index[contentKey]) return;
      delete index[contentKey];
      await this.write(key, index);
      this.notify('history');
    });
  }

  /** Removes every history entry for a title. Returns the removed content keys. */
  removeHistoryMatching(query: LocalTitleQuery): Promise<string[]> {
    return this.enqueue(async () => {
      const key = PROFILE_SCOPED_KEYS.LOCAL_WATCH_HISTORY;
      const index = await this.read<LocalWatchHistoryEntry>(key);
      const removed = Object.values(index)
        .filter((entry) => matches(entry, query))
        .map((entry) => entry.contentKey);
      if (removed.length === 0) return [];
      removed.forEach((contentKey) => delete index[contentKey]);
      await this.write(key, index);
      this.notify('history');
      return removed;
    });
  }

  clearHistory(): Promise<void> {
    return this.enqueue(async () => {
      await this.write(PROFILE_SCOPED_KEYS.LOCAL_WATCH_HISTORY, {});
      this.notify('history');
    });
  }

  // Watched

  /** Everything marked watched on this device, most recent first. */
  watchedEntries(): Promise<LocalWatchedEntry[]> {
    return this.enqueue(async () => {
      const index = await this.read<LocalWatchedEntry>(PROFILE_SCOPED_KEYS.LOCAL_WATCHED);
      return Object.values(index).sort((a, b) => b.watchedAt - a.watchedAt);
    });
  }

  /** Adds or refreshes watched entries in one write. Queries with no usable id are skipped. */
  markWatched(queries: LocalTitleQuery[], watchedAt: number = Date.now()): Promise<number> {
    return this.enqueue(async () => {
      const key = PROFILE_SCOPED_KEYS.LOCAL_WATCHED;
      const index = await this.read<LocalWatchedEntry>(key);
      let added = 0;
      for (const query of queries) {
        const entryKey = localWatchedKey(query);
        if (!entryKey) continue;
        index[entryKey] = {
          key: entryKey,
          mediaType: query.mediaType,
          tmdbId: query.tmdbId,
          imdbId: query.imdbId?.toLowerCase(),
          seasonNumber: query.season,
          episodeNumber: query.episode,
          watchedAt,
        };
        added += 1;
      }
      if (added === 0) return 0;
      await this.write(key, index);
      this.notify('watched');
      return added;
    });
  }

  /** Removes watched entries for a title. Returns how many were removed. */
  removeWatched(query: LocalTitleQuery): Promise<number> {
    return this.enqueue(async () => {
      const key = PROFILE_SCOPED_KEYS.LOCAL_WATCHED;
      const index = await this.read<LocalWatchedEntry>(key);
      const keys = Object.values(index)
        .filter((entry) => matches(entry, query))
        .map((entry) => entry.key);
      if (keys.length === 0) return 0;
      keys.forEach((entryKey) => delete index[entryKey]);
      await this.write(key, index);
      this.notify('watched');
      return keys.length;
    });
  }

  /** Whether a movie or a specific episode is marked watched on this device. */
  isWatched(query: LocalTitleQuery): Promise<boolean> {
    return this.enqueue(async () => {
      if (query.mediaType === 'episode' && (query.season == null || query.episode == null)) return false;
      const index = await this.read<LocalWatchedEntry>(PROFILE_SCOPED_KEYS.LOCAL_WATCHED);
      return Object.values(index).some((entry) => matches(entry, query));
    });
  }

  // Watchlist

  /** Most recently added first. */
  watchlist(): Promise<LocalWatchlistEntry[]> {
    return this.enqueue(async () => {
      const index = await this.read<LocalWatchlistEntry>(PROFILE_SCOPED_KEYS.LOCAL_WATCHLIST);
      return Object.values(index).sort((a, b) => b.addedAt - a.addedAt);
    });
  }

  isInWatchlist(id: string): Promise<boolean> {
    return this.enqueue(async () => {
      const index = await this.read<LocalWatchlistEntry>(PROFILE_SCOPED_KEYS.LOCAL_WATCHLIST);
      return index[normalizeWatchlistId(id)] !== undefined;
    });
  }

  addToWatchlist(entry: Omit<LocalWatchlistEntry, 'addedAt'> & { addedAt?: number }): Promise<void> {
    return this.enqueue(async () => {
      const key = PROFILE_SCOPED_KEYS.LOCAL_WATCHLIST;
      const index = await this.read<LocalWatchlistEntry>(key);
      index[normalizeWatchlistId(entry.id)] = { ...entry, addedAt: entry.addedAt ?? Date.now() };
      await this.write(key, index);
      this.notify('watchlist');
    });
  }

  removeFromWatchlist(id: string): Promise<void> {
    return this.enqueue(async () => {
      const key = PROFILE_SCOPED_KEYS.LOCAL_WATCHLIST;
      const index = await this.read<LocalWatchlistEntry>(key);
      const normalized = normalizeWatchlistId(id);
      if (!index[normalized]) return;
      delete index[normalized];
      await this.write(key, index);
      this.notify('watchlist');
    });
  }
}

export const localLibrary = new LocalLibrary();
