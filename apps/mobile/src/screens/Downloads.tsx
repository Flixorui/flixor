/**
 * Downloads Screen - Shows downloaded movies and TV shows
 *
 * Features:
 * - Tab selector for Movies / TV Shows
 * - List of downloaded items with poster, title, and status
 * - Play downloaded content offline
 * - Delete downloads
 */

import React, { useEffect, useCallback, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Pressable,
  ActivityIndicator,
  Platform,
  RefreshControl,
  ScrollView,
  Alert,
  Image,
} from 'react-native';
import { FlashList, ListRenderItemInfo } from '@shopify/flash-list';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect, useNavigation } from '@react-navigation/native';
import * as Haptics from 'expo-haptics';
import { DownloadListItem } from '../components/downloads';
import {
  useDownloads,
  downloadStore,
  downloadService,
} from '../services/downloads';
import { DownloadedMetadata, DownloadedShow, DownloadStatus } from '../types/downloads';

// Conditionally import GlassView for iOS 26+ liquid glass effect
let GlassViewComp: any = null;
let liquidGlassAvailable = false;
if (Platform.OS === 'ios') {
  try {
    const glass = require('expo-glass-effect');
    GlassViewComp = glass.GlassView;
    liquidGlassAvailable =
      typeof glass.isLiquidGlassAvailable === 'function'
        ? glass.isLiquidGlassAvailable()
        : false;
  } catch {
    liquidGlassAvailable = false;
  }
}

type Tab = 'movies' | 'shows';

