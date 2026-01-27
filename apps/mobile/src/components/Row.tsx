import React from 'react';
import { View, Text, FlatList, Pressable, StyleSheet } from 'react-native';
import Poster from './Poster';
import * as Haptics from 'expo-haptics';
import { Ionicons } from '@expo/vector-icons';

export interface RowBadge {
  text: string;
  color?: string;
}

function Row({ title, titleIcon, badge, items, getImageUri, getTitle, getSubtitle, authHeaders, onItemPress, onTitlePress, onBrowsePress, keyPrefix = '' }: {
  title: string;
  titleIcon?: keyof typeof Ionicons.glyphMap;
  badge?: RowBadge;
  items: any[];
  getImageUri: (item: any) => string | undefined;
  getTitle: (item: any) => string | undefined;
  getSubtitle?: (item: any) => string | undefined;
  authHeaders?: Record<string,string>;
  onItemPress?: (item: any) => void;
  onTitlePress?: () => void;
  onBrowsePress?: () => void;
  keyPrefix?: string;
}) {
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
            <View style={[styles.badge, badge.color ? { backgroundColor: badge.color } : null]}>
              <Text style={styles.badgeText}>{badge.text}</Text>
            </View>
          )}
          <Text style={styles.title}>{title}</Text>
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
          <Poster uri={getImageUri(item)} title={getTitle(item)} subtitle={getSubtitle?.(item)} authHeaders={authHeaders} onPress={() => onItemPress && onItemPress(item)} />
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
        getItemLayout={(_, index) => ({ length: 122, offset: 122 * index, index })}
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
  badge: {
    backgroundColor: '#ED1C24',
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
