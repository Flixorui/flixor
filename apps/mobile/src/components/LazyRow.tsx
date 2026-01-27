import React, { useState, useCallback, useRef, useEffect } from 'react';
import { View, LayoutChangeEvent, Dimensions } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import Row, { RowBadge } from './Row';
import RowSkeleton from './RowSkeleton';

const { height: SCREEN_HEIGHT } = Dimensions.get('window');

// How far outside viewport to trigger loading (prebuffer)
const VIEWPORT_BUFFER = SCREEN_HEIGHT * 0.5;

interface LazyRowProps {
  title: string;
  titleIcon?: keyof typeof Ionicons.glyphMap;
  badge?: RowBadge;
  // Either provide pre-loaded items OR a fetchData function
  items?: any[];
  fetchData?: () => Promise<any[]>;
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
  titleIcon,
  badge,
  items: preloadedItems,
  fetchData,
  getImageUri,
  getTitle,
  getSubtitle,
  authHeaders,
  onItemPress,
  onTitlePress,
  onBrowsePress,
  keyPrefix = '',
}: LazyRowProps) {
  const [fetchedData, setFetchedData] = useState<any[]>([]);
  const [loading, setLoading] = useState(!preloadedItems);
  const [hasTriggered, setHasTriggered] = useState(false);
  const [isVisible, setIsVisible] = useState(false);
  const layoutY = useRef<number | null>(null);

  // Use pre-loaded items if available, otherwise use fetched data
  const data = preloadedItems || fetchedData;

  // Track layout position and check visibility
  const onLayout = useCallback((event: LayoutChangeEvent) => {
    const { y } = event.nativeEvent.layout;
    layoutY.current = y;

    // Trigger visibility on first layout (optimistic - assume visible initially)
    if (!hasTriggered) {
      setIsVisible(true);
    }
  }, [hasTriggered]);

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
      } finally {
        setLoading(false);
      }
    })();
  }, [isVisible, hasTriggered, fetchData, preloadedItems, title]);

  // If not visible yet, show skeleton
  if (!isVisible) {
    return (
      <View onLayout={onLayout}>
        <RowSkeleton title={title} />
      </View>
    );
  }

  // If loading, show skeleton
  if (loading) {
    return (
      <View onLayout={onLayout}>
        <RowSkeleton title={title} />
      </View>
    );
  }

  // If data is empty after loading, don't render anything
  if (data.length === 0) {
    return null;
  }

  return (
    <View onLayout={onLayout}>
      <Row
        title={title}
        titleIcon={titleIcon}
        badge={badge}
        items={data}
        getImageUri={getImageUri}
        getTitle={getTitle}
        getSubtitle={getSubtitle}
        authHeaders={authHeaders}
        onItemPress={onItemPress}
        onTitlePress={onTitlePress}
        onBrowsePress={onBrowsePress}
        keyPrefix={keyPrefix}
      />
    </View>
  );
}

export default React.memo(LazyRow);
