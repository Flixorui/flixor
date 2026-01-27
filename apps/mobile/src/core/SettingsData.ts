/**
 * Settings screen data fetchers using FlixorCore
 * Replaces the old api/client.ts functions for My/Settings screen
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { getFlixorCore } from './index';
import { getProfileKey, PROFILE_SCOPED_KEYS } from './ProfileStorage';

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
// Profile-scoped: each profile has separate settings
// ============================================

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
  overseerrAuthMethod: 'api_key' | 'plex'; // Authentication method
  overseerrApiKey?: string; // Overseerr API key (when using api_key auth)
  overseerrSessionCookie?: string; // Session cookie (when using plex auth)
  overseerrPlexUsername?: string; // Username from Plex auth (for display)
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
  showTraktContinueWatching: boolean; // Show Trakt Continue Watching row on home screen
  showPlexPopularRow: boolean;
  showCollectionRows: boolean; // Show Plex collections on home screen
  hiddenCollectionKeys: string[]; // Collection ratingKeys to hide from home screen
  showPosterTitles: boolean;
  posterSize: 'small' | 'medium' | 'large';
  posterBorderRadius: number;
  showLibraryTitles: boolean;
  heroLayout: 'legacy' | 'carousel' | 'appletv';
  continueWatchingLayout: 'poster' | 'landscape';
  enabledLibraryKeys?: string[];
  // Library mapping for Home screen pills
  moviesLibraryKey?: string; // User's preferred movie library for Movies pill
  showsLibraryKey?: string; // User's preferred TV shows library for Shows pill
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

  // Player settings
  autoPlayNext: boolean; // Auto-play next episode when current finishes
  skipIntroAutomatically: boolean; // Auto-skip detected intro segments
  skipCreditsAutomatically: boolean; // Auto-skip detected credits segments
  autoSkipDelay: number; // Seconds before auto-skipping (1-30)
  creditsCountdownFallback: number; // Seconds before end to show Next Episode when no credits marker (10-120)
  seekTimeSmall: number; // Small seek duration in seconds (1-120)
  seekTimeLarge: number; // Large seek duration in seconds (1-120)
  rememberTrackSelections: boolean; // Remember audio/subtitle language choices

  // Advanced settings
  enableDebugLogging: boolean; // Enable verbose debug logging

  // Download settings
  downloadOnWifiOnly: boolean; // Only download on WiFi
  maxConcurrentDownloads: number; // Max simultaneous downloads (1-3)
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
  overseerrAuthMethod: 'plex', // Default to Plex auth (simpler for users)
  overseerrApiKey: undefined,
  overseerrSessionCookie: undefined,
  overseerrPlexUsername: undefined,
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
  showTraktContinueWatching: false, // Disabled by default, users enable when they want Trakt sync
  showPlexPopularRow: true,
  showCollectionRows: true,
  hiddenCollectionKeys: [],
  showPosterTitles: true,
  posterSize: 'medium',
  posterBorderRadius: 12,
  showLibraryTitles: true,
  heroLayout: 'carousel',
  continueWatchingLayout: 'landscape',
  enabledLibraryKeys: undefined,
  // Library mapping defaults
  moviesLibraryKey: undefined, // Auto-select first movie library
  showsLibraryKey: undefined, // Auto-select first TV shows library
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

  // Player defaults (matching macOS)
  autoPlayNext: false, // Default: disabled (user must opt-in)
  skipIntroAutomatically: true, // Default: enabled
  skipCreditsAutomatically: true, // Default: enabled
  autoSkipDelay: 5, // Default: 5 seconds
  creditsCountdownFallback: 30, // Default: 30 seconds before end
  seekTimeSmall: 10, // Default: 10 seconds
  seekTimeLarge: 30, // Default: 30 seconds
  rememberTrackSelections: true, // Default: enabled

  // Advanced defaults
  enableDebugLogging: false, // Default: disabled

  // Download defaults
  downloadOnWifiOnly: true, // Default: only download on WiFi
  maxConcurrentDownloads: 1, // Default: 1 concurrent download
};

let cachedSettings: AppSettings = { ...DEFAULT_APP_SETTINGS };

let settingsLoaded = false;

// Simple event emitter for settings changes
type SettingsListener = () => void;
const settingsListeners: Set<SettingsListener> = new Set();

export function addSettingsListener(listener: SettingsListener): () => void {
  settingsListeners.add(listener);
  return () => settingsListeners.delete(listener);
}

function notifySettingsListeners(): void {
  settingsListeners.forEach((listener) => listener());
}

export async function loadAppSettings(): Promise<AppSettings> {
  try {
    // Use profile-scoped key for settings
    const storageKey = getProfileKey(PROFILE_SCOPED_KEYS.APP_SETTINGS);
    const stored = await AsyncStorage.getItem(storageKey);
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
    // Use profile-scoped key for settings
    const storageKey = getProfileKey(PROFILE_SCOPED_KEYS.APP_SETTINGS);
    await AsyncStorage.setItem(storageKey, JSON.stringify(cachedSettings));
    notifySettingsListeners();
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
    // Use profile-scoped key for settings
    const storageKey = getProfileKey(PROFILE_SCOPED_KEYS.APP_SETTINGS);
    await AsyncStorage.removeItem(storageKey);
  } catch (e) {
    console.log('[SettingsData] resetAppSettings error:', e);
  }
}

/**
 * Reset all settings to defaults with UI notification.
 * Used by the "Reset Settings" button in Advanced settings.
 */
