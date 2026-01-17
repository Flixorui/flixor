import React, { useCallback, useMemo, useRef, useState } from 'react';
import { View, Text, ScrollView, StyleSheet, Switch, Dimensions, Linking, Pressable, Animated, Platform } from 'react-native';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFlixor } from '../core/FlixorContext';
import {
  getTraktProfile,
  getPlexUser,
  getConnectedServerInfo,
  getAppVersion,
  setDiscoveryDisabled,
} from '../core/SettingsData';
import { useAppSettings } from '../hooks/useAppSettings';
import SettingsCard from '../components/settings/SettingsCard';
import SettingItem from '../components/settings/SettingItem';
import SettingsHeader from '../components/settings/SettingsHeader';
import MDBListIcon from '../components/icons/MDBListIcon';
import TMDBIcon from '../components/icons/TMDBIcon';
import TraktIcon from '../components/icons/TraktIcon';
import PlexIcon from '../components/icons/PlexIcon';
import OverseerrIcon from '../components/icons/OverseerrIcon';

const { width } = Dimensions.get('window');
const isTablet = width >= 768;

const ABOUT_LINKS = {
  privacy: 'https://flixor.xyz/privacy',
  reportIssue: 'https://github.com/Flixorui/flixor/issues',
  contributors: 'https://github.com/Flixorui/flixor',
  discord: 'https://discord.gg/flixor',
  reddit: 'https://www.reddit.com/r/flixor/',
};

type CategoryId =
  | 'account'
  | 'content'
  | 'appearance'
  | 'androidPerformance'
  | 'integrations'
  | 'playback'
  | 'about';

const CATEGORIES: Array<{ id: CategoryId; title: string; icon: keyof typeof Ionicons.glyphMap; androidOnly?: boolean }> = [
  { id: 'account', title: 'Account', icon: 'person-circle-outline' },
  { id: 'content', title: 'Content & Discovery', icon: 'compass-outline' },
  { id: 'appearance', title: 'Appearance', icon: 'color-palette-outline' },
  { id: 'androidPerformance', title: 'Android Performance', icon: 'speedometer-outline', androidOnly: true },
  { id: 'integrations', title: 'Integrations', icon: 'layers-outline' },
  { id: 'playback', title: 'Playback', icon: 'play-circle-outline' },
  { id: 'about', title: 'About', icon: 'information-circle-outline' },
];

interface SettingsProps {
  onLogout?: () => Promise<void>;
  onBack?: () => void;
}

