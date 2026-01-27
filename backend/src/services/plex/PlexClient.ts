import axios, { AxiosInstance, AxiosError } from 'axios';
import { cacheManager } from '../cache/CacheManager';
import { createLogger } from '../../utils/logger';
import { AppDataSource } from '../../db/data-source';
import { UserSettings } from '../../db/entities';
import { decryptForUser, isEncrypted } from '../../utils/crypto';
import crypto from 'crypto';

const logger = createLogger('plex');

interface PlexServer {
  id: string;
  name: string;
  host: string;
  port: number;
  protocol: 'http' | 'https';
  accessToken: string;
  owned: boolean;
  publicAddress?: string;
  localAddresses?: string[];
}

interface PlexLibrary {
  key: string;
  title: string;
  type: 'movie' | 'show' | 'music' | 'photo';
  agent?: string;
  scanner?: string;
  language?: string;
}

interface PlexMetadata {
  key: string;
  ratingKey: string;
  guid: string;
  type: string;
  title: string;
  summary?: string;
  year?: number;
  thumb?: string;
  art?: string;
  duration?: number;
  viewOffset?: number;
  viewCount?: number;
  lastViewedAt?: number;
  editionTitle?: string; // Add support for movie editions
}

export class PlexClient {
  private axiosClient: AxiosInstance;
  private server: PlexServer;
  private userId: string;
  private encryptionKey: Buffer;

  constructor(server: PlexServer, userId: string) {
    this.server = server;
    this.userId = userId;

    // Generate encryption key from server ID and user ID
    this.encryptionKey = crypto.scryptSync(
      process.env.SESSION_SECRET || 'default-secret',
      `${server.id}:${userId}`,
      32
    );

    const baseURL = `${server.protocol}://${server.host}:${server.port}`;

    this.axiosClient = axios.create({
      baseURL,
      timeout: 30000,
      headers: {
        'Accept': 'application/json',
        'X-Plex-Token': server.accessToken,
        'X-Plex-Client-Identifier': process.env.PLEX_CLIENT_ID || 'plex-media-backend',
        'X-Plex-Product': 'Plex Web',
        'X-Plex-Version': '4.128.1',
        'X-Plex-Platform': 'Web',
        'X-Plex-Platform-Version': '4.128.1',
        'X-Plex-Device': 'Web',
        'X-Plex-Device-Name': 'Plex Media Backend',
      }
    });

    // Add error handling
    this.axiosClient.interceptors.response.use(
      response => response,
      this.handleError.bind(this)
    );

    logger.info(`Plex client initialized for server ${server.name}`, {
      userId,
      serverId: server.id,
      host: server.host
    });
  }

  private handleError(error: AxiosError) {
    if (error.response) {
      const status = error.response.status;
      logger.error(`Plex API error: ${status}`, {
        url: error.config?.url,
        server: this.server.name,
        userId: this.userId
      });

      if (status === 401) {
        throw new Error('Invalid Plex token');
      } else if (status === 404) {
        throw new Error('Resource not found');
      } else if (status === 503) {
        throw new Error('Plex server is unavailable');
      }
    }
    throw error;
  }

  /**
   * Make cached request to Plex
   */
  private async cachedRequest<T>(
    path: string,
    cacheKey?: string,
    ttl?: number
  ): Promise<T> {
    const key = cacheKey || `${this.server.id}:${path}`;

    // Try cache first
    const cached = cacheManager.get<T>('plex', key);
    if (cached) {
      logger.debug(`Cache HIT: ${key}`);
      return cached;
    }

    logger.debug(`Plex API request: ${path}`);
    const data = await this.requestWithFallback<T>(path);

    // Cache the response
    cacheManager.set('plex', key, data, ttl);

    return data;
  }

