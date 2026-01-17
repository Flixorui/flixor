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
  return 'Beta1.9.5';
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
  // Discovery mode - when true, disables all external data aggregation (TMDB, Trakt)
  discoveryDisabled: boolean;
  // MDBList settings
  mdblistEnabled: boolean; // Enable MDBList integration (disabled by default)
  mdblistApiKey?: string; // MDBList API key (required when enabled)
  // Overseerr settings
  overseerrEnabled: boolean; // Enable Overseerr integration (disabled by default)
  overseerrUrl?: string; // Overseerr server URL (e.g., https://overseerr.example.com)
  overseerrApiKey?: string; // Overseerr API key
  tmdbLanguagePreference: string;
  enrichMetadataWithTMDB: boolean;
  useTmdbLocalizedMetadata: boolean;
  episodeLayoutStyle: 'vertical' | 'horizontal';
  enableStreamsBackdrop: boolean;
  useCachedStreams: boolean;
  openMetadataScreenWhenCacheDisabled: boolean;
  streamCacheTTL: number;
  showHeroSection: boolean;
  showContinueWatchingRow: boolean;
  showTrendingRows: boolean;
  showTraktRows: boolean;
  showPlexPopularRow: boolean;
  showPosterTitles: boolean;
  posterSize: 'small' | 'medium' | 'large';
  posterBorderRadius: number;
  showLibraryTitles: boolean;
  heroLayout: 'legacy' | 'carousel' | 'appletv';
  continueWatchingLayout: 'poster' | 'landscape';
  enabledLibraryKeys?: string[];
  // Android-specific settings
  enableAndroidBlurView: boolean; // Enable blur effects on Android (may impact performance)
  // Details screen rating visibility settings
  showIMDbRating: boolean;
  showRottenTomatoesCritic: boolean;
  showRottenTomatoesAudience: boolean;
  // Details screen layout setting
  detailsScreenLayout: 'tabbed' | 'unified';
  // Tab bar settings
  showNewHotTab: boolean;
  // Search settings
  includeTmdbInSearch: boolean; // Include TMDB results in search
}

export const DEFAULT_APP_SETTINGS: AppSettings = {
  watchlistProvider: 'trakt',
  tmdbApiKey: undefined,
  // Discovery mode default (disabled = show discovery content)
  discoveryDisabled: false,
  // MDBList defaults
  mdblistEnabled: false,
  mdblistApiKey: undefined,
  // Overseerr defaults
  overseerrEnabled: false,
  overseerrUrl: undefined,
  overseerrApiKey: undefined,
  tmdbLanguagePreference: 'en',
  enrichMetadataWithTMDB: true,
  useTmdbLocalizedMetadata: false,
  episodeLayoutStyle: 'horizontal',
  enableStreamsBackdrop: true,
  useCachedStreams: false,
  openMetadataScreenWhenCacheDisabled: true,
  streamCacheTTL: 60 * 60 * 1000,
  showHeroSection: true,
  showContinueWatchingRow: true,
  showTrendingRows: true,
  showTraktRows: true,
  showPlexPopularRow: true,
  showPosterTitles: true,
  posterSize: 'medium',
  posterBorderRadius: 12,
  showLibraryTitles: true,
  heroLayout: 'carousel',
  continueWatchingLayout: 'landscape',
  enabledLibraryKeys: undefined,
  // Android-specific defaults
  enableAndroidBlurView: false, // Disabled by default for performance
  // Details screen rating visibility defaults
  showIMDbRating: true,
  showRottenTomatoesCritic: true,
  showRottenTomatoesAudience: true,
  // Details screen layout default
  detailsScreenLayout: 'tabbed',
  // Tab bar defaults
  showNewHotTab: true,
  // Search defaults
  includeTmdbInSearch: true,
};

let cachedSettings: AppSettings = { ...DEFAULT_APP_SETTINGS };

let settingsLoaded = false;

export async function loadAppSettings(): Promise<AppSettings> {
  try {
    const stored = await AsyncStorage.getItem(SETTINGS_KEY);
    if (stored) {
      cachedSettings = { ...DEFAULT_APP_SETTINGS, ...JSON.parse(stored) };
    } else {
      cachedSettings = { ...DEFAULT_APP_SETTINGS };
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

/**
 * Reset all settings to defaults and clear from storage.
 * Called during logout to ensure fresh state on next login.
 */
export async function resetAppSettings(): Promise<void> {
  cachedSettings = { ...DEFAULT_APP_SETTINGS };
  settingsLoaded = false;
  try {
    await AsyncStorage.removeItem(SETTINGS_KEY);
  } catch (e) {
    console.log('[SettingsData] resetAppSettings error:', e);
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

// MDBList helpers
export function isMdblistEnabled(): boolean {
  return cachedSettings.mdblistEnabled ?? false;
}

export async function setMdblistEnabled(enabled: boolean): Promise<void> {
  await setAppSettings({ mdblistEnabled: enabled });
}

export function getMdblistApiKey(): string | undefined {
  return cachedSettings.mdblistApiKey;
}

export async function setMdblistApiKey(apiKey: string | undefined): Promise<void> {
  await setAppSettings({ mdblistApiKey: apiKey });
}

// Overseerr helpers
export function isOverseerrEnabled(): boolean {
  return cachedSettings.overseerrEnabled ?? false;
}

export function getOverseerrUrl(): string | undefined {
  return cachedSettings.overseerrUrl;
}

export function getOverseerrApiKey(): string | undefined {
  return cachedSettings.overseerrApiKey;
}

export async function setOverseerrEnabled(enabled: boolean): Promise<void> {
  await setAppSettings({ overseerrEnabled: enabled });
}

export async function setOverseerrUrl(url: string | undefined): Promise<void> {
  await setAppSettings({ overseerrUrl: url });
}

export async function setOverseerrApiKey(apiKey: string | undefined): Promise<void> {
  await setAppSettings({ overseerrApiKey: apiKey });
}

// Discovery mode helpers
export function isDiscoveryDisabled(): boolean {
  return cachedSettings.discoveryDisabled ?? false;
}

/**
 * Set discovery disabled mode. When enabled, turns off all discovery-related settings:
 * - showTrendingRows
 * - showTraktRows
 * - showPlexPopularRow
 * - showNewHotTab
 * - includeTmdbInSearch
 */
export async function setDiscoveryDisabled(disabled: boolean): Promise<void> {
  if (disabled) {
    // Turn off all discovery features
    await setAppSettings({
      discoveryDisabled: true,
      showTrendingRows: false,
      showTraktRows: false,
      showPlexPopularRow: false,
      showNewHotTab: false,
      includeTmdbInSearch: false,
    });
  } else {
    // Just update the master toggle, don't change individual settings
    await setAppSettings({ discoveryDisabled: false });
  }
}
