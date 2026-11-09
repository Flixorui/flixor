import axios, { AxiosInstance, AxiosError } from 'axios';
import PQueue from 'p-queue';
import { cacheManager, CacheConfig } from '../cache/CacheManager';
import { createLogger } from '../../utils/logger';
import { AppDataSource } from '../../db/data-source';
import { UserSettings } from '../../db/entities';

const logger = createLogger('tmdb');

// Default TMDB API key (baked in)
const DEFAULT_TMDB_API_KEY = 'db55323b8d3e4154498498a75642b381';

// TMDB API configuration
const TMDB_BASE_URL = 'https://api.themoviedb.org/3';
const TMDB_IMAGE_BASE = 'https://image.tmdb.org/t/p';

// Rate limits
const DEFAULT_KEY_RATE_LIMIT = {
  concurrency: 50,   // Max concurrent requests
  interval: 1000,    // Time window (ms)
  intervalCap: 200   // Max requests per interval (200/sec)
};

const CUSTOM_KEY_RATE_LIMIT = {
  concurrency: 100,
  interval: 1000,
  intervalCap: 1000  // Max requests per interval (1000/sec)
};

interface TMDBUsageStats {
  requests: number;
  cacheHits: number;
  cacheMisses: number;
  errors: number;
  lastReset: Date;
}

export class TMDBClient {
  private apiKey: string;
  private isCustomKey: boolean;
  private axiosClient: AxiosInstance;
  private requestQueue: PQueue;
  private usageStats: TMDBUsageStats;
  private userId?: string;

  constructor(apiKey?: string, userId?: string) {
    this.apiKey = apiKey || DEFAULT_TMDB_API_KEY;
    this.isCustomKey = !!apiKey;
    this.userId = userId;

    // Setup rate limiting queue
    const rateLimit = this.isCustomKey ? CUSTOM_KEY_RATE_LIMIT : DEFAULT_KEY_RATE_LIMIT;
    this.requestQueue = new PQueue({
      concurrency: rateLimit.concurrency,
      interval: rateLimit.interval,
      intervalCap: rateLimit.intervalCap
    });

    // Initialize usage stats
    this.usageStats = {
      requests: 0,
      cacheHits: 0,
      cacheMisses: 0,
      errors: 0,
      lastReset: new Date()
    };

    // Create axios instance
    this.axiosClient = axios.create({
      baseURL: TMDB_BASE_URL,
      timeout: 10000,
      params: {
        api_key: this.apiKey
      },
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      }
    });

    // Add response interceptor for error handling
    this.axiosClient.interceptors.response.use(
      response => response,
      this.handleError.bind(this)
    );

