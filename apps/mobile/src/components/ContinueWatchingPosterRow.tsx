import React, { useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  Pressable,
  StyleSheet,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { LinearGradient } from 'expo-linear-gradient';
import ContextMenu from 'react-native-context-menu-view';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import type { PlexMediaItem } from '@flixor/core';
import { useAppSettings } from '../hooks/useAppSettings';

const POSTER_SIZES = {
  small: { width: 96, height: 144 },
  medium: { width: 110, height: 165 },
  large: { width: 128, height: 192 },
} as const;

const CARD_GAP = 12;

interface ContinueWatchingPosterRowProps {
  items: PlexMediaItem[];
  onItemPress: (item: PlexMediaItem) => void;
  onBrowsePress?: () => void;
  onRemove?: (item: PlexMediaItem) => void;
  onMarkWatched?: (item: PlexMediaItem) => void;
  onInfo?: (item: PlexMediaItem) => void;
  getImageUri: (item: PlexMediaItem) => string;
  getTitle: (item: PlexMediaItem) => string | undefined;
  getSubtitle?: (item: PlexMediaItem) => string | undefined;
}

// Calculate progress percentage
const getProgress = (item: PlexMediaItem): number => {
  if (!item.viewOffset || !item.duration) return 0;
  return Math.min((item.viewOffset / item.duration) * 100, 100);
};

// Format remaining time
const getRemainingTime = (item: PlexMediaItem): string => {
  if (!item.duration) return '';
  const remainingMs = item.duration - (item.viewOffset || 0);
  const minutes = Math.floor(remainingMs / 60000);
  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
  }
  return `${minutes}m`;
};

function ContinueWatchingPosterRow({
  items,
  onItemPress,
  onBrowsePress,
  onRemove,
  onMarkWatched,
  onInfo,
  getImageUri,
  getTitle,
  getSubtitle,
}: ContinueWatchingPosterRowProps) {
  const { settings } = useAppSettings();
  const size = POSTER_SIZES[settings.posterSize] || POSTER_SIZES.medium;
  const borderRadius = settings.posterBorderRadius;

  const handleTitlePress = useCallback(() => {
    if (onBrowsePress) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onBrowsePress();
    }
  }, [onBrowsePress]);

  const handleItemPress = useCallback((item: PlexMediaItem) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    onItemPress(item);
  }, [onItemPress]);

  const renderCard = useCallback(({ item }: { item: PlexMediaItem }) => {
    const progress = getProgress(item);
    const remainingTime = getRemainingTime(item);
    const imageUri = getImageUri(item);
    const title = getTitle(item);
    const subtitle = getSubtitle?.(item);

    return (
      <Pressable
        onPress={() => handleItemPress(item)}
        style={({ pressed }) => [
          styles.card,
          { width: size.width, opacity: pressed ? 0.95 : 1 },
        ]}
      >
        {/* Poster Image */}
        <View style={[styles.posterContainer, { width: size.width, height: size.height, borderRadius }]}>
          <FastImage
            source={{
              uri: imageUri,
              priority: FastImage.priority.high,
              cache: FastImage.cacheControl.immutable,
            }}
            style={styles.cardImage}
            resizeMode={FastImage.resizeMode.cover}
          />

          {/* Bottom gradient with controls */}
          <LinearGradient
            colors={['transparent', 'rgba(0,0,0,0.8)']}
            style={[styles.bottomGradient, { borderBottomLeftRadius: borderRadius, borderBottomRightRadius: borderRadius }]}
          >
            {/* Controls row */}
            <View style={styles.controlsRow}>
              {/* Left side: Play icon, progress bar, time */}
              <View style={styles.leftControls}>
                <Ionicons name="play" size={10} color="#fff" />
                <View style={styles.progressTrack}>
                  <View style={[styles.progressFill, { width: `${progress}%` }]} />
                </View>
                <Text style={styles.timeText}>{remainingTime}</Text>
              </View>

              {/* Right side: Context Menu */}
              <Pressable onPress={(e) => e.stopPropagation()}>
                <ContextMenu
                  actions={[
                    { title: 'Info', systemIcon: 'info.circle' },
                    { title: 'Mark as Watched', systemIcon: 'checkmark.circle' },
                    { title: 'Remove', systemIcon: 'trash', destructive: true },
                  ]}
                  onPress={(e) => {
                    const index = e.nativeEvent.index;
                    if (index === 0) onInfo?.(item);
                    else if (index === 1) onMarkWatched?.(item);
                    else if (index === 2) onRemove?.(item);
                    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                  }}
                  dropdownMenuMode
                >
                  <View style={styles.menuButton}>
                    <Ionicons name="ellipsis-horizontal" size={14} color="rgba(255,255,255,0.6)" />
                  </View>
                </ContextMenu>
              </Pressable>
            </View>
          </LinearGradient>
        </View>

        {/* Title and subtitle below poster */}
        {settings.showPosterTitles && (title || subtitle) && (
          <View style={styles.textContainer}>
            {title && <Text style={styles.titleText} numberOfLines={1}>{title}</Text>}
            {subtitle && <Text style={styles.subtitleText} numberOfLines={1}>{subtitle}</Text>}
          </View>
        )}
      </Pressable>
    );
  }, [getImageUri, getTitle, getSubtitle, handleItemPress, onInfo, onMarkWatched, onRemove, size, borderRadius, settings.showPosterTitles]);

  return (
    <View style={styles.container}>
      {/* Row header */}
      <View style={styles.header}>
        <Pressable onPress={handleTitlePress} style={styles.titleRow}>
          <Text style={styles.rowTitle}>Continue Watching</Text>
          <Ionicons name="chevron-forward" size={18} color="#fff" style={styles.chevron} />
        </Pressable>
      </View>

      {/* Horizontal card list */}
      <FlatList
        horizontal
        data={items}
        keyExtractor={(item) => item.ratingKey || item.key || ''}
        renderItem={renderCard}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.listContent}
        decelerationRate="fast"
        bounces={false}
        overScrollMode="never"
        windowSize={5}
        initialNumToRender={6}
        maxToRenderPerBatch={4}
        removeClippedSubviews={true}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 16,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 12,
    marginTop: 15,
    paddingHorizontal: 16,
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  rowTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    lineHeight: 22,
  },
  chevron: {
    marginLeft: 4,
    marginTop: 1,
  },
  listContent: {
    paddingHorizontal: 16,
    gap: CARD_GAP,
  },
  card: {
    // width set dynamically
  },
  posterContainer: {
    overflow: 'hidden',
    backgroundColor: '#1a1a1a',
  },
  cardImage: {
    width: '100%',
    height: '100%',
    backgroundColor: '#1a1a1a',
  },
  bottomGradient: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 45,
    justifyContent: 'flex-end',
  },
  controlsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 8,
    paddingBottom: 8,
  },
  leftControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    flex: 1,
  },
  progressTrack: {
    flex: 1,
    maxWidth: 40,
    height: 3,
    backgroundColor: 'rgba(255,255,255,0.4)',
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#fff',
    borderRadius: 2,
  },
  timeText: {
    color: '#fff',
    fontSize: 9,
    fontWeight: '500',
  },
  menuButton: {
    padding: 2,
  },
  textContainer: {
    marginTop: 6,
  },
  titleText: {
    color: '#ddd',
    fontSize: 12,
  },
  subtitleText: {
    color: '#888',
    fontSize: 11,
    marginTop: 2,
  },
});

export default React.memo(ContinueWatchingPosterRow);
