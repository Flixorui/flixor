/**
 * Details screen data fetchers using FlixorCore
 * Replaces the old api/data.ts functions for Details screen
 */

import { getFlixorCore } from './index';
import type { PlexMediaItem } from '@flixor/core';

export type RowItem = {
  id: string;
  title: string;
  image?: string;
  mediaType?: 'movie' | 'tv';
};

// ============================================
// Plex Metadata
// ============================================

export async function fetchPlexMetadata(ratingKey: string): Promise<PlexMediaItem | null> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getMetadata(ratingKey);
  } catch (e) {
    console.log('[DetailsData] fetchPlexMetadata error:', e);
    return null;
  }
}

export async function fetchPlexSeasons(showRatingKey: string): Promise<PlexMediaItem[]> {
  try {
    const core = getFlixorCore();
    const children = await core.plexServer.getChildren(showRatingKey);
    // Filter to seasons only
    let seasons = children.filter((c: PlexMediaItem) => c.type === 'season');
    if (!seasons.length) {
      // Fallback: treat all children as seasons
      seasons = children;
    }
    return seasons;
  } catch (e) {
    console.log('[DetailsData] fetchPlexSeasons error:', e);
    return [];
  }
}

export async function fetchPlexSeasonEpisodes(seasonRatingKey: string): Promise<PlexMediaItem[]> {
  try {
    const core = getFlixorCore();
    return await core.plexServer.getChildren(seasonRatingKey);
  } catch (e) {
    console.log('[DetailsData] fetchPlexSeasonEpisodes error:', e);
    return [];
  }
}

// ============================================
// TMDB Details and Images
// ============================================

export async function fetchTmdbDetails(mediaType: 'movie' | 'tv', tmdbId: number): Promise<any> {
  try {
    const core = getFlixorCore();
    if (mediaType === 'movie') {
      return await core.tmdb.getMovieDetails(tmdbId);
    } else {
      return await core.tmdb.getTVDetails(tmdbId);
    }
  } catch (e) {
    console.log('[DetailsData] fetchTmdbDetails error:', e);
    return null;
  }
}

export async function fetchTmdbLogo(mediaType: 'movie' | 'tv', tmdbId: number): Promise<string | undefined> {
  try {
    const core = getFlixorCore();
    const images = mediaType === 'movie'
      ? await core.tmdb.getMovieImages(tmdbId)
      : await core.tmdb.getTVImages(tmdbId);

    const logos = images.logos || [];
    const logo = logos.find((l: any) => l.iso_639_1 === 'en') || logos[0];
    if (logo?.file_path) {
      return core.tmdb.getImageUrl(logo.file_path, 'w500');
    }
    return undefined;
  } catch (e) {
    console.log('[DetailsData] fetchTmdbLogo error:', e);
    return undefined;
  }
}

export async function fetchTmdbCredits(mediaType: 'movie' | 'tv', tmdbId: number): Promise<{ cast: any[]; crew: any[] }> {
  try {
    const core = getFlixorCore();
    const credits = mediaType === 'movie'
      ? await core.tmdb.getMovieCredits(tmdbId)
      : await core.tmdb.getTVCredits(tmdbId);

    return {
      cast: (credits.cast || []).slice(0, 16),
      crew: (credits.crew || []).slice(0, 16),
    };
  } catch (e) {
    console.log('[DetailsData] fetchTmdbCredits error:', e);
    return { cast: [], crew: [] };
  }
}

// ============================================
// TMDB Seasons and Episodes
// ============================================

export async function fetchTmdbSeasonsList(tvId: number): Promise<Array<{ key: string; title: string; season_number: number }>> {
  try {
    const core = getFlixorCore();
    const details = await core.tmdb.getTVDetails(tvId);
    const seasons = details.seasons || [];

    return seasons
      .filter((s: any) => (s?.season_number ?? 0) > 0)
      .map((s: any) => ({
        key: String(s.season_number),
        title: `Season ${s.season_number}`,
        season_number: s.season_number,
      }));
  } catch (e) {
    console.log('[DetailsData] fetchTmdbSeasonsList error:', e);
    return [];
  }
}

export async function fetchTmdbSeasonEpisodes(tvId: number, seasonNumber: number): Promise<any[]> {
  try {
    const core = getFlixorCore();
    const seasonDetails = await core.tmdb.getSeasonDetails(tvId, seasonNumber);
    return seasonDetails.episodes || [];
  } catch (e) {
    console.log('[DetailsData] fetchTmdbSeasonEpisodes error:', e);
    return [];
  }
}

