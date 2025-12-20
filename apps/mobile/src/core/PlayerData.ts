/**
 * Player screen data fetchers using FlixorCore
 * Replaces the old api/client.ts functions for Player screen
 */

import { getFlixorCore } from './index';
import type { PlexMediaItem, PlexMarker } from '@flixor/core';

export type NextEpisodeInfo = {
  ratingKey: string;
  title: string;
  thumb?: string;
  episodeLabel?: string;
};

export type PlaybackInfo = {
  streamUrl: string;
  directPlay: boolean;
  sessionId: string;
  baseUrl: string;
  token: string;
};

// ============================================
// Metadata
// ============================================

export async function fetchPlayerMetadata(ratingKey: string): Promise<PlexMediaItem | null> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getMetadata(ratingKey);
  } catch (e) {
    console.log('[PlayerData] fetchPlayerMetadata error:', e);
    return null;
  }
}

// ============================================
// Markers (Skip Intro/Credits)
// ============================================

export async function fetchMarkers(ratingKey: string): Promise<PlexMarker[]> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getMarkers(ratingKey);
  } catch (e) {
    console.log('[PlayerData] fetchMarkers error:', e);
    return [];
  }
}

// ============================================
// Next Episode
// ============================================

export async function fetchNextEpisode(
  currentRatingKey: string,
  parentRatingKey: string
): Promise<NextEpisodeInfo | null> {
  try {
    const core = getFlixorCore();
    const episodes = await core.plexServer.getChildren(parentRatingKey);

    const currentIndex = episodes.findIndex(
      (ep: PlexMediaItem) => String(ep.ratingKey) === String(currentRatingKey)
    );

    if (currentIndex >= 0 && episodes[currentIndex + 1]) {
      const nextEp = episodes[currentIndex + 1];
      const seasonNum = nextEp.parentIndex;
      const epNum = nextEp.index;
      const episodeLabel = (seasonNum && epNum) ? `S${seasonNum}:E${epNum}` : undefined;

      return {
        ratingKey: String(nextEp.ratingKey),
        title: nextEp.title || 'Next Episode',
        thumb: nextEp.thumb,
        episodeLabel,
      };
    }

    return null;
  } catch (e) {
    console.log('[PlayerData] fetchNextEpisode error:', e);
    return null;
  }
}

// ============================================
// Playback URLs
// ============================================

export async function getDirectStreamUrl(ratingKey: string): Promise<string> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getStreamUrl(ratingKey);
  } catch (e) {
    console.log('[PlayerData] getDirectStreamUrl error:', e);
    throw e;
  }
}

export function getTranscodeStreamUrl(
  ratingKey: string,
  options?: {
    maxVideoBitrate?: number;
    videoResolution?: string;
    protocol?: 'hls' | 'dash';
    sessionId?: string;
    directStream?: boolean;
  }
): { url: string; startUrl: string; sessionUrl: string; sessionId: string } {
  try {
    const core = getFlixorCore();
    return core.plexServer.getTranscodeUrl(ratingKey, options);
  } catch (e) {
    console.log('[PlayerData] getTranscodeStreamUrl error:', e);
    throw e;
  }
}

export async function startTranscodeSession(startUrl: string): Promise<void> {
  try {
    const core = getFlixorCore();
    await core.plexServer.startTranscodeSession(startUrl);
  } catch (e) {
    console.log('[PlayerData] startTranscodeSession error:', e);
    throw e;
  }
}

// ============================================
// Timeline Updates (Progress Tracking)
// ============================================

export async function updatePlaybackTimeline(
  ratingKey: string,
  state: 'playing' | 'paused' | 'stopped',
  timeMs: number,
  durationMs: number
): Promise<void> {
  try {
    const core = getFlixorCore();
    await core.plexServer.updateTimeline(ratingKey, state, timeMs, durationMs);
  } catch (e) {
    console.log('[PlayerData] updatePlaybackTimeline error:', e);
  }
}

// ============================================
// Transcode Session Management
// ============================================

export async function stopTranscodeSession(sessionId: string): Promise<void> {
  try {
    const core = getFlixorCore();
    await core.plexServer.stopTranscode(sessionId);
  } catch (e) {
    console.log('[PlayerData] stopTranscodeSession error:', e);
  }
}

// ============================================
// Image URLs
// ============================================

export function getPlayerImageUrl(path: string | undefined, width: number = 300): string {
  if (!path) return '';
  try {
    const core = getFlixorCore();
    return core.plexServer.getImageUrl(path, width);
  } catch {
    return '';
  }
}

// ============================================
// Plex Headers for Video Playback
// ============================================

export function getPlexHeaders(): Record<string, string> {
  try {
    const core = getFlixorCore();
    return {
      'X-Plex-Token': core.getPlexToken() || '',
      'X-Plex-Client-Identifier': core.getClientId(),
      'X-Plex-Product': 'Flixor',
      'X-Plex-Version': '1.0.0',
      'X-Plex-Platform': 'iOS',
      'X-Plex-Device': 'iPhone',
    };
  } catch {
    return {};
  }
}

// ============================================
// Check if media can be direct streamed
// ============================================

export function canDirectStream(metadata: any): boolean {
  const media = metadata?.Media?.[0];
  if (!media) return false;

  const container = (media.container || '').toLowerCase();
  const videoCodec = (media.videoCodec || '').toLowerCase();

  // iOS natively supports these containers and codecs
  const supportedContainers = ['mp4', 'mov', 'm4v'];
  const supportedVideoCodecs = ['h264', 'avc1', 'hevc', 'h265'];

  const containerOk = supportedContainers.includes(container);
  const videoOk = supportedVideoCodecs.some(c => videoCodec.includes(c));

  console.log(`[PlayerData] Direct stream check: container=${container} (${containerOk}), video=${videoCodec} (${videoOk})`);

  return containerOk && videoOk;
}
