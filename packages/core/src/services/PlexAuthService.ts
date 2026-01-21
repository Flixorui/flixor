import type { PlexPin, PlexUser, PlexHomeUser, PlexServer, PlexConnection } from '../models/plex';

const PLEX_TV_URL = 'https://plex.tv';

interface PlexResourceConnection {
  protocol: string;
  address: string;
  port: number;
  uri: string;
  local: boolean;
  relay: boolean;
  IPv6: boolean;
}

interface PlexResource {
  name: string;
  product: string;
  productVersion: string;
  platform: string;
  platformVersion: string;
  device: string;
  clientIdentifier: string;
  createdAt: string;
  lastSeenAt: string;
  provides: string;
  owned: boolean;
  accessToken: string;
  publicAddress?: string;
  httpsRequired?: boolean;
  synced?: boolean;
  relay?: boolean;
  dnsRebindingProtection?: boolean;
  natLoopbackSupported?: boolean;
  publicAddressMatches?: boolean;
  presence?: boolean;
  connections: PlexResourceConnection[];
}

/**
 * Service for Plex.tv authentication (PIN-based auth flow)
 */
export class PlexAuthService {
  private clientId: string;
  private productName: string;
  private productVersion: string;
  private platform: string;
  private deviceName: string;

  constructor(options: {
    clientId: string;
    productName?: string;
    productVersion?: string;
    platform?: string;
    deviceName?: string;
  }) {
    this.clientId = options.clientId;
    this.productName = options.productName || 'Flixor';
    this.productVersion = options.productVersion || '1.0.0';
    this.platform = options.platform || 'Mobile';
    this.deviceName = options.deviceName || 'Flixor Mobile';
  }

  /**
   * Get standard Plex headers for API requests
   */
  private getHeaders(token?: string): Record<string, string> {
    const headers: Record<string, string> = {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-Plex-Client-Identifier': this.clientId,
      'X-Plex-Product': this.productName,
      'X-Plex-Version': this.productVersion,
      'X-Plex-Platform': this.platform,
      'X-Plex-Platform-Version': this.productVersion,
      'X-Plex-Device': this.platform,
      'X-Plex-Device-Name': this.deviceName,
    };

    if (token) {
      headers['X-Plex-Token'] = token;
    }

    return headers;
  }

