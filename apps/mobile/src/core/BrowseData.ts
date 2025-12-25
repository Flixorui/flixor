/**
 * Browse data fetchers for RowBrowseModal
 * Fetches paginated data based on BrowseContext
 */

import { getFlixorCore } from './index';
import type { BrowseContext, BrowseItem, BrowseResult } from '@flixor/core';
import type { PlexMediaItem, TMDBMedia } from '@flixor/core';

// Helper: Parallel processing with concurrency limit
async function withLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const ret: R[] = [];
  let idx = 0;
  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      ret[i] = await fn(items[i]);
    }
  }
  const workers = Array.from({ length: Math.min(limit, items.length) }).map(worker);
  await Promise.all(workers);
  return ret;
}

const PAGE_SIZE = 20;

/**
 * Fetch browse items for a given context and page
 */
export async function fetchBrowseItems(
  context: BrowseContext,
  page: number = 1
): Promise<BrowseResult> {
  try {
    switch (context.type) {
      case 'plexDirectory':
        return fetchPlexDirectory(context.path, page);
      case 'plexLibrary':
        return fetchPlexLibrary(context.libraryKey, page);
      case 'plexWatchlist':
        return fetchPlexWatchlist(page);
      case 'tmdb':
        return fetchTmdbBrowse(context, page);
      case 'trakt':
        return fetchTraktBrowse(context, page);
      default:
        return { items: [], hasMore: false };
    }
  } catch (e) {
    console.log('[BrowseData] fetchBrowseItems error:', e);
    return { items: [], hasMore: false };
  }
}

/**
 * Fetch from a Plex directory path (genre, hub, etc.)
 */
async function fetchPlexDirectory(path: string, page: number): Promise<BrowseResult> {
  try {
    const core = getFlixorCore();
    const offset = (page - 1) * PAGE_SIZE;

    // Parse the path to add pagination params
    const separator = path.includes('?') ? '&' : '?';
    const paginatedPath = `${path}${separator}X-Plex-Container-Start=${offset}&X-Plex-Container-Size=${PAGE_SIZE}`;

    const response = await core.plexServer.fetchDirectory(paginatedPath) as any;
    const items = (response.Metadata || []) as PlexMediaItem[];
    const totalSize = response.totalSize || response.size || items.length;

    const browseItems: BrowseItem[] = items.map((item) => ({
      id: `plex:${item.ratingKey}`,
      title: item.title || item.grandparentTitle || 'Untitled',
      image: item.thumb ? core.plexServer.getImageUrl(item.thumb, 300) : undefined,
      year: item.year,
    }));

    return {
      items: browseItems,
      hasMore: offset + items.length < totalSize,
      totalCount: totalSize,
    };
  } catch (e) {
    console.log('[BrowseData] fetchPlexDirectory error:', e);
    return { items: [], hasMore: false };
  }
}

/**
 * Fetch all items from a Plex library
 */
async function fetchPlexLibrary(libraryKey: string, page: number): Promise<BrowseResult> {
  try {
    const core = getFlixorCore();
    const offset = (page - 1) * PAGE_SIZE;

    const response = await core.plexServer.getLibraryItems(libraryKey, {
      offset: offset,
      limit: PAGE_SIZE,
    });

    const totalSize = (response as any).totalSize || response.length;
    const items = Array.isArray(response) ? response : (response as any).Metadata || [];

    const browseItems: BrowseItem[] = items.map((item: PlexMediaItem) => ({
      id: `plex:${item.ratingKey}`,
      title: item.title || 'Untitled',
      image: item.thumb ? core.plexServer.getImageUrl(item.thumb, 300) : undefined,
      year: item.year,
    }));

    return {
      items: browseItems,
      hasMore: offset + items.length < totalSize,
      totalCount: totalSize,
    };
  } catch (e) {
    console.log('[BrowseData] fetchPlexLibrary error:', e);
    return { items: [], hasMore: false };
  }
}

/**
 * Fetch Plex.tv watchlist
 */
async function fetchPlexWatchlist(page: number): Promise<BrowseResult> {
  try {
    const core = getFlixorCore();
    const items = await core.plexTv.getWatchlist();

    // Client-side pagination since Plex watchlist doesn't support server-side
    const offset = (page - 1) * PAGE_SIZE;
    const pageItems = items.slice(offset, offset + PAGE_SIZE);

    const browseItems: BrowseItem[] = pageItems.map((item: PlexMediaItem) => ({
      id: `plex:${item.ratingKey}`,
      title: item.title || 'Untitled',
      image: item.thumb ? core.plexServer.getImageUrl(item.thumb, 300) : undefined,
      year: item.year,
    }));

    return {
      items: browseItems,
      hasMore: offset + pageItems.length < items.length,
      totalCount: items.length,
    };
  } catch (e) {
    console.log('[BrowseData] fetchPlexWatchlist error:', e);
    return { items: [], hasMore: false };
  }
}