  private async requestWithFallback<T>(path: string): Promise<T> {
    const primaryUrl = `${this.axiosClient.defaults.baseURL}${path}`;
    try {
      logger.info(`[Plex] Requesting: ${primaryUrl}`);
      const res = await this.axiosClient.get<T>(path);
      return res.data as any as T;
    } catch (err: any) {
      logger.error(`[Plex] Primary request FAILED: ${primaryUrl}`, {
        message: err.message,
        code: err.code,
        status: err.response?.status,
        isTimeout: err.code === 'ECONNABORTED'
      });

      const candidates: string[] = [];
      const port = this.server.port || 32400;
      const protos: Array<'https'|'http'> = this.server.protocol === 'https' ? ['https','http'] : ['http','https'];
      const push = (proto: string, host?: string) => { if (host) candidates.push(`${proto}://${host}:${port}`); };
      // Original
      push(this.server.protocol, this.server.host);
      // Public
      if (this.server.publicAddress) { protos.forEach(p => push(p, this.server.publicAddress)); }
      // Locals
      (this.server.localAddresses || []).forEach(addr => protos.forEach(p => push(p, addr)));

      logger.info(`[Plex] Trying ${candidates.length} fallback URLs for: ${path}`, { candidates });

      for (const base of candidates) {
        try {
          const fallbackUrl = `${base}${path}`;
          logger.info(`[Plex] Trying fallback: ${fallbackUrl}`);
          const alt = axios.create({
            baseURL: base,
            timeout: 10000,
            headers: this.axiosClient.defaults.headers.common,
          });
          const res = await alt.get<T>(path);
          logger.info(`[Plex] ✓ Fallback SUCCEEDED: ${fallbackUrl}`);
          // Switch to the working base for future calls
          this.axiosClient.defaults.baseURL = base;
          return res.data as any as T;
        } catch (e: any) {
          logger.info(`[Plex] ✗ Fallback failed (${base}): ${e.message}`);
          continue;
        }
      }

      logger.error(`[Plex] All ${candidates.length} fallback attempts failed for: ${path}`);
      throw err;
    }
  }

  /**
   * Get all libraries
   */
  async getLibraries(): Promise<PlexLibrary[]> {
    const data = await this.cachedRequest<any>(
      '/library/sections',
      `${this.server.id}:libraries`,
      3600 // 1 hour cache
    );

    return data.MediaContainer.Directory || [];
  }

  /**
   * Get library contents
   */
  async getLibraryContents(
    libraryKey: string,
    offset = 0,
    limit = 50,
    params?: Record<string, any>
  ): Promise<any> {
    const usp = new URLSearchParams();
    usp.set('X-Plex-Container-Start', String(offset));
    usp.set('X-Plex-Container-Size', String(limit));
    if (params) {
      Object.entries(params).forEach(([k, v]) => {
        if (v !== undefined && v !== null && k !== 'offset' && k !== 'limit') usp.set(k, String(v));
      });
    }

    const qs = usp.toString();
    const path = `/library/sections/${libraryKey}/all${qs ? `?${qs}` : ''}`;
    const cacheKey = `${this.server.id}:library:${libraryKey}:${offset}:${limit}:${JSON.stringify(params||{})}`;

    const data = await this.cachedRequest<any>(
      path,
      cacheKey,
      300 // 5 minutes cache
    );

    return data.MediaContainer;
  }

  /**
   * Get metadata for a specific item
   */
  async getMetadata(ratingKey: string): Promise<PlexMetadata> {
    const data = await this.cachedRequest<any>(
      `/library/metadata/${ratingKey}`,
      `${this.server.id}:metadata:${ratingKey}`,
      3600 // 1 hour cache
    );

    const metadata = data.MediaContainer.Metadata[0];

    return {
      ...metadata,
      editionTitle: metadata.editionTitle || undefined, // Include edition title if available
    };
  }

  /**
   * Search across all libraries
   */
  async search(query: string): Promise<PlexMetadata[]> {
    const data = await this.cachedRequest<any>(
      `/search?query=${encodeURIComponent(query)}`,
      `${this.server.id}:search:${query}`,
      300 // 5 minutes cache
    );

    return data.MediaContainer.Metadata || [];
  }

