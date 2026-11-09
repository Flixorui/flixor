import { loadSettings, saveSettings } from '@/state/settings';
import { cached } from '@/services/cache';
import { API_BASE_URL } from './api';
import { clearTraktReconnect, traktNeedsReconnect } from './traktConnection';

// Always use backend proxy for Trakt (same-origin or configured API base)
const TRAKT = `${API_BASE_URL.replace(/\/$/, '')}/trakt`;

export class TraktApiError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = 'TraktApiError';
    this.status = status;
  }
}

/** JSON request to the backend's Trakt routes, using the session cookie. */
async function traktFetch<T = any>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${TRAKT}${path}`, {
    ...init,
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...init?.headers },
  });
  if (!response.ok) {
    let message = `Trakt request failed: ${response.status}`;
    try {
      const body = await response.json();
      if (body?.message || body?.error) message = String(body.message || body.error);
    } catch {
      // Keep the status message.
    }
    throw new TraktApiError(response.status, message);
  }
  return response.json();
}

export interface TraktDeviceCode {
  device_code: string;
  user_code: string;
  verification_url: string;
  expires_in: number;
  interval: number;
}

export interface TraktTokens {
  access_token: string;
  token_type: string;
  expires_in: number;
  refresh_token: string;
  scope: string;
  created_at: number;
}

export interface TraktUser {
  username: string;
  private: boolean;
  name: string;
  vip: boolean;
  vip_ep: boolean;
  ids: {
    slug: string;
  };
  joined_at: string;
  location: string;
  about: string;
  gender: string;
  age: number;
  images: {
    avatar: {
      full: string;
    };
  };
}

export interface TraktScrobble {
  movie?: TraktMovie;
  show?: TraktShow;
  episode?: TraktEpisode;
  progress: number;
  app_version: string;
  app_date: string;
}

export interface TraktMovie {
  title: string;
  year: number;
  ids: {
    trakt: number;
    slug: string;
    imdb?: string;
    tmdb?: number;
  };
}

export interface TraktShow {
  title: string;
  year: number;
  ids: {
    trakt: number;
    slug: string;
    imdb?: string;
    tmdb?: number;
    tvdb?: number;
  };
}

export interface TraktEpisode {
  season: number;
  number: number;
  title?: string;
  ids: {
    trakt: number;
    tvdb?: number;
    imdb?: string;
    tmdb?: number;
  };
}

// Authentication
export async function traktRequestDeviceCode(): Promise<TraktDeviceCode> {
  const response = await fetch(`${TRAKT}/oauth/device/code`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({})
  });

  if (!response.ok) {
    throw new Error(`Failed to get device code: ${response.status}`);
  }

  return response.json();
}

export async function traktPollForToken(deviceCode: string): Promise<TraktTokens | null> {
  const response = await fetch(`${TRAKT}/oauth/device/token`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: deviceCode })
  });

  // If backend is down or route missing
  if (!response.ok && response.status !== 400) {
    throw new Error(`Failed to poll token: ${response.status}`);
  }

  // Backend returns 200 with { ok:false, error } while pending
  // or { ok:true, tokens } when authorized.
  let data: any = null;
  try {
    data = await response.json();
  } catch {
    // If server ever returns empty body on 400 pending
    if (response.status === 400) return null;
    throw new Error('Failed to parse token response');
  }

  // Pending or temporary states
  if (data && data.ok === false) {
    const err = String(data.error || 'authorization_pending');
    if (err === 'expired_token') {
      // Signal caller to stop polling and restart
      throw new Error('device_code_expired');
    }
    if (err === 'access_denied' || err === 'invalid_grant' || err === 'invalid_client') {
      throw new Error(err);
    }
    // Treat authorization_pending / slow_down / temporarily_unavailable / server_error as pending
    return null;
  }

  // Success envelope from backend
  if (data && data.ok === true && data.tokens) {
    clearTraktReconnect();
    return data.tokens as TraktTokens;
  }

  // In case backend returns raw Trakt tokens directly
  if (data && data.access_token) {
    clearTraktReconnect();
    return data as TraktTokens;
  }

  throw new Error('Unexpected token response');
}

export async function traktRefreshToken(_refreshToken: string): Promise<TraktTokens> {
  // The backend holds the refresh token.
  return traktFetch<TraktTokens>('/oauth/token', { method: 'POST', body: '{}' });
}

/** Revokes the token on Trakt and clears it from the backend. */
export async function traktRevokeToken(_accessToken: string): Promise<void> {
  await traktFetch('/oauth/revoke', { method: 'POST', body: '{}' });
}

// User
export async function traktGetUserProfile(_accessToken: string): Promise<TraktUser> {
  // Use backend + session cookie
  const response = await fetch(`${TRAKT}/users/me`, { credentials: 'include' });

  if (!response.ok) {
    throw new Error(`Failed to get user profile: ${response.status}`);
  }

  return response.json();
}

export async function traktGetUserSettings(accessToken: string): Promise<any> {
  const response = await fetch(`${TRAKT}/users/me`, { credentials: 'include' });
  
  if (!response.ok) {
    throw new Error(`Failed to get user settings: ${response.status}`);
  }
  
  return response.json();
}

// Scrobbling
export async function traktScrobbleStart(accessToken: string, item: TraktScrobble): Promise<any> {
  const response = await fetch(`${TRAKT}/scrobble/start`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(item)
  });

  if (!response.ok) {
    // 409 = already scrobbling, which is fine
    if (response.status === 409) return { action: 'scrobbling' };
    throw new Error(`Failed to start scrobble: ${response.status}`);
  }

  return response.json();
}

export async function traktScrobblePause(accessToken: string, item: TraktScrobble): Promise<any> {
  const response = await fetch(`${TRAKT}/scrobble/pause`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(item)
  });

  if (!response.ok) {
    throw new Error(`Failed to pause scrobble: ${response.status}`);
  }

  return response.json();
}

export async function traktScrobbleStop(accessToken: string, item: TraktScrobble): Promise<any> {
  const response = await fetch(`${TRAKT}/scrobble/stop`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(item)
  });

  if (!response.ok) {
    throw new Error(`Failed to stop scrobble: ${response.status}`);
  }

  return response.json();
}

// History
export async function traktGetHistory(accessToken: string, type?: 'movies' | 'shows', limit?: number): Promise<any[]> {
  let url = `${TRAKT}/users/me/history`;
  if (type) url += `/${type}`;
  if (limit) url += `?limit=${limit}`;
  const response = await fetch(url, { credentials: 'include' });

  if (!response.ok) throw new Error(`Failed to get history: ${response.status}`);
  return response.json();
}

export interface TraktSyncResult {
  added?: Record<string, number>;
  deleted?: Record<string, number>;
  not_found?: Record<string, unknown[]>;
}

export async function traktAddToHistory(_accessToken: string, items: any): Promise<TraktSyncResult> {
  return traktSyncHistoryAdd(items);
}

export async function traktRemoveFromHistory(_accessToken: string, items: any): Promise<TraktSyncResult> {
  return traktSyncHistoryRemove(items);
}

export const traktSyncHistoryAdd = (items: any) =>
  traktFetch<TraktSyncResult>('/sync/history', { method: 'POST', body: JSON.stringify(items) });

export const traktSyncHistoryRemove = (items: any) =>
  traktFetch<TraktSyncResult>('/sync/history/remove', { method: 'POST', body: JSON.stringify(items) });

export const traktItemHistory = (type: 'movies' | 'shows' | 'seasons' | 'episodes', traktId: number, limit = 1) =>
  traktFetch<any[]>(`/sync/history/${type}/${traktId}?limit=${limit}`);

// Playback progress
export interface TraktPlaybackItem {
  id: number;
  progress: number;
  paused_at?: string;
  type: 'movie' | 'episode';
  movie?: TraktMovie & { runtime?: number };
  show?: TraktShow & { runtime?: number };
  episode?: TraktEpisode & { runtime?: number };
}

export const traktGetPlayback = (type?: 'movies' | 'episodes') =>
  traktFetch<TraktPlaybackItem[]>(`/sync/playback${type ? `/${type}` : ''}`);

export const traktRemovePlayback = (id: number) =>
  traktFetch(`/sync/playback/${id}`, { method: 'DELETE' });

// Ratings
export const traktGetRatings = (type: 'movies' | 'shows' | 'seasons' | 'episodes') =>
  traktFetch<any[]>(`/sync/ratings/${type}`);

export const traktAddRatings = (items: any) =>
  traktFetch<TraktSyncResult>('/sync/ratings', { method: 'POST', body: JSON.stringify(items) });

export const traktRemoveRatings = (items: any) =>
  traktFetch<TraktSyncResult>('/sync/ratings/remove', { method: 'POST', body: JSON.stringify(items) });

// Watched shows and show progress
export interface TraktWatchedShowSummary {
  last_watched_at?: string;
  show: TraktShow & { runtime?: number };
}

export interface TraktShowProgress {
  aired: number;
  completed: number;
  last_watched_at?: string;
  seasons: Array<{
    number: number;
    aired: number;
    completed: number;
    episodes: Array<{ number: number; completed: boolean; last_watched_at?: string }>;
  }>;
  next_episode?: (TraktEpisode & { runtime?: number }) | null;
}

export const traktWatchedShows = () => traktFetch<TraktWatchedShowSummary[]>('/sync/watched/shows');

export const traktShowProgress = (showId: string | number) =>
  traktFetch<TraktShowProgress>(`/shows/${encodeURIComponent(String(showId))}/progress/watched`);

/** Finds the Trakt item for an external id. Works without a Trakt login. */
export async function traktLookupId(
  source: 'tmdb' | 'imdb' | 'tvdb',
  id: string | number,
  type?: 'movie' | 'show',
): Promise<any | null> {
  const results = await traktFetch<any[]>(
    `/search/id/${source}/${encodeURIComponent(String(id))}${type ? `?type=${type}` : ''}`,
  );
  const wanted = (r: any) => !type || r?.type === type;
  return (results || []).find(wanted) ?? null;
}

// Watchlist
export async function traktGetWatchlist(accessToken: string, type?: 'movies' | 'shows'): Promise<any[]> {
  let url = `${TRAKT}/users/me/watchlist`;
  if (type) url += `/${type}`;
  const response = await fetch(url, { credentials: 'include' });

  if (!response.ok) throw new Error(`Failed to get watchlist: ${response.status}`);
  return response.json();
}

export async function traktAddToWatchlist(accessToken: string, items: any[]): Promise<any> {
  const response = await fetch(`${TRAKT}/watchlist`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(items)
  });

  if (!response.ok) throw new Error(`Failed to add to watchlist: ${response.status}`);
  return response.json();
}

export async function traktRemoveFromWatchlist(accessToken: string, items: any[]): Promise<any> {
  const response = await fetch(`${TRAKT}/watchlist/remove`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(items)
  });

  if (!response.ok) throw new Error(`Failed to remove from watchlist: ${response.status}`);
  return response.json();
}

// Recommendations
export async function traktGetRecommendations(accessToken: string, type: 'movies' | 'shows', limit?: number): Promise<any[]> {
  let url = `${TRAKT}/recommendations/${type}`;
  if (limit) url += `?limit=${limit}`;
  const response = await fetch(url, { credentials: 'include' });

  if (!response.ok) throw new Error(`Failed to get recommendations: ${response.status}`);
  return response.json();
}

// Search
export async function traktSearch(query: string, type?: 'movie' | 'show' | 'episode', limit?: number): Promise<any[]> {
  const searchType = type || 'movie,show';
  let url = `${TRAKT}/search/${searchType}?query=${encodeURIComponent(query)}`;
  if (limit) url += `&limit=${limit}`;
  const response = await fetch(url, { credentials: 'include' });

  if (!response.ok) throw new Error(`Failed to search: ${response.status}`);
  return response.json();
}

// Trending (existing, updated)
export async function traktTrending(type: 'movies'|'shows' = 'movies', limit?: number): Promise<any[]> {
  let url = `${TRAKT}/trending/${type}`;
  if (limit) url += `?limit=${limit}`;
  const response = await fetch(url, { credentials: 'include' });

  if (!response.ok) throw new Error(`Failed to get trending: ${response.status}`);
  return response.json();
}

// Popular
export async function traktPopular(type: 'movies' | 'shows', limit?: number): Promise<any[]> {
  let url = `${TRAKT}/popular/${type}`;
  if (limit) url += `?limit=${limit}`;
  const response = await fetch(url, { credentials: 'include' });

  if (!response.ok) throw new Error(`Failed to get popular: ${response.status}`);
  return response.json();
}

// Most Watched (charts) with period: daily | weekly | monthly | yearly | all
export async function traktMostWatched(type: 'movies'|'shows', period: 'daily'|'weekly'|'monthly'|'yearly'|'all' = 'weekly', limit?: number): Promise<any[]> {
  const urlBase = `${TRAKT}/${type}/watched/${period}`;
  const url = limit ? `${urlBase}?limit=${limit}` : urlBase;
  // 30m TTL
  return cached(`trakt:mostwatched:${type}:${period}:${limit||'all'}`, 30 * 60 * 1000, async () => {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Failed to get most watched: ${res.status}`);
    return res.json();
  });
}

