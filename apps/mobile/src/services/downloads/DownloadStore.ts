/**
 * DownloadStore - State management for downloads following TopBarStore pattern
 *
 * Uses useSyncExternalStore for React integration
 */

import React from 'react';
import {
  DownloadStatus,
  DownloadProgress,
  DownloadedMetadata,
  DownloadedMedia,
  DownloadedShow,
} from '../../types/downloads';
import {
  loadAllDownloads,
  loadDownloadList,
  loadDownloadMedia,
  loadDownloadMetadata,
} from './DownloadStorageService';

type State = {
  isLoading: boolean;
  downloads: Map<string, DownloadProgress>;
  metadata: Map<string, DownloadedMetadata>;
  media: Map<string, DownloadedMedia>;
  downloadedMovies: DownloadedMetadata[];
  downloadedShows: DownloadedShow[];
  error?: string;
};

type Listener = () => void;

const state: State = {
  isLoading: true,
  downloads: new Map(),
  metadata: new Map(),
  media: new Map(),
  downloadedMovies: [],
  downloadedShows: [],
};

const listeners = new Set<Listener>();

function emit(): void {
  listeners.forEach(l => l());
}

/**
 * Compute derived data (movies and shows lists)
 */
function computeDerivedData(): void {
  const movies: DownloadedMetadata[] = [];
  const showsMap = new Map<string, DownloadedShow>();

  state.metadata.forEach((meta, globalKey) => {
    const media = state.media.get(globalKey);
    if (!media) return;

    // Only include completed downloads in the lists
    const isCompleted = media.status === DownloadStatus.COMPLETED;
    const isDownloading = media.status === DownloadStatus.DOWNLOADING || media.status === DownloadStatus.QUEUED;

    if (meta.type === 'movie') {
      if (isCompleted || isDownloading) {
        movies.push(meta);
      }
    } else if (meta.type === 'episode' && meta.grandparentTitle) {
      // Group episodes by show
      const showKey = `${media.serverId}:${media.grandparentRatingKey}`;

      if (!showsMap.has(showKey)) {
        showsMap.set(showKey, {
          grandparentRatingKey: media.grandparentRatingKey || '',
          serverId: media.serverId,
          title: meta.grandparentTitle,
          year: meta.year,
          thumb: meta.thumb,
          localThumbPath: meta.localThumbPath,
          episodes: [],
          totalEpisodes: 0,
          downloadedEpisodes: 0,
        });
      }

      const show = showsMap.get(showKey)!;
      show.episodes.push(meta);
      show.totalEpisodes += 1;
      if (isCompleted) {
        show.downloadedEpisodes += 1;
      }

      // Use the first episode's thumb as show thumb if not set
      if (!show.localThumbPath && meta.localThumbPath) {
        show.localThumbPath = meta.localThumbPath;
      }
    }
  });

  // Sort movies by download date (most recent first)
  movies.sort((a, b) => {
    const mediaA = state.media.get(`${a.serverId}:${a.ratingKey}`);
    const mediaB = state.media.get(`${b.serverId}:${b.ratingKey}`);
    return (mediaB?.downloadedAt || 0) - (mediaA?.downloadedAt || 0);
  });

  // Sort shows by title
  const shows = Array.from(showsMap.values());
  shows.sort((a, b) => a.title.localeCompare(b.title));

  // Sort episodes within each show
  shows.forEach(show => {
    show.episodes.sort((a, b) => {
      const seasonDiff = (a.parentIndex || 0) - (b.parentIndex || 0);
      if (seasonDiff !== 0) return seasonDiff;
      return (a.index || 0) - (b.index || 0);
    });
  });

  state.downloadedMovies = movies;
  state.downloadedShows = shows;
}

