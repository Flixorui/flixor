import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import {
  ChevronBackIcon,
  ChevronForwardIcon,
  FilmIcon,
  GridIcon,
  LanguageIcon,
  LayersIcon,
  PlayCircleIcon,
  RefreshIcon,
} from '@/components/ServiceIcons';
import StreamRulesEditor from '@/components/stremio/StreamRulesEditor';
import {
  ensureDefaultAddons,
  getInstalledAddons,
  subscribeAddons,
  type StremioAddon,
} from '@/stremio';
import {
  saveSettings,
  useSettings,
  type StremioPlayAction,
  type StremioUnsupportedSourceVisibility,
} from '@/state/settings';
import StremioAddons from './StremioAddons';

const PLAY_ACTIONS: Array<{ value: StremioPlayAction; label: string; description: string }> = [
  { value: 'showSources', label: 'Show sources', description: 'Always open the list of sources' },
  { value: 'playBest', label: 'Play best source', description: 'Start the best source that can play in this browser' },
  { value: 'matchRules', label: 'Match my rules', description: 'Start the best source that fits your rules, or show the list if none does' },
  { value: 'addonOrder', label: 'Follow addon order', description: 'Try your first addon, then fall back to the next one in your addon order' },
];

const TIME_LIMITS = [3, 5, 8, 10, 15, 30];

const selectClass = 'max-w-[180px] rounded-lg bg-white/[0.08] px-2 py-1.5 text-[13px] text-white focus:outline-none';

