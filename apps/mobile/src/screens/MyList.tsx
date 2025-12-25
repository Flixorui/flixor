import React, { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { View, Text, ActivityIndicator, Pressable, StyleSheet, Dimensions, Animated, Alert } from 'react-native';
import { Image as ExpoImage } from 'expo-image';
import { FlashList } from '@shopify/flash-list';
import { Ionicons } from '@expo/vector-icons';
import { TopBarStore, useTopBarStore } from '../components/TopBarStore';
import { LinearGradient } from 'expo-linear-gradient';
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
import { BlurView } from 'expo-blur';
import * as Haptics from 'expo-haptics';

interface MyListProps {
  onOpenSettings: () => void;
}

export default function MyList({ onOpenSettings }: MyListProps) {
  const nav: any = useNavigation();
  const isFocused = useIsFocused();
  const { isLoading: flixorLoading, isConnected } = useFlixor();

  const [items, setItems] = useState<MyListItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<FilterOption>('all');
  const [sort, setSort] = useState<SortOption>('added');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('desc');
  const [showSortPicker, setShowSortPicker] = useState(false);

  const y = useRef(new Animated.Value(0)).current;
  const showPillsAnim = useRef(new Animated.Value(1)).current;
  const barHeight = useTopBarStore((s) => s.height || 90);
  const lastScrollY = useRef(0);
  const scrollDirection = useRef<'up' | 'down'>('down');

  // Set scrollY and showPills immediately on mount
  React.useLayoutEffect(() => {
    if (isFocused) {
      TopBarStore.setScrollY(y);
      TopBarStore.setShowPills(showPillsAnim);
    }
  }, [isFocused, y]);

  // Push top bar updates
  useEffect(() => {
    if (!isFocused) return;

    TopBarStore.setVisible(true);
    TopBarStore.setShowFilters(false);
    TopBarStore.setUsername('My List');
    TopBarStore.setSelected('all');
    TopBarStore.setCompact(false);
    TopBarStore.setActiveGenre(undefined);
    TopBarStore.setCustomFilters(undefined);
    TopBarStore.setHandlers({
      onNavigateLibrary: undefined,
      onClose: undefined,
      onSearch: () => nav.navigate('HomeTab', { screen: 'Search' }),
      onBrowse: onOpenSettings, // Gear icon opens settings
    });
  }, [isFocused, nav, onOpenSettings]);

  // Load items
  const loadItems = useCallback(async (showRefresh = false) => {
    if (showRefresh) setRefreshing(true);
    else setLoading(true);
    setError(null);

    try {
      const result = await fetchMyList({ filter, sort, sortDirection });
      setItems(result);
    } catch (e: any) {
      setError(e?.message || 'Failed to load watchlist');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [filter, sort, sortDirection]);

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

  const toggleSort = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setShowSortPicker(!showSortPicker);
  }, [showSortPicker]);

  const selectSort = useCallback((newSort: SortOption) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    if (sort === newSort) {
      setSortDirection(prev => prev === 'asc' ? 'desc' : 'asc');
    } else {
      setSort(newSort);
      setSortDirection('desc');
    }
    setShowSortPicker(false);
  }, [sort]);

  const selectFilter = useCallback((newFilter: FilterOption) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setFilter(newFilter);
  }, []);

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

  const sortLabels: Record<SortOption, string> = {
    added: 'Date Added',
    title: 'Title',
    year: 'Year',
  };

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

      {/* Filter and Sort Header */}
      <View style={[styles.header, { paddingTop: barHeight + 8 }]}>
        {/* Filter Pills */}
        <View style={styles.filterRow}>
          <FilterPill
            label="All"
            active={filter === 'all'}
            onPress={() => selectFilter('all')}
          />
          <FilterPill
            label="Movies"
            active={filter === 'movies'}
            onPress={() => selectFilter('movies')}
          />
          <FilterPill
            label="TV Shows"
            active={filter === 'shows'}
            onPress={() => selectFilter('shows')}
          />
        </View>

        {/* Sort Button */}
        <Pressable onPress={toggleSort} style={styles.sortButton}>
          <Text style={styles.sortText}>{sortLabels[sort]}</Text>
          <Ionicons
            name={sortDirection === 'desc' ? 'chevron-down' : 'chevron-up'}
            size={16}
            color="#fff"
          />
        </Pressable>
      </View>

      {/* Sort Picker Modal */}
      {showSortPicker && (
        <View style={styles.sortPickerOverlay}>
          <Pressable style={StyleSheet.absoluteFillObject} onPress={() => setShowSortPicker(false)} />
          <View style={styles.sortPicker}>
            {(['added', 'title', 'year'] as SortOption[]).map((option) => (
              <Pressable
                key={option}
                onPress={() => selectSort(option)}
                style={[styles.sortOption, sort === option && styles.sortOptionActive]}
              >
                <Text style={[styles.sortOptionText, sort === option && styles.sortOptionTextActive]}>
                  {sortLabels[option]}
                </Text>
                {sort === option && (
                  <Ionicons
                    name={sortDirection === 'desc' ? 'arrow-down' : 'arrow-up'}
                    size={16}
                    color="#000"
                  />
                )}
              </Pressable>
            ))}
          </View>
        </View>
      )}

      {/* Items Grid */}
      {items.length === 0 ? (
        <View style={styles.emptyContainer}>
          <Ionicons name="bookmark-outline" size={64} color="#444" />
          <Text style={styles.emptyTitle}>Your list is empty</Text>
          <Text style={styles.emptySubtitle}>
            {isTraktConnected()
              ? 'Add movies and shows to your watchlist to see them here'
              : 'Connect Trakt in settings to sync your watchlist'}
          </Text>
          {!isTraktConnected() && (
            <Pressable onPress={onOpenSettings} style={styles.connectButton}>
              <Text style={styles.connectButtonText}>Connect Trakt</Text>
            </Pressable>
          )}
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
          contentContainerStyle={{ padding: 8, paddingTop: 8 }}
          onScroll={Animated.event([{ nativeEvent: { contentOffset: { y } } }], {
            useNativeDriver: false,
            listener: (e: any) => {
              const currentY = e.nativeEvent.contentOffset.y;
              const delta = currentY - lastScrollY.current;

              if (delta > 5 && scrollDirection.current !== 'down') {
                scrollDirection.current = 'down';
                Animated.spring(showPillsAnim, {
                  toValue: 0,
                  useNativeDriver: true,
                  tension: 60,
                  friction: 10,
                }).start();
              } else if (delta < -5 && scrollDirection.current !== 'up') {
                scrollDirection.current = 'up';
                Animated.spring(showPillsAnim, {
                  toValue: 1,
                  useNativeDriver: true,
                  tension: 60,
                  friction: 10,
                }).start();
              }

              lastScrollY.current = currentY;
            },
          })}
          ListEmptyComponent={
            <Text style={styles.emptyText}>No items</Text>
          }
        />
      )}

      {/* Settings Button in Header */}
      <Pressable
        onPress={onOpenSettings}
        style={[styles.settingsButton, { top: barHeight - 36 }]}
      >
        <Ionicons name="settings-outline" size={22} color="#fff" />
      </Pressable>
    </View>
  );
}

