import { getSettings } from '@/state/settings';
import { API_BASE_URL } from '@/services/api';

const CACHE_TTL = 5 * 60 * 1000; // 5 minutes
const OVERSEERR_PROXY = `${API_BASE_URL.replace(/\/$/, '')}/overseerr/proxy`;
const OVERSEERR_AUTH = `${API_BASE_URL.replace(/\/$/, '')}/overseerr/auth/plex`;

export type OverseerrStatus =
  | 'not_requested'
  | 'pending'
  | 'approved'
  | 'declined'
  | 'processing'
  | 'partially_available'
  | 'available'
  | 'unknown';

export interface OverseerrSeason {
  seasonNumber: number;
  /** MediaInfoStatus value. Undefined when Overseerr has no record of the season. */
  status?: number;
  name?: string;
  episodeCount?: number;
}

export interface OverseerrMediaStatus {
  status: OverseerrStatus;
  requestId?: number;
  canRequest: boolean;
  /** TV only: per-season state, when Overseerr returned it. */
  seasons?: OverseerrSeason[];
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

function overseerrAuth(apiKey: string): { apiKey?: string; authMethod: 'api_key' | 'plex' } {
  return apiKey ? { apiKey, authMethod: 'api_key' } : { authMethod: 'plex' };
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
    credentials: 'include',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      targetUrl: baseUrl,
      ...overseerrAuth(apiKey),
      endpoint: endpoint,
      method: options.method || 'GET',
      body: options.body ? JSON.parse(options.body as string) : undefined,
    }),
  });
}

/** Credentials from settings. Null when Overseerr isn't ready to use. */
function configured(): { url: string; apiKey: string } | null {
  const settings = getSettings();
  if (!settings.overseerrEnabled || !settings.overseerrUrl) return null;
  if (settings.overseerrAuthMethod === 'plex') {
    return settings.overseerrPlexUsername ? { url: settings.overseerrUrl, apiKey: '' } : null;
  }
  return settings.overseerrApiKey ? { url: settings.overseerrUrl, apiKey: settings.overseerrApiKey } : null;
}

export function isOverseerrReady(): boolean {
  return configured() !== null;
}

export interface OverseerrSignInResult {
  valid: boolean;
  username?: string;
  error?: string;
}

async function overseerrAuthPost(path: string, targetUrl: string): Promise<Response> {
  return fetch(`${OVERSEERR_AUTH}${path}`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ targetUrl: normalizeUrl(targetUrl) }),
  });
}

/** Signs in with the app's Plex account. The backend keeps Overseerr's session. */
export async function signInToOverseerrWithPlex(url: string): Promise<OverseerrSignInResult> {
  try {
    const response = await overseerrAuthPost('', url);
    if (!response.ok) {
      const body = await response.json().catch(() => null);
      return { valid: false, error: body?.message || `Could not reach Overseerr (${response.status})` };
    }
    return await response.json();
  } catch {
    return { valid: false, error: 'Could not reach Overseerr' };
  }
}

export async function getOverseerrPlexSession(url: string): Promise<{ signedIn: boolean; username?: string }> {
  try {
    const response = await overseerrAuthPost('/status', url);
    return response.ok ? await response.json() : { signedIn: false };
  } catch {
    return { signedIn: false };
  }
}