export default function Downloads() {
  const insets = useSafeAreaInsets();
  const nav: any = useNavigation();
  const { isLoading, downloadedMovies, downloadedShows, error, refresh } = useDownloads();
  const [activeTab, setActiveTab] = useState<Tab>('movies');
  const [refreshing, setRefreshing] = useState(false);
  const [expandedShow, setExpandedShow] = useState<string | null>(null);

  // Initialize downloads on mount
  useEffect(() => {
    downloadService.initialize();
    downloadStore.loadDownloads();
  }, []);

  // Refresh on focus
  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh])
  );

  // Pull-to-refresh handler
  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    await refresh();
    setRefreshing(false);
  }, [refresh]);

  // Handle tab change
  const handleTabChange = useCallback((tab: Tab) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setActiveTab(tab);
  }, []);

  // Render movie item - gets media from store directly
  const renderMovieItem = useCallback(
    ({ item }: { item: DownloadedMetadata }) => {
      const globalKey = `${item.serverId}:${item.ratingKey}`;
      const mediaItem = downloadStore.getState().media.get(globalKey);
      if (!mediaItem) return null;

      return (
        <DownloadListItem
          globalKey={globalKey}
          metadata={item}
          media={mediaItem}
        />
      );
    },
    []
  );

  // Handle delete episode
  const handleDeleteEpisode = useCallback((globalKey: string, title: string) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    Alert.alert(
      'Delete Episode',
      `Are you sure you want to delete "${title}"?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => downloadService.deleteDownload(globalKey),
        },
      ]
    );
  }, []);

  // Handle delete all episodes of a show
  const handleDeleteShow = useCallback((show: DownloadedShow) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    Alert.alert(
      'Delete Show',
      `Are you sure you want to delete all ${show.downloadedEpisodes} episode${show.downloadedEpisodes !== 1 ? 's' : ''} of "${show.title}"?`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete All',
          style: 'destructive',
          onPress: async () => {
            for (const ep of show.episodes) {
              const epGlobalKey = `${show.serverId}:${ep.ratingKey}`;
              await downloadService.deleteDownload(epGlobalKey);
            }
          },
        },
      ]
    );
  }, []);

  // Render show item (expandable with episodes)
  const renderShowItem = useCallback(
    ({ item }: { item: DownloadedShow }) => {
      if (item.episodes.length === 0) return null;

      const showKey = `${item.serverId}:${item.grandparentRatingKey}`;
      const isExpanded = expandedShow === showKey;

      return (
        <View>
          <Pressable
            style={styles.showItem}
            onPress={() => {
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
              setExpandedShow(isExpanded ? null : showKey);
            }}
          >
            <View style={styles.showPoster}>
              {item.localThumbPath ? (
                <Image
                  source={{ uri: item.localThumbPath.startsWith('file://') ? item.localThumbPath : `file://${item.localThumbPath}` }}
                  style={styles.showPosterImage}
                  resizeMode="cover"
                />
              ) : (
                <View style={[styles.showPosterImage, styles.posterPlaceholder]}>
                  <Ionicons name="tv-outline" size={24} color="#555" />
                </View>
              )}
            </View>
            <View style={styles.showInfo}>
              <Text style={styles.showTitle} numberOfLines={1}>
                {item.title}
              </Text>
              <Text style={styles.showSubtitle}>
                {item.downloadedEpisodes} episode{item.downloadedEpisodes !== 1 ? 's' : ''} downloaded
              </Text>
            </View>
            <Pressable
              onPress={() => handleDeleteShow(item)}
              style={styles.showDeleteButton}
              hitSlop={8}
            >
              <Ionicons name="trash-outline" size={20} color="#f44336" />
            </Pressable>
            <Ionicons
              name={isExpanded ? 'chevron-down' : 'chevron-forward'}
              size={20}
              color="#666"
              style={styles.showChevron}
            />
          </Pressable>

          {/* Episode list when expanded */}
          {isExpanded && (
            <View style={styles.episodeList}>
              {item.episodes.map((ep) => {
                const epGlobalKey = `${item.serverId}:${ep.ratingKey}`;
                // Get media from store directly instead of subscribed Map
                const epMedia = downloadStore.getState().media.get(epGlobalKey);
                const isCompleted = epMedia?.status === DownloadStatus.COMPLETED;

                return (
                  <View key={epGlobalKey} style={styles.episodeItem}>
                    <Pressable
                      style={styles.episodeContent}
                      onPress={() => {
                        if (isCompleted && epMedia?.videoFilePath) {
                          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                          nav.navigate('Player', {
                            type: 'offline',
                            offlineFilePath: epMedia.videoFilePath,
                            offlineGlobalKey: epGlobalKey,
                          });
                        }
                      }}
                    >
                      <View style={styles.episodeInfo}>
                        <Text style={styles.episodeTitle} numberOfLines={1}>
                          S{ep.parentIndex || 1}E{ep.index || 1} - {ep.title}
                        </Text>
                        <Text style={styles.episodeStatus}>
                          {isCompleted ? 'Downloaded' : epMedia?.status || 'Unknown'}
                        </Text>
                      </View>
                      {isCompleted && (
                        <Ionicons name="play-circle" size={28} color="#e50914" />
                      )}
                    </Pressable>
                    <Pressable
                      onPress={() => handleDeleteEpisode(epGlobalKey, ep.title)}
                      style={styles.episodeDeleteButton}
                      hitSlop={8}
                    >
                      <Ionicons name="trash-outline" size={18} color="#f44336" />
                    </Pressable>
                  </View>
                );
              })}
            </View>
          )}
        </View>
      );
    },
    [nav, expandedShow, handleDeleteEpisode, handleDeleteShow]
  );

  // Get key extractor
  const movieKeyExtractor = useCallback(
    (item: DownloadedMetadata) => `${item.serverId}:${item.ratingKey}`,
    []
  );

  const showKeyExtractor = useCallback(
    (item: DownloadedShow) => `${item.serverId}:${item.grandparentRatingKey}`,
    []
  );

  // Empty state
  const renderEmptyState = () => (
    <View style={styles.emptyContainer}>
      <Ionicons
        name={activeTab === 'movies' ? 'film-outline' : 'tv-outline'}
        size={64}
        color="#444"
      />
      <Text style={styles.emptyTitle}>
        No {activeTab === 'movies' ? 'Movies' : 'TV Shows'} Downloaded
      </Text>
      <Text style={styles.emptySubtitle}>
        Download movies and shows to watch offline
      </Text>
    </View>
  );

  // Header component
  const renderHeader = () => (
    <View style={[styles.header, { paddingTop: insets.top + 10 }]}>
      <Text style={styles.headerTitle}>Downloads</Text>

      {/* Tab selector */}
      <View style={styles.tabContainer}>
        <Pressable
          style={[
            styles.tab,
            activeTab === 'movies' && styles.tabActive,
          ]}
          onPress={() => handleTabChange('movies')}
        >
          <Text
            style={[
              styles.tabText,
              activeTab === 'movies' && styles.tabTextActive,
            ]}
          >
            Movies
          </Text>
        </Pressable>
        <Pressable
          style={[
            styles.tab,
            activeTab === 'shows' && styles.tabActive,
          ]}
          onPress={() => handleTabChange('shows')}
        >
          <Text
            style={[
              styles.tabText,
              activeTab === 'shows' && styles.tabTextActive,
            ]}
          >
            TV Shows
          </Text>
        </Pressable>
      </View>
    </View>
  );

  // Loading state
  if (isLoading && downloadedMovies.length === 0 && downloadedShows.length === 0) {
    return (
      <View style={[styles.container, styles.centered]}>
        {renderHeader()}
        <ActivityIndicator size="large" color="#e50914" />
      </View>
    );
  }

  // Error state
  if (error && downloadedMovies.length === 0 && downloadedShows.length === 0) {
    return (
      <View style={[styles.container, styles.centered]}>
        {renderHeader()}
        <Text style={styles.errorText}>{error}</Text>
        <Pressable style={styles.retryButton} onPress={refresh}>
          <Text style={styles.retryText}>Retry</Text>
        </Pressable>
      </View>
    );
  }

  const currentData = activeTab === 'movies' ? downloadedMovies : downloadedShows;
  const isEmpty = currentData.length === 0;

  return (
    <View style={styles.container}>
      {renderHeader()}

      {isEmpty ? (
        <ScrollView
          contentContainerStyle={styles.emptyScrollContent}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor="#e50914"
            />
          }
        >
          {renderEmptyState()}
        </ScrollView>
      ) : activeTab === 'movies' ? (
        <FlashList
          data={downloadedMovies}
          renderItem={renderMovieItem}
          keyExtractor={movieKeyExtractor}
          estimatedItemSize={114}
          contentContainerStyle={{
            paddingBottom: insets.bottom + 80,
          }}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor="#e50914"
            />
          }
        />
      ) : (
        <FlashList
          data={downloadedShows}
          renderItem={renderShowItem}
          keyExtractor={showKeyExtractor}
          estimatedItemSize={80}
          contentContainerStyle={{
            paddingBottom: insets.bottom + 80,
          }}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor="#e50914"
            />
          }
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
  centered: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyScrollContent: {
    flexGrow: 1,
  },
  header: {
    paddingHorizontal: 16,
    paddingBottom: 12,
    backgroundColor: '#0a0a0a',
  },
  headerTitle: {
    color: '#fff',
    fontSize: 28,
    fontWeight: 'bold',
    marginBottom: 16,
  },
  tabContainer: {
    flexDirection: 'row',
    backgroundColor: '#1a1a1a',
    borderRadius: 10,
    padding: 4,
  },
  tab: {
    flex: 1,
    paddingVertical: 10,
    alignItems: 'center',
    borderRadius: 8,
  },
  tabActive: {
    backgroundColor: '#333',
  },
  tabText: {
    color: '#888',
    fontSize: 14,
    fontWeight: '600',
  },
  tabTextActive: {
    color: '#fff',
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingTop: 100,
  },
  emptyTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
    marginTop: 16,
  },
  emptySubtitle: {
    color: '#666',
    fontSize: 14,
    marginTop: 8,
    textAlign: 'center',
    paddingHorizontal: 40,
  },
  errorText: {
    color: '#f44336',
    fontSize: 14,
    textAlign: 'center',
    marginBottom: 16,
  },
  retryButton: {
    backgroundColor: '#e50914',
    paddingHorizontal: 24,
    paddingVertical: 10,
    borderRadius: 6,
  },
  retryText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  showItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#111',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#333',
  },
  showPoster: {
    width: 50,
    height: 50,
    borderRadius: 8,
    backgroundColor: '#222',
    overflow: 'hidden',
  },
  showPosterImage: {
    width: '100%',
    height: '100%',
  },
  posterPlaceholder: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  showInfo: {
    flex: 1,
    marginLeft: 12,
  },
  showTitle: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
  },
  showSubtitle: {
    color: '#888',
    fontSize: 13,
    marginTop: 2,
  },
  showDeleteButton: {
    padding: 8,
    marginRight: 4,
  },
  showChevron: {
    marginLeft: 4,
  },
  episodeList: {
    backgroundColor: '#0d0d0d',
    paddingLeft: 32,
  },
  episodeItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingRight: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#222',
  },
  episodeContent: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  episodeInfo: {
    flex: 1,
  },
  episodeTitle: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '500',
  },
  episodeStatus: {
    color: '#666',
    fontSize: 12,
    marginTop: 2,
  },
  episodeDeleteButton: {
    padding: 8,
  },
});
