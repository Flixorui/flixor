import type { IStorage } from './storage/IStorage';
import type { ISecureStorage } from './storage/ISecureStorage';
import type { ICache } from './storage/ICache';
import { PlexAuthService } from './services/PlexAuthService';
import { PlexServerService } from './services/PlexServerService';
import { PlexTvService } from './services/PlexTvService';
import { TMDBService } from './services/TMDBService';
import { TraktService } from './services/TraktService';
import type { PlexServer, PlexConnection } from './models/plex';

export interface FlixorCoreConfig {
  // Platform bindings
  storage: IStorage;
  secureStorage: ISecureStorage;
  cache: ICache;

  // Client identification
  clientId: string;
  productName?: string;
  productVersion?: string;
  platform?: string;
  deviceName?: string;

  // API keys
  tmdbApiKey: string;
  traktClientId: string;
  traktClientSecret: string;

  // Optional settings
  language?: string;
}

interface StoredPlexAuth {
  token: string;
  server: PlexServer;
  connection: PlexConnection;
}

/**
 * Main entry point for Flixor Core
 * Initializes and manages all services with platform-specific storage bindings
 */
export class FlixorCore {
  private config: FlixorCoreConfig;
  private _plexAuth: PlexAuthService;
  private _plexServer: PlexServerService | null = null;
  private _plexTv: PlexTvService | null = null;
  private _tmdb: TMDBService;
  private _trakt: TraktService;

  // Current Plex state
  private plexToken: string | null = null;
  private currentServer: PlexServer | null = null;
  private currentConnection: PlexConnection | null = null;

  constructor(config: FlixorCoreConfig) {
    this.config = config;

    // Initialize Plex Auth Service (always available)
    this._plexAuth = new PlexAuthService({
      clientId: config.clientId,
      productName: config.productName,
      productVersion: config.productVersion,
      platform: config.platform,
      deviceName: config.deviceName,
    });

    // Initialize TMDB Service (always available)
    this._tmdb = new TMDBService({
      apiKey: config.tmdbApiKey,
      cache: config.cache,
      language: config.language,
    });

    // Initialize Trakt Service (always available)
    this._trakt = new TraktService({
      clientId: config.traktClientId,
      clientSecret: config.traktClientSecret,
      cache: config.cache,
      secureStorage: config.secureStorage,
    });
  }

  // ============================================
  // Service Accessors
  // ============================================

  /**
   * Get Plex Auth service (for PIN auth flow)
   */
  get plexAuth(): PlexAuthService {
    return this._plexAuth;
  }

  /**
   * Get Plex Server service (requires active connection)
   */
  get plexServer(): PlexServerService {
    if (!this._plexServer) {
      throw new Error('Plex server not connected. Call connectToServer first.');
    }
    return this._plexServer;
  }

  /**
   * Get Plex.tv service (requires authentication)
   */
  get plexTv(): PlexTvService {
    if (!this._plexTv) {
      throw new Error('Plex not authenticated. Call authenticate or restoreSession first.');
    }
    return this._plexTv;
  }

  /**
   * Get TMDB service (always available)
   */
  get tmdb(): TMDBService {
    return this._tmdb;
  }

  /**
   * Get Trakt service (always available, but some features require auth)
   */
  get trakt(): TraktService {
    return this._trakt;
  }

  // ============================================
  // Plex Authentication & Connection
  // ============================================

  /**
   * Check if Plex is authenticated
   */
  get isPlexAuthenticated(): boolean {
    return this.plexToken !== null && this._plexTv !== null;
  }

  /**
   * Check if connected to a Plex server
   */
  get isPlexServerConnected(): boolean {
    return this._plexServer !== null;
  }

  /**
   * Get current Plex server info
   */
  get server(): PlexServer | null {
    return this.currentServer;
  }

  /**
   * Get current Plex connection info
   */
  get connection(): PlexConnection | null {
    return this.currentConnection;
  }

  /**
   * Get the Plex auth token (for playback headers)
   */
  getPlexToken(): string | null {
    // Return server-specific token if connected, otherwise general token
    return this.currentServer?.accessToken || this.plexToken;
  }

  /**
   * Get the client ID
   */
  getClientId(): string {
    return this.config.clientId;
  }

  /**
   * Initialize - restore session from storage
   */
  async initialize(): Promise<boolean> {
    // Restore Plex session
    const plexRestored = await this.restorePlexSession();

    // Initialize Trakt (restore tokens)
    await this._trakt.initialize();

    return plexRestored;
  }

