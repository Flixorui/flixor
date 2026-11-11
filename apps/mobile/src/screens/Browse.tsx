/**
 * Browse: the full list behind a row's "See All" (Home rows, Stremio catalogs, Trakt and
 * TMDB lists). Same look as the studio and collection pages: a big title with a round glass
 * back button over a Liquid Glass band that fades in on scroll, then the shared poster grid.
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Animated, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import FastImage from '@d11/react-native-fast-image';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useNavigation, useRoute, RouteProp, useFocusEffect } from '@react-navigation/native';
import * as Haptics from 'expo-haptics';
import type { BrowseItem } from '@flixor/core';
import { createStremioCatalogPager, fetchBrowseItems, type AnyBrowseContext } from '../core/BrowseData';
import { TopBarStore } from '../components/TopBarStore';
import SettingsHeader from '../components/settings/SettingsHeader';
import MediaGrid from '../components/collections/MediaGrid';

// Preload cap for pagination
const IMAGE_PRELOAD_CAP = 12;

type BrowseParams = {
  context: AnyBrowseContext;
  title: string;
  initialItems?: BrowseItem[];
};

type BrowseRouteProp = RouteProp<{ Browse: BrowseParams }, 'Browse'>;

type GridItem = { id: string; title: string; image?: string; year?: string | number; source: BrowseItem };

/** Keeps the first copy of each id: later pages can repeat a title, and the grid keys by id. */
function appendUnique(prev: BrowseItem[], next: BrowseItem[]): BrowseItem[] {
  const seen = new Set(prev.map((i) => i.id));
  return [...prev, ...next.filter((i) => i.id && !seen.has(i.id) && seen.add(i.id))];
}

export default function Browse() {
  const nav = useNavigation<any>();
  const route = useRoute<BrowseRouteProp>();
  const insets = useSafeAreaInsets();
  const isMounted = useRef(true);
  const scrollY = useRef(new Animated.Value(0)).current;

  const { context, title, initialItems = [] } = route.params || {};

  const [items, setItems] = useState<BrowseItem[]>(() => appendUnique([], initialItems));
  const [loading, setLoading] = useState(initialItems.length === 0);
  const [loadingMore, setLoadingMore] = useState(false);
  // Static context with initial items has no more pages to load
  const [hasMore, setHasMore] = useState(!(context?.type === 'static' && initialItems.length > 0));
  const [page, setPage] = useState(1);
  const [loadError, setLoadError] = useState(false);
  const [pagingError, setPagingError] = useState(false);

  const stremioPagerRef = useRef<ReturnType<typeof createStremioCatalogPager> | null>(null);
  const fetchPage = useCallback((page: number) => {
    if (context?.type !== 'stremioCatalog') return fetchBrowseItems(context, page);
    stremioPagerRef.current ??= createStremioCatalogPager(context.catalog);
    return stremioPagerRef.current(page);
  }, [context]);

  const preloadImages = useCallback((itemsToPreload: BrowseItem[]) => {
    const images = itemsToPreload
      .slice(0, IMAGE_PRELOAD_CAP)
      .filter((item) => item.image)
      .map((item) => ({ uri: item.image! }));
    if (images.length > 0) FastImage.preload(images);
  }, []);

  // The top bar stays hidden here, including when coming back from Details
  useFocusEffect(
    useCallback(() => {
      isMounted.current = true;
      TopBarStore.setVisible(false);
      TopBarStore.setTabBarVisible(false);
      if (initialItems.length > 0) preloadImages(initialItems);
      return () => {
        isMounted.current = false;
      };
    }, [initialItems, preloadImages])
  );

  const loadInitial = useCallback(async () => {
    if (!context) return;
    setLoading(true);
    setLoadError(false);
    try {
      const result = await fetchPage(1);
      if (!isMounted.current) return;
      setItems(appendUnique([], result.items));
      setHasMore(result.hasMore);
      setPage(1);
      preloadImages(result.items);
    } catch (e) {
      console.log('[Browse] Error loading items:', e);
      if (isMounted.current) {
        setHasMore(false);
        setLoadError(true);
      }
    } finally {
      if (isMounted.current) setLoading(false);
    }
  }, [context, fetchPage, preloadImages]);

  useEffect(() => {
    if (initialItems.length === 0 && context) loadInitial();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const loadMore = useCallback(async () => {
    if (!context || loading || loadingMore || !hasMore) return;
    setLoadingMore(true);
    setPagingError(false);
    try {
      const nextPage = page + 1;
      const result = await fetchPage(nextPage);
      if (!isMounted.current) return;
      setItems((prev) => appendUnique(prev, result.items));
      setHasMore(result.hasMore);
      setPage(nextPage);
      preloadImages(result.items);
    } catch (e) {
      console.log('[Browse] Error loading more:', e);
      if (isMounted.current) setPagingError(true);
    } finally {
      if (isMounted.current) setLoadingMore(false);
    }
  }, [context, fetchPage, hasMore, loading, loadingMore, page, preloadImages]);

  const handleItemPress = useCallback((grid: GridItem) => {
    const item = grid.source;
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    if (!item?.id) return;
    if (item.id.startsWith('plex:')) {
      nav.navigate('Details', { type: 'plex', ratingKey: item.id.split(':')[1] });
    } else if (item.id.startsWith('tmdb:')) {
      const [, media, id] = item.id.split(':');
      nav.navigate('Details', { type: 'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
    }
  }, [nav]);

  const gridItems: GridItem[] = items.map((item) => ({
    id: item.id,
    title: item.title,
    image: item.image,
    year: item.subtitle || item.year,
    source: item,
  }));

  const headerHeight = insets.top + 52;

  const empty = loading ? (
    <View style={styles.center}>
      <ActivityIndicator color="#fff" />
    </View>
  ) : (
    <View style={styles.center}>
      <Ionicons name={loadError ? 'cloud-offline-outline' : 'film-outline'} size={36} color="#48484a" />
      <Text style={styles.message}>{loadError ? "Couldn't load this list." : 'No titles here yet.'}</Text>
      {loadError ? (
        <Pressable onPress={loadInitial} style={styles.retry} accessibilityRole="button">
          <Text style={styles.retryText}>Try Again</Text>
        </Pressable>
      ) : null}
    </View>
  );

  return (
    <View style={styles.container}>
      <MediaGrid
        items={loading ? [] : gridItems}
        onPress={handleItemPress}
        empty={empty}
        onEndReached={loadMore}
        loadingMore={loadingMore}
        footer={
          pagingError ? (
            <Pressable onPress={loadMore} style={styles.pagingRetry} accessibilityRole="button">
              <Text style={styles.pagingRetryText}>Couldn't load more. Tap to retry.</Text>
            </Pressable>
          ) : null
        }
        paddingTop={headerHeight + 8}
        paddingBottom={insets.bottom + 40}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: false })}
      />
      <SettingsHeader scrollY={scrollY} title={title} onBack={() => nav.goBack()} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0e0e10' },
  center: { alignItems: 'center', justifyContent: 'center', paddingTop: 140, paddingHorizontal: 32, gap: 12 },
  message: { color: '#8e8e93', fontSize: 15, textAlign: 'center' },
  retry: { marginTop: 4, paddingHorizontal: 18, height: 40, borderRadius: 10, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' },
  retryText: { color: '#000', fontSize: 15, fontWeight: '700' },
  pagingRetry: { paddingVertical: 20, alignItems: 'center' },
  pagingRetryText: { color: '#8e8e93', fontSize: 14, fontWeight: '600' },
});
