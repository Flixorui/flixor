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
// TMDB Videos/Trailers
// ============================================

// Supported video types (ordered by priority)
const VIDEO_TYPES = ['Trailer', 'Teaser', 'Clip', 'Featurette', 'Behind the Scenes'];

export interface TrailerInfo {
  key: string;
  name: string;
  site: string;
  type: string;
  official?: boolean;
  publishedAt?: string;
}

export async function fetchTmdbTrailers(
  mediaType: 'movie' | 'tv',
  tmdbId: number
): Promise<TrailerInfo[]> {
  try {
    const core = getFlixorCore();
    const videos = mediaType === 'movie'
      ? await core.tmdb.getMovieVideos(tmdbId)
      : await core.tmdb.getTVVideos(tmdbId);

    const results = videos.results || [];

    // Filter for YouTube videos of supported types
    const trailers = results
      .filter((v: any) => v.site === 'YouTube' && VIDEO_TYPES.includes(v.type))
      .sort((a: any, b: any) => {
        // Prioritize official videos
        if (a.official && !b.official) return -1;
        if (!a.official && b.official) return 1;
        // Then by type priority
        const aTypeIndex = VIDEO_TYPES.indexOf(a.type);
        const bTypeIndex = VIDEO_TYPES.indexOf(b.type);
        if (aTypeIndex !== bTypeIndex) return aTypeIndex - bTypeIndex;
        // Then by publish date (newest first)
        if (a.published_at && b.published_at) {
          return new Date(b.published_at).getTime() - new Date(a.published_at).getTime();
        }
        return 0;
      })
      .map((v: any) => ({
        key: v.key,
        name: v.name,
        site: v.site,
        type: v.type,
        official: v.official,
        publishedAt: v.published_at,
      }));

    return trailers;
  } catch (e) {
    console.log('[DetailsData] fetchTmdbTrailers error:', e);
    return [];
  }
}

export function getYouTubeUrl(videoKey: string): string {
  return `https://www.youtube.com/watch?v=${videoKey}`;
}

export function getYouTubeThumbnailUrl(videoKey: string): string {
  return `https://img.youtube.com/vi/${videoKey}/hqdefault.jpg`;
}

// ============================================
// TMDB Episode Stills (for Plex fallback)
// ============================================

export interface TMDBEpisodeData {
  still_path?: string;
  air_date?: string;
  vote_average?: number;
}

/**
 * Fetch TMDB episode data for a season (stills, air_date, vote_average)
 * Returns a Map of episode_number -> episode data
 */
export async function fetchTmdbEpisodeStills(
  tvId: number,
  seasonNumber: number
): Promise<Map<number, TMDBEpisodeData>> {
  const episodeData = new Map<number, TMDBEpisodeData>();
  try {
    const core = getFlixorCore();
    const season = await core.tmdb.getSeasonDetails(tvId, seasonNumber);
    for (const ep of season.episodes || []) {
      episodeData.set(ep.episode_number, {
        still_path: ep.still_path ?? undefined,
        air_date: ep.air_date,
        vote_average: ep.vote_average,
      });
    }
  } catch (e) {
    console.log('[DetailsData] fetchTmdbEpisodeStills error:', e);
  }
  return episodeData;
}

// ============================================
// TMDB Episode Details (for enrichment)
// ============================================

export interface EpisodeEnrichment {
  air_date?: string;
  vote_average?: number;
  runtime?: number;
  guest_stars?: Array<{ id: number; name: string; character?: string; profile_path?: string | null }>;
  director?: string;
  writer?: string;
}

/**
 * Fetch TMDB episode details for enrichment (guest stars, crew, etc.)
 */