  /**
   * Search with optional type (1 movie, 2 show)
   */
  async searchTyped(query: string, type?: 1 | 2): Promise<PlexMetadata[]> {
    const params = new URLSearchParams({ query });
    if (type) params.set('type', String(type));
    const key = `${this.server.id}:search:${type || 'all'}:${query}`;
    const data = await this.cachedRequest<any>(`/search?${params.toString()}`, key, 300);
    return data.MediaContainer.Metadata || [];
  }

  /**
   * Get on deck items
   */
  async getOnDeck(): Promise<PlexMetadata[]> {
    const data = await this.cachedRequest<any>(
      '/library/onDeck',
      `${this.server.id}:ondeck`,
      60 // 1 minute cache
    );

    return data.MediaContainer.Metadata || [];
  }

  /**
   * Get continue watching
   */
  async getContinueWatching(): Promise<PlexMetadata[]> {
    const data = await this.cachedRequest<any>(
      '/hubs/home/continueWatching',
      `${this.server.id}:continue`,
      60 // 1 minute cache
    );

    return data.MediaContainer.Metadata || [];
  }

  /**
   * Get recently added
   */
  async getRecentlyAdded(libraryKey?: string): Promise<PlexMetadata[]> {
    const path = libraryKey
      ? `/library/sections/${libraryKey}/recentlyAdded`
      : '/library/recentlyAdded';

    const data = await this.cachedRequest<any>(
      path,
      `${this.server.id}:recent:${libraryKey || 'all'}`,
      300 // 5 minutes cache
    );

    return data.MediaContainer.Metadata || [];
  }

  /**
   * Get a secondary directory listing for a section (e.g., genre/year)
   */
  async getLibrarySecondary(libraryKey: string, directory: string) {
    const path = `/library/sections/${libraryKey}/${directory}`;
    const data = await this.cachedRequest<any>(
      path,
      `${this.server.id}:secondary:${libraryKey}:${directory}`,
      3600
    );
    return data.MediaContainer;
  }

  /**
   * Get collections for a library section
   */
  async getLibraryCollections(libraryKey: string) {
    const path = `/library/sections/${libraryKey}/collections`;
    const data = await this.cachedRequest<any>(
      path,
      `${this.server.id}:collections:${libraryKey}`,
      3600
    );
    return data.MediaContainer;
  }

  /**
   * Generic directory/path fetch under /library
   */
  async getDir(pathname: string, params?: Record<string, any>) {
    const safePath = pathname.startsWith('/') ? pathname : `/${pathname}`;
    if (!safePath.startsWith('/library/')) {
      throw new Error('Only /library paths are allowed');
    }

    const usp = new URLSearchParams();
    if (params) {
      Object.entries(params).forEach(([k, v]) => {
        if (v !== undefined && v !== null) usp.set(k, String(v));
      });
    }
    const fullPath = `${safePath}${usp.size ? `?${usp.toString()}` : ''}`;
    const key = `${this.server.id}:dir:${safePath}:${usp.toString()}`;
    const data = await this.cachedRequest<any>(fullPath, key, 600);
    return data.MediaContainer;
  }

  /**
   * Find items by GUID across libraries (optionally restricted by type)
   * Mirrors Plex Web behavior: try global /library/all?guid= first, then per-section fallback.
   */
  async findByGuid(guid: string, type?: 1 | 2) {
    // Try global search first
    try {
      const params = new URLSearchParams({ guid });
      if (type) params.set('type', String(type));
      const data = await this.cachedRequest<any>(
        `/library/all?${params.toString()}`,
        `${this.server.id}:guid:${guid}:${type || 0}:global`,
        1800
      );
      const meta = data?.MediaContainer?.Metadata || [];
      if (meta.length > 0) return data.MediaContainer;
    } catch {}

    // Fallback: iterate sections (optionally filtering by type)
    try {
      const libs = await this.cachedRequest<any>(
        '/library/sections',
        `${this.server.id}:libs`,
        1800
      );
      const sections: any[] = libs?.MediaContainer?.Directory || [];
      const filtered = type
        ? sections.filter((s) => (type === 1 && s.type === 'movie') || (type === 2 && s.type === 'show'))
        : sections;

      for (const s of filtered) {
        try {
          const p = `/library/sections/${s.key}/all?guid=${encodeURIComponent(guid)}`;
          const data = await this.cachedRequest<any>(
            p,
            `${this.server.id}:guid:${guid}:${type || 0}:section:${s.key}`,
            1800
          );
          const meta = data?.MediaContainer?.Metadata || [];
          if (meta.length > 0) return data.MediaContainer;
        } catch {}
      }
    } catch {}

    return { Metadata: [] };
  }

