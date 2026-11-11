/**
 * Home screen data fetchers using FlixorCore
 * Replaces the old api/data.ts functions for Home screen
 */

import { getFlixorCore } from './index';
import { loadAppSettings } from './SettingsData';
import { localLibrary } from './LocalLibrary';
import { mapTmdbToPlex, fetchPlexSeasons, fetchPlexSeasonEpisodes } from './DetailsData';
import type { PlexMediaItem, TMDBMedia, PlexUltraBlurColors, ContinueWatchingResult } from '@flixor/core';

export type RowItem = {
  id: string;
  title: string;
  image?: string;
  mediaType?: 'movie' | 'tv';
  subtitle?: string; // Optional subtitle (e.g., "3 new episodes" for grouped series)
  backdrop?: string; // Landscape art for the landscape row layout
  rating?: number; // 0-10, for rating badges
};

// ============================================
// Helper: Parallel processing with concurrency limit
// ============================================
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

// ============================================
// TMDB Trending
// ============================================

export async function fetchTmdbTrendingAllWeek(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const data = await core.tmdb.getTrendingAll('week', 1);
    const results = data.results || [];

    return results.map((r: TMDBMedia) => {
      const mediaType = r.media_type === 'movie' ? 'movie' : 'tv';
      return {
        id: `tmdb:${mediaType}:${r.id}`,
        title: r.title || r.name || 'Untitled',
        image: r.poster_path
          ? core.tmdb.getPosterUrl(r.poster_path, 'w342')
          : r.backdrop_path
            ? core.tmdb.getBackdropUrl(r.backdrop_path, 'w780')
            : undefined,
        backdrop: r.backdrop_path ? core.tmdb.getBackdropUrl(r.backdrop_path, 'w780') : undefined,
        rating: r.vote_average || undefined,
        mediaType: mediaType as 'movie' | 'tv',
      };
    });
  } catch (e) {
    console.log('[HomeData] fetchTmdbTrendingAllWeek error:', e);
    return [];
  }
}

export async function fetchTmdbTrendingTVWeek(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const data = await core.tmdb.getTrendingTV('week', 1);
    const results = data.results || [];

    return results.map((r: TMDBMedia) => ({
      id: `tmdb:tv:${r.id}`,
      title: r.name || r.title || 'Untitled',
      image: r.poster_path
        ? core.tmdb.getPosterUrl(r.poster_path, 'w342')
        : r.backdrop_path
          ? core.tmdb.getBackdropUrl(r.backdrop_path, 'w780')
          : undefined,
      backdrop: r.backdrop_path ? core.tmdb.getBackdropUrl(r.backdrop_path, 'w780') : undefined,
      rating: r.vote_average || undefined,
      mediaType: 'tv' as const,
    }));
  } catch (e) {
    console.log('[HomeData] fetchTmdbTrendingTVWeek error:', e);
    return [];
  }
}

export async function fetchTmdbTrendingMoviesWeek(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const data = await core.tmdb.getTrendingMovies('week', 1);
    const results = data.results || [];

    return results.map((r: TMDBMedia) => ({
      id: `tmdb:movie:${r.id}`,
      title: r.title || r.name || 'Untitled',
      image: r.poster_path
        ? core.tmdb.getPosterUrl(r.poster_path, 'w342')
        : r.backdrop_path
          ? core.tmdb.getBackdropUrl(r.backdrop_path, 'w780')
          : undefined,
      backdrop: r.backdrop_path ? core.tmdb.getBackdropUrl(r.backdrop_path, 'w780') : undefined,
      rating: r.vote_average || undefined,
      mediaType: 'movie' as const,
    }));
  } catch (e) {
    console.log('[HomeData] fetchTmdbTrendingMoviesWeek error:', e);
    return [];
  }
}

// ============================================
// Plex Data
// ============================================

export async function fetchContinueWatching(): Promise<ContinueWatchingResult> {
  try {
    const core = getFlixorCore();
    if (!core.plexServer) {
      console.log('[HomeData] fetchContinueWatching: no plexServer');
      return { items: [], itemsWithMultipleVersions: new Set() };
    }
    const result = await core.plexServer.getContinueWatching();
    console.log('[HomeData] fetchContinueWatching result:', result?.items?.length, 'items');
    return result;
  } catch (e) {
    console.log('[HomeData] fetchContinueWatching error:', e);
    return { items: [], itemsWithMultipleVersions: new Set() };
  }
}

/** Like fetchContinueWatching, but throws, so a failed refresh doesn't empty the row. */
export function refreshContinueWatching(): Promise<ContinueWatchingResult> {
  return getFlixorCore().plexServer.getContinueWatching({ fresh: true });
}

export async function fetchOnDeck(): Promise<PlexMediaItem[]> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getOnDeck();
  } catch (e) {
    console.log('[HomeData] fetchOnDeck error:', e);
    return [];
  }
}

export async function fetchRecentlyAdded(): Promise<PlexMediaItem[]> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getRecentlyAdded();
  } catch (e) {
    console.log('[HomeData] fetchRecentlyAdded error:', e);
    return [];
  }
}

