import type { ICache } from '../storage/ICache';
import { CacheTTL } from '../storage/ICache';
import type {
  PlexLibrary,
  PlexMediaItem,
  PlexMarker,
  PlexLibraryOptions,
  PlexMediaContainer,
  PlexUltraBlurColors,
  PlexUltraBlurResponse,
  ContinueWatchingResult,
} from '../models/plex';
import { EditionService } from './EditionService';

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

    // Include extended media info for edition display
    params.includeGuids = '1';
    params.includeExtras = '1';
    params.includeEditions = '1';

    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `/library/sections/${libraryKey}/all`,
      params,
      CacheTTL.SHORT
    );
    return this.applyEditions(data.MediaContainer?.Metadata || []);
  }

  // ============================================
  // Metadata
  // ============================================

  /**
   * Get metadata for a specific item
   */
  async getMetadata(ratingKey: string, includeGuids = false): Promise<PlexMediaItem | null> {
    const params: Record<string, string> = {
      includeEditions: '1', // Include edition information
    };
    if (includeGuids) {
      params.includeGuids = '1';
    }
    
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `/library/metadata/${ratingKey}`,
      params,
      CacheTTL.TRENDING
    );
    const metadata = data.MediaContainer?.Metadata?.[0] || null;

    if (metadata) {
      this.applyEdition(metadata);
    }

    return metadata;
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
    return this.applyEditions(data.MediaContainer?.Metadata || []);
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
    return this.applyEditions(data.MediaContainer?.Metadata || []);
  }

  // ============================================
  // Hubs (Continue Watching, On Deck, etc.)
  // ============================================

  /**
   * Get continue watching items (deduplicated by GUID)
   * Returns items grouped by TMDB/IMDB GUID, keeping only the most recently watched version
   */
  async getContinueWatching(): Promise<ContinueWatchingResult> {
    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      '/hubs/continueWatching/items',
      { includeGuids: '1' }, // Include external GUIDs (TMDB, IMDB, etc.)
      CacheTTL.SHORT
    );
    const items = this.applyEditions(data.MediaContainer?.Metadata || []);
    console.log('[PlexServerService] getContinueWatching raw items:', items.length);
    const result = this.deduplicateContinueWatching(items);
    return result;
  }

  /**
   * Deduplicate continue watching items by GUID
   * Groups items by their TMDB/IMDB GUID and keeps the most recently watched version
   */
  private deduplicateContinueWatching(items: PlexMediaItem[]): ContinueWatchingResult {
    const guidMap = new Map<string, PlexMediaItem>();
    const guidCount = new Map<string, number>();

    for (const item of items) {
      const guid = this.extractPrimaryGuid(item.Guid);

      // If no GUID, use ratingKey as fallback (can't dedupe without GUID)
      if (!guid) {
        guidMap.set(item.ratingKey, item);
        continue;
      }

      // Count items per GUID to track duplicates
      guidCount.set(guid, (guidCount.get(guid) || 0) + 1);

      const existing = guidMap.get(guid);
      // Keep the most recently watched version (highest lastViewedAt)
      if (!existing || (item.lastViewedAt || 0) > (existing.lastViewedAt || 0)) {
        guidMap.set(guid, item);
      }
    }

    // Identify which final items had duplicates (multiple editions)
    const itemsWithMultipleVersions = new Set<string>();
    for (const [guid, item] of guidMap.entries()) {
      if ((guidCount.get(guid) || 0) > 1) {
        itemsWithMultipleVersions.add(item.ratingKey);
      }
    }

    return {
      items: Array.from(guidMap.values()),
      itemsWithMultipleVersions,
    };
  }

  /**
   * Extract primary GUID (TMDB or IMDB) from Guid array
   */
  private extractPrimaryGuid(guids?: Array<{ id: string }>): string | null {
    if (!guids || guids.length === 0) return null;

    // Prefer TMDB, then IMDB
    const tmdb = guids.find(g => g.id.startsWith('tmdb://'));
    if (tmdb) return tmdb.id;

    const imdb = guids.find(g => g.id.startsWith('imdb://'));
    if (imdb) return imdb.id;

    return guids[0]?.id || null;
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
    return this.applyEditions(data.MediaContainer?.Metadata || []);
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
    return this.applyEditions(data.MediaContainer?.Metadata || []);
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
            { query, type: type ? String(type) : undefined, includeEditions: '1' } as Record<string, string>,
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
        return this.applyEditions(results);
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
      return this.applyEditions(items);
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

    return this.applyEditions(results);
  }

  // ============================================
  // Collections
  // ============================================

  /**
   * Get all collections in a library section
   */
  async getCollections(libraryKey: string): Promise<PlexMediaItem[]> {
    try {
      const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
        `/library/sections/${libraryKey}/collections`,
        {},
        CacheTTL.TRENDING
      );
      return this.applyEditions(data.MediaContainer?.Metadata || []);
    } catch (e) {
      console.log('[PlexServerService] getCollections error:', e);
      return [];
    }
  }

  /**
   * Get all collections across all libraries
   */
  async getAllCollections(type?: 'movie' | 'show'): Promise<PlexMediaItem[]> {
    const libraries = await this.getLibraries();
    const targetLibraries = libraries.filter((lib) => {
      if (!type) return true;
      return lib.type === type;
    });

    const allCollections: PlexMediaItem[] = [];

    for (const lib of targetLibraries) {
      try {
        const collections = await this.getCollections(lib.key);
        allCollections.push(...collections);
      } catch {
        // Continue on error
      }
    }

    return allCollections;
  }

  /**
   * Get items in a collection
   */
  async getCollectionItems(
    collectionRatingKey: string,
    options?: {
      start?: number;
      size?: number;
    }
  ): Promise<PlexMediaItem[]> {
    const params: Record<string, string> = {};

    if (options?.start !== undefined) params['X-Plex-Container-Start'] = String(options.start);
    if (options?.size !== undefined) params['X-Plex-Container-Size'] = String(options.size);

    try {
      const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
        `/library/collections/${collectionRatingKey}/children`,
        params,
        CacheTTL.DYNAMIC
      );
      return this.applyEditions(data.MediaContainer?.Metadata || []);
    } catch (e) {
      console.log('[PlexServerService] getCollectionItems error:', e);
      return [];
    }
  }

  // ============================================
  // Genres / Filters
  // ============================================

  /**
   * Get available genres for a library section
   */
  async getGenres(libraryKey: string): Promise<Array<{ key: string; title: string }>> {
    try {
      const data = await this.get<PlexMediaContainer<{ key: string; title: string }>>(
        `/library/sections/${libraryKey}/genre`,
        {},
        CacheTTL.TRENDING
      );
      return data.MediaContainer?.Directory || [];
    } catch (e) {
      console.log('[PlexServerService] getGenres error:', e);
      return [];
    }
  }

  /**
   * Get all genres across all libraries of a given type
   */
  async getAllGenres(type?: 'movie' | 'show'): Promise<Array<{ key: string; title: string }>> {
    const libraries = await this.getLibraries();
    const targetLibraries = libraries.filter((lib) => {
      if (!type) return true;
      return lib.type === type;
    });

    const allGenres = new Map<string, { key: string; title: string }>();

    for (const lib of targetLibraries) {
      try {
        const genres = await this.getGenres(lib.key);
        for (const genre of genres) {
          // Use title as key for deduplication
          if (!allGenres.has(genre.title)) {
            allGenres.set(genre.title, genre);
          }
        }
      } catch {
        // Continue on error
      }
    }

    // Sort genres alphabetically
    return Array.from(allGenres.values()).sort((a, b) => a.title.localeCompare(b.title));
  }

  /**
   * Get items by genre
   */
  async getItemsByGenre(
    libraryKey: string,
    genreKey: string,
    options?: {
      start?: number;
      size?: number;
      sort?: string;
    }
  ): Promise<PlexMediaItem[]> {
    const params: Record<string, string> = {
      genre: genreKey,
    };

    if (options?.sort) params.sort = options.sort;
    if (options?.start !== undefined) params['X-Plex-Container-Start'] = String(options.start);
    if (options?.size !== undefined) params['X-Plex-Container-Size'] = String(options.size);

    const data = await this.get<PlexMediaContainer<PlexMediaItem>>(
      `/library/sections/${libraryKey}/all`,
      params,
      CacheTTL.DYNAMIC
    );
    return this.applyEditions(data.MediaContainer?.Metadata || []);
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
   * @param ratingKey - The Plex rating key
   * @param mediaIndex - Index of the Media array (for multi-version support), defaults to 0
   */
  async getStreamUrl(ratingKey: string, mediaIndex: number = 0): Promise<string> {
    console.log('[PlexServerService] getStreamUrl called:', { ratingKey, mediaIndex });
    const metadata = await this.getMetadata(ratingKey);
    if (!metadata) {
      throw new Error('Metadata not found');
    }

    console.log('[PlexServerService] getStreamUrl - Media array length:', metadata.Media?.length);
    const part = metadata.Media?.[mediaIndex]?.Part?.[0];
    console.log('[PlexServerService] getStreamUrl - Selected part:', { mediaIndex, partId: part?.id, partKey: part?.key });
    if (!part?.key) {
      throw new Error('No playable media found');
    }

    const url = `${this.baseUrl}${part.key}?X-Plex-Token=${this.token}`;
    console.log('[PlexServerService] getStreamUrl - Final URL part ID:', part.id);
    return url;
  }

  /**
   * Get transcode URL for HLS playback
   * Returns both the start URL and session URL along with the session ID
   * @param ratingKey - The Plex rating key
   * @param options.mediaIndex - Index of Media array for multi-version support (defaults to 0)
   */
  getTranscodeUrl(
    ratingKey: string,
    options?: {
      maxVideoBitrate?: number;
      videoResolution?: string;
      protocol?: 'hls' | 'dash';
      sessionId?: string;
      directStream?: boolean;
      audioStreamID?: string;
      subtitleStreamID?: string;
      offset?: number; // Start offset in ms for seeking
      mediaIndex?: number; // Index of Media array (for multi-version support)
    }
  ): { url: string; startUrl: string; sessionUrl: string; sessionId: string } {
    // Always generate a fresh session ID to avoid Plex caching issues
    const freshSessionId = `${Date.now()}-${Math.random().toString(36).substring(2, 10)}`;

    const {
      maxVideoBitrate = 20000,
      videoResolution = '1920x1080',
      protocol = 'hls',
      sessionId = freshSessionId,
      directStream = false,
      audioStreamID,
      subtitleStreamID,
      offset,
      mediaIndex = 0,
    } = options || {};

    console.log('[PlexServerService] getTranscodeUrl called with:', {
      ratingKey,
      maxVideoBitrate,
      videoResolution,
      audioStreamID,
      subtitleStreamID,
      sessionId,
      mediaIndex,
    });

    const params = new URLSearchParams({
      hasMDE: '1',
      path: `/library/metadata/${ratingKey}`,
      mediaIndex: String(mediaIndex),
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
      'X-Plex-Client-Identifier': this.clientId,
      'X-Plex-Product': 'Flixor Mobile',
      'X-Plex-Platform': 'iOS',
      'X-Plex-Device': 'iPhone',
    });

    // Add audio stream selection if specified
    if (audioStreamID) {
      params.set('audioStreamID', audioStreamID);
      console.log('[PlexServerService] Added audioStreamID to transcode URL:', audioStreamID);
    }

    // Handle subtitle stream selection
    // Special case: 'burn' = just burn subtitles using Plex's default selection
    // '0' = disable subtitles
    // Other values = enable that specific subtitle track
    if (subtitleStreamID !== undefined) {
      if (subtitleStreamID === 'burn') {
        // Just enable subtitle burning, let Plex use the default selected subtitle
        params.set('subtitles', 'burn');
        console.log('[PlexServerService] Added subtitles=burn (using Plex default subtitle)');
      } else if (subtitleStreamID === '0') {
        // Explicitly disable subtitles
        params.set('subtitleStreamID', '0');
        console.log('[PlexServerService] Subtitle disabled (ID=0)');
      } else {
        // Enable specific subtitle track and burn it
        params.set('subtitleStreamID', subtitleStreamID);
        params.set('subtitles', 'burn');
        console.log('[PlexServerService] Added subtitleStreamID:', subtitleStreamID, 'with burn');
      }
    }

    // Add offset for seeking on transcode restart
    if (offset && offset > 0) {
      params.set('offset', String(Math.floor(offset / 1000))); // Plex uses seconds
    }

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
   * Make a transcode decision - tells Plex which streams to use
   * This should be called BEFORE requesting the transcode stream
   */
  async makeTranscodeDecision(
    ratingKey: string,
    options?: {
      audioStreamID?: string;
      subtitleStreamID?: string;
      mediaIndex?: number; // Index of Media array (for multi-version support)
    }
  ): Promise<void> {
    const mediaIndex = options?.mediaIndex ?? 0;
    const params = new URLSearchParams({
      path: `/library/metadata/${ratingKey}`,
      mediaIndex: String(mediaIndex),
      partIndex: '0',
      protocol: 'hls',
      directPlay: '0',
      directStream: '0',
      directStreamAudio: '0',
      'X-Plex-Token': this.token,
      'X-Plex-Client-Identifier': this.clientId,
      'X-Plex-Product': 'Flixor Mobile',
      'X-Plex-Platform': 'iOS',
    });

    if (options?.audioStreamID) {
      params.set('audioStreamID', options.audioStreamID);
    }
    if (options?.subtitleStreamID) {
      params.set('subtitleStreamID', options.subtitleStreamID);
      if (options.subtitleStreamID !== '0') {
        params.set('subtitles', 'burn');
      }
    }

    const url = `${this.baseUrl}/video/:/transcode/universal/decision?${params.toString()}`;
    console.log('[PlexServerService] Making transcode decision:', url.substring(0, 200) + '...');

    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: this.getHeaders(),
      });

      if (!response.ok) {
        console.warn('[PlexServerService] Decision API returned:', response.status);
      } else {
        console.log('[PlexServerService] Transcode decision made successfully');
      }
    } catch (e) {
      console.warn('[PlexServerService] Failed to make transcode decision:', e);
    }
  }

  /**
   * Start a transcode session (must be called before using sessionUrl)
   */
  async startTranscodeSession(startUrl: string): Promise<void> {
    try {
      console.log('[PlexServerService] Starting transcode session...');
      console.log('[PlexServerService] URL:', startUrl.substring(0, 200) + '...');

      const response = await fetch(startUrl, {
        headers: this.getHeaders(),
      });

      console.log('[PlexServerService] Transcode response status:', response.status);

      if (!response.ok) {
        const text = await response.text();
        console.error('[PlexServerService] Transcode error response:', text.substring(0, 500));
        throw new Error(`Transcode failed with status ${response.status}`);
      }

      console.log('[PlexServerService] Transcode session started successfully');
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

  /**
   * Change audio/subtitle stream selection for a media part
   * This tells Plex which streams to use - requires player to reload stream
   */
  async setStreamSelection(
    partId: string,
    options: {
      audioStreamID?: string;
      subtitleStreamID?: string; // Stream ID to enable, undefined to disable
    }
  ): Promise<void> {
    const params = new URLSearchParams({
      'X-Plex-Token': this.token,
      'allParts': '1', // Apply to all parts of the media
    });

    if (options.audioStreamID) {
      params.set('audioStreamID', options.audioStreamID);
      console.log('[PlexServerService] setStreamSelection - audioStreamID:', options.audioStreamID);
    }

    // Only set subtitleStreamID if it's a valid stream ID (not undefined)
    // To disable subtitles, we simply don't set this parameter
    if (options.subtitleStreamID) {
      params.set('subtitleStreamID', options.subtitleStreamID);
      console.log('[PlexServerService] setStreamSelection - subtitleStreamID:', options.subtitleStreamID);
    } else {
      console.log('[PlexServerService] setStreamSelection - subtitles disabled (no ID)');
    }

    const url = `${this.baseUrl}/library/parts/${partId}?${params.toString()}`;
    console.log('[PlexServerService] Setting stream selection:', url);

    try {
      const response = await fetch(url, {
        method: 'PUT',
        headers: this.getHeaders(),
      });

      if (!response.ok) {
        throw new Error(`Failed to set stream selection: ${response.status}`);
      }

      console.log('[PlexServerService] Stream selection updated successfully');
    } catch (e) {
      console.error('[PlexServerService] Failed to set stream selection:', e);
      throw e;
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
  // UltraBlur Colors
  // ============================================

  /**
   * Get UltraBlur colors from an image URL
   * Returns gradient colors extracted from the image
   */
  async getUltraBlurColors(imageUrl: string): Promise<PlexUltraBlurColors | null> {
    try {
      // Create a cache key based on the image URL
      const cacheKey = `ultrablur:${imageUrl}`;

      // Check cache first
      const cached = await this.cache.get<PlexUltraBlurColors>(cacheKey);
      if (cached) {
        return cached;
      }

      const params = new URLSearchParams({
        url: imageUrl,
        'X-Plex-Token': this.token,
      });

      const url = `${this.baseUrl}/services/ultrablur/colors?${params.toString()}`;

      const response = await fetch(url, {
        method: 'GET',
        headers: {
          Accept: 'application/json',
          'X-Plex-Client-Identifier': this.clientId,
        },
      });

      if (!response.ok) {
        return null;
      }

      const data: PlexUltraBlurResponse = await response.json();
      const colors = data.MediaContainer?.UltraBlurColors?.[0];

      // Cache the result (24 hours - colors don't change for a given image)
      if (colors) {
        await this.cache.set(cacheKey, colors, CacheTTL.STATIC);
      }

      return colors || null;
    } catch (e) {
      return null;
    }
  }

  /**
   * Get UltraBlur gradient image URL
   * Generates a gradient image from the given colors
   */
  getUltraBlurImageUrl(colors: PlexUltraBlurColors, noise: number = 1): string {
    const params = new URLSearchParams({
      topLeft: colors.topLeft,
      topRight: colors.topRight,
      bottomRight: colors.bottomRight,
      bottomLeft: colors.bottomLeft,
      noise: String(noise),
      'X-Plex-Token': this.token,
    });

    return `${this.baseUrl}/services/ultrablur/image?${params.toString()}`;
  }

  // ============================================
  // Generic Directory Fetch
  // ============================================

  /**
   * Fetch any Plex directory path and return the MediaContainer
   * Useful for browsing arbitrary paths like genres, hubs, etc.
   */
  async fetchDirectory(path: string): Promise<{
    Metadata?: PlexMediaItem[];
    Directory?: any[];
    size?: number;
    totalSize?: number;
    offset?: number;
  }> {
    // Ensure path starts with /
    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    const separator = normalizedPath.includes('?') ? '&' : '?';
    const url = `${this.baseUrl}${normalizedPath}${separator}X-Plex-Token=${this.token}`;

    const response = await fetch(url, {
      headers: { Accept: 'application/json' },
    });

    if (!response.ok) {
      throw new Error(`Plex fetchDirectory failed: ${response.status}`);
    }

    const data = await response.json();
    return data.MediaContainer || {};
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

  // ============================================
  // Edition Extraction
  // ============================================

  /**
   * Apply edition extraction to a single item
   */
  private applyEdition(item: PlexMediaItem): PlexMediaItem {
    item.editionTitle = EditionService.extractEditionTitle(
      item.editionTitle,
      item.Media
    );
    return item;
  }

  /**
   * Apply edition extraction to an array of items
   */
  private applyEditions(items: PlexMediaItem[]): PlexMediaItem[] {
    return items.map(item => this.applyEdition(item));
  }
}