// Anticipated (most lists)
export async function traktAnticipated(type: 'movies'|'shows', limit?: number): Promise<any[]> {
  // Web-only
  const urlBase = `${TRAKT}/${type}/anticipated`;
  const url = limit ? `${urlBase}?limit=${limit}` : urlBase;
  return cached(`trakt:anticipated:${type}:${limit||'all'}`, 30 * 60 * 1000, async () => {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Failed to get anticipated: ${res.status}`);
    return res.json();
  });
}

// Token Management Helpers
export function getTraktTokens(): TraktTokens | null {
  if (traktNeedsReconnect()) return null;
  const settings = loadSettings();
  if (settings.traktTokens) {
    try {
      return JSON.parse(settings.traktTokens);
    } catch {
      return null;
    }
  }
  return null;
}

export function saveTraktTokens(tokens: TraktTokens | null): void {
  saveSettings({
    traktTokens: tokens ? JSON.stringify(tokens) : undefined
  });
}

export function isTraktAuthenticated(): boolean {
  const tokens = getTraktTokens();
  if (!tokens) return false;

  // The backend refreshes expired tokens, so a refresh token is enough.
  const expiresAt = (tokens.created_at + tokens.expires_in) * 1000;
  return Date.now() < expiresAt || !!tokens.refresh_token;
}

export async function ensureValidToken(): Promise<string | null> {
  const tokens = getTraktTokens();
  if (!tokens) return null;

  const expiresAt = (tokens.created_at + tokens.expires_in) * 1000;
  const isExpired = Date.now() >= expiresAt;

  if (isExpired && tokens.refresh_token) {
    try {
      const newTokens = await traktRefreshToken(tokens.refresh_token);
      saveTraktTokens(newTokens);
      return newTokens.access_token;
    } catch (error) {
      console.error('Failed to refresh Trakt token:', error);
      saveTraktTokens(null);
      return null;
    }
  }

  return tokens.access_token;
}