export async function fetchTmdbEpisodeDetails(
  tvId: number,
  seasonNumber: number,
  episodeNumber: number
): Promise<EpisodeEnrichment | null> {
  try {
    const core = getFlixorCore();
    const details = await core.tmdb.getEpisodeDetails(tvId, seasonNumber, episodeNumber);

    // Extract director and writer from crew
    const director = details.crew?.find((c: any) => c.job === 'Director')?.name;
    const writer = details.crew?.find((c: any) => c.job === 'Writer' || c.department === 'Writing')?.name;

    return {
      air_date: details.air_date,
      vote_average: details.vote_average,
      runtime: details.runtime,
      guest_stars: details.guest_stars?.slice(0, 8), // Limit to 8 guest stars
      director,
      writer,
    };
  } catch (e) {
    console.log('[DetailsData] fetchTmdbEpisodeDetails error:', e);
    return null;
  }
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

// ============================================
// Helper: Extract IMDB ID from Plex Guids
// ============================================

export function extractImdbIdFromGuids(guids: any[]): string | null {
  if (!Array.isArray(guids)) return null;
  for (const g of guids) {
    const id = String(g.id || '');
    if (id.includes('imdb://')) {
      return id.split('://')[1];
    }
  }
  return null;
}

// ============================================
// Person Data
// ============================================

export interface PersonInfo {
  id: number;
  name: string;
  biography?: string;
  birthday?: string;
  deathday?: string;
  placeOfBirth?: string;
  profilePath?: string;
  knownFor?: string;
}

export interface PersonCredit {
  id: number;
  title: string;
  posterPath?: string;
  mediaType: 'movie' | 'tv';
  character?: string;
  job?: string;
  year?: string;
  voteAverage?: number;
}

export async function fetchPersonDetails(personId: number): Promise<PersonInfo | null> {
  try {
    const core = getFlixorCore();
    const person = await core.tmdb.getPersonDetails(personId);

    return {
      id: person.id,
      name: person.name,
      biography: person.biography,
      birthday: person.birthday,
      deathday: person.deathday,
      placeOfBirth: person.place_of_birth,
      profilePath: person.profile_path,
      knownFor: person.known_for_department,
    };
  } catch (e) {
    console.log('[DetailsData] fetchPersonDetails error:', e);
    return null;
  }
}

export async function fetchPersonCredits(personId: number): Promise<PersonCredit[]> {
  try {
    const core = getFlixorCore();
    const credits = await core.tmdb.getPersonCredits(personId);

    // Combine cast and crew, dedupe by id+media_type
    const allCredits: PersonCredit[] = [];
    const seen = new Set<string>();

    // Process cast credits
    for (const item of credits.cast || []) {
      const key = `${item.media_type}:${item.id}`;
      if (seen.has(key)) continue;
      seen.add(key);

      allCredits.push({
        id: item.id,
        title: item.title || item.name || 'Untitled',
        posterPath: item.poster_path,
        mediaType: item.media_type,
        character: item.character,
        year: (item.release_date || item.first_air_date || '').slice(0, 4),
        voteAverage: item.vote_average,
      });
    }

    // Process crew credits (if not already added as cast)
    for (const item of credits.crew || []) {
      const key = `${item.media_type}:${item.id}`;
      if (seen.has(key)) continue;
      seen.add(key);

      allCredits.push({
        id: item.id,
        title: item.title || item.name || 'Untitled',
        posterPath: item.poster_path,
        mediaType: item.media_type,
        job: item.job,
        year: (item.release_date || item.first_air_date || '').slice(0, 4),
        voteAverage: item.vote_average,
      });
    }

    // Sort by popularity (vote_average as proxy)
    allCredits.sort((a, b) => (b.voteAverage || 0) - (a.voteAverage || 0));

    return allCredits.slice(0, 20); // Top 20 credits
  } catch (e) {
    console.log('[DetailsData] fetchPersonCredits error:', e);
    return [];
  }
}

export function getPersonProfileUrl(profilePath: string | undefined, size: string = 'w185'): string {
  if (!profilePath) return '';
  try {
    const core = getFlixorCore();
    return core.tmdb.getProfileUrl(profilePath, size);
  } catch {
    return '';
  }
}

// ============================================
// Next Up Episode for TV Shows
// ============================================

export interface NextUpEpisode {
  ratingKey: string;
  title: string;
  seasonNumber: number;
  episodeNumber: number;
  thumb?: string;
  progress: number; // 0-100
  status: 'in-progress' | 'next-unwatched' | 'all-watched';
}

/**
 * Get the next episode to watch for a TV show
 * Priority:
 * 1. Episode currently in progress (has viewOffset but not completed)
 * 2. First unwatched episode
 * 3. If all watched, returns first episode for "Rewatch"
 */
export async function getNextUpEpisode(
  showRatingKey: string,
  allSeasons: any[]
): Promise<NextUpEpisode | null> {
  try {
    const core = getFlixorCore();

    // First, check Plex on-deck for this show
    try {
      const onDeck = await core.plexServer.getOnDeck();
      const showOnDeck = onDeck.find(
        (item: any) =>
          item.type === 'episode' &&
          (item.grandparentRatingKey === showRatingKey ||
            String(item.grandparentRatingKey) === String(showRatingKey))
      );

      if (showOnDeck) {
        const progress = showOnDeck.viewOffset && showOnDeck.duration
          ? Math.round((showOnDeck.viewOffset / showOnDeck.duration) * 100)
          : 0;
        return {
          ratingKey: String(showOnDeck.ratingKey),
          title: showOnDeck.title || 'Episode',
          seasonNumber: showOnDeck.parentIndex || 1,
          episodeNumber: showOnDeck.index || 1,
          thumb: showOnDeck.thumb,
          progress,
          status: 'in-progress',
        };
      }
    } catch (e) {
      console.log('[DetailsData] getOnDeck failed, falling back to episode scan:', e);
    }

    // Fallback: scan through all seasons/episodes to find next up
    let firstEpisode: NextUpEpisode | null = null;
    let firstUnwatched: NextUpEpisode | null = null;
    let inProgress: NextUpEpisode | null = null;

    for (const season of allSeasons) {
      const seasonRk = season.ratingKey || season.key;
      if (!seasonRk) continue;

      // Skip specials (season 0)
      const seasonNum = season.index || season.parentIndex || parseInt(season.key) || 0;
      if (seasonNum === 0) continue;

      try {
        const episodes = await core.plexServer.getChildren(String(seasonRk));

        for (const ep of episodes) {
          const epNum = ep.index || 1;
          const viewOffset = ep.viewOffset || 0;
          const duration = ep.duration || 1;
          const viewCount = ep.viewCount || 0;
          const progress = Math.round((viewOffset / duration) * 100);
          const isCompleted = viewCount > 0 || progress >= 95;

          const epInfo: NextUpEpisode = {
            ratingKey: String(ep.ratingKey),
            title: ep.title || `Episode ${epNum}`,
            seasonNumber: seasonNum,
            episodeNumber: epNum,
            thumb: ep.thumb,
            progress,
            status: 'next-unwatched',
          };

          // Track first episode for rewatch
          if (!firstEpisode) {
            firstEpisode = { ...epInfo, status: 'all-watched' };
          }

          // Check for in-progress episode (has progress but not completed)
          if (viewOffset > 0 && !isCompleted && !inProgress) {
            inProgress = { ...epInfo, status: 'in-progress' };
          }

          // Check for first unwatched episode
          if (!isCompleted && !firstUnwatched) {
            firstUnwatched = epInfo;
          }

          // If we found an in-progress episode, we can stop
          if (inProgress) break;
        }

        if (inProgress) break;
      } catch (e) {
        console.log(`[DetailsData] Failed to fetch episodes for season ${seasonRk}:`, e);
      }
    }

    // Return in priority order
    if (inProgress) return inProgress;
    if (firstUnwatched) return firstUnwatched;
    if (firstEpisode) return firstEpisode; // All watched - offer rewatch

    return null;
  } catch (e) {
    console.log('[DetailsData] getNextUpEpisode error:', e);
    return null;
  }
}

// ============================================
// Watchlist Functions
// ============================================

export interface WatchlistIds {
  tmdbId?: number;
  imdbId?: string;
  plexRatingKey?: string;
  mediaType: 'movie' | 'tv';
}

/**
 * Check if item is in Plex watchlist
 */
export async function isInPlexWatchlist(ratingKey: string): Promise<boolean> {
  try {
    const core = getFlixorCore();
    return await core.plexTv.isInWatchlist(ratingKey);
  } catch (e) {
    console.log('[DetailsData] isInPlexWatchlist error:', e);
    return false;
  }
}

/**
 * Check if item is in Trakt watchlist
 */
export async function isInTraktWatchlist(ids: WatchlistIds): Promise<boolean> {
  try {
    const core = getFlixorCore();
    if (!core.isTraktAuthenticated) return false;

    const type = ids.mediaType === 'movie' ? 'movies' : 'shows';
    const watchlist = await core.trakt.getWatchlist(type);

    return watchlist.some((item: any) => {
      const mediaItem = ids.mediaType === 'movie' ? item.movie : item.show;
      if (!mediaItem?.ids) return false;

      if (ids.tmdbId && mediaItem.ids.tmdb === ids.tmdbId) return true;
      if (ids.imdbId && mediaItem.ids.imdb === ids.imdbId) return true;
      return false;
    });
  } catch (e) {
    console.log('[DetailsData] isInTraktWatchlist error:', e);
    return false;
  }
}

/**
 * Add item to Plex watchlist
 */
export async function addToPlexWatchlist(ratingKey: string): Promise<boolean> {
  try {
    const core = getFlixorCore();
    await core.plexTv.addToWatchlist(ratingKey);
    return true;
  } catch (e) {
    console.log('[DetailsData] addToPlexWatchlist error:', e);
    return false;
  }
}

/**
 * Remove item from Plex watchlist
 */
export async function removeFromPlexWatchlist(ratingKey: string): Promise<boolean> {
  try {
    const core = getFlixorCore();
    await core.plexTv.removeFromWatchlist(ratingKey);
    return true;
  } catch (e) {
    console.log('[DetailsData] removeFromPlexWatchlist error:', e);
    return false;
  }
}

/**
 * Add item to Trakt watchlist
 */
export async function addToTraktWatchlist(ids: WatchlistIds): Promise<boolean> {
  try {
    const core = getFlixorCore();
    if (!core.isTraktAuthenticated) return false;

    const idsObj: { tmdb?: number; imdb?: string } = {};
    if (ids.tmdbId) idsObj.tmdb = ids.tmdbId;
    if (ids.imdbId) idsObj.imdb = ids.imdbId;

    if (ids.mediaType === 'movie') {
      await core.trakt.addMovieToWatchlist({ ids: idsObj });
    } else {
      await core.trakt.addShowToWatchlist({ ids: idsObj });
    }
    return true;
  } catch (e) {
    console.log('[DetailsData] addToTraktWatchlist error:', e);
    return false;
  }
}

/**
 * Remove item from Trakt watchlist
 */
export async function removeFromTraktWatchlist(ids: WatchlistIds): Promise<boolean> {
  try {
    const core = getFlixorCore();
    if (!core.isTraktAuthenticated) return false;

    const idsObj: { tmdb?: number; imdb?: string } = {};
    if (ids.tmdbId) idsObj.tmdb = ids.tmdbId;
    if (ids.imdbId) idsObj.imdb = ids.imdbId;

    if (ids.mediaType === 'movie') {
      await core.trakt.removeMovieFromWatchlist({ ids: idsObj });
    } else {
      await core.trakt.removeShowFromWatchlist({ ids: idsObj });
    }
    return true;
  } catch (e) {
    console.log('[DetailsData] removeFromTraktWatchlist error:', e);
    return false;
  }
}

/**
 * Toggle watchlist status (add or remove based on current state)
 *
 * ADD behavior (respects user preference):
 * - If Trakt is NOT authenticated → always saves to Plex
 * - If Trakt IS authenticated → uses watchlistProvider setting (default: 'trakt')
 *
 * REMOVE behavior (keeps providers in sync):
 * - Always removes from BOTH Plex and Trakt to prevent orphaned entries
 */
export async function toggleWatchlist(
  ids: WatchlistIds,
  _provider: 'plex' | 'trakt' | 'both' = 'both'
): Promise<{ inWatchlist: boolean; success: boolean }> {
  try {
    const core = getFlixorCore();
    const { getAppSettings } = await import('./SettingsData');
    const settings = getAppSettings();

    let isInWatchlist = false;

    // Check current watchlist status from BOTH providers
    if (ids.plexRatingKey) {
      isInWatchlist = await isInPlexWatchlist(ids.plexRatingKey);
    }

    if (!isInWatchlist && core.isTraktAuthenticated && (ids.tmdbId || ids.imdbId)) {
      isInWatchlist = await isInTraktWatchlist(ids);
    }

    // Toggle
    if (isInWatchlist) {
      // REMOVE: Always remove from BOTH providers to keep them in sync
      let success = true;

      if (ids.plexRatingKey) {
        success = await removeFromPlexWatchlist(ids.plexRatingKey) && success;
      }

      if (core.isTraktAuthenticated && (ids.tmdbId || ids.imdbId)) {
        success = await removeFromTraktWatchlist(ids) && success;
      }

      return { inWatchlist: false, success };
    } else {
      // ADD: Save to determined provider only based on settings
      let targetProvider: 'plex' | 'trakt';

      if (!core.isTraktAuthenticated) {
        // Trakt not enabled, always use Plex
        targetProvider = 'plex';
      } else {
        // Trakt is enabled - use user preference (default: 'trakt')
        targetProvider = settings.watchlistProvider || 'trakt';
      }

      let success = false;

      if (targetProvider === 'trakt') {
        if (ids.tmdbId || ids.imdbId) {
          success = await addToTraktWatchlist(ids);
        } else {
          // Fallback to Plex if we don't have TMDB/IMDB IDs for Trakt
          console.log('[DetailsData] No TMDB/IMDB IDs for Trakt, falling back to Plex');
          if (ids.plexRatingKey) {
            success = await addToPlexWatchlist(ids.plexRatingKey);
          }
        }
      } else {
        // targetProvider === 'plex'
        if (ids.plexRatingKey) {
          success = await addToPlexWatchlist(ids.plexRatingKey);
        } else {
          // Fallback to Trakt if we don't have Plex rating key
          console.log('[DetailsData] No Plex rating key, falling back to Trakt');
          if (core.isTraktAuthenticated && (ids.tmdbId || ids.imdbId)) {
            success = await addToTraktWatchlist(ids);
          }
        }
      }

      return { inWatchlist: success, success };
    }
  } catch (e) {
    console.log('[DetailsData] toggleWatchlist error:', e);
    return { inWatchlist: false, success: false };
  }
}

/**
 * Check if item is in watchlist (either Plex or Trakt)
 */
export async function checkWatchlistStatus(ids: WatchlistIds): Promise<boolean> {
  try {
    const core = getFlixorCore();

    // Check Plex first
    if (ids.plexRatingKey) {
      const inPlex = await isInPlexWatchlist(ids.plexRatingKey);
      if (inPlex) return true;
    }

    // Check Trakt
    if (core.isTraktAuthenticated && (ids.tmdbId || ids.imdbId)) {
      const inTrakt = await isInTraktWatchlist(ids);
      if (inTrakt) return true;
    }

    return false;
  } catch (e) {
    console.log('[DetailsData] checkWatchlistStatus error:', e);
    return false;
  }
}
