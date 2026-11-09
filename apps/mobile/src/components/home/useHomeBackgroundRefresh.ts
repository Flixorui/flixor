import { useCallback, useEffect, useRef } from 'react';
import { AppState } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';

const POLL_INTERVAL_MS = 30_000;
/** Regaining focus or the foreground only refetches data older than this. */
const STALE_AFTER_MS = 20_000;

/**
 * Keeps Home's changing rows fresh without a full reload. macOS reference:
 * HomeViewModel.pollDynamicRows.
 *
 * Runs only while Home is focused and the app is active. The Player is always pushed
 * over Home, so Home is unfocused for as long as it is playing and the row is
 * refreshed when the player closes.
 */
export function useHomeBackgroundRefresh(enabled: boolean, refresh: () => Promise<unknown>) {
  const refreshRef = useRef(refresh);
  refreshRef.current = refresh;
  const enabledRef = useRef(enabled);
  enabledRef.current = enabled;

  const focusedRef = useRef(false);
  const inFlightRef = useRef(false);
  const lastRefreshRef = useRef(Date.now());

  const refreshIfStale = useCallback(async () => {
    if (!enabledRef.current || !focusedRef.current || inFlightRef.current) return;
    if (AppState.currentState !== 'active') return;
    if (Date.now() - lastRefreshRef.current < STALE_AFTER_MS) return;

    inFlightRef.current = true;
    lastRefreshRef.current = Date.now();
    try {
      await refreshRef.current();
    } catch (e) {
      console.log('[Home] Background refresh failed:', e);
    } finally {
      inFlightRef.current = false;
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      focusedRef.current = true;
      refreshIfStale();
      const timer = setInterval(refreshIfStale, POLL_INTERVAL_MS);
      return () => {
        focusedRef.current = false;
        clearInterval(timer);
      };
    }, [refreshIfStale])
  );

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') refreshIfStale();
    });
    return () => subscription.remove();
  }, [refreshIfStale]);

  /** Marks the data out of date, and refreshes now if Home is showing. */
  return useCallback(() => {
    lastRefreshRef.current = 0;
    refreshIfStale();
  }, [refreshIfStale]);
}
