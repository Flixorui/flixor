/**
 * Settings screen data fetchers using FlixorCore
 * Replaces the old api/client.ts functions for My/Settings screen
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { getFlixorCore } from './index';

// ============================================
// Trakt Authentication
// ============================================

export async function getTraktProfile(): Promise<any | null> {
  try {
    const core = getFlixorCore();
    return await core.trakt.getProfile();
  } catch (e) {
    console.log('[SettingsData] getTraktProfile error:', e);
    return null;
  }
}

export async function startTraktDeviceAuth(): Promise<{
  device_code: string;
  user_code: string;
  verification_url: string;
  expires_in: number;
  interval: number;
} | null> {
  try {
    const core = getFlixorCore();
    return await core.trakt.generateDeviceCode();
  } catch (e) {
    console.log('[SettingsData] startTraktDeviceAuth error:', e);
    return null;
  }
}

export async function pollTraktToken(deviceCode: string): Promise<{
  access_token: string;
  refresh_token: string;
  expires_in: number;
  created_at: number;
} | null> {
  try {
    const core = getFlixorCore();
    return await core.trakt.pollDeviceCode(deviceCode);
  } catch (e) {
    // Polling will fail until user authorizes - this is expected
    return null;
  }
}

export async function saveTraktTokens(_tokens: {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  created_at: number;
}): Promise<void> {
  // Tokens are automatically saved by pollDeviceCode in TraktService
  // This function is kept for compatibility but is a no-op
}

export async function signOutTrakt(): Promise<void> {
  try {
    const core = getFlixorCore();
    await core.trakt.signOut();
  } catch (e) {
    console.log('[SettingsData] signOutTrakt error:', e);
  }
}

// ============================================
// Plex User Info
// ============================================

export async function getPlexUser(): Promise<any | null> {
  try {
    const core = getFlixorCore();
    // Access the internal plexToken to get user info
    const token = (core as any).plexToken;
    if (token) {
      return await core.plexAuth.getUser(token);
    }
    return null;
  } catch (e) {
    console.log('[SettingsData] getPlexUser error:', e);
    return null;
  }
}

// ============================================
// App Info
// ============================================

export function getAppVersion(): string {
  return '1.0.0';
}

export function getConnectedServerInfo(): { name: string; url: string } | null {
  try {
    const core = getFlixorCore();
    const server = core.server;
    const connection = core.connection;
    if (server && connection) {
      return {
        name: server.name,
        url: connection.uri,
      };
    }
    return null;
  } catch {
    return null;
  }
}

// ============================================
// Server Management
// ============================================

export interface PlexServerInfo {
  id: string;
  name: string;
  owned: boolean;
  accessToken: string;
  protocol: string;
  host: string;
  port: number;
  isActive: boolean;
  connections: PlexConnectionInfo[];
}

export interface PlexConnectionInfo {
  uri: string;
  protocol: string;
  local: boolean;
  relay: boolean;
  isCurrent: boolean;
  isPreferred: boolean;
}

export async function getPlexServers(): Promise<PlexServerInfo[]> {
  try {
    const core = getFlixorCore();
    const servers = await core.getPlexServers();
    const currentServerId = core.server?.id;
    const currentUri = core.connection?.uri;

    return servers.map((server) => {
      // Extract host/port from the first connection
      const firstConn = server.connections[0];
      let host = '';
      let port = 32400;
      let protocol = 'https';

      if (firstConn) {
        try {
          const url = new URL(firstConn.uri);
          host = url.hostname;
          port = parseInt(url.port) || 32400;
          protocol = url.protocol.replace(':', '');
        } catch {
          host = firstConn.uri;
        }
      }

      return {
        id: server.id,
        name: server.name,
        owned: server.owned,
        accessToken: server.accessToken,
        protocol,
        host,
        port,
        isActive: server.id === currentServerId,
        connections: server.connections.map((conn) => ({
          uri: conn.uri,
          protocol: conn.protocol,
          local: conn.local,
          relay: conn.relay,
          isCurrent: conn.uri === currentUri,
          isPreferred: conn.local && !conn.relay,
        })),
      };
    });
  } catch (e) {
    console.log('[SettingsData] getPlexServers error:', e);
    return [];
  }
}

export async function selectPlexServer(server: PlexServerInfo): Promise<void> {
  try {
    const core = getFlixorCore();
    const servers = await core.getPlexServers();
    const fullServer = servers.find((s) => s.id === server.id);
    if (!fullServer) {
      throw new Error('Server not found');
    }
    await core.connectToPlexServer(fullServer);
  } catch (e) {
    console.log('[SettingsData] selectPlexServer error:', e);
    throw e;
  }
}

export async function getServerConnections(serverId: string): Promise<PlexConnectionInfo[]> {
  try {
    const core = getFlixorCore();
    const servers = await core.getPlexServers();
    const server = servers.find((s) => s.id === serverId);
    if (!server) {
      return [];
    }

    const currentUri = core.connection?.uri;

    return server.connections.map((conn) => ({
      uri: conn.uri,
      protocol: conn.protocol,
      local: conn.local,
      relay: conn.relay,
      isCurrent: conn.uri === currentUri,
      isPreferred: conn.local && !conn.relay,
    }));
  } catch (e) {
    console.log('[SettingsData] getServerConnections error:', e);
    return [];
  }
}

export async function selectServerEndpoint(serverId: string, uri: string): Promise<void> {
  try {
    const core = getFlixorCore();
    const servers = await core.getPlexServers();
    const server = servers.find((s) => s.id === serverId);
    if (!server) {
      throw new Error('Server not found');
    }

    const connection = server.connections.find((c) => c.uri === uri);
    if (!connection) {
      throw new Error('Endpoint not found');
    }

    // Test the connection first
    const isValid = await core.plexAuth.testConnection(connection, server.accessToken);
    if (!isValid) {
      throw new Error('Endpoint unreachable');
    }

    // Connect using the specific connection
    // We need to manually set up the connection since FlixorCore auto-selects best
    // For now, we'll reconnect to the server which may pick a different endpoint
    // TODO: Add support for specific endpoint selection in FlixorCore
    await core.connectToPlexServer(server);
  } catch (e) {
    console.log('[SettingsData] selectServerEndpoint error:', e);
    throw e;
  }
}

// ============================================
// Settings State (stored locally since standalone)
// ============================================

const SETTINGS_KEY = 'flixor_app_settings';

export interface AppSettings {
  watchlistProvider: 'trakt' | 'plex';
  tmdbApiKey?: string; // Custom TMDB API key override
}

let cachedSettings: AppSettings = {
  watchlistProvider: 'trakt',
};

let settingsLoaded = false;

export async function loadAppSettings(): Promise<AppSettings> {
  try {
    const stored = await AsyncStorage.getItem(SETTINGS_KEY);
    if (stored) {
      cachedSettings = { ...cachedSettings, ...JSON.parse(stored) };
    }
    settingsLoaded = true;
  } catch (e) {
    console.log('[SettingsData] loadAppSettings error:', e);
  }
  return { ...cachedSettings };
}

export function getAppSettings(): AppSettings {
  return { ...cachedSettings };
}

export async function setAppSettings(settings: Partial<AppSettings>): Promise<void> {
  cachedSettings = { ...cachedSettings, ...settings };
  try {
    await AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(cachedSettings));
  } catch (e) {
    console.log('[SettingsData] setAppSettings error:', e);
  }
}

export async function getTmdbApiKey(): Promise<string | undefined> {
  if (!settingsLoaded) {
    await loadAppSettings();
  }
  return cachedSettings.tmdbApiKey;
}

export async function setTmdbApiKey(apiKey: string | undefined): Promise<void> {
  await setAppSettings({ tmdbApiKey: apiKey });
}
