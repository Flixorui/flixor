/**
 * My List, in the style of Home and the macOS library pages:
 * - Its own header: a big "My List" title with round glass Sort and New List buttons, and
 *   the list switcher (My List, then your Trakt lists) as Liquid Glass pills, like Home's.
 *   The pills hide on a scroll down and return on a deliberate scroll up, as on Home.
 * - Count chips (All, Movies, TV Shows, In Library, Added This Month) above the grid.
 * - A clean poster grid following the poster settings. Long-press opens a native menu.
 * macOS reference: Views/MyList/MyListView.swift
 */

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator, Alert, Animated, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View, useWindowDimensions,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { FlashList } from '@shopify/flash-list';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import ContextMenu from 'react-native-context-menu-view';
import * as Haptics from 'expo-haptics';
import { useFocusEffect, useNavigation } from '@react-navigation/native';
import { TopBarStore } from '../components/TopBarStore';
import { useScrollLinkedHeader } from '../components/useScrollLinkedHeader';
import HeaderGlass, { HEADER_GLASS_MIN_OPACITY } from '../components/HeaderGlass';
import LiquidGlass from '../components/LiquidGlass';
import GlassMenu from '../components/GlassMenu';
import { useFlixor } from '../core/FlixorContext';
import { useAppMode } from '../core/AppMode';
import { useAppSettings } from '../hooks/useAppSettings';
import { showToast } from '../components/Toast';
import {
  fetchMyList, fetchTmdbPoster, getMyListPosterUrl, isTraktConnected, removeFromMyList,
  type FilterOption, type MyListItem, type SortOption,
} from '../core/MyListData';
import TraktListContent from '../components/lists/TraktListContent';
import TraktListEditorSheet from '../components/lists/TraktListEditorSheet';
import AddToListSheet from '../components/lists/AddToListSheet';
import {
  fetchTraktLists, traktListErrorMessage, type TraktListGridItem, type TraktListTitle, type TraktUserList,
} from '../core/TraktListsData';

const SORT_OPTIONS: Array<{ value: SortOption; label: string }> = [
  { value: 'added', label: 'Date Added' },
  { value: 'title', label: 'Title' },
  { value: 'year', label: 'Year' },
];

const TITLE_ROW = 52;
const PILL_ROW = 52;
const GRID_GAP = 8;
const GRID_INSET = 12;
const MONTH = 30 * 86400000;

// Kept across visits so the grid shows straight away
const store = { items: null as MyListItem[] | null, sort: 'added' as SortOption, at: 0 };

// ---------------------------------------------------------------- pieces

/** Home's glass pill: white when selected. */
function GlassPill({ label, count, selected, onPress }: { label: string; count?: number; selected?: boolean; onPress: () => void }) {
  return (
    <Pressable
      onPress={() => {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
        onPress();
      }}
      accessibilityRole="button"
      accessibilityState={{ selected: !!selected }}
      style={({ pressed }) => [styles.pill, selected && styles.pillSelected, pressed && { opacity: 0.75 }]}
    >
      {selected ? null : <LiquidGlass radius={12} />}
      <Text style={[styles.pillText, selected && { color: '#000' }]} numberOfLines={1}>{label}</Text>
      {count !== undefined ? <Text style={[styles.pillCount, selected && { color: 'rgba(0,0,0,0.55)' }]}>{count}</Text> : null}
    </Pressable>
  );
}

function RoundGlassButton({ icon, label, onPress }: { icon: keyof typeof Ionicons.glyphMap; label: string; onPress?: () => void }) {
  return (
    <Pressable onPress={onPress} disabled={!onPress} hitSlop={6} accessibilityRole="button" accessibilityLabel={label} style={({ pressed }) => [styles.roundButton, pressed && { opacity: 0.7 }]}>
      <LiquidGlass radius={20} />
      <Ionicons name={icon} size={19} color="#fff" />
    </Pressable>
  );
}

