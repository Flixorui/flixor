import { useState, useEffect, useMemo } from 'react';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { AppSettings } from '@/state/settings';
import { plexBackendLibraries } from '@/services/plex_backend';
import {
  ChevronBackIcon,
  CloudDownloadIcon,
  FilmIcon,
  TvIcon,
} from '@/components/ServiceIcons';

// Icon wrapper - matches mobile's 34x34 icon container
function IconWrap({ children }: { children: React.ReactNode }) {
  return (
    <div
      className="flex items-center justify-center w-[34px] h-[34px] rounded-[10px]"
      style={{ backgroundColor: 'rgba(229,231,235,0.08)' }}
    >
      {children}
    </div>
  );
}

type LibraryItem = { key: string; title: string; type: string };

interface CatalogSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function CatalogSettings({ settings, updateSetting, onBack }: CatalogSettingsProps) {
  const [libraries, setLibraries] = useState<LibraryItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      try {
        const libs: any = await plexBackendLibraries();
        const dirs = libs?.MediaContainer?.Directory || [];
        setLibraries(
          dirs
            .filter((d: any) => d.type === 'movie' || d.type === 'show')
            .map((d: any) => ({
              key: String(d.key),
              title: d.title,
              type: d.type,
            }))
        );
      } catch (e) {
        console.error('Failed to load libraries:', e);
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  // Get enabled library keys - stored as array, empty means all enabled
  const enabledLibraryKeys = (settings as any).enabledLibraryKeys as string[] | undefined;
  const enabledKeys = useMemo(() => new Set(enabledLibraryKeys || []), [enabledLibraryKeys]);
  const isDefaultAll = !enabledLibraryKeys || enabledLibraryKeys.length === 0;

  const updateEnabledKeys = (nextKeys: string[]) => {
    const allKeys = libraries.map((lib) => lib.key);
    const normalized = nextKeys.filter((key) => allKeys.includes(key));
    const shouldUseDefaultAll = normalized.length === 0 || normalized.length === allKeys.length;
    updateSetting('enabledLibraryKeys' as any, shouldUseDefaultAll ? [] : normalized);
  };

  const toggleLibrary = (key: string, enabled: boolean) => {
    const allKeys = libraries.map((lib) => lib.key);
    if (enabled) {
      const next = isDefaultAll ? allKeys : Array.from(new Set([...enabledKeys, key]));
      updateEnabledKeys(next);
    } else {
      const base = isDefaultAll ? allKeys : Array.from(enabledKeys);
      const next = base.filter((k) => k !== key);
      updateEnabledKeys(next);
    }
  };

  return (
    <div className="min-h-screen bg-[#0b0b0d] pb-20">
      {/* Header with back button */}
      <div className="px-4 pt-6 pb-4 flex items-center gap-3">
        <button
          onClick={onBack}
          className="flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors"
        >
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">Catalogs</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        <SettingsCard title="LIBRARIES">
          {loading && (
            <div className="flex items-center gap-2 px-[14px] py-[14px]">
              <CloudDownloadIcon size={18} color="#9ca3af" />
              <span className="text-[#9ca3af] text-[13px]">Loading libraries…</span>
            </div>
          )}
          {!loading && libraries.length === 0 && (
            <div className="flex items-center gap-2 px-[14px] py-[14px]">
              <span className="text-[#9ca3af] text-[13px]">No Plex libraries found.</span>
            </div>
          )}
          {!loading && libraries.map((lib, index) => {
            const enabled = isDefaultAll ? true : enabledKeys.has(lib.key);
            return (
              <SettingItem
                key={lib.key}
                title={lib.title}
                description={lib.type === 'movie' ? 'Movies' : 'TV Shows'}
                renderIcon={() => (
                  <IconWrap>
                    {lib.type === 'movie' ? (
                      <FilmIcon size={18} color="#e5e7eb" />
                    ) : (
                      <TvIcon size={18} color="#e5e7eb" />
                    )}
                  </IconWrap>
                )}
                renderRight={() => (
                  <SettingToggle
                    checked={enabled}
                    onChange={(v) => toggleLibrary(lib.key, v)}
                  />
                )}
                isLast={index === libraries.length - 1}
              />
            );
          })}
        </SettingsCard>

        <p className="text-[#9ca3af] text-xs mt-1.5 px-1">
          Disabled libraries are hidden from Browse and Library screens.
        </p>
      </div>
    </div>
  );
}
