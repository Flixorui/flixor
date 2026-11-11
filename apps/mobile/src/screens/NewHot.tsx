/**
 * New & Hot, matched to the Netflix iOS app (measured frame by frame; spec in the notes
 * folder, new-hot-netflix-spec.md):
 * - One list in four sections (Coming Soon, Everyone's Watching, Top 10 Shows, Top 10
 *   Movies) with no headings between them. The pill row follows the scroll, centring the
 *   selected pill; tapping a pill jumps to its section.
 * - Frosted header: the title row hides on a scroll down (pills rise into its place, 430 ms)
 *   and returns on a deliberate scroll up (200 ms).
 * - Bordered cards; one is active at a time (the one crossing 40% of the screen). The others
 *   dim to 45%. With trailers on (Settings > Trailers) the active card plays its
 *   trailer, muted.
 * - Coming Soon cards have no buttons (no "Remind Me" in Flixor).
 */

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Animated, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions, type LayoutChangeEvent,
} from 'react-native';
import { useFocusEffect, useIsFocused, useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { LinearGradient } from 'expo-linear-gradient';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import Svg, { Defs, LinearGradient as SvgGradient, Stop, Text as SvgText } from 'react-native-svg';
import * as Haptics from 'expo-haptics';
import { TopBarStore } from '../components/TopBarStore';
import { useScrollLinkedHeader } from '../components/useScrollLinkedHeader';
import HeaderGlass, { HEADER_GLASS_MIN_OPACITY } from '../components/HeaderGlass';
import DetailsHeroTrailer from '../components/details/DetailsHeroTrailer';
import { useFlixor } from '../core/FlixorContext';
import { useAppMode } from '../core/AppMode';
import { useAppSettings } from '../hooks/useAppSettings';
import { checkWatchlistStatus, toggleWatchlist } from '../core/DetailsData';
import {
  SECTIONS, cachedFeed, fetchCardDetails, getCardDetails, loadNewHotFeed,
  type CardDetails, type FeedItem, type NewHotSection,
} from '../core/NewHotFeed';

const TITLE_ROW = 52;
const PILL_ROW = 48;
const CARD_INSET = 13;
const CARD_GAP = 12;
const RANK_RISE = 40; // how far a Top 10 number rises above its card
const RANK_STRIP = 17; // the strip above a Top 10 card's video
const ACTIVE_LINE = 0.4; // the card crossing this share of the screen is active

// ---------------------------------------------------------------- pills

function Top10Badge() {
  return (
    <View style={styles.top10Badge}>
      <Text style={styles.top10BadgeTop}>TOP</Text>
      <Text style={styles.top10BadgeNum}>10</Text>
    </View>
  );
}

function PillIcon({ section }: { section: NewHotSection }) {
  if (section === 'coming') return <Text style={styles.pillEmoji}>🍿</Text>;
  if (section === 'watching') return <Text style={styles.pillEmoji}>🔥</Text>;
  return <Top10Badge />;
}

function Pill({ section, label, selected, onPress, onLayout }: {
  section: NewHotSection; label: string; selected: boolean; onPress: () => void; onLayout: (e: LayoutChangeEvent) => void;
}) {
  // Cross-fade between outlined and filled (~130 ms)
  const fill = useRef(new Animated.Value(selected ? 1 : 0)).current;
  useEffect(() => {
    Animated.timing(fill, { toValue: selected ? 1 : 0, duration: 130, useNativeDriver: true }).start();
  }, [selected, fill]);
  return (
    <Pressable onPress={onPress} onLayout={onLayout} accessibilityRole="tab" accessibilityState={{ selected }} style={styles.pill}>
      {/* The outline shows only on unselected pills */}
      <Animated.View style={[StyleSheet.absoluteFill, styles.pillOutline, { opacity: fill.interpolate({ inputRange: [0, 1], outputRange: [1, 0] }) }]} />
      <Animated.View style={[StyleSheet.absoluteFill, styles.pillFill, { opacity: fill }]} />
      <PillIcon section={section} />
      <Text style={styles.pillText}>{label}</Text>
    </Pressable>
  );
}

// ---------------------------------------------------------------- rank number

function RankNumber({ rank }: { rank: number }) {
  const text = String(rank).padStart(2, '0');
  const h = TOP10_NUMBER_H;
  return (
    <Svg width={130} height={h} style={styles.rankNumber} pointerEvents="none">
      <Defs>
        <SvgGradient id="rankFill" x1="0" y1="0" x2="0" y2="1">
          <Stop offset="0" stopColor="#4a4a4a" stopOpacity="0.95" />
          <Stop offset="1" stopColor="#0a0a0a" stopOpacity="0.95" />
        </SvgGradient>
      </Defs>
      <SvgText
        x={2}
        y={h - 3}
        fontSize={66}
        fontWeight="800"
        letterSpacing={-3}
        fill="url(#rankFill)"
        stroke="#fff"
        strokeWidth={2.2}
        strokeLinejoin="round"
      >
        {text}
      </SvgText>
    </Svg>
  );
}
const TOP10_NUMBER_H = RANK_RISE + RANK_STRIP;

// ---------------------------------------------------------------- card

function CardLogo({ uri, title }: { uri?: string; title: string }) {
  const [aspect, setAspect] = useState<number | null>(null);
  if (!uri) return <Text style={styles.cardTitle} numberOfLines={2}>{title}</Text>;
  const h = 46;
  return (
    <FastImage
      source={{ uri, priority: FastImage.priority.normal, cache: FastImage.cacheControl.immutable }}
      onLoad={(e) => setAspect(e.nativeEvent.width / Math.max(1, e.nativeEvent.height))}
      // Left-aligned at its own aspect ratio, capped to 60% of the card
      style={{ height: h, width: aspect ? Math.min(h * aspect, 230) : 160, maxWidth: '62%' }}
      resizeMode={FastImage.resizeMode.contain}
    />
  );
}

const NewHotCard = React.memo(function NewHotCard({
  item, active, preload, focused, width, trailersOn, muted, onToggleMute, onPress, onLayout,
}: {
  item: FeedItem;
  active: boolean;
  /** The next card: its trailer loads paused, so it starts at once when the card becomes active. */
  preload: boolean;
  /** The page is on screen. Off screen, trailers only warm up (hidden, then paused). */
  focused: boolean;
  width: number;
  trailersOn: boolean;
  muted: boolean;
  onToggleMute: () => void;
  onPress: (item: FeedItem) => void;
  onLayout: (key: string, e: LayoutChangeEvent) => void;
}) {
  const [info, setInfo] = useState<CardDetails | undefined>(() => getCardDetails(item));
  const [inList, setInList] = useState(false);
  const [listBusy, setListBusy] = useState(false);
  const [playing, setPlaying] = useState(false);

  useEffect(() => {
    if (!info) fetchCardDetails(item).then(setInfo);
  }, [item, info]);

  useEffect(() => {
    if (!active) setPlaying(false);
  }, [active]);

  useEffect(() => {
    if (!active || item.section === 'coming') return;
    let live = true;
    checkWatchlistStatus({ tmdbId: item.tmdbId, mediaType: item.mediaType }).then((v) => live && setInList(v)).catch(() => {});
    return () => {
      live = false;
    };
  }, [active, item]);

  const toggleList = async () => {
    if (listBusy) return;
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setListBusy(true);
    try {
      const result = await toggleWatchlist({ tmdbId: item.tmdbId, mediaType: item.mediaType }, 'both');
      if (result.success) setInList(result.inWatchlist);
    } finally {
      setListBusy(false);
    }
  };

  const cardWidth = width - CARD_INSET * 2;
  const videoH = Math.round((cardWidth * 9) / 16);
  const backdrop = info?.backdrop ?? item.backdrop;
  const ranked = item.rank !== undefined;
  // Mounted for the active card and, paused, for the next one
  const showTrailer = trailersOn && (active || preload) && !!info?.trailerKey;

  return (
    <View onLayout={(e) => onLayout(item.key, e)} style={[styles.cardWrap, ranked && { paddingTop: RANK_RISE }]}>
      <View>
        <Pressable onPress={() => onPress(item)} style={styles.card} accessibilityRole="button" accessibilityLabel={item.title}>
          {ranked ? (
            <LinearGradient
              colors={['rgba(255,255,255,0.16)', 'rgba(255,255,255,0.05)', 'rgba(255,255,255,0)']}
              locations={[0, 0.55, 0.85]}
              start={{ x: 0, y: 0.5 }}
              end={{ x: 1, y: 0.5 }}
              style={{ height: RANK_STRIP }}
            />
          ) : null}
          <View style={{ width: cardWidth - 2, height: videoH, backgroundColor: '#111' }}>
            {backdrop ? (
              <FastImage
                source={{ uri: backdrop, priority: FastImage.priority.normal, cache: FastImage.cacheControl.immutable }}
                style={StyleSheet.absoluteFill}
                resizeMode={FastImage.resizeMode.cover}
              />
            ) : null}
            {showTrailer ? (
              <DetailsHeroTrailer
                videoKey={info!.trailerKey!}
                width={cardWidth - 2}
                height={videoH}
                muted={muted}
                // Plays only on screen. The next card plays hidden ahead of time (past YouTube's
                // start overlay), so it shows at once when it becomes active
                active={focused && (active || preload)}
                visible={focused && active}
                onPlayingChange={setPlaying}
                onFinished={() => setPlaying(false)}
              />
            ) : null}
            {info?.rating ? (
              <View style={styles.ratingBadge}>
                <Text style={styles.ratingText}>{info.rating}</Text>
              </View>
            ) : null}
            {showTrailer && playing ? (
              <Pressable onPress={onToggleMute} hitSlop={10} style={styles.muteButton} accessibilityLabel={muted ? 'Unmute' : 'Mute'}>
                <Ionicons name={muted ? 'volume-mute' : 'volume-high'} size={16} color="#fff" />
              </Pressable>
            ) : null}
          </View>

          <View style={styles.cardBody}>
            <CardLogo uri={info?.logo} title={item.title} />
            {info?.meta ? <Text style={styles.meta}>{info.meta}</Text> : null}
            {info?.overview ?? item.overview ? (
              <Text style={styles.overview} numberOfLines={3}>{info?.overview ?? item.overview}</Text>
            ) : null}
            {item.section !== 'coming' ? (
              <View style={styles.buttons}>
                <Pressable onPress={() => onPress(item)} style={({ pressed }) => [styles.primaryBtn, pressed && { opacity: 0.85 }]}>
                  <Ionicons name="play" size={16} color="#000" />
                  <Text style={styles.primaryText}>Play</Text>
                </Pressable>
                <Pressable onPress={toggleList} style={({ pressed }) => [styles.secondaryBtn, (pressed || listBusy) && { opacity: 0.7 }]}>
                  <Ionicons name={inList ? 'checkmark' : 'add'} size={20} color="#fff" />
                  <Text style={styles.secondaryText}>My List</Text>
                </Pressable>
              </View>
            ) : null}
          </View>
        </Pressable>
        {ranked ? <RankNumber rank={item.rank!} /> : null}
      </View>
    </View>
  );
});

// ---------------------------------------------------------------- skeleton

function Skeleton({ width, top }: { width: number; top: number }) {
  const cardW = width - CARD_INSET * 2;
  return (
    <View style={{ paddingTop: top }}>
      {[0, 1].map((i) => (
        <View key={i} style={[styles.cardWrap]}>
          <View style={[styles.card, { borderColor: '#1c1c1c' }]}>
            <View style={{ width: cardW - 2, height: (cardW * 9) / 16, backgroundColor: '#161616' }} />
            <View style={styles.cardBody}>
              <View style={{ width: 150, height: 34, borderRadius: 6, backgroundColor: '#161616' }} />
              <View style={{ width: '70%', height: 14, borderRadius: 4, backgroundColor: '#161616', marginTop: 12 }} />
              <View style={{ width: '90%', height: 12, borderRadius: 4, backgroundColor: '#121212', marginTop: 10 }} />
            </View>
          </View>
        </View>
      ))}
    </View>
  );
}

// ---------------------------------------------------------------- screen

export default function NewHot() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { width, height } = useWindowDimensions();
  const { isConnected } = useFlixor();
  const { isStremioOnly } = useAppMode();
  const { settings } = useAppSettings();
  const ready = isConnected || isStremioOnly;
  const isFocused = useIsFocused();

  const [items, setItems] = useState<FeedItem[] | null>(() => cachedFeed());
  const [activeKey, setActiveKey] = useState<string | null>(null);
  const [selected, setSelected] = useState<NewHotSection>('coming');
  const [muted, setMuted] = useState(true);
  const contentFade = useRef(new Animated.Value(items ? 1 : 0)).current;

  const scrollY = useRef(new Animated.Value(0)).current;
  const scrollRef = useRef<ScrollView>(null);
  const pillScroll = useRef<ScrollView>(null);
  const pillLayout = useRef<Record<string, { x: number; w: number }>>({});
  const cardLayout = useRef(new Map<string, { y: number; h: number }>());
  const offset = useRef(0);
  const jumpLock = useRef(0);

  const headerH = insets.top + TITLE_ROW + PILL_ROW;
  const contentTop = headerH + 8;
  // The header follows the scroll, then eases the rest of the way (shown or hidden) when
  // scrolling stops, so it never rests half out
  const { value: collapse, onScrollY, show } = useScrollLinkedHeader(TITLE_ROW);

  useFocusEffect(
    useCallback(() => {
      // This page draws its own header
      TopBarStore.setVisible(false);
      TopBarStore.setTabBarVisible(true);
    }, [])
  );

  useEffect(() => {
    if (!ready) return;
    let live = true;
    loadNewHotFeed().then((feed) => {
      if (!live) return;
      setItems(feed);
      Animated.timing(contentFade, { toValue: 1, duration: 400, useNativeDriver: true }).start();
    });
    return () => {
      live = false;
    };
  }, [ready, contentFade]);

  const firstOf = useMemo(() => {
    const map: Partial<Record<NewHotSection, string>> = {};
    for (const it of items ?? []) if (!map[it.section]) map[it.section] = it.key;
    return map;
  }, [items]);
  const sectionOf = useMemo(() => new Map((items ?? []).map((it) => [it.key, it.section])), [items]);
  const order = useMemo(() => (items ?? []).map((it) => it.key), [items]);
  // The card after the active one; its trailer preloads
  const nextKey = activeKey ? order[order.indexOf(activeKey) + 1] ?? null : null;

  // The active card is the one crossing ACTIVE_LINE of the screen
  const updateActive = useCallback(() => {
    const probe = offset.current + height * ACTIVE_LINE;
    let found: string | null = null;
    for (const key of order) {
      const l = cardLayout.current.get(key);
      if (!l) continue;
      if (probe >= l.y && probe < l.y + l.h + CARD_GAP) {
        found = key;
        break;
      }
    }
    if (!found && order.length) found = order[0];
    if (found) {
      setActiveKey((k) => (k === found ? k : found));
      const section = sectionOf.get(found);
      if (section && Date.now() > jumpLock.current) setSelected((s) => (s === section ? s : section));
    }
  }, [height, order, sectionOf]);

  useEffect(() => {
    updateActive();
  }, [items, updateActive]);

  // Keep the selected pill centred (~150 ms)
  useEffect(() => {
    const l = pillLayout.current[selected];
    if (!l) return;
    pillScroll.current?.scrollTo({ x: Math.max(0, l.x + l.w / 2 - width / 2), animated: true });
  }, [selected, width]);

  const onCardLayout = useCallback((key: string, e: LayoutChangeEvent) => {
    const { y, height: h } = e.nativeEvent.layout;
    cardLayout.current.set(key, { y, h });
  }, []);

  const jumpTo = (section: NewHotSection) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    const key = firstOf[section];
    const l = key ? cardLayout.current.get(key) : undefined;
    if (!l) return;
    // The pills say where you're going straight away; the cards fly past underneath
    jumpLock.current = Date.now() + 700;
    setSelected(section);
    show();
    scrollRef.current?.scrollTo({ y: Math.max(0, l.y - contentTop), animated: true });
  };

  const openDetails = useCallback(
    (item: FeedItem) => nav.navigate('Details', { type: 'tmdb', id: String(item.tmdbId), mediaType: item.mediaType }),
    [nav]
  );
  const toggleMute = useCallback(() => setMuted((m) => !m), []);

  const headerShift = collapse.interpolate({ inputRange: [0, TITLE_ROW], outputRange: [0, -TITLE_ROW] });
  const titleOpacity = collapse.interpolate({ inputRange: [0, TITLE_ROW * 0.7], outputRange: [1, 0], extrapolate: 'clamp' });

  return (
    <View style={styles.screen}>
      {!items ? (
        <Skeleton width={width} top={contentTop} />
      ) : (
        <Animated.ScrollView
          ref={scrollRef as any}
          style={{ flex: 1, opacity: contentFade }}
          contentContainerStyle={{ paddingTop: contentTop, paddingBottom: 120 + insets.bottom }}
          scrollEventThrottle={16}
          onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], {
            useNativeDriver: true,
            listener: (e: any) => {
              offset.current = e.nativeEvent.contentOffset.y;
              onScrollY(offset.current);
              updateActive();
            },
          })}
        >
          {items.map((item) => (
            <NewHotCard
              key={item.key}
              item={item}
              active={item.key === activeKey}
              preload={item.key === nextKey}
              focused={isFocused}
              width={width}
              trailersOn={settings.detailsHeroInlineTrailerEnabled}
              muted={muted}
              onToggleMute={toggleMute}
              onPress={openDetails}
              onLayout={onCardLayout}
            />
          ))}
        </Animated.ScrollView>
      )}

      {/* Frosted header: title row, then the pills. The band shrinks to the pills on scroll. */}
      <Animated.View style={[styles.header, { height: headerH, transform: [{ translateY: headerShift }] }]} pointerEvents="box-none">
        {/* Reaches one title row above the header, so the status bar stays covered as it slides up */}
        {/* Glass only once content is under it, like the other screens (never fully 0 alpha) */}
        <Animated.View
          pointerEvents="none"
          style={[
            styles.band,
            {
              top: -TITLE_ROW,
              height: headerH + TITLE_ROW,
              opacity: scrollY.interpolate({ inputRange: [0, 8, 60], outputRange: [HEADER_GLASS_MIN_OPACITY, HEADER_GLASS_MIN_OPACITY, 1], extrapolate: 'clamp' }),
            },
          ]}
        >
          <HeaderGlass />
        </Animated.View>
        <Animated.View style={[styles.titleRow, { marginTop: insets.top, opacity: titleOpacity }]} pointerEvents="none">
          <Text style={styles.title}>New & Hot</Text>
        </Animated.View>
        <View style={styles.pillRow}>
          <ScrollView
            ref={pillScroll}
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.pillRowContent}
          >
            {SECTIONS.filter((s) => firstOf[s.id] || !items).map((s) => (
              <Pill
                key={s.id}
                section={s.id}
                label={s.label}
                selected={selected === s.id}
                onPress={() => jumpTo(s.id)}
                onLayout={(e) => {
                  pillLayout.current[s.id] = { x: e.nativeEvent.layout.x, w: e.nativeEvent.layout.width };
                }}
              />
            ))}
          </ScrollView>
        </View>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#000' },
  header: { position: 'absolute', top: 0, left: 0, right: 0 },
  band: { position: 'absolute', top: 0, left: 0, right: 0, overflow: 'hidden' },
  titleRow: { height: TITLE_ROW, alignItems: 'center', justifyContent: 'center' },
  title: { color: '#fff', fontSize: 20, fontWeight: '700' },
  pillRow: { height: PILL_ROW, justifyContent: 'center' },
  pillRowContent: { paddingHorizontal: 11, gap: 8, alignItems: 'center' },
  pill: { height: 33, borderRadius: 9, paddingHorizontal: 12, flexDirection: 'row', alignItems: 'center', gap: 8 },
  pillOutline: { borderRadius: 9, borderWidth: 1, borderColor: 'rgba(255,255,255,0.32)' },
  pillFill: { borderRadius: 9, backgroundColor: 'rgba(255,255,255,0.28)' },
  pillText: { color: '#fff', fontSize: 15, fontWeight: '600' },
  pillEmoji: { fontSize: 16 },
  top10Badge: { width: 18, height: 18, borderRadius: 3, backgroundColor: '#E50914', alignItems: 'center', justifyContent: 'center' },
  top10BadgeTop: { color: '#fff', fontSize: 5.5, fontWeight: '900', lineHeight: 6, letterSpacing: 0.2 },
  top10BadgeNum: { color: '#fff', fontSize: 10, fontWeight: '900', lineHeight: 10, marginTop: -0.5 },
  cardWrap: { paddingHorizontal: CARD_INSET, marginBottom: CARD_GAP },
  card: {
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#2D2D2D',
    backgroundColor: '#000',
    overflow: 'hidden',
  },
  // Rises RANK_RISE above the card and sits on the strip above the video
  rankNumber: { position: 'absolute', left: 11, top: -RANK_RISE },
  ratingBadge: {
    position: 'absolute',
    top: 10,
    right: 10,
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 3,
    backgroundColor: 'rgba(0,0,0,0.7)',
  },
  ratingText: { color: '#fff', fontSize: 12, fontWeight: '700', letterSpacing: 0.3 },
  muteButton: {
    position: 'absolute',
    right: 10,
    bottom: 10,
    width: 30,
    height: 30,
    borderRadius: 15,
    backgroundColor: 'rgba(0,0,0,0.6)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  cardBody: { paddingHorizontal: 16, paddingTop: 14, paddingBottom: 16 },
  cardTitle: { color: '#fff', fontSize: 24, fontWeight: '800' },
  meta: { color: '#fff', fontSize: 15, marginTop: 10 },
  overview: { color: '#A9A9A9', fontSize: 15, lineHeight: 20, marginTop: 6 },
  buttons: { flexDirection: 'row', gap: 10, marginTop: 14 },
  primaryBtn: {
    height: 34,
    paddingHorizontal: 18,
    borderRadius: 17,
    backgroundColor: '#fff',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  primaryText: { color: '#000', fontSize: 15, fontWeight: '700' },
  secondaryBtn: {
    height: 34,
    paddingHorizontal: 16,
    borderRadius: 17,
    backgroundColor: 'rgba(255,255,255,0.16)',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  secondaryText: { color: '#fff', fontSize: 15, fontWeight: '600' },
});
