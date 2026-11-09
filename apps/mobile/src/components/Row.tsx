import React from 'react';
import { View, Text, FlatList, Pressable, StyleSheet } from 'react-native';
import Poster, { LANDSCAPE_CARD_SIZE, POSTER_GAP, POSTER_SIZES } from './Poster';
import { useAppSettings } from '../hooks/useAppSettings';
import { useTheme } from '../hooks/useTheme';
import type { RowLayout } from '../core/SettingsData';
import * as Haptics from 'expo-haptics';
import { Ionicons } from '@expo/vector-icons';

export interface RowBadge {
  text: string;
  color?: string;
}

function Row({ title, caption, titleIcon, badge, items, layout = 'poster', getImageUri, getTitle, getSubtitle, authHeaders, onItemPress, onTitlePress, onBrowsePress, keyPrefix = '' }: {
  title: string;
  /** Shown beside the title, e.g. the addon when two rows share a title. */
  caption?: string;
  titleIcon?: keyof typeof Ionicons.glyphMap;
  badge?: RowBadge;
  items: any[];
  layout?: RowLayout;
  getImageUri: (item: any) => string | undefined;
  getTitle: (item: any) => string | undefined;
  getSubtitle?: (item: any) => string | undefined;
  authHeaders?: Record<string,string>;
  onItemPress?: (item: any) => void;
  onTitlePress?: () => void;
  onBrowsePress?: () => void;
  keyPrefix?: string;
}) {
  const { settings } = useAppSettings();
  const theme = useTheme();
  const isLandscape = layout === 'landscape';
  const cardWidth = isLandscape
    ? LANDSCAPE_CARD_SIZE.width
    : (POSTER_SIZES[settings.posterSize] || POSTER_SIZES.medium).width;
  const itemLength = cardWidth + POSTER_GAP;

  const handleTitlePress = () => {
    // Prefer onBrowsePress for chevron tap, fall back to onTitlePress
    const handler = onBrowsePress || onTitlePress;
    if (handler) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      handler();
    }
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Pressable
          onPress={handleTitlePress}
          disabled={!onBrowsePress && !onTitlePress}
          style={styles.titlePressable}
        >
          {titleIcon && (
            <Ionicons name={titleIcon} size={16} color="#fff" style={styles.titleIcon} />
          )}
          {badge && (
            <View style={[styles.badge, { backgroundColor: badge.color || theme.accent }]}>
              <Text style={styles.badgeText}>{badge.text}</Text>
            </View>
          )}
          <Text style={styles.title}>{title}</Text>
          {caption ? <Text style={styles.caption} numberOfLines={1}>{caption}</Text> : null}
          {(onBrowsePress || onTitlePress) && (
            <Ionicons name="chevron-forward" size={18} color="#fff" style={styles.chevron} />
          )}
        </Pressable>
      </View>
      <FlatList
        horizontal
        data={items}
        keyExtractor={(item, idx) => `${keyPrefix}${item.id || item.ratingKey || `${title}-${idx}`}`}
        renderItem={({ item }) => (
          <Poster
            uri={getImageUri(item)}
            title={getTitle(item)}
            subtitle={getSubtitle?.(item)}
            rating={item.rating}
            width={isLandscape ? LANDSCAPE_CARD_SIZE.width : undefined}
            height={isLandscape ? LANDSCAPE_CARD_SIZE.height : undefined}
            authHeaders={authHeaders}
            onPress={() => onItemPress && onItemPress(item)}
          />
        )}
        showsHorizontalScrollIndicator={false}
        bounces={false}
        overScrollMode="never"
        alwaysBounceHorizontal={false}
        contentContainerStyle={{ paddingHorizontal: 16 }}
        windowSize={5}
        initialNumToRender={6}
        maxToRenderPerBatch={4}
        removeClippedSubviews={true}
        getItemLayout={(_, index) => ({ length: itemLength, offset: itemLength * index, index })}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 16,
    overflow: 'visible',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 15,
    marginTop: 15,
    paddingHorizontal: 16,
    overflow: 'visible',
  },
  titlePressable: {
    flexDirection: 'row',
    alignItems: 'center',
    overflow: 'visible',
  },
  title: {
    color: '#fff',
    fontSize: 18,
    fontWeight: 'bold',
    includeFontPadding: false, // Android: prevents extra padding that can cause clipping
    textAlignVertical: 'center', // Android: ensures proper vertical alignment
  },
  chevron: {
    marginLeft: 4,
    marginTop: 1,
  },
  titleIcon: {
    marginRight: 6,
  },
  caption: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 13,
    marginLeft: 8,
    flexShrink: 1,
  },
  badge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
    marginRight: 8,
  },
  badgeText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: '600',
  },
});

export default React.memo(Row);
