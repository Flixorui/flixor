// Plex-backed ratings helpers
import { API_BASE_URL } from './api';

// Plex-backed ratings by ratingKey (server metadata)
export async function fetchPlexRatingsByRatingKey(ratingKey: string): Promise<{ imdb?: { rating?: number; votes?: number } | null; rt?: { critic?: number; audience?: number } | null } | null> {
  if (!ratingKey) return null;
  const base = `${API_BASE_URL.replace(/\/$/, '')}/plex/ratings`;
  const res = await fetch(`${base}/${encodeURIComponent(ratingKey)}`, { credentials: 'include' });
  if (!res.ok) return null;
  const data = await res.json();
  return { imdb: data.imdb || null, rt: data.rottenTomatoes || null };
}

export async function fetchPlexVodRatingsById(vodId: string): Promise<{ imdb?: { rating?: number; votes?: number } | null; rt?: { critic?: number; audience?: number } | null } | null> {
  if (!vodId) return null;
  const base = `${API_BASE_URL.replace(/\/$/, '')}/plex/vod/ratings`;
  const res = await fetch(`${base}/${encodeURIComponent(vodId)}`, { credentials: 'include' });
  if (!res.ok) return null;
  const data = await res.json();
  return { imdb: data.imdb || null, rt: data.rottenTomatoes || null };
}
