/**
 * Overseerr API Service for requesting media
 * Requires user to enable and provide URL + API key in settings
 */

import { isOverseerrEnabled, getOverseerrUrl, getOverseerrApiKey } from './SettingsData';

const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

// Status enums from Overseerr API
export const MediaRequestStatus = {
  PENDING: 1,
  APPROVED: 2,
  DECLINED: 3,
} as const;

export const MediaInfoStatus = {
  UNKNOWN: 1,
  PENDING: 2,
  PROCESSING: 3,
  PARTIALLY_AVAILABLE: 4,
  AVAILABLE: 5,
} as const;

export type OverseerrStatus =
  | 'not_requested'
  | 'pending'
  | 'approved'
  | 'declined'
  | 'processing'
  | 'partially_available'
  | 'available'
  | 'unknown';

export interface OverseerrMediaStatus {
  status: OverseerrStatus;
  requestId?: number;
  canRequest: boolean;
}

export interface OverseerrRequestResult {
  success: boolean;
  requestId?: number;
  status?: OverseerrStatus;
  error?: string;
}

interface OverseerrUser {
  id: number;
  email: string;
  username: string;
  permissions: number;
}

interface MediaRequest {
  id: number;
  status: number;
  media: {
    id: number;
    tmdbId: number;
    mediaType: string;
    status: number;
  };
}

interface MediaInfo {
  id: number;
  tmdbId: number;
  status: number;
  requests?: MediaRequest[];
}

interface MovieDetails {
  id: number;
  mediaInfo?: MediaInfo;
}

interface TvDetails {
  id: number;
  mediaInfo?: MediaInfo;
}

// In-memory cache for media status
const statusCache = new Map<string, { status: OverseerrMediaStatus; timestamp: number }>();

/**
 * Normalize Overseerr URL - ensure it has /api/v1 suffix and no trailing slash
 */
function normalizeUrl(url: string): string {
  let normalized = url.trim();
  // Remove trailing slash
  if (normalized.endsWith('/')) {
    normalized = normalized.slice(0, -1);
  }
  // Don't add /api/v1 here - we'll add it per request
  return normalized;
}

/**
 * Make authenticated request to Overseerr API
 */
async function overseerrFetch<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  const baseUrl = getOverseerrUrl();
  const apiKey = getOverseerrApiKey();

  if (!baseUrl || !apiKey) {
    throw new Error('Overseerr not configured');
  }

  const url = `${normalizeUrl(baseUrl)}/api/v1${endpoint}`;

  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'X-Api-Key': apiKey,
      ...options.headers,
    },
  });

  if (!response.ok) {
    const errorText = await response.text().catch(() => 'Unknown error');
    throw new Error(`Overseerr API error (${response.status}): ${errorText}`);
  }

  return response.json();
}

/**
 * Check if Overseerr is enabled and has URL + API key configured
 */
export function isOverseerrReady(): boolean {
  return isOverseerrEnabled() && !!getOverseerrUrl() && !!getOverseerrApiKey();
}

/**
 * Validate Overseerr connection with provided credentials
 */
export async function validateOverseerrConnection(
  url: string,
  apiKey: string
): Promise<{ valid: boolean; username?: string; error?: string }> {
  try {
    const normalizedUrl = normalizeUrl(url);
    const response = await fetch(`${normalizedUrl}/api/v1/auth/me`, {
      headers: {
        'Content-Type': 'application/json',
        'X-Api-Key': apiKey,
      },
    });

    if (!response.ok) {
      if (response.status === 401 || response.status === 403) {
        return { valid: false, error: 'Invalid API key' };
      }
      return { valid: false, error: `Server error (${response.status})` };
    }

    const user: OverseerrUser = await response.json();
    return { valid: true, username: user.username || user.email };
  } catch (error) {
    console.log('[OverseerrService] Connection validation error:', error);
    if (error instanceof TypeError && error.message.includes('Network')) {
      return { valid: false, error: 'Unable to connect to server' };
    }
    return { valid: false, error: 'Connection failed' };
  }
}

/**
 * Convert API status codes to human-readable status
 */
function parseMediaStatus(mediaInfo?: MediaInfo): OverseerrMediaStatus {
  if (!mediaInfo) {
    return { status: 'not_requested', canRequest: true };
  }

  // Check media availability status first
  switch (mediaInfo.status) {
    case MediaInfoStatus.AVAILABLE:
      return { status: 'available', canRequest: false };
    case MediaInfoStatus.PARTIALLY_AVAILABLE:
      return { status: 'partially_available', canRequest: true };
    case MediaInfoStatus.PROCESSING:
      return { status: 'processing', canRequest: false };
  }

  // Check request status if media not available
  const latestRequest = mediaInfo.requests?.[0];
  if (latestRequest) {
    switch (latestRequest.status) {
      case MediaRequestStatus.PENDING:
        return { status: 'pending', requestId: latestRequest.id, canRequest: false };
      case MediaRequestStatus.APPROVED:
        return { status: 'approved', requestId: latestRequest.id, canRequest: false };
      case MediaRequestStatus.DECLINED:
        return { status: 'declined', requestId: latestRequest.id, canRequest: true };
    }
  }

  // Default to not requested
  if (mediaInfo.status === MediaInfoStatus.PENDING) {
    return { status: 'pending', canRequest: false };
  }

  return { status: 'not_requested', canRequest: true };
}

