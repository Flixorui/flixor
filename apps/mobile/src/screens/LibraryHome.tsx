/**
 * Shows / Movies page, Netflix style: a back button and centred title, a Categories pill
 * that narrows the page to a genre (it turns white with the genre's name), a billboard from
 * the library on a background tinted from it, then rows. The full poster grid stays one tap
 * away through the grid button.
 */

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Animated, Pressable, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect, useNavigation, useRoute } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { TopBarStore } from '../components/TopBarStore';
import ConditionalBlurView from '../components/ConditionalBlurView';
import GlassMenu, { type GlassMenuItem } from '../components/GlassMenu';
import HeroCarousel from '../components/HeroCarousel';
import AmbientTint from '../components/home/AmbientTint';
import Top10Row from '../components/home/Top10Row';
import Row from '../components/Row';
import RowSkeleton from '../components/RowSkeleton';
import { useAppSettings } from '../hooks/useAppSettings';
import { getUltraBlurColors, type HeroItem } from '../core/HomeData';
import { checkWatchlistStatus, toggleWatchlist, type WatchlistIds } from '../core/DetailsData';
import { fetchLibraryHome, type LibraryHomeData, type LibraryHomeType, type LibraryRowItem } from '../core/LibraryHomeData';

type Params = { type: LibraryHomeType; genre?: string; libraryKey?: string };

const HEADER_H = 48;

function tmdbIds(item: { id?: string; mediaType?: 'movie' | 'tv' }): WatchlistIds | null {
  if (!item.id?.startsWith('tmdb:') || !item.mediaType) return null;
  const tmdbId = parseInt(item.id.split(':')[2], 10);
  return Number.isNaN(tmdbId) ? null : { tmdbId, mediaType: item.mediaType };
}

