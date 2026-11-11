/**
 * Settings root: the same five groups and pages as the macOS Settings sidebar, as an iOS
 * grouped list with search. Each row opens its page; values show on the right.
 * macOS reference: Views/Settings/SettingsView.swift (SettingsCategory, SidebarSection)
 */

import React, { useCallback, useMemo, useRef, useState } from 'react';
import * as Top10Store from '../core/top10/Top10Store';
import { View, Text, StyleSheet, Pressable, Animated, TextInput, Dimensions } from 'react-native';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useFlixor } from '../core/FlixorContext';
import ProfileAvatar from '../components/ProfileAvatar';
import { getTraktProfile, getPlexUser, getConnectedServerInfo } from '../core/SettingsData';
import { useAppSettings } from '../hooks/useAppSettings';
import SettingsHeader from '../components/settings/SettingsHeader';
import MDBListIcon from '../components/icons/MDBListIcon';
import TMDBIcon from '../components/icons/TMDBIcon';
import TraktIcon from '../components/icons/TraktIcon';
import PlexIcon from '../components/icons/PlexIcon';
import OverseerrIcon from '../components/icons/OverseerrIcon';
import { useTheme } from '../hooks/useTheme';
import { clearAppMode, useAppMode } from '../core/AppMode';

const isTablet = Dimensions.get('window').width >= 768;

interface Row {
  id: string;
  title: string;
  /** Shown on the right, iOS Settings style. */
  value?: string;
  /** Matched by search along with the title (macOS uses the same idea). */
  keywords: string;
  tile: string;
  icon?: keyof typeof Ionicons.glyphMap;
  renderIcon?: () => React.ReactNode;
  onPress: () => void;
}

interface Group {
  title: string;
  rows: Row[];
}

interface SettingsProps {
  onLogout?: () => Promise<void>;
  onBack?: () => void;
}

