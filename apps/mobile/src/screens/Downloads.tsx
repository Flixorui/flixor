/**
 * Downloads, in the style of My List: a big title over a Liquid Glass band that fades in on
 * scroll, Movies / TV Shows as Home's glass pills (with counts), a storage line, then the
 * downloaded titles. The title row hides on a scroll down and returns on a scroll up, and
 * pull to refresh uses the round glass button.
 */

import React, { useEffect, useCallback, useMemo, useRef, useState } from 'react';
import { View, Text, StyleSheet, Pressable, ActivityIndicator, Animated, Alert, Image } from 'react-native';
import { FlashList } from '@shopify/flash-list';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect, useNavigation } from '@react-navigation/native';
import * as Haptics from 'expo-haptics';
import { DownloadListItem } from '../components/downloads';
import DownloadProgressBar from '../components/downloads/DownloadProgressBar';
import HeaderGlass, { HEADER_GLASS_MIN_OPACITY } from '../components/HeaderGlass';
import { GlassPill, RoundGlassButton, glassPillStyles } from '../components/GlassPill';
import PullToRefresh, { usePullToRefresh } from '../components/PullToRefresh';
import { useScrollLinkedHeader } from '../components/useScrollLinkedHeader';
import { useTheme } from '../hooks/useTheme';
import { useAppSettings } from '../hooks/useAppSettings';
import {
  useDownloads,
  downloadStore,
  downloadService,
  useDownloadSummary,
} from '../services/downloads';
import { DownloadedMetadata, DownloadedShow, DownloadStatus } from '../types/downloads';

const TITLE_ROW = 52;
const PILL_ROW = 52;

type Tab = 'movies' | 'shows';

