import React, { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { AppState, View, Text, StyleSheet, Pressable, useWindowDimensions } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import Animated, {
  type SharedValue,
  useSharedValue,
  useAnimatedScrollHandler,
  useAnimatedReaction,
  useAnimatedStyle,
  runOnJS,
  useReducedMotion,
} from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import FastImage from '@d11/react-native-fast-image';
import { isTextlessArtwork } from '../core/HomeData';
import { Pagination } from 'react-native-reanimated-carousel';
import { Ionicons } from '@expo/vector-icons';

const AUTO_ROTATE_INTERVAL_MS = 8000;
const CARD_GAP = 12;

type HeroCarouselItem = {
  id: string;
  title: string;
  image?: string;
  backdrop?: string;
  mediaType?: 'movie' | 'tv';
  logo?: string;
  genres?: string[];
  /** Set when the title is in the Plex library (hero ids are rewritten to TMDB ids). */
  plexRatingKey?: string;
  description?: string;
  year?: string;
};

function HeroCarousel({
  items,
  onSelect,
  onPlay,
  isPlayable,
  onAdd,
  inWatchlist,
  watchlistLoading,
  onActiveIndexChange,
  autoRotate = false,
}: {
  items: HeroCarouselItem[];
  onSelect: (item: HeroCarouselItem) => void;
  /** Primary button. Falls back to onSelect when not given. */
  onPlay?: (item: HeroCarouselItem) => void;
  /** Whether the primary button can start playback ("Play") or only opens Details ("Details"). */
  isPlayable?: (item: HeroCarouselItem) => boolean;
  onAdd: (item: HeroCarouselItem) => void;
  inWatchlist: boolean;
  watchlistLoading: boolean;
  onActiveIndexChange?: (index: number) => void;
  autoRotate?: boolean;
}) {
  const { width: windowWidth, height: windowHeight } = useWindowDimensions();
  const isTablet = Math.min(windowWidth, windowHeight) >= 600;
  // Netflix billboard: one inset card, 16 pt from each edge, swiping through items. The
  // textless poster fills the card; the title logo, tag line and Play / My List sit on a
  // dark gradient over its lower part.
  const cardWidth = isTablet ? Math.max(560, windowWidth - 2 * Math.round(0.1 * windowWidth)) : windowWidth - 32;
  const cardHeight = isTablet
    ? Math.round(cardWidth * 9 / 16)
    : Math.round(Math.min(cardWidth * 1.42, windowHeight * 0.64));
  const interval = cardWidth + CARD_GAP;
  const contentPadding = useMemo(() => ({ paddingHorizontal: (windowWidth - cardWidth) / 2 - CARD_GAP / 2 }), [windowWidth, cardWidth]);

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

  const reducedMotion = useReducedMotion();
  const focusedRef = useRef(true);
  const draggingRef = useRef(false);
  const lastInteractionRef = useRef(0);

  useFocusEffect(
    useCallback(() => {
      focusedRef.current = true;
      return () => {
        focusedRef.current = false;
      };
    }, [])
  );

  useEffect(() => {
    if (!autoRotate || reducedMotion || data.length < 2) return;
    const timer = setInterval(() => {
      if (!focusedRef.current || draggingRef.current || AppState.currentState !== 'active') return;
      // A swipe restarts the wait, so a card doesn't change right after the user picks it.
      if (Date.now() - lastInteractionRef.current < AUTO_ROTATE_INTERVAL_MS) return;
      let page = Math.round(scrollX.value / interval);
      if (page >= loopData.length - 1) {
        // Android doesn't report the end of a programmatic scroll, so leave the clone here.
        scrollViewRef.current?.scrollTo({ x: interval, y: 0, animated: false });
        page = 1;
      }
      scrollViewRef.current?.scrollTo({ x: (page + 1) * interval, y: 0, animated: true });
    }, AUTO_ROTATE_INTERVAL_MS);
    return () => clearInterval(timer);
  }, [autoRotate, reducedMotion, data.length, interval, loopData.length, scrollX]);

  const handleDragBegin = useCallback(() => {
    draggingRef.current = true;
  }, []);

  const handleDragEnd = useCallback(() => {
    draggingRef.current = false;
    lastInteractionRef.current = Date.now();
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
          onScrollBeginDrag={handleDragBegin}
          onScrollEndDrag={handleDragEnd}
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
              isTablet={isTablet}
              playable={isPlayable ? isPlayable(item) : true}
              onPress={() => onSelect(item)}
              onPlay={() => (onPlay ? onPlay(item) : onSelect(item))}
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
  scrollX,
  interval,
  cardWidth,
  cardHeight,
  isTablet,
  playable,
  onPress,
  onPlay,
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
  isTablet: boolean;
  playable: boolean;
  onPress: () => void;
  onPlay: () => void;
  showActions: boolean;
  onAdd: () => void;
  inWatchlist: boolean;
  watchlistLoading: boolean;
}) {
  // Phones show the textless poster, tablets the wide backdrop. The logo goes on top only
  // when the artwork has no title of its own (or there's no artwork), never twice.
  const heroImageUri = isTablet ? item.backdrop || item.image : item.image || item.backdrop;
  const showLogo = !!item.logo && (!heroImageUri || isTextlessArtwork(heroImageUri));

  // Neighbouring cards dim slightly while swiping, as before
  const cardAnimatedStyle = useAnimatedStyle(() => {
    const distance = Math.abs(scrollX.value - index * interval);
    const t = Math.min(1, distance / interval);
    return { opacity: 1 - t * 0.35, transform: [{ scale: 1 - t * 0.04 }] };
  });

  const tags = [
    item.mediaType === 'tv' ? 'Series' : item.mediaType === 'movie' ? 'Film' : null,
    ...(item.genres ?? []).slice(0, 3),
  ].filter(Boolean) as string[];
  if (tags.length < 2 && item.year) tags.push(item.year);

  return (
    <View style={{ width: cardWidth + CARD_GAP, alignItems: 'center' }}>
      <Animated.View style={[styles.card, { width: cardWidth, height: cardHeight }, cardAnimatedStyle]}>
        <Pressable
          onPress={onPress}
          accessibilityRole="button"
          accessibilityLabel={`${item.title}, details`}
          style={StyleSheet.absoluteFill}
        >
          {heroImageUri ? (
            <FastImage
              source={{ uri: heroImageUri, priority: FastImage.priority.high, cache: FastImage.cacheControl.immutable }}
              style={StyleSheet.absoluteFill}
              resizeMode={FastImage.resizeMode.cover}
            />
          ) : null}
          {/* Darkens the lower part so the logo, tags and buttons read on any artwork */}
          <LinearGradient
            colors={['rgba(0,0,0,0)', 'rgba(0,0,0,0.45)', 'rgba(0,0,0,0.88)']}
            locations={[0.5, 0.72, 1]}
            style={StyleSheet.absoluteFill}
            pointerEvents="none"
          />
        </Pressable>

        <View style={styles.overlay} pointerEvents="box-none">
          <View pointerEvents="none" style={styles.titleArea}>
            {showLogo ? (
              <FastImage
                source={{ uri: item.logo, priority: FastImage.priority.high, cache: FastImage.cacheControl.immutable }}
                style={{ width: Math.round(cardWidth * 0.7), height: isTablet ? 110 : 88 }}
                resizeMode={FastImage.resizeMode.contain}
              />
            ) : (
              heroImageUri ? null : <Text style={styles.fallbackTitle} numberOfLines={2}>{item.title}</Text>
            )}
          </View>
          {tags.length ? (
            <Text style={styles.tags} numberOfLines={1} pointerEvents="none">
              {tags.map((t, i) => (
                <Text key={t + i}>
                  {i > 0 ? <Text style={styles.tagDot}>{'  •  '}</Text> : null}
                  <Text style={i === 0 ? styles.tagStrong : undefined}>{t}</Text>
                </Text>
              ))}
            </Text>
          ) : null}
          <View style={styles.buttons}>
            <Pressable
              onPress={onPlay}
              accessibilityRole="button"
              style={({ pressed }) => [styles.primary, pressed && { opacity: 0.85 }]}
            >
              <Ionicons name={playable ? 'play' : 'information-circle-outline'} size={18} color="#000" />
              <Text style={styles.primaryText}>{playable ? 'Play' : 'Details'}</Text>
            </Pressable>
            <Pressable
              onPress={onAdd}
              disabled={!showActions || watchlistLoading}
              accessibilityRole="button"
              accessibilityLabel={inWatchlist && showActions ? 'Remove from My List' : 'Add to My List'}
              style={({ pressed }) => [styles.secondary, (pressed || watchlistLoading) && { opacity: 0.7 }]}
            >
              <Ionicons name={inWatchlist && showActions ? 'checkmark' : 'add'} size={20} color="#fff" />
              <Text style={styles.secondaryText}>My List</Text>
            </Pressable>
          </View>
        </View>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    paddingBottom: 4,
  },
  card: {
    borderRadius: 14,
    backgroundColor: '#0e0e10',
    overflow: 'hidden',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.16)',
  },
  fallbackTitle: { color: '#fff', fontSize: 30, fontWeight: '800', textAlign: 'center' },
  overlay: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    paddingHorizontal: 14,
    paddingBottom: 14,
  },
  titleArea: { alignItems: 'center', justifyContent: 'flex-end', marginBottom: 10 },
  tags: { color: 'rgba(255,255,255,0.85)', fontSize: 13, textAlign: 'center', marginBottom: 12 },
  tagStrong: { color: '#fff', fontWeight: '600' },
  tagDot: { color: 'rgba(255,255,255,0.4)' },
  buttons: { flexDirection: 'row', gap: 10 },
  primary: {
    flex: 1,
    height: 44,
    borderRadius: 10,
    backgroundColor: '#fff',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
  },
  primaryText: { color: '#000', fontSize: 16, fontWeight: '600' },
  secondary: {
    flex: 1,
    height: 44,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.18)',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
  },
  secondaryText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  paginationWrap: {
    marginTop: 12,
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