  /**
   * Create a new PIN for authentication
   * User should visit app.plex.tv/auth with the code pre-filled
   */
  async createPin(): Promise<PlexPin> {
    // Use X-Plex-Model: hosted for web-based auth flow (app.plex.tv/auth)
    const headers = {
      ...this.getHeaders(),
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-Plex-Model': 'hosted',
    };

    const response = await fetch(`${PLEX_TV_URL}/api/v2/pins?strong=true`, {
      method: 'POST',
      headers,
    });

    if (!response.ok) {
      throw new Error(`Failed to create PIN: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    return {
      id: data.id,
      code: data.code,
    };
  }

  /**
   * Check if PIN has been authorized
   * Returns authToken if authorized, null if still pending
   */
  async checkPin(pinId: number): Promise<string | null> {
    const response = await fetch(`${PLEX_TV_URL}/api/v2/pins/${pinId}`, {
      method: 'GET',
      headers: this.getHeaders(),
    });

    if (!response.ok) {
      if (response.status === 404) {
        throw new Error('PIN expired or not found');
      }
      throw new Error(`Failed to check PIN: ${response.status}`);
    }

    const data = await response.json();
    return data.authToken || null;
  }

  /**
   * Poll for PIN authorization with timeout
   */
  async waitForPin(
    pinId: number,
    options?: { intervalMs?: number; timeoutMs?: number; onPoll?: () => void }
  ): Promise<string> {
    const { intervalMs = 2000, timeoutMs = 300000, onPoll } = options || {};
    const startTime = Date.now();

    while (Date.now() - startTime < timeoutMs) {
      onPoll?.();

      const token = await this.checkPin(pinId);
      if (token) {
        return token;
      }

      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }

    throw new Error('PIN authorization timed out');
  }

  /**
   * Get authenticated user information
   */
  async getUser(token: string): Promise<PlexUser> {
    const response = await fetch(`${PLEX_TV_URL}/api/v2/user`, {
      method: 'GET',
      headers: this.getHeaders(token),
    });

    if (!response.ok) {
      if (response.status === 401) {
        throw new Error('Invalid or expired token');
      }
      throw new Error(`Failed to get user: ${response.status}`);
    }

    const data = await response.json();
    return {
      id: data.id,
      uuid: data.uuid,
      username: data.username,
      email: data.email,
      thumb: data.thumb,
      title: data.title,
    };
  }

  /**
   * Get available Plex servers for the authenticated user
   */
  async getServers(token: string): Promise<PlexServer[]> {
    const response = await fetch(
      `${PLEX_TV_URL}/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1`,
      {
        method: 'GET',
        headers: this.getHeaders(token),
      }
    );

    if (!response.ok) {
      throw new Error(`Failed to get servers: ${response.status}`);
    }

    const resources: PlexResource[] = await response.json();

    // Filter to only Plex Media Servers
    const servers = resources.filter((r) => r.provides === 'server');

    return servers.map((server) => ({
      id: server.clientIdentifier,
      name: server.name,
      owned: server.owned,
      accessToken: server.accessToken,
      publicAddress: server.publicAddress,
      presence: server.presence,
      connections: server.connections.map((conn) => ({
        uri: conn.uri,
        protocol: conn.protocol,
        local: conn.local,
        relay: conn.relay,
        IPv6: conn.IPv6,
      })),
    }));
  }

  /**
   * Test a server connection
   * Returns true if connection is valid and accessible
   */
  async testConnection(connection: PlexConnection, token: string): Promise<boolean> {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 5000);

      const response = await fetch(`${connection.uri}/identity`, {
        method: 'GET',
        headers: this.getHeaders(token),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);
      return response.ok;
    } catch {
      return false;
    }
  }

  /**
   * Find the best connection for a server
   * Prefers local connections, then relay, then remote
   */
  async findBestConnection(
    server: PlexServer,
    token: string
  ): Promise<PlexConnection | null> {
    // Sort connections: local first, then non-relay, then relay
    const sortedConnections = [...server.connections].sort((a, b) => {
      if (a.local !== b.local) return a.local ? -1 : 1;
      if (a.relay !== b.relay) return a.relay ? 1 : -1;
      return 0;
    });

    // Test each connection
    for (const conn of sortedConnections) {
      const isValid = await this.testConnection(conn, token);
      if (isValid) {
        return conn;
      }
    }

    return null;
  }

  /**
   * Get list of Plex Home users
   * Returns empty array if user is not part of a Plex Home
   */
  async getHomeUsers(token: string): Promise<PlexHomeUser[]> {
    const response = await fetch(`${PLEX_TV_URL}/api/v2/home/users`, {
      method: 'GET',
      headers: this.getHeaders(token),
    });

    if (!response.ok) {
      if (response.status === 403) {
        // User is not part of a Plex Home
        return [];
      }
      throw new Error(`Failed to get home users: ${response.status}`);
    }

    const data = await response.json();

    // API returns { users: [...] } or may be direct array
    const users = Array.isArray(data) ? data : (data?.users || []);

    return users.map((user: Record<string, unknown>) => ({
      id: user.id as number,
      uuid: user.uuid as string,
      title: (user.title || user.username || 'Unknown') as string,
      username: (user.username || '') as string,
      email: user.email as string | undefined,
      thumb: user.thumb as string | undefined,
      restricted: Boolean(user.restricted),
      protected: Boolean(user.protected),
      admin: Boolean(user.admin),
      guest: Boolean(user.guest),
      home: Boolean(user.home),
    }));
  }

  /**
   * Switch to a different Plex Home user
   * @param token - Main account token
   * @param userUuid - Target user UUID to switch to
   * @param pin - PIN if the user is protected (has PIN set)
   * @returns Object with new authentication token for the switched user
   */
  async switchHomeUser(
    token: string,
    userUuid: string,
    pin?: string
  ): Promise<{ authenticationToken: string }> {
    const url = new URL(`${PLEX_TV_URL}/api/v2/home/users/${userUuid}/switch`);
    if (pin) {
      url.searchParams.append('pin', pin);
    }

    const response = await fetch(url.toString(), {
      method: 'POST',
      headers: this.getHeaders(token),
    });

    if (!response.ok) {
      if (response.status === 401) {
        throw new Error('Invalid PIN');
      }
      if (response.status === 403) {
        throw new Error('Not authorized to switch to this user');
      }
      throw new Error(`Failed to switch user: ${response.status}`);
    }

    const data = await response.json();

    if (!data.authToken && !data.authenticationToken) {
      throw new Error('No authentication token in response');
    }

    return {
      authenticationToken: data.authToken || data.authenticationToken,
    };
  }

  /**
   * Sign out - revoke the token
   */
  async signOut(token: string): Promise<void> {
    try {
      await fetch(`${PLEX_TV_URL}/api/v2/tokens/${token}`, {
        method: 'DELETE',
        headers: this.getHeaders(token),
      });
    } catch {
      // Ignore errors during sign out
    }
  }
}
