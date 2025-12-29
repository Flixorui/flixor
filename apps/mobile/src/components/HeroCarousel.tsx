import React, { useMemo, useRef, useState, useCallback } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, Platform, Image, useWindowDimensions } from 'react-native';
import Animated, {
  type SharedValue,
  useSharedValue,
  useAnimatedScrollHandler,
  useAnimatedReaction,
  useAnimatedStyle,
  interpolate,
  Extrapolation,
  withTiming,
  runOnJS,
} from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import ConditionalBlurView from './ConditionalBlurView';
import FastImage from '@d11/react-native-fast-image';
import { Pagination } from 'react-native-reanimated-carousel';
import { Ionicons } from '@expo/vector-icons';

// Optional iOS glass effect (expo-glass-effect) with safe fallback
let GlassViewComp: any = null;
let liquidGlassAvailable = false;
if (Platform.OS === 'ios') {
  try {
    const glass = require('expo-glass-effect');
    GlassViewComp = glass.GlassView;
    liquidGlassAvailable = typeof glass.isLiquidGlassAvailable === 'function'
      ? glass.isLiquidGlassAvailable()
      : false;
  } catch {
    GlassViewComp = null;
    liquidGlassAvailable = false;
  }
}

type HeroCarouselItem = {
  id: string;
  title: string;
  image?: string;
  mediaType?: 'movie' | 'tv';
  logo?: string;
  genres?: string[];
  description?: string;
  year?: string;
};

