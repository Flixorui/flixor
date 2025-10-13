import { API_BASE_URL } from './api';
const API_BASE = `${API_BASE_URL.replace(/\/$/, '')}/plextv`;

export function clearPlexTvWatchlistCache() {
  // Backend caches; nothing to clear on the client beyond any UI state
}

// Backend-proxied Plex.tv watchlist
export async function plexTvWatchlist(): Promise<any> {
  const res = await fetch(`${API_BASE}/watchlist`, { credentials: 'include' });
  if (!res.ok) throw new Error(`PlexTV watchlist error: ${res.status}`);
  return res.json();
}

// Add an item to Plex.tv Watchlist via backend
export async function plexTvAddToWatchlist(idOrGuid: string) {
  const res = await fetch(`${API_BASE}/watchlist/${encodeURIComponent(idOrGuid)}`, { method: 'PUT', credentials: 'include' });
  if (!res.ok) throw new Error(`Failed to add to Plex.tv Watchlist: ${res.status}`);
  return true;
}

// Remove an item from Plex.tv Watchlist via backend
export async function plexTvRemoveFromWatchlist(idOrGuid: string) {
  const res = await fetch(`${API_BASE}/watchlist/${encodeURIComponent(idOrGuid)}`, { method: 'DELETE', credentials: 'include' });
  if (!res.ok) throw new Error(`Failed to remove from Plex.tv Watchlist: ${res.status}`);
  return true;
}
