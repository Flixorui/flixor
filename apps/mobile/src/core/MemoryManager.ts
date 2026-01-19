/**
 * Centralized memory management for the mobile app
 * Handles AppState changes and clears caches when app goes to background
 */

import { AppState, AppStateStatus } from 'react-native';
import FastImage from '@d11/react-native-fast-image';

class MemoryManager {
  private subscription: ReturnType<typeof AppState.addEventListener> | null = null;
  private initialized = false;

  /**
   * Initialize the memory manager - call this once at app startup
   */
  initialize() {
    if (this.initialized) return;
    this.initialized = true;

    this.subscription = AppState.addEventListener('change', this.handleAppStateChange);
    console.log('[MemoryManager] Initialized');
  }

  private handleAppStateChange = (nextAppState: AppStateStatus) => {
    if (nextAppState === 'background') {
      console.log('[MemoryManager] App going to background - clearing FastImage memory cache');
      FastImage.clearMemoryCache();
    }
  };

  /**
   * Cleanup the memory manager - call this on app unmount if needed
   */
  cleanup() {
    this.subscription?.remove();
    this.subscription = null;
    this.initialized = false;
    console.log('[MemoryManager] Cleaned up');
  }

  /**
   * Manually clear the image memory cache
   */
  clearImageCache() {
    FastImage.clearMemoryCache();
  }

  /**
   * Clear both memory and disk cache (use sparingly)
   */
  clearAllImageCaches() {
    FastImage.clearMemoryCache();
    FastImage.clearDiskCache();
  }

  /**
   * Clear both memory and disk cache (async version)
   */
  async clearAllImageCachesAsync(): Promise<void> {
    await FastImage.clearMemoryCache();
    await FastImage.clearDiskCache();
    console.log('[MemoryManager] All image caches cleared');
  }
}

export const memoryManager = new MemoryManager();

/**
 * Clear all application caches (images + API data)
 * Use this for the "Clear Cache" settings option
 */
export async function clearAllCaches(): Promise<void> {
  // Clear image caches
  await memoryManager.clearAllImageCachesAsync();

  // Clear API/data cache
  const { clearApiCache } = await import('./MobileCache');
  await clearApiCache();

  console.log('[MemoryManager] All caches cleared successfully');
}
