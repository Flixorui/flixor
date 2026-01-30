import type { ICache } from '../storage/ICache';
import type { ISecureStorage } from '../storage/ISecureStorage';
import { CacheTTL } from '../storage/ICache';
import type {
  TraktTokens,
  TraktDeviceCode,
  TraktMovie,
  TraktShow,
  TraktSeason,
  TraktEpisode,
  TraktTrendingMovie,
  TraktTrendingShow,
  TraktWatchlistItem,
  TraktHistoryItem,
  TraktCollectionItem,
  TraktRatingItem,
  TraktPlaybackItem,
  TraktUser,
  TraktStats,
} from '../models/trakt';

const TRAKT_API_URL = 'https://api.trakt.tv';

/**
 * Service for Trakt API (device code OAuth + sync features)
 */
export class TraktService {
  private clientId: string;
  private clientSecret: string;
  private cache: ICache;
  private secureStorage: ISecureStorage;
  private tokens: TraktTokens | null = null;

  constructor(options: {
    clientId: string;
    clientSecret: string;
    cache: ICache;
    secureStorage: ISecureStorage;
  }) {
    this.clientId = options.clientId;
    this.clientSecret = options.clientSecret;
    this.cache = options.cache;
    this.secureStorage = options.secureStorage;
  }

  /**
   * Get standard Trakt headers
   */
  private getHeaders(includeAuth: boolean = false): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'trakt-api-version': '2',
      'trakt-api-key': this.clientId,
    };

    if (includeAuth && this.tokens?.access_token) {
      headers['Authorization'] = `Bearer ${this.tokens.access_token}`;
    }

    return headers;
  }

  /**
   * Make a GET request to Trakt with optional caching
   */
  private async get<T>(
    path: string,
    params?: Record<string, string>,
    options?: { auth?: boolean; ttl?: number }
  ): Promise<T> {
    const { auth = false, ttl = CacheTTL.TRENDING } = options || {};

    const queryString = params
      ? '?' + new URLSearchParams(params).toString()
      : '';
    const url = `${TRAKT_API_URL}${path}${queryString}`;
    const cacheKey = auth ? `trakt:auth:${path}${queryString}` : `trakt:${url}`;

    // Check cache first (only for non-auth or when TTL > 0)
    if (ttl > 0) {
      const cached = await this.cache.get<T>(cacheKey);
      if (cached) {
        return cached;
      }
    }

    const response = await fetch(url, {
      method: 'GET',
      headers: this.getHeaders(auth),
    });

    if (!response.ok) {
      if (response.status === 401) {
        // Token might be expired, try to refresh
        if (auth && this.tokens?.refresh_token) {
          await this.refreshTokens();
          // Retry the request
          const retryResponse = await fetch(url, {
            method: 'GET',
            headers: this.getHeaders(true),
          });
          if (!retryResponse.ok) {
            throw new Error(`Trakt API error: ${retryResponse.status}`);
          }
          const data = await retryResponse.json();
          if (ttl > 0) {
            await this.cache.set(cacheKey, data, ttl);
          }
          return data;
        }
        throw new Error('Authentication required');
      }
      throw new Error(`Trakt API error: ${response.status}`);
    }

    const data = await response.json();

    // Cache the response
    if (ttl > 0) {
      await this.cache.set(cacheKey, data, ttl);
    }

    return data;
  }

  /**
   * Make a POST request to Trakt
   */
  private async post<T>(
    path: string,
    body?: unknown,
    auth: boolean = false
  ): Promise<T> {
    const response = await fetch(`${TRAKT_API_URL}${path}`, {
      method: 'POST',
      headers: this.getHeaders(auth),
      body: body ? JSON.stringify(body) : undefined,
    });

    if (!response.ok) {
      throw new Error(`Trakt API error: ${response.status}`);
    }

    return response.json();
  }

  /**
   * Make a DELETE request to Trakt
   */
  private async delete<T>(path: string, body?: unknown): Promise<T> {
    const response = await fetch(`${TRAKT_API_URL}${path}`, {
      method: 'DELETE',
      headers: this.getHeaders(true),
      body: body ? JSON.stringify(body) : undefined,
    });

    if (!response.ok) {
      throw new Error(`Trakt API error: ${response.status}`);
    }

    return response.json();
  }

  // ============================================
  // Authentication (Device Code Flow)
  // ============================================

  /**
   * Initialize tokens from secure storage
   * This should be called after profile switches to reload tokens from the new storage context
   */
  async initialize(): Promise<boolean> {
    const storedTokens = await this.secureStorage.get<TraktTokens>('trakt_tokens');
    if (storedTokens) {
      this.tokens = storedTokens;

      // Check if tokens are expired
      const expiresAt = (storedTokens.created_at + storedTokens.expires_in) * 1000;
      if (Date.now() > expiresAt) {
        try {
          await this.refreshTokens();
        } catch {
          this.tokens = null;
          await this.secureStorage.remove('trakt_tokens');
          return false;
        }
      }
      return true;
    }
    // Clear in-memory tokens when no stored tokens found (important for profile switching)
    this.tokens = null;
    return false;
  }

  /**
   * Check if user is authenticated
   */
  isAuthenticated(): boolean {
    return this.tokens !== null;
  }

  /**
   * Generate device code for authentication
   */
  async generateDeviceCode(): Promise<TraktDeviceCode> {
    return this.post<TraktDeviceCode>('/oauth/device/code', {
      client_id: this.clientId,
    });
  }

  /**
   * Poll for device code authorization
   */
  async pollDeviceCode(deviceCode: string): Promise<TraktTokens | null> {
    try {
      const tokens = await this.post<TraktTokens>('/oauth/device/token', {
        code: deviceCode,
        client_id: this.clientId,
        client_secret: this.clientSecret,
      });

      this.tokens = tokens;
      await this.secureStorage.set('trakt_tokens', tokens);
      return tokens;
    } catch (error) {
      // 400 means still waiting for authorization
      if (error instanceof Error && error.message.includes('400')) {
        return null;
      }
      throw error;
    }
  }

  /**
   * Wait for device code authorization with polling
   */
  async waitForDeviceCode(
    deviceCode: TraktDeviceCode,
    options?: { onPoll?: () => void }
  ): Promise<TraktTokens> {
    const { onPoll } = options || {};
    const startTime = Date.now();
    const expiresAt = startTime + deviceCode.expires_in * 1000;

    while (Date.now() < expiresAt) {
      onPoll?.();

      const tokens = await this.pollDeviceCode(deviceCode.device_code);
      if (tokens) {
        return tokens;
      }

      await new Promise((resolve) =>
        setTimeout(resolve, deviceCode.interval * 1000)
      );
    }

    throw new Error('Device code authorization timed out');
  }

  /**
   * Refresh access tokens
   */
  async refreshTokens(): Promise<void> {
    if (!this.tokens?.refresh_token) {
      throw new Error('No refresh token available');
    }

    const newTokens = await this.post<TraktTokens>('/oauth/token', {
      refresh_token: this.tokens.refresh_token,
      client_id: this.clientId,
      client_secret: this.clientSecret,
      redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
      grant_type: 'refresh_token',
    });

    this.tokens = newTokens;
    await this.secureStorage.set('trakt_tokens', newTokens);
  }

  /**
   * Sign out - revoke tokens
   */
  async signOut(): Promise<void> {
    if (this.tokens?.access_token) {
      try {
        await this.post('/oauth/revoke', {
          token: this.tokens.access_token,
          client_id: this.clientId,
          client_secret: this.clientSecret,
        });
      } catch {
        // Ignore errors during sign out
      }
    }

    this.tokens = null;
    await this.secureStorage.remove('trakt_tokens');
    await this.cache.invalidatePattern('trakt:auth:*');
  }

  // ============================================
  // User
  // ============================================

  /**
   * Get authenticated user profile
   */
  async getProfile(): Promise<TraktUser> {
    return this.get<TraktUser>('/users/me', undefined, {
      auth: true,
      ttl: CacheTTL.DYNAMIC,
    });
  }

  /**
   * Get user stats
   */
  async getStats(): Promise<TraktStats> {
    return this.get<TraktStats>('/users/me/stats', undefined, {
      auth: true,
      ttl: CacheTTL.DYNAMIC,
    });
  }

  // ============================================
  // Trending & Popular
  // ============================================

  /**
   * Get trending movies
   */
  async getTrendingMovies(page: number = 1, limit: number = 20): Promise<TraktTrendingMovie[]> {
    return this.get<TraktTrendingMovie[]>(
      '/movies/trending',
      { page: String(page), limit: String(limit), extended: 'full' },
      { ttl: CacheTTL.TRENDING }
    );
  }

  /**
   * Get trending shows
   */
  async getTrendingShows(page: number = 1, limit: number = 20): Promise<TraktTrendingShow[]> {
    return this.get<TraktTrendingShow[]>(
      '/shows/trending',
      { page: String(page), limit: String(limit), extended: 'full' },
      { ttl: CacheTTL.TRENDING }
    );
  }

  /**
   * Get popular movies
   */
  async getPopularMovies(page: number = 1, limit: number = 20): Promise<TraktMovie[]> {
    return this.get<TraktMovie[]>(
      '/movies/popular',
      { page: String(page), limit: String(limit), extended: 'full' },
      { ttl: CacheTTL.TRENDING }
    );
  }

  /**
   * Get popular shows
   */
  async getPopularShows(page: number = 1, limit: number = 20): Promise<TraktShow[]> {
    return this.get<TraktShow[]>(
      '/shows/popular',
      { page: String(page), limit: String(limit), extended: 'full' },
      { ttl: CacheTTL.TRENDING }
    );
  }

  /**
   * Get recommended movies (personalized)
   */
  async getRecommendedMovies(page: number = 1, limit: number = 20): Promise<TraktMovie[]> {
    return this.get<TraktMovie[]>(
      '/recommendations/movies',
      { page: String(page), limit: String(limit), extended: 'full' },
      { auth: true, ttl: CacheTTL.DYNAMIC }
    );
  }

  /**
   * Get recommended shows (personalized)
   */
  async getRecommendedShows(page: number = 1, limit: number = 20): Promise<TraktShow[]> {
    return this.get<TraktShow[]>(
      '/recommendations/shows',
      { page: String(page), limit: String(limit), extended: 'full' },
      { auth: true, ttl: CacheTTL.DYNAMIC }
    );
  }

  // ============================================
  // Watchlist
  // ============================================

  /**
   * Get user's watchlist
   */
  async getWatchlist(type?: 'movies' | 'shows'): Promise<TraktWatchlistItem[]> {
    const path = type ? `/users/me/watchlist/${type}` : '/users/me/watchlist';
    return this.get<TraktWatchlistItem[]>(path, { extended: 'full' }, {
      auth: true,
      ttl: CacheTTL.DYNAMIC,
    });
  }

  /**
   * Add movie to watchlist
   */
  async addMovieToWatchlist(movie: { ids: { tmdb?: number; imdb?: string } }): Promise<void> {
    await this.post(
      '/sync/watchlist',
      { movies: [movie] },
      true
    );
    await this.cache.invalidatePattern('trakt:auth:*watchlist*');
  }

  /**
   * Add show to watchlist
   */
  async addShowToWatchlist(show: { ids: { tmdb?: number; imdb?: string } }): Promise<void> {
    await this.post(
      '/sync/watchlist',
      { shows: [show] },
      true
    );
    await this.cache.invalidatePattern('trakt:auth:*watchlist*');
  }

  /**
   * Remove movie from watchlist
   */
  async removeMovieFromWatchlist(movie: { ids: { tmdb?: number; imdb?: string } }): Promise<void> {
    await this.post(
      '/sync/watchlist/remove',
      { movies: [movie] },
      true
    );
    await this.cache.invalidatePattern('trakt:auth:*watchlist*');
  }

  /**
   * Remove show from watchlist
   */
  async removeShowFromWatchlist(show: { ids: { tmdb?: number; imdb?: string } }): Promise<void> {
    await this.post(
      '/sync/watchlist/remove',
      { shows: [show] },
      true
    );
    await this.cache.invalidatePattern('trakt:auth:*watchlist*');
  }

  // ============================================
  // History / Watched
  // ============================================

  /**
   * Get watch history
   */
  async getHistory(
    type?: 'movies' | 'shows' | 'episodes',
    page: number = 1,
    limit: number = 20
  ): Promise<TraktHistoryItem[]> {
    const path = type ? `/users/me/history/${type}` : '/users/me/history';
    return this.get<TraktHistoryItem[]>(
      path,
      { page: String(page), limit: String(limit), extended: 'full' },
      { auth: true, ttl: CacheTTL.SHORT }
    );
  }

  /**
   * Get playback progress (Continue Watching)
   * Returns items the user has started but not finished watching
   */
  async getPlaybackProgress(
    type?: 'movies' | 'episodes'
  ): Promise<TraktPlaybackItem[]> {
    const path = type ? `/sync/playback/${type}` : '/sync/playback';
    return this.get<TraktPlaybackItem[]>(
      path,
      { extended: 'full' },
      { auth: true, ttl: CacheTTL.SHORT }
    );
  }

  /**
   * Remove a playback progress item (removes from Continue Watching)
   */
  async removePlaybackProgress(playbackId: number): Promise<void> {
    await this.delete(`/sync/playback/${playbackId}`);
    await this.cache.invalidatePattern('trakt:auth:*playback*');
  }

  /**
   * Mark movie as watched
   */
  async markMovieWatched(
    movie: { ids: { tmdb?: number; imdb?: string } },
    watchedAt?: Date
  ): Promise<void> {
    await this.post(
      '/sync/history',
      {
        movies: [
          {
            ...movie,
            watched_at: watchedAt?.toISOString() || new Date().toISOString(),
          },
        ],
      },
      true
    );
    await this.cache.invalidatePattern('trakt:auth:*history*');
  }

  /**
   * Mark episode as watched
   */
  async markEpisodeWatched(
    show: { ids: { tmdb?: number; imdb?: string } },
    season: number,
    episode: number,
    watchedAt?: Date
  ): Promise<void> {
    await this.post(
      '/sync/history',
      {
        shows: [
          {
            ...show,
            seasons: [
              {
                number: season,
                episodes: [
                  {
                    number: episode,
                    watched_at: watchedAt?.toISOString() || new Date().toISOString(),
                  },
                ],
              },
            ],
          },
        ],
      },
      true
    );
    await this.cache.invalidatePattern('trakt:auth:*history*');
  }

  // ============================================
  // Collection
  // ============================================

  /**
   * Get user's collection
   */
  async getCollection(type: 'movies' | 'shows'): Promise<TraktCollectionItem[]> {
    return this.get<TraktCollectionItem[]>(
      `/users/me/collection/${type}`,
      { extended: 'full' },
      { auth: true, ttl: CacheTTL.DYNAMIC }
    );
  }

  // ============================================
  // Ratings
  // ============================================

  /**
   * Get user's ratings
   */
  async getRatings(type?: 'movies' | 'shows' | 'episodes'): Promise<TraktRatingItem[]> {
    const path = type ? `/users/me/ratings/${type}` : '/users/me/ratings';
    return this.get<TraktRatingItem[]>(path, { extended: 'full' }, {
      auth: true,
      ttl: CacheTTL.DYNAMIC,
    });
  }

  /**
   * Rate a movie
   */
  async rateMovie(
    movie: { ids: { tmdb?: number; imdb?: string } },
    rating: number
  ): Promise<void> {
    await this.post(
      '/sync/ratings',
      { movies: [{ ...movie, rating }] },
      true
    );
    await this.cache.invalidatePattern('trakt:auth:*ratings*');
  }

  /**
   * Rate a show
   */
  async rateShow(
    show: { ids: { tmdb?: number; imdb?: string } },
    rating: number
  ): Promise<void> {
    await this.post(
      '/sync/ratings',
      { shows: [{ ...show, rating }] },
      true
    );
    await this.cache.invalidatePattern('trakt:auth:*ratings*');
  }

  // ============================================
  // Metadata Lookup
  // ============================================

  /**
   * Get movie by ID
   */
  async getMovie(id: string | number): Promise<TraktMovie> {
    return this.get<TraktMovie>(`/movies/${id}`, { extended: 'full' }, {
      ttl: CacheTTL.TRENDING,
    });
  }

  /**
   * Get show by ID
   */
  async getShow(id: string | number): Promise<TraktShow> {
    return this.get<TraktShow>(`/shows/${id}`, { extended: 'full' }, {
      ttl: CacheTTL.TRENDING,
    });
  }

  /**
   * Get show seasons
   */
  async getSeasons(showId: string | number): Promise<TraktSeason[]> {
    return this.get<TraktSeason[]>(`/shows/${showId}/seasons`, { extended: 'full' }, {
      ttl: CacheTTL.DYNAMIC,
    });
  }

  /**
   * Get season episodes
   */
  async getSeasonEpisodes(
    showId: string | number,
    seasonNumber: number
  ): Promise<TraktEpisode[]> {
    return this.get<TraktEpisode[]>(
      `/shows/${showId}/seasons/${seasonNumber}`,
      { extended: 'full' },
      { ttl: CacheTTL.DYNAMIC }
    );
  }

  // ============================================
  // Search
  // ============================================

  /**
   * Search for movies
   */
  async searchMovies(
    query: string,
    page: number = 1,
    limit: number = 20
  ): Promise<{ movie: TraktMovie }[]> {
    return this.get<{ movie: TraktMovie }[]>(
      '/search/movie',
      { query, page: String(page), limit: String(limit), extended: 'full' },
      { ttl: CacheTTL.SHORT }
    );
  }

  /**
   * Search for shows
   */
  async searchShows(
    query: string,
    page: number = 1,
    limit: number = 20
  ): Promise<{ show: TraktShow }[]> {
    return this.get<{ show: TraktShow }[]>(
      '/search/show',
      { query, page: String(page), limit: String(limit), extended: 'full' },
      { ttl: CacheTTL.SHORT }
    );
  }

  /**
   * Lookup by IMDB ID
   */
  async lookupByImdb(
    imdbId: string,
    type: 'movie' | 'show'
  ): Promise<TraktMovie | TraktShow | null> {
    try {
      const results = await this.get<{ movie?: TraktMovie; show?: TraktShow }[]>(
        `/search/imdb/${imdbId}`,
        { type, extended: 'full' },
        { ttl: CacheTTL.STATIC }
      );
      if (results.length > 0) {
        return type === 'movie' ? results[0].movie! : results[0].show!;
      }
      return null;
    } catch {
      return null;
    }
  }

  /**
   * Lookup by TMDB ID
   */
  async lookupByTmdb(
    tmdbId: number,
    type: 'movie' | 'show'
  ): Promise<TraktMovie | TraktShow | null> {
    try {
      const results = await this.get<{ movie?: TraktMovie; show?: TraktShow }[]>(
        `/search/tmdb/${tmdbId}`,
        { type, extended: 'full' },
        { ttl: CacheTTL.STATIC }
      );
      if (results.length > 0) {
        return type === 'movie' ? results[0].movie! : results[0].show!;
      }
      return null;
    } catch {
      return null;
    }
  }

  // ============================================
  // Scrobbling (Real-time playback tracking)
  // ============================================

  /**
   * Start scrobbling a movie
   */
  async startScrobbleMovie(
    movie: { ids: { tmdb?: number; imdb?: string } },
    progress: number
  ): Promise<void> {
    if (!this.isAuthenticated()) return;
    await this.post(
      '/scrobble/start',
      { movie, progress },
      true
    );
  }

  /**
   * Start scrobbling an episode
   */
  async startScrobbleEpisode(
    show: { ids: { tmdb?: number; imdb?: string } },
    episode: { season: number; number: number },
    progress: number
  ): Promise<void> {
    if (!this.isAuthenticated()) return;
    await this.post(
      '/scrobble/start',
      { show, episode, progress },
      true
    );
  }

  /**
   * Pause scrobbling a movie
   */
  async pauseScrobbleMovie(
    movie: { ids: { tmdb?: number; imdb?: string } },
    progress: number
  ): Promise<void> {
    if (!this.isAuthenticated()) return;
    await this.post(
      '/scrobble/pause',
      { movie, progress },
      true
    );
  }

  /**
   * Pause scrobbling an episode
   */
  async pauseScrobbleEpisode(
    show: { ids: { tmdb?: number; imdb?: string } },
    episode: { season: number; number: number },
    progress: number
  ): Promise<void> {
    if (!this.isAuthenticated()) return;
    await this.post(
      '/scrobble/pause',
      { show, episode, progress },
      true
    );
  }

  /**
   * Stop scrobbling a movie
   */
  async stopScrobbleMovie(
    movie: { ids: { tmdb?: number; imdb?: string } },
    progress: number
  ): Promise<void> {
    if (!this.isAuthenticated()) return;
    await this.post(
      '/scrobble/stop',
      { movie, progress },
      true
    );
    // If progress >= 80%, Trakt will auto-mark as watched
    if (progress >= 80) {
      await this.cache.invalidatePattern('trakt:auth:*history*');
    }
  }

  /**
   * Stop scrobbling an episode
   */
  async stopScrobbleEpisode(
    show: { ids: { tmdb?: number; imdb?: string } },
    episode: { season: number; number: number },
    progress: number
  ): Promise<void> {
    if (!this.isAuthenticated()) return;
    await this.post(
      '/scrobble/stop',
      { show, episode, progress },
      true
    );
    // If progress >= 80%, Trakt will auto-mark as watched
    if (progress >= 80) {
      await this.cache.invalidatePattern('trakt:auth:*history*');
    }
  }

  // ============================================
  // Cache Management
  // ============================================

  /**
   * Invalidate all Trakt cache
   */
  async invalidateCache(): Promise<void> {
    await this.cache.invalidatePattern('trakt:*');
  }
}