export function getPlexImageUrl(item: PlexMediaItem, width: number = 300): string {
  try {
    const core = getFlixorCore();
    const path = item.thumb || item.art;
    if (!path) return '';
    return core.plexServer.getImageUrl(path, width);
  } catch {
    return '';
  }
}

export function getContinueWatchingImageUrl(item: PlexMediaItem, width: number = 300): string {
  try {
    const core = getFlixorCore();
    const path =
      item.type === 'episode'
        ? item.grandparentThumb || item.thumb || item.art
        : item.thumb || item.art;
    if (!path) return '';
    return core.plexServer.getImageUrl(path, width);
  } catch {
    return '';
  }
}

// ============================================
// Plex.tv Watchlist
// ============================================

export async function fetchPlexWatchlist(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const items = await core.plexTv.getWatchlist();

    return items.slice(0, 12).map((item: PlexMediaItem) => {
      const mediaType: 'movie' | 'tv' = item.type === 'movie' ? 'movie' : 'tv';

      // Extract TMDB ID from Plex watchlist item's Guid array
      // Watchlist items use GUIDs not library ratingKeys, so we need TMDB ID for navigation
      let tmdbId: number | undefined;
      const guids = (item as any).Guid || [];
      for (const g of guids) {
        const gid = String(g.id || '');
        if (gid.includes('tmdb://') || gid.includes('themoviedb://')) {
          tmdbId = Number(gid.split('://')[1]);
          break;
        }
      }

      // Use TMDB ID if available, fallback to plex ratingKey (may fail for non-library items)
      const id = tmdbId
        ? `tmdb:${mediaType}:${tmdbId}`
        : `plex:${item.ratingKey}`;

      return {
        id,
        title: item.title || item.grandparentTitle || 'Untitled',
        image: item.thumb
          ? core.plexServer.getImageUrl(item.thumb, 300)
          : undefined,
        mediaType,
      };
    });
  } catch (e) {
    console.log('[HomeData] fetchPlexWatchlist error:', e);
    return [];
  }
}

/** This device's watchlist, for profiles with no Plex account. */
export async function fetchLocalWatchlistRow(): Promise<RowItem[]> {
  try {
    const entries = await localLibrary.watchlist();
    return entries.slice(0, 20).map((entry) => ({
      id: entry.id,
      title: entry.title,
      image: entry.posterUrl,
      backdrop: entry.backdropUrl,
      mediaType: entry.type === 'movie' ? 'movie' as const : 'tv' as const,
    }));
  } catch (e) {
    console.log('[HomeData] fetchLocalWatchlistRow error:', e);
    return [];
  }
}

// ============================================
// Plex Genre Rows
// ============================================

export async function fetchPlexGenreRow(type: 'movie' | 'show', genre: string): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const libraries = await core.plexServer.getLibraries();
    const lib = libraries.find((d) => d.type === type);
    if (!lib) return [];

    // Get items filtered by genre
    const items = await core.plexServer.getLibraryItems(lib.key, {
      type: type === 'movie' ? 1 : 2,
      filter: { genre },
      limit: 12,
    });

    return items.map((m: PlexMediaItem) => ({
      id: `plex:${m.ratingKey}`,
      title: m.title || m.grandparentTitle || 'Untitled',
      image: core.plexServer.getImageUrl(m.thumb, 300),
      backdrop: m.art ? core.plexServer.getImageUrl(m.art, 600) : undefined,
      rating: m.rating || undefined,
      mediaType: type === 'movie' ? 'movie' as const : 'tv' as const,
    }));
  } catch (e) {
    console.log('[HomeData] fetchPlexGenreRow error:', e);
    return [];
  }
}

// ============================================
// Trakt Data with TMDB image enrichment
// ============================================

export async function fetchTraktTrendingMovies(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const trending = await core.trakt.getTrendingMovies(1, 20);

    return withLimit(trending.slice(0, 12), 5, async (item) => {
      const movie = item.movie;
      const tmdbId = movie.ids.tmdb;
      let image: string | undefined;
      let backdrop: string | undefined;
      let rating: number | undefined;

      if (tmdbId) {
        try {
          const details = await core.tmdb.getMovieDetails(tmdbId);
          image = details.poster_path
            ? core.tmdb.getPosterUrl(details.poster_path, 'w342')
            : undefined;
          backdrop = details.backdrop_path
            ? core.tmdb.getBackdropUrl(details.backdrop_path, 'w780')
            : undefined;
          rating = details.vote_average || undefined;
        } catch {}
      }

      return {
        id: tmdbId ? `tmdb:movie:${tmdbId}` : `trakt:movie:${movie.ids.trakt}`,
        title: movie.title,
        image,
        backdrop,
        rating,
        mediaType: 'movie' as const,
      };
    });
  } catch (e) {
    console.log('[HomeData] fetchTraktTrendingMovies error:', e);
    return [];
  }
}

