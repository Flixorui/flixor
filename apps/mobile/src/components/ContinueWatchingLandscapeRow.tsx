import React, { useCallback } from 'react';
import {
  View,
  Text,
  FlatList,
  Image,
  Pressable,
  StyleSheet,
  useWindowDimensions,
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

const CARD_GAP = 12;
const TABLET_BREAKPOINT = 600;
const PHONE_CARD_WIDTH_RATIO = 0.85;
const TABLET_CARD_WIDTH_RATIO = 0.55;
const TABLET_CARD_MAX_WIDTH = 460;

interface ContinueWatchingLandscapeRowProps {
  title: string;
  entries: ContinueWatchingEntry[];
  blurNextUp: boolean;
  onItemPress: (entry: ContinueWatchingEntry) => void;
  onBrowsePress?: () => void;
  onAction: (action: ContinueWatchingMenuAction, entry: ContinueWatchingEntry) => void;
}

function ContinueWatchingLandscapeRow({
  title,
  entries,
  blurNextUp,
  onItemPress,
  onBrowsePress,
  onAction,
}: ContinueWatchingLandscapeRowProps) {
  const { width: windowWidth, height: windowHeight } = useWindowDimensions();
  const isTablet = Math.min(windowWidth, windowHeight) >= TABLET_BREAKPOINT;
  const cardWidth = Math.round(
    isTablet
      ? Math.min(windowWidth * TABLET_CARD_WIDTH_RATIO, TABLET_CARD_MAX_WIDTH)
      : windowWidth * PHONE_CARD_WIDTH_RATIO
  );
  const cardHeight = Math.round(cardWidth * (9 / 16));

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
    const imageUri = item.backdrop || item.image;
    const episodeLabel = continueWatchingEpisodeLabel(item);
    const status = continueWatchingStatus(item);
    const menuItems = continueWatchingMenuItems(item);

    return (
      <Pressable
        onPress={() => handleItemPress(item)}
        style={({ pressed }) => [
          styles.card,
          { width: cardWidth, height: cardHeight, opacity: pressed ? 0.95 : 1 },
        ]}
      >
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
          <View style={[styles.cardImage, styles.placeholder]}>
            <Text style={styles.placeholderTitle} numberOfLines={2}>{item.title}</Text>
          </View>
        )}

        {/* Bottom gradient - seamless blend */}
        <LinearGradient
          colors={['transparent', 'rgba(0,0,0,0.6)']}
          style={styles.bottomGradient}
        >
          <View style={styles.controlsRow}>
            <View style={styles.leftControls}>
              <Ionicons name="play" size={12} color="#fff" />

              {!item.isUpNext && (
                <View style={styles.progressTrack}>
                  <View style={[styles.progressFill, { width: `${item.progress}%` }]} />
                </View>
              )}

              {episodeLabel && <Text style={styles.episodeText}>{episodeLabel}</Text>}
              <Text style={styles.timeText}>{status}</Text>
              {item.versionLabel && <Text style={styles.versionText}>{item.versionLabel}</Text>}
            </View>

            {/* Wrapped in Pressable to stop event propagation */}
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
                  <Ionicons name="ellipsis-horizontal" size={16} color="rgba(255,255,255,0.6)" />
                </View>
              </ContextMenu>
            </Pressable>
          </View>
        </LinearGradient>
      </Pressable>
    );
  }, [blurNextUp, cardHeight, cardWidth, handleItemPress, onAction]);

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
        snapToInterval={cardWidth + CARD_GAP}
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
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: '#1a1a1a',
  },
  cardImage: {
    width: '100%',
    height: '100%',
    backgroundColor: '#1a1a1a',
  },
  placeholder: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
  },
  placeholderTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
    textAlign: 'center',
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
  episodeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '500',
  },
  timeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '500',
  },
  versionText: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 10,
    fontWeight: '400',
    marginLeft: 6,
  },
  menuButton: {
    padding: 4,
  },
});

export default React.memo(ContinueWatchingLandscapeRow);