function IconWrap({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-[34px] w-[34px] items-center justify-center rounded-[10px] text-[#e5e7eb]" style={{ backgroundColor: 'rgba(229,231,235,0.08)' }}>
      {children}
    </div>
  );
}

function Header({ title, onBack }: { title: string; onBack: () => void }) {
  return (
    <div className="mx-auto flex max-w-2xl items-center gap-3 px-4 pb-4 pt-6">
      <button type="button" onClick={onBack} aria-label="Back" className="-ml-2 flex h-10 w-10 items-center justify-center rounded-full transition-colors hover:bg-white/10">
        <ChevronBackIcon size={24} color="#fff" />
      </button>
      <h1 className="text-xl font-bold text-white">{title}</h1>
    </div>
  );
}

export default function StremioSettings() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const settings = useSettings();
  const [addons, setAddons] = useState<StremioAddon[]>([]);
  const showAddons = searchParams.get('view') === 'addons';

  useEffect(() => {
    const refresh = () => {
      getInstalledAddons().then(setAddons);
    };
    refresh();
    return subscribeAddons(refresh);
  }, []);

  useEffect(() => {
    if (settings.stremioPlaybackEnabled) ensureDefaultAddons();
  }, [settings.stremioPlaybackEnabled]);

  const streamAddons = useMemo(() => addons.filter((addon) => addon.resources.includes('stream')), [addons]);
  const subtitleCount = useMemo(() => addons.filter((addon) => addon.resources.includes('subtitles')).length, [addons]);
  const playAction = PLAY_ACTIONS.find((action) => action.value === settings.stremioPlayAction) ?? PLAY_ACTIONS[0];
  const timeLimits = TIME_LIMITS.includes(settings.stremioAutoPickTimeLimit)
    ? TIME_LIMITS
    : [...TIME_LIMITS, settings.stremioAutoPickTimeLimit].sort((a, b) => a - b);

  if (showAddons) {
    return (
      <div className="min-h-screen pb-20">
        <Header title="Addons" onBack={() => setSearchParams({})} />
        <div className="mx-auto max-w-2xl px-4">
          <StremioAddons />
        </div>
      </div>
    );
  }

  const toggle = (key: 'stremioPlaybackEnabled' | 'stremioShowOnTmdbDetails' | 'stremioPreferCachedSourceResume' | 'stremioSubtitleAddonsEnabled' | 'showStremioCatalogRows' | 'stremioCatalogSearchEnabled') => (
    <SettingToggle
      checked={settings[key]}
      onChange={(value) => saveSettings(key === 'stremioPlaybackEnabled' ? { stremioPlaybackEnabled: value, stremioPlaybackSetByUser: true } : { [key]: value })}
    />
  );

  return (
    <div className="min-h-screen pb-20">
      <Header title="Stremio" onBack={() => navigate('/settings')} />
      <div className="mx-auto max-w-2xl px-4">
        <SettingsCard title="Playback">
          <SettingItem
            title="Enable Stremio Playback"
            description="Show addon source buttons on supported details pages"
            renderIcon={() => <IconWrap><PlayCircleIcon size={18} /></IconWrap>}
            renderRight={() => toggle('stremioPlaybackEnabled')}
          />
          <SettingItem
            title="Manage Addons"
            description={addons.length === 0 ? 'Install stream and subtitle addons' : `${addons.length} installed • ${streamAddons.length} stream • ${subtitleCount} subtitle`}
            renderIcon={() => <IconWrap><LayersIcon size={18} /></IconWrap>}
            renderRight={() => <ChevronForwardIcon size={18} color="#9ca3af" />}
            onClick={() => setSearchParams({ view: 'addons' })}
          />
          <SettingItem
            title="When I Press Play"
            description={playAction.description}
            renderIcon={() => <IconWrap><PlayCircleIcon size={18} /></IconWrap>}
            renderRight={() => (
              <select
                value={settings.stremioPlayAction}
                onChange={(event) => saveSettings({ stremioPlayAction: event.target.value as StremioPlayAction })}
                aria-label="When I press Play on addon content"
                className={selectClass}
              >
                {PLAY_ACTIONS.map((action) => (
                  <option key={action.value} value={action.value}>{action.label}</option>
                ))}
              </select>
            )}
          />
          {settings.stremioPlayAction !== 'showSources' && (
            <SettingItem
              title="Wait for Addons"
              description="Longest to wait before deciding with the sources that have arrived"
              renderIcon={() => <IconWrap><RefreshIcon size={18} /></IconWrap>}
              renderRight={() => (
                <select
                  value={settings.stremioAutoPickTimeLimit}
                  onChange={(event) => saveSettings({ stremioAutoPickTimeLimit: Number(event.target.value) })}
                  aria-label="Time limit for waiting on addons"
                  className={selectClass}
                >
                  {timeLimits.map((seconds) => (
                    <option key={seconds} value={seconds}>{seconds} seconds</option>
                  ))}
                </select>
              )}
            />
          )}
          <SettingItem
            title="Show on TMDB Details"
            description="Offer addon sources for titles that are not in Plex"
            renderIcon={() => <IconWrap><FilmIcon size={18} /></IconWrap>}
            renderRight={() => toggle('stremioShowOnTmdbDetails')}
          />
          <SettingItem
            title="Prefer Cached Source Resume"
            description="Start from the last source used for a title while its link is still valid"
            renderIcon={() => <IconWrap><RefreshIcon size={18} /></IconWrap>}
            renderRight={() => toggle('stremioPreferCachedSourceResume')}
          />
          <SettingItem
            title="Subtitle Addons"
            description="Fetch external subtitles from subtitle addons"
            renderIcon={() => <IconWrap><LanguageIcon size={18} /></IconWrap>}
            renderRight={() => toggle('stremioSubtitleAddonsEnabled')}
          />
          <SettingItem
            title="Catalog Rows on Home"
            description="Show a Home row for each catalog your addons provide"
            renderIcon={() => <IconWrap><GridIcon size={18} /></IconWrap>}
            renderRight={() => toggle('showStremioCatalogRows')}
          />
          <SettingItem
            title="Search Addon Catalogs"
            description="Include addon catalog matches in search results"
            renderIcon={() => <IconWrap><GridIcon size={18} /></IconWrap>}
            renderRight={() => toggle('stremioCatalogSearchEnabled')}
          />
          <SettingItem
            title="Sources That Can't Play Here"
            description="Keep them visible with the reason, or hide them"
            isLast
            renderIcon={() => <IconWrap><LayersIcon size={18} /></IconWrap>}
            renderRight={() => (
              <select
                value={settings.stremioUnsupportedSourceVisibility}
                onChange={(event) => saveSettings({ stremioUnsupportedSourceVisibility: event.target.value as StremioUnsupportedSourceVisibility })}
                aria-label="Sources that can't play in this browser"
                className={selectClass}
              >
                <option value="showDisabled">Show with reason</option>
                <option value="hide">Hide</option>
              </select>
            )}
          />
        </SettingsCard>

        {settings.stremioPlayAction === 'matchRules' && <StreamRulesEditor streamAddons={streamAddons} />}
      </div>
    </div>
  );
}
