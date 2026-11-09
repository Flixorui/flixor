import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { AppSettings, SETTINGS_DEFAULTS, type DetailsSectionKey, type DetailsSectionPreference } from '@/state/settings';
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

const SECTION_LABELS: Record<DetailsSectionKey, string> = {
  episodes: 'Episodes',
  suggested: 'More Like This',
  collection: 'Collection',
  cast: 'Cast & Crew',
  trailers: 'Trailers & Videos',
  comments: 'Comments',
  about: 'About',
};

function completeSectionOrder(stored?: DetailsSectionPreference[]): DetailsSectionPreference[] {
  const order = stored ?? SETTINGS_DEFAULTS.detailsSectionOrder;
  const known = new Set(order.map((section) => section.key));
  return [...order, ...SETTINGS_DEFAULTS.detailsSectionOrder.filter((section) => !known.has(section.key))];
}

function MoveButton({ label, disabled, onClick, path }: { label: string; disabled: boolean; onClick: () => void; path: string }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={label}
      className="flex h-8 w-8 items-center justify-center rounded-full text-white hover:bg-white/10 disabled:opacity-25"
    >
      <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d={path} />
      </svg>
    </button>
  );
}

interface DetailsScreenSettingsProps {
  settings: AppSettings;
  updateSetting: <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;
  onBack: () => void;
}

export default function DetailsScreenSettings({ settings, updateSetting, onBack }: DetailsScreenSettingsProps) {
  const sections = completeSectionOrder(settings.detailsSectionOrder);
  const moveSection = (index: number, delta: number) => {
    const next = [...sections];
    const [section] = next.splice(index, 1);
    next.splice(index + delta, 0, section);
    updateSetting('detailsSectionOrder', next);
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
          />
          <SettingItem
            title="Letterboxd"
            description="Requires MDBList"
            renderIcon={() => <IconWrap><StarIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.ratingsVisible?.letterboxd !== false}
                onChange={(v) => updateSetting('ratingsVisible', { ...settings.ratingsVisible, letterboxd: v })}
              />
            )}
          />
          <SettingItem
            title="Metacritic"
            description="Requires MDBList"
            renderIcon={() => <IconWrap><StarIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.ratingsVisible?.metacritic !== false}
                onChange={(v) => updateSetting('ratingsVisible', { ...settings.ratingsVisible, metacritic: v })}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* SECTIONS */}
        <SettingsCard title="SECTIONS">
          {sections.map((section, index) => (
            <SettingItem
              key={section.key}
              title={SECTION_LABELS[section.key]}
              renderRight={() => (
                <div className="flex items-center gap-1">
                  <MoveButton label={`Move ${SECTION_LABELS[section.key]} up`} disabled={index === 0} onClick={() => moveSection(index, -1)} path="M5 15l7-7 7 7" />
                  <MoveButton label={`Move ${SECTION_LABELS[section.key]} down`} disabled={index === sections.length - 1} onClick={() => moveSection(index, 1)} path="M19 9l-7 7-7-7" />
                  <SettingToggle
                    checked={section.enabled}
                    onChange={(enabled) => updateSetting('detailsSectionOrder', sections.map((item) => (item.key === section.key ? { ...item, enabled } : item)))}
                  />
                </div>
              )}
              isLast={index === sections.length - 1}
            />
          ))}
        </SettingsCard>

        {/* EPISODES */}
        <SettingsCard title="EPISODES">
          <SegmentedPicker
            label="Season Picker"
            value={settings.detailsSeasonPickerStyle ?? 'chips'}
            options={[
              { value: 'chips', label: 'Chips' },
              { value: 'posters', label: 'Posters' },
            ]}
            onChange={(v) => updateSetting('detailsSeasonPickerStyle', v)}
          />
          <SettingItem
            title="Hide Spoilers"
            description="Blur images and hide synopses of unwatched episodes"
            renderRight={() => (
              <SettingToggle
                checked={settings.detailsHideEpisodeSpoilers ?? false}
                onChange={(v) => updateSetting('detailsHideEpisodeSpoilers', v)}
              />
            )}
          />
          <SettingItem
            title="Episode Ratings"
            description="Show the TMDB rating on each episode"
            renderRight={() => (
              <SettingToggle
                checked={settings.detailsShowEpisodeRatings ?? true}
                onChange={(v) => updateSetting('detailsShowEpisodeRatings', v)}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* HERO AND SUGGESTIONS */}
        <SettingsCard title="HERO">
          <SettingItem
            title="Inline Trailer"
            description="Play the trailer behind the title after a few seconds"
            renderRight={() => (
              <SettingToggle
                checked={settings.detailsHeroInlineTrailerEnabled ?? true}
                onChange={(v) => updateSetting('detailsHeroInlineTrailerEnabled', v)}
              />
            )}
          />
          <SettingItem
            title="Start Muted"
            renderRight={() => (
              <SettingToggle
                checked={settings.detailsHeroTrailerStartsMuted ?? true}
                onChange={(v) => updateSetting('detailsHeroTrailerStartsMuted', v)}
              />
            )}
            isLast
          />
        </SettingsCard>

        <SettingsCard title="SUGGESTED">
          <SegmentedPicker
            label="Row Layout"
            value={settings.suggestedLayout ?? 'landscape'}
            options={[
              { value: 'landscape', label: 'Landscape' },
              { value: 'poster', label: 'Poster' },
            ]}
            onChange={(v) => updateSetting('suggestedLayout', v)}
          />
        </SettingsCard>
      </div>
    </div>
  );
}
