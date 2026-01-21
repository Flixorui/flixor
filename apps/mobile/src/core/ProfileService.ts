/**
 * Profile Management Service
 *
 * Handles Plex Home user profile switching with full data isolation.
 * Each profile has its own settings, cache, and service connections.
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import type { PlexHomeUser, ActiveProfile } from '@flixor/core';
import { getFlixorCore, reinitializeFlixorCore } from './index';
import { setCurrentProfile, GLOBAL_KEYS } from './ProfileStorage';
import { onProfileSwitch } from './MobileCache';
import { loadAppSettings } from './SettingsData';

// Re-export ActiveProfile type for convenience
export type { ActiveProfile } from '@flixor/core';

// Storage key for active profile (global, not profile-scoped)
const ACTIVE_PROFILE_KEY = GLOBAL_KEYS.ACTIVE_PROFILE;

/**
 * Get list of Plex Home users for the current account
 * Returns empty array if user is not part of a Plex Home
 */
export async function getHomeUsers(): Promise<PlexHomeUser[]> {
  try {
    const core = getFlixorCore();
    console.log('[ProfileService] Fetching home users...');
    const users = await core.getHomeUsers();
    console.log(`[ProfileService] Got ${users.length} home users`);
    return users;
  } catch (e) {
    console.log('[ProfileService] getHomeUsers error:', e);
    return [];
  }
}

/**
 * Check if the current user has a Plex Home with multiple users
 */
export async function hasPlexHome(): Promise<boolean> {
  const users = await getHomeUsers();
  console.log(`[ProfileService] hasPlexHome: found ${users.length} users`, users.map(u => u.title));
  return users.length > 0; // Show if ANY home users exist
}


/**
 * Get the currently active profile
 * Returns null if using the main account
 */
export async function getActiveProfile(): Promise<ActiveProfile | null> {
  try {
    const profileJson = await AsyncStorage.getItem(ACTIVE_PROFILE_KEY);
    if (!profileJson) {
      return null;
    }
    return JSON.parse(profileJson) as ActiveProfile;
  } catch (e) {
    console.log('[ProfileService] getActiveProfile error:', e);
    return null;
  }
}

/**
 * Store the active profile (internal use)
 */
async function saveActiveProfile(profile: ActiveProfile | null): Promise<void> {
  try {
    if (profile) {
      await AsyncStorage.setItem(ACTIVE_PROFILE_KEY, JSON.stringify(profile));
    } else {
      await AsyncStorage.removeItem(ACTIVE_PROFILE_KEY);
    }
  } catch (e) {
    console.log('[ProfileService] saveActiveProfile error:', e);
  }
}

/**
 * Switch to a Plex Home profile
 *
 * This will:
 * 1. Validate PIN if the profile is protected
 * 2. Get a new authentication token for the profile
 * 3. Switch the storage context to the profile
 * 4. Clear memory caches
 * 5. Load profile-specific settings
 *
 * @param user - The Plex Home user to switch to
 * @param pin - PIN if the user has one set (user.protected === true)
 * @throws Error if PIN is required but not provided, or PIN is invalid
 */
export async function switchProfile(
  user: PlexHomeUser,
  pin?: string
): Promise<void> {
  console.log(`[ProfileService] Switching to profile: ${user.title}`);

  // Validate PIN requirement
  if (user.protected && !pin) {
    throw new Error('PIN required for this profile');
  }

  try {
    // Get FlixorCore and switch profile
    const core = getFlixorCore();
    console.log(`[ProfileService] Calling core.switchToProfile for user uuid: ${user.uuid}`);
    await core.switchToProfile(user, pin);
    console.log(`[ProfileService] core.switchToProfile completed`);

    // Create ActiveProfile object
    const profile: ActiveProfile = {
      userId: user.id,
      uuid: user.uuid,
      title: user.title,
      thumb: user.thumb,
      restricted: user.restricted,
      protected: user.protected,
    };

    // Save active profile to global storage
    await saveActiveProfile(profile);

    // Switch storage context to this profile
    setCurrentProfile(user.uuid);

    // Clear memory caches (disk cache is per-profile)
    onProfileSwitch();

    // Reinitialize Trakt with new profile's tokens (storage context now set)
    await core.trakt.initialize();
    console.log(`[ProfileService] Reinitialized Trakt for profile: ${user.title}`);

    // Load profile-specific settings
    await loadAppSettings();

    console.log(`[ProfileService] Successfully switched to profile: ${user.title}`);
  } catch (e: any) {
    console.error('[ProfileService] switchProfile error:', e);
    throw e;
  }
}

/**
 * Switch back to the main account
 *
 * This will:
 * 1. Restore the main account token
 * 2. Clear the profile context
 * 3. Clear memory caches
 * 4. Load main account settings
 */
export async function switchToMainAccount(): Promise<void> {
  console.log('[ProfileService] Switching to main account');

  try {
    const core = getFlixorCore();
    await core.switchToMainAccount();

    // Clear active profile
    await saveActiveProfile(null);

    // Reset storage context to main account
    setCurrentProfile(null);

    // Clear memory caches
    onProfileSwitch();

    // Reinitialize Trakt with main account's tokens
    await core.trakt.initialize();
    console.log('[ProfileService] Reinitialized Trakt for main account');

    // Load main account settings
    await loadAppSettings();

    console.log('[ProfileService] Successfully switched to main account');
  } catch (e) {
    console.error('[ProfileService] switchToMainAccount error:', e);
    throw e;
  }
}

/**
 * Restore profile context on app startup
 * Called during app initialization to restore the previously active profile
 */
export async function restoreProfileContext(): Promise<void> {
  try {
    const profile = await getActiveProfile();
    if (profile) {
      // Restore storage context
      setCurrentProfile(profile.uuid);
      console.log(`[ProfileService] Restored profile context: ${profile.title}`);
    } else {
      setCurrentProfile(null);
      console.log('[ProfileService] Using main account');
    }
  } catch (e) {
    console.log('[ProfileService] restoreProfileContext error:', e);
    setCurrentProfile(null);
  }
}

/**
 * Get the display name for the current profile
 * Returns the main account username if no profile is active
 */
export async function getCurrentProfileName(): Promise<string> {
  const profile = await getActiveProfile();
  if (profile) {
    return profile.title;
  }

  // Get main account name
  try {
    const core = getFlixorCore();
    const mainToken = core.mainToken || (core as any).plexToken;
    if (mainToken) {
      const user = await core.plexAuth.getUser(mainToken);
      return user.username || user.title || 'Main Account';
    }
  } catch (e) {
    console.log('[ProfileService] getCurrentProfileName error:', e);
  }

  return 'Main Account';
}