export async function fetchTraktTrendingShows(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const trending = await core.trakt.getTrendingShows(1, 20);

    return withLimit(trending.slice(0, 12), 5, async (item) => {
      const show = item.show;
      const tmdbId = show.ids.tmdb;
      let image: string | undefined;
      let backdrop: string | undefined;
      let rating: number | undefined;

      if (tmdbId) {
        try {
          const details = await core.tmdb.getTVDetails(tmdbId);
          image = details.poster_path
            ? core.tmdb.getPosterUrl(details.poster_path, 'w342')
            : undefined;
          backdrop = details.backdrop_path
            ? core.tmdb.getBackdropUrl(details.backdrop_path, 'w780')
            : undefined;
          rating = details.vote_average || undefined;
        } catch {}
      }

      return {
        id: tmdbId ? `tmdb:tv:${tmdbId}` : `trakt:show:${show.ids.trakt}`,
        title: show.title,
        image,
        backdrop,
        rating,
        mediaType: 'tv' as const,
      };
    });
  } catch (e) {
    console.log('[HomeData] fetchTraktTrendingShows error:', e);
    return [];
  }
}

export async function fetchTraktPopularShows(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const popular = await core.trakt.getPopularShows(1, 20);

    return withLimit(popular.slice(0, 12), 5, async (show) => {
      const tmdbId = show.ids.tmdb;
      let image: string | undefined;
      let backdrop: string | undefined;
      let rating: number | undefined;

      if (tmdbId) {
        try {
          const details = await core.tmdb.getTVDetails(tmdbId);
          image = details.poster_path
            ? core.tmdb.getPosterUrl(details.poster_path, 'w342')
            : undefined;
          backdrop = details.backdrop_path
            ? core.tmdb.getBackdropUrl(details.backdrop_path, 'w780')
            : undefined;
          rating = details.vote_average || undefined;
        } catch {}
      }

      return {
        id: tmdbId ? `tmdb:tv:${tmdbId}` : `trakt:show:${show.ids.trakt}`,
        title: show.title,
        image,
        backdrop,
        rating,
        mediaType: 'tv' as const,
      };
    });
  } catch (e) {
    console.log('[HomeData] fetchTraktPopularShows error:', e);
    return [];
  }
}

export async function fetchTraktWatchlist(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    if (!core.isTraktAuthenticated) return [];

    const [movies, shows] = await Promise.all([
      core.trakt.getWatchlist('movies').catch(() => []),
      core.trakt.getWatchlist('shows').catch(() => []),
    ]);

    const items = [...movies, ...shows];

    // Deduplicate by tmdb ID
    const seenIds = new Set<string>();
    const uniqueItems = items.filter((item) => {
      const movie = item.movie;
      const show = item.show;
      const media = movie || show;
      const type = movie ? 'movie' : 'tv';
      const tmdbId = media?.ids?.tmdb;
      const id = tmdbId ? `tmdb:${type}:${tmdbId}` : `trakt:${type}:${media?.ids?.trakt}`;
      if (seenIds.has(id)) return false;
      seenIds.add(id);
      return true;
    });

    return withLimit(uniqueItems.slice(0, 12), 5, async (item) => {
      const movie = item.movie;
      const show = item.show;
      const media = movie || show;
      const type = movie ? 'movie' : 'tv';
      const tmdbId = media?.ids?.tmdb;
      let image: string | undefined;
      let backdrop: string | undefined;
      let rating: number | undefined;

      if (tmdbId) {
        try {
          const details =
            type === 'movie'
              ? await core.tmdb.getMovieDetails(tmdbId)
              : await core.tmdb.getTVDetails(tmdbId);
          image = details.poster_path
            ? core.tmdb.getPosterUrl(details.poster_path, 'w342')
            : undefined;
          backdrop = details.backdrop_path
            ? core.tmdb.getBackdropUrl(details.backdrop_path, 'w780')
            : undefined;
          rating = details.vote_average || undefined;
        } catch {}
      }

      return {
        id: tmdbId ? `tmdb:${type}:${tmdbId}` : `trakt:${type}:${media?.ids?.trakt}`,
        title: media?.title || '',
        image,
        backdrop,
        rating,
        mediaType: type as 'movie' | 'tv',
      };
    });
  } catch (e) {
    console.log('[HomeData] fetchTraktWatchlist error:', e);
    return [];
  }
}

/**
 * Try to match a TMDB show episode to a Plex library episode
 * Returns the Plex episode ratingKey if found, null otherwise
 */
export async function matchTraktEpisodeToPlex(
  tmdbId: number,
  showTitle: string,
  seasonNum: number,
  episodeNum: number
): Promise<string | null> {
  try {
    // 1. Try to match the show to Plex
    const plexShow = await mapTmdbToPlex('tv', String(tmdbId), showTitle);
    if (!plexShow) {
      return null;
    }

    // 2. Get all seasons of the show
    const seasons = await fetchPlexSeasons(String(plexShow.ratingKey));
    if (!seasons.length) {
      return null;
    }

    // 3. Find the matching season (by index which is the season number)
    const matchingSeason = seasons.find((s: PlexMediaItem) => s.index === seasonNum);
    if (!matchingSeason) {
      return null;
    }

    // 4. Get all episodes of the season
    const episodes = await fetchPlexSeasonEpisodes(String(matchingSeason.ratingKey));
    if (!episodes.length) {
      return null;
    }

    // 5. Find the matching episode (by index which is the episode number)
    const matchingEpisode = episodes.find((e: PlexMediaItem) => e.index === episodeNum);
    if (!matchingEpisode) {
      return null;
    }

    console.log(`[HomeData] Matched Trakt episode to Plex: ${showTitle} S${seasonNum}E${episodeNum} -> ${matchingEpisode.ratingKey}`);
    return String(matchingEpisode.ratingKey);
  } catch (e) {
    console.log('[HomeData] matchTraktEpisodeToPlex error:', e);
    return null;
  }
}

