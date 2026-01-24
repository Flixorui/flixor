/**
 * Download types for offline playback functionality
 */

export enum DownloadStatus {
  QUEUED = 'queued',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
  PARTIAL = 'partial',  // Shows with some episodes downloaded
}

export interface DownloadProgress {
  globalKey: string;           // serverId:ratingKey
  status: DownloadStatus;
  progress: number;            // 0-100
  downloadedBytes: number;
  totalBytes: number;
  speed: number;               // bytes/sec
  errorMessage?: string;
  thumbPath?: string;          // Local artwork path
}

export interface DownloadedMedia {
  globalKey: string;           // serverId:ratingKey
  serverId: string;
  ratingKey: string;
  type: 'movie' | 'episode';
  parentRatingKey?: string;    // Season key for episodes
  grandparentRatingKey?: string; // Show key for episodes
  status: DownloadStatus;
  progress: number;
  totalBytes?: number;
  downloadedBytes: number;
  videoFilePath?: string;
  thumbPath?: string;
  downloadedAt?: number;
  errorMessage?: string;
  retryCount: number;
}

export interface DownloadedMetadata {
  ratingKey: string;
  serverId: string;
  type: string;
  title: string;
  year?: number;
  summary?: string;
  thumb?: string;              // Plex thumb path (for constructing URLs)
  localThumbPath?: string;     // Local cached artwork path
  art?: string;
  grandparentTitle?: string;   // Show title
  parentTitle?: string;        // Season title
  parentIndex?: number;        // Season number
  index?: number;              // Episode number
  duration?: number;
  viewOffset?: number;
  chapters?: ChapterMarker[];
}

export interface ChapterMarker {
  startTimeOffset: number;
  endTimeOffset: number;
  type: string;
}

export interface DownloadSettings {
  downloadOnWifiOnly: boolean;
  maxConcurrentDownloads: number;
  downloadSubtitles: boolean;
  preferredSubtitleLanguage?: string;
}

export interface DownloadQueueItem {
  globalKey: string;
  serverId: string;
  ratingKey: string;
  type: 'movie' | 'episode';
  priority: number;
  addedAt: number;
  parentRatingKey?: string;
  grandparentRatingKey?: string;
}

// Grouped downloads for UI display
export interface DownloadedShow {
  grandparentRatingKey: string;
  serverId: string;
  title: string;
  year?: number;
  thumb?: string;
  localThumbPath?: string;
  episodes: DownloadedMetadata[];
  totalEpisodes: number;
  downloadedEpisodes: number;
}
