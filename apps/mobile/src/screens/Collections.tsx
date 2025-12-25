import React, { useEffect, useState, useRef } from 'react';
import {
  View,
  Text,
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Dimensions,
  Animated,
  Platform,
} from 'react-native';
import { Image as ExpoImage } from 'expo-image';
import { FlashList } from '@shopify/flash-list';
import { LinearGradient } from 'expo-linear-gradient';
import { useNavigation, useRoute } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import { useFlixor } from '../core/FlixorContext';
import {
  fetchCollections,
  fetchCollectionItems,
  getCollectionImageUrl,
  CollectionItem,
  CollectionMediaItem,
} from '../core/CollectionsData';

type ViewMode = 'collections' | 'items';

export default function Collections() {
  const nav: any = useNavigation();
  const route = useRoute();
  const { isLoading: flixorLoading, isConnected } = useFlixor();

  const [viewMode, setViewMode] = useState<ViewMode>('collections');
  const [collections, setCollections] = useState<CollectionItem[]>([]);
  const [collectionItems, setCollectionItems] = useState<CollectionMediaItem[]>([]);
  const [selectedCollection, setSelectedCollection] = useState<CollectionItem | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const loadingMoreRef = useRef(false);
  const scrollY = useRef(new Animated.Value(0)).current;

  // Get initial filter from route params
  const initialType = (route.params as any)?.type as 'movie' | 'show' | undefined;

  // Load collections
  useEffect(() => {
    if (flixorLoading || !isConnected) return;

    (async () => {
      setLoading(true);
      setError(null);
      try {
        const result = await fetchCollections(initialType);
        console.log('[Collections] Loaded', result.length, 'collections');
        setCollections(result);
      } catch (e: any) {
        setError(e?.message || 'Failed to load collections');
      } finally {
        setLoading(false);
      }
    })();
  }, [flixorLoading, isConnected, initialType]);

  // Load collection items when a collection is selected
  const loadCollectionItems = async (collection: CollectionItem) => {
    setSelectedCollection(collection);
    setViewMode('items');
    setLoading(true);
    setError(null);
    setPage(1);

    try {
      const result = await fetchCollectionItems(collection.ratingKey, {
        offset: 0,
        limit: 40,
      });
      console.log('[Collections] Loaded', result.items.length, 'items from collection');
      setCollectionItems(result.items);
      setHasMore(result.hasMore);
    } catch (e: any) {
      setError(e?.message || 'Failed to load collection items');
    } finally {
      setLoading(false);
    }
  };

  // Load more collection items
  const loadMoreItems = async () => {
    if (!hasMore || loadingMoreRef.current || !selectedCollection) return;
    loadingMoreRef.current = true;

    try {
      const nextPage = page + 1;
      const offset = (nextPage - 1) * 40;
      const result = await fetchCollectionItems(selectedCollection.ratingKey, {
        offset,
        limit: 40,
      });

      setCollectionItems((prev) => [...prev, ...result.items]);
      setPage(nextPage);
      setHasMore(result.hasMore);
    } catch (e) {
      console.log('[Collections] loadMoreItems error:', e);
    }

    loadingMoreRef.current = false;
  };

  const goBack = () => {
    if (viewMode === 'items') {
      setViewMode('collections');
      setSelectedCollection(null);
      setCollectionItems([]);
    } else if (nav.canGoBack()) {
      nav.goBack();
    }
  };

  // Show loading
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

  if (loading && viewMode === 'collections') {
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
        <Pressable onPress={goBack} style={styles.retry}>
          <Text style={{ color: '#000', fontWeight: '800' }}>Go Back</Text>
        </Pressable>
      </View>
    );
  }

  const numColumns = Dimensions.get('window').width >= 800 ? 4 : 2;
  const itemSize = Math.floor(
    (Dimensions.get('window').width - 24 - (numColumns - 1) * 12) / numColumns
  );

  const headerOpacity = scrollY.interpolate({
    inputRange: [0, 60],
    outputRange: [0, 1],
    extrapolate: 'clamp',
  });

  return (
    <View style={{ flex: 1, backgroundColor: '#0a0a0a' }}>
      {/* Background gradients */}
      <LinearGradient
        colors={['#0a0a0a', '#0f0f10', '#0b0c0d']}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />
      <LinearGradient
        colors={['rgba(122,22,18,0.18)', 'rgba(122,22,18,0.06)', 'transparent']}
        start={{ x: 0.0, y: 1.0 }}
        end={{ x: 0.45, y: 0.35 }}
        style={StyleSheet.absoluteFillObject}
      />

      {/* Header */}
      <Animated.View style={[styles.headerBlurContainer, { opacity: headerOpacity }]}>
        <BlurView intensity={80} tint="dark" style={styles.headerBlur} />
      </Animated.View>
      <View style={styles.header}>
        <Pressable onPress={goBack} style={styles.backButton}>
          <Ionicons name="chevron-back" size={28} color="#fff" />
        </Pressable>
        <Text style={styles.headerTitle}>
          {viewMode === 'items' && selectedCollection
            ? selectedCollection.title
            : 'Collections'}
        </Text>
        <View style={{ width: 40 }} />
      </View>

      {viewMode === 'collections' ? (
        // Collections grid
        <FlashList
          data={collections}
          keyExtractor={(item) => item.ratingKey}
          renderItem={({ item }) => (
            <CollectionCard
              item={item}
              size={itemSize}
              onPress={() => loadCollectionItems(item)}
            />
          )}
          estimatedItemSize={itemSize + 60}
          numColumns={numColumns}
          contentContainerStyle={{ padding: 12, paddingTop: 100 }}
          onScroll={Animated.event(
            [{ nativeEvent: { contentOffset: { y: scrollY } } }],
            { useNativeDriver: false }
          )}
          ListEmptyComponent={
            <View style={styles.emptyContainer}>
              <Ionicons name="albums-outline" size={48} color="#444" />
              <Text style={styles.emptyText}>No collections found</Text>
              <Text style={styles.emptySubtext}>
                Create collections in Plex to organize your media
              </Text>
            </View>
          }
        />
      ) : (
        // Collection items grid
        <>
          {loading ? (
            <View style={[styles.center, { paddingTop: 100 }]}>
              <ActivityIndicator color="#fff" />
            </View>
          ) : (
            <FlashList
              data={collectionItems}
              keyExtractor={(item) => item.ratingKey}
              renderItem={({ item }) => (
                <MediaCard
                  item={item}
                  size={Math.floor((Dimensions.get('window').width - 24 - 2 * 8) / 3)}
                  onPress={() =>
                    nav.navigate('Details', { type: 'plex', ratingKey: item.ratingKey })
                  }
                />
              )}
              estimatedItemSize={200}
              numColumns={3}
              contentContainerStyle={{ padding: 8, paddingTop: 100 }}
              onEndReached={loadMoreItems}
              onEndReachedThreshold={0.5}
              ListEmptyComponent={
                <Text style={{ color: '#888', textAlign: 'center', marginTop: 40 }}>
                  No items in this collection
                </Text>
              }
            />
          )}
        </>
      )}
    </View>
  );
}

