import { useSyncExternalStore } from 'react';
import { API_BASE_URL, apiClient } from '@/services/api';
import { forget } from '@/services/cache';
import { refreshPlexServers } from '@/services/plexServers';
import {
  ACTIVE_PROFILE_STORAGE_KEY,
  type ActiveProfile,
  clearAccountSettings,
  getActiveProfile,
  loadSettings,
  setActiveProfile,
} from '@/state/settings';

export type HomeProfile = {
  id: number;
  uuid: string;
  title: string;
  thumb?: string;
  restricted: boolean;
  protected: boolean;
  admin: boolean;
  guest: boolean;
  isMain: boolean;
};

export class ProfileSwitchError extends Error {
  code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

export function profileInitials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (words.length >= 2) return `${words[0][0]}${words[1][0]}`.toUpperCase();
  return (words[0] ?? '?').slice(0, 2).toUpperCase();
}

export async function fetchHomeProfiles(): Promise<{ users: HomeProfile[]; activeUuid: string | null }> {
  const res = await fetch(`${API_BASE_URL}/auth/profiles`, { credentials: 'include' });
  if (!res.ok) throw new Error(`Failed to load profiles (${res.status})`);
  return res.json();
}

/** Switches the session and this browser's settings, then restarts the app in the profile. */
export async function switchProfile(uuid: string, pin?: string): Promise<void> {
  const res = await fetch(`${API_BASE_URL}/auth/profiles/switch`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ uuid, pin, clientId: loadSettings().plexClientId }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new ProfileSwitchError(body.code || 'failed', body.message || 'Could not switch profiles');
  }

  setActiveProfile((body.profile as ActiveProfile | null) ?? null);
  forget('');
  try {
    await refreshPlexServers();
  } catch {
    // TopNav retries after the reload.
  }
  window.location.assign('/');
}

export async function signOut(): Promise<void> {
  await apiClient.logout();
  clearAccountSettings();
  forget('');
  window.location.href = '/login';
}

// Summary for the navigation bar. Loaded once per page load; switching reloads the page.
export type ProfileSummary = { name: string; thumb?: string; canSwitch: boolean; signedIn: boolean };

let summary: ProfileSummary = { name: getActiveProfile()?.title ?? 'Profile', thumb: getActiveProfile()?.thumb, canSwitch: false, signedIn: false };
const listeners = new Set<() => void>();

function setSummary(next: Partial<ProfileSummary>) {
  summary = { ...summary, ...next };
  listeners.forEach((listener) => listener());
}

export function useProfileSummary(): ProfileSummary {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    () => summary
  );
}

/**
 * Lines up this browser with the session: the session can change profile from
 * another tab, or have ended and been replaced. Reloads if the two disagree.
 */
async function loadSession() {
  const session = await apiClient.getSession();
  if (!session.authenticated) return;

  const sessionProfile: ActiveProfile | null = session.profile ?? null;
  if ((sessionProfile?.uuid ?? null) !== (getActiveProfile()?.uuid ?? null)) {
    setActiveProfile(sessionProfile);
    forget('');
    window.location.reload();
    return;
  }

  setSummary({
    signedIn: true,
    name: sessionProfile?.title || session.user?.username || 'Profile',
    thumb: sessionProfile?.thumb || session.user?.thumb,
  });
  try {
    const { users } = await fetchHomeProfiles();
    setSummary({ canSwitch: users.length > 1 });
  } catch {
    // Profile switching stays hidden until the list can be loaded.
  }
}

let initialized = false;

export function initProfiles() {
  if (initialized) return;
  initialized = true;
  // Another tab switched profile, and this tab's session changed with it.
  window.addEventListener('storage', (event) => {
    if (event.key === ACTIVE_PROFILE_STORAGE_KEY) window.location.reload();
  });
  loadSession().catch(() => {});
}
