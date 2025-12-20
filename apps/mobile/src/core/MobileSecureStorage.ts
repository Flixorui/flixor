import type { ISecureStorage } from '@flixor/core';

// Note: In production, you should use expo-secure-store
// For now, we'll use a simple implementation that can be swapped later
// Install: npx expo install expo-secure-store

// import * as SecureStore from 'expo-secure-store';

const SECURE_PREFIX = 'secure:';

/**
 * Mobile implementation of ISecureStorage
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

  async get<T>(key: string): Promise<T | null> {
    try {
      // TODO: Use SecureStore
      // const value = await SecureStore.getItemAsync(key);
      const value = await this.AsyncStorage.getItem(SECURE_PREFIX + key);
      if (value === null) return null;
      return JSON.parse(value) as T;
    } catch {
      return null;
    }
  }

  async set<T>(key: string, value: T): Promise<void> {
    // TODO: Use SecureStore
    // await SecureStore.setItemAsync(key, JSON.stringify(value));
    await this.AsyncStorage.setItem(SECURE_PREFIX + key, JSON.stringify(value));
  }

  async remove(key: string): Promise<void> {
    // TODO: Use SecureStore
    // await SecureStore.deleteItemAsync(key);
    await this.AsyncStorage.removeItem(SECURE_PREFIX + key);
  }
}