export default function Downloads() {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const nav: any = useNavigation();
  const { settings } = useAppSettings();
  const { isLoading, downloadedMovies, downloadedShows, error, refresh } = useDownloads();
  const [activeTab, setActiveTab] = useState<Tab>('movies');
  const [refreshing, setRefreshing] = useState(false);
  const [expandedShow, setExpandedShow] = useState<string | null>(null);
  const downloadSummary = useDownloadSummary();

  const formatBytes = useCallback((bytes: number): string => {
    if (!bytes) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
  }, []);

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

  const handleRefresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await refresh();
    } finally {
      setRefreshing(false);
    }
  }, [refresh]);

  // Header: the title row slides away on a scroll down and returns on a scroll up (as on My
  // List); the glass band fades in once content scrolls under it
  const headerH = insets.top + TITLE_ROW + PILL_ROW;
  const scrollY = useRef(new Animated.Value(0)).current;
  const { value: collapse, onScrollY, show } = useScrollLinkedHeader(TITLE_ROW);
  const headerShift = collapse.interpolate({ inputRange: [0, TITLE_ROW], outputRange: [0, -TITLE_ROW] });
  const titleOpacity = collapse.interpolate({ inputRange: [0, TITLE_ROW * 0.7], outputRange: [1, 0], extrapolate: 'clamp' });
  const glassOpacity = useMemo(
    () => scrollY.interpolate({ inputRange: [0, 8, 60], outputRange: [HEADER_GLASS_MIN_OPACITY, HEADER_GLASS_MIN_OPACITY, 1], extrapolate: 'clamp' }),
    [scrollY]
  );
  const onScroll = useMemo(
    () => Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], {
      useNativeDriver: false,
      listener: (e: any) => onScrollY(e.nativeEvent.contentOffset.y),
    }),
    [scrollY, onScrollY]
  );
  const pull = usePullToRefresh(scrollY, refreshing, handleRefresh);

  const handleTabChange = useCallback((tab: Tab) => {
    setActiveTab(tab);
    show();
  }, [show]);

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
      const showDownloadedBytes = item.episodes.reduce((sum, ep) => {
        const epGlobalKey = `${item.serverId}:${ep.ratingKey}`;
        const epMedia = downloadStore.getState().media.get(epGlobalKey);
        return sum + (epMedia?.downloadedBytes || 0);
      }, 0);

      return (
        <View>
          <Pressable
            style={styles.showItem}
            onPress={() => {
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
              setExpandedShow(isExpanded ? null : showKey);
            }}
          >
            <View style={[styles.showPoster, { borderRadius: Math.min(settings.posterBorderRadius, 8) }]}>
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
                {showDownloadedBytes > 0 ? ` • ${formatBytes(showDownloadedBytes)}` : ''}
              </Text>
            </View>
            <Pressable
              onPress={() => handleDeleteShow(item)}
              style={styles.showDeleteButton}
              hitSlop={8}
              accessibilityRole="button"
              accessibilityLabel={`Delete all episodes of ${item.title}`}
            >
              <Ionicons name="trash-outline" size={20} color="rgba(255,255,255,0.7)" />
            </Pressable>
            <Ionicons
              name={isExpanded ? 'chevron-down' : 'chevron-forward'}
              size={18}
              color="#8e8e93"
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
                          {(() => {
                            if (!epMedia) return 'Unknown';
                            if (epMedia.status === DownloadStatus.COMPLETED) {
                              const size = epMedia.downloadedBytes ? formatBytes(epMedia.downloadedBytes) : '';
                              return ['Downloaded', size].filter(Boolean).join(' • ');
                            }
                            if (epMedia.status === DownloadStatus.PAUSED) {
                              if (epMedia.totalBytes && epMedia.downloadedBytes) {
                                return `Paused • ${formatBytes(epMedia.downloadedBytes)} / ${formatBytes(epMedia.totalBytes)}`;
                              }
                              return 'Paused';
                            }
                            if (
                              epMedia.status === DownloadStatus.DOWNLOADING ||
                              epMedia.status === DownloadStatus.QUEUED
                            ) {
                              if (epMedia.totalBytes && epMedia.downloadedBytes) {
                                return `Downloading • ${formatBytes(epMedia.downloadedBytes)} / ${formatBytes(epMedia.totalBytes)}`;
                              }
                              return 'Downloading';
                            }
                            if (epMedia.status === DownloadStatus.FAILED) {
                              return epMedia.errorMessage || 'Failed';
                            }
                            return epMedia.status || 'Unknown';
                          })()}
                        </Text>
                      </View>
                      {isCompleted && (
                        <Ionicons name="play-circle" size={28} color="#fff" />
                      )}
                    </Pressable>
                    <Pressable
                      onPress={() => handleDeleteEpisode(epGlobalKey, ep.title)}
                      style={styles.episodeDeleteButton}
                      hitSlop={8}
                      accessibilityRole="button"
                      accessibilityLabel={`Delete ${ep.title}`}
                    >
                      <Ionicons name="trash-outline" size={18} color="rgba(255,255,255,0.7)" />
                    </Pressable>
                  </View>
                );
              })}
            </View>
          )}
        </View>
      );
    },
    [nav, expandedShow, handleDeleteEpisode, handleDeleteShow, formatBytes, settings.posterBorderRadius]
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

  const firstLoad = isLoading && downloadedMovies.length === 0 && downloadedShows.length === 0;
  const failed = !!error && downloadedMovies.length === 0 && downloadedShows.length === 0;

  // Storage line, scrolling with the list under the pills
  const summary = (
    <View style={styles.summary}>
      <Text style={styles.summaryText}>
        {formatBytes(downloadSummary.totalDownloadedBytes)} downloaded
      </Text>
      {downloadSummary.activeCount > 0 ? (
        <View style={styles.summaryActive}>
          <View style={styles.summaryRow}>
            <Text style={styles.summaryLabel}>Downloading {downloadSummary.activeCount}</Text>
            <Text style={styles.summaryLabel}>
              {downloadSummary.activeTotalBytes > 0
                ? `${formatBytes(downloadSummary.activeDownloadedBytes)} of ${formatBytes(downloadSummary.activeTotalBytes)}`
                : 'Starting'}
            </Text>
          </View>
          <DownloadProgressBar
            progress={downloadSummary.activeTotalBytes > 0
              ? (downloadSummary.activeDownloadedBytes / downloadSummary.activeTotalBytes) * 100
              : 0}
            height={4}
            backgroundColor="rgba(255,255,255,0.12)"
            progressColor={theme.accent}
          />
        </View>
      ) : null}
    </View>
  );

  const emptyState = firstLoad ? (
    <View style={styles.emptyContainer}>
      <ActivityIndicator color="#fff" />
    </View>
  ) : failed ? (
    <View style={styles.emptyContainer}>
      <Ionicons name="alert-circle-outline" size={44} color="#48484a" />
      <Text style={styles.emptyTitle}>Couldn't load downloads</Text>
      <Text style={styles.emptySubtitle}>{error}</Text>
      <Pressable style={styles.retryButton} onPress={refresh} accessibilityRole="button">
        <Text style={styles.retryText}>Try Again</Text>
      </Pressable>
    </View>
  ) : (
    <View style={styles.emptyContainer}>
      <Ionicons name="arrow-down-circle-outline" size={44} color="#48484a" />
      <Text style={styles.emptyTitle}>
        No {activeTab === 'movies' ? 'movies' : 'TV shows'} downloaded
      </Text>
      <Text style={styles.emptySubtitle}>
        Download movies and episodes from their details page to watch offline.
      </Text>
    </View>
  );

  const listProps = {
    // Only once something is stored or downloading ("0 B downloaded" says nothing)
    ListHeaderComponent: firstLoad || failed || (!downloadSummary.totalDownloadedBytes && !downloadSummary.activeCount) ? null : summary,
    ListEmptyComponent: emptyState,
    contentContainerStyle: { paddingTop: headerH + 4, paddingBottom: insets.bottom + 110 },
    onScroll,
    scrollEventThrottle: 16,
    ...pull.dragHandlers,
  };

  return (
    <View style={styles.container}>
      {activeTab === 'movies' ? (
        <FlashList
          key="movies"
          data={firstLoad || failed ? [] : downloadedMovies}
          renderItem={renderMovieItem}
          keyExtractor={movieKeyExtractor}
          {...listProps}
        />
      ) : (
        <FlashList
          key="shows"
          data={firstLoad || failed ? [] : downloadedShows}
          renderItem={renderShowItem}
          keyExtractor={showKeyExtractor}
          extraData={expandedShow}
          {...listProps}
        />
      )}

      {/* Header: title (with a back button when Downloads isn't a tab), then the pills */}
      <Animated.View style={[styles.header, { height: headerH, transform: [{ translateY: headerShift }] }]} pointerEvents="box-none">
        {/* Reaches one title row above, so the status bar stays covered as the header slides up */}
        <View pointerEvents="none" style={[styles.band, { top: -TITLE_ROW, height: headerH + TITLE_ROW }]}>
          <Animated.View style={[StyleSheet.absoluteFill, { opacity: glassOpacity }]}>
            <HeaderGlass />
          </Animated.View>
        </View>
        <Animated.View style={[styles.titleRow, { marginTop: insets.top, opacity: titleOpacity }]} pointerEvents="box-none">
          {!settings.showDownloadsTab ? (
            <View style={styles.backButton}>
              <RoundGlassButton icon="chevron-back" label="Back" size={36} iconSize={22} onPress={() => nav.goBack()} />
            </View>
          ) : null}
          <Text style={styles.headerTitle} accessibilityRole="header">Downloads</Text>
        </Animated.View>
        <View style={{ height: PILL_ROW }}>
          <View style={[glassPillStyles.row, styles.pills]}>
            <GlassPill label="Movies" count={downloadedMovies.length} selected={activeTab === 'movies'} onPress={() => handleTabChange('movies')} />
            <GlassPill label="TV Shows" count={downloadedShows.length} selected={activeTab === 'shows'} onPress={() => handleTabChange('shows')} />
          </View>
        </View>
      </Animated.View>

      <PullToRefresh {...pull.indicatorProps} top={headerH + 6} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0e0e10' },
  header: { position: 'absolute', top: 0, left: 0, right: 0 },
  band: { position: 'absolute', left: 0, right: 0, overflow: 'hidden' },
  titleRow: { height: TITLE_ROW, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20 },
  backButton: { marginRight: 10 },
  headerTitle: { flex: 1, color: '#fff', fontSize: 25, fontWeight: '600' },
  pills: { flexDirection: 'row' },
  summary: { paddingHorizontal: 20, paddingTop: 4, paddingBottom: 10 },
  summaryText: { color: '#8e8e93', fontSize: 13, fontWeight: '500' },
  summaryActive: { marginTop: 10, gap: 6 },
  summaryRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  summaryLabel: { color: '#fff', fontSize: 13, fontWeight: '600' },
  emptyContainer: { alignItems: 'center', justifyContent: 'center', paddingTop: 120, paddingHorizontal: 32 },
  emptyTitle: { color: '#fff', fontSize: 18, fontWeight: '700', marginTop: 12, textAlign: 'center' },
  emptySubtitle: { color: '#8e8e93', fontSize: 14, marginTop: 6, textAlign: 'center', lineHeight: 20 },
  retryButton: { marginTop: 16, paddingHorizontal: 18, height: 40, borderRadius: 10, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' },
  retryText: { color: '#000', fontSize: 15, fontWeight: '700' },
  showItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  showPoster: {
    width: 64,
    height: 96,
    backgroundColor: '#1a1a1c',
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
    color: '#8e8e93',
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
    marginHorizontal: 16,
    marginBottom: 8,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.05)',
    overflow: 'hidden',
  },
  episodeItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingRight: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.08)',
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
    color: '#8e8e93',
    fontSize: 12,
    marginTop: 2,
  },
  episodeDeleteButton: {
    padding: 8,
  },
});