  /**
   * Restore Plex session from secure storage
   */
  private async restorePlexSession(): Promise<boolean> {
    try {
      const storedAuth = await this.config.secureStorage.get<StoredPlexAuth>('plex_auth');

      if (!storedAuth) {
        return false;
      }

      // Verify token is still valid
      try {
        await this._plexAuth.getUser(storedAuth.token);
      } catch {
        // Token invalid, clear stored auth
        await this.config.secureStorage.remove('plex_auth');
        return false;
      }

      // Restore state
      this.plexToken = storedAuth.token;
      this.currentServer = storedAuth.server;
      this.currentConnection = storedAuth.connection;

      // Initialize services
      this._plexTv = new PlexTvService({
        token: storedAuth.token,
        clientId: this.config.clientId,
        cache: this.config.cache,
      });

      this._plexServer = new PlexServerService({
        baseUrl: storedAuth.connection.uri,
        token: storedAuth.server.accessToken,
        clientId: this.config.clientId,
        cache: this.config.cache,
      });

      return true;
    } catch {
      return false;
    }
  }

  /**
   * Authenticate with Plex using PIN code
   * Returns the PIN info for user to enter at plex.tv/link
   */
  async createPlexPin(): Promise<{ id: number; code: string }> {
    return this._plexAuth.createPin();
  }

  /**
   * Wait for PIN authorization and complete auth
   */
  async waitForPlexPin(
    pinId: number,
    options?: { intervalMs?: number; timeoutMs?: number; onPoll?: () => void }
  ): Promise<string> {
    const token = await this._plexAuth.waitForPin(pinId, options);

    // Store token and initialize PlexTvService
    this.plexToken = token;
    this._plexTv = new PlexTvService({
      token,
      clientId: this.config.clientId,
      cache: this.config.cache,
    });

    return token;
  }

  /**
   * Get available Plex servers for authenticated user
   */
  async getPlexServers(): Promise<PlexServer[]> {
    if (!this.plexToken) {
      throw new Error('Plex not authenticated');
    }
    return this._plexAuth.getServers(this.plexToken);
  }

  /**
   * Connect to a specific Plex server
   */
  async connectToPlexServer(server: PlexServer): Promise<PlexConnection> {
    if (!this.plexToken) {
      throw new Error('Plex not authenticated');
    }

    // Find the best connection
    const connection = await this._plexAuth.findBestConnection(
      server,
      server.accessToken
    );

    if (!connection) {
      throw new Error(`Could not connect to server: ${server.name}`);
    }

    // Store state
    this.currentServer = server;
    this.currentConnection = connection;

    // Initialize server service
    this._plexServer = new PlexServerService({
      baseUrl: connection.uri,
      token: server.accessToken,
      clientId: this.config.clientId,
      cache: this.config.cache,
    });

    // Persist to secure storage
    await this.config.secureStorage.set<StoredPlexAuth>('plex_auth', {
      token: this.plexToken,
      server,
      connection,
    });

    return connection;
  }

  /**
   * Sign out from Plex
   */
  async signOutPlex(): Promise<void> {
    if (this.plexToken) {
      await this._plexAuth.signOut(this.plexToken);
    }

    // Clear state
    this.plexToken = null;
    this.currentServer = null;
    this.currentConnection = null;
    this._plexTv = null;
    this._plexServer = null;

    // Clear storage
    await this.config.secureStorage.remove('plex_auth');
    await this.config.cache.invalidatePattern('plex:*');
    await this.config.cache.invalidatePattern('plextv:*');
  }

  // ============================================
  // Trakt Authentication
  // ============================================

  /**
   * Check if Trakt is authenticated
   */
  get isTraktAuthenticated(): boolean {
    return this._trakt.isAuthenticated();
  }

  /**
   * Generate Trakt device code for authentication
   */
  async createTraktDeviceCode() {
    return this._trakt.generateDeviceCode();
  }

  /**
   * Wait for Trakt device code authorization
   */
  async waitForTraktDeviceCode(
    deviceCode: Awaited<ReturnType<TraktService['generateDeviceCode']>>,
    options?: { onPoll?: () => void }
  ) {
    return this._trakt.waitForDeviceCode(deviceCode, options);
  }

  /**
   * Sign out from Trakt
   */
  async signOutTrakt(): Promise<void> {
    await this._trakt.signOut();
  }

  // ============================================
  // Cache Management
  // ============================================

  /**
   * Clear all caches
   */
  async clearAllCaches(): Promise<void> {
    await this.config.cache.clear();
  }

  /**
   * Clear Plex caches
   */
  async clearPlexCache(): Promise<void> {
    await this.config.cache.invalidatePattern('plex:*');
    await this.config.cache.invalidatePattern('plextv:*');
  }

  /**
   * Clear TMDB cache
   */
  async clearTmdbCache(): Promise<void> {
    await this._tmdb.invalidateCache();
  }

  /**
   * Clear Trakt cache
   */
  async clearTraktCache(): Promise<void> {
    await this._trakt.invalidateCache();
  }
}
