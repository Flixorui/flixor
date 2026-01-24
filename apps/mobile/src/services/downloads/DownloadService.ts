/**
 * DownloadService - Manages download queue, execution, and progress
 *
 * Uses expo-file-system downloadAsync for proper large file handling
 */

import { File, Directory } from 'expo-file-system';
import * as FileSystemLegacy from 'expo-file-system/legacy';
import { getFlixorCore } from '../../core/index';
import type { PlexMediaItem } from '@flixor/core';
import {
  DownloadStatus,
  DownloadProgress,
  DownloadedMedia,
  DownloadedMetadata,
  DownloadQueueItem,
  ChapterMarker,
} from '../../types/downloads';
import {
  ensureDirectoryExists,
  getMoviePath,
  getMovieDirectory,
  getEpisodePath,
  getSeasonDirectory,
  getArtworkPath,
  getAvailableSpace,
  saveDownloadList,
  loadDownloadList,
  saveDownloadMedia,
  loadDownloadMedia,
  saveDownloadMetadata,
  loadDownloadMetadata,
  saveDownloadQueue,
  loadDownloadQueue,
  saveMarkers,
  removeDownloadCompletely,
  initializeDownloadsDirectory,
  fileExists,
  getFileSize,
} from './DownloadStorageService';
import { downloadStore } from './DownloadStore';

// Minimum required free space (500MB)
const MIN_FREE_SPACE = 500 * 1024 * 1024;

// Progress throttling settings
const PROGRESS_THROTTLE_MS = 500;
const PROGRESS_MIN_CHANGE = 2;

// Active download tracking
interface ActiveDownload {
  controller: AbortController;
  globalKey: string;
}

// Event types
type ProgressCallback = (progress: DownloadProgress) => void;
type StatusCallback = (globalKey: string, status: DownloadStatus, error?: string) => void;

class DownloadServiceClass {
  private activeDownloads: Map<string, ActiveDownload> = new Map();
  private progressCallbacks: Set<ProgressCallback> = new Set();
  private statusCallbacks: Set<StatusCallback> = new Set();
  private queue: DownloadQueueItem[] = [];
  private isProcessingQueue = false;
  private maxConcurrent = 1;
  private downloadOnWifiOnly = true;
  private lastProgressUpdate: Map<string, number> = new Map();
  private lastProgressPercent: Map<string, number> = new Map();

  /**
   * Initialize the download service
   */
  async initialize(): Promise<void> {
    await initializeDownloadsDirectory();
    this.queue = await loadDownloadQueue();
    this.processQueue();
  }

  /**
   * Set download preferences
   */
  setPreferences(opts: { maxConcurrent?: number; downloadOnWifiOnly?: boolean }): void {
    if (opts.maxConcurrent !== undefined) {
      this.maxConcurrent = opts.maxConcurrent;
    }
    if (opts.downloadOnWifiOnly !== undefined) {
      this.downloadOnWifiOnly = opts.downloadOnWifiOnly;
    }
  }

  /**
   * Subscribe to progress updates
   */
  onProgress(callback: ProgressCallback): () => void {
    this.progressCallbacks.add(callback);
    return () => this.progressCallbacks.delete(callback);
  }

  /**
   * Subscribe to status changes
   */
  onStatusChange(callback: StatusCallback): () => void {
    this.statusCallbacks.add(callback);
    return () => this.statusCallbacks.delete(callback);
  }

  private emitProgress(progress: DownloadProgress): void {
    this.progressCallbacks.forEach(cb => cb(progress));
    downloadStore.updateProgress(progress.globalKey, progress);
  }

  private emitStatusChange(globalKey: string, status: DownloadStatus, error?: string): void {
    this.statusCallbacks.forEach(cb => cb(globalKey, status, error));
  }

