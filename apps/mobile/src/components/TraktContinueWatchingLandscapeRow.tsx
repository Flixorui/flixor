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
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import type { TraktContinueWatchingItem } from '../core/HomeData';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const CARD_WIDTH = SCREEN_WIDTH * 0.85;
const CARD_HEIGHT = CARD_WIDTH * (9 / 16); // 16:9 aspect ratio
const CARD_GAP = 12;

interface TraktContinueWatchingLandscapeRowProps {
  items: TraktContinueWatchingItem[];
  onItemPress: (item: TraktContinueWatchingItem) => void;
  onBrowsePress?: () => void;
}

function TraktContinueWatchingLandscapeRow({
  items,
  onItemPress,
  onBrowsePress,
}: TraktContinueWatchingLandscapeRowProps) {
  const handleTitlePress = useCallback(() => {
    if (onBrowsePress) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onBrowsePress();
    }
  }, [onBrowsePress]);

  const handleItemPress = useCallback((item: TraktContinueWatchingItem) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    onItemPress(item);
  }, [onItemPress]);

  const renderCard = useCallback(({ item }: { item: TraktContinueWatchingItem }) => {
    const imageUri = item.backdrop || item.image;

    return (
      <Pressable
        onPress={() => handleItemPress(item)}
        style={({ pressed }) => [
          styles.card,
          { opacity: pressed ? 0.95 : 1 },
        ]}
      >
        {/* Landscape Image */}
        {imageUri ? (
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
          <View style={[styles.cardImage, styles.placeholder]} />
        )}

        {/* Bottom gradient */}
        <LinearGradient
          colors={['transparent', 'rgba(0,0,0,0.6)']}
          style={styles.bottomGradient}
        >
          {/* Controls row */}
          <View style={styles.controlsRow}>
            {/* Left side: Play icon, progress bar, episode info, percentage */}
            <View style={styles.leftControls}>
              <Ionicons name="play" size={12} color="#fff" />

              <View style={styles.progressTrack}>
                <View style={[styles.progressFill, { width: `${item.progress}%` }]} />
              </View>

              {/* Show episode info (S1, E1) for episodes */}
              {item.seasonNumber && item.episodeNumber && (
                <Text style={styles.episodeText}>S{item.seasonNumber}, E{item.episodeNumber}</Text>
              )}
              <Text style={styles.progressText}>{Math.round(item.progress)}%</Text>
            </View>
          </View>
        </LinearGradient>
      </Pressable>
    );
  }, [handleItemPress]);

  return (
    <View style={styles.container}>
      {/* Row header */}
      <View style={styles.header}>
        <Pressable onPress={handleTitlePress} style={styles.titleRow}>
          <View style={styles.traktHeaderBadge}>
            <Text style={styles.traktHeaderText}>Trakt</Text>
          </View>
          <Text style={styles.rowTitle}>Continue Watching</Text>
          <Ionicons name="chevron-forward" size={18} color="#fff" style={styles.chevron} />
        </Pressable>
      </View>

      {/* Horizontal card list */}
      <FlatList
        horizontal
        data={items}
        keyExtractor={(item) => item.id}
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
  traktHeaderBadge: {
    backgroundColor: '#ED1C24',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    marginRight: 8,
  },
  traktHeaderText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: '600',
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
  placeholder: {
    backgroundColor: '#2a2a2a',
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
    width: 40,
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
  progressText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '500',
  },
});

export default React.memo(TraktContinueWatchingLandscapeRow);
