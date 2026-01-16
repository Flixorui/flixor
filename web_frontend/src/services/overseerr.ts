import { loadSettings } from '@/state/settings';
import { API_BASE_URL } from '@/services/api';

const CACHE_TTL = 5 * 60 * 1000; // 5 minutes
const OVERSEERR_PROXY = `${API_BASE_URL.replace(/\/$/, '')}/overseerr/proxy`;

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

// Status codes from Overseerr API
const MediaRequestStatus = {
  PENDING: 1,
  APPROVED: 2,
  DECLINED: 3,
};

const MediaInfoStatus = {
  UNKNOWN: 1,
  PENDING: 2,
  PROCESSING: 3,
  PARTIALLY_AVAILABLE: 4,
  AVAILABLE: 5,
};

interface CacheEntry {
  status: OverseerrMediaStatus;
  timestamp: number;
}

// In-memory cache
const statusCache = new Map<string, CacheEntry>();

function getCacheKey(tmdbId: number, mediaType: 'movie' | 'tv'): string {
  return `${mediaType}:${tmdbId}`;
}

function isValidCache(entry: CacheEntry): boolean {
  return Date.now() - entry.timestamp < CACHE_TTL;
}

function normalizeUrl(url: string): string {
  // Remove trailing slashes and ensure no /api/v1 suffix
  return url.replace(/\/+$/, '').replace(/\/api\/v1$/, '');
}

async function fetchOverseerr(
  url: string,
  apiKey: string,
  endpoint: string,
  options: RequestInit = {}
): Promise<Response> {
  const baseUrl = normalizeUrl(url);

  // Use backend proxy to avoid CORS issues
  return fetch(OVERSEERR_PROXY, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      targetUrl: baseUrl,
      apiKey: apiKey,
      endpoint: endpoint,
      method: options.method || 'GET',
      body: options.body ? JSON.parse(options.body as string) : undefined,
    }),
  });
}

export async function validateOverseerrConnection(
  url: string,
  apiKey: string
): Promise<boolean> {
  try {
    const response = await fetchOverseerr(url, apiKey, '/auth/me');
    return response.ok;
  } catch {
    return false;
  }
}

function determineStatus(mediaInfo: any): OverseerrMediaStatus {
  // Check media availability status
  const mediaStatus = mediaInfo?.mediaInfo?.status;
  const requests = mediaInfo?.mediaInfo?.requests || [];

  // If media is available or partially available
  if (mediaStatus === MediaInfoStatus.AVAILABLE) {
    return { status: 'available', canRequest: false };
  }
  if (mediaStatus === MediaInfoStatus.PARTIALLY_AVAILABLE) {
    return { status: 'partially_available', canRequest: true };
  }
  if (mediaStatus === MediaInfoStatus.PROCESSING) {
    return { status: 'processing', canRequest: false };
  }

  // Check for pending requests
  const pendingRequest = requests.find((r: any) => r.status === MediaRequestStatus.PENDING);
  if (pendingRequest) {
    return { status: 'pending', requestId: pendingRequest.id, canRequest: false };
  }

  // Check for approved requests (processing)
  const approvedRequest = requests.find((r: any) => r.status === MediaRequestStatus.APPROVED);
  if (approvedRequest) {
    return { status: 'approved', requestId: approvedRequest.id, canRequest: false };
  }

  // Check for declined requests
  const declinedRequest = requests.find((r: any) => r.status === MediaRequestStatus.DECLINED);
  if (declinedRequest) {
    return { status: 'declined', requestId: declinedRequest.id, canRequest: true };
  }

  // No request exists
  return { status: 'not_requested', canRequest: true };
}

