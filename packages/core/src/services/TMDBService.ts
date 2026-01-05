import type { ICache } from '../storage/ICache';
import { CacheTTL } from '../storage/ICache';
import type {
  TMDBMedia,
  TMDBMovieDetails,
  TMDBTVDetails,
  TMDBSeason,
  TMDBCredits,
  TMDBExternalIds,
  TMDBVideosResponse,
  TMDBImages,
  TMDBResultsResponse,
  TMDBPerson,
  TMDBPersonCredits,
} from '../models/tmdb';
import { TMDBImageSize } from '../models/tmdb';

const TMDB_API_URL = 'https://api.themoviedb.org/3';
const TMDB_IMAGE_BASE = 'https://image.tmdb.org/t/p';

/**
 * Service for TMDB API (The Movie Database)
 */
export class TMDBService {
  private apiKey: string;
  private cache: ICache;
  private language: string;

  constructor(options: { apiKey: string; cache: ICache; language?: string }) {
    this.apiKey = options.apiKey;
    this.cache = options.cache;
    this.language = options.language || 'en-US';
  }

  /**
   * Make a GET request to TMDB with caching
   */
  private async get<T>(
    path: string,
    params?: Record<string, string>,
    ttl: number = CacheTTL.TRENDING
  ): Promise<T> {
    const queryParams = new URLSearchParams({
      api_key: this.apiKey,
      language: this.language,
      ...params,
    });

    const url = `${TMDB_API_URL}${path}?${queryParams.toString()}`;
    const cacheKey = `tmdb:${url}`;

    // Check cache first
    if (ttl > 0) {
      const cached = await this.cache.get<T>(cacheKey);
      if (cached) {
        return cached;
      }
    }

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`TMDB API error: ${response.status}`);
    }

    const data = await response.json();

    // Cache the response
    if (ttl > 0) {
      await this.cache.set(cacheKey, data, ttl);
    }

    return data;
  }

  // ============================================
  // Image URLs
  // ============================================

  /**
   * Get full image URL for a TMDB image path
   */
  getImageUrl(
    path: string | null | undefined,
    size: string = TMDBImageSize.POSTER.LARGE
  ): string {
    if (!path) return '';
    return `${TMDB_IMAGE_BASE}/${size}${path}`;
  }

  /**
   * Get poster URL
   */
  getPosterUrl(path: string | null | undefined, width: 'w185' | 'w342' | 'w500' | 'w780' | 'original' = 'w500'): string {
    if (!path) return '';
    return `${TMDB_IMAGE_BASE}/${width}${path}`;
  }

  /**
   * Get backdrop URL
   */
  getBackdropUrl(path: string | null | undefined, width: 'w300' | 'w780' | 'w1280' | 'original' = 'w1280'): string {
    if (!path) return '';
    return `${TMDB_IMAGE_BASE}/${width}${path}`;
  }

  /**
   * Get profile URL (for cast/crew)
   */
  getProfileUrl(path: string | null | undefined, width: 'w45' | 'w185' | 'h632' | 'original' = 'w185'): string {
    if (!path) return '';
    return `${TMDB_IMAGE_BASE}/${width}${path}`;
  }

  // ============================================
  // Movies
  // ============================================

  /**
   * Get movie details (includes external_ids for IMDB matching)
   */
  async getMovieDetails(id: number): Promise<TMDBMovieDetails> {
    return this.get<TMDBMovieDetails>(
      `/movie/${id}`,
      { append_to_response: 'external_ids' },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get movie credits (cast & crew)
   */
  async getMovieCredits(id: number): Promise<TMDBCredits> {
    return this.get<TMDBCredits>(
      `/movie/${id}/credits`,
      undefined,
      CacheTTL.TRENDING
    );
  }

  /**
   * Get movie external IDs (IMDB, etc.)
   */
  async getMovieExternalIds(id: number): Promise<TMDBExternalIds> {
    return this.get<TMDBExternalIds>(
      `/movie/${id}/external_ids`,
      undefined,
      CacheTTL.STATIC
    );
  }

  /**
   * Get movie videos (trailers, etc.)
   */
  async getMovieVideos(id: number): Promise<TMDBVideosResponse> {
    return this.get<TMDBVideosResponse>(
      `/movie/${id}/videos`,
      undefined,
      CacheTTL.TRENDING
    );
  }

  /**
   * Get movie images
   */
  async getMovieImages(id: number): Promise<TMDBImages> {
    return this.get<TMDBImages>(
      `/movie/${id}/images`,
      { include_image_language: 'en,null' },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get similar movies
   */
  async getSimilarMovies(id: number, page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      `/movie/${id}/similar`,
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get movie recommendations
   */
  async getMovieRecommendations(id: number, page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      `/movie/${id}/recommendations`,
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  // ============================================
  // TV Shows
  // ============================================

  /**
   * Get TV show details (includes external_ids for TVDB/IMDB matching)
   */
  async getTVDetails(id: number): Promise<TMDBTVDetails> {
    return this.get<TMDBTVDetails>(
      `/tv/${id}`,
      { append_to_response: 'external_ids' },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get TV show credits
   */
  async getTVCredits(id: number): Promise<TMDBCredits> {
    return this.get<TMDBCredits>(
      `/tv/${id}/credits`,
      undefined,
      CacheTTL.TRENDING
    );
  }

  /**
   * Get TV external IDs
   */
  async getTVExternalIds(id: number): Promise<TMDBExternalIds> {
    return this.get<TMDBExternalIds>(
      `/tv/${id}/external_ids`,
      undefined,
      CacheTTL.STATIC
    );
  }

  /**
   * Get TV videos
   */
  async getTVVideos(id: number): Promise<TMDBVideosResponse> {
    return this.get<TMDBVideosResponse>(
      `/tv/${id}/videos`,
      undefined,
      CacheTTL.TRENDING
    );
  }

  /**
   * Get TV images
   */
  async getTVImages(id: number): Promise<TMDBImages> {
    return this.get<TMDBImages>(
      `/tv/${id}/images`,
      { include_image_language: 'en,null' },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get similar TV shows
   */
  async getSimilarTV(id: number, page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      `/tv/${id}/similar`,
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get TV recommendations
   */
  async getTVRecommendations(id: number, page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      `/tv/${id}/recommendations`,
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get season details
   */
  async getSeasonDetails(tvId: number, seasonNumber: number): Promise<TMDBSeason> {
    return this.get<TMDBSeason>(
      `/tv/${tvId}/season/${seasonNumber}`,
      undefined,
      CacheTTL.DYNAMIC
    );
  }

  // ============================================
  // Discover & Trending
  // ============================================

  /**
   * Get trending movies
   */
  async getTrendingMovies(timeWindow: 'day' | 'week' = 'week', page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      `/trending/movie/${timeWindow}`,
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get trending TV shows
   */
  async getTrendingTV(timeWindow: 'day' | 'week' = 'week', page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      `/trending/tv/${timeWindow}`,
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get trending all (movies + TV)
   */
  async getTrendingAll(timeWindow: 'day' | 'week' = 'week', page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      `/trending/all/${timeWindow}`,
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get popular movies
   */
  async getPopularMovies(page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/movie/popular',
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get popular TV shows
   */
  async getPopularTV(page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/tv/popular',
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get top rated movies
   */
  async getTopRatedMovies(page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/movie/top_rated',
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get top rated TV shows
   */
  async getTopRatedTV(page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/tv/top_rated',
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get upcoming movies
   */
  async getUpcomingMovies(page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/movie/upcoming',
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get now playing movies
   */
  async getNowPlayingMovies(page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/movie/now_playing',
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get TV shows airing today
   */
  async getTVAiringToday(page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/tv/airing_today',
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  /**
   * Get TV shows on the air
   */
  async getTVOnTheAir(page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/tv/on_the_air',
      { page: String(page) },
      CacheTTL.TRENDING
    );
  }

  // ============================================
  // Search
  // ============================================

  /**
   * Search for movies
   */
  async searchMovies(query: string, page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/search/movie',
      { query, page: String(page) },
      CacheTTL.SHORT
    );
  }

  /**
   * Search for TV shows
   */
  async searchTV(query: string, page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/search/tv',
      { query, page: String(page) },
      CacheTTL.SHORT
    );
  }

  /**
   * Search for movies and TV shows
   */
  async searchMulti(query: string, page: number = 1): Promise<TMDBResultsResponse<TMDBMedia>> {
    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/search/multi',
      { query, page: String(page) },
      CacheTTL.SHORT
    );
  }

  // ============================================
  // Discover
  // ============================================

  /**
   * Discover movies with filters
   */
  async discoverMovies(options?: {
    page?: number;
    sortBy?: string;
    withGenres?: string;
    region?: string;
  }): Promise<TMDBResultsResponse<TMDBMedia>> {
    const params: Record<string, string> = {
      page: String(options?.page || 1),
      sort_by: options?.sortBy || 'popularity.desc',
    };
    if (options?.withGenres) params.with_genres = options.withGenres;
    if (options?.region) params.region = options.region;

    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/discover/movie',
      params,
      CacheTTL.TRENDING
    );
  }

  /**
   * Discover TV shows with filters
   */
  async discoverTV(options?: {
    page?: number;
    sortBy?: string;
    withGenres?: string;
  }): Promise<TMDBResultsResponse<TMDBMedia>> {
    const params: Record<string, string> = {
      page: String(options?.page || 1),
      sort_by: options?.sortBy || 'popularity.desc',
    };
    if (options?.withGenres) params.with_genres = options.withGenres;

    return this.get<TMDBResultsResponse<TMDBMedia>>(
      '/discover/tv',
      params,
      CacheTTL.TRENDING
    );
  }

  // ============================================
  // Lookup by External ID
  // ============================================

  /**
   * Find by IMDB ID
   */
  async findByImdbId(imdbId: string): Promise<{ movie_results: TMDBMedia[]; tv_results: TMDBMedia[] }> {
    return this.get<{ movie_results: TMDBMedia[]; tv_results: TMDBMedia[] }>(
      `/find/${imdbId}`,
      { external_source: 'imdb_id' },
      CacheTTL.STATIC
    );
  }

  /**
   * Find by TVDB ID
   */
  async findByTvdbId(tvdbId: number): Promise<{ tv_results: TMDBMedia[] }> {
    return this.get<{ tv_results: TMDBMedia[] }>(
      `/find/${tvdbId}`,
      { external_source: 'tvdb_id' },
      CacheTTL.STATIC
    );
  }

  // ============================================
  // Person
  // ============================================

  /**
   * Get person details
   */
  async getPersonDetails(personId: number): Promise<TMDBPerson> {
    return this.get<TMDBPerson>(
      `/person/${personId}`,
      undefined,
      CacheTTL.TRENDING
    );
  }

  /**
   * Get person combined credits (movies + TV)
   */
  async getPersonCredits(personId: number): Promise<TMDBPersonCredits> {
    return this.get<TMDBPersonCredits>(
      `/person/${personId}/combined_credits`,
      undefined,
      CacheTTL.DYNAMIC
    );
  }

  // ============================================
  // Cache Management
  // ============================================

  /**
   * Invalidate all TMDB cache
   */
  async invalidateCache(): Promise<void> {
    await this.cache.invalidatePattern('tmdb:*');
  }
}