export async function fetchTraktHistory(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    if (!core.isTraktAuthenticated) return [];

    const [movies, shows] = await Promise.all([
      core.trakt.getHistory('movies', 1, 20).catch(() => []),
      core.trakt.getHistory('shows', 1, 20).catch(() => []),
    ]);

    const items = [...movies, ...shows];

    // Deduplicate by tmdb ID (same movie/show watched multiple times)
    const seenIds = new Set<string>();
    const uniqueItems = items.filter((item) => {
      const movie = item.movie;
      const show = item.show;
      const media = movie || show;
      const type = movie ? 'movie' : 'tv';
      const tmdbId = media?.ids?.tmdb;
      const id = tmdbId ? `tmdb:${type}:${tmdbId}` : `trakt:${type}:${media?.ids?.trakt}`;
      if (seenIds.has(id)) return false;
      seenIds.add(id);
      return true;
    });

    return withLimit(uniqueItems.slice(0, 12), 5, async (item) => {
      const movie = item.movie;
      const show = item.show;
      const media = movie || show;
      const type = movie ? 'movie' : 'tv';
      const tmdbId = media?.ids?.tmdb;
      let image: string | undefined;
      let backdrop: string | undefined;
      let rating: number | undefined;

      if (tmdbId) {
        try {
          const details =
            type === 'movie'
              ? await core.tmdb.getMovieDetails(tmdbId)
              : await core.tmdb.getTVDetails(tmdbId);
          image = details.poster_path
            ? core.tmdb.getPosterUrl(details.poster_path, 'w342')
            : undefined;
          backdrop = details.backdrop_path
            ? core.tmdb.getBackdropUrl(details.backdrop_path, 'w780')
            : undefined;
          rating = details.vote_average || undefined;
        } catch {}
      }

      return {
        id: tmdbId ? `tmdb:${type}:${tmdbId}` : `trakt:${type}:${media?.ids?.trakt}`,
        title: media?.title || '',
        image,
        backdrop,
        rating,
        mediaType: type as 'movie' | 'tv',
      };
    });
  } catch (e) {
    console.log('[HomeData] fetchTraktHistory error:', e);
    return [];
  }
}

export async function fetchTraktRecommendations(): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    if (!core.isTraktAuthenticated) return [];

    const [movies, shows] = await Promise.all([
      core.trakt.getRecommendedMovies(1, 20).catch(() => []),
      core.trakt.getRecommendedShows(1, 20).catch(() => []),
    ]);

    const items = [
      ...movies.map((m) => ({ movie: m, show: undefined })),
      ...shows.map((s) => ({ movie: undefined, show: s })),
    ];

    // Deduplicate by tmdb ID
    const seenIds = new Set<string>();
    const uniqueItems = items.filter((item) => {
      const movie = item.movie;
      const show = item.show;
      const media = movie || show;
      const type = movie ? 'movie' : 'tv';
      const tmdbId = media?.ids?.tmdb;
      const id = tmdbId ? `tmdb:${type}:${tmdbId}` : `trakt:${type}:${media?.ids?.trakt}`;
      if (seenIds.has(id)) return false;
      seenIds.add(id);
      return true;
    });

    return withLimit(uniqueItems.slice(0, 12), 5, async (item) => {
      const movie = item.movie;
      const show = item.show;
      const media = movie || show;
      const type = movie ? 'movie' : 'tv';
      const tmdbId = media?.ids?.tmdb;
      let image: string | undefined;
      let backdrop: string | undefined;
      let rating: number | undefined;

      if (tmdbId) {
        try {
          const details =
            type === 'movie'
              ? await core.tmdb.getMovieDetails(tmdbId)
              : await core.tmdb.getTVDetails(tmdbId);
          image = details.poster_path
            ? core.tmdb.getPosterUrl(details.poster_path, 'w342')
            : undefined;
          backdrop = details.backdrop_path
            ? core.tmdb.getBackdropUrl(details.backdrop_path, 'w780')
            : undefined;
          rating = details.vote_average || undefined;
        } catch {}
      }

      return {
        id: tmdbId ? `tmdb:${type}:${tmdbId}` : `trakt:${type}:${media?.ids?.trakt}`,
        title: media?.title || '',
        image,
        backdrop,
        rating,
        mediaType: type as 'movie' | 'tv',
      };
    });
  } catch (e) {
    console.log('[HomeData] fetchTraktRecommendations error:', e);
    return [];
  }
}

// ============================================
// TMDB Logo Fetching
// ============================================

export async function getTmdbLogo(
  tmdbId: number,
  mediaType: 'movie' | 'tv'
): Promise<string | undefined> {
  try {
    const core = getFlixorCore();
    const images =
      mediaType === 'movie'
        ? await core.tmdb.getMovieImages(tmdbId)
        : await core.tmdb.getTVImages(tmdbId);

    const logos = images.logos || [];
    const logo = logos.find((l: any) => l.iso_639_1 === 'en') || logos[0];

    if (logo?.file_path) {
      return core.tmdb.getImageUrl(logo.file_path, 'w500');
    }
    return undefined;
  } catch (e) {
    console.log('[HomeData] getTmdbLogo error:', e);
    return undefined;
  }
}

