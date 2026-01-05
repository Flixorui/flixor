import { useCallback, useEffect, useState } from 'react';
import {
  DEFAULT_APP_SETTINGS,
  type AppSettings,
  loadAppSettings,
  setAppSettings,
} from '../core/SettingsData';

class SettingsEmitter {
  private listeners: Array<() => void> = [];

  addListener(listener: () => void) {
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== listener);
    };
  }

  emit() {
    this.listeners.forEach((listener) => listener());
  }
}

export const appSettingsEmitter = new SettingsEmitter();

export function useAppSettings() {
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_APP_SETTINGS);
  const [isLoaded, setIsLoaded] = useState(false);

  const refresh = useCallback(async () => {
    const next = await loadAppSettings();
    setSettings(next);
    setIsLoaded(true);
  }, []);

  useEffect(() => {
    refresh();
    const unsubscribe = appSettingsEmitter.addListener(refresh);
    return unsubscribe;
  }, [refresh]);

  const updateSetting = useCallback(
    async <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => {
      const next = { ...settings, [key]: value };
      setSettings(next);
      await setAppSettings({ [key]: value });
      appSettingsEmitter.emit();
    },
    [settings]
  );

  return {
    settings,
    updateSetting,
    isLoaded,
    refresh,
  };
}
