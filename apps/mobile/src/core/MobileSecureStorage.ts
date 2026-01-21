import type { ISecureStorage } from '@flixor/core';
import { getProfileKey, GLOBAL_KEYS } from './ProfileStorage';

// Note: In production, you should use expo-secure-store
// For now, we'll use a simple implementation that can be swapped later
// Install: npx expo install expo-secure-store

// import * as SecureStore from 'expo-secure-store';

const SECURE_PREFIX = 'secure:';

// Keys that should NOT be profile-scoped (shared across profiles)
const GLOBAL_SECURE_KEYS: Set<string> = new Set([
  GLOBAL_KEYS.PLEX_AUTH,  // plex_auth stores main token + current profile info
]);

/**
 * Mobile implementation of ISecureStorage
 *
 * Supports profile-scoped storage:
 * - Global keys (like plex_auth) are shared across profiles
 * - Other keys (like trakt_tokens) are scoped to the current profile
 *
 * TODO: Replace with expo-secure-store for production
 * This temporary implementation uses AsyncStorage (not secure!)
 */
export class MobileSecureStorage implements ISecureStorage {
  private AsyncStorage: typeof import('@react-native-async-storage/async-storage').default;

  constructor(asyncStorage: typeof import('@react-native-async-storage/async-storage').default) {
    this.AsyncStorage = asyncStorage;
    console.warn(
      '[MobileSecureStorage] Using AsyncStorage fallback. Install expo-secure-store for production.'
    );
  }

  /**
   * Get the storage key, applying profile scoping if appropriate
   */
  private getStorageKey(key: string): string {
    // Global keys are not profile-scoped
    if (GLOBAL_SECURE_KEYS.has(key)) {
      return SECURE_PREFIX + key;
    }
    // Other keys are profile-scoped
    return SECURE_PREFIX + getProfileKey(key);
  }

  async get<T>(key: string): Promise<T | null> {
    try {
      // TODO: Use SecureStore
      // const value = await SecureStore.getItemAsync(key);
      const value = await this.AsyncStorage.getItem(this.getStorageKey(key));
      if (value === null) return null;
      return JSON.parse(value) as T;
    } catch {
      return null;
    }
  }

  async set<T>(key: string, value: T): Promise<void> {
    // TODO: Use SecureStore
    // await SecureStore.setItemAsync(key, JSON.stringify(value));
    await this.AsyncStorage.setItem(this.getStorageKey(key), JSON.stringify(value));
  }

  async remove(key: string): Promise<void> {
    // TODO: Use SecureStore
    // await SecureStore.deleteItemAsync(key);
    await this.AsyncStorage.removeItem(this.getStorageKey(key));
  }
}
