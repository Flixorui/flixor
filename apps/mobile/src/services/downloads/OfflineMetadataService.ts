/**
 * OfflineMetadataService - Handles metadata caching for offline display and playback
 *
 * Provides:
 * - Offline artwork access
 * - Cached markers for skip intro/credits
 * - Watch progress sync when back online
 */

import {
  loadDownloadMetadata,
  loadMarkers,
  loadDownloadMedia,
} from './DownloadStorageService';
import { ChapterMarker, DownloadedMetadata, DownloadedMedia } from '../../types/downloads';

/**
 * Get metadata for offline playback
 */
export async function getOfflineMetadata(globalKey: string): Promise<DownloadedMetadata | null> {
  return loadDownloadMetadata(globalKey);
}

/**
 * Get media info for offline playback
 */
export async function getOfflineMedia(globalKey: string): Promise<DownloadedMedia | null> {
  return loadDownloadMedia(globalKey);
}

/**
 * Get cached markers for skip intro/credits during offline playback
 */
export async function getOfflineMarkers(globalKey: string): Promise<ChapterMarker[]> {
  return loadMarkers(globalKey);
}

/**
 * Get the local video file path for offline playback
 */
export async function getOfflineVideoPath(globalKey: string): Promise<string | null> {
  const media = await loadDownloadMedia(globalKey);
  return media?.videoFilePath || null;
}

/**
 * Get the local artwork path
 */
export async function getOfflineArtworkPath(globalKey: string): Promise<string | null> {
  const metadata = await loadDownloadMetadata(globalKey);
  return metadata?.localThumbPath || null;
}

/**
 * Convert offline metadata to player-compatible format
 */
export function formatMetadataForPlayer(
  metadata: DownloadedMetadata,
  media: DownloadedMedia
): {
  title: string;
  subtitle?: string;
  thumb?: string;
  duration?: number;
  type: 'movie' | 'episode';
  seasonEpisode?: string;
} {
  const result: ReturnType<typeof formatMetadataForPlayer> = {
    title: metadata.title,
    thumb: metadata.localThumbPath,
    duration: metadata.duration,
    type: media.type,
  };

  if (media.type === 'episode') {
    result.subtitle = metadata.grandparentTitle;
    const sNum = metadata.parentIndex?.toString().padStart(2, '0') || '01';
    const eNum = metadata.index?.toString().padStart(2, '0') || '01';
    result.seasonEpisode = `S${sNum}:E${eNum}`;
  }

  return result;
}

/**
 * Convert cached markers to player-compatible format
 */
export function formatMarkersForPlayer(
  markers: ChapterMarker[]
): Array<{ id?: string; type: string; startTimeOffset: number; endTimeOffset: number }> {
  return markers.map((m, i) => ({
    id: `offline-marker-${i}`,
    type: m.type,
    startTimeOffset: m.startTimeOffset,
    endTimeOffset: m.endTimeOffset,
  }));
}
