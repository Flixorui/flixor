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

// ============================================
// Trakt Scrobbling
// ============================================

export type TraktScrobbleIds = {
  tmdbId?: number;
  imdbId?: string;
};

// Convert local TraktScrobbleIds to the format TraktService expects
function toTraktIds(ids: TraktScrobbleIds): { tmdb?: number; imdb?: string } {
  return {
    tmdb: ids.tmdbId,
    imdb: ids.imdbId,
  };
}

export type TraktEpisodeInfo = {
  season: number;
  number: number;
};

/**
 * Check if Trakt is authenticated
 */
export function isTraktAuthenticated(): boolean {
  try {
    const core = getFlixorCore();
    return core.isTraktAuthenticated;
  } catch {
    return false;
  }
}

/**
 * Extract TMDB/IMDB IDs from Plex metadata for Trakt
 */
export function extractTraktIds(metadata: PlexMediaItem | null): TraktScrobbleIds {
  const ids: TraktScrobbleIds = {};
  if (!metadata) return ids;

  const guids = (metadata as any)?.Guid || [];
  for (const g of guids) {
    const id = String(g.id || '');
    if (id.includes('tmdb://') || id.includes('themoviedb://')) {
      ids.tmdbId = Number(id.split('://')[1]);
    }
    if (id.includes('imdb://')) {
      ids.imdbId = id.split('://')[1];
    }
  }

  return ids;
}

/**
 * Start scrobbling on Trakt
 */
export async function startTraktScrobble(
  metadata: PlexMediaItem | null,
  progress: number
): Promise<void> {
  if (!metadata || !isTraktAuthenticated()) return;

  try {
    const core = getFlixorCore();
    const ids = extractTraktIds(metadata);

    if (!ids.tmdbId && !ids.imdbId) {
      console.log('[PlayerData] No TMDB/IMDB IDs for Trakt scrobble');
      return;
    }

    const mediaType = metadata.type;

    if (mediaType === 'movie') {
      await core.trakt.startScrobbleMovie({ ids: toTraktIds(ids) }, progress);
      console.log('[PlayerData] Started Trakt movie scrobble');
    } else if (mediaType === 'episode') {
      // For episodes, we need show IDs and episode info
      const showIds = extractTraktIds({ Guid: (metadata as any).grandparentGuid } as any);
      const episodeInfo = {
        season: (metadata as any).parentIndex || 1,
        number: (metadata as any).index || 1,
      };

      // Try with episode-specific IDs if show IDs aren't available
      const finalIds = (showIds.tmdbId || showIds.imdbId) ? showIds : ids;
      await core.trakt.startScrobbleEpisode({ ids: toTraktIds(finalIds) }, episodeInfo, progress);
      console.log('[PlayerData] Started Trakt episode scrobble');
    }
  } catch (e) {
    console.log('[PlayerData] startTraktScrobble error:', e);
  }
}

/**
 * Pause scrobbling on Trakt
 */
export async function pauseTraktScrobble(
  metadata: PlexMediaItem | null,
  progress: number
): Promise<void> {
  if (!metadata || !isTraktAuthenticated()) return;

  try {
    const core = getFlixorCore();
    const ids = extractTraktIds(metadata);

    if (!ids.tmdbId && !ids.imdbId) return;

    const mediaType = metadata.type;

    if (mediaType === 'movie') {
      await core.trakt.pauseScrobbleMovie({ ids: toTraktIds(ids) }, progress);
      console.log('[PlayerData] Paused Trakt movie scrobble');
    } else if (mediaType === 'episode') {
      const showIds = extractTraktIds({ Guid: (metadata as any).grandparentGuid } as any);
      const episodeInfo = {
        season: (metadata as any).parentIndex || 1,
        number: (metadata as any).index || 1,
      };
      const finalIds = (showIds.tmdbId || showIds.imdbId) ? showIds : ids;
      await core.trakt.pauseScrobbleEpisode({ ids: toTraktIds(finalIds) }, episodeInfo, progress);
      console.log('[PlayerData] Paused Trakt episode scrobble');
    }
  } catch (e) {
    console.log('[PlayerData] pauseTraktScrobble error:', e);
  }
}

/**
 * Stop scrobbling on Trakt (and auto-mark watched if progress >= 80%)
 */
export async function stopTraktScrobble(
  metadata: PlexMediaItem | null,
  progress: number
): Promise<void> {
  if (!metadata || !isTraktAuthenticated()) return;

  try {
    const core = getFlixorCore();
    const ids = extractTraktIds(metadata);

    if (!ids.tmdbId && !ids.imdbId) return;

    const mediaType = metadata.type;

    if (mediaType === 'movie') {
      await core.trakt.stopScrobbleMovie({ ids: toTraktIds(ids) }, progress);
      console.log('[PlayerData] Stopped Trakt movie scrobble, progress:', progress);
    } else if (mediaType === 'episode') {
      const showIds = extractTraktIds({ Guid: (metadata as any).grandparentGuid } as any);
      const episodeInfo = {
        season: (metadata as any).parentIndex || 1,
        number: (metadata as any).index || 1,
      };
      const finalIds = (showIds.tmdbId || showIds.imdbId) ? showIds : ids;
      await core.trakt.stopScrobbleEpisode({ ids: toTraktIds(finalIds) }, episodeInfo, progress);
      console.log('[PlayerData] Stopped Trakt episode scrobble, progress:', progress);
    }
  } catch (e) {
    console.log('[PlayerData] stopTraktScrobble error:', e);
  }
}