function FilterPill({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      style={[styles.filterPill, active && styles.filterPillActive]}
    >
      {active && (
        <>
          <BlurView intensity={20} tint="dark" style={StyleSheet.absoluteFillObject} />
          <View style={[StyleSheet.absoluteFillObject, { backgroundColor: 'rgba(255,255,255,0.15)' }]} />
        </>
      )}
      <Text style={styles.filterPillText}>{label}</Text>
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
          <ExpoImage source={{ uri: posterUrl }} style={{ width: '100%', height: '100%' }} contentFit="cover" />
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
  header: {
    paddingHorizontal: 12,
    paddingBottom: 8,
    gap: 12,
  },
  filterRow: {
    flexDirection: 'row',
    gap: 8,
  },
  filterPill: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#4a4a4a',
    overflow: 'hidden',
  },
  filterPillActive: {
    borderColor: 'rgba(255,255,255,0.3)',
  },
  filterPillText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
  sortButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    alignSelf: 'flex-start',
    paddingVertical: 4,
  },
  sortText: {
    color: '#aaa',
    fontSize: 13,
    fontWeight: '600',
  },
  sortPickerOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 100,
  },
  sortPicker: {
    position: 'absolute',
    top: 180,
    left: 12,
    backgroundColor: '#1a1a1a',
    borderRadius: 12,
    padding: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  sortOption: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 8,
    gap: 8,
  },
  sortOptionActive: {
    backgroundColor: '#fff',
  },
  sortOptionText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  sortOptionTextActive: {
    color: '#000',
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
  connectButton: {
    marginTop: 20,
    backgroundColor: '#fff',
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 8,
  },
  connectButtonText: {
    color: '#000',
    fontWeight: '700',
  },
  emptyText: {
    color: '#888',
    textAlign: 'center',
    marginTop: 40,
  },
  settingsButton: {
    position: 'absolute',
    right: 16,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.1)',
    alignItems: 'center',
    justifyContent: 'center',
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