/*
 * Artwork known to have no title printed in it. Some titles have no textless poster on TMDB
 * (e.g. Housefull 2: every poster carries the title), so the helpers below fall back to a
 * titled one. Callers draw the logo only over artwork listed here, never on top of a
 * poster that already shows the title.
 */
const textlessArtwork = new Set<string>();

/** The image at `url` was picked as textless (no title printed in it). */
export function isTextlessArtwork(url: string | undefined | null): boolean {
  return !!url && textlessArtwork.has(url);
}

/**
 * Fetch textless poster from TMDB (iso_639_1 is null)
 * These are clean posters without any text overlay
 */
export async function getTmdbTextlessPoster(
  tmdbId: number,
  mediaType: 'movie' | 'tv'
): Promise<string | undefined> {
  try {
    const core = getFlixorCore();
    const images =
      mediaType === 'movie'
        ? await core.tmdb.getMovieImages(tmdbId)
        : await core.tmdb.getTVImages(tmdbId);

    const posters = images.posters || [];

    // Find a textless poster (iso_639_1 is null means no language/text)
    const textless = posters.find(
      (p) => p.iso_639_1 === null || p.iso_639_1 === undefined
    );

    // Fallback to any poster if no textless found
    const poster = textless || posters[0];

    if (poster?.file_path) {
      const url = core.tmdb.getPosterUrl(poster.file_path, 'w780');
      if (textless) textlessArtwork.add(url);
      return url;
    }
    return undefined;
  } catch (e) {
    return undefined;
  }
}

/**
 * Fetch textless backdrop from TMDB (iso_639_1 is null and iso_3166_1 is null)
 */
export async function getTmdbTextlessBackdrop(
  tmdbId: number,
  mediaType: 'movie' | 'tv'
): Promise<string | undefined> {
  try {
    const core = getFlixorCore();
    const images =
      mediaType === 'movie'
        ? await core.tmdb.getMovieImages(tmdbId)
        : await core.tmdb.getTVImages(tmdbId);

    const backdrops = images.backdrops || [];

    const textless = backdrops.find(
      (b: any) => (b.iso_639_1 == null) && (b.iso_3166_1 == null)
    );
    const backdrop = textless || backdrops[0];

    if (backdrop?.file_path) {
      const url = core.tmdb.getBackdropUrl(backdrop.file_path, 'w780');
      if (textless) textlessArtwork.add(url);
      return url;
    }
    return undefined;
  } catch (e) {
    return undefined;
  }
}

/**
 * Fetch backdrop with title from TMDB
 * Priority:
 * 1. iso_639_1 = 'en' (English title burned in)
 * 2. Highest rated backdrop with iso_639_1 != null (any language with title)
 * 3. Fallback to iso_639_1 = null (textless) if no titled backdrops available
 */
export async function getTmdbBackdropWithTitle(
  tmdbId: number,
  mediaType: 'movie' | 'tv'
): Promise<string | undefined> {
  try {
    const core = getFlixorCore();
    // Pass true to get all languages (Hindi, Korean, etc.) for backdrop with title
    const images =
      mediaType === 'movie'
        ? await core.tmdb.getMovieImages(tmdbId, true)
        : await core.tmdb.getTVImages(tmdbId, true);

    const backdrops = images.backdrops || [];
    let backdrop: any = null;

    // Separate backdrops with title text (any language) from textless ones
    const withTitle = backdrops.filter((b: any) => b.iso_639_1 && b.iso_639_1.length > 0);
    const textless = backdrops.filter((b: any) => !b.iso_639_1 || b.iso_639_1.length === 0);

    // 1. Prefer English backdrop (has title text burned in)
    backdrop = withTitle.find((b: any) => b.iso_639_1 === 'en');

    // 2. If no English, get highest rated backdrop with any language that has title
    //    When vote_average is equal, prefer higher resolution (width)
    if (!backdrop && withTitle.length > 0) {
      const sorted = withTitle.sort((a: any, b: any) => {
        const voteDiff = (b.vote_average || 0) - (a.vote_average || 0);
        if (voteDiff !== 0) return voteDiff;
        return (b.width || 0) - (a.width || 0); // Prefer higher resolution
      });
      backdrop = sorted[0];
    }

    // 3. Fallback to textless - highest rated, then highest resolution
    if (!backdrop && textless.length > 0) {
      const sorted = textless.sort((a: any, b: any) => {
        const voteDiff = (b.vote_average || 0) - (a.vote_average || 0);
        if (voteDiff !== 0) return voteDiff;
        return (b.width || 0) - (a.width || 0);
      });
      backdrop = sorted[0];
    }

    if (backdrop?.file_path) {
      return core.tmdb.getBackdropUrl(backdrop.file_path, 'w780');
    }
    return undefined;
  } catch (e) {
    return undefined;
  }
}

/**
 * Get show's TMDB ID from its rating key (for episodes that need parent show ID)
 */