  /**
   * Get metadata with optional params (includeExtras, includeExternalMedia, includeChildren)
   */
  async getMetadataWithParams(ratingKey: string, params?: Record<string, any>) {
    const usp = new URLSearchParams();
    if (params) {
      Object.entries(params).forEach(([k, v]) => {
        if (v !== undefined && v !== null) usp.set(k, String(v));
      });
    }
    const fullPath = `/library/metadata/${ratingKey}${usp.size ? `?${usp.toString()}` : ''}`;
    const key = `${this.server.id}:metadata:${ratingKey}:${usp.toString()}`;
    const data = await this.cachedRequest<any>(fullPath, key, 3600);
    return data.MediaContainer.Metadata?.[0];
  }

  /**
   * Update playback progress
   */
  async updateProgress(ratingKey: string, timeMs: number, durationMs: number, stateOverride?: string, sessionId?: string, isTranscoding?: boolean) {
    const state = stateOverride || (timeMs >= durationMs * 0.9 ? 'stopped' : 'playing');

    const params: any = {
      ratingKey,
      key: `/library/metadata/${ratingKey}`,
      playbackTime: Math.floor(timeMs),
      time: Math.floor(timeMs),
      duration: Math.floor(durationMs),
      state,
      context: isTranscoding ? 'streaming' : 'library',
    };

    // Include session identifier for transcode sessions
    if (sessionId) {
      params['X-Plex-Session-Identifier'] = sessionId;
    }

    await this.axiosClient.get('/:/timeline', { params });

    // Invalidate related caches
    cacheManager.del('plex', `${this.server.id}:ondeck`);
    cacheManager.del('plex', `${this.server.id}:continue`);
    cacheManager.del('plex', `${this.server.id}:metadata:${ratingKey}`);
  }

  /**
   * Scrobble (mark as watched)
   */
  async scrobble(ratingKey: string) {
    await this.axiosClient.get(`/:/scrobble?key=${ratingKey}`);

    // Invalidate caches
    cacheManager.del('plex', `${this.server.id}:metadata:${ratingKey}`);
    cacheManager.del('plex', `${this.server.id}:ondeck`);
    cacheManager.del('plex', `${this.server.id}:continue`);
  }

  /**
   * Rate an item
   */
  async rate(ratingKey: string, rating: number) {
    await this.axiosClient.put(`/:/rate?key=${ratingKey}&rating=${rating}`);

    // Invalidate cache
    cacheManager.del('plex', `${this.server.id}:metadata:${ratingKey}`);
  }

  /**
   * Get transcode decision
   */
  async getTranscodeDecision(ratingKey: string, options: any = {}) {
    const params: any = {
      hasMDE: 1,
      path: `/library/metadata/${ratingKey}`,
      mediaIndex: options.mediaIndex ?? 0,
      partIndex: options.partIndex ?? 0,
      protocol: 'hls',
      fastSeek: 1,
      directPlay: 0,
      directStream: 1,
      audioBoost: 100,
    };
    if (options.quality != null) params.maxVideoBitrate = Number(options.quality);
    if (options.resolution) params.videoResolution = options.resolution;
    if (options.audioStreamID) params.audioStreamID = options.audioStreamID;
    if (options.subtitleStreamID) params.subtitleStreamID = options.subtitleStreamID;

    const response = await this.axiosClient.post('/video/:/transcode/universal/decision', null, {
      params
    });

    return response.data;
  }