export default function LibraryHome() {
  const nav: any = useNavigation();
  const route = useRoute();
  const params = (route.params ?? { type: 'movie' }) as Params;
  const { type, genre, libraryKey } = params;
  const insets = useSafeAreaInsets();
  const { settings } = useAppSettings();
  const noun = type === 'movie' ? 'Movies' : 'Shows';

  const [data, setData] = useState<LibraryHomeData | null>(null);
  const [loading, setLoading] = useState(true);
  const loadId = useRef(0);

  const scrollY = useRef(new Animated.Value(0)).current;
  const headerBg = scrollY.interpolate({ inputRange: [0, 40], outputRange: [0, 1], extrapolate: 'clamp' });

  const [heroIndex, setHeroIndex] = useState(0);
  const [tint, setTint] = useState('2b3a3f');
  const tintCache = useRef(new Map<string, string>());
  const [inWatchlist, setInWatchlist] = useState(false);
  const [watchlistLoading, setWatchlistLoading] = useState(false);

  useFocusEffect(
    useCallback(() => {
      TopBarStore.setVisible(false);
      TopBarStore.setTabBarVisible(true);
    }, [])
  );

  useEffect(() => {
    const id = ++loadId.current;
    setLoading(true);
    setHeroIndex(0);
    fetchLibraryHome(type, { genre, libraryKey })
      .then((result) => {
        if (id === loadId.current) setData(result);
      })
      .catch((e) => {
        console.log('[LibraryHome] load failed', e);
        if (id === loadId.current) setData(null);
      })
      .finally(() => {
        if (id === loadId.current) setLoading(false);
      });
  }, [type, genre, libraryKey]);

  const hero = data?.hero ?? [];
  const activeHero: HeroItem | undefined = hero[heroIndex] ?? hero[0];

  // Background colour follows the billboard
  useEffect(() => {
    const image = activeHero?.image;
    if (!image) return;
    const cached = tintCache.current.get(image);
    if (cached) {
      setTint(cached);
      return;
    }
    let cancelled = false;
    getUltraBlurColors(image).then((colors) => {
      const color = colors?.topLeft || colors?.topRight;
      if (!color) return;
      tintCache.current.set(image, color);
      if (!cancelled) setTint(color);
    });
    return () => {
      cancelled = true;
    };
  }, [activeHero?.image]);

  useEffect(() => {
    const ids = activeHero ? tmdbIds(activeHero) : null;
    if (!ids) {
      setInWatchlist(false);
      return;
    }
    let active = true;
    checkWatchlistStatus(ids).then((v) => active && setInWatchlist(v)).catch(() => {});
    return () => {
      active = false;
    };
  }, [activeHero?.id]);

  const openDetails = useCallback(
    (item: { id?: string; mediaType?: 'movie' | 'tv'; plexRatingKey?: string }) => {
      const ids = tmdbIds(item);
      if (ids) nav.navigate('Details', { type: 'tmdb', id: String(ids.tmdbId), mediaType: ids.mediaType });
      else if (item.plexRatingKey) nav.navigate('Details', { type: 'plex', ratingKey: item.plexRatingKey });
      else if (item.id?.startsWith('plex:')) nav.navigate('Details', { type: 'plex', ratingKey: item.id.slice(5) });
    },
    [nav]
  );

  const openRowItem = useCallback(
    (item: LibraryRowItem) => nav.navigate('Details', { type: 'plex', ratingKey: item.ratingKey }),
    [nav]
  );

  const openGrid = useCallback(() => {
    nav.navigate('Library', {
      tab: type === 'movie' ? 'movies' : 'tv',
      libraryKey: data?.library.key,
      libraryTitle: data?.library.title,
      ...(genre && data?.genreKey ? { genre, genreKey: data.genreKey } : {}),
    });
  }, [nav, type, data, genre]);

  // Categories menu: "All …" to clear a genre, the other libraries, then this library's genres
  const menuItems = useMemo<GlassMenuItem[]>(() => {
    const items: GlassMenuItem[] = [];
    if (genre) items.push({ title: `All ${noun}`, icon: 'grid-outline', onPress: () => nav.setParams({ genre: undefined }) });
    if (data && data.libraries.length > 1) {
      items.push({
        title: 'Libraries',
        icon: 'albums-outline',
        children: data.libraries.map((l) => ({
          title: l.title,
          checked: l.key === data.library.key,
          onPress: () => nav.setParams({ libraryKey: l.key, genre: undefined }),
        })),
      });
    }
    for (const g of data?.genres ?? []) {
      items.push({ title: g.title, checked: g.title === genre, onPress: () => nav.setParams({ genre: g.title }) });
    }
    return items;
  }, [data, genre, noun, nav]);

  const title = libraryKey && data ? data.library.title : noun;

  return (
    <View style={{ flex: 1, backgroundColor: '#0e0e10' }}>
      <AmbientTint color={tint} />

      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: insets.top + HEADER_H, paddingBottom: 110 + insets.bottom }}
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
      >
        <View style={styles.pillRow}>
          <GlassMenu items={menuItems} accessibilityLabel={genre ? `${genre}, change category` : 'Categories'}>
            <View style={[styles.pill, genre ? styles.pillActive : null]}>
              {genre ? null : (
                <View pointerEvents="none" style={StyleSheet.absoluteFillObject}>
                  <ConditionalBlurView intensity={30} tint="dark" style={StyleSheet.absoluteFillObject} />
                  <View style={[StyleSheet.absoluteFillObject, styles.pillGlass]} />
                </View>
              )}
              <Text style={[styles.pillText, genre ? { color: '#000' } : null]}>{genre ?? 'Categories'}</Text>
              <Ionicons name="chevron-down" size={14} color={genre ? '#000' : '#fff'} style={{ marginLeft: 5 }} />
            </View>
          </GlassMenu>
        </View>

        {loading && !data ? (
          <View>
            <View style={styles.cardPlaceholder} />
            <RowSkeleton />
            <RowSkeleton />
          </View>
        ) : null}

        {!loading && (!data || (hero.length === 0 && data.rows.length === 0)) ? (
          <View style={styles.empty}>
            <Text style={styles.emptyTitle}>{genre ? `No ${genre} ${noun.toLowerCase()} here yet` : `No ${noun.toLowerCase()} yet`}</Text>
            <Text style={styles.emptyText}>{genre ? 'Try another category.' : 'Add a library in Plex to see it here.'}</Text>
          </View>
        ) : null}

        {data && hero.length > 0 ? (
          <View style={{ opacity: loading ? 0.5 : 1 }}>
            <HeroCarousel
              items={hero}
              onSelect={openDetails}
              isPlayable={(item) => !!item.plexRatingKey && item.mediaType === 'movie'}
              onPlay={(item) => {
                if (item.plexRatingKey && item.mediaType === 'movie') {
                  nav.navigate('Player', { type: 'plex', ratingKey: item.plexRatingKey });
                } else {
                  openDetails(item);
                }
              }}
              onAdd={async (item) => {
                const ids = tmdbIds(item);
                if (!ids || watchlistLoading) return;
                setWatchlistLoading(true);
                try {
                  const result = await toggleWatchlist(ids, 'both');
                  if (result.success) setInWatchlist(result.inWatchlist);
                } finally {
                  setWatchlistLoading(false);
                }
              }}
              inWatchlist={inWatchlist}
              watchlistLoading={watchlistLoading}
              onActiveIndexChange={setHeroIndex}
              autoRotate={settings.heroAutoRotate}
            />
          </View>
        ) : null}

        {data && !genre && !libraryKey ? (
          <Top10Row
            kind={type === 'movie' ? 'movie' : 'tv'}
            onItemPress={(item) => {
              if (item.tmdbId && item.mediaType) nav.navigate('Details', { type: 'tmdb', id: String(item.tmdbId), mediaType: item.mediaType });
            }}
          />
        ) : null}

        {data?.rows.map((row) => (
          <Row
            key={row.id}
            title={row.title}
            items={row.items}
            getImageUri={(item: LibraryRowItem) => item.image}
            getTitle={(item: LibraryRowItem) => item.title}
            onItemPress={openRowItem}
            onTitlePress={row.genre ? () => nav.push('LibraryHome', { type, genre: row.genre, libraryKey }) : undefined}
            keyPrefix={`${row.id}-`}
          />
        ))}

        {data && (hero.length > 0 || data.rows.length > 0) ? (
          <Pressable onPress={openGrid} style={({ pressed }) => [styles.browseAll, pressed && { opacity: 0.7 }]}>
            <Ionicons name="grid-outline" size={16} color="#fff" />
            <Text style={styles.browseAllText}>{genre ? `Browse all ${genre}` : `Browse all ${noun.toLowerCase()}`}</Text>
          </Pressable>
        ) : null}
      </Animated.ScrollView>

      {/* Header: back, centred title, grid. Frosted once content scrolls under it. */}
      <View style={[styles.header, { paddingTop: insets.top, height: insets.top + HEADER_H }]} pointerEvents="box-none">
        <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { opacity: headerBg }]}>
          <ConditionalBlurView intensity={40} tint="dark" style={StyleSheet.absoluteFill} />
          <View style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(14,14,16,0.45)' }]} />
          <View style={styles.headerHairline} />
        </Animated.View>
        <View style={styles.headerRow} pointerEvents="box-none">
          <Pressable onPress={() => nav.goBack()} hitSlop={10} accessibilityRole="button" accessibilityLabel="Back" style={styles.headerButton}>
            <Ionicons name="chevron-back" size={26} color="#fff" />
          </Pressable>
          <Text style={styles.headerTitle} numberOfLines={1}>{title}</Text>
          <Pressable onPress={openGrid} hitSlop={10} accessibilityRole="button" accessibilityLabel={`Browse all ${noun.toLowerCase()}`} style={styles.headerButton}>
            {loading && data ? <ActivityIndicator color="#fff" /> : <Ionicons name="grid-outline" size={21} color="#fff" />}
          </Pressable>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  header: { position: 'absolute', top: 0, left: 0, right: 0 },
  headerHairline: { position: 'absolute', left: 0, right: 0, bottom: 0, height: StyleSheet.hairlineWidth, backgroundColor: 'rgba(255,255,255,0.1)' },
  headerRow: { flex: 1, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8 },
  headerButton: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  headerTitle: { flex: 1, color: '#fff', fontSize: 17, fontWeight: '700', textAlign: 'center' },
  pillRow: { alignItems: 'center', marginTop: 2, marginBottom: 14 },
  pill: {
    height: 36,
    paddingHorizontal: 14,
    borderRadius: 10,
    overflow: 'hidden',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  pillActive: { backgroundColor: '#fff' },
  pillGlass: {
    backgroundColor: 'rgba(118,124,132,0.30)',
    borderRadius: 10,
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.10)',
  },
  pillText: { color: '#fff', fontSize: 14, fontWeight: '600' },
  cardPlaceholder: { height: 520, marginHorizontal: 16, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.06)', marginBottom: 8 },
  empty: { alignItems: 'center', paddingHorizontal: 32, paddingTop: 120 },
  emptyTitle: { color: '#fff', fontSize: 18, fontWeight: '700', textAlign: 'center' },
  emptyText: { color: 'rgba(255,255,255,0.6)', fontSize: 14, marginTop: 8, textAlign: 'center' },
  browseAll: {
    alignSelf: 'center',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 24,
    paddingHorizontal: 18,
    height: 40,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  browseAllText: { color: '#fff', fontSize: 15, fontWeight: '600' },
});
