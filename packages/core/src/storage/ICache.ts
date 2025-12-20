/**
 * Interface for cached data with TTL support.
 * Platform implementations:
 * - Mobile: expo-sqlite
 * - Web: IndexedDB
 * - Native: SQLite/GRDB
 */
export interface ICache {
  get<T>(key: string): Promise<T | null>;
  set<T>(key: string, value: T, ttlSeconds: number): Promise<void>;
  remove(key: string): Promise<void>;
  clear(): Promise<void>;
  invalidatePattern(pattern: string): Promise<void>;
}

/**
 * TTL presets for different data types
 */
export const CacheTTL = {
  /** Static data that rarely changes (24 hours) */
  STATIC: 86400,
  /** Semi-static data like trending (1 hour) */
  TRENDING: 3600,
  /** Dynamic data (5 minutes) */
  DYNAMIC: 300,
  /** Very short-lived data (1 minute) */
  SHORT: 60,
  /** No caching */
  NONE: 0,
} as const;