const PosterCell = React.memo(function PosterCell({
  item, width, radius, showTitle, onPress, onAddToList, onRemove,
}: {
  item: MyListItem;
  width: number;
  radius: number;
  showTitle: boolean;
  onPress: (item: MyListItem) => void;
  onAddToList?: (item: MyListItem) => void;
  onRemove: (item: MyListItem) => void;
}) {
  // FlashList reuses cells for other titles, so the poster is tied to the item's id
  const direct = getMyListPosterUrl(item, Math.round(width * 2)) || '';
  const [fetched, setFetched] = useState<{ id: string; uri: string } | null>(null);
  const uri = direct || (fetched?.id === item.id ? fetched.uri : '');
  useEffect(() => {
    if (direct || !item.tmdbId) return;
    let live = true;
    fetchTmdbPoster(item).then((u) => live && u && setFetched({ id: item.id, uri: u })).catch(() => {});
    return () => {
      live = false;
    };
  }, [item, direct]);

  const actions = [
    ...(onAddToList ? [{ title: 'Add to Trakt List', systemIcon: 'text.badge.plus' }] : []),
    { title: 'Remove from My List', systemIcon: 'minus.circle', destructive: true },
  ];

  return (
    <View style={{ width, marginBottom: showTitle ? 14 : GRID_GAP }}>
      <ContextMenu
        actions={actions}
        previewBackgroundColor="transparent"
        borderRadius={radius}
        onPress={(e) => {
          const title = actions[e.nativeEvent.index]?.title;
          if (title === 'Add to Trakt List') onAddToList?.(item);
          else if (title === 'Remove from My List') onRemove(item);
        }}
      >
        <Pressable onPress={() => onPress(item)} accessibilityRole="button" accessibilityLabel={item.title}>
          <View style={[styles.poster, { width, height: Math.round(width * 1.5), borderRadius: radius }]}>
            {uri ? (
              <FastImage
                source={{ uri, priority: FastImage.priority.normal, cache: FastImage.cacheControl.immutable }}
                style={StyleSheet.absoluteFill}
                resizeMode={FastImage.resizeMode.cover}
              />
            ) : (
              <View style={styles.posterFallback}>
                <Text style={styles.posterFallbackText} numberOfLines={3}>{item.title}</Text>
              </View>
            )}
          </View>
        </Pressable>
      </ContextMenu>
      {showTitle ? (
        <>
          <Text numberOfLines={1} style={styles.cellTitle}>{item.title}</Text>
          {item.year ? <Text style={styles.cellYear}>{item.year}</Text> : null}
        </>
      ) : null}
    </View>
  );
});

// ---------------------------------------------------------------- screen