export async function resetAllSettingsWithNotify(): Promise<void> {
  cachedSettings = { ...DEFAULT_APP_SETTINGS };
  settingsLoaded = true;
  try {
    // Use profile-scoped key for settings
    const storageKey = getProfileKey(PROFILE_SCOPED_KEYS.APP_SETTINGS);
    await AsyncStorage.removeItem(storageKey);
    notifySettingsListeners();
  } catch (e) {
    console.log('[SettingsData] resetAllSettingsWithNotify error:', e);
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

export function getOverseerrAuthMethod(): 'api_key' | 'plex' {
  return cachedSettings.overseerrAuthMethod ?? 'plex';
}

export function getOverseerrApiKey(): string | undefined {
  return cachedSettings.overseerrApiKey;
}

export function getOverseerrSessionCookie(): string | undefined {
  return cachedSettings.overseerrSessionCookie;
}

export function getOverseerrPlexUsername(): string | undefined {
  return cachedSettings.overseerrPlexUsername;
}

export async function setOverseerrEnabled(enabled: boolean): Promise<void> {
  await setAppSettings({ overseerrEnabled: enabled });
}

export async function setOverseerrUrl(url: string | undefined): Promise<void> {
  await setAppSettings({ overseerrUrl: url });
}

export async function setOverseerrAuthMethod(method: 'api_key' | 'plex'): Promise<void> {
  await setAppSettings({ overseerrAuthMethod: method });
}

export async function setOverseerrApiKey(apiKey: string | undefined): Promise<void> {
  await setAppSettings({ overseerrApiKey: apiKey });
}

export async function setOverseerrSessionCookie(cookie: string | undefined): Promise<void> {
  await setAppSettings({ overseerrSessionCookie: cookie });
}

export async function setOverseerrPlexUsername(username: string | undefined): Promise<void> {
  await setAppSettings({ overseerrPlexUsername: username });
}

export async function clearOverseerrAuth(): Promise<void> {
  await setAppSettings({
    overseerrApiKey: undefined,
    overseerrSessionCookie: undefined,
    overseerrPlexUsername: undefined,
  });
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

// Library mapping helpers
export function getMoviesLibraryKey(): string | undefined {
  return cachedSettings.moviesLibraryKey;
}

export async function setMoviesLibraryKey(key: string | undefined): Promise<void> {
  await setAppSettings({ moviesLibraryKey: key });
}

export function getShowsLibraryKey(): string | undefined {
  return cachedSettings.showsLibraryKey;
}

export async function setShowsLibraryKey(key: string | undefined): Promise<void> {
  await setAppSettings({ showsLibraryKey: key });
}

// Trakt Continue Watching helpers
export function isShowTraktContinueWatching(): boolean {
  return cachedSettings.showTraktContinueWatching ?? false;
}

export async function setShowTraktContinueWatching(enabled: boolean): Promise<void> {
  await setAppSettings({ showTraktContinueWatching: enabled });
}