  /**
   * Queue a download for a movie or episode
   */
  async queueDownload(metadata: PlexMediaItem, serverId?: string): Promise<void> {
    const core = getFlixorCore();
    const actualServerId = serverId || core.server?.id;

    if (!actualServerId) {
      throw new Error('No server connected');
    }

    const ratingKey = String(metadata.ratingKey);
    const globalKey = `${actualServerId}:${ratingKey}`;

    // Check if already downloaded or in queue
    const existingMedia = await loadDownloadMedia(globalKey);
    if (existingMedia?.status === DownloadStatus.COMPLETED) {
      console.log('[DownloadService] Already downloaded:', globalKey);
      return;
    }

    // Check if in queue
    if (this.queue.some(q => q.globalKey === globalKey)) {
      console.log('[DownloadService] Already in queue:', globalKey);
      return;
    }

    // Check available space
    const freeSpace = await getAvailableSpace();
    if (freeSpace < MIN_FREE_SPACE) {
      throw new Error('Not enough storage space');
    }

    // Determine type
    const type = metadata.type === 'movie' ? 'movie' : 'episode';

    // Create queue item
    const queueItem: DownloadQueueItem = {
      globalKey,
      serverId: actualServerId,
      ratingKey,
      type,
      priority: Date.now(),
      addedAt: Date.now(),
      parentRatingKey: metadata.parentRatingKey ? String(metadata.parentRatingKey) : undefined,
      grandparentRatingKey: metadata.grandparentRatingKey ? String(metadata.grandparentRatingKey) : undefined,
    };

    // Create initial media record
    const media: DownloadedMedia = {
      globalKey,
      serverId: actualServerId,
      ratingKey,
      type,
      parentRatingKey: queueItem.parentRatingKey,
      grandparentRatingKey: queueItem.grandparentRatingKey,
      status: DownloadStatus.QUEUED,
      progress: 0,
      downloadedBytes: 0,
      retryCount: 0,
    };

    // Create metadata record
    const downloadMetadata: DownloadedMetadata = {
      ratingKey,
      serverId: actualServerId,
      type: metadata.type,
      title: metadata.title,
      year: metadata.year,
      summary: metadata.summary,
      thumb: metadata.thumb,
      art: metadata.art,
      grandparentTitle: metadata.grandparentTitle,
      parentTitle: metadata.parentTitle,
      parentIndex: metadata.parentIndex,
      index: metadata.index,
      duration: metadata.duration,
      viewOffset: metadata.viewOffset,
    };

    // Save to storage
    await saveDownloadMedia(globalKey, media);
    await saveDownloadMetadata(globalKey, downloadMetadata);

    // Update download list
    const list = await loadDownloadList();
    if (!list.includes(globalKey)) {
      list.push(globalKey);
      await saveDownloadList(list);
    }

    // Add to queue and save
    this.queue.push(queueItem);
    await saveDownloadQueue(this.queue);

    // Update store
    downloadStore.addDownload(globalKey, {
      globalKey,
      status: DownloadStatus.QUEUED,
      progress: 0,
      downloadedBytes: 0,
      totalBytes: 0,
      speed: 0,
    });
    downloadStore.setMetadata(globalKey, downloadMetadata);
    downloadStore.setMedia(globalKey, media);

    console.log('[DownloadService] Queued download:', globalKey);

    // Start processing queue
    this.processQueue();
  }

  /**
   * Pause a download
   */
  async pauseDownload(globalKey: string): Promise<void> {
    const active = this.activeDownloads.get(globalKey);
    if (active) {
      active.controller.abort();
      this.activeDownloads.delete(globalKey);

      const media = await loadDownloadMedia(globalKey);
      if (media) {
        media.status = DownloadStatus.PAUSED;
        await saveDownloadMedia(globalKey, media);
      }

      downloadStore.updateStatus(globalKey, DownloadStatus.PAUSED);
      this.emitStatusChange(globalKey, DownloadStatus.PAUSED);
    }
  }

  /**
   * Resume a paused download
   */
  async resumeDownload(globalKey: string): Promise<void> {
    const media = await loadDownloadMedia(globalKey);
    if (!media || media.status !== DownloadStatus.PAUSED) {
      return;
    }

    const queueItem: DownloadQueueItem = {
      globalKey,
      serverId: media.serverId,
      ratingKey: media.ratingKey,
      type: media.type,
      priority: 0,
      addedAt: Date.now(),
      parentRatingKey: media.parentRatingKey,
      grandparentRatingKey: media.grandparentRatingKey,
    };

    media.status = DownloadStatus.QUEUED;
    await saveDownloadMedia(globalKey, media);

    this.queue.unshift(queueItem);
    await saveDownloadQueue(this.queue);

    downloadStore.updateStatus(globalKey, DownloadStatus.QUEUED);
    this.emitStatusChange(globalKey, DownloadStatus.QUEUED);

    this.processQueue();
  }

