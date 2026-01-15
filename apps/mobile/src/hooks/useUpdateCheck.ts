/**
 * useUpdateCheck - Hook for managing OTA update UI state
 *
 * Provides update checking, downloading, and user preference management
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import UpdateService, { type UpdateInfo } from '../core/UpdateService';

const STORAGE_KEYS = {
  DISMISSED_UPDATE_ID: 'flixor:update_dismissed_id',
  UPDATE_LATER_TIMESTAMP: 'flixor:update_later_ts',
  OTA_ALERTS_ENABLED: 'flixor:ota_alerts_enabled',
  LAST_CHECK_TIMESTAMP: 'flixor:update_last_check_ts',
};

// Snooze duration when user chooses "Later" (6 hours)
const LATER_SNOOZE_MS = 6 * 60 * 60 * 1000;
// Minimum time between checks (5 minutes) - reduced to allow more frequent checks
const MIN_CHECK_INTERVAL_MS = 5 * 60 * 1000;
// Delay before showing popup after app startup
const STARTUP_DELAY_MS = 3000;

export interface UseUpdateCheckResult {
  /** Whether an update is available and should be shown */
  isUpdateAvailable: boolean;
  /** Whether update is currently downloading */
  isDownloading: boolean;
  /** Update manifest and metadata */
  updateInfo: UpdateInfo | null;
  /** Manually trigger update check */
  checkForUpdate: () => Promise<void>;
  /** Download and apply update (reloads app) */
  applyUpdate: () => Promise<void>;
  /** Dismiss this specific update version */
  dismissUpdate: () => Promise<void>;
  /** Snooze update for 6 hours */
  snoozeUpdate: () => Promise<void>;
  /** Whether OTA alerts are enabled */
  alertsEnabled: boolean;
  /** Toggle OTA alerts preference */
  setAlertsEnabled: (enabled: boolean) => Promise<void>;
}

export function useUpdateCheck(): UseUpdateCheckResult {
  const [isUpdateAvailable, setIsUpdateAvailable] = useState(false);
  const [isDownloading, setIsDownloading] = useState(false);
  const [updateInfo, setUpdateInfo] = useState<UpdateInfo | null>(null);
  const [alertsEnabled, setAlertsEnabledState] = useState(true);
  const isChecking = useRef(false);

  // Load preferences on mount
  useEffect(() => {
    const loadPreferences = async () => {
      try {
        const enabled = await AsyncStorage.getItem(STORAGE_KEYS.OTA_ALERTS_ENABLED);
        if (enabled !== null) {
          setAlertsEnabledState(enabled === 'true');
        }
      } catch (error) {
        console.error('Failed to load OTA preferences:', error);
      }
    };
    loadPreferences();
  }, []);

  const shouldShowUpdate = useCallback(
    async (manifest: any): Promise<boolean> => {
      console.log('[useUpdateCheck] shouldShowUpdate called, alertsEnabled:', alertsEnabled);
      if (!alertsEnabled) {
        console.log('[useUpdateCheck] Alerts disabled, not showing');
        return false;
      }

      try {
        // Check if this update was dismissed
        const dismissedId = await AsyncStorage.getItem(STORAGE_KEYS.DISMISSED_UPDATE_ID);
        console.log('[useUpdateCheck] Dismissed ID:', dismissedId, 'Manifest ID:', manifest?.id);
        if (dismissedId === manifest?.id) {
          console.log('[useUpdateCheck] Update was dismissed');
          return false;
        }

        // Check if user chose "later" and we're still in snooze period
        const laterTs = await AsyncStorage.getItem(STORAGE_KEYS.UPDATE_LATER_TIMESTAMP);
        if (laterTs) {
          const snoozedAt = parseInt(laterTs, 10);
          const remaining = LATER_SNOOZE_MS - (Date.now() - snoozedAt);
          console.log('[useUpdateCheck] Snooze remaining:', Math.round(remaining / 1000 / 60), 'minutes');
          if (remaining > 0) {
            console.log('[useUpdateCheck] Still snoozed');
            return false;
          }
        }

        console.log('[useUpdateCheck] Should show update: true');
        return true;
      } catch (error) {
        console.error('Failed to check update preferences:', error);
        return true; // Default to showing on error
      }
    },
    [alertsEnabled]
  );

  const checkForUpdate = useCallback(async (force: boolean = false) => {
    if (isChecking.current) return;

    try {
      isChecking.current = true;

      // Check if enough time has passed since last check (skip if force)
      if (!force) {
        const lastCheck = await AsyncStorage.getItem(STORAGE_KEYS.LAST_CHECK_TIMESTAMP);
        if (lastCheck) {
          const lastCheckTime = parseInt(lastCheck, 10);
          if (Date.now() - lastCheckTime < MIN_CHECK_INTERVAL_MS) {
            console.log('[useUpdateCheck] Skipping check - too recent');
            return;
          }
        }
      }

      const service = UpdateService.getInstance();
      // Use forceCheckForUpdates to bypass expo-updates caching
      const result = await service.forceCheckForUpdates();

      // Record check timestamp
      await AsyncStorage.setItem(
        STORAGE_KEYS.LAST_CHECK_TIMESTAMP,
        Date.now().toString()
      );

      if (result.isAvailable && result.manifest) {
        const shouldShow = await shouldShowUpdate(result.manifest);
        if (shouldShow) {
          setUpdateInfo(result);
          setIsUpdateAvailable(true);
        }
      }
    } catch (error) {
      console.error('[useUpdateCheck] Check failed:', error);
    } finally {
      isChecking.current = false;
    }
  }, [shouldShowUpdate]);

  const applyUpdate = useCallback(async () => {
    setIsDownloading(true);
    try {
      const service = UpdateService.getInstance();
      await service.downloadAndApply();
      // If we get here, reload didn't happen (no update available)
      setIsDownloading(false);
    } catch (error) {
      console.error('[useUpdateCheck] Apply failed:', error);
      setIsDownloading(false);
    }
  }, []);

  const dismissUpdate = useCallback(async () => {
    if (updateInfo?.manifest?.id) {
      await AsyncStorage.setItem(
        STORAGE_KEYS.DISMISSED_UPDATE_ID,
        updateInfo.manifest.id
      );
    }
    setIsUpdateAvailable(false);
    setUpdateInfo(null);
  }, [updateInfo]);

  const snoozeUpdate = useCallback(async () => {
    await AsyncStorage.setItem(
      STORAGE_KEYS.UPDATE_LATER_TIMESTAMP,
      Date.now().toString()
    );
    setIsUpdateAvailable(false);
  }, []);

  const setAlertsEnabled = useCallback(async (enabled: boolean) => {
    setAlertsEnabledState(enabled);
    await AsyncStorage.setItem(
      STORAGE_KEYS.OTA_ALERTS_ENABLED,
      enabled.toString()
    );
    if (!enabled) {
      setIsUpdateAvailable(false);
    }
  }, []);

  // Auto-check on mount with delay - always force check on app launch
  useEffect(() => {
    if (!alertsEnabled) return;

    const timeout = setTimeout(() => {
      checkForUpdate(true); // Force check on app launch, bypass rate limit
    }, STARTUP_DELAY_MS);

    return () => clearTimeout(timeout);
  }, [alertsEnabled, checkForUpdate]);

  return {
    isUpdateAvailable,
    isDownloading,
    updateInfo,
    checkForUpdate,
    applyUpdate,
    dismissUpdate,
    snoozeUpdate,
    alertsEnabled,
    setAlertsEnabled,
  };
}