export async function getShowTmdbId(showRatingKey: string): Promise<string | null> {
  try {
    const core = getFlixorCore();
    const showMeta = await core.plexServer.getMetadata(showRatingKey, true);
    if (!showMeta?.Guid) return null;

    for (const g of showMeta.Guid) {
      const id = String(g.id || '');
      if (id.includes('tmdb://') || id.includes('themoviedb://')) {
        return id.split('://')[1];
      }
    }
    return null;
  } catch (e) {
    return null;
  }
}

/**
 * Get TMDB overview/description for a movie or TV show
 */
export async function getTmdbOverview(
  tmdbId: number,
  mediaType: 'movie' | 'tv'
): Promise<string | undefined> {
  try {
    const core = getFlixorCore();
    if (mediaType === 'movie') {
      const details = await core.tmdb.getMovieDetails(tmdbId);
      return details.overview || undefined;
    } else {
      const details = await core.tmdb.getTVDetails(tmdbId);
      return details.overview || undefined;
    }
  } catch (e) {
    console.log('[HomeData] getTmdbOverview error:', e);
    return undefined;
  }
}

// ============================================
// Plex to Hero Conversion (for Billboard/Carousel)
// ============================================

export type HeroItem = {
  id: string;
  title: string;
  image?: string;
  mediaType?: 'movie' | 'tv';
  logo?: string;
  backdrop?: string;
  description?: string;
  year?: string;
  genres?: string[];
  /** Plex ratingKey when the title is in the library (id is rewritten to a TMDB id). */
  plexRatingKey?: string;
};

/**
 * Extract TMDB ID from a PlexMediaItem's Guid array
 * Returns { tmdbId, mediaType } or null if not found
 */
export function extractTmdbFromPlexItem(item: PlexMediaItem): { tmdbId: number; mediaType: 'movie' | 'tv' } | null {
  const guids = (item as any).Guid || [];
  for (const g of guids) {
    const gid = String(g.id || '');
    if (gid.includes('tmdb://') || gid.includes('themoviedb://')) {
      const tmdbId = Number(gid.split('://')[1]);
      if (!isNaN(tmdbId)) {
        const mediaType: 'movie' | 'tv' = item.type === 'movie' ? 'movie' : 'tv';
        return { tmdbId, mediaType };
      }
    }
  }
  return null;
}

/**
 * Convert PlexMediaItem array to hero carousel format
 * Enriches with TMDB logos and backdrops
 */
export async function convertPlexItemsToHero(
  items: PlexMediaItem[],
  limit: number = 8
): Promise<HeroItem[]> {
  const core = getFlixorCore();
  const limitedItems = items.slice(0, limit);

  return withLimit(limitedItems, 3, async (item): Promise<HeroItem> => {
    // For episodes, use series info
    const isEpisode = item.type === 'episode';
    const isSeason = item.type === 'season';
    const isEpisodeOrSeason = isEpisode || isSeason;

    // Get display title (series title for episodes/seasons)
    const displayTitle = isEpisode
      ? item.grandparentTitle || item.title
      : isSeason
        ? item.parentTitle || item.grandparentTitle || item.title
        : item.title;

    // Determine media type
    const mediaType: 'movie' | 'tv' = item.type === 'movie' ? 'movie' : 'tv';

    // Base hero item from Plex
    const heroItem: HeroItem = {
      id: `plex:${item.ratingKey}`,
      title: displayTitle || 'Untitled',
      mediaType,
      year: item.year ? String(item.year) : undefined,
      description: item.summary || undefined,
      // Episodes and seasons point at their show
      plexRatingKey: String(
        isEpisode ? item.grandparentRatingKey || item.ratingKey : isSeason ? item.parentRatingKey || item.ratingKey : item.ratingKey
      ),
      genres: (item as any).Genre?.slice(0, 3).map((g: { tag: string }) => g.tag),
    };

    // Get Plex poster as fallback (prefer thumb/poster over art/backdrop)
    const plexPoster = isEpisode
      ? item.grandparentThumb || item.thumb
      : item.thumb;
    if (plexPoster) {
      heroItem.image = core.plexServer.getImageUrl(plexPoster, 600);
    }

    // Get Plex backdrop as fallback for Apple TV layout
    const plexBackdrop = isEpisode
      ? item.grandparentArt || item.art
      : item.art;
    if (plexBackdrop) {
      heroItem.backdrop = core.plexServer.getImageUrl(plexBackdrop, 1280);
    }

    // Try to get TMDB ID for enrichment
    let tmdbId: number | null = null;

    if (isEpisodeOrSeason) {
      // For episodes/seasons, get the series TMDB ID
      const seriesRatingKey = isEpisode ? item.grandparentRatingKey : item.parentRatingKey;
      if (seriesRatingKey) {
        const showTmdbId = await getShowTmdbId(seriesRatingKey);
        if (showTmdbId) {
          tmdbId = Number(showTmdbId);
        }
      }
    } else {
      // For movies/shows, extract from Guid
      const tmdbInfo = extractTmdbFromPlexItem(item);
      if (tmdbInfo) {
        tmdbId = tmdbInfo.tmdbId;
      }
    }

    // Enrich with TMDB data if we have an ID
    if (tmdbId && !isNaN(tmdbId)) {
      // Update ID to use TMDB format for navigation
      heroItem.id = `tmdb:${mediaType}:${tmdbId}`;

      try {
        const [poster, backdrop, logo, overview] = await Promise.all([
          getTmdbTextlessPoster(tmdbId, mediaType), // Use textless poster (iso_639_1 is null) for Carousel/Netflix
          getTmdbTextlessBackdrop(tmdbId, mediaType), // Use textless backdrop for Apple TV layout
          getTmdbLogo(tmdbId, mediaType),
          getTmdbOverview(tmdbId, mediaType),
        ]);

        if (poster) heroItem.image = poster; // Use poster for hero image (Carousel/Netflix)
        if (backdrop) heroItem.backdrop = backdrop; // Use backdrop for Apple TV layout
        if (logo) heroItem.logo = logo;
        if (overview) heroItem.description = overview;
      } catch (e) {
        console.log('[HomeData] TMDB enrichment error for', displayTitle, e);
      }
    }

    return heroItem;
  });
}

