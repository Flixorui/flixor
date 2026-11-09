/**
 * Which content backbone the app runs on. macOS reference: Models/AppMode.swift
 *
 * `plex` is the original experience. `stremio` runs with no Plex account or server:
 * TMDB and Trakt supply discovery, Stremio addons supply streams.
 *
 * `null` means no mode has been chosen. Existing installs have no stored mode and
 * behave as Plex, so guard Plex-only work with `isStremioOnlyMode()`, not `isPlexMode()`.
 *
 * Not profile-scoped: profiles are keyed by Plex Home, and the mode decides whether
 * a Plex profile exists at all.
 */

import { useSyncExternalStore } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { GLOBAL_KEYS } from './ProfileStorage';
import { loadAppSettings, setAppSettings } from './SettingsData';

export type AppMode = 'plex' | 'stremio';

interface AppModeState {
  mode: AppMode | null;
  isLoaded: boolean;
}

let state: AppModeState = { mode: null, isLoaded: false };
const listeners = new Set<() => void>();

function update(next: AppModeState): void {
  state = next;
  listeners.forEach((listener) => listener());
}

export function addAppModeListener(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** Reads the stored mode. App.tsx calls this at startup. */
export async function loadAppMode(): Promise<AppMode | null> {
  try {
    const stored = await AsyncStorage.getItem(GLOBAL_KEYS.APP_MODE);
    update({ mode: stored === 'plex' || stored === 'stremio' ? stored : null, isLoaded: true });
  } catch (e) {
    console.log('[AppMode] loadAppMode error:', e);
    update({ mode: state.mode, isLoaded: true });
  }
  return state.mode;
}

/** The current mode. `null` until `loadAppMode` finishes or when none is chosen. */
export function getAppMode(): AppMode | null {
  return state.mode;
}

export function isAppModeLoaded(): boolean {
  return state.isLoaded;
}

/** True when running with no Plex. Skip Plex work entirely in this mode. */
export function isStremioOnlyMode(): boolean {
  return state.mode === 'stremio';
}

/** True only when Plex was explicitly chosen. Callers still need a connected server. */
export function isPlexMode(): boolean {
  return state.mode === 'plex';
}

export async function setAppMode(mode: AppMode): Promise<void> {
  await AsyncStorage.setItem(GLOBAL_KEYS.APP_MODE, mode);
  update({ mode, isLoaded: true });
  if (mode === 'stremio') {
    // Addons are the only source of playback and catalogs in this mode, so the opt-ins
    // have to be on. Load first: setAppSettings writes the whole cached object.
    await loadAppSettings();
    await setAppSettings({
      stremioPlaybackEnabled: true,
      showStremioCatalogRows: true,
      stremioCatalogSearchEnabled: true,
    });
  }
}

export async function clearAppMode(): Promise<void> {
  await AsyncStorage.removeItem(GLOBAL_KEYS.APP_MODE);
  update({ mode: null, isLoaded: true });
}

function getState(): AppModeState {
  return state;
}

export function useAppMode() {
  const { mode, isLoaded } = useSyncExternalStore(addAppModeListener, getState, getState);
  return {
    mode,
    isLoaded,
    isStremioOnly: mode === 'stremio',
    isPlexMode: mode === 'plex',
  };
}