/**
 * Fetch TMDB browse (trending, recommendations, similar)
 */
async function fetchTmdbBrowse(
  context: Extract<BrowseContext, { type: 'tmdb' }>,
  page: number
): Promise<BrowseResult> {
  try {
    const core = getFlixorCore();
    const { kind, mediaType, id } = context;

    let response: { results: TMDBMedia[]; total_pages?: number; page?: number };

    switch (kind) {
      case 'trending':
        response =
          mediaType === 'movie'
            ? await core.tmdb.getTrendingMovies('week', page)
            : await core.tmdb.getTrendingTV('week', page);
        break;

      case 'recommendations':
        if (!id) return { items: [], hasMore: false };
        response =
          mediaType === 'movie'
            ? await core.tmdb.getMovieRecommendations(Number(id), page)
            : await core.tmdb.getTVRecommendations(Number(id), page);
        break;

      case 'similar':
        if (!id) return { items: [], hasMore: false };
        response =
          mediaType === 'movie'
            ? await core.tmdb.getSimilarMovies(Number(id), page)
            : await core.tmdb.getSimilarTV(Number(id), page);
        break;

      default:
        return { items: [], hasMore: false };
    }

    const results = response.results || [];
    const browseItems: BrowseItem[] = results.map((r: TMDBMedia) => ({
      id: `tmdb:${mediaType}:${r.id}`,
      title: r.title || r.name || 'Untitled',
      image: r.poster_path ? core.tmdb.getPosterUrl(r.poster_path, 'w342') : undefined,
      year: r.release_date
        ? parseInt(r.release_date.split('-')[0])
        : r.first_air_date
          ? parseInt(r.first_air_date.split('-')[0])
          : undefined,
    }));

    return {
      items: browseItems,
      hasMore: (response.page || page) < (response.total_pages || 1),
    };
  } catch (e) {
    console.log('[BrowseData] fetchTmdbBrowse error:', e);
    return { items: [], hasMore: false };
  }
}

/**
 * Fetch Trakt browse (trending, watchlist, history, recommendations)
 */
async function fetchTraktBrowse(
  context: Extract<BrowseContext, { type: 'trakt' }>,
  page: number
): Promise<BrowseResult> {
  try {
    const core = getFlixorCore();
    const { kind, mediaType } = context;

    let items: any[] = [];

    switch (kind) {
      case 'trending':
        items =
          mediaType === 'movie'
            ? await core.trakt.getTrendingMovies(page, PAGE_SIZE)
            : await core.trakt.getTrendingShows(page, PAGE_SIZE);
        break;

      case 'watchlist':
        if (!core.isTraktAuthenticated) return { items: [], hasMore: false };
        items = await core.trakt.getWatchlist(mediaType === 'movie' ? 'movies' : 'shows');
        // Client-side pagination
        const offset = (page - 1) * PAGE_SIZE;
        items = items.slice(offset, offset + PAGE_SIZE);
        break;

      case 'history':
        if (!core.isTraktAuthenticated) return { items: [], hasMore: false };
        items = await core.trakt.getHistory(mediaType === 'movie' ? 'movies' : 'shows', page, PAGE_SIZE);
        break;

      case 'recommendations':
        if (!core.isTraktAuthenticated) return { items: [], hasMore: false };
        items =
          mediaType === 'movie'
            ? await core.trakt.getRecommendedMovies(page, PAGE_SIZE)
            : await core.trakt.getRecommendedShows(page, PAGE_SIZE);
        break;

      default:
        return { items: [], hasMore: false };
    }

    // Enrich with TMDB images
    const browseItems = await withLimit(items, 5, async (item) => {
      const movie = item.movie;
      const show = item.show;
      const media = movie || show || item;
      const type = movie ? 'movie' : 'tv';
      const tmdbId = media?.ids?.tmdb;
      let image: string | undefined;
      let year: number | undefined = media?.year;

      if (tmdbId) {
        try {
          const details =
            type === 'movie'
              ? await core.tmdb.getMovieDetails(tmdbId)
              : await core.tmdb.getTVDetails(tmdbId);
          image = details.poster_path
            ? core.tmdb.getPosterUrl(details.poster_path, 'w342')
            : undefined;
        } catch {}
      }

      return {
        id: tmdbId ? `tmdb:${type}:${tmdbId}` : `trakt:${type}:${media?.ids?.trakt}`,
        title: media?.title || '',
        image,
        year,
      };
    });

    return {
      items: browseItems,
      hasMore: items.length === PAGE_SIZE,
    };
  } catch (e) {
    console.log('[BrowseData] fetchTraktBrowse error:', e);
    return { items: [], hasMore: false };
  }
}
