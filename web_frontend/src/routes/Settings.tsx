import { useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { saveSettings, setDiscoveryDisabled, useSettings, type AppSettings } from '@/state/settings';
import SettingsCard from '@/components/SettingsCard';
import SettingItem, { SettingToggle } from '@/components/SettingItem';
import { checkForUpdate } from '@/services/versionCheck';
import { showToast } from '@/services/toast';
import { useProfileSummary } from '@/services/profiles';
import { traktNeedsReconnect } from '@/services/traktConnection';
import { APP_VERSION } from '@/version';

// Eye Off Icon for Discovery Mode
function EyeOffIcon({ size = 18, color = '#e5e7eb' }: { size?: number; color?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  );
}
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
  PersonCircleIcon,
  GridIcon,
  ShieldIcon,
  BugIcon,
  PeopleIcon,
  CloudDownloadIcon,
  ChatbubblesIcon,
  ChatboxEllipsesIcon,
  PlayCircleIcon,
  ChevronForwardIcon,
  ColorPaletteIcon,
  CompassIcon,
  LayersIcon,
  AnalyticsIcon,
  StatsChartIcon,
} from '@/components/ServiceIcons';

const ABOUT_LINKS = {
  privacy: 'https://flixor.xyz/privacy',
  reportIssue: 'https://github.com/Flixorui/flixor/issues',
  contributors: 'https://github.com/Flixorui/flixor',
  discord: 'https://discord.gg/flixor',
  reddit: 'https://www.reddit.com/r/flixor/',
};

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
  const settings = useSettings();
  const profile = useProfileSummary();
  const navigate = useNavigate();

  const updateSetting = useCallback(<K extends keyof AppSettings>(key: K, value: AppSettings[K]) => {
    saveSettings({ [key]: value });
  }, []);

  // Plex description
  const plexDescription = useMemo(() => {
    const isConnected = !!(settings.plexBaseUrl && settings.plexToken) || !!settings.plexServer;
    if (!isConnected) return 'Not connected';
    const account = profile.signedIn ? profile.name : 'Connected';
    return settings.plexServer ? `${account} · ${settings.plexServer.name}` : account;
  }, [settings.plexBaseUrl, settings.plexToken, settings.plexServer, profile.name, profile.signedIn]);

  const traktDescription = traktNeedsReconnect()
    ? 'Reconnect needed'
    : settings.traktAccessToken || settings.traktTokens ? 'Connected' : 'Sign in to sync';

  const renderChevron = useCallback(() => <ChevronRight />, []);

  async function checkUpdates() {
    const info = await checkForUpdate();
    if (info.hasUpdate) {
      showToast(`Version ${info.latestVersion} is available`, 'info', 5000);
      if (info.releaseUrl) window.open(info.releaseUrl, '_blank', 'noopener');
    } else {
      showToast(`You're on the latest version (${info.currentVersion})`, 'success');
    }
  }

  // Row that opens another settings page.
  const linkRow = (title: string, description: string, icon: React.ReactNode, to: string, isLast = false) => (
    <SettingItem
      title={title}
      description={description}
      renderIcon={() => <IconWrap>{icon}</IconWrap>}
      renderRight={renderChevron}
      onClick={() => navigate(to)}
      isLast={isLast}
    />
  );

  const externalRow = (title: string, description: string, icon: React.ReactNode, url: string, isLast = false) => (
    <SettingItem
      title={title}
      description={description}
      renderIcon={() => <IconWrap>{icon}</IconWrap>}
      renderRight={renderChevron}
      onClick={() => window.open(url, '_blank', 'noopener')}
      isLast={isLast}
    />
  );

  const c = '#e5e7eb';

  return (
    <div className="min-h-screen bg-[#0b0b0d] pb-20">
      <div className="px-4 pt-6 pb-4 max-w-2xl mx-auto">
        <h1 className="text-white text-2xl font-bold">Settings</h1>
      </div>

      <div className="px-4 max-w-2xl mx-auto">
        <SettingsCard title="ACCOUNT">
          {linkRow('Plex', plexDescription, <PlexIcon size={18} color={c} />, '/settings/plex', !profile.canSwitch)}
          {profile.canSwitch &&
            linkRow('Switch Profile', 'Change to another Plex Home profile', <PersonCircleIcon size={18} color={c} />, '/profiles', true)}
        </SettingsCard>

        <SettingsCard title="PLAYER">
          {linkRow('Player', 'Subtitles, skipping and playback', <PlayCircleIcon size={18} color={c} />, '/settings/player', true)}
        </SettingsCard>

        <SettingsCard title="CONTENT & DISCOVERY">
          <SettingItem
            title="Library Only Mode"
            description="Turn off all discovery features"
            renderIcon={() => <IconWrap><EyeOffIcon size={18} color={c} /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.discoveryDisabled === true}
                onChange={(disabled) => setDiscoveryDisabled(disabled)}
              />
            )}
          />
          {linkRow('Catalogs', 'Choose which libraries appear', <AlbumsIcon size={18} color={c} />, '/settings/catalogs')}
          {linkRow('Rows', 'Reorder, rename and hide Home rows', <GridIcon size={18} color={c} />, '/settings/rows')}
          {linkRow('Navigation', 'Navigation style and tabs', <CompassIcon size={18} color={c} />, '/settings/navigation')}
          {linkRow('Search', 'Search sources and Discover', <StatsChartIcon size={18} color={c} />, '/settings/search', true)}
        </SettingsCard>

        <SettingsCard title="APPEARANCE">
          {linkRow('Appearance', 'Accent color and background', <ColorPaletteIcon size={18} color={c} />, '/settings/appearance')}
          {linkRow('Home Screen', 'Hero and row visibility', <HomeIcon size={18} color={c} />, '/settings/home')}
          {linkRow('Continue Watching', 'Playback and cache behavior', <PlayIcon size={18} color={c} />, '/settings/continue-watching')}
          {linkRow('Details Screen', 'Ratings and badges display', <InformationCircleIcon size={18} color={c} />, '/settings/details')}
          <SettingItem
            title="Episode Layout"
            description={settings.episodeLayout === 'horizontal' ? 'Horizontal' : 'Vertical'}
            renderIcon={() => <IconWrap><GridIcon size={18} color={c} /></IconWrap>}
            renderRight={() => (
              <SettingToggle
                checked={settings.episodeLayout === 'horizontal'}
                onChange={(v) => updateSetting('episodeLayout', v ? 'horizontal' : 'vertical')}
              />
            )}
            isLast
          />
        </SettingsCard>

        <SettingsCard title="INTEGRATIONS">
          {linkRow('TMDB', 'Metadata and language (always enabled)', <TMDBIcon size={18} color={c} />, '/settings/tmdb')}
          {linkRow('Stremio', 'Addons, sources and catalogs', <LayersIcon size={18} color={c} />, '/settings/stremio')}
          {linkRow('MDBList (Multi-source)', settings.mdblistEnabled ? 'Enabled' : 'Disabled', <MDBListIcon size={18} color={c} />, '/settings/mdblist')}
          {linkRow('Overseerr', settings.overseerrEnabled ? 'Enabled' : 'Disabled', <OverseerrIcon size={18} color={c} />, '/settings/overseerr')}
          {linkRow('Trakt', traktDescription, <TraktIcon size={18} color={c} />, '/settings/trakt', true)}
        </SettingsCard>

        <SettingsCard title="SYSTEM">
          {linkRow('Advanced', 'Diagnostics and logs', <AnalyticsIcon size={18} color={c} />, '/settings/advanced', true)}
        </SettingsCard>

        <SettingsCard title="ABOUT">
          {externalRow('Privacy Policy', 'Review how data is handled', <ShieldIcon size={18} color={c} />, ABOUT_LINKS.privacy)}
          {externalRow('Report Issue', 'Open a GitHub issue', <BugIcon size={18} color={c} />, ABOUT_LINKS.reportIssue)}
          {externalRow('Contributors', 'Project contributors', <PeopleIcon size={18} color={c} />, ABOUT_LINKS.contributors)}
          <SettingItem
            title="Version"
            description={`v${APP_VERSION}`}
            renderIcon={() => <IconWrap><InformationCircleIcon size={18} color={c} /></IconWrap>}
          />
          <SettingItem
            title="App Updates"
            description="Check for a new version"
            renderIcon={() => <IconWrap><CloudDownloadIcon size={18} color={c} /></IconWrap>}
            renderRight={renderChevron}
            onClick={checkUpdates}
          />
          {externalRow('Discord', 'Join the community', <ChatbubblesIcon size={18} color={c} />, ABOUT_LINKS.discord)}
          {externalRow('Reddit', 'Follow updates', <ChatboxEllipsesIcon size={18} color={c} />, ABOUT_LINKS.reddit, true)}
        </SettingsCard>

        <div className="text-center py-8">
          <p className="text-[#9ca3af] text-sm opacity-50">Made with love by Flixor team</p>
        </div>
      </div>
    </div>
  );
}