    logger.info(`TMDB client initialized with ${this.isCustomKey ? 'custom' : 'default'} key`, {
      userId: this.userId,
      rateLimit
    });
  }

  /**
   * Handle API errors
   */
  private async handleError(error: AxiosError) {
    this.usageStats.errors++;

    if (error.response) {
      const status = error.response.status;
      const message = (error.response.data as any)?.status_message || 'Unknown error';

      // 404s are expected (invalid TMDB IDs, deleted movies, etc.) - log as warning not error
      if (status === 404) {
        logger.warn(`TMDB resource not found: ${error.config?.url}`, {
          userId: this.userId
        });
        throw new Error('Resource not found');
      }

      logger.error(`TMDB API error: ${status} - ${message}`, {
        url: error.config?.url,
        userId: this.userId
      });

      if (status === 401) {
        throw new Error('Invalid TMDB API key');
      } else if (status === 429) {
        // Rate limited - implement exponential backoff
        const retryAfter = error.response.headers['retry-after'] || '5';
        logger.warn(`Rate limited by TMDB. Retry after ${retryAfter}s`);
        throw new Error(`Rate limited. Please try again in ${retryAfter} seconds`);
      }
    }

    throw error;
  }

  /**
   * Make a cached request to TMDB
   */
  private async cachedRequest<T>(
    path: string,
    params?: any,
    cacheKey?: string,
    ttl?: number
  ): Promise<T> {
    const key = cacheKey || `${path}:${JSON.stringify(params || {})}`;

    // Try cache first
    const cached = cacheManager.get<T>('tmdb', key);
    if (cached) {
      this.usageStats.cacheHits++;
      logger.debug(`Cache HIT: ${key}`);
      return cached;
    }

    this.usageStats.cacheMisses++;

    // Queue the request for rate limiting
    return this.requestQueue.add(async () => {
      this.usageStats.requests++;
      logger.debug(`TMDB API request: ${path}`, { params });

      const response = await this.axiosClient.get<T>(path, { params });
      const data = response.data;

      // Cache the response
      cacheManager.set('tmdb', key, data, ttl);

      return data;
    }) as Promise<T>;
  }

  /**
   * Trending content
   */
  async getTrending(
    mediaType: 'all' | 'movie' | 'tv' | 'person' = 'all',
    timeWindow: 'day' | 'week' = 'week',
    page: number = 1
  ) {
    return this.cachedRequest(
      `/trending/${mediaType}/${timeWindow}`,
      { page },
      `trending:${mediaType}:${timeWindow}:${page}`,
      CacheConfig.tmdb.trending
    );
  }

  /**
   * Search multi
   */
  async searchMulti(query: string, page: number = 1) {
    return this.cachedRequest(
      '/search/multi',
      { query, page, include_adult: false },
      `search:multi:${query}:${page}`,
      CacheConfig.tmdb.search
    );
  }

  /**
   * Search movies
   */
  async searchMovies(query: string, year?: number, page: number = 1) {
    const params: any = { query, page, include_adult: false };
    if (year) params.year = year;

    return this.cachedRequest(
      '/search/movie',
      params,
      `search:movie:${query}:${year || ''}:${page}`,
      CacheConfig.tmdb.search
    );
  }

  /**
   * Search TV shows
   */
  async searchTVShows(query: string, firstAirYear?: number, page: number = 1) {
    const params: any = { query, page, include_adult: false };
    if (firstAirYear) params.first_air_date_year = firstAirYear;

    return this.cachedRequest(
      '/search/tv',
      params,
      `search:tv:${query}:${firstAirYear || ''}:${page}`,
      CacheConfig.tmdb.search
    );
  }

  /**
   * Get movie details
   */
  async getMovieDetails(movieId: number | string, appendToResponse?: string) {
    const params: any = {};
    if (appendToResponse) params.append_to_response = appendToResponse;

    return this.cachedRequest(
      `/movie/${movieId}`,
      params,
      `movie:${movieId}:${appendToResponse || ''}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Get TV show details
   */
  async getTVDetails(tvId: number | string, appendToResponse?: string) {
    const params: any = {};
    if (appendToResponse) params.append_to_response = appendToResponse;

    return this.cachedRequest(
      `/tv/${tvId}`,
      params,
      `tv:${tvId}:${appendToResponse || ''}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Get movie credits
   */
  async getMovieCredits(movieId: number | string) {
    return this.cachedRequest(
      `/movie/${movieId}/credits`,
      {},
      `movie:credits:${movieId}`,
      CacheConfig.tmdb.credits
    );
  }

  /**
   * Get TV credits
   */
  async getTVCredits(tvId: number | string) {
    return this.cachedRequest(
      `/tv/${tvId}/credits`,
      {},
      `tv:credits:${tvId}`,
      CacheConfig.tmdb.credits
    );
  }

  /**
   * Get recommendations
   */
  async getRecommendations(
    mediaType: 'movie' | 'tv',
    id: number | string,
    page: number = 1
  ) {
    return this.cachedRequest(
      `/${mediaType}/${id}/recommendations`,
      { page },
      `${mediaType}:recommendations:${id}:${page}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Get similar
   */
  async getSimilar(
    mediaType: 'movie' | 'tv',
    id: number | string,
    page: number = 1
  ) {
    return this.cachedRequest(
      `/${mediaType}/${id}/similar`,
      { page },
      `${mediaType}:similar:${id}:${page}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Get images
   */
  async getImages(
    mediaType: 'movie' | 'tv',
    id: number | string,
    includeImageLanguage: string = 'en,null'
  ) {
    return this.cachedRequest(
      `/${mediaType}/${id}/images`,
      { include_image_language: includeImageLanguage },
      `${mediaType}:images:${id}:${includeImageLanguage}`,
      CacheConfig.tmdb.images
    );
  }

  /**
   * Get videos
   */
  async getVideos(mediaType: 'movie' | 'tv', id: number | string) {
    return this.cachedRequest(
      `/${mediaType}/${id}/videos`,
      {},
      `${mediaType}:videos:${id}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Get external IDs
   */
  async getExternalIds(mediaType: 'movie' | 'tv', id: number | string) {
    return this.cachedRequest(
      `/${mediaType}/${id}/external_ids`,
      {},
      `${mediaType}:external_ids:${id}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Get popular
   */
  async getPopular(mediaType: 'movie' | 'tv', page: number = 1) {
    return this.cachedRequest(
      `/${mediaType}/popular`,
      { page },
      `${mediaType}:popular:${page}`,
      CacheConfig.tmdb.trending
    );
  }

  /**
   * Get upcoming movies
   */
  async getUpcoming(region?: string, page: number = 1) {
    const params: any = { page };
    if (region) params.region = region;

    return this.cachedRequest(
      '/movie/upcoming',
      params,
      `movie:upcoming:${region || 'US'}:${page}`,
      CacheConfig.tmdb.trending
    );
  }

  /**
   * Get TV season details
   */
  async getTVSeasonDetails(tvId: number | string, seasonNumber: number) {
    return this.cachedRequest(
      `/tv/${tvId}/season/${seasonNumber}`,
      {},
      `tv:season:${tvId}:${seasonNumber}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Get person details
   */
  async getPersonDetails(personId: number | string) {
    return this.cachedRequest(
      `/person/${personId}`,
      {},
      `person:${personId}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Get person combined credits
   */
  async getPersonCombinedCredits(personId: number | string) {
    return this.cachedRequest(
      `/person/${personId}/combined_credits`,
      {},
      `person:combined_credits:${personId}`,
      CacheConfig.tmdb.credits
    );
  }

  /**
   * Discover movies
   */
  async discoverMovies(params: any = {}) {
    return this.cachedRequest(
      '/discover/movie',
      { ...params, include_adult: false },
      `discover:movie:${JSON.stringify(params)}`,
      CacheConfig.tmdb.search
    );
  }

  /**
   * Discover TV shows
   */
  async discoverTV(params: any = {}) {
    return this.cachedRequest(
      '/discover/tv',
      { ...params, include_adult: false },
      `discover:tv:${JSON.stringify(params)}`,
      CacheConfig.tmdb.search
    );
  }

  /**
   * Search collections (franchises)
   */
  async searchCollections(query: string, page: number = 1) {
    return this.cachedRequest(
      '/search/collection',
      { query, page },
      `search:collection:${query}:${page}`,
      CacheConfig.tmdb.search
    );
  }

  /**
   * Collection (franchise) with its movies
   */
  async getCollection(collectionId: number | string) {
    return this.cachedRequest(
      `/collection/${collectionId}`,
      {},
      `collection:${collectionId}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Production company
   */
  async getCompany(companyId: number | string) {
    return this.cachedRequest(
      `/company/${companyId}`,
      {},
      `company:${companyId}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * TV network
   */
  async getNetwork(networkId: number | string) {
    return this.cachedRequest(
      `/network/${networkId}`,
      {},
      `network:${networkId}`,
      CacheConfig.tmdb.details
    );
  }

  /**
   * Validate API key
   */
  async validateKey(): Promise<boolean> {
    try {
      await this.axiosClient.get('/configuration');
      return true;
    } catch (error) {
      logger.error('TMDB API key validation failed', { error });
      return false;
    }
  }

  /**
   * Get usage statistics
   */
  getUsageStats(): TMDBUsageStats {
    return { ...this.usageStats };
  }

  /**
   * Reset usage statistics
   */
  resetUsageStats() {
    this.usageStats = {
      requests: 0,
      cacheHits: 0,
      cacheMisses: 0,
      errors: 0,
      lastReset: new Date()
    };
  }

  /**
   * Get image URL
   */
  static getImageUrl(path: string | null, size: string = 'original'): string | null {
    if (!path) return null;
    return `${TMDB_IMAGE_BASE}/${size}${path}`;
  }
}

// Singleton for default key client
let defaultClient: TMDBClient | null = null;

/**
 * Get or create default TMDB client
 */
export function getDefaultTMDBClient(): TMDBClient {
  if (!defaultClient) {
    defaultClient = new TMDBClient();
  }
  return defaultClient;
}

/**
 * Get or create user-specific TMDB client
 */
export async function getUserTMDBClient(userId: string): Promise<TMDBClient> {
  const settingsRepo = AppDataSource.getRepository(UserSettings);
  const settings = await settingsRepo.findOne({ where: { userId } });

  if (settings?.tmdbApiKey) {
    logger.info(`Using custom TMDB key for user ${userId}`);
    return new TMDBClient(settings.tmdbApiKey, userId);
  }

  // Fallback to default client
  return getDefaultTMDBClient();
}