export default function MyList() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const { flixor, isLoading: flixorLoading, isConnected } = useFlixor();
  const { isStremioOnly } = useAppMode();
  const { settings } = useAppSettings();
  const ready = isConnected || isStremioOnly;

  const [items, setItems] = useState<MyListItem[]>(() => store.items ?? []);
  const [loading, setLoading] = useState(!store.items);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sort, setSort] = useState<SortOption>(store.sort);
  const [filter, setFilter] = useState<FilterOption>('all');
  const [inLibraryOnly, setInLibraryOnly] = useState(false);
  const [recentOnly, setRecentOnly] = useState(false);

  const [traktLists, setTraktLists] = useState<TraktUserList[]>([]);
  const [selectedListId, setSelectedListId] = useState<number | null>(null);
  const [listEditor, setListEditor] = useState<{ list: TraktUserList | null } | null>(null);
  const [addToListTitle, setAddToListTitle] = useState<TraktListTitle | null>(null);
  const selectedList = selectedListId ? traktLists.find((l) => l.ids.trakt === selectedListId) ?? null : null;
  // The list pills show only when there are Trakt lists to switch between
  const showListPills = isTraktConnected() && traktLists.length > 0;
  // Title row, then the filter pills (and the Trakt list pills when there are lists)
  const pillRows = showListPills ? 2 : 1;
  const headerH = insets.top + TITLE_ROW + PILL_ROW * pillRows;

  const scrollY = useRef(new Animated.Value(0)).current;
  const gridRef = useRef<any>(null);
  // Like New & Hot: the title row follows the scroll (the pills stay pinned), then eases the
  // rest of the way when scrolling stops
  const { value: collapse, onScrollY, show } = useScrollLinkedHeader(TITLE_ROW);
  // A new order or filter starts from the top
  useEffect(() => {
    gridRef.current?.scrollToOffset?.({ offset: 0, animated: false });
    show();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sort, filter, inLibraryOnly, recentOnly, items]);
  const headerShift = collapse.interpolate({ inputRange: [0, TITLE_ROW], outputRange: [0, -TITLE_ROW] });
  const titleOpacity = collapse.interpolate({ inputRange: [0, TITLE_ROW * 0.7], outputRange: [1, 0], extrapolate: 'clamp' });

  useFocusEffect(
    useCallback(() => {
      // This page draws its own header
      TopBarStore.setVisible(false);
      TopBarStore.setTabBarVisible(true);
    }, [])
  );

  // The whole list in the chosen order; filters apply on the phone so the chips show counts
  const load = useCallback(async (opts: { quiet?: boolean } = {}) => {
    if (!opts.quiet) setLoading(store.items === null);
    setError(null);
    try {
      const result = await fetchMyList({ filter: 'all', sort, sortDirection: sort === 'title' ? 'asc' : 'desc' });
      const usable = result.filter((i) => i.poster || i.tmdbId);
      store.items = usable;
      store.sort = sort;
      store.at = Date.now();
      setItems(usable);
    } catch (e) {
      console.log('[MyList] load failed', e);
      if (!store.items) setError("Couldn't load your list.");
    } finally {
      setLoading(false);
    }
  }, [sort]);

  useFocusEffect(
    useCallback(() => {
      if (flixorLoading || !ready) return;
      const stale = !store.items || store.sort !== sort || Date.now() - store.at > 60 * 1000;
      if (stale) load({ quiet: !!store.items });
    }, [flixorLoading, ready, sort, load])
  );

  // Trakt lists refresh on focus, since lists can change on other devices
  useFocusEffect(
    useCallback(() => {
      let current = true;
      if (flixorLoading || !ready || !isTraktConnected()) {
        setTraktLists([]);
        return;
      }
      fetchTraktLists()
        .then((lists) => current && setTraktLists(lists))
        .catch((e) => {
          console.log('[MyList] Trakt lists failed', e);
          if (current) showToast(traktListErrorMessage(e, "Couldn't load your Trakt lists."), { kind: 'error' });
        });
      return () => {
        current = false;
      };
    }, [flixorLoading, ready])
  );

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    if (flixor) await Promise.all([flixor.clearPlexCache(), flixor.clearTraktCache()]);
    await load({ quiet: true });
    setRefreshing(false);
  }, [flixor, load]);

  const counts = useMemo(() => ({
    all: items.length,
    movies: items.filter((i) => i.type === 'movie').length,
    shows: items.filter((i) => i.type !== 'movie').length,
    inLibrary: items.filter((i) => i.source === 'plex' || i.source === 'both').length,
  }), [items]);

  const visible = useMemo(() => {
    const now = Date.now();
    return items.filter((i) => {
      if (filter === 'movies' && i.type !== 'movie') return false;
      if (filter === 'shows' && i.type === 'movie') return false;
      if (inLibraryOnly && !(i.source === 'plex' || i.source === 'both')) return false;
      if (recentOnly && now - new Date(i.addedAt).getTime() > MONTH) return false;
      return true;
    });
  }, [items, filter, inLibraryOnly, recentOnly]);

  const openItem = useCallback((item: MyListItem) => {
    const numericKey = item.plexRatingKey && /^\d+$/.test(item.plexRatingKey);
    if (numericKey) nav.navigate('Details', { type: 'plex', ratingKey: item.plexRatingKey });
    else if (item.tmdbId) nav.navigate('Details', { type: 'tmdb', id: String(item.tmdbId), mediaType: item.type === 'movie' ? 'movie' : 'tv' });
    else if (item.plexRatingKey) nav.navigate('Details', { type: 'plex', ratingKey: item.plexRatingKey });
  }, [nav]);

  const removeItem = useCallback((item: MyListItem) => {
    Alert.alert('Remove from My List', `Remove "${item.title}" from your list?`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Remove',
        style: 'destructive',
        onPress: async () => {
          if (await removeFromMyList(item)) {
            setItems((prev) => {
              const next = prev.filter((i) => i.id !== item.id);
              store.items = next;
              return next;
            });
            Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          } else {
            showToast("Couldn't remove it. Try again.", { kind: 'error' });
          }
        },
      },
    ]);
  }, []);

  const addToList = useCallback((item: MyListItem) => {
    setAddToListTitle({ type: item.type, tmdbId: item.tmdbId, imdbId: item.imdbId, title: item.title });
  }, []);

  const handleTraktItemPress = useCallback((item: TraktListGridItem) => {
    if (item.tmdbId) nav.navigate('Details', { type: 'tmdb', id: String(item.tmdbId), mediaType: item.type === 'movie' ? 'movie' : 'tv' });
    else showToast("This title can't be opened because Trakt has no TMDB id for it.", { kind: 'info' });
  }, [nav]);

  const handleListSaved = useCallback((saved: TraktUserList) => {
    setTraktLists((prev) =>
      prev.some((l) => l.ids.trakt === saved.ids.trakt) ? prev.map((l) => (l.ids.trakt === saved.ids.trakt ? saved : l)) : [...prev, saved]
    );
    setSelectedListId(saved.ids.trakt);
  }, []);
  const handleListDeleted = useCallback(() => {
    setTraktLists((prev) => prev.filter((l) => l.ids.trakt !== selectedListId));
    setSelectedListId(null);
  }, [selectedListId]);
  const handleListCountChanged = useCallback((listId: number, count: number) => {
    setTraktLists((prev) => prev.map((l) => (l.ids.trakt === listId && l.item_count !== count ? { ...l, item_count: count } : l)));
  }, []);

  // Grid: 3 columns on phones, 5 on tablets
  const columns = width >= 800 ? 5 : 3;
  const cellW = Math.floor((width - GRID_INSET * 2 - GRID_GAP * (columns - 1)) / columns);
  const radius = settings.posterBorderRadius ?? 12;

  const filterChips = (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.pillRow}>
      <GlassPill label="All" selected={filter === 'all' && !inLibraryOnly && !recentOnly} onPress={() => { setFilter('all'); setInLibraryOnly(false); setRecentOnly(false); }} />
      {counts.movies > 0 ? <GlassPill label="Movies" count={counts.movies} selected={filter === 'movies'} onPress={() => setFilter(filter === 'movies' ? 'all' : 'movies')} /> : null}
      {counts.shows > 0 ? <GlassPill label="TV Shows" count={counts.shows} selected={filter === 'shows'} onPress={() => setFilter(filter === 'shows' ? 'all' : 'shows')} /> : null}
      {selectedListId === null && counts.inLibrary > 0 ? (
        <GlassPill label="In Library" count={counts.inLibrary} selected={inLibraryOnly} onPress={() => setInLibraryOnly((v) => !v)} />
      ) : null}
      {selectedListId === null ? <GlassPill label="Added This Month" selected={recentOnly} onPress={() => setRecentOnly((v) => !v)} /> : null}
    </ScrollView>
  );

  const onScroll = Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], {
    useNativeDriver: false,
    listener: (e: any) => onScrollY(e.nativeEvent.contentOffset.y),
  });

  // ---------------------------------------------------------------- body

  let body: React.ReactNode;
  if (flixorLoading || !ready || (loading && items.length === 0 && selectedListId === null)) {
    body = (
      <View style={{ paddingTop: headerH + 6 }}>
        <View style={[styles.skelGrid, { paddingHorizontal: GRID_INSET, gap: GRID_GAP }]}>
          {Array.from({ length: columns * 3 }).map((_, i) => (
            <View key={i} style={{ width: cellW, height: Math.round(cellW * 1.5), borderRadius: radius, backgroundColor: '#1a1a1c' }} />
          ))}
        </View>
      </View>
    );
  } else if (selectedList) {
    body = (
      <TraktListContent
        key={selectedList.ids.trakt}
        list={selectedList}
        filter={filter}
        sort={sort}
        switcher={<View />}
        paddingTop={headerH}
        onScroll={(e: any) => {
          scrollY.setValue(e.nativeEvent.contentOffset.y);
          onScrollY(e.nativeEvent.contentOffset.y);
        }}
        onPressItem={handleTraktItemPress}
        onAddToList={setAddToListTitle}
        onEdit={() => setListEditor({ list: selectedList })}
        onDeleted={handleListDeleted}
        onCountChanged={handleListCountChanged}
      />
    );
  } else if (error && items.length === 0) {
    body = (
      <View style={[styles.empty, { paddingTop: headerH + 80 }]}>
        <Text style={styles.emptyTitle}>{error}</Text>
        <Pressable onPress={() => load()} style={styles.emptyButton}>
          <Text style={styles.emptyButtonText}>Try Again</Text>
        </Pressable>
      </View>
    );
  } else {
    body = (
      <FlashList
        ref={gridRef}
        data={visible}
        keyExtractor={(item) => item.id}
        numColumns={columns}
        renderItem={({ item, index }) => (
          <View style={{ paddingLeft: index % columns === 0 ? 0 : GRID_GAP / 2, paddingRight: index % columns === columns - 1 ? 0 : GRID_GAP / 2, alignItems: index % columns === 0 ? 'flex-start' : index % columns === columns - 1 ? 'flex-end' : 'center' }}>
            <PosterCell
              item={item}
              width={cellW}
              radius={radius}
              showTitle={settings.showPosterTitles}
              onPress={openItem}
              onAddToList={isTraktConnected() ? addToList : undefined}
              onRemove={removeItem}
            />
          </View>
        )}
        contentContainerStyle={{ paddingHorizontal: GRID_INSET, paddingTop: headerH + 6, paddingBottom: 120 + insets.bottom }}
        ListEmptyComponent={
          <View style={[styles.empty, { paddingTop: 60 }]}>
            <Ionicons name="bookmark-outline" size={44} color="#3a3a3c" />
            <Text style={styles.emptyTitle}>{items.length === 0 ? 'Your list is empty' : 'Nothing matches these filters'}</Text>
            <Text style={styles.emptyText}>
              {items.length === 0 ? 'Add movies and TV shows to My List from their details page.' : 'Try another filter.'}
            </Text>
          </View>
        }
        onScroll={onScroll}
        scrollEventThrottle={16}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#fff" progressViewOffset={headerH} />}
      />
    );
  }

  const sortLabel = SORT_OPTIONS.find((o) => o.value === sort)?.label ?? 'Date Added';
  const traktOn = isTraktConnected();

  return (
    <View style={styles.screen}>
      {body}

      {/* Header: title with glass buttons, then the pills. Slides up by the title row on scroll. */}
      <Animated.View style={[styles.header, { height: headerH, transform: [{ translateY: headerShift }] }]} pointerEvents="box-none">
        {/* Reaches one title row above, so the status bar stays covered as the header slides up */}
        <Animated.View pointerEvents="none" style={[styles.band, { top: -TITLE_ROW, height: headerH + TITLE_ROW }]}>
          <Animated.View
            style={[StyleSheet.absoluteFill, { opacity: scrollY.interpolate({ inputRange: [0, 8, 60], outputRange: [HEADER_GLASS_MIN_OPACITY, HEADER_GLASS_MIN_OPACITY, 1], extrapolate: 'clamp' }) }]}
          >
            <HeaderGlass />
          </Animated.View>
        </Animated.View>

        <Animated.View style={[styles.titleRow, { marginTop: insets.top, opacity: titleOpacity }]} pointerEvents="box-none">
          <Text style={styles.title}>My List</Text>
          <View style={styles.titleButtons}>
            <GlassMenu
              accessibilityLabel={`Sort by ${sortLabel}`}
              items={SORT_OPTIONS.map((o) => ({ title: o.label, checked: o.value === sort, onPress: () => setSort(o.value) }))}
            >
              <View style={styles.roundButton}>
                <LiquidGlass radius={20} />
                <Ionicons name="swap-vertical" size={19} color="#fff" />
              </View>
            </GlassMenu>
            {traktOn ? <RoundGlassButton icon="add" label="New Trakt list" onPress={() => setListEditor({ list: null })} /> : null}
          </View>
        </Animated.View>

        {showListPills ? (
          <View style={{ height: PILL_ROW }}>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.pillRow}>
              <GlassPill label="My List" selected={selectedListId === null} onPress={() => setSelectedListId(null)} />
              {traktLists.map((list) => (
                <GlassPill
                  key={list.ids.trakt}
                  label={list.name.length > 24 ? `${list.name.slice(0, 24)}…` : list.name}
                  selected={selectedListId === list.ids.trakt}
                  onPress={() => setSelectedListId(list.ids.trakt)}
                />
              ))}
            </ScrollView>
          </View>
        ) : null}
        <View style={{ height: PILL_ROW }}>{filterChips}</View>
      </Animated.View>

      <TraktListEditorSheet visible={listEditor !== null} list={listEditor?.list} onClose={() => setListEditor(null)} onSaved={handleListSaved} />
      <AddToListSheet title={addToListTitle} onClose={() => setAddToListTitle(null)} />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#0e0e10' },
  header: { position: 'absolute', top: 0, left: 0, right: 0 },
  band: { position: 'absolute', top: 0, left: 0, right: 0, overflow: 'hidden' },
  titleRow: { height: TITLE_ROW, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20 },
  title: { flex: 1, color: '#fff', fontSize: 25, fontWeight: '600' },
  titleButtons: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  roundButton: { width: 40, height: 40, borderRadius: 20, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  pillRow: { paddingHorizontal: 16, gap: 8, alignItems: 'center', paddingVertical: 6 },
  pill: { height: 40, paddingHorizontal: 15, borderRadius: 12, overflow: 'hidden', flexDirection: 'row', alignItems: 'center', gap: 6 },
  pillSelected: { backgroundColor: '#fff' },
  pillText: { color: '#fff', fontSize: 15, fontWeight: '600' },
  pillCount: { color: 'rgba(255,255,255,0.6)', fontSize: 14, fontWeight: '600' },
  poster: { overflow: 'hidden', backgroundColor: '#1a1a1c' },
  posterFallback: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 8 },
  posterFallbackText: { color: '#8e8e93', fontSize: 12, textAlign: 'center' },
  cellTitle: { color: '#fff', fontSize: 12.5, fontWeight: '600', marginTop: 6 },
  cellYear: { color: '#8e8e93', fontSize: 11.5, marginTop: 1 },
  skelGrid: { flexDirection: 'row', flexWrap: 'wrap' },
  empty: { alignItems: 'center', paddingHorizontal: 32 },
  emptyTitle: { color: '#fff', fontSize: 18, fontWeight: '700', marginTop: 12, textAlign: 'center' },
  emptyText: { color: '#8e8e93', fontSize: 14, marginTop: 6, textAlign: 'center', lineHeight: 20 },
  emptyButton: { marginTop: 16, paddingHorizontal: 18, height: 40, borderRadius: 10, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center' },
  emptyButtonText: { color: '#000', fontSize: 15, fontWeight: '700' },
});
