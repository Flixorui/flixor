import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { View, Text, ScrollView, Pressable, ActivityIndicator, StyleSheet, Animated, InteractionManager } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { TopBarStore } from '../components/TopBarStore';
import { TOP_BAR_EXPANDED_CONTENT_HEIGHT } from '../components/topBarMetrics';
import * as Haptics from 'expo-haptics';
import { useFlixor } from '../core/FlixorContext';
import { IMAGE_PRELOAD_CAP, CACHE_TTL, isCacheValid } from '../core/PerformanceConfig';
import {
  getUpcomingMovies,
  getTrendingAll,
  getTop10Shows,
  getTop10Movies,
  getWorthTheWait,
  fetchPreferredBackdrops,
  ContentItem,
  TrendingPeriod,
} from '../core/NewHotData';
import { useAppMode } from '../core/AppMode';
import { useTheme } from '../hooks/useTheme';
import Chip from '../components/collections/Chip';

type TabType = 'coming-soon' | 'worth-the-wait' | 'everyones-watching' | 'top10-shows' | 'top10-movies';

const PERIOD_TABS: TabType[] = ['everyones-watching', 'top10-shows', 'top10-movies'];

const TABS = [
  { id: 'coming-soon' as const, label: 'Coming Soon' },
  { id: 'worth-the-wait' as const, label: 'Worth the Wait' },
  { id: 'everyones-watching' as const, label: "Everyone's Watching" },
  { id: 'top10-shows' as const, label: 'Top 10 Shows' },
  { id: 'top10-movies' as const, label: 'Top 10 Movies' },
];

// Persistent store for caching content across mounts (like NuvioStreaming)
const persistentStore: {
  'coming-soon': ContentItem[] | null;
  'worth-the-wait': ContentItem[] | null;
  'everyones-watching': ContentItem[] | null;
  'top10-shows': ContentItem[] | null;
  'top10-movies': ContentItem[] | null;
  lastFetchTime: Record<TabType, number>;
} = {
  'coming-soon': null,
  'worth-the-wait': null,
  'everyones-watching': null,
  'top10-shows': null,
  'top10-movies': null,
  lastFetchTime: {
    'coming-soon': 0,
    'worth-the-wait': 0,
    'everyones-watching': 0,
    'top10-shows': 0,
    'top10-movies': 0,
  },
};

// Survives remounts along with the cached lists it describes
const persistentPeriod: { value: TrendingPeriod } = { value: 'week' };

// TabPill component - defined outside to be available in useMemo
function TabPill({ active, label, onPress }: { active?: boolean; label: string; onPress?: () => void }) {
  const handlePress = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    onPress?.();
  };

  return (
    <Pressable onPress={handlePress} style={[styles.tabPill, active && styles.tabPillActive]}>
      <Text style={[styles.tabPillText, { color: active ? '#000' : '#fff' }]}>{label}</Text>
    </Pressable>
  );
}

