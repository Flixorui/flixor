import { useCallback } from 'react';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { AppSettings, setDiscoveryDisabled } from '@/state/settings';
import {
  StarIcon,
  PlayIcon,
  StatsChartIcon,
  LayersIcon,
  FlameIcon,
  ImageIcon,
  LibraryIcon,
  ChevronBackIcon,
} from '@/components/ServiceIcons';

// Eye Off Icon for Discovery Mode
function EyeOffIcon({ size = 18, color = '#e5e7eb' }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  );
}

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

// Segmented control for settings
function SegmentedPicker<T extends string>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <div className="px-[14px] py-3">
      <span className="block text-[#f9fafb] text-[14px] font-semibold mb-2.5">{label}</span>
      <div
        className="flex rounded-[14px] p-0.5 gap-0.5 h-[44px]"
        style={{
          backgroundColor: 'rgba(255,255,255,0.04)',
          border: '1px solid rgba(255,255,255,0.12)',
        }}
      >
        {options.map((opt, idx) => (
          <button
            key={opt.value}
            onClick={() => onChange(opt.value)}
            className={`
              flex-1 h-[40px] flex items-center justify-center text-[12px] font-semibold rounded-[10px]
              transition-all duration-200
              ${idx > 0 ? 'border-l border-white/[0.08]' : ''}
              ${value === opt.value ? 'bg-white text-[#111827]' : 'text-[#e5e7eb] hover:text-white'}
            `}
          >
            {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}

interface HomeScreenSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function HomeScreenSettings({ settings, updateSetting, onBack }: HomeScreenSettingsProps) {
  const handleDiscoveryDisabledChange = (disabled: boolean) => {
    setDiscoveryDisabled(disabled);
    updateSetting('discoveryDisabled', disabled);
    if (disabled) {
      updateSetting('showTrendingRows', false);
      updateSetting('showTraktRows', false);
      updateSetting('showPlexPopularRow', false);
      updateSetting('showNewPopularTab', false);
      updateSetting('includeTmdbInSearch', false);
    }
  };

  const isDiscoveryDisabled = settings.discoveryDisabled === true;

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
        <h1 className="text-white text-xl font-bold">Home Screen</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* DISCOVERY MODE */}
        <SettingsCard title="DISCOVERY MODE">
          <SettingItem
            title="Library Only Mode"
            description="Turn off all discovery features. Only show content from your Plex library."
            renderIcon={() => <IconWrap><EyeOffIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={isDiscoveryDisabled}
                onChange={handleDiscoveryDisabledChange}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* HERO */}
        <SettingsCard title="HERO">
          <SettingItem
            title="Show Hero"
            description="Display the featured hero row"
            renderIcon={() => <IconWrap><StarIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.showHeroSection !== false}
                onChange={(v) => updateSetting('showHeroSection', v)}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* HERO LAYOUT - only show when hero is enabled */}
        {settings.showHeroSection !== false && (
          <SettingsCard title="HERO LAYOUT">
            <SegmentedPicker
              label="Hero Layout"
              value={settings.heroLayout || 'legacy'}
              options={[
                { value: 'legacy', label: 'Netflix' },
                { value: 'carousel', label: 'Carousel' },
                { value: 'appletv', label: 'Apple TV' },
              ]}
              onChange={(v) => updateSetting('heroLayout', v)}
            />
          </SettingsCard>
        )}

        {/* ROWS */}
        <SettingsCard title="ROWS">
          <SettingItem
            title="Continue Watching"
            description="Show continue watching row"
            renderIcon={() => <IconWrap><PlayIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.showContinueWatchingRow !== false}
                onChange={(v) => updateSetting('showContinueWatchingRow', v)}
              />
            )}
          />
          <SettingItem
            title="Trending"
            description={isDiscoveryDisabled ? "Disabled by Library Only Mode" : "Show TMDB trending rows"}
            renderIcon={() => <IconWrap><StatsChartIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.showTrendingRows !== false}
                onChange={(v) => updateSetting('showTrendingRows', v)}
                disabled={isDiscoveryDisabled}
              />
            )}
            disabled={isDiscoveryDisabled}
          />
          <SettingItem
            title="Trakt Rows"
            description={isDiscoveryDisabled ? "Disabled by Library Only Mode" : "Show Trakt watchlist, history, and recs"}
            renderIcon={() => <IconWrap><LayersIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.showTraktRows !== false}
                onChange={(v) => updateSetting('showTraktRows', v)}
                disabled={isDiscoveryDisabled}
              />
            )}
            disabled={isDiscoveryDisabled}
          />
          <SettingItem
            title="Popular on Plex"
            description={isDiscoveryDisabled ? "Disabled by Library Only Mode" : "Show Plex popularity row"}
            renderIcon={() => <IconWrap><FlameIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.showPlexPopularRow !== false}
                onChange={(v) => updateSetting('showPlexPopularRow', v)}
                disabled={isDiscoveryDisabled}
              />
            )}
            disabled={isDiscoveryDisabled}
            isLast
          />
        </SettingsCard>

        {/* POSTERS */}
        <SettingsCard title="POSTERS">
          <SettingItem
            title="Show Titles"
            description="Display title text below each poster"
            renderIcon={() => <IconWrap><ImageIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.showPosterTitles !== false}
                onChange={(v) => updateSetting('showPosterTitles', v)}
              />
            )}
          />
          <SettingItem
            title="Library Titles"
            description="Display title text in Library grid"
            renderIcon={() => <IconWrap><LibraryIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.showLibraryTitles !== false}
                onChange={(v) => updateSetting('showLibraryTitles', v)}
              />
            )}
          />
          <SegmentedPicker
            label="Poster Size"
            value={settings.posterSize || 'medium'}
            options={[
              { value: 'small', label: 'Small' },
              { value: 'medium', label: 'Medium' },
              { value: 'large', label: 'Large' },
            ]}
            onChange={(v) => updateSetting('posterSize', v)}
          />
          <div className="pb-3">
            <SegmentedPicker
              label="Poster Corners"
              value={String(settings.posterBorderRadius ?? 12)}
              options={[
                { value: '0', label: 'Square' },
                { value: '12', label: 'Rounded' },
                { value: '20', label: 'Pill' },
              ]}
              onChange={(v) => updateSetting('posterBorderRadius', Number(v))}
            />
          </div>
        </SettingsCard>
      </div>
    </div>
  );
}