export async function getOverseerrMediaStatus(
  tmdbId: number,
  mediaType: 'movie' | 'tv'
): Promise<OverseerrMediaStatus | null> {
  const settings = loadSettings();

  if (!settings.overseerrEnabled || !settings.overseerrUrl || !settings.overseerrApiKey) {
    return null;
  }

  // Check cache first
  const cacheKey = getCacheKey(tmdbId, mediaType);
  const cached = statusCache.get(cacheKey);
  if (cached && isValidCache(cached)) {
    return cached.status;
  }

  try {
    const endpoint = mediaType === 'movie' ? `/movie/${tmdbId}` : `/tv/${tmdbId}`;
    const response = await fetchOverseerr(
      settings.overseerrUrl,
      settings.overseerrApiKey,
      endpoint
    );

    if (!response.ok) {
      if (response.status === 404) {
        // Media not found in Overseerr - can be requested
        const status: OverseerrMediaStatus = { status: 'not_requested', canRequest: true };
        statusCache.set(cacheKey, { status, timestamp: Date.now() });
        return status;
      }
      console.error(`[Overseerr] Error fetching status: ${response.status}`);
      return null;
    }

    const data = await response.json();
    const status = determineStatus(data);

    // Cache the result
    statusCache.set(cacheKey, { status, timestamp: Date.now() });

    return status;
  } catch (error) {
    console.error('[Overseerr] Error fetching media status:', error);
    return null;
  }
}

export async function requestMedia(
  tmdbId: number,
  mediaType: 'movie' | 'tv',
  is4k: boolean = false
): Promise<OverseerrRequestResult> {
  const settings = loadSettings();

  if (!settings.overseerrEnabled || !settings.overseerrUrl || !settings.overseerrApiKey) {
    return { success: false, error: 'Overseerr not configured' };
  }

  try {
    // For TV shows, we need to fetch and request all seasons
    let seasons: number[] | undefined;
    if (mediaType === 'tv') {
      try {
        const tvResponse = await fetchOverseerr(
          settings.overseerrUrl,
          settings.overseerrApiKey,
          `/tv/${tmdbId}`
        );
        if (tvResponse.ok) {
          const tvData = await tvResponse.json();
          seasons = (tvData.seasons || [])
            .filter((s: any) => s.seasonNumber > 0)
            .map((s: any) => s.seasonNumber);
        }
      } catch {}
    }

    const requestBody: any = {
      mediaType,
      mediaId: tmdbId,
      is4k,
    };

    if (seasons && seasons.length > 0) {
      requestBody.seasons = seasons;
    }

    const response = await fetchOverseerr(
      settings.overseerrUrl,
      settings.overseerrApiKey,
      '/request',
      {
        method: 'POST',
        body: JSON.stringify(requestBody),
      }
    );

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}));
      return {
        success: false,
        error: errorData.message || `Request failed: ${response.status}`,
      };
    }

    const data = await response.json();

    // Invalidate cache for this item
    const cacheKey = getCacheKey(tmdbId, mediaType);
    statusCache.delete(cacheKey);

    return {
      success: true,
      requestId: data.id,
      status: 'pending',
    };
  } catch (error) {
    console.error('[Overseerr] Error requesting media:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

export function clearOverseerrCache(): void {
  statusCache.clear();
}

export function invalidateOverseerrCache(tmdbId: number, mediaType: 'movie' | 'tv'): void {
  const cacheKey = getCacheKey(tmdbId, mediaType);
  statusCache.delete(cacheKey);
}

// Get display text for status
export function getStatusDisplayText(status: OverseerrStatus): string {
  const texts: Record<OverseerrStatus, string> = {
    not_requested: 'Request',
    pending: 'Pending',
    approved: 'Approved',
    declined: 'Declined',
    processing: 'Processing',
    partially_available: 'Partial',
    available: 'Available',
    unknown: 'Unknown',
  };
  return texts[status];
}

// Get status color class
export function getStatusColorClass(status: OverseerrStatus): string {
  const colors: Record<OverseerrStatus, string> = {
    not_requested: 'bg-blue-600 hover:bg-blue-700',
    pending: 'bg-yellow-600',
    approved: 'bg-green-600',
    declined: 'bg-red-600',
    processing: 'bg-purple-600',
    partially_available: 'bg-orange-600',
    available: 'bg-green-700',
    unknown: 'bg-gray-600',
  };
  return colors[status];
}
