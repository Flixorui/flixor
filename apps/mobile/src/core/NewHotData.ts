/**
 * New & Hot screen data fetchers using FlixorCore
 */

import { getFlixorCore } from './index';
import { getTmdbBackdropWithTitle } from './HomeData';

export type ContentItem = {
  id: string;
  title: string;
  image?: string;
  backdropImage?: string;
  subtitle?: string;
  description?: string;
  releaseDate?: string;
  badge?: string;
  rank?: number;
  tmdbId?: number;
  mediaType?: 'movie' | 'tv';
};

/**
 * Fetch preferred backdrops with titles for a list of content items
 * Returns a map of id -> backdrop URL
 */
export async function fetchPreferredBackdrops(
  items: ContentItem[]
): Promise<Record<string, string>> {
  const results: Record<string, string> = {};

  await Promise.all(
    items.map(async (item) => {
      if (!item.tmdbId || !item.mediaType) return;
      try {
        const backdrop = await getTmdbBackdropWithTitle(item.tmdbId, item.mediaType);
        if (backdrop) {
          results[item.id] = backdrop;
        }
      } catch {
        // Silently fail - fallback to default backdrop
      }
    })
  );

  return results;
}

// ============================================
// Content Loaders
// ============================================

export async function getUpcomingMovies(): Promise<ContentItem[]> {
  try {
    const core = getFlixorCore();
    const res = await core.tmdb.getUpcomingMovies();

    return (res?.results || []).slice(0, 20).map((item: any) => ({
      id: `tmdb:movie:${item.id}`,
      title: item.title,
      image: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w500') : undefined,
      backdropImage: item.backdrop_path ? core.tmdb.getBackdropUrl(item.backdrop_path, 'w780') : undefined,
      description: item.overview,
      releaseDate: item.release_date
        ? new Date(item.release_date).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
        : undefined,
      badge: 'Coming Soon',
      tmdbId: item.id,
      mediaType: 'movie' as const,
    }));
  } catch (e) {
    console.log('[NewHotData] getUpcomingMovies error:', e);
    return [];
  }
}

export async function getTrendingAll(): Promise<ContentItem[]> {
  try {
    const core = getFlixorCore();
    const res = await core.tmdb.getTrendingAll('week');

    return (res?.results || []).slice(0, 20).map((item: any) => ({
      id: item.media_type === 'movie' ? `tmdb:movie:${item.id}` : `tmdb:tv:${item.id}`,
      title: item.title || item.name,
      image: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w500') : undefined,
      backdropImage: item.backdrop_path ? core.tmdb.getBackdropUrl(item.backdrop_path, 'w780') : undefined,
      description: item.overview,
      subtitle: (item.release_date || item.first_air_date)?.split('-')[0],
      badge: item.vote_average ? `⭐ ${item.vote_average.toFixed(1)}` : undefined,
      tmdbId: item.id,
      mediaType: item.media_type === 'movie' ? 'movie' as const : 'tv' as const,
    }));
  } catch (e) {
    console.log('[NewHotData] getTrendingAll error:', e);
    return [];
  }
}

export async function getTop10Shows(): Promise<ContentItem[]> {
  try {
    const core = getFlixorCore();
    const res = await core.tmdb.getTrendingTV('week');

    return (res?.results || []).slice(0, 10).map((item: any, index: number) => ({
      id: `tmdb:tv:${item.id}`,
      title: item.name,
      image: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w500') : undefined,
      backdropImage: item.backdrop_path ? core.tmdb.getBackdropUrl(item.backdrop_path, 'w780') : undefined,
      description: item.overview,
      subtitle: item.first_air_date?.split('-')[0],
      rank: index + 1,
      tmdbId: item.id,
      mediaType: 'tv' as const,
    }));
  } catch (e) {
    console.log('[NewHotData] getTop10Shows error:', e);
    return [];
  }
}

export async function getTop10Movies(): Promise<ContentItem[]> {
  try {
    const core = getFlixorCore();
    const res = await core.tmdb.getTrendingMovies('week');

    return (res?.results || []).slice(0, 10).map((item: any, index: number) => ({
      id: `tmdb:movie:${item.id}`,
      title: item.title,
      image: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w500') : undefined,
      backdropImage: item.backdrop_path ? core.tmdb.getBackdropUrl(item.backdrop_path, 'w780') : undefined,
      description: item.overview,
      subtitle: item.release_date?.split('-')[0],
      rank: index + 1,
      tmdbId: item.id,
      mediaType: 'movie' as const,
    }));
  } catch (e) {
    console.log('[NewHotData] getTop10Movies error:', e);
    return [];
  }
}
