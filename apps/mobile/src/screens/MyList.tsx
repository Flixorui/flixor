import React, { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { View, Text, ActivityIndicator, Pressable, StyleSheet, Dimensions, Animated, Alert, Modal, Platform } from 'react-native';
import PullToRefresh from '../components/PullToRefresh';
import { Image as ExpoImage } from 'expo-image';
import { FlashList } from '@shopify/flash-list';
import { Ionicons } from '@expo/vector-icons';
import { TopBarStore, useTopBarStore } from '../components/TopBarStore';
import { LinearGradient } from 'expo-linear-gradient';
import { BlurView } from 'expo-blur';
import { useNavigation, useIsFocused } from '@react-navigation/native';
import { useFlixor } from '../core/FlixorContext';
import {
  fetchMyList,
  getMyListPosterUrl,
  fetchTmdbPoster,
  removeFromMyList,
  isTraktConnected,
  MyListItem,
  SortOption,
  FilterOption,
} from '../core/MyListData';
import * as Haptics from 'expo-haptics';

// Conditionally import GlassView for iOS 26+ liquid glass effect
let GlassViewComp: any = null;
let liquidGlassAvailable = false;
if (Platform.OS === 'ios') {
  try {
    const glass = require('expo-glass-effect');
    GlassViewComp = glass.GlassView;
    liquidGlassAvailable = typeof glass.isLiquidGlassAvailable === 'function'
      ? glass.isLiquidGlassAvailable()
      : false;
  } catch {
    liquidGlassAvailable = false;
  }
}

// Sort options configuration (like Library)
const SORT_OPTIONS: Array<{ value: SortOption; label: string }> = [
  { value: 'added', label: 'Date Added' },
  { value: 'title', label: 'Title' },
  { value: 'year', label: 'Year' },
];

export default function MyList() {
  const nav: any = useNavigation();
  const isFocused = useIsFocused();
  const { flixor, isLoading: flixorLoading, isConnected } = useFlixor();

  const [items, setItems] = useState<MyListItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterOption>('all');
  const [sortOption, setSortOption] = useState(SORT_OPTIONS[0]);
  const [showSortModal, setShowSortModal] = useState(false);

  const y = useRef(new Animated.Value(0)).current;
  const barHeight = useTopBarStore((s) => s.height || 90);
  const lastScrollY = useRef(0);

  // Set scrollY on mount (no showPills needed - using customFilters)
  React.useLayoutEffect(() => {
    if (isFocused) {
      TopBarStore.setScrollY(y);
    }
  }, [isFocused, y]);

  // Load items
  const loadItems = useCallback(async (showRefresh = false) => {
    if (showRefresh) setRefreshing(true);
    else setLoading(true);
    setError(null);

    try {
      const result = await fetchMyList({ filter, sort: sortOption.value, sortDirection: 'desc' });
      setItems(result);
    } catch (e: any) {
      setError(e?.message || 'Failed to load watchlist');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [filter, sortOption]);

  useEffect(() => {
    if (flixorLoading || !isConnected) return;
    loadItems();
  }, [flixorLoading, isConnected, loadItems]);

  // Reload when screen comes into focus
  useEffect(() => {
    if (isFocused && !loading && !flixorLoading && isConnected) {
      loadItems(true);
    }
  }, [isFocused]);

  // Pull-to-refresh handler
  const handleRefresh = useCallback(async () => {
    console.log('[MyList] Pull-to-refresh triggered');
    setRefreshing(true);

    // Invalidate watchlist caches
    if (flixor) {
      console.log('[MyList] Clearing Plex and Trakt caches...');
      await Promise.all([
        flixor.clearPlexCache(),
        flixor.clearTraktCache(),
      ]);
      console.log('[MyList] Caches cleared');
    }

    // Reload items
    console.log('[MyList] Reloading items...');
    await loadItems(false); // false because we already set refreshing=true
    console.log('[MyList] Items reloaded');
    setRefreshing(false);
  }, [flixor, loadItems]);

  const handleRemove = useCallback(async (item: MyListItem) => {
    Alert.alert(
      'Remove from My List',
      `Remove "${item.title}" from your watchlist?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Remove',
          style: 'destructive',
          onPress: async () => {
            const success = await removeFromMyList(item);
            if (success) {
              setItems(prev => prev.filter(i => i.id !== item.id));
              Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
            } else {
              Alert.alert('Error', 'Failed to remove item');
            }
          },
        },
      ]
    );
  }, []);

  const handleItemPress = useCallback((item: MyListItem) => {
    // Navigate to details - prefer Plex if available
    if (item.plexRatingKey) {
      nav.navigate('HomeTab', {
        screen: 'Details',
        params: { type: 'plex', ratingKey: item.plexRatingKey },
      });
    } else if (item.tmdbId) {
      nav.navigate('HomeTab', {
        screen: 'Details',
        params: { type: 'tmdb', id: String(item.tmdbId), mediaType: item.type === 'movie' ? 'movie' : 'tv' },
      });
    }
  }, [nav]);

  const selectFilter = useCallback((newFilter: FilterOption) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setFilter(newFilter);
  }, []);

  // Push top bar updates synchronously before paint (useLayoutEffect)
  React.useLayoutEffect(() => {
    if (!isFocused) return;

    // Create custom filter pills
    const filterPills = (
      <View style={{ flexDirection: 'row', paddingHorizontal: 16, alignItems: 'center' }}>
        <FilterPill label="All" active={filter === 'all'} onPress={() => selectFilter('all')} />
        <FilterPill label="Movies" active={filter === 'movies'} onPress={() => selectFilter('movies')} />
        <FilterPill label="TV Shows" active={filter === 'shows'} onPress={() => selectFilter('shows')} />
      </View>
    );

    TopBarStore.setState({
      visible: true,
      tabBarVisible: true,
      showFilters: false,
      username: 'My List',
      selected: 'all',
      compact: false,
      customFilters: filterPills,
      activeGenre: undefined,
      onNavigateLibrary: undefined,
      onClose: undefined,
      onSearch: () => nav.navigate('HomeTab', { screen: 'Search' }),
      onBrowse: undefined,
      onClearGenre: undefined,
    });

    return () => {
      TopBarStore.setCustomFilters(undefined);
    };
  }, [isFocused, nav, filter, selectFilter]);

  // Show loading while FlixorCore is initializing
  if (flixorLoading || !isConnected) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#fff" />
        <Text style={styles.loadingText}>
          {flixorLoading ? 'Initializing...' : 'Connecting...'}
        </Text>
      </View>
    );
  }

  if (loading && !refreshing) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.center}>
        <Text style={styles.errorText}>{error}</Text>
        <Pressable onPress={() => loadItems()} style={styles.retry}>
          <Text style={styles.retryText}>Retry</Text>
        </Pressable>
      </View>
    );
  }

  const numColumns = Dimensions.get('window').width >= 800 ? 5 : 3;
  const itemSize = Math.floor((Dimensions.get('window').width - 16 - (numColumns - 1) * 8) / numColumns);

  return (
    <View style={styles.container}>
      {/* Background gradients */}
      <LinearGradient
        colors={['#0a0a0a', '#0f0f10', '#0b0c0d']}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />
      <LinearGradient
        colors={['rgba(122,22,18,0.24)', 'rgba(122,22,18,0.10)', 'rgba(122,22,18,0.0)']}
        start={{ x: 0.0, y: 1.0 }}
        end={{ x: 0.45, y: 0.35 }}
        style={StyleSheet.absoluteFillObject}
      />

      <PullToRefresh scrollY={y} refreshing={refreshing} onRefresh={handleRefresh} />

      {/* Items Grid */}
      {items.length === 0 ? (
        <View style={[styles.emptyContainer, { paddingTop: barHeight }]}>
          <Ionicons name="bookmark-outline" size={64} color="#444" />
          <Text style={styles.emptyTitle}>Your list is empty</Text>
          <Text style={styles.emptySubtitle}>
            {isTraktConnected()
              ? 'Add movies and shows to your watchlist to see them here'
              : 'Connect Trakt in Settings tab to sync your watchlist'}
          </Text>
        </View>
      ) : (
        <FlashList
          data={items}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <Card
              item={item}
              size={itemSize}
              onPress={() => handleItemPress(item)}
              onLongPress={() => handleRemove(item)}
            />
          )}
          estimatedItemSize={itemSize + 28}
          numColumns={numColumns}
          contentContainerStyle={{ padding: 8, paddingTop: barHeight, paddingBottom: 120 }}
          scrollEventThrottle={16}
          onScroll={(e: any) => {
            const currentY = e.nativeEvent.contentOffset.y;
            // Manually update animated value (FlashList doesn't support Animated.event properly)
            y.setValue(currentY);
            lastScrollY.current = currentY;
          }}
          ListEmptyComponent={
            <Text style={styles.emptyText}>No items</Text>
          }
        />
      )}

      {/* Floating Sort Button */}
      <Pressable
        onPress={() => setShowSortModal(true)}
        style={styles.floatingSortButton}
      >
        {liquidGlassAvailable && GlassViewComp ? (
          <GlassViewComp style={styles.floatingSortButtonGlass}>
            <Ionicons name="swap-vertical" size={20} color="#fff" />
            <Text style={styles.floatingSortButtonText}>{sortOption.label}</Text>
          </GlassViewComp>
        ) : (
          <BlurView intensity={80} tint="dark" style={styles.floatingSortButtonBlur}>
            <Ionicons name="swap-vertical" size={20} color="#fff" />
            <Text style={styles.floatingSortButtonText}>{sortOption.label}</Text>
          </BlurView>
        )}
      </Pressable>

      {/* Sort Modal - BlurView works better in modals than GlassView */}
      <Modal
        visible={showSortModal}
        transparent
        animationType="fade"
        onRequestClose={() => setShowSortModal(false)}
      >
        <Pressable style={styles.modalOverlay} onPress={() => setShowSortModal(false)}>
          <View style={styles.sortModalContent}>
            <BlurView intensity={100} tint="dark" style={styles.sortModalBlur}>
              <Text style={styles.sortModalTitle}>Sort By</Text>
              {SORT_OPTIONS.map((option) => (
                <Pressable
                  key={option.value}
                  onPress={() => {
                    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                    setSortOption(option);
                    setShowSortModal(false);
                  }}
                  style={[
                    styles.sortOption,
                    sortOption.value === option.value && styles.sortOptionActive,
                  ]}
                >
                  <Text
                    style={[
                      styles.sortOptionText,
                      sortOption.value === option.value && styles.sortOptionTextActive,
                    ]}
                  >
                    {option.label}
                  </Text>
                  {sortOption.value === option.value && (
                    <Ionicons name="checkmark" size={20} color="#fff" />
                  )}
                </Pressable>
              ))}
            </BlurView>
          </View>
        </Pressable>
      </Modal>

      {/* Custom refresh indicator above TopAppBar */}
      {refreshing && (
        <View style={{ position: 'absolute', top: barHeight + 10, left: 0, right: 0, alignItems: 'center', zIndex: 50 }}>
          <View style={{ backgroundColor: 'rgba(0,0,0,0.7)', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20, flexDirection: 'row', alignItems: 'center' }}>
            <ActivityIndicator color="#fff" size="small" />
            <Text style={{ color: '#fff', marginLeft: 8, fontSize: 13 }}>Refreshing...</Text>
          </View>
        </View>
      )}
    </View>
  );
}

function FilterPill({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  const handlePress = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    onPress();
  };

  return (
    <Pressable
      onPress={handlePress}
      style={[styles.filterPill, active && styles.filterPillActive]}
    >
      <Text style={[styles.filterPillText, { color: active ? '#000' : '#fff' }]}>{label}</Text>
    </Pressable>
  );
}

function Card({
  item,
  size,
  onPress,
  onLongPress,
}: {
  item: MyListItem;
  size: number;
  onPress?: () => void;
  onLongPress?: () => void;
}) {
  const [posterUrl, setPosterUrl] = useState<string>('');

  useEffect(() => {
    let cancelled = false;

    const loadPoster = async () => {
      // First try direct poster URL from Plex
      const url = getMyListPosterUrl(item, size * 2);
      if (url) {
        setPosterUrl(url);
        return;
      }

      // For Trakt items, fetch poster from TMDB
      if (item.tmdbId && !item.poster) {
        try {
          const tmdbUrl = await fetchTmdbPoster(item);
          if (!cancelled && tmdbUrl) {
            setPosterUrl(tmdbUrl);
          }
        } catch (e) {
          console.log('[Card] Error fetching TMDB poster:', e);
        }
      }
    };

    loadPoster();

    return () => {
      cancelled = true;
    };
  }, [item, size]);

  return (
    <Pressable onPress={onPress} onLongPress={onLongPress} style={{ width: size, margin: 4 }}>
      <View style={[styles.cardImage, { width: size, height: Math.round(size * 1.5) }]}>
        {posterUrl ? (
          <ExpoImage
            source={{ uri: posterUrl }}
            style={{ width: '100%', height: '100%' }}
            contentFit="cover"
            cachePolicy="memory-disk"
            transition={200}
          />
        ) : (
          <View style={styles.placeholderImage}>
            <Ionicons name="film-outline" size={32} color="#444" />
          </View>
        )}
        {/* Source badge */}
        {item.source !== 'plex' && (
          <View style={styles.sourceBadge}>
            <Text style={styles.sourceBadgeText}>
              {item.source === 'both' ? 'T+P' : 'T'}
            </Text>
          </View>
        )}
      </View>
      <Text numberOfLines={1} style={styles.cardTitle}>
        {item.title}
      </Text>
      {item.year ? <Text style={styles.cardYear}>{item.year}</Text> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a0a0a',
  },
  center: {
    flex: 1,
    backgroundColor: '#0a0a0a',
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    color: '#999',
    marginTop: 12,
  },
  errorText: {
    color: '#fff',
    marginBottom: 12,
  },
  retry: {
    backgroundColor: '#fff',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 8,
  },
  retryText: {
    color: '#000',
    fontWeight: '800',
  },
  filterPill: {
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#4a4a4a',
    backgroundColor: 'transparent',
    marginRight: 8,
    overflow: 'hidden',
  },
  filterPillActive: {
    backgroundColor: '#fff',
    borderColor: '#fff',
  },
  filterPillText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
  // Floating sort button (like Library)
  floatingSortButton: {
    position: 'absolute',
    bottom: Platform.OS === 'ios' ? 100 : 80,
    right: 16,
    borderRadius: 24,
    overflow: 'hidden',
  },
  floatingSortButtonBlur: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 8,
  },
  floatingSortButtonGlass: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 8,
    borderRadius: 24,
  },
  floatingSortButtonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
  // Modal styles (like Library)
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  sortModalContent: {
    width: '80%',
    maxWidth: 320,
    borderRadius: 16,
    overflow: 'hidden',
  },
  sortModalBlur: {
    padding: 20,
  },
  sortModalTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    marginBottom: 16,
    textAlign: 'center',
  },
  sortOption: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 14,
    paddingHorizontal: 12,
    borderRadius: 10,
    marginBottom: 4,
  },
  sortOptionActive: {
    backgroundColor: 'rgba(255,255,255,0.15)',
  },
  sortOptionText: {
    color: '#aaa',
    fontSize: 16,
  },
  sortOptionTextActive: {
    color: '#fff',
    fontWeight: '600',
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 40,
  },
  emptyTitle: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
    marginTop: 16,
    marginBottom: 8,
  },
  emptySubtitle: {
    color: '#888',
    fontSize: 14,
    textAlign: 'center',
    lineHeight: 20,
  },
  emptyText: {
    color: '#888',
    textAlign: 'center',
    marginTop: 40,
  },
  cardImage: {
    backgroundColor: '#111',
    borderRadius: 10,
    overflow: 'hidden',
  },
  placeholderImage: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#1a1a1a',
  },
  sourceBadge: {
    position: 'absolute',
    top: 6,
    right: 6,
    backgroundColor: 'rgba(0,0,0,0.7)',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  sourceBadgeText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: '700',
  },
  cardTitle: {
    color: '#fff',
    marginTop: 6,
    fontWeight: '700',
    fontSize: 13,
  },
  cardYear: {
    color: '#aaa',
    fontSize: 12,
  },
});
