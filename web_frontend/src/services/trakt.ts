import { loadSettings, saveSettings } from '@/state/settings';
import { cached } from '@/services/cache';
import { API_BASE_URL } from './api';

// Always use backend proxy for Trakt (same-origin or configured API base)
const TRAKT = `${API_BASE_URL.replace(/\/$/, '')}/trakt`;
// Keep client constants unused to avoid exposing secrets in the browser
const CLIENT_ID = '';
const CLIENT_SECRET = '';

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
    return data.tokens as TraktTokens;
  }

  // In case backend returns raw Trakt tokens directly
  if (data && data.access_token) {
    return data as TraktTokens;
  }

  throw new Error('Unexpected token response');
}

export async function traktRefreshToken(refreshToken: string): Promise<TraktTokens> {
  // Web fallback

  // Web fallback
  const response = await fetch(`${TRAKT}/oauth/token`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      refresh_token: refreshToken,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      grant_type: 'refresh_token'
    })
  });

  if (!response.ok) {
    throw new Error(`Failed to refresh token: ${response.status}`);
  }

  return response.json();
}

export async function traktRevokeToken(accessToken: string): Promise<void> {
  // Web fallback

  // Web fallback
  const response = await fetch(`${TRAKT}/oauth/revoke`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      token: accessToken,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET
    })
  });

  if (!response.ok) {
    throw new Error(`Failed to revoke token: ${response.status}`);
  }
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
export async function traktScrobbleStart(accessToken: string, item: TraktScrobble): Promise<any> { throw new Error('Trakt scrobble not supported via backend'); }

export async function traktScrobblePause(accessToken: string, item: TraktScrobble): Promise<any> { throw new Error('Trakt scrobble not supported via backend'); }

export async function traktScrobbleStop(accessToken: string, item: TraktScrobble): Promise<any> { throw new Error('Trakt scrobble not supported via backend'); }

// History
export async function traktGetHistory(accessToken: string, type?: 'movies' | 'shows', limit?: number): Promise<any[]> {
  let url = `${TRAKT}/users/me/history`;
  if (type) url += `/${type}`;
  if (limit) url += `?limit=${limit}`;
  const response = await fetch(url, { credentials: 'include' });

  if (!response.ok) throw new Error(`Failed to get history: ${response.status}`);
  return response.json();
}

export async function traktAddToHistory(accessToken: string, items: any[]): Promise<any> {
  // Web-only

  const response = await fetch(`${TRAKT}/sync/history`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      'trakt-api-version': '2',
      'trakt-api-key': CLIENT_ID
    },
    body: JSON.stringify(items)
  });

  if (!response.ok) throw new Error(`Failed to add to history: ${response.status}`);
  return response.json();
}

export async function traktRemoveFromHistory(accessToken: string, items: any[]): Promise<any> {
  // Web-only

  const response = await fetch(`${TRAKT}/sync/history/remove`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      'trakt-api-version': '2',
      'trakt-api-key': CLIENT_ID
    },
    body: JSON.stringify(items)
  });

  if (!response.ok) throw new Error(`Failed to remove from history: ${response.status}`);
  return response.json();
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

// Progress
export async function traktGetProgress(accessToken: string, type: 'shows', sort?: string): Promise<any[]> {
  let url = `${TRAKT}/users/me/watched/${type}/progress`;
  if (sort) url += `?sort=${sort}`;
  const response = await fetch(url, { credentials: 'include' });

  if (!response.ok) throw new Error(`Failed to get progress: ${response.status}`);
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
    const res = await fetch(url, {
      headers: { 'trakt-api-version': '2', 'trakt-api-key': CLIENT_ID }
    });
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
    const res = await fetch(url, {
      headers: { 'trakt-api-version': '2', 'trakt-api-key': CLIENT_ID }
    });
    if (!res.ok) throw new Error(`Failed to get anticipated: ${res.status}`);
    return res.json();
  });
}

// Token Management Helpers
export function getTraktTokens(): TraktTokens | null {
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

  // Check if token is expired
  const expiresAt = (tokens.created_at + tokens.expires_in) * 1000;
  return Date.now() < expiresAt;
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
