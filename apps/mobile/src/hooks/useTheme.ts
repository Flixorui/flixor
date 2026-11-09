import { useSyncExternalStore } from 'react';
import { addSettingsListener, getAppSettings } from '../core/SettingsData';
import { resolveTheme, type FlixorTheme } from '../core/theme';

function getCurrentTheme(): FlixorTheme {
  const { accentPalette, pureBlack } = getAppSettings();
  return resolveTheme(accentPalette, pureBlack);
}

/**
 * The current profile's theme. Reads the in-memory settings, so it has no storage
 * cost per component and the first render already has the right colours once
 * settings have loaded. Re-renders only when the accent or background changes.
 */
export function useTheme(): FlixorTheme {
  return useSyncExternalStore(addSettingsListener, getCurrentTheme, getCurrentTheme);
}