// ============================================
// TMDB Recommendations and Similar
// ============================================

export async function fetchTmdbRecommendations(mediaType: 'movie' | 'tv', tmdbId: number): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const data = mediaType === 'movie'
      ? await core.tmdb.getMovieRecommendations(tmdbId)
      : await core.tmdb.getTVRecommendations(tmdbId);

    const results = data.results || [];
    return results.slice(0, 12).map((r: any) => ({
      id: `tmdb:${mediaType}:${r.id}`,
      title: r.title || r.name || 'Untitled',
      image: r.poster_path ? core.tmdb.getPosterUrl(r.poster_path, 'w342') : undefined,
      mediaType,
    }));
  } catch (e) {
    console.log('[DetailsData] fetchTmdbRecommendations error:', e);
    return [];
  }
}

export async function fetchTmdbSimilar(mediaType: 'movie' | 'tv', tmdbId: number): Promise<RowItem[]> {
  try {
    const core = getFlixorCore();
    const data = mediaType === 'movie'
      ? await core.tmdb.getSimilarMovies(tmdbId)
      : await core.tmdb.getSimilarTV(tmdbId);

    const results = data.results || [];
    return results.slice(0, 12).map((r: any) => ({
      id: `tmdb:${mediaType}:${r.id}`,
      title: r.title || r.name || 'Untitled',
      image: r.poster_path ? core.tmdb.getPosterUrl(r.poster_path, 'w342') : undefined,
      mediaType,
    }));
  } catch (e) {
    console.log('[DetailsData] fetchTmdbSimilar error:', e);
    return [];
  }
}

// ============================================
// TMDB to Plex Mapping
// ============================================

function normalizeTitle(s: string): string {
  const base = (s || '').toLowerCase();
  const noArticles = base.replace(/^(the|a|an)\s+/i, '');
  const noDiacritics = noArticles.normalize('NFD').replace(/\p{Diacritic}+/gu, '');
  return noDiacritics.replace(/[^a-z0-9]+/g, '');
}

export async function mapTmdbToPlex(
  mediaType: 'movie' | 'tv',
  tmdbId: string,
  title?: string,
  year?: string
): Promise<PlexMediaItem | null> {
  try {
    const core = getFlixorCore();
    const typeNum = mediaType === 'movie' ? 1 : 2;
    const hits: PlexMediaItem[] = [];

    // Store external IDs for later matching
    let imdbId: string | undefined;
    let tvdbId: number | undefined;

    // 1) First, get TMDB details to get title and external IDs
    try {
      const details = mediaType === 'movie'
        ? await core.tmdb.getMovieDetails(Number(tmdbId))
        : await core.tmdb.getTVDetails(Number(tmdbId));

      // Get external IDs
      const externalIds = (details as any)?.external_ids;
      imdbId = externalIds?.imdb_id;
      tvdbId = externalIds?.tvdb_id;

      // Extract title/year if not provided
      if (!title) {
        title = (details as any)?.title || (details as any)?.name;
      }
      if (!year) {
        const releaseDate = (details as any)?.release_date || (details as any)?.first_air_date;
        if (releaseDate) {
          year = releaseDate.slice(0, 4);
        }
      }
    } catch (e) {
      console.log('[DetailsData] Failed to get TMDB details:', e);
    }

    // 2) Search Plex by title (most reliable method)
    if (title) {
      try {
        console.log(`[DetailsData] Searching Plex for: "${title}"`);
        const searchResults = await core.plexServer.search(title, typeNum);
        console.log(`[DetailsData] Search returned ${searchResults.length} results`);
        if (searchResults.length > 0) {
          hits.push(...searchResults);
        }
      } catch (e) {
        console.log('[DetailsData] Typed search failed:', e);
      }

      // Try untyped search if no results
      if (hits.length === 0) {
        try {
          const searchResults = await core.plexServer.search(title);
          console.log(`[DetailsData] Untyped search returned ${searchResults.length} results`);
          if (searchResults.length > 0) {
            hits.push(...searchResults);
          }
        } catch (e) {
          console.log('[DetailsData] Untyped search failed:', e);
        }
      }
    }

    if (hits.length === 0) {
      console.log('[DetailsData] No Plex matches found for:', { tmdbId, title, year });
      return null;
    }

    // Deduplicate by ratingKey
    const unique = Array.from(
      new Map(hits.map((h) => [String(h.ratingKey), h])).values()
    );
    console.log(`[DetailsData] Found ${unique.length} unique Plex items`);

    // 3) Selection policy - match by GUID from search results
    // a) Exact TMDB GUID match
    for (const h of unique) {
      const guids = extractGuidsFromItem(h);
      if (guids.includes(`tmdb://${tmdbId}`)) {
        console.log(`[DetailsData] Matched by TMDB GUID: ${h.ratingKey}`);
        return h;
      }
    }

    // b) IMDB GUID match
    if (imdbId) {
      for (const h of unique) {
        const guids = extractGuidsFromItem(h);
        if (guids.includes(`imdb://${imdbId}`)) {
          console.log(`[DetailsData] Matched by IMDB GUID: ${h.ratingKey}`);
          return h;
        }
      }
    }

    // c) TVDB GUID match (for TV shows)
    if (tvdbId && mediaType === 'tv') {
      for (const h of unique) {
        const guids = extractGuidsFromItem(h);
        if (guids.includes(`tvdb://${tvdbId}`)) {
          console.log(`[DetailsData] Matched by TVDB GUID: ${h.ratingKey}`);
          return h;
        }
      }
    }

    // d) Normalized title + same/near year (±1)
    if (title) {
      const nTitle = normalizeTitle(title);
      const yy = Number(year || 0);
      for (const h of unique) {
        const t = normalizeTitle(h.title || (h as any).grandparentTitle || '');
        const y = Number(h.year || 0);
        const yearOk = !yy || y === yy || y === yy - 1 || y === yy + 1;
        if (t === nTitle && yearOk) {
          console.log(`[DetailsData] Matched by title+year: ${h.ratingKey} (${h.title} ${h.year})`);
          return h;
        }
      }
    }

    // e) Fallback: first item
    console.log(`[DetailsData] Fallback to first result: ${unique[0]?.ratingKey}`);
    return unique[0] || null;
  } catch (e) {
    console.log('[DetailsData] mapTmdbToPlex error:', e);
    return null;
  }
}

