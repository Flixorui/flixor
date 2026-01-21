import type { IStorage } from './storage/IStorage';
import type { ISecureStorage } from './storage/ISecureStorage';
import type { ICache } from './storage/ICache';
import { PlexAuthService } from './services/PlexAuthService';
import { PlexServerService } from './services/PlexServerService';
import { PlexTvService } from './services/PlexTvService';
import { TMDBService } from './services/TMDBService';
import { TraktService } from './services/TraktService';
import type { PlexServer, PlexConnection, PlexHomeUser } from './models/plex';

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
  // Profile info (if using a profile other than main account)
  currentProfile?: {
    userId: number;
    uuid: string;
    title: string;
    thumb?: string;
    profileToken: string;
    profileServerToken?: string;  // Server-specific access token for this profile
    restricted: boolean;
  };
}

// Active profile info (exported for mobile usage)
export interface ActiveProfile {
  userId: number;
  uuid: string;
  title: string;
  thumb?: string;
  restricted: boolean;
  protected: boolean;
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

  // Profile management state
  private mainAccountToken: string | null = null;  // Original account token (for switching back)
  private currentProfileId: string | null = null;   // Current profile UUID (null = main account)
  private _currentProfile: ActiveProfile | null = null;  // Current profile info

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

  // ============================================
  // Profile Management
  // ============================================

  /**
   * Check if user is using a profile (not main account)
   */
  get isUsingProfile(): boolean {
    return this.currentProfileId !== null;
  }

  /**
   * Get current active profile info (null if using main account)
   */
  get currentProfile(): ActiveProfile | null {
    return this._currentProfile;
  }

  /**
   * Get the main account token (for profile switching operations)
   */
  get mainToken(): string | null {
    return this.mainAccountToken;
  }

  /**
   * Get Plex Home users for current account
   */
  async getHomeUsers(): Promise<PlexHomeUser[]> {
    const token = this.mainAccountToken || this.plexToken;
    if (!token) {
      throw new Error('Plex not authenticated');
    }
    return this._plexAuth.getHomeUsers(token);
  }

  /**
   * Switch to a Plex Home profile
   * @param userId - Target user ID
   * @param pin - PIN if required (protected profile)
   */
  async switchToProfile(user: PlexHomeUser, pin?: string): Promise<void> {
    const mainToken = this.mainAccountToken || this.plexToken;
    if (!mainToken) {
      throw new Error('Plex not authenticated');
    }

    // Validate PIN for protected users
    if (user.protected && !pin) {
      throw new Error('PIN required for this profile');
    }

    // Switch on the server side (get new token) - uses UUID for v2 API
    const result = await this._plexAuth.switchHomeUser(mainToken, user.uuid, pin);

    // Store main account token if not already stored
    if (!this.mainAccountToken) {
      this.mainAccountToken = this.plexToken;
    }

    // Update to profile-specific token
    this.plexToken = result.authenticationToken;
    this.currentProfileId = user.uuid;
    this._currentProfile = {
      userId: user.id,
      uuid: user.uuid,
      title: user.title,
      thumb: user.thumb,
      restricted: user.restricted,
      protected: user.protected,
    };

    // Re-initialize PlexTvService with new token
    this._plexTv = new PlexTvService({
      token: result.authenticationToken,
      clientId: this.config.clientId,
      cache: this.config.cache,
    });

    // Re-fetch server resources with profile token to get profile-specific server access token
    let profileServerToken = result.authenticationToken;
    if (this.currentServer) {
      try {
        const servers = await this._plexAuth.getServers(result.authenticationToken);
        const matchingServer = servers.find(s => s.id === this.currentServer!.id);
        if (matchingServer) {
          profileServerToken = matchingServer.accessToken;
          // Update current server with profile-specific access token
          this.currentServer = {
            ...this.currentServer,
            accessToken: profileServerToken,
          };
        }
      } catch {
        // Failed to get profile-specific server token, will use profile token
      }
    }

    // Re-initialize PlexServerService with profile-specific server token
    if (this._plexServer && this.currentConnection) {
      this._plexServer = new PlexServerService({
        baseUrl: this.currentConnection.uri,
        token: profileServerToken,
        clientId: this.config.clientId,
        cache: this.config.cache,
      });
    }

    // Update stored auth with profile info
    if (this.currentServer && this.currentConnection) {
      await this.config.secureStorage.set<StoredPlexAuth>('plex_auth', {
        token: mainToken,
        server: this.currentServer,
        connection: this.currentConnection,
        currentProfile: {
          userId: user.id,
          uuid: user.uuid,
          title: user.title,
          thumb: user.thumb,
          profileToken: result.authenticationToken,
          profileServerToken: profileServerToken,
          restricted: user.restricted,
        },
      });
    }
  }

