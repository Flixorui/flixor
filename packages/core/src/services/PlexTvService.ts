import type { ICache } from '../storage/ICache';
import { CacheTTL } from '../storage/ICache';
import type { PlexMediaItem, PlexMediaContainer } from '../models/plex';

const PLEX_TV_METADATA_URL = 'https://metadata.provider.plex.tv';

/**
 * Service for Plex.tv features (watchlist, discover, etc.)
 */
export class PlexTvService {
  private token: string;
  private clientId: string;
  private cache: ICache;

  constructor(options: { token: string; clientId: string; cache: ICache }) {
    this.token = options.token;
    this.clientId = options.clientId;
    this.cache = options.cache;
  }

  /**
   * Get standard Plex headers
   */
  private getHeaders(): Record<string, string> {
    return {
      Accept: 'application/json',
      'X-Plex-Token': this.token,
      'X-Plex-Client-Identifier': this.clientId,
      'X-Plex-Product': 'Flixor',
      'X-Plex-Version': '1.0.0',
      'X-Plex-Platform': 'Mobile',
    };
  }

  /**
   * Make a GET request to Plex.tv with caching
   */
  private async get<T>(
    url: string,
    ttl: number = CacheTTL.DYNAMIC
  ): Promise<T> {
    const cacheKey = `plextv:${url}`;

    // Check cache first
    if (ttl > 0) {
      const cached = await this.cache.get<T>(cacheKey);
      if (cached) {
        return cached;
      }
    }

    const response = await fetch(url, {
      method: 'GET',
      headers: this.getHeaders(),
    });

    if (!response.ok) {
      throw new Error(`Plex.tv API error: ${response.status}`);
    }

    const data = await response.json();

    // Cache the response
    if (ttl > 0) {
      await this.cache.set(cacheKey, data, ttl);
    }

    return data;
  }

  // ============================================
  // Watchlist
  // ============================================

  /**
   * Get user's watchlist
   */
  async getWatchlist(): Promise<PlexMediaItem[]> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `${PLEX_TV_METADATA_URL}/library/sections/watchlist/all`,
      CacheTTL.DYNAMIC
    );
    return data.MediaContainer?.Metadata || [];
  }

  /**
   * Add item to watchlist
   */
  async addToWatchlist(ratingKey: string): Promise<void> {
    const response = await fetch(
      `${PLEX_TV_METADATA_URL}/library/sections/watchlist/items/${ratingKey}`,
      {
        method: 'PUT',
        headers: this.getHeaders(),
      }
    );

    if (!response.ok) {
      throw new Error(`Failed to add to watchlist: ${response.status}`);
    }

    // Invalidate watchlist cache
    await this.cache.invalidatePattern('plextv:*watchlist*');
  }

  /**
   * Remove item from watchlist
   */
  async removeFromWatchlist(ratingKey: string): Promise<void> {
    const response = await fetch(
      `${PLEX_TV_METADATA_URL}/library/sections/watchlist/items/${ratingKey}`,
      {
        method: 'DELETE',
        headers: this.getHeaders(),
      }
    );

    if (!response.ok) {
      throw new Error(`Failed to remove from watchlist: ${response.status}`);
    }

    // Invalidate watchlist cache
    await this.cache.invalidatePattern('plextv:*watchlist*');
  }

  /**
   * Check if item is in watchlist
   */
  async isInWatchlist(ratingKey: string): Promise<boolean> {
    try {
      const watchlist = await this.getWatchlist();
      return watchlist.some((item) => item.ratingKey === ratingKey);
    } catch {
      return false;
    }
  }

  // ============================================
  // Discover
  // ============================================

  /**
   * Get discover recommendations
   */
  async getDiscover(): Promise<PlexMediaItem[]> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `${PLEX_TV_METADATA_URL}/library/sections/discover/all`,
      CacheTTL.TRENDING
    );
    return data.MediaContainer?.Metadata || [];
  }

  /**
   * Get trending items
   */
  async getTrending(): Promise<PlexMediaItem[]> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `${PLEX_TV_METADATA_URL}/library/sections/trending/all`,
      CacheTTL.TRENDING
    );
    return data.MediaContainer?.Metadata || [];
  }

  // ============================================
  // Search
  // ============================================

  /**
   * Search Plex.tv (global search across all content)
   */
  async search(query: string): Promise<PlexMediaItem[]> {
    const params = new URLSearchParams({
      query,
      'X-Plex-Token': this.token,
    });

    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `${PLEX_TV_METADATA_URL}/library/search?${params.toString()}`,
      CacheTTL.SHORT
    );
    return data.MediaContainer?.Metadata || [];
  }

  // ============================================
  // Metadata Lookup
  // ============================================

  /**
   * Get metadata by GUID (TMDB, IMDB, etc.)
   */
  async getByGuid(guid: string): Promise<PlexMediaItem | null> {
    try {
      const params = new URLSearchParams({
        guid,
        'X-Plex-Token': this.token,
      });

      const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
        `${PLEX_TV_METADATA_URL}/library/metadata/matches?${params.toString()}`,
        CacheTTL.TRENDING
      );
      return data.MediaContainer?.Metadata?.[0] || null;
    } catch {
      return null;
    }
  }

  /**
   * Get Plex.tv metadata for a specific item
   */
  async getMetadata(ratingKey: string): Promise<PlexMediaItem | null> {
    try {
      const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
        `${PLEX_TV_METADATA_URL}/library/metadata/${ratingKey}`,
        CacheTTL.TRENDING
      );
      return data.MediaContainer?.Metadata?.[0] || null;
    } catch {
      return null;
    }
  }

  // ============================================
  // Cache Management
  // ============================================

  /**
   * Invalidate all Plex.tv cache
   */
  async invalidateCache(): Promise<void> {
    await this.cache.invalidatePattern('plextv:*');
  }
}
