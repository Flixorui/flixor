/**
 * Profile-scoped storage utility
 *
 * This module manages profile context for storage operations.
 * When a profile is active, storage keys are automatically scoped to that profile.
 * Main account uses un-prefixed keys for backward compatibility.
 */

// Current active profile UUID (null = main account)
let currentProfileId: string | null = null;

/**
 * Set the current active profile
 * @param id - Profile UUID or null for main account
 */
export function setCurrentProfile(id: string | null): void {
  currentProfileId = id;
}

/**
 * Get the current active profile UUID
 * @returns Profile UUID or null if using main account
 */
export function getCurrentProfile(): string | null {
  return currentProfileId;
}

/**
 * Generate profile-scoped storage key
 * Main account uses original keys (no prefix) for backward compatibility.
 * Profiles use prefixed keys: `profile:{uuid}:{baseKey}`
 *
 * @param baseKey - Original storage key (e.g., 'flixor_app_settings')
 * @returns Scoped key (e.g., 'profile:abc123:flixor_app_settings')
 */
export function getProfileKey(baseKey: string): string {
  if (!currentProfileId) {
    return baseKey; // Main account uses original keys
  }
  return `profile:${currentProfileId}:${baseKey}`;
}

/**
 * Check if a key is profile-scoped
 * @param key - Storage key to check
 * @returns True if the key is profile-scoped
 */
export function isProfileScopedKey(key: string): boolean {
  return key.startsWith('profile:');
}

/**
 * Extract profile ID from a scoped key
 * @param key - Profile-scoped key
 * @returns Profile UUID or null if not a scoped key
 */
export function extractProfileId(key: string): string | null {
  if (!isProfileScopedKey(key)) {
    return null;
  }
  const parts = key.split(':');
  return parts.length >= 2 ? parts[1] : null;
}

/**
 * Storage keys that should be profile-scoped
 */
export const PROFILE_SCOPED_KEYS = {
  // App settings
  APP_SETTINGS: 'flixor_app_settings',

  // Secure storage keys
  TRAKT_TOKENS: 'trakt_tokens',

  // Note: plex_auth is handled specially - stores main token + profile info
} as const;

/**
 * Storage keys that are global (shared across profiles)
 */
export const GLOBAL_KEYS = {
  // Client identification
  CLIENT_ID: 'flixor_client_id',

  // Onboarding state
  ONBOARDING_COMPLETED: 'flixor_onboarding_completed',

  // Main Plex auth (contains main token + current profile info)
  PLEX_AUTH: 'plex_auth',

  // Active profile tracking
  ACTIVE_PROFILE: 'flixor_active_profile',

  // Migration version
  MIGRATION_VERSION: 'flixor_migration_version',
} as const;
