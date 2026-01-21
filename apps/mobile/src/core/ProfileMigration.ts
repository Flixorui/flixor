/**
 * Profile Migration Service
 *
 * Handles data migration when upgrading to profile support.
 *
 * Migration Strategy:
 * - Existing data stays as "main account" data (no key prefix)
 * - New profiles use prefixed keys: profile:{uuid}:{key}
 * - No data loss for existing users
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { GLOBAL_KEYS } from './ProfileStorage';

// Migration version tracking
const MIGRATION_VERSION_KEY = GLOBAL_KEYS.MIGRATION_VERSION;
const CURRENT_MIGRATION_VERSION = 2; // Version 2 = profile support

/**
 * Run all necessary migrations
 * Should be called early during app initialization, before FlixorCore init
 */
export async function runMigrations(): Promise<void> {
  try {
    const versionStr = await AsyncStorage.getItem(MIGRATION_VERSION_KEY);
    const currentVersion = versionStr ? parseInt(versionStr, 10) : 1;

    console.log(`[Migration] Current version: ${currentVersion}, Target: ${CURRENT_MIGRATION_VERSION}`);

    if (currentVersion < 2) {
      await migrateToProfileSupport();
    }

    // Save current migration version
    await AsyncStorage.setItem(MIGRATION_VERSION_KEY, String(CURRENT_MIGRATION_VERSION));
    console.log('[Migration] All migrations complete');
  } catch (e) {
    console.error('[Migration] Migration failed:', e);
    // Don't throw - app should still work, just might have issues
  }
}

/**
 * Migration from v1 (single user) to v2 (profile support)
 *
 * Strategy:
 * - Keep existing data in place (main account = no prefix)
 * - Clear any active profile state (shouldn't exist, but just in case)
 * - Future profiles will use prefixed keys
 */
async function migrateToProfileSupport(): Promise<void> {
  console.log('[Migration] Running migration to profile support v2');

  try {
    // Clear any stale active profile (shouldn't exist pre-migration)
    await AsyncStorage.removeItem(GLOBAL_KEYS.ACTIVE_PROFILE);

    // No need to modify existing data - main account uses un-prefixed keys
    // which is what existing data already uses

    console.log('[Migration] Profile support migration complete');
  } catch (e) {
    console.error('[Migration] migrateToProfileSupport error:', e);
    throw e;
  }
}

/**
 * Check if migration is needed
 * Useful for showing migration UI if needed
 */
export async function needsMigration(): Promise<boolean> {
  try {
    const versionStr = await AsyncStorage.getItem(MIGRATION_VERSION_KEY);
    const currentVersion = versionStr ? parseInt(versionStr, 10) : 1;
    return currentVersion < CURRENT_MIGRATION_VERSION;
  } catch {
    return true;
  }
}

/**
 * Get current migration version
 */
export async function getMigrationVersion(): Promise<number> {
  try {
    const versionStr = await AsyncStorage.getItem(MIGRATION_VERSION_KEY);
    return versionStr ? parseInt(versionStr, 10) : 1;
  } catch {
    return 1;
  }
}

/**
 * Clear all profile data (dangerous - use with caution)
 * This removes all profile-prefixed keys while keeping main account data
 */
export async function clearAllProfileData(): Promise<void> {
  console.log('[Migration] Clearing all profile data');

  try {
    const allKeys = await AsyncStorage.getAllKeys();
    const profileKeys = allKeys.filter((key) => key.includes('profile:'));

    if (profileKeys.length > 0) {
      await AsyncStorage.multiRemove(profileKeys);
      console.log(`[Migration] Removed ${profileKeys.length} profile keys`);
    }

    // Also clear active profile
    await AsyncStorage.removeItem(GLOBAL_KEYS.ACTIVE_PROFILE);
  } catch (e) {
    console.error('[Migration] clearAllProfileData error:', e);
    throw e;
  }
}