  /**
   * Cancel a download
   */
  async cancelDownload(globalKey: string): Promise<void> {
    const active = this.activeDownloads.get(globalKey);
    if (active) {
      active.controller.abort();
      this.activeDownloads.delete(globalKey);
    }

    this.queue = this.queue.filter(q => q.globalKey !== globalKey);
    await saveDownloadQueue(this.queue);

    const media = await loadDownloadMedia(globalKey);
    if (media) {
      media.status = DownloadStatus.CANCELLED;
      await saveDownloadMedia(globalKey, media);
    }

    downloadStore.updateStatus(globalKey, DownloadStatus.CANCELLED);
    this.emitStatusChange(globalKey, DownloadStatus.CANCELLED);
  }

  /**
   * Delete a download (including files)
   */
  async deleteDownload(globalKey: string): Promise<void> {
    await this.cancelDownload(globalKey);
    await removeDownloadCompletely(globalKey);
    downloadStore.removeDownload(globalKey);
  }

  /**
   * Retry a failed download
   */
  async retryDownload(globalKey: string): Promise<void> {
    const media = await loadDownloadMedia(globalKey);
    if (!media || media.status !== DownloadStatus.FAILED) {
      return;
    }

    media.status = DownloadStatus.QUEUED;
    media.progress = 0;
    media.downloadedBytes = 0;
    media.errorMessage = undefined;
    media.retryCount += 1;
    await saveDownloadMedia(globalKey, media);

    const queueItem: DownloadQueueItem = {
      globalKey,
      serverId: media.serverId,
      ratingKey: media.ratingKey,
      type: media.type,
      priority: 0,
      addedAt: Date.now(),
      parentRatingKey: media.parentRatingKey,
      grandparentRatingKey: media.grandparentRatingKey,
    };

    this.queue.unshift(queueItem);
    await saveDownloadQueue(this.queue);

    downloadStore.updateStatus(globalKey, DownloadStatus.QUEUED);
    this.emitStatusChange(globalKey, DownloadStatus.QUEUED);

    this.processQueue();
  }

  /**
   * Process the download queue
   */
  private async processQueue(): Promise<void> {
    if (this.isProcessingQueue) return;
    this.isProcessingQueue = true;

    try {
      while (this.queue.length > 0 && this.activeDownloads.size < this.maxConcurrent) {
        this.queue.sort((a, b) => a.priority - b.priority);
        const item = this.queue.shift();
        if (!item) break;

        await saveDownloadQueue(this.queue);
        this.startDownload(item);
      }
    } finally {
      this.isProcessingQueue = false;
    }
  }

