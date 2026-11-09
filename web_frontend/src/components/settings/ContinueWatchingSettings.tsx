import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { AppSettings } from '@/state/settings';
import {
  ChevronBackIcon,
  FlashIcon,
  InformationCircleIcon,
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

const TTL_OPTIONS = [
  { label: '15 min', value: 15 * 60 * 1000 },
  { label: '30 min', value: 30 * 60 * 1000 },
  { label: '1 hour', value: 60 * 60 * 1000 },
  { label: '6 hours', value: 6 * 60 * 60 * 1000 },
  { label: '12 hours', value: 12 * 60 * 60 * 1000 },
  { label: '24 hours', value: 24 * 60 * 60 * 1000 },
];

function SegmentedPicker<T extends string>({ label, value, options, onChange }: {
  label: string;
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <div className="p-[14px]">
      <span className="block text-[#f9fafb] text-[15px] font-semibold mb-3">{label}</span>
      <div className="flex gap-2">
        {options.map((option) => (
          <button
            key={option.value}
            onClick={() => onChange(option.value)}
            className={`flex-1 py-3 rounded-[10px] border text-[13px] font-semibold transition-all ${
              value === option.value ? 'bg-white border-white text-[#111827]' : 'bg-white/[0.04] border-white/[0.12] text-[#9ca3af] hover:text-white'
            }`}
          >
            {option.label}
          </button>
        ))}
      </div>
    </div>
  );
}

interface ContinueWatchingSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function ContinueWatchingSettings({ settings, updateSetting, onBack }: ContinueWatchingSettingsProps) {
  const useCachedStreams = settings.useCachedStreams ?? false;
  const streamCacheTTL = settings.streamCacheTTL ?? TTL_OPTIONS[2].value;

  return (
    <div className="min-h-screen pb-20">
      {/* Header with back button */}
      <div className="px-4 pt-6 pb-4 max-w-2xl mx-auto flex items-center gap-3">
        <button
          onClick={onBack}
          className="-ml-2 flex items-center justify-center w-10 h-10 rounded-full hover:bg-white/10 transition-colors"
        >
          <ChevronBackIcon size={24} color="#fff" />
        </button>
        <h1 className="text-white text-xl font-bold">Continue Watching</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* LAYOUT */}
        <SettingsCard title="LAYOUT">
          <div className="p-[14px]">
            <span className="block text-[#f9fafb] text-[15px] font-semibold mb-3">Card Style</span>
            <div className="flex gap-2">
              {[
                { label: 'Landscape', value: 'landscape' },
                { label: 'Poster', value: 'poster' },
                { label: 'Wide', value: 'wide' },
              ].map((option) => {
                const selected = (settings.continueWatchingLayout || 'landscape') === option.value;
                return (
                  <button
                    key={option.value}
                    onClick={() => updateSetting('continueWatchingLayout', option.value as 'landscape' | 'poster' | 'wide')}
                    className={`
                      flex-1 py-3 rounded-[10px] border text-[14px] font-semibold transition-all
                      ${selected
                        ? 'bg-[#e5a00d]/20 border-[#e5a00d] text-white'
                        : 'bg-white/[0.04] border-white/[0.12] text-[#9ca3af] hover:text-white'}
                    `}
                  >
                    {option.label}
                  </button>
                );
              })}
            </div>
            <p className="text-[#6b7280] text-xs mt-3 leading-4">
              Landscape shows large cards with a progress bar. Poster shows vertical cards. Wide adds the episode still and title.
            </p>
          </div>
        </SettingsCard>

        {/* SOURCE */}
        <SettingsCard title="SOURCE">
          <SegmentedPicker
            label="Continue Watching Source"
            value={settings.continueWatchingSource || 'automatic'}
            options={[
              { value: 'automatic', label: 'Automatic' },
              { value: 'library', label: 'Library' },
              { value: 'trakt', label: 'Trakt' },
            ]}
            onChange={(v) => updateSetting('continueWatchingSource', v)}
          />
          <p className="text-[#9ca3af] text-xs px-[14px] pb-3">
            Automatic combines your Plex progress with Trakt when Trakt is connected.
          </p>
        </SettingsCard>

        {/* ORDER AND SPOILERS */}
        <SettingsCard title="ORDER AND SPOILERS">
          <SegmentedPicker
            label="Sort Order"
            value={settings.continueWatchingSort || 'recent'}
            options={[
              { value: 'recent', label: 'Recent' },
              { value: 'nextEpisodeFirst', label: 'Next Episode' },
              { value: 'title', label: 'Title' },
            ]}
            onChange={(v) => updateSetting('continueWatchingSort', v)}
          />
          <SettingItem
            title="Blur Next-Up Thumbnails"
            description="Hide stills of episodes you haven't started (Wide cards)"
            renderIcon={() => <IconWrap><InformationCircleIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.continueWatchingBlurNextUp === true}
                onChange={(v) => updateSetting('continueWatchingBlurNextUp', v)}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* PLAYBACK SOURCE CACHE */}
        <SettingsCard title="PLAYBACK SOURCE CACHE">
          <SettingItem
            title="Cache Playback Sources"
            description="Reuse recent addon stream links for faster resume"
            renderIcon={() => <IconWrap><FlashIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={useCachedStreams}
                onChange={(v) => updateSetting('useCachedStreams', v)}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* CACHE DURATION - only show when cached streams enabled */}
        {useCachedStreams && (
          <SettingsCard title="CACHE DURATION">
            <div className="flex flex-wrap gap-2 p-[14px]">
              {TTL_OPTIONS.map((option) => {
                const selected = streamCacheTTL === option.value;
                return (
                  <button
                    key={option.label}
                    onClick={() => updateSetting('streamCacheTTL', option.value)}
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
            <p className="text-[#9ca3af] text-xs px-[14px] pb-3">
              Applies to resuming addon streams.
            </p>
          </SettingsCard>
        )}
      </div>
    </div>
  );
}
