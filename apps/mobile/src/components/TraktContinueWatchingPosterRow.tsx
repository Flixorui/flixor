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
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { useAppSettings } from '../hooks/useAppSettings';
import type { TraktContinueWatchingItem } from '../core/HomeData';

const POSTER_SIZES = {
  small: { width: 96, height: 144 },
  medium: { width: 110, height: 165 },
  large: { width: 128, height: 192 },
} as const;

const CARD_GAP = 12;

interface TraktContinueWatchingPosterRowProps {
  items: TraktContinueWatchingItem[];
  onItemPress: (item: TraktContinueWatchingItem) => void;
  onBrowsePress?: () => void;
}

function TraktContinueWatchingPosterRow({
  items,
  onItemPress,
  onBrowsePress,
}: TraktContinueWatchingPosterRowProps) {
  const { settings } = useAppSettings();
  const size = POSTER_SIZES[settings.posterSize] || POSTER_SIZES.medium;
  const borderRadius = settings.posterBorderRadius;

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
    const imageUri = item.image;

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
          {imageUri ? (
            <FastImage
              source={{
                uri: imageUri,
                priority: FastImage.priority.high,
                cache: FastImage.cacheControl.immutable,
              }}
              style={[styles.posterImage, { borderRadius }]}
              resizeMode={FastImage.resizeMode.cover}
            />
          ) : (
            <View style={[styles.posterImage, styles.placeholder, { borderRadius }]} />
          )}

          {/* Bottom gradient with progress */}
          <LinearGradient
            colors={['transparent', 'rgba(0,0,0,0.8)']}
            style={[styles.bottomGradient, { borderBottomLeftRadius: borderRadius, borderBottomRightRadius: borderRadius }]}
          >
            {/* Progress row */}
            <View style={styles.progressRow}>
              <Ionicons name="play" size={10} color="#fff" />
              <View style={styles.progressTrack}>
                <View style={[styles.progressFill, { width: `${item.progress}%` }]} />
              </View>
              <Text style={styles.progressText}>{Math.round(item.progress)}%</Text>
            </View>
          </LinearGradient>
        </View>

        {/* Title and subtitle below poster */}
        {settings.showPosterTitles && (
          <View style={[styles.textContainer, { width: size.width }]}>
            <Text style={styles.title} numberOfLines={2}>{item.title}</Text>
            {item.subtitle && (
              <Text style={styles.subtitle} numberOfLines={1}>{item.subtitle}</Text>
            )}
          </View>
        )}
      </Pressable>
    );
  }, [handleItemPress, size, borderRadius, settings.showPosterTitles]);

  return (
    <View style={styles.container}>
      {/* Row header */}
      <View style={styles.header}>
        <Pressable onPress={handleTitlePress} style={styles.titleRow}>
          <View style={styles.traktBadge}>
            <Text style={styles.traktText}>Trakt</Text>
          </View>
          <Text style={styles.rowTitle}>Continue Watching</Text>
          <Ionicons name="chevron-forward" size={18} color="#fff" style={styles.chevron} />
        </Pressable>
      </View>

      {/* Horizontal poster list */}
      <FlatList
        horizontal
        data={items}
        keyExtractor={(item) => item.id}
        renderItem={renderCard}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.listContent}
        bounces={false}
        overScrollMode="never"
        windowSize={5}
        initialNumToRender={4}
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
    fontWeight: 'bold',
    includeFontPadding: false,
    textAlignVertical: 'center',
  },
  traktBadge: {
    backgroundColor: '#ED1C24',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    marginRight: 8,
  },
  traktText: {
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
    alignItems: 'center',
  },
  posterContainer: {
    overflow: 'hidden',
    backgroundColor: '#1a1a1a',
  },
  posterImage: {
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
    height: 36,
    justifyContent: 'flex-end',
    paddingBottom: 6,
    paddingHorizontal: 8,
  },
  progressRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  progressTrack: {
    flex: 1,
    height: 3,
    backgroundColor: 'rgba(255,255,255,0.4)',
    borderRadius: 2,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#ED1C24', // Trakt red
    borderRadius: 2,
  },
  progressText: {
    color: '#fff',
    fontSize: 9,
    fontWeight: '500',
  },
  textContainer: {
    marginTop: 6,
    paddingHorizontal: 2,
  },
  title: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '500',
    lineHeight: 16,
  },
  subtitle: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 11,
    marginTop: 2,
  },
});

export default React.memo(TraktContinueWatchingPosterRow);