// Collection card component
function CollectionCard({
  item,
  size,
  onPress,
}: {
  item: CollectionItem;
  size: number;
  onPress?: () => void;
}) {
  const img = getCollectionImageUrl(item.thumb || item.art, size * 2);
  const aspectRatio = 16 / 9;

  return (
    <Pressable onPress={onPress} style={{ width: size, margin: 6 }}>
      <View
        style={{
          width: size,
          height: Math.round(size / aspectRatio),
          backgroundColor: '#1a1a1a',
          borderRadius: 12,
          overflow: 'hidden',
        }}
      >
        {img ? (
          <ExpoImage
            source={{ uri: img }}
            style={{ width: '100%', height: '100%' }}
            contentFit="cover"
          />
        ) : (
          <View style={styles.placeholderContainer}>
            <Ionicons name="albums" size={32} color="#444" />
          </View>
        )}
        <LinearGradient
          colors={['transparent', 'rgba(0,0,0,0.9)']}
          style={styles.cardGradient}
        />
        <View style={styles.cardOverlay}>
          <Text numberOfLines={2} style={styles.collectionTitle}>
            {item.title}
          </Text>
          {item.childCount !== undefined && (
            <Text style={styles.itemCount}>{item.childCount} items</Text>
          )}
        </View>
      </View>
    </Pressable>
  );
}

// Media card component for collection items
function MediaCard({
  item,
  size,
  onPress,
}: {
  item: CollectionMediaItem;
  size: number;
  onPress?: () => void;
}) {
  const img = getCollectionImageUrl(item.thumb, size * 2);

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
          <ExpoImage
            source={{ uri: img }}
            style={{ width: '100%', height: '100%' }}
            contentFit="cover"
          />
        ) : null}
      </View>
      <Text numberOfLines={1} style={{ color: '#fff', marginTop: 6, fontWeight: '700' }}>
        {item.title}
      </Text>
      {item.year ? (
        <Text style={{ color: '#aaa', fontSize: 12 }}>{item.year}</Text>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    backgroundColor: '#0a0a0a',
    alignItems: 'center',
    justifyContent: 'center',
  },
  retry: {
    backgroundColor: '#fff',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 8,
  },
  header: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: Platform.OS === 'ios' ? 56 : 20,
    paddingHorizontal: 12,
    paddingBottom: 12,
    zIndex: 10,
  },
  headerBlurContainer: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: Platform.OS === 'ios' ? 100 : 64,
    zIndex: 9,
  },
  headerBlur: {
    flex: 1,
  },
  headerTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    flex: 1,
    textAlign: 'center',
  },
  backButton: {
    width: 40,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingTop: 80,
    paddingHorizontal: 24,
  },
  emptyText: {
    color: '#888',
    fontSize: 18,
    fontWeight: '600',
    marginTop: 16,
  },
  emptySubtext: {
    color: '#666',
    fontSize: 14,
    textAlign: 'center',
    marginTop: 8,
  },
  placeholderContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#1a1a1a',
  },
  cardGradient: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: '60%',
  },
  cardOverlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 10,
  },
  collectionTitle: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  itemCount: {
    color: '#aaa',
    fontSize: 12,
    marginTop: 2,
  },
});
