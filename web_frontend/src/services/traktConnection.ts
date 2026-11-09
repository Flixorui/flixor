/**
 * The old Trakt settings page kept tokens only in this browser, so the backend (which
 * every Trakt feature now uses) never received them. Those users have to connect once
 * more. Until they do, the browser's tokens must not count as a connection.
 */
import { API_BASE_URL } from './api';
import { showToast } from './toast';
import { loadSettings } from '@/state/settings';

const NEEDS_RECONNECT_KEY = 'flixor.trakt.needsReconnect.v1';
const TOAST_SHOWN_KEY = 'flixor.trakt.reconnectToastShown.v1';

function readFlag(key: string): boolean {
  try {
    return localStorage.getItem(key) === '1';
  } catch {
    return false;
  }
}

function writeFlag(key: string, on: boolean) {
  try {
    if (on) localStorage.setItem(key, '1');
    else localStorage.removeItem(key);
  } catch {
    // Storage blocked: the check simply runs again on the next load.
  }
}

export function traktNeedsReconnect(): boolean {
  return readFlag(NEEDS_RECONNECT_KEY);
}

function setNeedsReconnect(value: boolean) {
  if (value === traktNeedsReconnect()) return;
  writeFlag(NEEDS_RECONNECT_KEY, value);
  window.dispatchEvent(new CustomEvent('trakt-auth-changed'));
}

/** Call after a successful sign-in or sign-out. */
export function clearTraktReconnect() {
  setNeedsReconnect(false);
  writeFlag(TOAST_SHOWN_KEY, false);
}

/** Asks the backend whether it holds Trakt tokens, for browsers that have their own. */
export async function checkTraktConnection(): Promise<void> {
  const settings = loadSettings();
  if (!settings.traktAccessToken && !settings.traktTokens) return;
  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL.replace(/\/$/, '')}/trakt/users/me`, { credentials: 'include' });
  } catch {
    return; // Offline says nothing about the connection.
  }
  if (response.ok) {
    setNeedsReconnect(false);
    return;
  }
  if (response.status !== 401) return;
  // A 401 can also mean the Flixor session ended, which is not about Trakt.
  const body = await response.text().catch(() => '');
  if (!body.includes('Trakt not authenticated')) return;
  setNeedsReconnect(true);
  if (!readFlag(TOAST_SHOWN_KEY)) {
    writeFlag(TOAST_SHOWN_KEY, true);
    showToast('Trakt needs reconnecting. Open Settings > Trakt to turn syncing back on.', 'info', 8000);
  }
}
