import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { AppSettings } from '@/state/settings';
import {
  StarIcon,
  LeafIcon,
  PeopleIcon,
  ChevronBackIcon,
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

// Segmented control for settings
function SegmentedPicker<T extends string>({
  label,
  description,
  value,
  options,
  onChange,
}: {
  label: string;
  description?: string;
  value: T;
  options: { value: T; label: string }[];
  onChange: (v: T) => void;
}) {
  return (
    <div className="px-[14px] py-3">
      <span className="block text-[#f9fafb] text-[14px] font-semibold mb-1.5">{label}</span>
      {description && (
        <span className="block text-[#9ca3af] text-[12px] mb-3">{description}</span>
      )}
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
              flex-1 h-[40px] flex items-center justify-center text-[14px] font-semibold rounded-[10px]
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

interface DetailsScreenSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function DetailsScreenSettings({ settings, updateSetting, onBack }: DetailsScreenSettingsProps) {
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
        <h1 className="text-white text-xl font-bold">Details Screen</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* SCREEN LAYOUT */}
        <SettingsCard title="SCREEN LAYOUT">
          <SegmentedPicker
            label="Details Page Style"
            description="Tabbed shows sections in tabs, Unified shows all content on one scrollable page"
            value={settings.detailsLayout || 'tabbed'}
            options={[
              { value: 'tabbed', label: 'Tabbed' },
              { value: 'unified', label: 'Unified' },
            ]}
            onChange={(v) => updateSetting('detailsLayout', v)}
          />
        </SettingsCard>

        {/* RATINGS DISPLAY */}
        <SettingsCard title="RATINGS DISPLAY">
          <SettingItem
            title="IMDb Rating"
            description="Show IMDb rating on details screen"
            renderIcon={() => <IconWrap><StarIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.ratingsVisible?.imdb !== false}
                onChange={(v) => updateSetting('ratingsVisible', { ...settings.ratingsVisible, imdb: v })}
              />
            )}
          />
          <SettingItem
            title="Rotten Tomatoes (Critics)"
            description="Show critic score from Rotten Tomatoes"
            renderIcon={() => <IconWrap><LeafIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.ratingsVisible?.rtCritic !== false}
                onChange={(v) => updateSetting('ratingsVisible', { ...settings.ratingsVisible, rtCritic: v })}
              />
            )}
          />
          <SettingItem
            title="Rotten Tomatoes (Audience)"
            description="Show audience score from Rotten Tomatoes"
            renderIcon={() => <IconWrap><PeopleIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.ratingsVisible?.rtAudience !== false}
                onChange={(v) => updateSetting('ratingsVisible', { ...settings.ratingsVisible, rtAudience: v })}
              />
            )}
            isLast
          />
        </SettingsCard>
      </div>
    </div>
  );
}
