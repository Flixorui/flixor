import AsyncStorage from '@react-native-async-storage/async-storage';
import { FlixorCore } from '@flixor/core';
import { MobileStorage } from './MobileStorage';
import { MobileSecureStorage } from './MobileSecureStorage';
import { MobileCache } from './MobileCache';
import { loadAppSettings } from './SettingsData';

// Default API Keys - can be overridden by user in settings
const DEFAULT_TMDB_API_KEY = 'db55323b8d3e4154498498a75642b381';
const TRAKT_CLIENT_ID = '4ab0ead6d5510bf39180a5e1dd7b452f5ad700b7794564befdd6bca56e0f7ce4';
const TRAKT_CLIENT_SECRET = ''; // Add your Trakt client secret

// Generate or retrieve a persistent client ID
const CLIENT_ID_KEY = 'flixor_client_id';

async function getOrCreateClientId(): Promise<string> {
  let clientId = await AsyncStorage.getItem(CLIENT_ID_KEY);
  if (!clientId) {
    // Generate a UUID-like client identifier
    clientId =
      'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0;
        const v = c === 'x' ? r : (r & 0x3) | 0x8;
        return v.toString(16);
      });
    await AsyncStorage.setItem(CLIENT_ID_KEY, clientId);
  }
  return clientId;
}

// Singleton instance
let flixorCoreInstance: FlixorCore | null = null;

/**
 * Initialize and get the FlixorCore instance
 */
export async function initializeFlixorCore(): Promise<FlixorCore> {
  if (flixorCoreInstance) {
    return flixorCoreInstance;
  }

  const clientId = await getOrCreateClientId();

  // Load settings to get custom TMDB API key if set
  const settings = await loadAppSettings();
  const tmdbApiKey = settings.tmdbApiKey || DEFAULT_TMDB_API_KEY;
  const tmdbLanguage = settings.tmdbLanguagePreference
    ? settings.tmdbLanguagePreference.includes('-')
      ? settings.tmdbLanguagePreference
      : `${settings.tmdbLanguagePreference}-US`
    : 'en-US';

  const storage = new MobileStorage();
  const secureStorage = new MobileSecureStorage(AsyncStorage);
  const cache = new MobileCache();

  flixorCoreInstance = new FlixorCore({
    storage,
    secureStorage,
    cache,
    clientId,
    productName: 'Flixor',
    productVersion: '1.0.0',
    platform: 'iOS', // or detect dynamically
    deviceName: 'Flixor Mobile',
    tmdbApiKey: tmdbApiKey,
    traktClientId: TRAKT_CLIENT_ID,
    traktClientSecret: TRAKT_CLIENT_SECRET,
    language: tmdbLanguage,
  });

  // Initialize (restore sessions)
  await flixorCoreInstance.initialize();

  return flixorCoreInstance;
}

/**
 * Reinitialize FlixorCore with updated settings (e.g., new TMDB API key)
 * This clears the existing instance and creates a new one
 */
export async function reinitializeFlixorCore(): Promise<FlixorCore> {
  flixorCoreInstance = null;
  return initializeFlixorCore();
}

/**
 * Get the FlixorCore instance (must be initialized first)
 */
export function getFlixorCore(): FlixorCore {
  if (!flixorCoreInstance) {
    throw new Error('FlixorCore not initialized. Call initializeFlixorCore first.');
  }
  return flixorCoreInstance;
}

// Re-export for convenience
export { MobileStorage } from './MobileStorage';
export { MobileSecureStorage } from './MobileSecureStorage';
export { MobileCache } from './MobileCache';

// High-level mobile API
export {
  FlixorMobile,
  initializeFlixorMobile,
  getFlixorMobile,
  type MobileHomeData,
  type LibraryItemsResult,
} from './FlixorMobile';

// React Context and Hooks
export { FlixorProvider, useFlixor, useRequireFlixor } from './FlixorContext';
