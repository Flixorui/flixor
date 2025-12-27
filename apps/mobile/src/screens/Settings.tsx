import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, Text, ScrollView, StyleSheet, Switch, Dimensions, Linking, Pressable, Animated } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFlixor } from '../core/FlixorContext';
import {
  getTraktProfile,
  getPlexUser,
  getConnectedServerInfo,
  getAppVersion,
} from '../core/SettingsData';
import { useAppSettings } from '../hooks/useAppSettings';
import SettingsCard from '../components/settings/SettingsCard';
import SettingItem from '../components/settings/SettingItem';
import SettingsHeader from '../components/settings/SettingsHeader';

const { width } = Dimensions.get('window');
const isTablet = width >= 768;

const ABOUT_LINKS = {
  privacy: 'https://flixor.app/privacy',
  reportIssue: 'https://github.com/flixor/flixor/issues',
  contributors: 'https://github.com/flixor/flixor',
  discord: 'https://discord.gg/flixor',
  reddit: 'https://www.reddit.com/r/flixor/',
};

type CategoryId =
  | 'account'
  | 'content'
  | 'appearance'
  | 'integrations'
  | 'playback'
  | 'about';

const CATEGORIES: Array<{ id: CategoryId; title: string; icon: keyof typeof Ionicons.glyphMap }> = [
  { id: 'account', title: 'Account', icon: 'person-circle-outline' },
  { id: 'content', title: 'Content & Discovery', icon: 'compass-outline' },
  { id: 'appearance', title: 'Appearance', icon: 'color-palette-outline' },
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

  useEffect(() => {
    if (flixorLoading || !isConnected) return;

    (async () => {
      setTraktProfile(await getTraktProfile());
      setPlexUser(await getPlexUser());
      setServerInfo(getConnectedServerInfo());
    })();
  }, [flixorLoading, isConnected]);

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

  const traktDescription = traktProfile
    ? `@${traktProfile?.username || traktProfile?.ids?.slug}`
    : 'Sign in to sync';

  const renderAccount = () => (
    <SettingsCard title="ACCOUNT">
      <SettingItem
        title="Plex"
        description={plexDescription}
        icon="tv-outline"
        isLast={false}
      />
      <SettingItem
        title="Trakt"
        description={traktDescription}
        icon="layers-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('TraktSettings')}
        isLast={true}
      />
    </SettingsCard>
  );

  const renderContent = () => (
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
        title="Continue Watching"
        description="Playback and cache behavior"
        icon="play-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('ContinueWatchingSettings')}
        isLast={true}
      />
    </SettingsCard>
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

  const renderIntegrations = () => (
    <SettingsCard title="INTEGRATIONS">
      <SettingItem
        title="TMDB"
        description="Metadata and language preferences"
        icon="film-outline"
        renderRight={renderRightChevron}
        onPress={() => nav.navigate('TMDBSettings')}
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
        description={`v${getAppVersion()}`}
        icon="information-circle-outline"
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

  if (isTablet) {
    return (
      <View style={styles.container}>
        <SettingsHeader title="Settings" onBack={goBack} scrollY={scrollY} />
        <View style={[styles.tabletLayout, { paddingTop: headerHeight }]}>
          <View style={styles.sidebar}>
            {CATEGORIES.map((cat) => (
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
            contentContainerStyle={styles.tabletContent}
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
        contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12 }]}
        onScroll={Animated.event(
          [{ nativeEvent: { contentOffset: { y: scrollY } } }],
          { useNativeDriver: false }
        )}
        scrollEventThrottle={16}
      >
        {renderAccount()}
        {renderContent()}
        {renderAppearance()}
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
    paddingBottom: 40,
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
    paddingBottom: 40,
    flexGrow: 1,
  },
});
