import AsyncStorage from '@react-native-async-storage/async-storage';
import type { ICache } from '@flixor/core';

const CACHE_PREFIX = 'cache:';
const CACHE_INDEX_KEY = 'cache_index';

interface CacheEntry<T> {
  data: T;
  timestamp: number;
  ttl: number;
}

const CACHE_LIMITS = {
  maxMemoryEntries: 200,
  maxDiskEntries: 400,
  maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days absolute max
};

/**
 * Mobile implementation of ICache using AsyncStorage + in-memory LRU
 */
export class MobileCache implements ICache {
  private memoryCache = new Map<string, CacheEntry<unknown>>();
  private accessOrder: string[] = [];

  private isValid<T>(entry: CacheEntry<T>): boolean {
    const age = Date.now() - entry.timestamp;
    return age < entry.ttl && age < CACHE_LIMITS.maxAge;
  }

  private touchKey(key: string) {
    const idx = this.accessOrder.indexOf(key);
    if (idx > -1) {
      this.accessOrder.splice(idx, 1);
    }
    this.accessOrder.push(key);
  }

  private evictIfNeeded() {
    while (this.memoryCache.size > CACHE_LIMITS.maxMemoryEntries) {
      const oldestKey = this.accessOrder.shift();
      if (oldestKey) {
        this.memoryCache.delete(oldestKey);
      }
    }
  }

  async get<T>(key: string): Promise<T | null> {
    // 1. Check memory cache
    const memEntry = this.memoryCache.get(key) as CacheEntry<T> | undefined;
    if (memEntry) {
      if (this.isValid(memEntry)) {
        this.touchKey(key);
        return memEntry.data;
      }
      this.memoryCache.delete(key);
    }

    // 2. Check disk cache
    try {
      const raw = await AsyncStorage.getItem(CACHE_PREFIX + key);
      if (!raw) return null;

      const entry: CacheEntry<T> = JSON.parse(raw);
      if (!this.isValid(entry)) {
        await AsyncStorage.removeItem(CACHE_PREFIX + key);
        return null;
      }

      // Promote to memory cache
      this.memoryCache.set(key, entry);
      this.touchKey(key);
      this.evictIfNeeded();

      return entry.data;
    } catch {
      return null;
    }
  }

  async set<T>(key: string, value: T, ttlMs: number): Promise<void> {
    const entry: CacheEntry<T> = {
      data: value,
      timestamp: Date.now(),
      ttl: ttlMs,
    };

    // Memory cache
    this.memoryCache.set(key, entry);
    this.touchKey(key);
    this.evictIfNeeded();

    // Disk cache
    try {
      await AsyncStorage.setItem(CACHE_PREFIX + key, JSON.stringify(entry));
      await this.updateCacheIndex(key);
    } catch (e) {
      console.error('[MobileCache] Failed to write to disk:', e);
    }
  }

  private async updateCacheIndex(key: string) {
    try {
      const indexRaw = await AsyncStorage.getItem(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      if (!index.includes(key)) {
        index.push(key);
      }

      // Limit disk cache entries
      while (index.length > CACHE_LIMITS.maxDiskEntries) {
        const oldKey = index.shift();
        if (oldKey) {
          await AsyncStorage.removeItem(CACHE_PREFIX + oldKey);
        }
      }

      await AsyncStorage.setItem(CACHE_INDEX_KEY, JSON.stringify(index));
    } catch (e) {
      console.error('[MobileCache] Failed to update index:', e);
    }
  }

  async remove(key: string): Promise<void> {
    this.memoryCache.delete(key);
    const idx = this.accessOrder.indexOf(key);
    if (idx > -1) {
      this.accessOrder.splice(idx, 1);
    }
    await AsyncStorage.removeItem(CACHE_PREFIX + key);
  }

  // Alias for backwards compatibility
  async invalidate(key: string): Promise<void> {
    return this.remove(key);
  }

  async invalidatePattern(pattern: string): Promise<void> {
    // Convert glob pattern to regex-like matching
    // e.g., "plex:*" matches "plex:anything"
    const regexPattern = pattern
      .replace(/[.+^${}()|[\]\\]/g, '\\$&') // Escape special regex chars
      .replace(/\*/g, '.*'); // Convert * to .*
    const regex = new RegExp(`^${regexPattern}$`);

    // Memory
    const keysToDelete: string[] = [];
    this.memoryCache.forEach((_, key) => {
      if (regex.test(key)) {
        keysToDelete.push(key);
      }
    });
    keysToDelete.forEach((key) => {
      this.memoryCache.delete(key);
      const idx = this.accessOrder.indexOf(key);
      if (idx > -1) {
        this.accessOrder.splice(idx, 1);
      }
    });

    // Disk
    try {
      const indexRaw = await AsyncStorage.getItem(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      for (const key of index) {
        if (regex.test(key)) {
          await AsyncStorage.removeItem(CACHE_PREFIX + key);
        }
      }

      // Update index
      const newIndex = index.filter((key) => !regex.test(key));
      await AsyncStorage.setItem(CACHE_INDEX_KEY, JSON.stringify(newIndex));
    } catch (e) {
      console.error('[MobileCache] Failed to invalidate pattern:', e);
    }
  }

  async clear(): Promise<void> {
    this.memoryCache.clear();
    this.accessOrder = [];

    try {
      const indexRaw = await AsyncStorage.getItem(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      for (const key of index) {
        await AsyncStorage.removeItem(CACHE_PREFIX + key);
      }
      await AsyncStorage.removeItem(CACHE_INDEX_KEY);
    } catch (e) {
      console.error('[MobileCache] Failed to clear cache:', e);
    }
  }
}