  /**
   * Start downloading an item
   */
  private async startDownload(item: DownloadQueueItem): Promise<void> {
    const { globalKey, ratingKey, type } = item;

    try {
      const core = getFlixorCore();
      const media = await loadDownloadMedia(globalKey);
      if (!media) return;

      media.status = DownloadStatus.DOWNLOADING;
      await saveDownloadMedia(globalKey, media);

      downloadStore.updateStatus(globalKey, DownloadStatus.DOWNLOADING);
      this.emitStatusChange(globalKey, DownloadStatus.DOWNLOADING);

      const metadata = await loadDownloadMetadata(globalKey);
      if (!metadata) {
        throw new Error('Metadata not found');
      }

      // Get direct stream URL
      const streamUrl = await core.plexServer.getStreamUrl(ratingKey);

      // Determine file path
      let videoPath: string;
      let directory: string;

      if (type === 'movie') {
        const ext = this.getExtensionFromUrl(streamUrl) || 'mp4';
        videoPath = getMoviePath(metadata.title, metadata.year, ext);
        directory = getMovieDirectory(metadata.title, metadata.year);
      } else {
        const showTitle = metadata.grandparentTitle || 'Unknown Show';
        const seasonNum = metadata.parentIndex || 1;
        const episodeNum = metadata.index || 1;
        const ext = this.getExtensionFromUrl(streamUrl) || 'mp4';

        videoPath = getEpisodePath(showTitle, metadata.year, seasonNum, episodeNum, metadata.title, ext);
        directory = getSeasonDirectory(showTitle, metadata.year, seasonNum);
      }

      console.log('[DownloadService] Video path:', videoPath);
      console.log('[DownloadService] Directory:', directory);

      if (!videoPath || !directory) {
        throw new Error('Failed to generate valid file paths');
      }

      // Ensure directory exists
      console.log('[DownloadService] Creating directory...');
      try {
        await ensureDirectoryExists(directory);
        console.log('[DownloadService] Directory created successfully');
      } catch (dirError) {
        console.log('[DownloadService] Directory creation error:', dirError);
        throw dirError;
      }

      // Get Plex headers
      const token = core.getPlexToken() || '';
      const headers: Record<string, string> = {
        'X-Plex-Token': token,
      };

      // Download with progress using fetch API
      console.log('[DownloadService] Starting download from:', streamUrl.substring(0, 100) + '...');
      const controller = new AbortController();
      this.activeDownloads.set(globalKey, { controller, globalKey });

      try {
        await this.downloadWithProgress(streamUrl, videoPath, headers, globalKey, controller.signal);
        console.log('[DownloadService] Download completed successfully');
      } catch (downloadError) {
        console.log('[DownloadService] Download error in progress:', downloadError);
        throw downloadError;
      }

      // Remove from active downloads
      this.activeDownloads.delete(globalKey);
      this.lastProgressUpdate.delete(globalKey);
      this.lastProgressPercent.delete(globalKey);

      // Download artwork
      const artworkLocalPath = await this.downloadArtwork(globalKey, metadata, directory);

      // Cache markers for offline
      await this.cacheMarkers(globalKey, ratingKey);

      // Update media record
      media.status = DownloadStatus.COMPLETED;
      media.progress = 100;
      media.videoFilePath = videoPath;
      media.thumbPath = artworkLocalPath;
      media.downloadedAt = Date.now();
      media.downloadedBytes = getFileSize(videoPath);
      media.totalBytes = media.downloadedBytes;

      await saveDownloadMedia(globalKey, media);

      // Update metadata with local artwork path
      if (artworkLocalPath) {
        metadata.localThumbPath = artworkLocalPath;
        await saveDownloadMetadata(globalKey, metadata);
        downloadStore.setMetadata(globalKey, metadata);
      }

      downloadStore.updateStatus(globalKey, DownloadStatus.COMPLETED);
      downloadStore.setMedia(globalKey, media);
      downloadStore.updateProgress(globalKey, {
        globalKey,
        status: DownloadStatus.COMPLETED,
        progress: 100,
        downloadedBytes: media.downloadedBytes,
        totalBytes: media.totalBytes || 0,
        speed: 0,
        thumbPath: artworkLocalPath,
      });

      this.emitStatusChange(globalKey, DownloadStatus.COMPLETED);
      console.log('[DownloadService] Download completed:', globalKey);

    } catch (error: any) {
      if (error.name === 'AbortError') {
        console.log('[DownloadService] Download aborted:', globalKey);
        return;
      }

      console.log('[DownloadService] Download error:', error);

      this.activeDownloads.delete(globalKey);
      this.lastProgressUpdate.delete(globalKey);
      this.lastProgressPercent.delete(globalKey);

      const media = await loadDownloadMedia(globalKey);
      if (media) {
        media.status = DownloadStatus.FAILED;
        media.errorMessage = error.message || 'Download failed';
        await saveDownloadMedia(globalKey, media);
      }

      downloadStore.updateStatus(globalKey, DownloadStatus.FAILED, error.message);
      this.emitStatusChange(globalKey, DownloadStatus.FAILED, error.message);
    }

    this.processQueue();
  }