// ============================================
// UltraBlur Colors
// ============================================

export type { PlexUltraBlurColors };

/**
 * Get UltraBlur gradient colors from an image URL
 * Uses Plex's color extraction service
 */
export async function getUltraBlurColors(
  imageUrl: string
): Promise<PlexUltraBlurColors | null> {
  try {
    const core = getFlixorCore();
    const colors = await core.plexServer.getUltraBlurColors(imageUrl);
    return colors;
  } catch (e) {
    console.log('[HomeData] getUltraBlurColors error:', e);
    return null;
  }
}

// ============================================
// User Info
// ============================================

export async function getUsername(): Promise<string> {
  try {
    const core = getFlixorCore();
    const token = (core as any).plexToken;
    if (token) {
      const user = await core.plexAuth.getUser(token);
      return user?.username || 'User';
    }
    return 'User';
  } catch {
    return 'User';
  }
}

// ============================================
// Genres / Categories
// ============================================

export type GenreItem = {
  key: string;
  title: string;
};

/**
 * Fetch all available genres for movies
 */
export async function fetchMovieGenres(): Promise<GenreItem[]> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getAllGenres('movie');
  } catch (e) {
    console.log('[HomeData] fetchMovieGenres error:', e);
    return [];
  }
}

/**
 * Fetch all available genres for TV shows
 */
export async function fetchTvGenres(): Promise<GenreItem[]> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getAllGenres('show');
  } catch (e) {
    console.log('[HomeData] fetchTvGenres error:', e);
    return [];
  }
}

/**
 * Fetch all available genres (movies + TV combined)
 */
export async function fetchAllGenres(): Promise<GenreItem[]> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getAllGenres();
  } catch (e) {
    console.log('[HomeData] fetchAllGenres error:', e);
    return [];
  }
}

/**
 * Fetch libraries (for browse modal)
 */
export async function fetchLibraries(): Promise<Array<{ key: string; title: string; type: string }>> {
  try {
    const core = getFlixorCore();
    const libraries = await core.plexServer.getLibraries();
    const settings = await loadAppSettings();
    const enabledKeys = settings.enabledLibraryKeys;
    const filtered = enabledKeys && enabledKeys.length > 0
      ? libraries.filter((lib) => enabledKeys.includes(String(lib.key)))
      : libraries;
    return filtered.map((lib) => ({
      key: lib.key,
      title: lib.title,
      type: lib.type,
    }));
  } catch (e) {
    console.log('[HomeData] fetchLibraries error:', e);
    return [];
  }
}

export async function fetchAllLibraries(): Promise<Array<{ key: string; title: string; type: string }>> {
  try {
    const core = getFlixorCore();
    const libraries = await core.plexServer.getLibraries();
    return libraries.map((lib) => ({
      key: lib.key,
      title: lib.title,
      type: lib.type,
    }));
  } catch (e) {
    console.log('[HomeData] fetchAllLibraries error:', e);
    return [];
  }
}

// ============================================
// Plex Collections
// ============================================

export type CollectionRowData = {
  ratingKey: string;
  title: string;
  items: RowItem[];
};

/**
 * Fetch collections with their items for home screen rows
 * Sorted by childCount (popular collections first), limited to avoid clutter
 */
export async function fetchCollectionRowsForHome(
  limit: number = 5
): Promise<CollectionRowData[]> {
  try {
    const core = getFlixorCore();
    const collections = await core.plexServer.getAllCollections();

    // Sort by childCount descending (show largest collections first)
    // and limit to avoid overwhelming the home screen
    const sortedCollections = collections
      .filter((c: any) => (c.childCount || 0) > 0)
      .sort((a: any, b: any) => (b.childCount || 0) - (a.childCount || 0))
      .slice(0, limit);

    const collectionRows: CollectionRowData[] = [];

    for (const coll of sortedCollections) {
      try {
        const items = await core.plexServer.getCollectionItems(coll.ratingKey, {
          size: 15, // Limit items per row for performance
        });

        if (items.length > 0) {
          collectionRows.push({
            ratingKey: coll.ratingKey,
            title: coll.title || 'Untitled Collection',
            items: items.map((item: PlexMediaItem) => ({
              id: `plex:${item.ratingKey}`,
              title: item.title || 'Untitled',
              image: core.plexServer.getImageUrl(item.thumb, 300),
              backdrop: item.art ? core.plexServer.getImageUrl(item.art, 600) : undefined,
              rating: item.rating || undefined,
              mediaType: item.type === 'movie' ? 'movie' as const : 'tv' as const,
            })),
          });
        }
      } catch (e) {
        console.log('[HomeData] Error fetching collection items:', e);
      }
    }

    return collectionRows;
  } catch (e) {
    console.log('[HomeData] fetchCollectionRowsForHome error:', e);
    return [];
  }
}