function HeroCarousel({
  items,
  onSelect,
  onAdd,
  inWatchlist,
  watchlistLoading,
  onActiveIndexChange,
}: {
  items: HeroCarouselItem[];
  onSelect: (item: HeroCarouselItem) => void;
  onAdd: (item: HeroCarouselItem) => void;
  inWatchlist: boolean;
  watchlistLoading: boolean;
  onActiveIndexChange?: (index: number) => void;
}) {
  const { width: windowWidth, height: windowHeight } = useWindowDimensions();
  const isTablet = Math.min(windowWidth, windowHeight) >= 600;
  const baseCardWidthForHeight = Math.min(windowWidth * 0.8, 480);
  const cardWidth = isTablet ? Math.max(560, windowWidth - 2 * Math.round(0.1 * windowWidth)) : Math.min(windowWidth * 0.8, 480);
  const cardHeight = Math.round(baseCardWidthForHeight * 9 / 16) + 310;
  const interval = cardWidth + 16;
  const contentPadding = useMemo(() => ({ paddingHorizontal: (windowWidth - cardWidth) / 2 }), [windowWidth, cardWidth]);

  const data = useMemo(() => (items && items.length ? items.slice(0, 10) : []), [items]);
  const loopingEnabled = data.length > 1;
  const loopData = useMemo(() => {
    if (!loopingEnabled) return data;
    const head = data[0];
    const tail = data[data.length - 1];
    return [tail, ...data, head];
  }, [data, loopingEnabled]);

  const [activeIndex, setActiveIndex] = useState(0);
  const initialOffset = loopingEnabled ? interval : 0;
  const scrollX = useSharedValue(initialOffset);
  const paginationProgress = useSharedValue(loopingEnabled ? 0 : 0);
  const scrollViewRef = useRef<any>(null);
  const [flippedMap, setFlippedMap] = useState<Record<string, boolean>>({});
  const hasInitialized = useRef(false);

  // Reset initialization when data changes
  React.useEffect(() => {
    hasInitialized.current = false;
  }, [data]);

  // Handle ScrollView layout - set initial position
  const handleScrollViewLayout = useCallback(() => {
    if (!loopingEnabled || hasInitialized.current) return;
    hasInitialized.current = true;
    // Immediately scroll to correct position and sync scrollX
    scrollViewRef.current?.scrollTo({ x: interval, y: 0, animated: false });
    scrollX.value = interval;
  }, [loopingEnabled, interval, scrollX]);

  const toggleFlipById = useCallback((id: string) => {
    setFlippedMap((prev) => ({ ...prev, [id]: !prev[id] }));
  }, []);

  const scrollHandler = useAnimatedScrollHandler({
    onScroll: (event) => {
      scrollX.value = event.contentOffset.x;
    },
  });

  useAnimatedReaction(
    () => {
      let idx = Math.round(scrollX.value / interval);
      if (loopingEnabled) idx -= 1;
      if (idx < 0) idx = data.length - 1;
      if (idx > data.length - 1) idx = 0;
      return idx;
    },
    (idx, prevIdx) => {
      if (idx == null || idx === prevIdx) return;
      const clamped = Math.max(0, Math.min(idx, data.length - 1));
      runOnJS(setActiveIndex)(clamped);
    },
    [data.length]
  );

  useAnimatedReaction(
    () => scrollX.value / interval,
    (val) => {
      paginationProgress.value = loopingEnabled ? val - 1 : val;
    },
    [interval, loopingEnabled]
  );

  React.useEffect(() => {
    onActiveIndexChange?.(activeIndex);
  }, [activeIndex, onActiveIndexChange]);

  const handleMomentumEnd = (event: any) => {
    if (!loopingEnabled) return;
    const offsetX = event.nativeEvent.contentOffset.x;
    const rawIndex = Math.round(offsetX / interval);
    if (rawIndex === 0) {
      scrollViewRef.current?.scrollTo({ x: interval * data.length, y: 0, animated: false });
    } else if (rawIndex === loopData.length - 1) {
      scrollViewRef.current?.scrollTo({ x: interval, y: 0, animated: false });
    }
  };

  if (!data.length) return null;

  const activeItem = data[activeIndex];

  return (
    <View>
      <Animated.View style={styles.container}>
        <Animated.ScrollView
          ref={scrollViewRef}
          horizontal
          showsHorizontalScrollIndicator={false}
          snapToInterval={interval}
          decelerationRate="fast"
          onScroll={scrollHandler}
          scrollEventThrottle={16}
          disableIntervalMomentum
          pagingEnabled={false}
          bounces={false}
          overScrollMode="never"
          onMomentumScrollEnd={handleMomentumEnd}
          onLayout={handleScrollViewLayout}
          contentContainerStyle={contentPadding}
        >
          {loopData.map((item, index) => {
            const logicalIndex = loopingEnabled
              ? (index === 0 ? data.length - 1 : index === loopData.length - 1 ? 0 : index - 1)
              : index;
            return (
            <CarouselCard
              key={`${item.id}-${index}`}
              item={item}
              index={index}
              logicalIndex={logicalIndex}
              scrollX={scrollX}
              interval={interval}
              cardWidth={cardWidth}
              cardHeight={cardHeight}
              flipped={!!flippedMap[item.id]}
              onToggleFlip={() => toggleFlipById(item.id)}
              onPress={() => onSelect(item)}
              showActions={logicalIndex === activeIndex}
              onAdd={() => onAdd(item)}
              inWatchlist={inWatchlist}
              watchlistLoading={watchlistLoading}
            />
            );
          })}
        </Animated.ScrollView>
      </Animated.View>

      {data.length > 1 ? (
        <View style={styles.paginationWrap}>
          <Pagination.Basic
            data={data}
            progress={paginationProgress}
            dotStyle={styles.dot}
            activeDotStyle={styles.activeDot}
            containerStyle={styles.paginationContainer}
          />
        </View>
      ) : null}
    </View>
  );
}

