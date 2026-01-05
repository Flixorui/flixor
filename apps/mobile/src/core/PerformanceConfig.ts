/**
 * Performance configuration constants for the mobile app
 * Implements NuvioStreaming-style optimizations with platform-aware limits
 */

import { Platform } from 'react-native';

// Platform-aware item limits (Android has more memory constraints)
export const ITEM_LIMITS = {
  ROW: Platform.OS === 'android' ? 18 : 30,
  TRENDING: Platform.OS === 'android' ? 10 : 12,
  HERO: Platform.OS === 'android' ? 6 : 8,
  GRID_PAGE: Platform.OS === 'android' ? 30 : 40,
};

// Image preload configuration
export const IMAGE_PRELOAD_CAP = Platform.OS === 'android' ? 8 : 12;

// Scroll throttling (ms)
export const SCROLL_DEBOUNCE_MS = 120;

// Cache TTLs (ms)
export const CACHE_TTL = {
  TRENDING: 5 * 60 * 1000,     // 5 minutes
  LIBRARY: 10 * 60 * 1000,     // 10 minutes
  SEARCH: 5 * 60 * 1000,       // 5 minutes
  NEW_HOT: 5 * 60 * 1000,      // 5 minutes
  MY_LIST: 5 * 60 * 1000,      // 5 minutes
  COLLECTIONS: 10 * 60 * 1000, // 10 minutes
};

// Scroll delta thresholds for header show/hide
export const SCROLL_DELTA_THRESHOLD = 6;

// Helper to check if cache is still valid
export function isCacheValid(lastFetchTime: number, ttl: number): boolean {
  return Date.now() - lastFetchTime < ttl;
}