/**
 * Get media request status from Overseerr
 */
export async function getMediaStatus(
  tmdbId: number,
  mediaType: 'movie' | 'tv'
): Promise<OverseerrMediaStatus> {
  if (!isOverseerrReady()) {
    return { status: 'unknown', canRequest: false };
  }

  // Check cache
  const cacheKey = `${mediaType}:${tmdbId}`;
  const cached = statusCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    console.log(`[OverseerrService] Cache hit for ${cacheKey}`);
    return cached.status;
  }

  try {
    console.log(`[OverseerrService] Fetching status for ${mediaType}:${tmdbId}`);

    const endpoint = mediaType === 'movie' ? `/movie/${tmdbId}` : `/tv/${tmdbId}`;
    const details = await overseerrFetch<MovieDetails | TvDetails>(endpoint);

    const status = parseMediaStatus(details.mediaInfo);

    // Cache the result
    statusCache.set(cacheKey, { status, timestamp: Date.now() });

    console.log(`[OverseerrService] Status for ${cacheKey}:`, status);
    return status;
  } catch (error) {
    console.log('[OverseerrService] Error fetching status:', error);
    // Return unknown but allow request attempt
    return { status: 'unknown', canRequest: true };
  }
}

/**
 * Get available seasons for a TV show from Overseerr
 */
async function getTvSeasons(tmdbId: number): Promise<number[]> {
  try {
    const details = await overseerrFetch<TvDetails & { seasons?: Array<{ seasonNumber: number }> }>(
      `/tv/${tmdbId}`
    );
    // Filter out season 0 (specials) and return season numbers
    return (details.seasons || [])
      .map(s => s.seasonNumber)
      .filter(n => n > 0);
  } catch (error) {
    console.log('[OverseerrService] Error fetching TV seasons:', error);
    return [];
  }
}

/**
 * Request media through Overseerr
 */
export async function requestMedia(
  tmdbId: number,
  mediaType: 'movie' | 'tv',
  is4k: boolean = false
): Promise<OverseerrRequestResult> {
  if (!isOverseerrReady()) {
    return { success: false, error: 'Overseerr not configured' };
  }

  try {
    console.log(`[OverseerrService] Requesting ${mediaType}:${tmdbId} (4K: ${is4k})`);

    // Build request body
    const requestBody: {
      mediaType: string;
      mediaId: number;
      is4k?: boolean;
      seasons?: number[];
    } = {
      mediaType,
      mediaId: tmdbId,
    };

    // Only add is4k if true
    if (is4k) {
      requestBody.is4k = true;
    }

    // For TV shows, we need to specify which seasons to request
    if (mediaType === 'tv') {
      const seasons = await getTvSeasons(tmdbId);
      if (seasons.length === 0) {
        return { success: false, error: 'Could not determine available seasons' };
      }
      requestBody.seasons = seasons;
      console.log(`[OverseerrService] Requesting seasons:`, seasons);
    }

    const response = await overseerrFetch<MediaRequest>('/request', {
      method: 'POST',
      body: JSON.stringify(requestBody),
    });

    // Clear cache for this item
    const cacheKey = `${mediaType}:${tmdbId}`;
    statusCache.delete(cacheKey);

    console.log('[OverseerrService] Request created:', response);

    // Determine status from response
    let status: OverseerrStatus = 'pending';
    if (response.status === MediaRequestStatus.APPROVED) {
      status = 'approved';
    }

    return {
      success: true,
      requestId: response.id,
      status,
    };
  } catch (error) {
    console.log('[OverseerrService] Error creating request:', error);
    const message = error instanceof Error ? error.message : 'Request failed';
    return { success: false, error: message };
  }
}

/**
 * Clear the status cache
 */
export function clearOverseerrCache(): void {
  statusCache.clear();
  console.log('[OverseerrService] Cache cleared');
}

/**
 * Clear cache for a specific item
 */
export function clearOverseerrCacheItem(tmdbId: number, mediaType: 'movie' | 'tv'): void {
  const cacheKey = `${mediaType}:${tmdbId}`;
  statusCache.delete(cacheKey);
  console.log(`[OverseerrService] Cache cleared for ${cacheKey}`);
}
