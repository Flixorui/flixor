import { type ComponentType, useCallback, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { type AppSettings, loadSettings, saveSettings } from '@/state/settings';

export type SettingsPageProps = {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
};

/** Gives a settings page its own URL, supplying the props the hub used to pass down. */
export default function SettingsSubpage({ page: Page }: { page: ComponentType<SettingsPageProps> }) {
  const navigate = useNavigate();
  const [settings, setSettings] = useState<AppSettings>(loadSettings);

  const updateSetting = useCallback(<K extends keyof AppSettings>(key: K, value: AppSettings[K]) => {
    setSettings(saveSettings({ [key]: value }));
  }, []);

  return <Page settings={settings} updateSetting={updateSetting} onBack={() => navigate('/settings')} />;
}