  /**
   * Download file with progress tracking using expo-file-system downloadAsync
   * This properly handles large files without loading them entirely into memory
   */
  private async downloadWithProgress(
    url: string,
    filePath: string,
    headers: Record<string, string>,
    globalKey: string,
    signal: AbortSignal
  ): Promise<void> {
    if (!filePath) {
      throw new Error('Invalid file path');
    }

    // Ensure path has file:// prefix for expo-file-system
    const cleanPath = filePath.startsWith('file://') ? filePath : `file://${filePath}`;
    console.log('[DownloadService] Downloading to:', cleanPath);

    // Create a download resumable for progress tracking
    const downloadResumable = FileSystemLegacy.createDownloadResumable(
      url,
      cleanPath,
      {
        headers,
      },
      (downloadProgress) => {
        // Throttled progress update
        const now = Date.now();
        const lastUpdate = this.lastProgressUpdate.get(globalKey) || 0;
        const percent = downloadProgress.totalBytesExpectedToWrite > 0
          ? Math.round((downloadProgress.totalBytesWritten / downloadProgress.totalBytesExpectedToWrite) * 100)
          : 0;
        const lastPercent = this.lastProgressPercent.get(globalKey) || 0;

        if (now - lastUpdate >= PROGRESS_THROTTLE_MS || Math.abs(percent - lastPercent) >= PROGRESS_MIN_CHANGE) {
          this.lastProgressUpdate.set(globalKey, now);
          this.lastProgressPercent.set(globalKey, percent);

          this.emitProgress({
            globalKey,
            status: DownloadStatus.DOWNLOADING,
            progress: percent,
            downloadedBytes: downloadProgress.totalBytesWritten,
            totalBytes: downloadProgress.totalBytesExpectedToWrite,
            speed: 0,
          });
        }
      }
    );

    // Store the resumable for potential pause/cancel operations
    const activeDownload = this.activeDownloads.get(globalKey);
    if (activeDownload) {
      (activeDownload as any).resumable = downloadResumable;
    }

    // Handle abort signal
    const abortHandler = () => {
      console.log('[DownloadService] Abort signal received');
      downloadResumable.pauseAsync().catch(() => {});
    };
    signal.addEventListener('abort', abortHandler);

    try {
      const result = await downloadResumable.downloadAsync();
      console.log('[DownloadService] Download result:', result?.uri);

      if (!result?.uri) {
        throw new Error('Download failed - no result URI');
      }
    } finally {
      signal.removeEventListener('abort', abortHandler);
    }

    console.log('[DownloadService] File downloaded:', cleanPath);
  }

  /**
   * Download artwork for a media item
   * Returns the local artwork path if successful
   */
  private async downloadArtwork(
    globalKey: string,
    metadata: DownloadedMetadata,
    directory: string
  ): Promise<string | undefined> {
    if (!metadata.thumb) return undefined;

    try {
      const core = getFlixorCore();
      const thumbUrl = core.plexServer.getImageUrl(metadata.thumb, 400);
      const artworkPath = getArtworkPath(metadata.serverId, metadata.thumb);

      if (!artworkPath) {
        console.log('[DownloadService] Artwork path is invalid, skipping');
        return undefined;
      }

      // Ensure path has file:// prefix
      const cleanPath = artworkPath.startsWith('file://') ? artworkPath : `file://${artworkPath}`;

      // Check if artwork already exists (deduplication)
      if (fileExists(artworkPath)) {
        console.log('[DownloadService] Artwork already exists:', cleanPath);
        return cleanPath;
      }

      // Ensure artwork directory exists - extract directory from path
      const lastSlash = artworkPath.lastIndexOf('/');
      const artworkDirPath = artworkPath.substring(0, lastSlash);
      await ensureDirectoryExists(artworkDirPath);

      const token = core.getPlexToken() || '';

      // Use downloadAsync for artwork as well
      await FileSystemLegacy.downloadAsync(thumbUrl, cleanPath, {
        headers: { 'X-Plex-Token': token },
      });

      console.log('[DownloadService] Artwork downloaded:', cleanPath);
      return cleanPath;
    } catch (error) {
      console.log('[DownloadService] Error downloading artwork:', error);
      return undefined;
    }
  }

  /**
   * Cache chapter markers for offline playback
   */
  private async cacheMarkers(globalKey: string, ratingKey: string): Promise<void> {
    try {
      const core = getFlixorCore();
      const markersData = await core.plexServer.getMarkers(ratingKey);

      if (markersData && markersData.length > 0) {
        const markers: ChapterMarker[] = markersData.map((m: any) => ({
          startTimeOffset: m.startTimeOffset,
          endTimeOffset: m.endTimeOffset,
          type: m.type,
        }));

        await saveMarkers(globalKey, markers);
        console.log('[DownloadService] Cached markers for:', globalKey);
      }
    } catch (error) {
      console.log('[DownloadService] Error caching markers:', error);
    }
  }

  /**
   * Get file extension from URL
   */
  private getExtensionFromUrl(url: string): string | null {
    try {
      const urlObj = new URL(url);
      const pathname = urlObj.pathname;
      const match = pathname.match(/\.([a-zA-Z0-9]+)(?:\?|$)/);
      return match ? match[1].toLowerCase() : null;
    } catch {
      return null;
    }
  }
}

// Export singleton instance
export const downloadService = new DownloadServiceClass();