export default function Settings({ onBack }: SettingsProps) {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const scrollY = useRef(new Animated.Value(0)).current;
  const { isLoading: flixorLoading, isConnected } = useFlixor();
  const { settings, updateSetting } = useAppSettings();
  const [traktProfile, setTraktProfile] = useState<any | null>(null);
  const [plexUser, setPlexUser] = useState<any | null>(null);
  const [serverInfo, setServerInfo] = useState<{ name: string; url: string } | null>(null);
  const [selectedCategory, setSelectedCategory] = useState<CategoryId>('account');

  useFocusEffect(
    useCallback(() => {
      if (flixorLoading || !isConnected) return;

      (async () => {
        setTraktProfile(await getTraktProfile());
        setPlexUser(await getPlexUser());
        setServerInfo(getConnectedServerInfo());
      })();
    }, [flixorLoading, isConnected])
  );

  // Only create goBack if onBack was provided (from sub-screen navigation)
  const goBack = onBack ? onBack : undefined;

  const renderRightChevron = useCallback(
    () => <Ionicons name="chevron-forward" size={18} color="#9ca3af" />,
    []
  );

  const plexDescription = useMemo(() => {
    if (!plexUser) return 'Not connected';
    if (serverInfo) return `${plexUser?.username || plexUser?.title || 'Connected'} · ${serverInfo.name}`;
    return plexUser?.username || plexUser?.title || 'Connected';
  }, [plexUser, serverInfo]);

  const renderAccount = () => (
    <SettingsCard title="ACCOUNT">
      <SettingItem
        title="Plex"
        description={plexDescription}
        renderIcon={() => <PlexIcon size={18} color="#e5e7eb" />}
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('PlexSettings')}
        isLast={true}
      />
    </SettingsCard>
  );

  const renderContent = () => (
    <>
      <SettingsCard title="DISCOVERY MODE">
        <SettingItem
          title="Library Only Mode"
          description="Turn off all discovery features. Only show content from your Plex library."
          icon="eye-off-outline"
          renderRight={() => (
            <Switch
              value={settings.discoveryDisabled}
              onValueChange={async (value) => {
                await setDiscoveryDisabled(value);
                updateSetting('discoveryDisabled', value);
                if (value) {
                  updateSetting('showTrendingRows', false);
                  updateSetting('showTraktRows', false);
                  updateSetting('showPlexPopularRow', false);
                  updateSetting('showNewHotTab', false);
                  updateSetting('includeTmdbInSearch', false);
                }
              }}
              trackColor={{ false: 'rgba(255,255,255,0.2)', true: '#FF6B6B' }}
            />
          )}
          isLast={true}
        />
      </SettingsCard>
      <SettingsCard title="CONTENT & DISCOVERY">
        <SettingItem
          title="Catalogs"
          description="Choose which libraries appear"
          icon="albums-outline"
          renderRight={renderRightChevron}
          onPress={() => nav.navigate('CatalogSettings')}
          isLast={false}
        />
      <SettingItem
        title="Home Screen"
        description="Hero and row visibility"
        icon="home-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('HomeScreenSettings')}
        isLast={false}
      />
      <SettingItem
        title="Details Screen"
        description="Ratings and badges display"
        icon="information-circle-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('DetailsScreenSettings')}
        isLast={false}
      />
      <SettingItem
        title="Continue Watching"
        description="Playback and cache behavior"
        icon="play-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('ContinueWatchingSettings')}
        isLast={false}
      />
      <SettingItem
        title="Bottom App Bar"
        description="Tab visibility settings"
        icon="apps-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('BottomAppBarSettings')}
        isLast={false}
      />
      <SettingItem
        title="Search"
        description="Search sources and behavior"
        icon="search-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('SearchSettings')}
        isLast={true}
      />
    </SettingsCard>
    </>
  );

  const renderAppearance = () => (
    <SettingsCard title="APPEARANCE">
      <SettingItem
        title="Episode Layout"
        description={settings.episodeLayoutStyle === 'horizontal' ? 'Horizontal' : 'Vertical'}
        icon="grid-outline"
        renderRight={() => (
          <Switch
            value={settings.episodeLayoutStyle === 'horizontal'}
            onValueChange={(value) =>
              updateSetting('episodeLayoutStyle', value ? 'horizontal' : 'vertical')
            }
          />
        )}
        isLast={false}
      />
      <SettingItem
        title="Streams Backdrop"
        description="Show dimmed backdrop behind player settings"
        icon="image-outline"
        renderRight={() => (
          <Switch
            value={settings.enableStreamsBackdrop}
            onValueChange={(value) => updateSetting('enableStreamsBackdrop', value)}
          />
        )}
        isLast={true}
      />
    </SettingsCard>
  );

  const renderAndroidPerformance = () => (
    <SettingsCard title="ANDROID PERFORMANCE">
      <SettingItem
        title="Enable Blur Effects"
        description="Enable blur view effects. May impact performance on some devices."
        icon="sparkles-outline"
        renderRight={() => (
          <Switch
            value={settings.enableAndroidBlurView}
            onValueChange={(value) => updateSetting('enableAndroidBlurView', value)}
          />
        )}
        isLast={true}
      />
    </SettingsCard>
  );

  const renderIntegrations = () => (
    <SettingsCard title="INTEGRATIONS">
      <SettingItem
        title="TMDB"
        description="Metadata and language (always enabled)"
        renderIcon={() => <TMDBIcon size={18} color="#e5e7eb" />}
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('TMDBSettings')}
        isLast={false}
      />
      <SettingItem
        title="MDBList (Multi-source)"
        description={settings.mdblistEnabled ? 'Enabled' : 'Disabled'}
        renderIcon={() => <MDBListIcon size={18} color="#e5e7eb" />}
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('MDBListSettings')}
        isLast={false}
      />
      <SettingItem
        title="Trakt"
        description={traktProfile ? `@${traktProfile?.username || traktProfile?.ids?.slug}` : 'Sign in to sync'}
        renderIcon={() => <TraktIcon size={18} color="#e5e7eb" />}
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('TraktSettings')}
        isLast={false}
      />
      <SettingItem
        title="Overseerr"
        description={settings.overseerrEnabled ? 'Enabled' : 'Disabled'}
        renderIcon={() => <OverseerrIcon size={18} color="#e5e7eb" />}
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('OverseerrSettings')}
        isLast={true}
      />
    </SettingsCard>
  );

  const renderPlayback = () => (
    <SettingsCard title="PLAYBACK">
      <SettingItem
        title="Video Player"
        description="Coming soon"
        icon="play-circle-outline"
        renderRight={() => <Text style={styles.comingSoon}>Soon</Text>}
        disabled
        isLast={false}
      />
      <SettingItem
        title="Auto-play Best Stream"
        description="Coming soon"
        icon="flash-outline"
        renderRight={() => <Switch value={false} onValueChange={() => {}} disabled />}
        disabled
        isLast={false}
      />
      <SettingItem
        title="Always Resume"
        description="Coming soon"
        icon="refresh-outline"
        renderRight={() => <Switch value={false} onValueChange={() => {}} disabled />}
        disabled
        isLast={true}
      />
    </SettingsCard>
  );

  const renderAbout = () => (
    <SettingsCard title="ABOUT">
      <SettingItem
        title="Privacy Policy"
        description="Review how data is handled"
        icon="shield-outline"
        renderRight={renderRightChevron}
        onPress={() => Linking.openURL(ABOUT_LINKS.privacy)}
        isLast={false}
      />
      <SettingItem
        title="Report Issue"
        description="Open a GitHub issue"
        icon="bug-outline"
        renderRight={renderRightChevron}
        onPress={() => Linking.openURL(ABOUT_LINKS.reportIssue)}
        isLast={false}
      />
      <SettingItem
        title="Contributors"
        description="Project contributors"
        icon="people-outline"
        renderRight={renderRightChevron}
        onPress={() => Linking.openURL(ABOUT_LINKS.contributors)}
        isLast={false}
      />
      <SettingItem
        title="Version"
        description={`${getAppVersion()}`}
        icon="information-circle-outline"
        isLast={false}
      />
      <SettingItem
        title="App Updates"
        description="Check for OTA updates"
        icon="cloud-download-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('UpdateSettings')}
        isLast={false}
      />
      <SettingItem
        title="Discord"
        description="Join the community"
        icon="chatbubbles-outline"
        renderRight={renderRightChevron}
        onPress={() => Linking.openURL(ABOUT_LINKS.discord)}
        isLast={false}
      />
      <SettingItem
        title="Reddit"
        description="Follow updates"
        icon="chatbox-ellipses-outline"
        renderRight={renderRightChevron}
        onPress={() => Linking.openURL(ABOUT_LINKS.reddit)}
        isLast={true}
      />
    </SettingsCard>
  );

  const renderCategory = (category: CategoryId) => {
    switch (category) {
      case 'account':
        return renderAccount();
      case 'content':
        return renderContent();
      case 'appearance':
        return renderAppearance();
      case 'androidPerformance':
        return renderAndroidPerformance();
      case 'integrations':
        return renderIntegrations();
      case 'playback':
        return renderPlayback();
      case 'about':
        return renderAbout();
      default:
        return null;
    }
  };

  // Filter categories based on platform
  const visibleCategories = useMemo(() =>
    CATEGORIES.filter(cat => !cat.androidOnly || Platform.OS === 'android'),
    []
  );

  if (isTablet) {
    return (
      <View style={styles.container}>
        <SettingsHeader title="Settings" onBack={goBack} scrollY={scrollY} />
        <View style={[styles.tabletLayout, { paddingTop: headerHeight }]}>
          <View style={styles.sidebar}>
            {visibleCategories.map((cat) => (
              <Pressable
                key={cat.id}
                onPress={() => setSelectedCategory(cat.id)}
                style={[
                  styles.sidebarItem,
                  selectedCategory === cat.id && styles.sidebarItemActive,
                ]}
              >
                <Ionicons
                  name={cat.icon}
                  size={18}
                  color={selectedCategory === cat.id ? '#fff' : '#9ca3af'}
                />
                <Text
                  style={[
                    styles.sidebarText,
                    selectedCategory === cat.id && styles.sidebarTextActive,
                  ]}
                >
                  {cat.title}
                </Text>
              </Pressable>
            ))}
          </View>
          <Animated.ScrollView
            contentContainerStyle={[
              styles.tabletContent,
              { paddingBottom: insets.bottom + 100 }
            ]}
            onScroll={Animated.event(
              [{ nativeEvent: { contentOffset: { y: scrollY } } }],
              { useNativeDriver: false }
            )}
            scrollEventThrottle={16}
          >
            {renderCategory(selectedCategory)}
          </Animated.ScrollView>
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <SettingsHeader title="Settings" onBack={goBack} scrollY={scrollY} />
      <Animated.ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }
        ]}
        onScroll={Animated.event(
          [{ nativeEvent: { contentOffset: { y: scrollY } } }],
          { useNativeDriver: false }
        )}
        scrollEventThrottle={16}
      >
        {renderAccount()}
        {renderContent()}
        {renderAppearance()}
        {Platform.OS === 'android' && renderAndroidPerformance()}
        {renderIntegrations()}
        {renderPlayback()}
        {renderAbout()}
      </Animated.ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0b0b0d',
  },
  content: {
    paddingHorizontal: 16,
  },
  comingSoon: {
    color: '#9ca3af',
    fontSize: 12,
    fontWeight: '600',
  },
  tabletLayout: {
    flex: 1,
    flexDirection: 'row',
  },
  sidebar: {
    width: 260,
    paddingHorizontal: 12,
    paddingTop: 8,
    borderRightWidth: 1,
    borderRightColor: 'rgba(255,255,255,0.08)',
  },
  sidebarItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 12,
    marginBottom: 6,
  },
  sidebarItemActive: {
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  sidebarText: {
    color: '#9ca3af',
    fontSize: 14,
    fontWeight: '600',
  },
  sidebarTextActive: {
    color: '#fff',
  },
  tabletContent: {
    paddingHorizontal: 20,
    flexGrow: 1,
  },
});