export default function NewHot() {
  const nav: any = useNavigation();
  const { isConnected } = useFlixor();
  const { isStremioOnly } = useAppMode();
  // TMDB supplies everything here, so Stremio-only mode has nothing to wait for
  const ready = isConnected || isStremioOnly;
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const [period, setPeriod] = useState<TrendingPeriod>(persistentPeriod.value);
  const loadId = useRef(0);
  const [activeTab, setActiveTab] = useState<TabType>('coming-soon');
  const [loading, setLoading] = useState(false);
  // Initialize from persistent store for instant render
  const [content, setContent] = useState<ContentItem[]>(() => persistentStore['coming-soon'] || []);
  const y = useRef(new Animated.Value(0)).current;
  // Use stable local barHeight - calculate once based on typical safe area
  const barHeight = insets.top + TOP_BAR_EXPANDED_CONTENT_HEIGHT;

  // Tab pills for TopAppBar customFilters
  const tabPills = useMemo(() => (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ paddingHorizontal: 16, alignItems: 'center'}}
      style={{ flexGrow: 0 }}
    >
      {TABS.map((tab) => (
        <TabPill
          key={tab.id}
          active={activeTab === tab.id}
          label={tab.label}
          onPress={() => setActiveTab(tab.id)}
        />
      ))}
    </ScrollView>
  ), [activeTab]);

  // Update TopBarStore with NewHot configuration when focused
  useFocusEffect(
    useCallback(() => {
      TopBarStore.setState({
        visible: true,
        tabBarVisible: true,
        showFilters: false,
        compact: true,
        customFilters: tabPills,
        activeGenre: undefined,
        onClearGenre: undefined,
      });
      TopBarStore.setScrollY(y);
    }, [tabPills, nav, y])
  );

  // When tab changes, load from persistent cache first for instant display
  useEffect(() => {
    const cached = persistentStore[activeTab];
    if (cached && cached.length > 0) {
      setContent(cached);
    }
  }, [activeTab]);

  useEffect(() => {
    if (ready) {
      // Check if cache is still valid
      if (isCacheValid(persistentStore.lastFetchTime[activeTab], CACHE_TTL.NEW_HOT) && persistentStore[activeTab]) {
        // Use cached data, no need to refetch
        return;
      }
      loadContent();
    }
  }, [ready, activeTab, period]);

  const changePeriod = (next: TrendingPeriod) => {
    if (next === period) return;
    persistentPeriod.value = next;
    // The cached lists belong to the old period
    PERIOD_TABS.forEach((tab) => {
      persistentStore[tab] = null;
      persistentStore.lastFetchTime[tab] = 0;
    });
    setPeriod(next);
  };

  const loadContent = async () => {
    if (!ready) return;

    const id = ++loadId.current;
    const tab = activeTab;
    setLoading(true);
    try {
      let items: ContentItem[] = [];
      switch (activeTab) {
        case 'coming-soon':
          items = await getUpcomingMovies();
          break;
        case 'worth-the-wait':
          items = await getWorthTheWait();
          break;
        case 'everyones-watching':
          items = await getTrendingAll(period);
          break;
        case 'top10-shows':
          items = await getTop10Shows(period);
          break;
        case 'top10-movies':
          items = await getTop10Movies(period);
          break;
      }
      // Update persistent store
      persistentStore[tab] = items;
      persistentStore.lastFetchTime[tab] = Date.now();
      // The user moved on while this was loading
      if (id !== loadId.current) return;

      // Preload images for smoother scrolling
      const imagesToPreload = items
        .slice(0, IMAGE_PRELOAD_CAP)
        .filter((item) => item.backdropImage)
        .map((item) => ({ uri: item.backdropImage! }));
      if (imagesToPreload.length > 0) {
        FastImage.preload(imagesToPreload);
      }
      // Use InteractionManager to defer state updates for smoother UI
      InteractionManager.runAfterInteractions(() => {
        setContent(items);
      });

      // Fetch preferred backdrops with titles asynchronously
      fetchPreferredBackdrops(items).then((backdrops) => {
        if (Object.keys(backdrops).length > 0) {
          // Update persistent store with backdrops
          const updatedItems = items.map((item) => ({
            ...item,
            backdropImage: backdrops[item.id] || item.backdropImage,
          }));
          persistentStore[tab] = updatedItems;

          InteractionManager.runAfterInteractions(() => {
            if (id === loadId.current) setContent(updatedItems);
          });
        }
      });
    } catch (error) {
      console.error('[NewHot] Failed to load content:', error);
    } finally {
      InteractionManager.runAfterInteractions(() => {
        if (id === loadId.current) setLoading(false);
      });
    }
  };

  const handleItemPress = (id: string) => {
    if (id.startsWith('plex:')) {
      const rk = id.split(':')[1];
      nav.navigate('Details', { type: 'plex', ratingKey: rk });
    } else if (id.startsWith('tmdb:')) {
      const [, media, tmdbId] = id.split(':');
      nav.navigate('Details', { type: 'tmdb', mediaType: media, id: tmdbId });
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: '#0a0a0a' }}>
      {/* Gradients */}
      <LinearGradient
        colors={['#0a0a0a', '#0f0f10', '#0b0c0d']}
        start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />

      <View style={{ flex: 1 }}>
        {/* TopAppBar is rendered globally above this content */}

        {/* Scrollable content - tab pills are now in TopAppBar */}
        <Animated.ScrollView 
          style={{ flex: 1 }} 
          contentContainerStyle={{ paddingTop: barHeight, paddingBottom: 80 }}
          scrollEventThrottle={16}
          onScroll={Animated.event([
            { nativeEvent: { contentOffset: { y } } }
          ], { useNativeDriver: false })}
        >
          {PERIOD_TABS.includes(activeTab) ? (
            <View style={styles.periods}>
              <Chip label="Today" active={period === 'day'} onPress={() => changePeriod('day')} />
              <Chip label="This Week" active={period === 'week'} onPress={() => changePeriod('week')} />
            </View>
          ) : null}

          {/* Content */}
          {loading ? (
            <View style={{ alignItems: 'center', paddingTop: 40 }}>
              <ActivityIndicator color="#fff" size="large" />
            </View>
          ) : (
            <View style={{ paddingTop: 16 }}>
              {content.map((item, index) => (
                <Pressable
                  key={index}
                  onPress={() => handleItemPress(item.id)}
                  style={styles.contentCard}
                >
                  {/* Backdrop Image */}
                  <View style={styles.backdropContainer}>
                    {item.backdropImage ? (
                      <FastImage
                        source={{
                          uri: item.backdropImage,
                          priority: FastImage.priority.normal,
                          cache: FastImage.cacheControl.immutable,
                        }}
                        style={{ width: '100%', height: '100%' }}
                        resizeMode={FastImage.resizeMode.cover}
                      />
                    ) : (
                      <View style={{ width: '100%', height: '100%', backgroundColor: '#1a1a1a' }} />
                    )}

                    {/* Rank badge for Top 10 */}
                    {item.rank && (
                      <View style={[styles.rankBadge, { backgroundColor: 'rgba(0,0,0,0.6)' }]}>
                        <Text style={styles.rankNumber}>{item.rank}</Text>
                      </View>
                    )}

                    {/* Mute icon */}
                    <View style={styles.muteIcon}>
                      <Ionicons name="volume-mute" size={20} color="#fff" />
                    </View>
                  </View>

                  {/* Title and Info */}
                  <View style={styles.contentInfo}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.contentTitle}>{item.title}</Text>
                      {item.releaseDate && (
                        <Text style={styles.releaseDate}>Coming on {item.releaseDate}</Text>
                      )}
                      {item.description && (
                        <Text style={styles.description} numberOfLines={3}>
                          {item.description}
                        </Text>
                      )}
                    </View>
                  </View>
                </Pressable>
              ))}
            </View>
          )}
        </Animated.ScrollView>

      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  periods: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingTop: 12,
  },
  tabPill: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#4a4a4a',
    backgroundColor: 'transparent',
    marginRight: 8,
  },
  tabPillActive: {
    backgroundColor: '#fff',
    borderColor: '#fff',
  },
  tabPillText: {
    fontWeight: '600',
    fontSize: 14,
  },
  contentCard: {
    marginBottom: 24,
    paddingHorizontal: 16,
  },
  backdropContainer: {
    width: '100%',
    aspectRatio: 16 / 9,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#1a1a1a',
    marginBottom: 12,
  },
  rankBadge: {
    position: 'absolute',
    bottom: 8,
    left: 8,
    width: 40,
    height: 40,
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rankNumber: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '900',
  },
  muteIcon: {
    position: 'absolute',
    bottom: 8,
    right: 8,
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(0,0,0,0.6)',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: '#fff',
  },
  contentInfo: {
    gap: 12,
  },
  contentTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 4,
  },
  releaseDate: {
    color: '#aaa',
    fontSize: 13,
    marginBottom: 8,
  },
  description: {
    color: '#ccc',
    fontSize: 14,
    lineHeight: 20,
  },
  remindButton: {
    alignItems: 'center',
    gap: 4,
  },
  remindText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
});
