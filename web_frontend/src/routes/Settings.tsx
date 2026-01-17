import { useState, useEffect, useCallback, useMemo } from 'react';
import { loadSettings, saveSettings, setDiscoveryDisabled, resetAllSettings, type AppSettings } from '@/state/settings';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';

// Eye Off Icon for Discovery Mode
function EyeOffIcon({ size = 18, color = '#e5e7eb' }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  );
}
import HomeScreenSettings from '@/components/settings/HomeScreenSettings';
import DetailsScreenSettings from '@/components/settings/DetailsScreenSettings';
import MDBListSettings from '@/components/settings/MDBListSettings';
import OverseerrSettings from '@/components/settings/OverseerrSettings';
import CatalogSettings from '@/components/settings/CatalogSettings';
import ContinueWatchingSettings from '@/components/settings/ContinueWatchingSettings';
import TMDBSettings from '@/components/settings/TMDBSettings';
import TraktSettings from '@/components/settings/TraktSettings';
import PlexSettings from '@/components/settings/PlexSettings';
import {
  PlexIcon,
  TMDBIcon,
  TraktIcon,
  MDBListIcon,
  OverseerrIcon,
  AlbumsIcon,
  HomeIcon,
  InformationCircleIcon,
  PlayIcon,
  GridIcon,
  ImageIcon,
  ShieldIcon,
  BugIcon,
  PeopleIcon,
  CloudDownloadIcon,
  ChatbubblesIcon,
  ChatboxEllipsesIcon,
  FlashIcon,
  RefreshIcon,
  PlayCircleIcon,
  ChevronForwardIcon,
} from '@/components/ServiceIcons';

const APP_VERSION = 'Beta1.9.5';

const ABOUT_LINKS = {
  privacy: 'https://flixor.xyz/privacy',
  reportIssue: 'https://github.com/Flixorui/flixor/issues',
  contributors: 'https://github.com/Flixorui/flixor',
  discord: 'https://discord.gg/flixor',
  reddit: 'https://www.reddit.com/r/flixor/',
};

// Possible sub-screens
type SettingsScreen =
  | 'main'
  | 'plex'
  | 'homeScreen'
  | 'detailsScreen'
  | 'mdblist'
  | 'overseerr'
  | 'catalogs'
  | 'continueWatching'
  | 'tmdb'
  | 'trakt';

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

// Chevron right component matching mobile
function ChevronRight() {
  return <ChevronForwardIcon size={18} color="#9ca3af" />;
}

