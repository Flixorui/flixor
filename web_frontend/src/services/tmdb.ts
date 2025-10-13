/**
 * TMDB Service - Proxies all requests through backend
 */

import { API_BASE_URL } from './api';
const BACKEND_BASE = `${API_BASE_URL.replace(/\/$/, '')}/tmdb`;
const IMG = 'https://image.tmdb.org/t/p';

// Keep local cache for already fetched data
import { cached } from './cache';

/**
 * Fetch from backend TMDB proxy
 */
async function tmdbBackendFetch(path: string, params?: Record<string, any>): Promise<any> {
  const base = BACKEND_BASE.replace(/\/$/, '');
  let url = `${base}${path}`;
  if (params) {
    const qs = new URLSearchParams();
    Object.entries(params).forEach(([key, value]) => {
      if (value !== undefined && value !== null) qs.append(key, String(value));
    });
    const q = qs.toString();
    if (q) url += (url.includes('?') ? '&' : '?') + q;
  }

  const response = await fetch(url, {
    credentials: 'include', // Include cookies for session
  });

  if (!response.ok) {
    throw new Error(`TMDB API error: ${response.status}`);
  }

  return response.json();
}

// Export types
export type TmdbTrendingItem = {
  id: number;
  title?: string;
  name?: string;
  poster_path?: string;
  backdrop_path?: string;
  media_type?: string;
};

/**
 * Get trending content (uses backend proxy)
 */
export async function tmdbTrending(key: string, media: 'movie'|'tv' = 'movie', window: 'day'|'week' = 'week') {
  // Note: key parameter is kept for compatibility but not used (backend handles auth)
  return cached(`tmdb:trending:${media}:${window}`, 30 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/trending/${media}/${window}`);
  });
}

/**
 * Get image URL (client-side helper)
 */
export function tmdbImage(path?: string, size: 'w500'|'w780'|'w1280'|'original' = 'w780') {
  return path ? `${IMG}/${size}${path}` : undefined;
}

/**
 * Get movie or TV details
 */
export async function tmdbDetails(key: string, media: 'movie'|'tv', id: string | number) {
  return cached(`tmdb:details:${media}:${id}`, 24 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/${media}/${id}`);
  });
}

/**
 * Get credits
 */
export async function tmdbCredits(key: string, media: 'movie'|'tv', id: string | number) {
  return cached(`tmdb:credits:${media}:${id}`, 24 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/${media}/${id}/credits`);
  });
}

/**
 * Get external IDs
 */
export async function tmdbExternalIds(key: string, media: 'movie'|'tv', id: string | number) {
  return cached(`tmdb:external:${media}:${id}`, 24 * 60 * 60 * 1000, async () => {
    const details = await tmdbBackendFetch(`/${media}/${id}`, {
      append_to_response: 'external_ids'
    });
    return details.external_ids || {};
  });
}

/**
 * Get recommendations
 */
export async function tmdbRecommendations(key: string, media: 'movie'|'tv', id: string | number, page?: number) {
  return cached(`tmdb:recs:${media}:${id}:${page||1}`, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/${media}/${id}/recommendations`, { page });
  });
}

/**
 * Get similar content
 */
export async function tmdbSimilar(key: string, media: 'movie'|'tv', id: string | number, page?: number) {
  return cached(`tmdb:similar:${media}:${id}:${page||1}`, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/${media}/${id}/similar`, { page });
  });
}

/**
 * Search for titles
 */
export async function tmdbSearchTitle(key: string, media: 'movie'|'tv', query: string, year?: string | number) {
  return cached(`tmdb:search:${media}:${query}:${year||''}`, 6 * 60 * 60 * 1000, async () => {
    const endpoint = media === 'movie' ? '/search/movie' : '/search/tv';
    return tmdbBackendFetch(endpoint, { query, year });
  });
}

/**
 * Get TV seasons
 */
export async function tmdbTvSeasons(key: string, tvId: string | number) {
  return cached(`tmdb:tv:seasons:${tvId}`, 24 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/tv/${tvId}`);
  });
}

