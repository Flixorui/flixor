/**
 * Search screen data fetchers using FlixorCore
 */

import { getFlixorCore } from './index';
import { getTmdbBackdropWithTitle } from './HomeData';

export type SearchResult = {
  id: string;
  title: string;
  type: 'movie' | 'show';
  image?: string;
  year?: string;
  source: 'plex' | 'tmdb';
  genreIds?: number[];
  editionTitle?: string;
};

export type RowItem = {
  id: string;
  title: string;
  image?: string;
  year?: string;
  tmdbId?: number;
  mediaType?: 'movie' | 'tv';
};

/**
 * Fetch preferred backdrops with titles for a list of row items
 * Returns a map of id -> backdrop URL
 */
export async function fetchPreferredBackdropsForSearch(
  items: RowItem[]
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

// TMDB Genre mapping
export const GENRE_MAP: { [key: number]: string } = {
  28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy', 80: 'Crime',
  99: 'Documentary', 18: 'Drama', 10751: 'Family', 14: 'Fantasy', 36: 'History',
  27: 'Horror', 10402: 'Music', 9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi',
  10770: 'TV Movie', 53: 'Thriller', 10752: 'War', 37: 'Western',
  10759: 'Action & Adventure', 10762: 'Kids', 10763: 'News', 10764: 'Reality',
  10765: 'Sci-Fi & Fantasy', 10766: 'Soap', 10767: 'Talk', 10768: 'War & Politics'
};

// ============================================
// Search Functions
// ============================================

export async function searchPlex(query: string): Promise<SearchResult[]> {
  try {
    const core = getFlixorCore();
    const items = await core.plexServer.search(query);

    return items.slice(0, 20).map((item: any) => {
      const thumb = item.thumb || item.parentThumb || item.grandparentThumb;
      // Extract edition from Media array
      let editionTitle = item.Media?.[0]?.editionTitle;
      if (!editionTitle) {
        const filePath = item.Media?.[0]?.Part?.[0]?.file;
        if (filePath) {
          const match = filePath.match(/\{edition-([^}]+)\}/i);
          if (match) editionTitle = match[1];
        }
      }
      return {
        id: `plex:${item.ratingKey}`,
        title: item.title || item.grandparentTitle || 'Untitled',
        type: item.type === 'movie' ? 'movie' : 'show',
        image: thumb ? core.plexServer.getImageUrl(thumb, 300) : undefined,
        year: item.year ? String(item.year) : undefined,
        source: 'plex' as const,
        editionTitle,
      };
    });
  } catch (e) {
    console.log('[SearchData] searchPlex error:', e);
    return [];
  }
}

export async function searchTmdb(query: string): Promise<{ movies: SearchResult[]; shows: SearchResult[] }> {
  try {
    const core = getFlixorCore();
    const res = await core.tmdb.searchMulti(query);
    const items = res?.results || [];

    const movies: SearchResult[] = [];
    const shows: SearchResult[] = [];

    items.slice(0, 20).forEach((item: any) => {
      if (item.media_type === 'movie') {
        movies.push({
          id: `tmdb:movie:${item.id}`,
          title: item.title,
          type: 'movie',
          image: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w500') : undefined,
          year: item.release_date?.slice(0, 4),
          source: 'tmdb',
          genreIds: item.genre_ids || [],
        });
      } else if (item.media_type === 'tv') {
        shows.push({
          id: `tmdb:tv:${item.id}`,
          title: item.name,
          type: 'show',
          image: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w500') : undefined,
          year: item.first_air_date?.slice(0, 4),
          source: 'tmdb',
          genreIds: item.genre_ids || [],
        });
      }
    });

    return { movies, shows };
  } catch (e) {
    console.log('[SearchData] searchTmdb error:', e);
    return { movies: [], shows: [] };
  }
}

// ============================================
// Trending/Recommendations
// ============================================

export async function getTrendingForSearch(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const [moviesRes, showsRes] = await Promise.all([
      core.tmdb.getTrendingMovies('week'),
      core.tmdb.getTrendingTV('week'),
    ]);

    const movies = (moviesRes?.results || []).slice(0, 6).map((item: any) => ({
      id: `tmdb:movie:${item.id}`,
      title: item.title,
      image: item.backdrop_path ? core.tmdb.getBackdropUrl(item.backdrop_path, 'w780') : undefined,
      year: item.release_date?.slice(0, 4),
      tmdbId: item.id,
      mediaType: 'movie' as const,
    }));

    const shows = (showsRes?.results || []).slice(0, 6).map((item: any) => ({
      id: `tmdb:tv:${item.id}`,
      title: item.name,
      image: item.backdrop_path ? core.tmdb.getBackdropUrl(item.backdrop_path, 'w780') : undefined,
      year: item.first_air_date?.slice(0, 4),
      tmdbId: item.id,
      mediaType: 'tv' as const,
    }));

    // Interleave movies and shows for variety
    const combined: RowItem[] = [];
    for (let i = 0; i < Math.max(movies.length, shows.length); i++) {
      if (shows[i]) combined.push(shows[i]);
      if (movies[i]) combined.push(movies[i]);
    }

    return combined;
  } catch (e) {
    console.log('[SearchData] getTrendingForSearch error:', e);
    return [];
  }
}

// ============================================
// Genre-based Discovery
// ============================================

export async function discoverByGenre(genreId: number): Promise<SearchResult[]> {
  try {
    const core = getFlixorCore();

    const [movieRes, tvRes] = await Promise.all([
      core.tmdb.discoverMovies({ withGenres: String(genreId) }),
      core.tmdb.discoverTV({ withGenres: String(genreId) }),
    ]);

    const movies = (movieRes?.results || []).slice(0, 10).map((item: any) => ({
      id: `tmdb:movie:${item.id}`,
      title: item.title,
      type: 'movie' as const,
      image: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w500') : undefined,
      year: item.release_date?.slice(0, 4),
      source: 'tmdb' as const,
    }));

    const shows = (tvRes?.results || []).slice(0, 10).map((item: any) => ({
      id: `tmdb:tv:${item.id}`,
      title: item.name,
      type: 'show' as const,
      image: item.poster_path ? core.tmdb.getPosterUrl(item.poster_path, 'w500') : undefined,
      year: item.first_air_date?.slice(0, 4),
      source: 'tmdb' as const,
    }));

    return [...movies, ...shows].slice(0, 15);
  } catch (e) {
    console.log('[SearchData] discoverByGenre error:', e);
    return [];
  }
}
