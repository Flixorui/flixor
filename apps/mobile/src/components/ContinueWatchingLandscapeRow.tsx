import React, { useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  Pressable,
  Dimensions,
  StyleSheet,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { LinearGradient } from 'expo-linear-gradient';
import ContextMenu from 'react-native-context-menu-view';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import type { PlexMediaItem } from '@flixor/core';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const CARD_WIDTH = SCREEN_WIDTH * 0.85;
const CARD_HEIGHT = CARD_WIDTH * (9 / 16); // 16:9 aspect ratio
const CARD_GAP = 12;

interface ContinueWatchingLandscapeRowProps {
  items: PlexMediaItem[];
  onItemPress: (item: PlexMediaItem) => void;
  onBrowsePress?: () => void;
  onRemove?: (item: PlexMediaItem) => void;
  onMarkWatched?: (item: PlexMediaItem) => void;
  onInfo?: (item: PlexMediaItem) => void;
  getImageUri: (item: PlexMediaItem) => string;
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

// Get title for display (used in menu)
const getTitle = (item: PlexMediaItem): string => {
  if (item.type === 'episode') {
    return item.grandparentTitle || item.title || 'Episode';
  }
  return item.title || '';
};

function ContinueWatchingLandscapeRow({
  items,
  onItemPress,
  onBrowsePress,
  onRemove,
  onMarkWatched,
  onInfo,
  getImageUri,
}: ContinueWatchingLandscapeRowProps) {
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

    return (
      <Pressable
        onPress={() => handleItemPress(item)}
        style={({ pressed }) => [
          styles.card,
          { opacity: pressed ? 0.95 : 1 },
        ]}
      >
        {/* Landscape Image - includes movie title/branding */}
        <FastImage
          source={{
            uri: imageUri,
            priority: FastImage.priority.high,
            cache: FastImage.cacheControl.immutable,
          }}
          style={styles.cardImage}
          resizeMode={FastImage.resizeMode.cover}
        />

        {/* Bottom gradient - seamless blend */}
        <LinearGradient
          colors={['transparent', 'rgba(0,0,0,0.6)']}
          style={styles.bottomGradient}
        >
          {/* Controls row */}
          <View style={styles.controlsRow}>
            {/* Left side: Play icon, progress bar, time */}
            <View style={styles.leftControls}>
              <Ionicons name="play" size={12} color="#fff" />

              <View style={styles.progressTrack}>
                <View style={[styles.progressFill, { width: `${progress}%` }]} />
              </View>

              <Text style={styles.timeText}>{remainingTime}</Text>
            </View>

            {/* Right side: Context Menu - wrapped in Pressable to stop event propagation */}
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
                  <Ionicons name="ellipsis-horizontal" size={16} color="rgba(255,255,255,0.6)" />
                </View>
              </ContextMenu>
            </Pressable>
          </View>
        </LinearGradient>
      </Pressable>
    );
  }, [getImageUri, handleItemPress, onInfo, onMarkWatched, onRemove]);

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
        snapToInterval={CARD_WIDTH + CARD_GAP}
        decelerationRate="fast"
        snapToAlignment="start"
        bounces={false}
        overScrollMode="never"
        windowSize={3}
        initialNumToRender={2}
        maxToRenderPerBatch={2}
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
    fontWeight: 'bold',
    includeFontPadding: false,
    textAlignVertical: 'center',
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
    width: CARD_WIDTH,
    height: CARD_HEIGHT,
    borderRadius: 12,
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
    height: 50,
    justifyContent: 'flex-end',
    borderBottomLeftRadius: 12,
    borderBottomRightRadius: 12,
  },
  controlsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingBottom: 10,
  },
  leftControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  progressTrack: {
    width: 28,
    height: 4,
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
    fontSize: 11,
    fontWeight: '500',
  },
  menuButton: {
    padding: 4,
  },
});

export default React.memo(ContinueWatchingLandscapeRow);
