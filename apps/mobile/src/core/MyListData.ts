/**
 * My List screen data fetchers using FlixorCore
 * Fetches watchlist from both Trakt and Plex, merges and dedupes
 */

import { getFlixorCore } from './index';
import type { TraktWatchlistItem, PlexMediaItem } from '@flixor/core';

export type MyListItem = {
  id: string;
  title: string;
  type: 'movie' | 'show';
  poster?: string;
  year?: number;
  addedAt: string;
  source: 'trakt' | 'plex' | 'both';
  tmdbId?: number;
  imdbId?: string;
  plexRatingKey?: string;
  traktSlug?: string;
};

export type SortOption = 'added' | 'title' | 'year';
export type FilterOption = 'all' | 'movies' | 'shows';

// ============================================
// Fetch Watchlist
// ============================================

export async function fetchMyList(options?: {
  filter?: FilterOption;
  sort?: SortOption;
  sortDirection?: 'asc' | 'desc';
}): Promise<MyListItem[]> {
  const { filter = 'all', sort = 'added', sortDirection = 'desc' } = options || {};

  try {
    const core = getFlixorCore();
    const items: MyListItem[] = [];
    const seen = new Set<string>();

    // Fetch from Trakt if authenticated
    if (core.isTraktAuthenticated) {
      try {
        const traktType = filter === 'movies' ? 'movies' : filter === 'shows' ? 'shows' : undefined;
        const traktItems = await core.trakt.getWatchlist(traktType);

        for (const item of traktItems) {
          const media = item.movie || item.show;
          if (!media) continue;

          const isMovie = item.type === 'movie';
          const tmdbId = media.ids?.tmdb;
          const imdbId = media.ids?.imdb;
          const slug = media.ids?.slug;

          // Create unique key for deduplication
          const key = tmdbId ? `tmdb:${tmdbId}` : imdbId ? `imdb:${imdbId}` : `slug:${slug}`;

          if (!seen.has(key)) {
            seen.add(key);
            items.push({
              id: key,
              title: media.title || 'Unknown',
              type: isMovie ? 'movie' : 'show',
              year: media.year,
              addedAt: item.listed_at,
              source: 'trakt',
              tmdbId,
              imdbId,
              traktSlug: slug,
            });
          }
        }
      } catch (e) {
        console.log('[MyListData] Error fetching Trakt watchlist:', e);
      }
    }

    // Fetch from Plex
    try {
      const plexItems = await core.plexTv.getWatchlist();

      for (const item of plexItems) {
        // Extract IDs from Plex GUIDs
        let tmdbId: number | undefined;
        let imdbId: string | undefined;

        const guids = (item as any).Guid || [];
        for (const g of guids) {
          const id = String(g.id || '');
          if (id.includes('tmdb://') || id.includes('themoviedb://')) {
            tmdbId = Number(id.split('://')[1]);
          }
          if (id.includes('imdb://')) {
            imdbId = id.split('://')[1];
          }
        }

        const isMovie = item.type === 'movie';

        // Skip if filter doesn't match
        if (filter === 'movies' && !isMovie) continue;
        if (filter === 'shows' && isMovie) continue;

        // Create unique key
        const key = tmdbId ? `tmdb:${tmdbId}` : imdbId ? `imdb:${imdbId}` : `plex:${item.ratingKey}`;

        if (seen.has(key)) {
          // Update existing item to mark as 'both'
          const existing = items.find(i => i.id === key);
          if (existing) {
            existing.source = 'both';
            existing.plexRatingKey = String(item.ratingKey);
          }
        } else {
          seen.add(key);
          items.push({
            id: key,
            title: item.title || 'Unknown',
            type: isMovie ? 'movie' : 'show',
            poster: item.thumb,
            year: item.year,
            addedAt: (item as any).addedAt ? new Date((item as any).addedAt * 1000).toISOString() : new Date().toISOString(),
            source: 'plex',
            tmdbId,
            imdbId,
            plexRatingKey: String(item.ratingKey),
          });
        }
      }
    } catch (e) {
      console.log('[MyListData] Error fetching Plex watchlist:', e);
    }

    // Sort items
    items.sort((a, b) => {
      let comparison = 0;

      switch (sort) {
        case 'title':
          comparison = a.title.localeCompare(b.title);
          break;
        case 'year':
          comparison = (a.year || 0) - (b.year || 0);
          break;
        case 'added':
        default:
          comparison = new Date(a.addedAt).getTime() - new Date(b.addedAt).getTime();
          break;
      }

      return sortDirection === 'asc' ? comparison : -comparison;
    });

    return items;
  } catch (e) {
    console.log('[MyListData] fetchMyList error:', e);
    return [];
  }
}

// ============================================
// Get Poster URL
// ============================================

export function getMyListPosterUrl(item: MyListItem, width: number = 300): string {
  try {
    const core = getFlixorCore();

    // If we have a Plex poster path, use Plex image service
    if (item.poster) {
      return core.plexServer.getImageUrl(item.poster, width);
    }

    // For items without a poster path, return empty - let fetchTmdbPoster handle it
    return '';
  } catch {
    return '';
  }
}

/**
 * Fetch TMDB poster path for an item
 */
export async function fetchTmdbPoster(item: MyListItem): Promise<string | undefined> {
  if (!item.tmdbId) return undefined;

  try {
    const core = getFlixorCore();
    const mediaType = item.type === 'movie' ? 'movie' : 'tv';

    const details = mediaType === 'movie'
      ? await core.tmdb.getMovieDetails(item.tmdbId)
      : await core.tmdb.getTVDetails(item.tmdbId);

    if (details?.poster_path) {
      return core.tmdb.getPosterUrl(details.poster_path, 'w342');
    }
    return undefined;
  } catch (e) {
    console.log('[MyListData] fetchTmdbPoster error:', e);
    return undefined;
  }
}

// ============================================
// Remove from Watchlist
// ============================================

export async function removeFromMyList(item: MyListItem): Promise<boolean> {
  try {
    const core = getFlixorCore();
    let success = false;

    // Remove from Trakt if it was added there
    if ((item.source === 'trakt' || item.source === 'both') && core.isTraktAuthenticated) {
      try {
        if (item.type === 'movie' && (item.tmdbId || item.imdbId)) {
          await core.trakt.removeMovieFromWatchlist({ ids: { tmdb: item.tmdbId, imdb: item.imdbId } });
          success = true;
        } else if (item.type === 'show' && (item.tmdbId || item.imdbId)) {
          await core.trakt.removeShowFromWatchlist({ ids: { tmdb: item.tmdbId, imdb: item.imdbId } });
          success = true;
        }
      } catch (e) {
        console.log('[MyListData] Error removing from Trakt:', e);
      }
    }

    // Remove from Plex if it was added there
    if ((item.source === 'plex' || item.source === 'both') && item.plexRatingKey) {
      try {
        await core.plexTv.removeFromWatchlist(item.plexRatingKey);
        success = true;
      } catch (e) {
        console.log('[MyListData] Error removing from Plex:', e);
      }
    }

    return success;
  } catch (e) {
    console.log('[MyListData] removeFromMyList error:', e);
    return false;
  }
}

// ============================================
// Check if user has any watchlist source
// ============================================

export function hasWatchlistSource(): boolean {
  try {
    const core = getFlixorCore();
    // User can always use Plex watchlist, Trakt is optional
    return true;
  } catch {
    return false;
  }
}

export function isTraktConnected(): boolean {
  try {
    const core = getFlixorCore();
    return core.isTraktAuthenticated;
  } catch {
    return false;
  }
}
