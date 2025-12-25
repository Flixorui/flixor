import React, { useEffect, useMemo, useRef, useState } from 'react';
import { View, Text, ActivityIndicator, Pressable, StyleSheet, Dimensions, Animated, Modal, Platform } from 'react-native';
import { Image as ExpoImage } from 'expo-image';
import { FlashList } from '@shopify/flash-list';
import { TopBarStore, useTopBarStore } from '../components/TopBarStore';
import { LinearGradient } from 'expo-linear-gradient';
import { useRoute, useNavigation } from '@react-navigation/native';
import { useFlixor } from '../core/FlixorContext';
import {
  fetchLibrarySections,
  fetchLibraryItems,
  getLibraryImageUrl,
  getLibraryUsername,
  LibraryItem,
  LibrarySections,
  LIBRARY_SORT_OPTIONS,
} from '../core/LibraryData';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';

export default function Library() {
  const route = useRoute();
  const nav: any = useNavigation();
  const { isLoading: flixorLoading, isConnected } = useFlixor();

  const [items, setItems] = useState<LibraryItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<'all' | 'movies' | 'shows'>('all');
  const [username, setUsername] = useState<string>('You');
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const loadingMoreRef = useRef(false);
  const [sectionKeys, setSectionKeys] = useState<LibrarySections>({});
  const [genreKey, setGenreKey] = useState<string | undefined>(undefined);
  const [genreName, setGenreName] = useState<string | undefined>(undefined);
  const [sortOption, setSortOption] = useState(LIBRARY_SORT_OPTIONS[0]);
  const [showSortModal, setShowSortModal] = useState(false);
  const y = useRef(new Animated.Value(0)).current;
  const showPillsAnim = useRef(new Animated.Value(1)).current;
  const barHeight = useTopBarStore((s) => s.height || 90);
  const lastScrollY = useRef(0);
  const scrollDirection = useRef<'up' | 'down'>('down');

  const mType = useMemo(
    () => (selected === 'movies' ? 'movie' : selected === 'shows' ? 'show' : 'all'),
    [selected]
  );

  // Read route params to set initial selection and genre filter
  useEffect(() => {
    const params = route.params as any;
    if (params?.tab === 'movies') {
      setSelected('movies');
    } else if (params?.tab === 'tv') {
      setSelected('shows');
    }
    // Set genre filter if provided
    if (params?.genreKey) {
      setGenreKey(params.genreKey);
      setGenreName(params.genre || 'Genre');
    } else {
      setGenreKey(undefined);
      setGenreName(undefined);
    }
    console.log('[Library] route params:', params);
  }, [route.params]);

  // Set scrollY and showPills immediately on mount
  React.useLayoutEffect(() => {
    console.log('[Library] Setting scrollY and showPills for Library screen');
    TopBarStore.setScrollY(y);
    TopBarStore.setShowPills(showPillsAnim);
  }, [y]);

  // Clear genre filter handler (stable ref for TopBar)
  const clearGenreFilter = React.useCallback(() => {
    setGenreKey(undefined);
    setGenreName(undefined);
  }, []);

  // Push top bar updates via effects (avoid setState in render)
  useEffect(() => {
    TopBarStore.setVisible(true);
    TopBarStore.setShowFilters(true);
    TopBarStore.setUsername(username);
    TopBarStore.setSelected(selected);
    TopBarStore.setCompact(false); // Library uses full-size bar
    // Set active genre for Pills component
    TopBarStore.setActiveGenre(genreName);
    TopBarStore.setCustomFilters(undefined);
    TopBarStore.setHandlers({
      onNavigateLibrary: undefined,
      onClose: () => {
        console.log('[Library] Close button clicked, navigating back');
        if (nav.canGoBack()) {
          nav.goBack();
        }
      },
      onSearch: () => {
        console.log('[Library] Opening search');
        nav.navigate('Search');
      },
      onBrowse: () => {
        console.log('[Library] Opening Collections');
        nav.navigate('Collections');
      },
      onClearGenre: clearGenreFilter,
    });
  }, [username, selected, nav, genreName, clearGenreFilter]);

  // Clean up activeGenre when leaving Library
  useEffect(() => {
    return () => {
      TopBarStore.setActiveGenre(undefined);
      TopBarStore.setHandlers({ onClearGenre: undefined });
    };
  }, []);

  // Initial load: get username and library sections
  useEffect(() => {
    if (flixorLoading || !isConnected) return;

    (async () => {
      try {
        const name = await getLibraryUsername();
        setUsername(name);

        const sections = await fetchLibrarySections();
        setSectionKeys(sections);
        console.log('[Library] sections resolved', sections);
      } catch (e) {
        console.log('[Library] Error loading sections:', e);
      }
    })();
  }, [flixorLoading, isConnected]);

  // Load items when section keys, type, genre, or sort changes
  useEffect(() => {
    if (flixorLoading || !isConnected) return;
    if (!sectionKeys.show && !sectionKeys.movie) return;

    setLoading(true);
    setError(null);
    setPage(1);

    (async () => {
      try {
        // Resolve a concrete section key based on pill, or fall back to first available section
        const useSection =
          mType === 'show'
            ? sectionKeys.show
            : mType === 'movie'
              ? sectionKeys.movie
              : sectionKeys.show || sectionKeys.movie;

        console.log('[Library] load items', { selected, mType, useSection, genreKey, sort: sortOption.value });

        if (useSection) {
          const result = await fetchLibraryItems(useSection, {
            type: mType === 'all' ? 'all' : mType,
            offset: 0,
            limit: 40,
            genreKey,
            sort: sortOption.value,
          });

          console.log('[Library] mapped first page', result.items.length);
          setItems(result.items);
          setHasMore(result.hasMore);
        } else {
          console.log('[Library] no section found; showing empty');
          setItems([]);
          setHasMore(false);
        }
      } catch (e: any) {
        setError(e?.message || 'Failed to load library');
      } finally {
        setLoading(false);
      }
    })();
  }, [flixorLoading, isConnected, mType, sectionKeys, genreKey, sortOption]);

  const loadMore = async () => {
    if (!hasMore || loadingMoreRef.current) return;
    loadingMoreRef.current = true;

    try {
      const nextPage = page + 1;
      const useSection =
        mType === 'show'
          ? sectionKeys.show
          : mType === 'movie'
            ? sectionKeys.movie
            : sectionKeys.show || sectionKeys.movie;

      if (useSection) {
        const offset = (nextPage - 1) * 40;
        const result = await fetchLibraryItems(useSection, {
          type: mType === 'all' ? 'all' : mType,
          offset,
          limit: 40,
          genreKey,
          sort: sortOption.value,
        });

        console.log('[Library] loadMore page', nextPage, 'count', result.items.length);
        setItems((prev) => [...prev, ...result.items]);
        setPage(nextPage);
        setHasMore(result.hasMore);
      }
    } catch (e) {
      console.log('[Library] loadMore error:', e);
    }

    loadingMoreRef.current = false;
  };

  // Show loading while FlixorCore is initializing
  if (flixorLoading || !isConnected) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#fff" />
        <Text style={{ color: '#999', marginTop: 12 }}>
          {flixorLoading ? 'Initializing...' : 'Connecting...'}
        </Text>
      </View>
    );
  }

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.center}>
        <Text style={{ color: '#fff', marginBottom: 12 }}>{error}</Text>
        <Pressable onPress={() => setSelected((s) => s)} style={styles.retry}>
          <Text style={{ color: '#000', fontWeight: '800' }}>Retry</Text>
        </Pressable>
      </View>
    );
  }

  const numColumns = Dimensions.get('window').width >= 800 ? 5 : 3;
  const itemSize = Math.floor((Dimensions.get('window').width - 16 - (numColumns - 1) * 8) / numColumns);

  return (
    <View style={{ flex: 1, backgroundColor: '#0a0a0a' }}>
      {/* Themed background layers similar to Home */}
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
      <LinearGradient
        colors={['rgba(20,76,84,0.22)', 'rgba(20,76,84,0.10)', 'rgba(20,76,84,0.0)']}
        start={{ x: 1.0, y: 0.0 }}
        end={{ x: 0.55, y: 0.45 }}
        style={StyleSheet.absoluteFillObject}
      />

      <FlashList
        data={items}
        keyExtractor={(it) => String(it.ratingKey)}
        renderItem={({ item }) => (
          <Card
            item={item}
            size={itemSize}
            onPress={() => nav.navigate('Details', { type: 'plex', ratingKey: item.ratingKey })}
          />
        )}
        estimatedItemSize={itemSize + 28}
        numColumns={numColumns}
        contentContainerStyle={{ padding: 8, paddingTop: barHeight }}
        onEndReached={loadMore}
        onEndReachedThreshold={0.5}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y } } }], {
          useNativeDriver: false,
          listener: (e: any) => {
            const currentY = e.nativeEvent.contentOffset.y;
            const delta = currentY - lastScrollY.current;

            // Determine scroll direction
            if (delta > 5) {
              // Scrolling down - hide pills
              if (scrollDirection.current !== 'down') {
                scrollDirection.current = 'down';
                Animated.spring(showPillsAnim, {
                  toValue: 0,
                  useNativeDriver: true,
                  tension: 60,
                  friction: 10,
                }).start();
              }
            } else if (delta < -5) {
              // Scrolling up - show pills
              if (scrollDirection.current !== 'up') {
                scrollDirection.current = 'up';
                Animated.spring(showPillsAnim, {
                  toValue: 1,
                  useNativeDriver: true,
                  tension: 60,
                  friction: 10,
                }).start();
              }
            }

            lastScrollY.current = currentY;
          },
        })}
        ListEmptyComponent={
          <Text style={{ color: '#888', textAlign: 'center', marginTop: 40 }}>No items</Text>
        }
      />

      {/* Floating Sort Button */}
      <Pressable
        onPress={() => setShowSortModal(true)}
        style={styles.sortButton}
      >
        <BlurView intensity={80} tint="dark" style={styles.sortButtonBlur}>
          <Ionicons name="swap-vertical" size={20} color="#fff" />
          <Text style={styles.sortButtonText}>{sortOption.label}</Text>
        </BlurView>
      </Pressable>

      {/* Sort Modal */}
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
              {LIBRARY_SORT_OPTIONS.map((option) => (
                <Pressable
                  key={option.value}
                  onPress={() => {
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
    </View>
  );
}

function Card({
  item,
  size,
  onPress,
}: {
  item: LibraryItem;
  size: number;
  onPress?: () => void;
}) {
  const img = getLibraryImageUrl(item.thumb, size * 2);

  return (
    <Pressable onPress={onPress} style={{ width: size, margin: 4 }}>
      <View
        style={{
          width: size,
          height: Math.round(size * 1.5),
          backgroundColor: '#111',
          borderRadius: 10,
          overflow: 'hidden',
        }}
      >
        {img ? (
          <ExpoImage source={{ uri: img }} style={{ width: '100%', height: '100%' }} contentFit="cover" />
        ) : null}
      </View>
      <Text numberOfLines={1} style={{ color: '#fff', marginTop: 6, fontWeight: '700' }}>
        {item.title}
      </Text>
      {item.year ? <Text style={{ color: '#aaa', fontSize: 12 }}>{item.year}</Text> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' },
  retry: { backgroundColor: '#fff', paddingHorizontal: 16, paddingVertical: 10, borderRadius: 8 },
  sortButton: {
    position: 'absolute',
    bottom: Platform.OS === 'ios' ? 100 : 80,
    right: 16,
    borderRadius: 24,
    overflow: 'hidden',
  },
  sortButtonBlur: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
    gap: 8,
  },
  sortButtonText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
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
});
