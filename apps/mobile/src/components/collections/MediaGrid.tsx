import React, { useCallback } from 'react';
import { ActivityIndicator, Dimensions, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { FlashList } from '@shopify/flash-list';
import { Ionicons } from '@expo/vector-icons';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';

export interface MediaGridItem {
  id: string;
  title: string;
  image?: string;
  year?: string | number;
}

interface MediaGridProps<T extends MediaGridItem> {
  items: T[];
  onPress: (item: T) => void;
  onLongPress?: (item: T) => void;
  header?: React.ReactElement | null;
  empty?: React.ReactElement | null;
  onEndReached?: () => void;
  loadingMore?: boolean;
  /** Shown under the grid, e.g. a retry row after a failed page. */
  footer?: React.ReactElement | null;
  refreshing?: boolean;
  onRefresh?: () => void;
  onScroll?: (event: any) => void;
  paddingTop?: number;
  paddingBottom?: number;
  /** For a grid under a native navigation header. */
  contentInsetAdjustmentBehavior?: 'automatic' | 'never';
}

export function mediaGridLayout() {
  const width = Dimensions.get('window').width;
  const numColumns = width >= 800 ? 5 : 3;
  const itemSize = Math.floor((width - 16 - (numColumns - 1) * 8) / numColumns);
  return { numColumns, itemSize };
}

/** The poster grid used by Discover, collections, studio pages and Trakt lists. */
export default function MediaGrid<T extends MediaGridItem>({
  items,
  onPress,
  onLongPress,
  header,
  empty,
  onEndReached,
  loadingMore,
  footer,
  refreshing,
  onRefresh,
  onScroll,
  paddingTop = 0,
  paddingBottom = 120,
  contentInsetAdjustmentBehavior,
}: MediaGridProps<T>) {
  const { settings } = useAppSettings();
  const theme = useTheme();
  const { numColumns, itemSize } = mediaGridLayout();

  const renderItem = useCallback(
    ({ item }: { item: T }) => (
      <Pressable
        onPress={() => onPress(item)}
        onLongPress={onLongPress ? () => onLongPress(item) : undefined}
        style={{ width: itemSize, margin: 4 }}
      >
        <View style={[styles.poster, { width: itemSize, height: Math.round(itemSize * 1.5), backgroundColor: theme.surface }]}>
          {item.image ? (
            <FastImage
              source={{ uri: item.image, priority: FastImage.priority.normal, cache: FastImage.cacheControl.immutable }}
              style={StyleSheet.absoluteFillObject}
              resizeMode={FastImage.resizeMode.cover}
            />
          ) : (
            <View style={styles.placeholder}>
              <Ionicons name="film-outline" size={28} color={theme.textDisabled} />
              <Text numberOfLines={3} style={[styles.placeholderTitle, { color: theme.textTertiary }]}>
                {item.title}
              </Text>
            </View>
          )}
        </View>
        {settings.showPosterTitles ? (
          <>
            <Text numberOfLines={1} style={[styles.title, { color: theme.textPrimary }]}>
              {item.title}
            </Text>
            {item.year ? <Text style={[styles.year, { color: theme.textTertiary }]}>{item.year}</Text> : null}
          </>
        ) : null}
      </Pressable>
    ),
    [itemSize, onLongPress, onPress, settings.showPosterTitles, theme]
  );

  return (
    <FlashList
      data={items}
      keyExtractor={(item: T) => item.id}
      renderItem={renderItem}
      numColumns={numColumns}
      keyboardShouldPersistTaps="handled"
      keyboardDismissMode="on-drag"
      contentInsetAdjustmentBehavior={contentInsetAdjustmentBehavior}
      contentContainerStyle={{ paddingHorizontal: 8, paddingTop, paddingBottom }}
      onEndReached={onEndReached}
      onEndReachedThreshold={0.6}
      onScroll={onScroll}
      scrollEventThrottle={16}
      refreshControl={
        onRefresh ? (
          <RefreshControl refreshing={!!refreshing} onRefresh={onRefresh} tintColor={theme.accentBright} />
        ) : undefined
      }
      ListHeaderComponent={header ?? undefined}
      ListEmptyComponent={empty ?? undefined}
      ListFooterComponent={
        loadingMore ? (
          <View style={styles.footer}>
            <ActivityIndicator color={theme.textPrimary} />
          </View>
        ) : (
          footer ?? undefined
        )
      }
    />
  );
}

const styles = StyleSheet.create({
  poster: { borderRadius: 8, overflow: 'hidden' },
  placeholder: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 8 },
  placeholderTitle: { fontSize: 11, marginTop: 6, textAlign: 'center' },
  title: { fontSize: 12, fontWeight: '600', marginTop: 6 },
  year: { fontSize: 11, marginTop: 1 },
  footer: { paddingVertical: 20, alignItems: 'center' },
});
