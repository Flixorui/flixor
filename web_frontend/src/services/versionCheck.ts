import { APP_VERSION } from '@/version';
import { API_BASE_URL } from './api';

export interface UpdateInfo {
  hasUpdate: boolean;
  currentVersion: string;
  latestVersion: string;
  releaseNotes?: string;
  releaseUrl?: string;
}

// Check if an update is available (calls backend which caches the result)
export async function checkForUpdate(): Promise<UpdateInfo> {
  const result: UpdateInfo = {
    hasUpdate: false,
    currentVersion: APP_VERSION,
    latestVersion: APP_VERSION,
  };

  try {
    const response = await fetch(`${API_BASE_URL}/version`, {
      credentials: 'include',
      headers: { 'Accept': 'application/json' },
    });

    if (!response.ok) {
      console.warn('Version check failed:', response.status);
      return result;
    }

    const data = await response.json();

    result.currentVersion = data.current || APP_VERSION;
    result.latestVersion = data.latest || APP_VERSION;
    result.hasUpdate = data.hasUpdate || false;
    result.releaseNotes = data.releaseNotes;
    result.releaseUrl = data.releaseUrl;

    return result;
  } catch (error) {
    // Silently fail - backend might be unavailable
    console.debug('Version check failed:', error);
    return result;
  }
}

// Storage key for dismissed version
const DISMISSED_VERSION_KEY = 'flixor_dismissed_version';

// Check if user dismissed this version's update notification
export function isUpdateDismissed(version: string): boolean {
  try {
    return localStorage.getItem(DISMISSED_VERSION_KEY) === version;
  } catch {
    return false;
  }
}

// Dismiss update notification for a specific version
export function dismissUpdate(version: string): void {
  try {
    localStorage.setItem(DISMISSED_VERSION_KEY, version);
  } catch {}
}

// Clear dismissed version (e.g., when user updates)
export function clearDismissedUpdate(): void {
  try {
    localStorage.removeItem(DISMISSED_VERSION_KEY);
  } catch {}
}