export default function Settings({ onBack }: SettingsProps) {
  const nav: any = useNavigation();
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const scrollY = useRef(new Animated.Value(0)).current;
  const { isLoading: flixorLoading, isConnected, activeProfile, hasMultipleProfiles } = useFlixor();
  const { settings } = useAppSettings();
  const { isStremioOnly } = useAppMode();
  const [traktProfile, setTraktProfile] = useState<any | null>(null);
  const [plexUser, setPlexUser] = useState<any | null>(null);
  const [serverInfo, setServerInfo] = useState<{ name: string; url: string } | null>(null);
  const [query, setQuery] = useState('');

  useFocusEffect(
    useCallback(() => {
      if (flixorLoading || (!isConnected && !isStremioOnly)) return;
      (async () => {
        setTraktProfile(await getTraktProfile());
        if (isStremioOnly) return;
        setPlexUser(await getPlexUser());
        setServerInfo(getConnectedServerInfo());
      })();
    }, [flixorLoading, isConnected, isStremioOnly])
  );

  const go = useCallback((route: string) => () => nav.navigate(route), [nav]);
  const onOff = (on: boolean) => (on ? 'On' : 'Off');

  // Top 10 Lists: how many sources are set up
  const top10Version = Top10Store.useTop10Version();
  React.useEffect(() => {
    Top10Store.initTop10();
  }, []);
  const top10Summary = useMemo(() => {
    const count = Top10Store.sourceInfos().length + Top10Store.keyInfos().length;
    if (!count) return 'Not set up';
    return settings.top10Enabled ? `${count} source${count === 1 ? '' : 's'}` : 'Off';
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [top10Version, settings.top10Enabled]);

  const groups: Group[] = useMemo(() => {
    const plexValue = isStremioOnly
      ? 'Not connected'
      : serverInfo?.name || plexUser?.username || plexUser?.title || (isConnected ? 'Connected' : 'Not connected');
    const sources: Row[] = [
      {
        id: 'plex',
        title: 'Plex',
        value: plexValue,
        keywords: 'account servers sign out connect libraries',
        tile: '#272A2D',
        renderIcon: () => <PlexIcon size={17} color="#fff" />,
        onPress: isStremioOnly ? () => clearAppMode() : go('PlexSettings'),
      },
    ];
    if (!isStremioOnly && hasMultipleProfiles) {
      sources.push({
        id: 'profile',
        title: 'Profile',
        value: activeProfile?.title || 'Main',
        keywords: 'switch profile plex home user',
        tile: '#3A3A3C',
        renderIcon: () => <ProfileAvatar thumb={activeProfile?.thumb} title={activeProfile?.title || 'Main'} size={22} />,
        onPress: go('ProfileSelect'),
      });
    }
    sources.push({
      id: 'stremio',
      title: 'Stremio',
      value: onOff(settings.stremioPlaybackEnabled),
      keywords: 'addons subtitles alternate playback sources streams',
      tile: '#6D4FD8',
      icon: 'extension-puzzle',
      onPress: go('StremioSettings'),
    });

    return [
      { title: 'Sources', rows: sources },
      {
        title: 'Playback & Content',
        rows: [
          {
            id: 'player',
            title: 'Player',
            keywords: 'playback skip intro credits recap auto-play next subtitles audio tracks speed seek backdrop',
            tile: '#0A84FF',
            icon: 'play',
            onPress: go('PlayerSettings'),
          },
          {
            id: 'trailers',
            title: 'Trailers',
            value: onOff(settings.detailsHeroInlineTrailerEnabled),
            keywords: 'trailer trailers autoplay inline video preview new & hot details hero muted sound data',
            tile: '#FF9F0A',
            icon: 'film',
            onPress: go('TrailerSettings'),
          },
          {
            id: 'content',
            title: 'Content',
            value: settings.discoveryDisabled ? 'Library Only' : undefined,
            keywords: 'catalogs libraries library mapping discovery library only search tmdb results addon catalogs',
            tile: '#A64FD8',
            icon: 'albums',
            onPress: go('ContentSettings'),
          },
        ],
      },
      {
        title: 'Screens',
        rows: [
          {
            id: 'home',
            title: 'Home',
            keywords: 'home screen hero rows arrange continue watching posters titles rating badges cards',
            tile: '#5E5CE6',
            icon: 'home',
            onPress: go('HomeScreenSettings'),
          },
          {
            id: 'details',
            title: 'Details',
            keywords: 'details screen sections episodes layout season picker spoilers ratings',
            tile: '#2AA3BD',
            icon: 'information-circle',
            onPress: go('DetailsScreenSettings'),
          },
          {
            id: 'navigation',
            title: 'Navigation',
            keywords: 'tabs bottom app bar tab bar new & hot downloads my list tab labels titles text tab glow',
            tile: '#3B9FD6',
            icon: 'apps',
            onPress: go('BottomAppBarSettings'),
          },
        ],
      },
      {
        title: 'Integrations',
        rows: [
          {
            id: 'tmdb',
            title: 'TMDB',
            keywords: 'artwork metadata language the movie database',
            tile: '#042541',
            renderIcon: () => <TMDBIcon size={17} color="#fff" />,
            onPress: go('TMDBSettings'),
          },
          {
            id: 'mdblist',
            title: 'MDBList',
            value: onOff(settings.mdblistEnabled),
            keywords: 'ratings imdb rotten tomatoes letterboxd metacritic',
            tile: '#4284CA',
            renderIcon: () => <MDBListIcon size={17} color="#fff" />,
            onPress: go('MDBListSettings'),
          },
          {
            id: 'overseerr',
            title: 'Overseerr',
            value: onOff(settings.overseerrEnabled),
            keywords: 'requests request movies shows',
            tile: '#0B1223',
            renderIcon: () => <OverseerrIcon size={17} color="#fff" />,
            onPress: go('OverseerrSettings'),
          },
          {
            id: 'trakt',
            title: 'Trakt',
            value: traktProfile ? `@${traktProfile?.username || traktProfile?.ids?.slug}` : 'Not signed in',
            keywords: 'watch history scrobbling sync ratings watchlist lists',
            tile: '#ED1C24',
            renderIcon: () => <TraktIcon size={17} color="#fff" />,
            onPress: go('TraktSettings'),
          },
          {
            id: 'top10',
            title: 'Top 10 Lists',
            value: top10Summary,
            keywords: 'flixpatrol streaming availability movie of the night top 10 netflix prime disney apple max paramount hulu starz hotstar api key new this week',
            tile: '#7C3AED',
            icon: 'list',
            onPress: go('Top10ListsSettings'),
          },
        ],
      },
      {
        title: 'Browse',
        rows: [
          {
            id: 'entities',
            title: 'Studios & Networks',
            keywords: 'companies networks browse',
            tile: '#8E8E93',
            icon: 'business',
            onPress: go('EntityBrowse'),
          },
          {
            id: 'collections',
            title: 'Your Collections',
            keywords: 'collections lists custom',
            tile: '#8E8E93',
            icon: 'albums',
            onPress: go('UserCollection'),
          },
        ],
      },
      {
        title: 'General',
        rows: [
          {
            id: 'appearance',
            title: 'Appearance',
            keywords: 'theme accent colour color background pure black',
            tile: '#E0405F',
            icon: 'color-palette',
            onPress: go('AppearanceSettings'),
          },
          {
            id: 'advanced',
            title: 'Advanced',
            keywords: 'debug logging logs clear cache reset settings blur',
            tile: '#6E6E73',
            icon: 'construct',
            onPress: go('AdvancedSettings'),
          },
          {
            id: 'about',
            title: 'About',
            keywords: 'version updates privacy discord reddit github report issue',
            tile: '#55555A',
            icon: 'information',
            onPress: go('AboutSettings'),
          },
        ],
      },
    ];
  }, [
    top10Summary,
    isStremioOnly,
    isConnected,
    serverInfo,
    plexUser,
    hasMultipleProfiles,
    activeProfile,
    settings.stremioPlaybackEnabled,
    settings.discoveryDisabled,
    settings.detailsHeroInlineTrailerEnabled,
    settings.mdblistEnabled,
    settings.overseerrEnabled,
    traktProfile,
    go,
  ]);

  const visibleGroups = useMemo(() => {
    const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.length) return groups;
    return groups
      .map((g) => ({
        ...g,
        rows: g.rows.filter((r) => {
          const haystack = `${r.title} ${r.keywords} ${g.title}`.toLowerCase();
          return terms.every((t) => haystack.includes(t));
        }),
      }))
      .filter((g) => g.rows.length);
  }, [groups, query]);

  return (
    <View style={[styles.container, { backgroundColor: theme.settingsBackground }]}>
      <SettingsHeader title="Settings" onBack={onBack} scrollY={scrollY} />
      <Animated.ScrollView
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        contentContainerStyle={[
          styles.content,
          isTablet && styles.contentTablet,
          { paddingTop: headerHeight + 8, paddingBottom: insets.bottom + 100 },
        ]}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: false })}
        scrollEventThrottle={16}
      >
        <View style={styles.search}>
          <Ionicons name="search" size={16} color="rgba(235,235,245,0.6)" />
          <TextInput
            value={query}
            onChangeText={setQuery}
            placeholder="Search"
            placeholderTextColor="rgba(235,235,245,0.6)"
            style={styles.searchInput}
            autoCorrect={false}
            autoCapitalize="none"
            clearButtonMode="while-editing"
            returnKeyType="search"
            accessibilityLabel="Search settings"
          />
        </View>

        {visibleGroups.map((group) => (
          <View key={group.title} style={styles.group}>
            <Text style={styles.groupTitle}>{group.title}</Text>
            <View style={[styles.card, { backgroundColor: theme.surface }]}>
              {group.rows.map((row, index) => (
                <Pressable
                  key={row.id}
                  onPress={row.onPress}
                  style={({ pressed }) => [styles.row, pressed && styles.rowPressed]}
                  accessibilityRole="button"
                  accessibilityLabel={row.value ? `${row.title}, ${row.value}` : row.title}
                >
                  <View style={[styles.tile, { backgroundColor: row.tile }]}>
                    {row.renderIcon ? row.renderIcon() : <Ionicons name={row.icon ?? 'settings'} size={17} color="#fff" />}
                  </View>
                  <View style={[styles.rowBody, index < group.rows.length - 1 && styles.rowDivider]}>
                    <Text style={styles.rowTitle} numberOfLines={1}>{row.title}</Text>
                    {row.value ? <Text style={styles.rowValue} numberOfLines={1}>{row.value}</Text> : null}
                    <Ionicons name="chevron-forward" size={16} color="rgba(235,235,245,0.3)" />
                  </View>
                </Pressable>
              ))}
            </View>
          </View>
        ))}

        {visibleGroups.length === 0 ? (
          <Text style={styles.noResults}>No settings match "{query.trim()}"</Text>
        ) : null}
      </Animated.ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { paddingHorizontal: 16 },
  contentTablet: { alignSelf: 'center', width: '100%', maxWidth: 640 },
  search: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    height: 38,
    paddingHorizontal: 10,
    borderRadius: 10,
    backgroundColor: 'rgba(118,118,128,0.24)',
    marginBottom: 20,
  },
  searchInput: { flex: 1, color: '#fff', fontSize: 17, paddingVertical: 0 },
  group: { marginBottom: 24 },
  groupTitle: {
    color: 'rgba(235,235,245,0.6)',
    fontSize: 13,
    fontWeight: '500',
    marginLeft: 16,
    marginBottom: 7,
  },
  card: { borderRadius: 12, overflow: 'hidden' },
  row: { flexDirection: 'row', alignItems: 'center', paddingLeft: 14, minHeight: 48 },
  rowPressed: { backgroundColor: 'rgba(255,255,255,0.08)' },
  tile: { width: 30, height: 30, borderRadius: 7, alignItems: 'center', justifyContent: 'center', marginRight: 14 },
  rowBody: { flex: 1, flexDirection: 'row', alignItems: 'center', minHeight: 48, paddingRight: 12, gap: 8 },
  rowDivider: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: 'rgba(84,84,88,0.65)' },
  rowTitle: { flex: 1, color: '#fff', fontSize: 17 },
  rowValue: { color: 'rgba(235,235,245,0.6)', fontSize: 17, maxWidth: '50%' },
  noResults: { color: 'rgba(235,235,245,0.6)', fontSize: 15, textAlign: 'center', marginTop: 40 },
});