/**
 * Get TV season episodes
 */
export async function tmdbTvSeasonEpisodes(key: string, tvId: string | number, seasonNumber: number) {
  return cached(`tmdb:tv:season:${tvId}:${seasonNumber}`, 24 * 60 * 60 * 1000, async () => {
    const details = await tmdbBackendFetch(`/tv/${tvId}`);
    const season = details.seasons?.find((s: any) => s.season_number === seasonNumber);
    return season || {};
  });
}

/**
 * Search for person
 */
export async function tmdbSearchPerson(key: string, name: string) {
  return cached(`tmdb:searchPerson:${name}`, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch('/search/multi', { query: name });
  });
}

/**
 * Get person combined credits
 */
export async function tmdbPersonCombined(key: string, personId: string | number) {
  return cached(`tmdb:personCombined:${personId}`, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/person/${personId}/combined_credits`);
  });
}

/**
 * Get videos
 */
export async function tmdbVideos(key: string, media: 'movie'|'tv', id: string | number) {
  return cached(`tmdb:videos:${media}:${id}`, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/${media}/${id}/videos`);
  });
}

/**
 * Search multi
 */
export async function tmdbSearchMulti(key: string, query: string) {
  return cached(`tmdb:searchMulti:${query}`, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch('/search/multi', { query });
  });
}

/**
 * Get popular content
 */
export async function tmdbPopular(key: string, media: 'movie'|'tv' = 'movie') {
  return cached(`tmdb:popular:${media}`, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/${media}/popular`);
  });
}

/**
 * Get images
 */
export async function tmdbImages(key: string, media: 'movie'|'tv', id: string | number, includeImageLanguage = 'en,null') {
  return cached(`tmdb:images:${media}:${id}:${includeImageLanguage}`, 24 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch(`/${media}/${id}/images`, { language: includeImageLanguage });
  });
}

/**
 * Get best backdrop URL
 */
export async function tmdbBestBackdropUrl(key: string, media: 'movie'|'tv', id: string | number, lang: string = 'en'): Promise<string | undefined> {
  try {
    const imgs = await tmdbImages(key, media, id, `${lang},null`);
    const list = (imgs as any).backdrops || [];

    // Pick best backdrop
    const pick = (arr: any[]) => arr.sort((a: any, b: any) => b.vote_average - a.vote_average)[0];
    const en = pick(list.filter((x: any) => x.iso_639_1 === lang));
    const nul = pick(list.filter((x: any) => !x.iso_639_1));
    const any = pick(list);
    const sel = en || nul || any;

    return sel?.file_path ? tmdbImage(sel.file_path, 'original') : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Get upcoming movies
 */
export async function tmdbUpcoming(key: string, region?: string) {
  return cached(`tmdb:upcoming:${region || 'US'}`, 30 * 60 * 1000, async () => {
    return tmdbBackendFetch('/movie/upcoming', { region });
  });
}

/**
 * Discover movies
 */
export async function tmdbDiscoverMovies(key: string, params?: any) {
  const cacheKey = `tmdb:discover:movie:${JSON.stringify(params || {})}`;
  return cached(cacheKey, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch('/discover/movie', params);
  });
}

/**
 * Discover TV shows
 */
export async function tmdbDiscoverTV(key: string, params?: any) {
  const cacheKey = `tmdb:discover:tv:${JSON.stringify(params || {})}`;
  return cached(cacheKey, 6 * 60 * 60 * 1000, async () => {
    return tmdbBackendFetch('/discover/tv', params);
  });
}

/**
 * Note: The 'key' parameter is maintained in all functions for backward compatibility
 * but is no longer used since the backend handles authentication with its own keys.
 * This can be removed in a future refactor once all calling code is updated.
 */