  /**
   * Switch back to main account
   */
  async switchToMainAccount(): Promise<void> {
    if (!this.mainAccountToken) {
      // Already on main account
      return;
    }

    // Restore main account token
    this.plexToken = this.mainAccountToken;
    this.currentProfileId = null;
    this._currentProfile = null;

    // Re-initialize PlexTvService with main token
    this._plexTv = new PlexTvService({
      token: this.mainAccountToken,
      clientId: this.config.clientId,
      cache: this.config.cache,
    });

    // Re-fetch server resources with main account token to get main account's server access token
    let mainServerToken = this.mainAccountToken;
    if (this.currentServer) {
      try {
        const servers = await this._plexAuth.getServers(this.mainAccountToken);
        const matchingServer = servers.find(s => s.id === this.currentServer!.id);
        if (matchingServer) {
          mainServerToken = matchingServer.accessToken;
          // Update current server with main account's access token
          this.currentServer = {
            ...this.currentServer,
            accessToken: mainServerToken,
          };
        }
      } catch {
        // Failed to get main account server token
      }
    }

    // Re-initialize PlexServerService with main account's server token
    if (this._plexServer && this.currentConnection) {
      this._plexServer = new PlexServerService({
        baseUrl: this.currentConnection.uri,
        token: mainServerToken,
        clientId: this.config.clientId,
        cache: this.config.cache,
      });
    }

    // Update stored auth (remove profile info)
    if (this.currentServer && this.currentConnection) {
      await this.config.secureStorage.set<StoredPlexAuth>('plex_auth', {
        token: this.mainAccountToken,
        server: this.currentServer,
        connection: this.currentConnection,
      });
    }
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
      this.mainAccountToken = storedAuth.token;
      this.currentServer = storedAuth.server;
      this.currentConnection = storedAuth.connection;

      // Check if we have a stored profile
      if (storedAuth.currentProfile) {
        // Restore profile state
        this.plexToken = storedAuth.currentProfile.profileToken;
        this.currentProfileId = storedAuth.currentProfile.uuid;
        this._currentProfile = {
          userId: storedAuth.currentProfile.userId,
          uuid: storedAuth.currentProfile.uuid,
          title: storedAuth.currentProfile.title,
          thumb: storedAuth.currentProfile.thumb,
          restricted: storedAuth.currentProfile.restricted,
          protected: false, // We don't store this, doesn't matter for restore
        };
      } else {
        // Using main account
        this.plexToken = storedAuth.token;
        this.currentProfileId = null;
        this._currentProfile = null;
      }

      // Initialize services with the appropriate tokens
      // PlexTv uses the plex.tv identity token
      const activeToken = this.plexToken || storedAuth.token;
      this._plexTv = new PlexTvService({
        token: activeToken,
        clientId: this.config.clientId,
        cache: this.config.cache,
      });

      // PlexServer needs the server-specific access token
      let serverToken: string;

      if (storedAuth.currentProfile) {
        // We have a profile - need profile-specific server token
        if (storedAuth.currentProfile.profileServerToken) {
          serverToken = storedAuth.currentProfile.profileServerToken;
        } else {
          // No profileServerToken stored (legacy data) - fetch it now
          try {
            const servers = await this._plexAuth.getServers(storedAuth.currentProfile.profileToken);
            const matchingServer = servers.find(s => s.id === storedAuth.server.id);
            if (matchingServer) {
              serverToken = matchingServer.accessToken;
              // Update stored auth with the new profileServerToken
              this.currentServer = { ...storedAuth.server, accessToken: serverToken };
              await this.config.secureStorage.set<StoredPlexAuth>('plex_auth', {
                ...storedAuth,
                server: this.currentServer,
                currentProfile: {
                  ...storedAuth.currentProfile,
                  profileServerToken: serverToken,
                },
              });
            } else {
              serverToken = storedAuth.server.accessToken;
            }
          } catch {
            serverToken = storedAuth.server.accessToken;
          }
        }
      } else {
        // Main account - use the server's accessToken
        serverToken = storedAuth.server.accessToken;
      }

      this._plexServer = new PlexServerService({
        baseUrl: storedAuth.connection.uri,
        token: serverToken,
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
