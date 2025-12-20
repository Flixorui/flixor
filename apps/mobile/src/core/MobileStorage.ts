import AsyncStorage from '@react-native-async-storage/async-storage';
import type { IStorage } from '@flixor/core';

const STORAGE_PREFIX = 'flixor:';

/**
 * Mobile implementation of IStorage using AsyncStorage
 */
export class MobileStorage implements IStorage {
  async get<T>(key: string): Promise<T | null> {
    try {
      const value = await AsyncStorage.getItem(STORAGE_PREFIX + key);
      if (value === null) return null;
      return JSON.parse(value) as T;
    } catch {
      return null;
    }
  }

  async set<T>(key: string, value: T): Promise<void> {
    await AsyncStorage.setItem(STORAGE_PREFIX + key, JSON.stringify(value));
  }

  async remove(key: string): Promise<void> {
    await AsyncStorage.removeItem(STORAGE_PREFIX + key);
  }

  async clear(): Promise<void> {
    const keys = await AsyncStorage.getAllKeys();
    const prefixedKeys = keys.filter(k => k.startsWith(STORAGE_PREFIX));
    await AsyncStorage.multiRemove(prefixedKeys);
  }
}
