import React, { useState, useCallback, useRef, useEffect } from 'react';
import { View, Text, Pressable, LayoutChangeEvent, Animated } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import Row, { RowBadge } from './Row';
import RowSkeleton from './RowSkeleton';
import type { HomeViewport } from './home/homeViewport';
import type { RowLayout } from '../core/SettingsData';
import { useTheme } from '../hooks/useTheme';

interface LazyRowProps {
  title: string;
  caption?: string;
  titleIcon?: keyof typeof Ionicons.glyphMap;
  badge?: RowBadge;
  // Either provide pre-loaded items OR a fetchData function
  items?: any[];
  fetchData?: () => Promise<any[]>;
  /** When set, fetchData waits until the row is near the visible part of the screen. */
  viewport?: HomeViewport;
  /** Named on a retry card when fetchData fails. Without it, a failed row just disappears. */
  errorSource?: string;
  layout?: RowLayout;
  getImageUri: (item: any) => string | undefined;
  getTitle: (item: any) => string | undefined;
  getSubtitle?: (item: any) => string | undefined;
  authHeaders?: Record<string, string>;
  onItemPress?: (item: any) => void;
  onTitlePress?: () => void;
  onBrowsePress?: () => void;
  keyPrefix?: string;
}

function LazyRow({
  title,
  caption,
  titleIcon,
  badge,
  items: preloadedItems,
  fetchData,
  viewport,
  errorSource,
  layout,
  getImageUri,
  getTitle,
  getSubtitle,
  authHeaders,
  onItemPress,
  onTitlePress,
  onBrowsePress,
  keyPrefix = '',
}: LazyRowProps) {
  const theme = useTheme();
  const [fetchedData, setFetchedData] = useState<any[]>([]);
  const [loading, setLoading] = useState(!preloadedItems);
  const [failed, setFailed] = useState(false);
  const [hasTriggered, setHasTriggered] = useState(false);
  const [isVisible, setIsVisible] = useState(false);
  // Remembers whether a skeleton was on screen, so only those rows fade in
  const showedSkeletonRef = useRef(false);
  const layoutY = useRef<number | null>(null);

  // Use pre-loaded items if available, otherwise use fetched data
  const data = preloadedItems || fetchedData;

  const checkViewport = useCallback(() => {
    if (viewport && layoutY.current !== null && viewport.isNear(layoutY.current)) {
      setIsVisible(true);
    }
  }, [viewport]);

  // Track layout position and check visibility
  const onLayout = useCallback((event: LayoutChangeEvent) => {
    layoutY.current = event.nativeEvent.layout.y;
    if (viewport) {
      checkViewport();
    } else if (!hasTriggered) {
      // Trigger visibility on first layout (optimistic - assume visible initially)
      setIsVisible(true);
    }
  }, [hasTriggered, viewport, checkViewport]);

  useEffect(() => {
    if (!viewport || isVisible) return;
    return viewport.subscribe(checkViewport);
  }, [viewport, isVisible, checkViewport]);

  // Load data when visible (only if fetchData is provided and items aren't pre-loaded)
  useEffect(() => {
    if (!isVisible || hasTriggered) return;
    if (preloadedItems) {
      // Data is pre-loaded, just mark as triggered
      setHasTriggered(true);
      setLoading(false);
      return;
    }
    if (!fetchData) {
      setHasTriggered(true);
      setLoading(false);
      return;
    }

    setHasTriggered(true);

    (async () => {
      try {
        const items = await fetchData();
        setFetchedData(items);
      } catch (error) {
        console.log(`[LazyRow] Failed to load ${title}:`, error);
        setFetchedData([]);
        setFailed(true);
      } finally {
        setLoading(false);
      }
    })();
  }, [isVisible, hasTriggered, fetchData, preloadedItems, title]);

  const retry = useCallback(() => {
    setFailed(false);
    setLoading(true);
    setHasTriggered(false);
  }, []);

  // If not visible yet or still loading, show skeleton
  if (!isVisible || loading) {
    showedSkeletonRef.current = true;
    return (
      <View onLayout={onLayout}>
        <RowSkeleton title={title} layout={layout} />
      </View>
    );
  }

  if (failed && errorSource) {
    return (
      <View onLayout={onLayout} style={{ marginHorizontal: 16, marginVertical: 12, padding: 14, borderRadius: 12, backgroundColor: theme.surfaceOverlay, flexDirection: 'row', alignItems: 'center' }}>
        <Ionicons name="alert-circle-outline" size={20} color={theme.textSecondary} />
        <View style={{ flex: 1, marginHorizontal: 10 }}>
          <Text style={{ color: theme.textPrimary, fontSize: 14, fontWeight: '600' }} numberOfLines={1}>{title}</Text>
          <Text style={{ color: theme.textSecondary, fontSize: 12, marginTop: 2 }} numberOfLines={1}>
            Couldn't load from {errorSource}
          </Text>
        </View>
        <Pressable onPress={retry} hitSlop={8}>
          <Text style={{ color: theme.textPrimary, fontSize: 14, fontWeight: '600' }}>Retry</Text>
        </Pressable>
      </View>
    );
  }

  // If data is empty after loading, don't render anything
  if (data.length === 0) {
    return null;
  }

  return (
    <FadeIn enabled={showedSkeletonRef.current} onLayout={onLayout}>
      <Row
        title={title}
        caption={caption}
        titleIcon={titleIcon}
        badge={badge}
        items={data}
        layout={layout}
        getImageUri={getImageUri}
        getTitle={getTitle}
        getSubtitle={getSubtitle}
        authHeaders={authHeaders}
        onItemPress={onItemPress}
        onTitlePress={onTitlePress}
        onBrowsePress={onBrowsePress}
        keyPrefix={keyPrefix}
      />
    </FadeIn>
  );
}

/** Content that replaced a skeleton fades in once (250 ms) instead of popping in. */
function FadeIn({ enabled, onLayout, children }: { enabled: boolean; onLayout?: (e: any) => void; children: React.ReactNode }) {
  const opacity = useRef(new Animated.Value(enabled ? 0 : 1)).current;
  useEffect(() => {
    if (enabled) Animated.timing(opacity, { toValue: 1, duration: 250, useNativeDriver: true }).start();
  }, [enabled, opacity]);
  return <Animated.View onLayout={onLayout} style={{ opacity }}>{children}</Animated.View>;
}

export default React.memo(LazyRow);