/**
 * Extract all GUIDs from a Plex item (handles different formats)
 */
function extractGuidsFromItem(item: PlexMediaItem): string[] {
  const guids: string[] = [];

  // Check Guid array (modern Plex format)
  if (Array.isArray((item as any).Guid)) {
    for (const g of (item as any).Guid) {
      const id = String(g.id || '');
      if (id) guids.push(id);
    }
  }

  // Check guid field (older format)
  if ((item as any).guid) {
    const guid = String((item as any).guid);
    // Extract embedded GUIDs from plex:// format
    if (guid.includes('tmdb://')) {
      const match = guid.match(/tmdb:\/\/(\d+)/);
      if (match) guids.push(`tmdb://${match[1]}`);
    }
    if (guid.includes('imdb://')) {
      const match = guid.match(/imdb:\/\/([a-z0-9]+)/i);
      if (match) guids.push(`imdb://${match[1]}`);
    }
    if (guid.includes('tvdb://')) {
      const match = guid.match(/tvdb:\/\/(\d+)/);
      if (match) guids.push(`tvdb://${match[1]}`);
    }
    if (guid.includes('themoviedb://')) {
      const match = guid.match(/themoviedb:\/\/(\d+)/);
      if (match) guids.push(`tmdb://${match[1]}`);
    }
  }

  return guids;
}

// ============================================
// Image URLs
// ============================================

export function getPlexImageUrl(path: string | undefined, width: number = 300): string {
  if (!path) return '';
  try {
    const core = getFlixorCore();
    return core.plexServer.getImageUrl(path, width);
  } catch {
    return '';
  }
}

export function getTmdbImageUrl(path: string | undefined, size: string = 'w780'): string {
  if (!path) return '';
  try {
    const core = getFlixorCore();
    return core.tmdb.getImageUrl(path, size);
  } catch {
    return '';
  }
}

export function getTmdbProfileUrl(path: string | undefined): string {
  if (!path) return '';
  try {
    const core = getFlixorCore();
    return core.tmdb.getProfileUrl(path, 'w185');
  } catch {
    return '';
  }
}

// ============================================
// Helper: Extract TMDB ID from Plex Guids
// ============================================

export function extractTmdbIdFromGuids(guids: any[]): string | null {
  if (!Array.isArray(guids)) return null;
  for (const g of guids) {
    const id = String(g.id || '');
    if (id.includes('tmdb://') || id.includes('themoviedb://')) {
      return id.split('://')[1];
    }
  }
  return null;
}