  /**
   * Get streaming URL
   * Returns both the URL and the session ID used (for timeline sync)
   */
  async getStreamingUrl(ratingKey: string, options: any = {}): Promise<{ url: string; sessionId: string }> {
    // Detect client type - use HLS for native apps (iOS/macOS), DASH for web
    const protocol = options.protocol || 'hls'; // Default to HLS
    const extension = protocol === 'hls' ? 'm3u8' : 'mpd';

    // Build a universal start URL similar to Plex Web behavior (mirror frontend params)
    const usp = new URLSearchParams();
    usp.set('hasMDE', '1');
    usp.set('path', `/library/metadata/${ratingKey}`);
    usp.set('mediaIndex', String(options.mediaIndex ?? 0));
    usp.set('partIndex', String(options.partIndex ?? 0));
    usp.set('protocol', protocol);
    usp.set('fastSeek', '1');

    // Normalize directPlay to '1' or '0'
    usp.set('directPlay', (options.directPlay ?? '0') === '1' ? '1' : '0');

    // When transcoding (quality explicitly set), disable directStream; otherwise allow it
    const hasQuality = options.quality !== undefined && options.quality !== null && options.quality !== '';
    const directStream = hasQuality ? '0' : ((options.directStream ?? '1') === '1' ? '1' : '0');
    usp.set('directStream', directStream);

    usp.set('directStreamAudio', '1');
    usp.set('subtitleSize', '100');
    usp.set('audioBoost', '100');

    if (protocol === 'hls') {
      // HLS-specific parameters
      usp.set('segmentSize', '4');
    } else {
      // DASH-specific parameters
      usp.set('manifestSubtitles', '1');
    }

    // Normalize autoAdjustQuality to '1' or '0' (string '0' is truthy, so explicitly check)
    const autoAdjust = (options.autoAdjustQuality ?? '0') === '1' ? '1' : '0';
    usp.set('autoAdjustQuality', autoAdjust);
    if (options.quality != null) usp.set('maxVideoBitrate', String(Number(options.quality)));
    if (options.resolution) usp.set('videoResolution', options.resolution);
    // Omit audio/subtitle stream selection from the URL like the legacy frontend dash path
    // Note: We intentionally do not append token; our proxy layer will add it when fetching
    const sep = usp.toString().length ? '?' : '';
    const path = `/video/:/transcode/universal/start.${extension}${sep}${usp.toString()}`;
    const urlBase = `${this.axiosClient.defaults.baseURL}${path}`;

    // Build client profile for DASH transcoding (tells Plex what codecs/resolutions we support)
    const clientProfile = [
      'add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.width&value=4096&replace=true)',
      'add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.height&value=2160&replace=true)',
      'add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.bitDepth&value=10&replace=true)',
      'append-transcode-target-codec(type=videoProfile&context=streaming&protocol=dash&videoCodec=h264)',
      'append-transcode-target-codec(type=videoProfile&context=streaming&protocol=hls&videoCodec=h264)',
      'append-transcode-target-codec(type=videoProfile&context=streaming&videoCodec=h264,hevc&audioCodec=aac&protocol=dash)',
      'add-limitation(scope=videoTranscodeTarget&scopeName=hevc&scopeType=videoCodec&context=streaming&protocol=dash&type=match&name=video.colorTrc&list=bt709|bt470m|bt470bg|smpte170m|smpte240m|bt2020-10|smpte2084&isRequired=false)'
    ].join('+');

    // Append X-Plex headers as query params to mirror frontend behavior
    const headerParams = new URLSearchParams({
      'X-Plex-Product': process.env.PLEX_PRODUCT || 'Plex Web',
      'X-Plex-Version': process.env.PLEX_VERSION || '4.128.1',
      'X-Plex-Client-Identifier': process.env.PLEX_CLIENT_ID || 'plex-media-backend',
      'X-Plex-Platform': 'Web',
      'X-Plex-Platform-Version': process.env.PLEX_PLATFORM_VERSION || '1.0.0',
      'X-Plex-Device': 'Web',
      'X-Plex-Device-Name': 'Plex Media Backend',
      'X-Plex-Device-Screen-Resolution': process.env.PLEX_SCREEN_RES || '1920x1080',
      'X-Plex-Language': 'en',
      'X-Plex-Client-Profile-Extra': clientProfile,
    });
    // Session identifier - use provided sessionId or generate a new one
    const sessionId = options.sessionId || `sess_${this.userId}_${ratingKey}_${Date.now()}`;
    headerParams.set('session', sessionId);

    // Append token last
    headerParams.set('X-Plex-Token', this.server.accessToken);

    const url = urlBase.includes('?')
      ? `${urlBase}&${headerParams.toString()}`
      : `${urlBase}?${headerParams.toString()}`;
    return { url, sessionId };
  }