export default function Settings() {
  const [settings, setSettings] = useState<AppSettings>(loadSettings);
  const [currentScreen, setCurrentScreen] = useState<SettingsScreen>('main');

  useEffect(() => {
    setSettings(loadSettings());
  }, []);

  const updateSetting = useCallback(<K extends keyof AppSettings>(key: K, value: AppSettings[K]) => {
    setSettings(prev => {
      const next = { ...prev, [key]: value };
      saveSettings(next);
      return next;
    });
  }, []);

  const handleDiscoveryDisabledChange = useCallback((disabled: boolean) => {
    setDiscoveryDisabled(disabled);
    setSettings(prev => {
      const next = {
        ...prev,
        discoveryDisabled: disabled,
        ...(disabled ? {
          showTrendingRows: false,
          showTraktRows: false,
          showPlexPopularRow: false,
          showNewPopularTab: false,
          includeTmdbInSearch: false,
        } : {}),
      };
      return next;
    });
  }, []);

  // Plex description
  const plexDescription = useMemo(() => {
    // Check for actual server connection (plexBaseUrl + plexToken or plexServer)
    const isConnected = !!(settings.plexBaseUrl && settings.plexToken) || !!settings.plexServer;
    if (!isConnected) return 'Not connected';
    if (settings.plexServer) return `${settings.plexUserProfile?.username || 'Connected'} · ${settings.plexServer.name}`;
    return settings.plexUserProfile?.username || 'Connected';
  }, [settings.plexBaseUrl, settings.plexToken, settings.plexServer, settings.plexUserProfile]);

  // Trakt description
  const traktDescription = useMemo(() => {
    if (settings.traktAccessToken || settings.traktTokens) return 'Connected';
    return 'Sign in to sync';
  }, [settings.traktAccessToken, settings.traktTokens]);

  // Render chevron for navigation items
  const renderChevron = useCallback(() => <ChevronRight />, []);

  // Navigate back to main
  const goBack = useCallback(() => setCurrentScreen('main'), []);

  // Render sub-screens
  if (currentScreen === 'plex') {
    return (
      <PlexSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  if (currentScreen === 'homeScreen') {
    return (
      <HomeScreenSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  if (currentScreen === 'detailsScreen') {
    return (
      <DetailsScreenSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  if (currentScreen === 'mdblist') {
    return (
      <MDBListSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  if (currentScreen === 'overseerr') {
    return (
      <OverseerrSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  if (currentScreen === 'catalogs') {
    return (
      <CatalogSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  if (currentScreen === 'continueWatching') {
    return (
      <ContinueWatchingSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  if (currentScreen === 'tmdb') {
    return (
      <TMDBSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  if (currentScreen === 'trakt') {
    return (
      <TraktSettings
        settings={settings}
        updateSetting={updateSetting}
        onBack={goBack}
      />
    );
  }

  // Main settings screen - matches mobile exactly
  return (
    <div className="min-h-screen bg-[#0b0b0d] pb-20">
      {/* Header */}
      <div className="px-4 pt-6 pb-4">
        <h1 className="text-white text-2xl font-bold">Settings</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        {/* ACCOUNT */}
        <SettingsCard title="ACCOUNT">
          <SettingItem
            title="Plex"
            description={plexDescription}
            renderIcon={() => <IconWrap><PlexIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('plex')}
            isLast
          />
        </SettingsCard>

        {/* DISCOVERY MODE */}
        <SettingsCard title="DISCOVERY MODE">
          <SettingItem
            title="Library Only Mode"
            description="Turn off all discovery features"
            renderIcon={() => <IconWrap><EyeOffIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.discoveryDisabled === true}
                onChange={handleDiscoveryDisabledChange}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* CONTENT & DISCOVERY */}
        <SettingsCard title="CONTENT & DISCOVERY">
          <SettingItem
            title="Catalogs"
            description="Choose which libraries appear"
            renderIcon={() => <IconWrap><AlbumsIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('catalogs')}
          />
          <SettingItem
            title="Home Screen"
            description="Hero and row visibility"
            renderIcon={() => <IconWrap><HomeIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('homeScreen')}
          />
          <SettingItem
            title="Details Screen"
            description="Ratings and badges display"
            renderIcon={() => <IconWrap><InformationCircleIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('detailsScreen')}
          />
          <SettingItem
            title="Continue Watching"
            description="Playback and cache behavior"
            renderIcon={() => <IconWrap><PlayIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('continueWatching')}
            isLast
          />
        </SettingsCard>

        {/* APPEARANCE */}
        <SettingsCard title="APPEARANCE">
          <SettingItem
            title="Episode Layout"
            description={settings.episodeLayout === 'horizontal' ? 'Horizontal' : 'Vertical'}
            renderIcon={() => <IconWrap><GridIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.episodeLayout === 'horizontal'}
                onChange={(v) => updateSetting('episodeLayout', v ? 'horizontal' : 'vertical')}
              />
            )}
          />
          <SettingItem
            title="Streams Backdrop"
            description="Show dimmed backdrop behind player settings"
            renderIcon={() => <IconWrap><ImageIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.showCardTitles !== false}
                onChange={(v) => updateSetting('showCardTitles', v)}
              />
            )}
            isLast
          />
        </SettingsCard>

        {/* INTEGRATIONS */}
        <SettingsCard title="INTEGRATIONS">
          <SettingItem
            title="TMDB"
            description="Metadata and language (always enabled)"
            renderIcon={() => <IconWrap><TMDBIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('tmdb')}
          />
          <SettingItem
            title="MDBList (Multi-source)"
            description={settings.mdblistEnabled ? 'Enabled' : 'Disabled'}
            renderIcon={() => <IconWrap><MDBListIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('mdblist')}
          />
          <SettingItem
            title="Trakt"
            description={traktDescription}
            renderIcon={() => <IconWrap><TraktIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('trakt')}
          />
          <SettingItem
            title="Overseerr"
            description={settings.overseerrEnabled ? 'Enabled' : 'Disabled'}
            renderIcon={() => <IconWrap><OverseerrIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => setCurrentScreen('overseerr')}
            isLast
          />
        </SettingsCard>

        {/* PLAYBACK */}
        <SettingsCard title="PLAYBACK">
          <SettingItem
            title="Video Player"
            description="Coming soon"
            renderIcon={() => <IconWrap><PlayCircleIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => <span className="text-[#9ca3af] text-xs font-semibold">Soon</span>}
            disabled
          />
          <SettingItem
            title="Auto-play Best Stream"
            description="Coming soon"
            renderIcon={() => <IconWrap><FlashIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => <SettingToggle checked={false} onChange={() => {}} disabled />}
            disabled
          />
          <SettingItem
            title="Always Resume"
            description="Coming soon"
            renderIcon={() => <IconWrap><RefreshIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={() => <SettingToggle checked={false} onChange={() => {}} disabled />}
            disabled
            isLast
          />
        </SettingsCard>

        {/* ABOUT */}
        <SettingsCard title="ABOUT">
          <SettingItem
            title="Privacy Policy"
            description="Review how data is handled"
            renderIcon={() => <IconWrap><ShieldIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => window.open(ABOUT_LINKS.privacy, '_blank')}
          />
          <SettingItem
            title="Report Issue"
            description="Open a GitHub issue"
            renderIcon={() => <IconWrap><BugIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => window.open(ABOUT_LINKS.reportIssue, '_blank')}
          />
          <SettingItem
            title="Contributors"
            description="Project contributors"
            renderIcon={() => <IconWrap><PeopleIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => window.open(ABOUT_LINKS.contributors, '_blank')}
          />
          <SettingItem
            title="Version"
            description={`v${APP_VERSION}`}
            renderIcon={() => <IconWrap><InformationCircleIcon size={18} color="#e5e7eb" /></IconWrap>}
          />
          <SettingItem
            title="App Updates"
            description="Check for OTA updates"
            renderIcon={() => <IconWrap><CloudDownloadIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => {/* TODO: UpdateSettings */}}
          />
          <SettingItem
            title="Discord"
            description="Join the community"
            renderIcon={() => <IconWrap><ChatbubblesIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => window.open(ABOUT_LINKS.discord, '_blank')}
          />
          <SettingItem
            title="Reddit"
            description="Follow updates"
            renderIcon={() => <IconWrap><ChatboxEllipsesIcon size={18} color="#e5e7eb" /></IconWrap>}
            renderRight={renderChevron}
            onClick={() => window.open(ABOUT_LINKS.reddit, '_blank')}
            isLast
          />
        </SettingsCard>

        {/* Footer */}
        <div className="text-center py-8">
          <p className="text-[#9ca3af] text-sm opacity-50">
            Made with love by Flixor team
          </p>
        </div>
      </div>
    </div>
  );
}