// ============================================
// Recently Added Per Library
// ============================================

export type RecentlyAddedSection = {
  id: string;
  libraryKey: string;
  title: string;
  items: RowItem[];
};

/**
 * Fetch "Recently Added in {LibraryName}" for each enabled library
 * @param groupEpisodes - If true, group TV episodes by series
 */
export async function fetchRecentlyAddedPerLibrary(
  groupEpisodes: boolean = true,
  enabledLibraryKeys?: string[]
): Promise<RecentlyAddedSection[]> {
  try {
    const core = getFlixorCore();
    const libraries = await core.plexServer.getLibraries();

    // Filter libraries based on enabled settings
    const filteredLibraries = enabledLibraryKeys && enabledLibraryKeys.length > 0
      ? libraries.filter((lib) => enabledLibraryKeys.includes(String(lib.key)))
      : libraries;

    const sections: RecentlyAddedSection[] = [];

    for (const library of filteredLibraries) {
      try {
        // Fetch recently added for this specific library
        const allItems = await core.plexServer.getRecentlyAdded(library.key);
        // Fetch more items if grouping is enabled to account for consolidation
        const fetchLimit = groupEpisodes ? 30 : 20;
        const rawItems = allItems.slice(0, fetchLimit);

        if (rawItems.length > 0) {
          let finalItems: RowItem[];

          if (groupEpisodes) {
            // Group TV episodes by series, keep movies/shows as-is
            const processedItems = groupEpisodesBySeries(rawItems, core);
            finalItems = processedItems.slice(0, 20);
          } else {
            // Show individual items without grouping
            finalItems = rawItems.slice(0, 20).map((item: PlexMediaItem) => ({
              id: `plex:${item.ratingKey}`,
              title: item.title || item.grandparentTitle || 'Untitled',
              image: core.plexServer.getImageUrl(item.thumb, 300),
              backdrop: item.art ? core.plexServer.getImageUrl(item.art, 600) : undefined,
              rating: item.rating || undefined,
              mediaType: item.type === 'movie' ? 'movie' as const : 'tv' as const,
            }));
          }

          sections.push({
            id: `recently-added-${library.key}`,
            libraryKey: library.key,
            title: `Recently Added in ${library.title}`,
            items: finalItems,
          });
        }
      } catch (e) {
        console.log(`[HomeData] Failed to load recently added for ${library.title}:`, e);
        // Continue with other libraries
      }
    }

    return sections;
  } catch (e) {
    console.log('[HomeData] fetchRecentlyAddedPerLibrary error:', e);
    return [];
  }
}

/**
 * Group TV episodes by their parent series, preserving order of first appearance
 * Non-episode items (movies, shows) are kept as-is
 */
function groupEpisodesBySeries(items: PlexMediaItem[], core: any): RowItem[] {
  const result: RowItem[] = [];
  const seenSeriesKeys = new Set<string>();
  const seriesEpisodeCounts: Record<string, number> = {};

  // First pass: count episodes per series
  for (const item of items) {
    if (item.type === 'episode' && item.grandparentRatingKey) {
      seriesEpisodeCounts[item.grandparentRatingKey] = (seriesEpisodeCounts[item.grandparentRatingKey] || 0) + 1;
    }
  }

  // Second pass: build result list, replacing episodes with series representative
  for (const item of items) {
    if (item.type === 'episode' && item.grandparentRatingKey) {
      // Skip if we've already added this series
      if (seenSeriesKeys.has(item.grandparentRatingKey)) {
        continue;
      }
      seenSeriesKeys.add(item.grandparentRatingKey);

      const episodeCount = seriesEpisodeCounts[item.grandparentRatingKey] || 1;

      // Create a series representative item
      result.push({
        id: `plex:${item.grandparentRatingKey}`, // Use series rating key so clicking navigates to series details
        title: item.grandparentTitle || item.title || 'Untitled',
        image: core.plexServer.getImageUrl(item.grandparentThumb || item.thumb, 300),
        backdrop: item.grandparentArt || item.art
          ? core.plexServer.getImageUrl((item.grandparentArt || item.art) as string, 600)
          : undefined,
        mediaType: 'tv' as const,
        subtitle: episodeCount > 1 ? `${episodeCount} new episodes` : '1 new episode',
      });
    } else {
      // Non-episode items (movies, shows) - keep as-is
      result.push({
        id: `plex:${item.ratingKey}`,
        title: item.title || 'Untitled',
        image: core.plexServer.getImageUrl(item.thumb, 300),
        backdrop: item.art ? core.plexServer.getImageUrl(item.art, 600) : undefined,
        rating: item.rating || undefined,
        mediaType: item.type === 'movie' ? 'movie' as const : 'tv' as const,
      });
    }
  }

  return result;
}
