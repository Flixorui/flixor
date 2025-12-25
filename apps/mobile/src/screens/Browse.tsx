import React, { useEffect, useState, useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  Pressable,
  ActivityIndicator,
  StyleSheet,
  useWindowDimensions,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Image as ExpoImage } from 'expo-image';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { LinearGradient } from 'expo-linear-gradient';
import * as Haptics from 'expo-haptics';
import type { BrowseContext, BrowseItem } from '@flixor/core';
import { fetchBrowseItems } from '../core/BrowseData';
import { TopBarStore } from '../components/TopBarStore';

const BLURHASH_PLACEHOLDER = 'L6PZfSi_.AyE_3t7t7R**0o#DgR4';

type BrowseParams = {
  context: BrowseContext;
  title: string;
  initialItems?: BrowseItem[];
};

type BrowseRouteProp = RouteProp<{ Browse: BrowseParams }, 'Browse'>;

export default function Browse() {
  const nav = useNavigation<any>();
  const route = useRoute<BrowseRouteProp>();
  const insets = useSafeAreaInsets();
  const { width: screenWidth } = useWindowDimensions();

  const { context, title, initialItems = [] } = route.params || {};

  const [items, setItems] = useState<BrowseItem[]>(initialItems);
  const [loading, setLoading] = useState(initialItems.length === 0);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [page, setPage] = useState(1);

  // Calculate grid item size (3 columns with gap)
  const horizontalPadding = 16;
  const gap = 12;
  const numColumns = 3;
  const itemWidth = (screenWidth - horizontalPadding * 2 - gap * (numColumns - 1)) / numColumns;
  const itemHeight = itemWidth * 1.5; // 2:3 aspect ratio

  // Hide top bar when this screen is focused
  useEffect(() => {
    TopBarStore.setVisible(false);
    TopBarStore.setTabBarVisible(false);
    return () => {
      TopBarStore.setVisible(true);
      TopBarStore.setTabBarVisible(true);
    };
  }, []);

  // Load initial data if none provided
  useEffect(() => {
    if (initialItems.length === 0 && context) {
      loadInitial();
    }
  }, []);

  const loadInitial = async () => {
    if (!context) return;
    setLoading(true);
    try {
      const result = await fetchBrowseItems(context, 1);
      setItems(result.items);
      setHasMore(result.hasMore);
      setPage(1);
    } catch (e) {
      console.log('[Browse] Error loading items:', e);
    } finally {
      setLoading(false);
    }
  };

  const loadMore = async () => {
    if (!context || loadingMore || !hasMore) return;
    setLoadingMore(true);
    try {
      const nextPage = page + 1;
      const result = await fetchBrowseItems(context, nextPage);
      setItems(prev => [...prev, ...result.items]);
      setHasMore(result.hasMore);
      setPage(nextPage);
    } catch (e) {
      console.log('[Browse] Error loading more:', e);
    } finally {
      setLoadingMore(false);
    }
  };

  const handleItemPress = useCallback((item: BrowseItem) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    if (!item?.id) return;
    if (item.id.startsWith('plex:')) {
      const rk = item.id.split(':')[1];
      nav.navigate('Details', { type: 'plex', ratingKey: rk });
    } else if (item.id.startsWith('tmdb:')) {
      const [, media, id] = item.id.split(':');
      nav.navigate('Details', { type: 'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
    }
  }, [nav]);

  const handleBack = () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    nav.goBack();
  };

  const renderItem = ({ item }: { item: BrowseItem }) => (
    <Pressable
      onPress={() => handleItemPress(item)}
      style={({ pressed }) => [styles.gridItem, { width: itemWidth, opacity: pressed ? 0.7 : 1 }]}
    >
      <View style={[styles.posterContainer, { width: itemWidth, height: itemHeight }]}>
        {item.image ? (
          <ExpoImage
            source={{ uri: item.image }}
            placeholder={{ blurhash: BLURHASH_PLACEHOLDER }}
            style={styles.poster}
            contentFit="cover"
            transition={200}
            cachePolicy="memory-disk"
          />
        ) : (
          <View style={styles.noImage}>
            <Ionicons name="image-outline" size={24} color="#555" />
          </View>
        )}
      </View>
      <Text style={styles.itemTitle} numberOfLines={2}>{item.title}</Text>
      {item.year && <Text style={styles.itemYear}>{item.year}</Text>}
    </Pressable>
  );

  const renderFooter = () => {
    if (!hasMore) return <View style={{ height: 40 }} />;

    return (
      <View style={styles.footer}>
        {loadingMore ? (
          <ActivityIndicator color="#fff" size="small" />
        ) : (
          <Pressable onPress={loadMore} style={styles.loadMoreButton}>
            <Text style={styles.loadMoreText}>Load More</Text>
          </Pressable>
        )}
      </View>
    );
  };

  return (
    <View style={styles.container}>
      <LinearGradient
        colors={['#0a0a0a', '#0f0f10', '#0b0c0d']}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />

      {/* Header */}
      <View style={[styles.header, { paddingTop: insets.top + 8 }]}>
        <Pressable onPress={handleBack} style={styles.backButton}>
          <Ionicons name="chevron-back" size={24} color="#fff" />
        </Pressable>
        <Text style={styles.headerTitle} numberOfLines={1}>{title}</Text>
        <View style={{ width: 44 }} />
      </View>

      {/* Content */}
      {loading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator color="#fff" size="large" />
        </View>
      ) : items.length === 0 ? (
        <View style={styles.emptyContainer}>
          <Ionicons name="film-outline" size={48} color="#444" />
          <Text style={styles.emptyText}>No items found</Text>
        </View>
      ) : (
        <FlatList
          data={items}
          renderItem={renderItem}
          keyExtractor={(item, idx) => `${item.id}-${idx}`}
          numColumns={numColumns}
          columnWrapperStyle={styles.row}
          contentContainerStyle={[styles.gridContent, { paddingBottom: insets.bottom + 20 }]}
          showsVerticalScrollIndicator={false}
          onEndReached={loadMore}
          onEndReachedThreshold={0.5}
          ListFooterComponent={renderFooter}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a0a0a',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 8,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.1)',
  },
  backButton: {
    width: 44,
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerTitle: {
    flex: 1,
    fontSize: 18,
    fontWeight: '700',
    color: '#fff',
    textAlign: 'center',
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  emptyText: {
    color: '#666',
    fontSize: 16,
  },
  gridContent: {
    padding: 16,
  },
  row: {
    gap: 12,
    marginBottom: 16,
  },
  gridItem: {
    // width set dynamically
  },
  posterContainer: {
    backgroundColor: '#1a1a1a',
    borderRadius: 8,
    overflow: 'hidden',
  },
  poster: {
    width: '100%',
    height: '100%',
  },
  noImage: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#1a1a1a',
  },
  itemTitle: {
    color: '#ddd',
    fontSize: 12,
    fontWeight: '500',
    marginTop: 6,
  },
  itemYear: {
    color: '#666',
    fontSize: 11,
    marginTop: 2,
  },
  footer: {
    paddingVertical: 20,
    alignItems: 'center',
  },
  loadMoreButton: {
    paddingHorizontal: 24,
    paddingVertical: 12,
    borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.1)',
  },
  loadMoreText: {
    color: '#fff',
    fontWeight: '600',
    fontSize: 14,
  },
});
