import { createMMKV, type MMKV } from 'react-native-mmkv';
import type { ICache } from '@flixor/core';
import { getCurrentProfile } from './ProfileStorage';

const CACHE_PREFIX = 'cache:';
const CACHE_INDEX_KEY = 'cache_index';

// Map of MMKV storage instances per profile
// 'main' for main account, profile UUID for profiles
const storageInstances = new Map<string, MMKV>();

/**
 * Get MMKV storage instance for the current profile
 * Each profile has its own isolated cache storage
 */
function getStorage(): MMKV {
  const profileId = getCurrentProfile() || 'main';

  if (!storageInstances.has(profileId)) {
    // Create new MMKV instance for this profile
    const storage = createMMKV({ id: `flixor-cache-${profileId}` });
    storageInstances.set(profileId, storage);
  }

  return storageInstances.get(profileId)!;
}

interface CacheEntry<T> {
  data: T;
  timestamp: number;
  ttl: number;
}

const CACHE_LIMITS = {
  maxMemoryEntries: 100, // Reduced to 100 like NuvioStreaming
  maxDiskEntries: 100,   // Reduced to 100 like NuvioStreaming (was 400)
  maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days absolute max
  memoryTTL: 30000, // 30 seconds in-memory cache (like NuvioStreaming)
};

/**
 * Mobile implementation of ICache using MMKV + in-memory LRU
 * MMKV is 10x faster than AsyncStorage due to native implementation
 */
export class MobileCache implements ICache {
  private memoryCache = new Map<string, { entry: CacheEntry<unknown>; accessTime: number }>();
  private accessOrder: string[] = [];

  private isValid<T>(entry: CacheEntry<T>): boolean {
    const age = Date.now() - entry.timestamp;
    return age < entry.ttl && age < CACHE_LIMITS.maxAge;
  }

  private isMemoryCacheValid(accessTime: number): boolean {
    return Date.now() - accessTime < CACHE_LIMITS.memoryTTL;
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
    // 1. Check memory cache first (fastest path)
    const memEntry = this.memoryCache.get(key);
    if (memEntry && this.isMemoryCacheValid(memEntry.accessTime)) {
      const entry = memEntry.entry as CacheEntry<T>;
      if (this.isValid(entry)) {
        this.touchKey(key);
        return entry.data;
      }
      this.memoryCache.delete(key);
    }

    // 2. Check MMKV disk cache (synchronous, very fast)
    try {
      const raw = getStorage().getString(CACHE_PREFIX + key);
      if (!raw) return null;

      const entry: CacheEntry<T> = JSON.parse(raw);
      if (!this.isValid(entry)) {
        getStorage().remove(CACHE_PREFIX + key);
        return null;
      }

      // Promote to memory cache with current access time
      this.memoryCache.set(key, { entry, accessTime: Date.now() });
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

    // Memory cache with access time
    this.memoryCache.set(key, { entry, accessTime: Date.now() });
    this.touchKey(key);
    this.evictIfNeeded();

    // Disk cache (MMKV is synchronous but we keep async interface for compatibility)
    try {
      getStorage().set(CACHE_PREFIX + key, JSON.stringify(entry));
      this.updateCacheIndex(key);
    } catch (e) {
      console.error('[MobileCache] Failed to write to disk:', e);
    }
  }

  private updateCacheIndex(key: string) {
    try {
      const indexRaw = getStorage().getString(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      if (!index.includes(key)) {
        index.push(key);
      }

      // Limit disk cache entries with LRU eviction
      while (index.length > CACHE_LIMITS.maxDiskEntries) {
        const oldKey = index.shift();
        if (oldKey) {
          getStorage().remove(CACHE_PREFIX + oldKey);
        }
      }

      getStorage().set(CACHE_INDEX_KEY, JSON.stringify(index));
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
    getStorage().remove(CACHE_PREFIX + key);
  }

  // Alias for backwards compatibility
  async invalidate(key: string): Promise<void> {
    return this.remove(key);
  }

  async invalidatePattern(pattern: string): Promise<void> {
    // Convert glob pattern to regex-like matching
    const regexPattern = pattern
      .replace(/[.+^${}()|[\]\\]/g, '\\$&')
      .replace(/\*/g, '.*');
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
      const indexRaw = getStorage().getString(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      for (const key of index) {
        if (regex.test(key)) {
          getStorage().remove(CACHE_PREFIX + key);
        }
      }

      // Update index
      const newIndex = index.filter((key) => !regex.test(key));
      getStorage().set(CACHE_INDEX_KEY, JSON.stringify(newIndex));
    } catch (e) {
      console.error('[MobileCache] Failed to invalidate pattern:', e);
    }
  }

  async clear(): Promise<void> {
    this.memoryCache.clear();
    this.accessOrder = [];

    try {
      const indexRaw = getStorage().getString(CACHE_INDEX_KEY);
      const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];

      for (const key of index) {
        getStorage().remove(CACHE_PREFIX + key);
      }
      getStorage().remove(CACHE_INDEX_KEY);
    } catch (e) {
      console.error('[MobileCache] Failed to clear cache:', e);
    }
  }

  // New: Get cache stats for debugging
  getStats() {
    const indexRaw = getStorage().getString(CACHE_INDEX_KEY);
    const index: string[] = indexRaw ? JSON.parse(indexRaw) : [];
    return {
      memoryEntries: this.memoryCache.size,
      diskEntries: index.length,
      memoryLimit: CACHE_LIMITS.maxMemoryEntries,
      diskLimit: CACHE_LIMITS.maxDiskEntries,
    };
  }

  /**
   * Clear in-memory cache only (called when switching profiles)
   * Disk cache is already per-profile via getStorage()
   */
  clearMemoryCache(): void {
    this.memoryCache.clear();
    this.accessOrder = [];
  }
}

// Singleton instance for direct access (used by clearAllCaches)
let sharedCacheInstance: MobileCache | null = null;

export function getSharedCache(): MobileCache {
  if (!sharedCacheInstance) {
    sharedCacheInstance = new MobileCache();
  }
  return sharedCacheInstance;
}

/**
 * Clear all cached data (API responses, etc.)
 * Does not clear image cache - use clearAllCachesIncludingImages for that
 */
export async function clearApiCache(): Promise<void> {
  const cache = getSharedCache();
  await cache.clear();
  console.log('[MobileCache] API cache cleared');
}

/**
 * Called when switching profiles
 * Clears in-memory cache since disk cache is per-profile
 */
export function onProfileSwitch(): void {
  const cache = getSharedCache();
  cache.clearMemoryCache();
  console.log('[MobileCache] Memory cache cleared for profile switch');
}