  /**
   * Get server capabilities
   */
  async getServerCapabilities() {
    const data = await this.cachedRequest<any>(
      '/',
      `${this.server.id}:capabilities`,
      3600 // 1 hour cache
    );

    return {
      version: data.MediaContainer.version,
      platform: data.MediaContainer.platform,
      platformVersion: data.MediaContainer.platformVersion,
      transcoderVideo: data.MediaContainer.transcoderVideo,
      transcoderAudio: data.MediaContainer.transcoderAudio,
      transcoderVideoBitrates: data.MediaContainer.transcoderVideoBitrates,
      transcoderVideoQualities: data.MediaContainer.transcoderVideoQualities,
      transcoderVideoResolutions: data.MediaContainer.transcoderVideoResolutions,
    };
  }

  /**
   * Test server connection
   */
  async testConnection(): Promise<boolean> {
    try {
      await this.axiosClient.get('/');
      return true;
    } catch (error) {
      logger.error('Server connection test failed', {
        server: this.server.name,
        error
      });
      return false;
    }
  }

  /**
   * Get server info
   */
  getServerInfo(): PlexServer {
    return { ...this.server };
  }

  /**
   * Encrypt sensitive data
   */
  private encrypt(text: string): string {
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.encryptionKey, iv);

    let encrypted = cipher.update(text, 'utf8', 'hex');
    encrypted += cipher.final('hex');

    const authTag = cipher.getAuthTag();

    return iv.toString('hex') + ':' + authTag.toString('hex') + ':' + encrypted;
  }

  /**
   * Decrypt sensitive data
   */
  private decrypt(encryptedData: string): string {
    const parts = encryptedData.split(':');
    const iv = Buffer.from(parts[0], 'hex');
    const authTag = Buffer.from(parts[1], 'hex');
    const encrypted = parts[2];

    const decipher = crypto.createDecipheriv('aes-256-gcm', this.encryptionKey, iv);
    decipher.setAuthTag(authTag);

    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
  }
}

// Singleton management for Plex clients
const clientMap = new Map<string, PlexClient>();

/**
 * Get or create Plex client for a user and server
 */
export async function getPlexClient(userId: string, serverId?: string): Promise<PlexClient> {
  const settingsRepo = AppDataSource.getRepository(UserSettings);
  const settings = await settingsRepo.findOne({ where: { userId } });

  if (!settings?.plexServers || settings.plexServers.length === 0) {
    throw new Error('No Plex servers configured');
  }

  // Use specified server or current server
  const targetServerId = serverId || settings.currentServerId;
  const server = settings.plexServers.find((s: any) => s.id === targetServerId);

  if (!server) {
    throw new Error('Server not found');
  }

  const cacheKey = `${userId}:${server.id}`;

  if (!clientMap.has(cacheKey)) {
    // Decrypt access token if needed
    const plainToken = isEncrypted((server as any).accessToken)
      ? decryptForUser(userId, (server as any).accessToken)
      : (server as any).accessToken;
    const normalized = {
      id: (server as any).id,
      name: (server as any).name,
      host: (server as any).host,
      port: (server as any).port,
      protocol: (server as any).protocol,
      accessToken: plainToken,
      owned: (server as any).owned,
      publicAddress: (server as any).publicAddress,
      localAddresses: (server as any).localAddresses,
    } as any as PlexServer;
    clientMap.set(cacheKey, new PlexClient(normalized, userId));
  }

  return clientMap.get(cacheKey)!;
}

/**
 * Clear client cache for a user
 */
export function clearPlexClients(userId: string) {
  for (const [key, _] of clientMap) {
    if (key.startsWith(userId)) {
      clientMap.delete(key);
    }
  }
}