function CarouselCard({
  item,
  index,
  logicalIndex,
  scrollX,
  interval,
  cardWidth,
  cardHeight,
  flipped,
  onToggleFlip,
  onPress,
  showActions,
  onAdd,
  inWatchlist,
  watchlistLoading,
}: {
  item: HeroCarouselItem;
  index: number;
  logicalIndex: number;
  scrollX: SharedValue<number>;
  interval: number;
  cardWidth: number;
  cardHeight: number;
  flipped: boolean;
  onToggleFlip: () => void;
  onPress: () => void;
  showActions: boolean;
  onAdd: () => void;
  inWatchlist: boolean;
  watchlistLoading: boolean;
}) {
  const { width: windowWidth, height: windowHeight } = useWindowDimensions();
  const isTablet = Math.min(windowWidth, windowHeight) >= 600;
  const isFlipped = useSharedValue(flipped ? 1 : 0);

  React.useEffect(() => {
    isFlipped.value = withTiming(flipped ? 1 : 0, { duration: 240 });
  }, [flipped, isFlipped]);

  const cardAnimatedStyle = useAnimatedStyle(() => {
    const distance = Math.abs(scrollX.value - index * interval);
    if (distance > interval * 1.5) {
      return {
        transform: [{ scale: isTablet ? 0.95 : 0.9 }],
        opacity: isTablet ? 0.85 : 0.7,
      };
    }
    const maxDistance = interval;
    const scale = 1 - (distance / maxDistance) * 0.1;
    const clampedScale = Math.max(isTablet ? 0.95 : 0.9, Math.min(1, scale));
    const opacity = 1 - (distance / maxDistance) * 0.3;
    const clampedOpacity = Math.max(isTablet ? 0.85 : 0.7, Math.min(1, opacity));
    return { transform: [{ scale: clampedScale }], opacity: clampedOpacity };
  });

  const overlayAnimatedStyle = useAnimatedStyle(() => {
    const distance = Math.abs(scrollX.value - index * interval);
    if (distance > interval * 1.2) {
      return { opacity: 0 };
    }
    const maxDistance = interval * 0.5;
    const progress = Math.min(distance / maxDistance, 1);
    const opacity = 1 - progress;
    const clampedOpacity = Math.max(0, Math.min(1, opacity));
    return { opacity: clampedOpacity };
  });

  const frontFlipStyle = useAnimatedStyle(() => ({
    transform: [{ rotateY: `${interpolate(isFlipped.value, [0, 1], [0, 180])}deg` }],
  }));

  const backFlipStyle = useAnimatedStyle(() => ({
    transform: [{ rotateY: `${interpolate(isFlipped.value, [0, 1], [180, 360])}deg` }],
  }));

  return (
    <View style={{ width: cardWidth + 16 }}>
      <Animated.View style={[styles.card, { width: cardWidth, height: cardHeight }, cardAnimatedStyle]}>
        <Animated.View style={[styles.flipFace, frontFlipStyle]}>
          <TouchableOpacity activeOpacity={0.9} onPress={onPress} style={StyleSheet.absoluteFillObject as any}>
            <View style={styles.bannerContainer}>
              {item.image ? (
                <FastImage
                  source={{ uri: item.image, priority: FastImage.priority.normal, cache: FastImage.cacheControl.immutable }}
                  style={styles.banner}
                  resizeMode={FastImage.resizeMode.cover}
                />
              ) : null}
              <LinearGradient
                colors={['transparent', 'rgba(0,0,0,0.2)', 'rgba(0,0,0,0.6)']}
                locations={[0.4, 0.7, 1]}
                style={styles.bannerGradient}
              />
            </View>
            {item.logo ? (
              <View style={styles.logoOverlay} pointerEvents="none">
                <FastImage
                  source={{ uri: item.logo, priority: FastImage.priority.high, cache: FastImage.cacheControl.immutable }}
                  style={[styles.logo, { width: Math.round(cardWidth * 0.72) }]}
                  resizeMode={FastImage.resizeMode.contain}
                />
              </View>
            ) : null}
            {item.genres && item.genres.length ? (
              <View style={styles.genresOverlay} pointerEvents="none">
                <Animated.Text style={[styles.genres, overlayAnimatedStyle]} numberOfLines={1}>
                  {item.genres.slice(0, 3).join(' • ')}
                </Animated.Text>
              </View>
            ) : null}
          </TouchableOpacity>
        </Animated.View>

        <Animated.View style={[styles.flipFace, styles.backFace, backFlipStyle]} pointerEvents={flipped ? 'auto' : 'none'}>
          <View style={styles.bannerContainer}>
            {item.image ? (
              <FastImage
                source={{ uri: item.image, priority: FastImage.priority.low, cache: FastImage.cacheControl.immutable }}
                style={styles.banner}
                resizeMode={FastImage.resizeMode.cover}
              />
            ) : null}
            {Platform.OS === 'ios' && GlassViewComp && liquidGlassAvailable ? (
              <GlassViewComp style={styles.banner} glassEffectStyle="regular" />
            ) : (
              <ConditionalBlurView style={styles.banner} intensity={30} tint="dark" />
            )}
          </View>
          <View style={styles.backContent}>
            {item.logo ? (
              <FastImage
                source={{ uri: item.logo, priority: FastImage.priority.normal, cache: FastImage.cacheControl.immutable }}
                style={[styles.logo, { width: Math.round(cardWidth * 0.72) }]}
                resizeMode={FastImage.resizeMode.contain}
              />
            ) : (
              <Text style={styles.backTitle} numberOfLines={1}>
                {item.title}
              </Text>
            )}
            {item.year ? (
              <View style={styles.infoRow}>
                <Ionicons name="calendar-outline" size={14} color="#9ca3af" />
                <Text style={styles.infoText}>{item.year}</Text>
              </View>
            ) : null}
            <ScrollView style={{ maxHeight: 120 }} showsVerticalScrollIndicator={false}>
              <Text style={styles.backDescription} numberOfLines={2}>
                {item.description || 'No description available'}
              </Text>
            </ScrollView>
          </View>
        </Animated.View>

        <View style={styles.topButtonsContainer} pointerEvents="box-none">
          {showActions && (
            <TouchableOpacity
              activeOpacity={0.85}
              onPress={onAdd}
              disabled={watchlistLoading}
              style={[styles.topButton, watchlistLoading && { opacity: 0.6 }]}
            >
              <Ionicons name={inWatchlist ? 'bookmark' : 'bookmark-outline'} size={18} color="#fff" />
            </TouchableOpacity>
          )}
          <TouchableOpacity activeOpacity={0.8} onPress={onToggleFlip} style={styles.topButton}>
            <Ionicons name={flipped ? 'close' : 'information-outline'} size={18} color="#fff" />
          </TouchableOpacity>
        </View>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingBottom: 8,
  },
  card: {
    borderRadius: 16,
    backgroundColor: '#111',
    overflow: 'hidden',
  },
  bannerContainer: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
  },
  banner: {
    width: '100%',
    height: '100%',
  },
  bannerGradient: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    top: 0,
  },
  logoOverlay: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    alignItems: 'center',
    justifyContent: 'flex-end',
    paddingBottom: 40,
  },
  logo: {
    height: 64,
  },
  titleOverlay: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 50,
    alignItems: 'center',
  },
  title: {
    fontSize: 18,
    fontWeight: '800',
    color: '#fff',
  },
  genresOverlay: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 20,
    alignItems: 'center',
  },
  genres: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 13,
    textAlign: 'center',
  },
  flipFace: {
    ...StyleSheet.absoluteFillObject,
    backfaceVisibility: 'hidden',
  },
  backFace: {
    transform: [{ rotateY: '180deg' }],
  },
  backContent: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'flex-end',
    padding: 16,
    paddingBottom: 22,
  },
  backTitle: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '800',
    marginBottom: 8,
    textAlign: 'center',
  },
  backDescription: {
    color: '#f3f4f6',
    fontSize: 12,
    lineHeight: 16,
    textAlign: 'center',
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    marginBottom: 8,
  },
  infoText: {
    color: '#9ca3af',
    fontSize: 12,
  },
  topButtonsContainer: {
    position: 'absolute',
    top: 10,
    right: 10,
    zIndex: 10,
    flexDirection: 'row',
    gap: 8,
  },
  topButton: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(0,0,0,0.45)',
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.18)',
  },
  paginationWrap: {
    marginTop: 8,
  },
  paginationContainer: {
    gap: 6,
  },
  dot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: 'rgba(255,255,255,0.35)',
  },
  activeDot: {
    width: 18,
    height: 6,
    borderRadius: 3,
    backgroundColor: '#fff',
  },
});

export default React.memo(HeroCarousel);
