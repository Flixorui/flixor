import React, { useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  Image,
  Pressable,
  StyleSheet,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { LinearGradient } from 'expo-linear-gradient';
import ContextMenu from 'react-native-context-menu-view';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import type { ContinueWatchingEntry } from '../core/TraktContinueWatching';
import {
  continueWatchingEpisodeLabel,
  continueWatchingMenuItems,
  continueWatchingStatus,
  type ContinueWatchingMenuAction,
} from './home/continueWatchingMenu';
import { useAppSettings } from '../hooks/useAppSettings';

const POSTER_SIZES = {
  small: { width: 96, height: 144 },
  medium: { width: 110, height: 165 },
  large: { width: 128, height: 192 },
} as const;

const CARD_GAP = 12;

interface ContinueWatchingPosterRowProps {
  title: string;
  entries: ContinueWatchingEntry[];
  blurNextUp: boolean;
  onItemPress: (entry: ContinueWatchingEntry) => void;
  onBrowsePress?: () => void;
  onAction: (action: ContinueWatchingMenuAction, entry: ContinueWatchingEntry) => void;
}

function ContinueWatchingPosterRow({
  title,
  entries,
  blurNextUp,
  onItemPress,
  onBrowsePress,
  onAction,
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

  const handleItemPress = useCallback((entry: ContinueWatchingEntry) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    onItemPress(entry);
  }, [onItemPress]);

  const renderCard = useCallback(({ item }: { item: ContinueWatchingEntry }) => {
    const imageUri = item.image || item.backdrop;
    const episodeLabel = continueWatchingEpisodeLabel(item);
    const status = continueWatchingStatus(item);
    const menuItems = continueWatchingMenuItems(item);
    const subtitle = episodeLabel ?? (item.year ? String(item.year) : undefined);

    return (
      <Pressable
        onPress={() => handleItemPress(item)}
        style={({ pressed }) => [
          styles.card,
          { width: size.width, opacity: pressed ? 0.95 : 1 },
        ]}
      >
        <View style={[styles.posterContainer, { width: size.width, height: size.height, borderRadius }]}>
          {imageUri && item.isUpNext && blurNextUp ? (
            <Image source={{ uri: imageUri }} blurRadius={24} style={styles.cardImage} resizeMode="cover" />
          ) : imageUri ? (
            <FastImage
              source={{
                uri: imageUri,
                priority: FastImage.priority.high,
                cache: FastImage.cacheControl.immutable,
              }}
              style={styles.cardImage}
              resizeMode={FastImage.resizeMode.cover}
            />
          ) : (
            <View style={styles.cardImage} />
          )}

          <LinearGradient
            colors={['transparent', 'rgba(0,0,0,0.8)']}
            style={[styles.bottomGradient, { borderBottomLeftRadius: borderRadius, borderBottomRightRadius: borderRadius }]}
          >
            <View style={styles.controlsRow}>
              <View style={styles.leftControls}>
                <Ionicons name="play" size={10} color="#fff" />
                {!item.isUpNext && (
                  <View style={styles.progressTrack}>
                    <View style={[styles.progressFill, { width: `${item.progress}%` }]} />
                  </View>
                )}
                {episodeLabel && <Text style={styles.episodeText}>{episodeLabel}</Text>}
                <Text style={styles.timeText}>{status}</Text>
              </View>

              <Pressable onPress={(e) => e.stopPropagation()}>
                <ContextMenu
                  actions={menuItems}
                  onPress={(e) => {
                    const selected = menuItems[e.nativeEvent.index];
                    if (selected) onAction(selected.action, item);
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

        {settings.showPosterTitles && (
          <View style={styles.textContainer}>
            <Text style={styles.titleText} numberOfLines={1}>{item.title}</Text>
            {subtitle && <Text style={styles.subtitleText} numberOfLines={1}>{subtitle}</Text>}
            {item.versionLabel && <Text style={styles.versionText} numberOfLines={1}>{item.versionLabel}</Text>}
          </View>
        )}
      </Pressable>
    );
  }, [blurNextUp, handleItemPress, onAction, size, borderRadius, settings.showPosterTitles]);

  return (
    <View style={styles.container}>
      {/* Row header */}
      <View style={styles.header}>
        <Pressable onPress={handleTitlePress} style={styles.titleRow}>
          <Text style={styles.rowTitle}>{title}</Text>
          <Ionicons name="chevron-forward" size={18} color="#fff" style={styles.chevron} />
        </Pressable>
      </View>

      {/* Horizontal card list */}
      <FlatList
        horizontal
        data={entries}
        keyExtractor={(entry) => entry.key}
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
  episodeText: {
    color: '#fff',
    fontSize: 9,
    fontWeight: '500',
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
  versionText: {
    color: '#888',
    fontSize: 10,
    marginTop: 2,
  },
});

export default React.memo(ContinueWatchingPosterRow);