export async function signOutOfOverseerrPlex(): Promise<void> {
  await fetch(`${OVERSEERR_AUTH}/signout`, { method: 'POST', credentials: 'include' }).catch(() => undefined);
  clearOverseerrCache();
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

function isSeasonRequestable(season: OverseerrSeason): boolean {
  if (season.status === undefined) return true;
  return (
    season.status !== MediaInfoStatus.AVAILABLE
    && season.status !== MediaInfoStatus.PROCESSING
    && season.status !== MediaInfoStatus.PENDING
    && season.status !== MediaInfoStatus.PARTIALLY_AVAILABLE
  );
}

export function canRequestSeason(season: OverseerrSeason): boolean {
  return season.seasonNumber > 0 && isSeasonRequestable(season);
}

export function seasonStatusLabel(season: OverseerrSeason): string {
  switch (season.status) {
    case MediaInfoStatus.AVAILABLE: return 'Available';
    case MediaInfoStatus.PARTIALLY_AVAILABLE: return 'Partially available';
    case MediaInfoStatus.PROCESSING: return 'Processing';
    case MediaInfoStatus.PENDING: return 'Requested';
    default: return 'Not requested';
  }
}

function determineStatus(mediaInfo: any, seasons?: OverseerrSeason[]): OverseerrMediaStatus {
  // Check media availability status
  const mediaStatus = mediaInfo?.mediaInfo?.status;
  const requests = mediaInfo?.mediaInfo?.requests || [];

  // If media is available or partially available
  if (mediaStatus === MediaInfoStatus.AVAILABLE) {
    return { status: 'available', canRequest: false, seasons };
  }
  if (mediaStatus === MediaInfoStatus.PARTIALLY_AVAILABLE) {
    const missing = (seasons || []).some((s) => s.seasonNumber > 0 && s.status !== MediaInfoStatus.AVAILABLE);
    return { status: 'partially_available', canRequest: seasons ? missing : true, seasons };
  }
  if (mediaStatus === MediaInfoStatus.PROCESSING) {
    return { status: 'processing', canRequest: false, seasons };
  }

  // Check for pending requests
  const pendingRequest = requests.find((r: any) => r.status === MediaRequestStatus.PENDING);
  if (pendingRequest) {
    return { status: 'pending', requestId: pendingRequest.id, canRequest: false, seasons };
  }

  // Check for approved requests (processing)
  const approvedRequest = requests.find((r: any) => r.status === MediaRequestStatus.APPROVED);
  if (approvedRequest) {
    return { status: 'approved', requestId: approvedRequest.id, canRequest: false, seasons };
  }

  // Check for declined requests
  const declinedRequest = requests.find((r: any) => r.status === MediaRequestStatus.DECLINED);
  if (declinedRequest) {
    return { status: 'declined', requestId: declinedRequest.id, canRequest: true, seasons };
  }

  // No request exists
  return { status: 'not_requested', canRequest: true, seasons };
}

export async function getOverseerrMediaStatus(
  tmdbId: number,
  mediaType: 'movie' | 'tv'
): Promise<OverseerrMediaStatus | null> {
  const config = configured();
  if (!config) return null;

  // Check cache first
  const cacheKey = getCacheKey(tmdbId, mediaType);
  const cached = statusCache.get(cacheKey);
  if (cached && isValidCache(cached)) {
    return cached.status;
  }

  try {
    const endpoint = mediaType === 'movie' ? `/movie/${tmdbId}` : `/tv/${tmdbId}`;
    const response = await fetchOverseerr(config.url, config.apiKey, endpoint);

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
    const seasons: OverseerrSeason[] | undefined = mediaType === 'tv'
      ? mergeSeasons(data.seasons, data.mediaInfo?.seasons)
      : undefined;
    const status = determineStatus(data, seasons);

    // Cache the result
    statusCache.set(cacheKey, { status, timestamp: Date.now() });

    return status;
  } catch (error) {
    console.error('[Overseerr] Error fetching media status:', error);
    return null;
  }
}

/** Season list from the show, with per-season state from `mediaInfo` when present. */
function mergeSeasons(all: any[] | undefined, withStatus: any[] | undefined): OverseerrSeason[] | undefined {
  if (!Array.isArray(all) && !Array.isArray(withStatus)) return undefined;
  const statusByNumber = new Map((withStatus ?? []).map((s: any) => [s.seasonNumber, s.status]));
  return (all ?? withStatus ?? []).map((s: any) => ({
    seasonNumber: s.seasonNumber,
    status: statusByNumber.get(s.seasonNumber) ?? s.status,
    name: s.name,
    episodeCount: s.episodeCount,
  }));
}

/**
 * Requests a title. `seasons` picks specific TV seasons. Without it every
 * season Overseerr can still request is sent.
 */
export async function requestMedia(
  tmdbId: number,
  mediaType: 'movie' | 'tv',
  is4k: boolean = false,
  seasons?: number[]
): Promise<OverseerrRequestResult> {
  const config = configured();
  if (!config) {
    return { success: false, error: 'Overseerr not configured' };
  }

  try {
    let requestSeasons = seasons;
    if (mediaType === 'tv' && !requestSeasons) {
      try {
        const tvResponse = await fetchOverseerr(config.url, config.apiKey, `/tv/${tmdbId}`);
        if (tvResponse.ok) {
          const tvData = await tvResponse.json();
          requestSeasons = (mergeSeasons(tvData.seasons, tvData.mediaInfo?.seasons) ?? [])
            .filter(canRequestSeason)
            .map((s) => s.seasonNumber);
        }
      } catch {}
    }

    const requestBody: any = {
      mediaType,
      mediaId: tmdbId,
      is4k,
    };

    if (requestSeasons && requestSeasons.length > 0) {
      requestBody.seasons = requestSeasons;
    }

    const response = await fetchOverseerr(
      config.url,
      config.apiKey,
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
