import { useState, useMemo } from 'react';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { AppSettings } from '@/state/settings';
import {
  TMDBIcon,
  ChevronBackIcon,
  FilmIcon,
  LanguageIcon,
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

const LANGUAGE_OPTIONS = [
  { label: 'English', value: 'en' },
  { label: 'Spanish', value: 'es' },
  { label: 'French', value: 'fr' },
  { label: 'German', value: 'de' },
  { label: 'Japanese', value: 'ja' },
];

interface TMDBSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function TMDBSettings({ settings, updateSetting, onBack }: TMDBSettingsProps) {
  const [apiKey, setApiKey] = useState((settings as any).tmdbApiKey || '');
  const hasKey = useMemo(() => apiKey.trim().length > 0, [apiKey]);

  // Cast for settings not in AppSettings type
  const enrichMetadataWithTMDB = (settings as any).enrichMetadataWithTMDB ?? true;
  const useTmdbLocalizedMetadata = (settings as any).useTmdbLocalizedMetadata ?? false;
  const tmdbLanguagePreference = (settings as any).tmdbLanguagePreference ?? 'en';

  const saveKey = () => {
    const trimmed = apiKey.trim();
    updateSetting('tmdbApiKey' as any, trimmed.length ? trimmed : undefined);
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
        <h1 className="text-white text-xl font-bold">TMDB</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* Logo Header */}
        <div className="flex flex-col items-center mb-5 py-4">
          <div
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ backgroundColor: 'rgba(1, 180, 228, 0.1)' }}
          >
            <TMDBIcon size={32} color="#01b4e4" />
          </div>
          <span className="text-white text-lg font-bold">The Movie Database</span>
          <span className="text-[#9ca3af] text-[13px] mt-1">Metadata and artwork provider</span>
        </div>

        {/* API Key */}
        <SettingsCard title="API KEY">
          <div className="p-3.5 space-y-2.5">
            <input
              type="text"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="Enter your TMDB API key"
              className={`
                w-full bg-white/[0.06] border border-white/[0.08] rounded-[10px]
                px-3 py-2.5 text-white text-sm placeholder:text-[#6b7280]
                focus:outline-none focus:ring-2 focus:ring-white/20
              `}
            />
            <button
              onClick={saveKey}
              className="w-full py-2.5 rounded-[10px] font-bold text-sm bg-white text-[#0b0b0d] hover:bg-white/90 transition-colors"
            >
              {hasKey ? 'Save Key' : 'Clear Key'}
            </button>
          </div>
          <p className="px-3.5 pb-3 text-[#9ca3af] text-xs">
            Leave empty to use the default app key.
          </p>
        </SettingsCard>

        {/* Metadata */}
        <SettingsCard title="METADATA">
          <SettingItem
            title="Enrich Metadata"
            description="Fetch cast, logos, and extras"
            renderIcon={() => <IconWrap><FilmIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={enrichMetadataWithTMDB}
                onChange={(v) => updateSetting('enrichMetadataWithTMDB' as any, v)}
              />
            )}
          />
          <SettingItem
            title="Localized Metadata"
            description="Prefer localized titles and summaries"
            renderIcon={() => <IconWrap><LanguageIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={useTmdbLocalizedMetadata}
                onChange={(v) => updateSetting('useTmdbLocalizedMetadata' as any, v)}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* Language */}
        <SettingsCard title="LANGUAGE">
          <div className="flex flex-wrap gap-2 p-3.5">
            {LANGUAGE_OPTIONS.map((option) => {
              const selected = tmdbLanguagePreference === option.value;
              return (
                <button
                  key={option.value}
                  onClick={() => updateSetting('tmdbLanguagePreference' as any, option.value)}
                  className={`
                    px-3 py-2 rounded-[10px] border text-xs font-semibold transition-all
                    ${selected
                      ? 'bg-white border-white text-[#111827]'
                      : 'bg-white/[0.04] border-white/[0.12] text-[#e5e7eb] hover:text-white'}
                  `}
                >
                  {option.label}
                </button>
              );
            })}
          </div>
          <p className="px-3.5 pb-3 text-[#9ca3af] text-xs">
            Applies to TMDB requests and logo localization.
          </p>
        </SettingsCard>
      </div>
    </div>
  );
}
