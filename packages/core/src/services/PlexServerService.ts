import type { ICache } from '../storage/ICache';
import { CacheTTL } from '../storage/ICache';
import type {
  PlexLibrary,
  PlexMediaItem,
  PlexMarker,
  PlexLibraryOptions,
  PlexMediaContainer,
} from '../models/plex';

/**
 * Service for communicating with a Plex Media Server
 */
export class PlexServerService {
  private baseUrl: string;
  private token: string;
  private clientId: string;
  private cache: ICache;

  constructor(options: {
    baseUrl: string;
    token: string;
    clientId: string;
    cache: ICache;
  }) {
    this.baseUrl = options.baseUrl.replace(/\/$/, '');
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
      'X-Plex-Device': 'Mobile',
      'X-Plex-Device-Name': 'Flixor Mobile',
    };
  }

  /**
   * Make a GET request to the Plex server with caching
   */
  private async get<T>(
    path: string,
    params?: Record<string, string>,
    ttl: number = CacheTTL.DYNAMIC,
    extraHeaders?: Record<string, string>
  ): Promise<T> {
    const queryString = params
      ? '?' + new URLSearchParams(params).toString()
      : '';
    const fullPath = `${path}${queryString}`;

    // Include extra headers in cache key for pagination
    const headersSuffix = extraHeaders
      ? ':' + Object.entries(extraHeaders).map(([k, v]) => `${k}=${v}`).join('&')
      : '';
    const cacheKey = `plex:${this.baseUrl}:${fullPath}${headersSuffix}`;

    // Check cache first
    if (ttl > 0) {
      const cached = await this.cache.get<T>(cacheKey);
      if (cached) {
        return cached;
      }
    }

    const url = `${this.baseUrl}${fullPath}`;
    console.log('[PlexServerService] GET:', url);
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        ...this.getHeaders(),
        ...extraHeaders,
      },
    });

    if (!response.ok) {
      throw new Error(`Plex API error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();

    // Cache the response
    if (ttl > 0) {
      await this.cache.set(cacheKey, data, ttl);
    }

    return data;
  }

  // ============================================
  // Libraries
  // ============================================

  /**
   * Get all libraries
   */
  async getLibraries(): Promise<PlexLibrary[]> {
    const data = await this.get<PlexMediaContainer<PlexLibrary>>(
      '/library/sections',
      undefined,
      CacheTTL.TRENDING
    );
    return data.MediaContainer?.Directory || [];
  }

  /**
   * Get items in a library with pagination
   */
  async getLibraryItems(
    libraryKey: string,
    options?: PlexLibraryOptions
  ): Promise<PlexMediaItem[]> {
    const params: Record<string, string> = {};

    if (options?.type) params.type = String(options.type);
    if (options?.sort) params.sort = options.sort;
    if (options?.filter) {
      Object.entries(options.filter).forEach(([key, value]) => {
        params[key] = value;
      });
    }

    // Pagination via query parameters
    if (options?.limit !== undefined) {
      params['X-Plex-Container-Size'] = String(options.limit);
    }
    if (options?.offset !== undefined) {
      params['X-Plex-Container-Start'] = String(options.offset);
    }

    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `/library/sections/${libraryKey}/all`,
      params,
      CacheTTL.SHORT
    );
    return data.MediaContainer?.Metadata || [];
  }

  // ============================================
  // Metadata
  // ============================================

  /**
   * Get metadata for a specific item
   */
  async getMetadata(ratingKey: string): Promise<PlexMediaItem | null> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `/library/metadata/${ratingKey}`,
      undefined,
      CacheTTL.TRENDING
    );
    return data.MediaContainer?.Metadata?.[0] || null;
  }

  /**
   * Get children (seasons for show, episodes for season)
   */
  async getChildren(ratingKey: string): Promise<PlexMediaItem[]> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `/library/metadata/${ratingKey}/children`,
      undefined,
      CacheTTL.DYNAMIC
    );
    return data.MediaContainer?.Metadata || [];
  }

  /**
   * Get related items
   */
  async getRelated(ratingKey: string): Promise<PlexMediaItem[]> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `/library/metadata/${ratingKey}/related`,
      undefined,
      CacheTTL.TRENDING
    );
    return data.MediaContainer?.Metadata || [];
  }

  // ============================================
  // Hubs (Continue Watching, On Deck, etc.)
  // ============================================

  /**
   * Get continue watching items
   */
  async getContinueWatching(): Promise<PlexMediaItem[]> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      '/hubs/continueWatching/items',
      undefined,
      CacheTTL.SHORT
    );
    return data.MediaContainer?.Metadata || [];
  }

  /**
   * Get on deck items
   */
  async getOnDeck(): Promise<PlexMediaItem[]> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      '/library/onDeck',
      undefined,
      CacheTTL.SHORT
    );
    return data.MediaContainer?.Metadata || [];
  }

  /**
   * Get recently added items
   */
  async getRecentlyAdded(libraryKey?: string): Promise<PlexMediaItem[]> {
    const path = libraryKey
      ? `/library/sections/${libraryKey}/recentlyAdded`
      : '/library/recentlyAdded';

    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      path,
      undefined,
      CacheTTL.DYNAMIC
    );
    return data.MediaContainer?.Metadata || [];
  }

  // ============================================
  // Search
  // ============================================

  /**
   * Search the library - searches each library section directly
   */
  async search(query: string, type?: number): Promise<PlexMediaItem[]> {
    console.log(`[PlexServerService] Searching for: "${query}" type=${type}`);
    const results: PlexMediaItem[] = [];

    // Get all libraries and search each one
    try {
      const libraries = await this.getLibraries();

      // Filter libraries by type if specified
      const targetLibraries = libraries.filter((lib) => {
        if (!type) return true;
        if (type === 1) return lib.type === 'movie';
        if (type === 2) return lib.type === 'show';
        return true;
      });

      // Search each library section
      for (const lib of targetLibraries) {
        try {
          // Use section-specific search endpoint
          const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
            `/library/sections/${lib.key}/search`,
            { query, type: type ? String(type) : undefined } as Record<string, string>,
            CacheTTL.SHORT
          );
          const items = data.MediaContainer?.Metadata || [];
          console.log(`[PlexServerService] Section ${lib.key} search returned ${items.length} results`);
          results.push(...items);
        } catch (e) {
          // Try alternative: get all items and filter by title
          try {
            const allItems = await this.get<PlexMediaContainer<PlexMediaItem>>(
              `/library/sections/${lib.key}/all`,
              { title: query },
              CacheTTL.SHORT
            );
            const items = allItems.MediaContainer?.Metadata || [];
            console.log(`[PlexServerService] Section ${lib.key} title filter returned ${items.length} results`);
            results.push(...items);
          } catch {}
        }
      }

      if (results.length > 0) {
        console.log(`[PlexServerService] Total search results: ${results.length}`);
        return results;
      }
    } catch (e) {
      console.log('[PlexServerService] Section search failed:', e);
    }

    // Last resort: global library search
    try {
      const params: Record<string, string> = { query };
      if (type) params.type = String(type);

      const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
        '/library/search',
        params,
        CacheTTL.SHORT
      );
      const items = data.MediaContainer?.Metadata || [];
      console.log(`[PlexServerService] Global search returned ${items.length} results`);
      return items;
    } catch (e) {
      console.log('[PlexServerService] Global search failed:', e);
      return [];
    }
  }

  /**
   * Find items by GUID (for TMDB/IMDB matching)
   * Searches across all library sections
   */
  async findByGuid(guid: string, type?: number): Promise<PlexMediaItem[]> {
    const results: PlexMediaItem[] = [];

    // Get all libraries
    const libraries = await this.getLibraries();

    // Filter libraries by type if specified
    const targetLibraries = libraries.filter((lib) => {
      if (!type) return true;
      // type 1 = movie, type 2 = show
      if (type === 1) return lib.type === 'movie';
      if (type === 2) return lib.type === 'show';
      return true;
    });

    // Search each library for the GUID
    for (const lib of targetLibraries) {
      try {
        const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
          `/library/sections/${lib.key}/all`,
          { guid },
          CacheTTL.SHORT
        );
        const items = data.MediaContainer?.Metadata || [];
        results.push(...items);
      } catch {
        // Continue to next library on error
      }
    }

    return results;
  }

  // ============================================
  // Markers (Skip Intro/Credits)
  // ============================================

  /**
   * Get markers for an item (intro/credits skip points)
   */
  async getMarkers(ratingKey: string): Promise<PlexMarker[]> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `/library/metadata/${ratingKey}`,
      { includeMarkers: '1' },
      CacheTTL.TRENDING
    );
    return data.MediaContainer?.Metadata?.[0]?.Marker || [];
  }

  // ============================================
  // Playback
  // ============================================

  /**
   * Get direct stream URL for playback
   */
  async getStreamUrl(ratingKey: string): Promise<string> {
    const metadata = await this.getMetadata(ratingKey);
    if (!metadata) {
      throw new Error('Metadata not found');
    }

    const part = metadata.Media?.[0]?.Part?.[0];
    if (!part?.key) {
      throw new Error('No playable media found');
    }

    return `${this.baseUrl}${part.key}?X-Plex-Token=${this.token}`;
  }

  /**
   * Get transcode URL for HLS playback
   * Returns both the start URL and session URL along with the session ID
   */
  getTranscodeUrl(
    ratingKey: string,
    options?: {
      maxVideoBitrate?: number;
      videoResolution?: string;
      protocol?: 'hls' | 'dash';
      sessionId?: string;
      directStream?: boolean;
    }
  ): { url: string; startUrl: string; sessionUrl: string; sessionId: string } {
    const {
      maxVideoBitrate = 20000,
      videoResolution = '1920x1080',
      protocol = 'hls',
      sessionId = Math.random().toString(36).substring(2, 15),
      directStream = false,
    } = options || {};

    const params = new URLSearchParams({
      hasMDE: '1',
      path: `/library/metadata/${ratingKey}`,
      mediaIndex: '0',
      partIndex: '0',
      protocol,
      fastSeek: '1',
      directPlay: '0',
      directStream: directStream ? '1' : '0',
      directStreamAudio: '0',
      videoQuality: '100',
      videoResolution,
      maxVideoBitrate: String(maxVideoBitrate),
      subtitleSize: '100',
      audioBoost: '100',
      location: 'lan',
      addDebugOverlay: '0',
      autoAdjustQuality: '0',
      mediaBufferSize: '102400',
      session: sessionId,
      copyts: '1',
      'X-Plex-Token': this.token,
      'X-Plex-Client-Identifier': sessionId,
      'X-Plex-Product': 'Flixor Mobile',
      'X-Plex-Platform': 'iOS',
      'X-Plex-Device': 'iPhone',
    });

    const startUrl = `${this.baseUrl}/video/:/transcode/universal/start.m3u8?${params.toString()}`;
    const sessionUrl = `${this.baseUrl}/video/:/transcode/universal/session/${sessionId}/base/index.m3u8?X-Plex-Token=${this.token}`;

    return {
      url: sessionUrl, // Default to session URL (the working one)
      startUrl,
      sessionUrl,
      sessionId,
    };
  }

  /**
   * Start a transcode session (must be called before using sessionUrl)
   */
  async startTranscodeSession(startUrl: string): Promise<void> {
    try {
      await fetch(startUrl);
      console.log('[PlexServerService] Transcode session started');
    } catch (e) {
      console.error('[PlexServerService] Failed to start transcode session:', e);
      throw e;
    }
  }

  /**
   * Update playback timeline (progress tracking)
   */
  async updateTimeline(
    ratingKey: string,
    state: 'playing' | 'paused' | 'stopped',
    timeMs: number,
    durationMs: number
  ): Promise<void> {
    const params = new URLSearchParams({
      ratingKey,
      key: `/library/metadata/${ratingKey}`,
      state,
      time: String(timeMs),
      duration: String(durationMs),
      'X-Plex-Token': this.token,
      'X-Plex-Client-Identifier': this.clientId,
      'X-Plex-Product': 'Flixor',
      'X-Plex-Device': 'Mobile',
    });

    const url = `${this.baseUrl}/:/timeline?${params.toString()}`;

    try {
      await fetch(url, {
        method: 'GET',
        headers: this.getHeaders(),
      });
    } catch {
      // Timeline updates are best-effort
    }
  }

  /**
   * Stop transcode session
   */
  async stopTranscode(sessionId: string): Promise<void> {
    try {
      await fetch(
        `${this.baseUrl}/video/:/transcode/universal/stop?session=${sessionId}&X-Plex-Token=${this.token}`,
        { method: 'GET' }
      );
    } catch {
      // Best-effort
    }
  }

  // ============================================
  // Images
  // ============================================

  /**
   * Get image URL
   */
  getImageUrl(path: string | null | undefined, width?: number): string {
    if (!path) return '';

    const params = new URLSearchParams({
      'X-Plex-Token': this.token,
    });

    if (width) {
      params.set('width', String(width));
    }

    // Handle absolute URLs (TMDB images)
    if (path.startsWith('http')) {
      return path;
    }

    return `${this.baseUrl}${path}?${params.toString()}`;
  }

  /**
   * Get photo transcoded URL (resized)
   */
  getPhotoTranscodeUrl(
    path: string,
    width: number,
    height: number
  ): string {
    const params = new URLSearchParams({
      url: path,
      width: String(width),
      height: String(height),
      minSize: '1',
      upscale: '1',
      'X-Plex-Token': this.token,
    });

    return `${this.baseUrl}/photo/:/transcode?${params.toString()}`;
  }

  // ============================================
  // Cache Management
  // ============================================

  /**
   * Invalidate cache for this server
   */
  async invalidateCache(): Promise<void> {
    await this.cache.invalidatePattern(`plex:${this.baseUrl}:*`);
  }

  /**
   * Invalidate cache for a specific item
   */
  async invalidateItem(ratingKey: string): Promise<void> {
    await this.cache.invalidatePattern(`plex:${this.baseUrl}:/library/metadata/${ratingKey}*`);
  }
}