export const downloadStore = {
  subscribe(fn: Listener): () => void {
    listeners.add(fn);
    return () => listeners.delete(fn);
  },

  getState(): State {
    return state;
  },

  /**
   * Load all downloads from storage
   */
  async loadDownloads(): Promise<void> {
    state.isLoading = true;
    emit();

    try {
      const { media, metadata, progress } = await loadAllDownloads();

      state.media = media;
      state.metadata = metadata;
      state.downloads = progress;
      state.error = undefined;

      computeDerivedData();
    } catch (e: any) {
      state.error = e.message || 'Failed to load downloads';
      console.log('[DownloadStore] Error loading downloads:', e);
    } finally {
      state.isLoading = false;
      emit();
    }
  },

  /**
   * Add a new download to the store
   */
  addDownload(globalKey: string, progress: DownloadProgress): void {
    state.downloads.set(globalKey, progress);
    computeDerivedData();
    emit();
  },

  /**
   * Update download progress (does NOT recompute derived data for performance)
   */
  updateProgress(globalKey: string, progress: DownloadProgress): void {
    state.downloads.set(globalKey, progress);
    // Don't call computeDerivedData() here - progress updates don't change movie/show lists
    emit();
  },

  /**
   * Update download status
   */
  updateStatus(globalKey: string, status: DownloadStatus, error?: string): void {
    const progress = state.downloads.get(globalKey);
    if (progress) {
      progress.status = status;
      if (error) progress.errorMessage = error;
      state.downloads.set(globalKey, { ...progress });
    }

    const media = state.media.get(globalKey);
    if (media) {
      media.status = status;
      if (error) media.errorMessage = error;
      state.media.set(globalKey, { ...media });
    }

    computeDerivedData();
    emit();
  },

  /**
   * Set metadata for a download
   */
  setMetadata(globalKey: string, metadata: DownloadedMetadata): void {
    state.metadata.set(globalKey, metadata);
    computeDerivedData();
    emit();
  },

  /**
   * Set media info for a download
   */
  setMedia(globalKey: string, media: DownloadedMedia): void {
    state.media.set(globalKey, media);
    computeDerivedData();
    emit();
  },

  /**
   * Remove a download from the store
   */
  removeDownload(globalKey: string): void {
    state.downloads.delete(globalKey);
    state.metadata.delete(globalKey);
    state.media.delete(globalKey);
    statusCache.delete(globalKey); // Clear status cache for removed item
    computeDerivedData();
    emit();
  },

  /**
   * Get progress for a specific download
   */
  getProgress(globalKey: string): DownloadProgress | undefined {
    return state.downloads.get(globalKey);
  },

  /**
   * Check if a specific item is downloaded
   */
  isDownloaded(globalKey: string): boolean {
    const media = state.media.get(globalKey);
    return media?.status === DownloadStatus.COMPLETED;
  },

  /**
   * Check if a specific item is currently downloading
   */
  isDownloading(globalKey: string): boolean {
    const media = state.media.get(globalKey);
    return media?.status === DownloadStatus.DOWNLOADING || media?.status === DownloadStatus.QUEUED;
  },

  /**
   * Get all downloaded episodes for a show
   */
  getDownloadedEpisodesForShow(showKey: string): DownloadedMetadata[] {
    const episodes: DownloadedMetadata[] = [];
    state.metadata.forEach((meta, globalKey) => {
      const media = state.media.get(globalKey);
      if (
        meta.type === 'episode' &&
        media?.grandparentRatingKey === showKey &&
        media.status === DownloadStatus.COMPLETED
      ) {
        episodes.push(meta);
      }
    });
    return episodes;
  },
};

/**
 * React hook for accessing download store state
 * Note: Selectors should return primitive values or stable references to avoid unnecessary re-renders
 */
export function useDownloadStore<T>(selector: (s: State) => T): T {
  return React.useSyncExternalStore(
    downloadStore.subscribe,
    () => selector(state),
    () => selector(state)
  );
}

// Cached result for useDownloads to maintain stable references
let cachedDownloadsResult = {
  isLoading: state.isLoading,
  downloadedMovies: state.downloadedMovies,
  downloadedShows: state.downloadedShows,
  error: state.error,
};

/**
 * Hook for download state convenience methods - returns stable references
 */
export function useDownloads() {
  const result = React.useSyncExternalStore(
    downloadStore.subscribe,
    () => {
      // Only create new object if values actually changed
      if (
        cachedDownloadsResult.isLoading !== state.isLoading ||
        cachedDownloadsResult.downloadedMovies !== state.downloadedMovies ||
        cachedDownloadsResult.downloadedShows !== state.downloadedShows ||
        cachedDownloadsResult.error !== state.error
      ) {
        cachedDownloadsResult = {
          isLoading: state.isLoading,
          downloadedMovies: state.downloadedMovies,
          downloadedShows: state.downloadedShows,
          error: state.error,
        };
      }
      return cachedDownloadsResult;
    },
    () => cachedDownloadsResult
  );

  const refresh = React.useCallback(() => downloadStore.loadDownloads(), []);

  return {
    ...result,
    refresh,
  };
}

// Cache for useDownloadStatus results per globalKey
const statusCache = new Map<string, {
  progress: DownloadProgress | undefined;
  media: DownloadedMedia | undefined;
  metadata: DownloadedMetadata | undefined;
  isDownloaded: boolean;
  isDownloading: boolean;
  isPaused: boolean;
  isFailed: boolean;
  status: DownloadStatus | undefined;
}>();

/**
 * Hook for checking download status of a specific item - returns stable references
 */
export function useDownloadStatus(globalKey: string) {
  return React.useSyncExternalStore(
    downloadStore.subscribe,
    () => {
      const progress = state.downloads.get(globalKey);
      const media = state.media.get(globalKey);
      const metadata = state.metadata.get(globalKey);
      const status = media?.status;

      const cached = statusCache.get(globalKey);

      // Return cached if nothing changed
      if (
        cached &&
        cached.progress === progress &&
        cached.media === media &&
        cached.metadata === metadata
      ) {
        return cached;
      }

      // Create and cache new result
      const newResult = {
        progress,
        media,
        metadata,
        isDownloaded: status === DownloadStatus.COMPLETED,
        isDownloading: status === DownloadStatus.DOWNLOADING || status === DownloadStatus.QUEUED,
        isPaused: status === DownloadStatus.PAUSED,
        isFailed: status === DownloadStatus.FAILED,
        status,
      };

      statusCache.set(globalKey, newResult);
      return newResult;
    },
    () => statusCache.get(globalKey) || {
      progress: undefined,
      media: undefined,
      metadata: undefined,
      isDownloaded: false,
      isDownloading: false,
      isPaused: false,
      isFailed: false,
      status: undefined,
    }
  );
}
