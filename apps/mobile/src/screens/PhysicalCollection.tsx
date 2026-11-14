/**
 * Your Discs: the Blu-ray.com collection through MyBluray (owned discs,
 * wishlist and the other lists) as a cover grid, opened from Home → Explore
 * More. Controls match the app's other glass filter bars: list pills with
 * counts, a format menu, a sort menu (with Refresh) and search. Tapping a
 * disc opens its edition page, which offers "Open in Library" when Plex has
 * the film. macOS reference: Views/Library/PhysicalCollectionView.swift
 */
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, Animated, FlatList, Pressable, StyleSheet, Text, TextInput, useWindowDimensions, View } from 'react-native';
import { useFocusEffect, useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import HeaderGlass, { HEADER_GLASS_MIN_OPACITY } from '../components/HeaderGlass';
import GlassMenu from '../components/GlassMenu';
import { GlassDropdownPill, GlassPill, RoundGlassButton, RoundGlassIcon } from '../components/GlassPill';
import LiquidGlass from '../components/LiquidGlass';
import EditionCoverCard from '../components/details/EditionCoverCard';
import { TopBarStore } from '../components/TopBarStore';
import { useTheme } from '../hooks/useTheme';
import {
  FORMAT_TITLES,
  SORT_TITLES,
  listsInUse,
  loadCollection,
  setCollectionFilters,
  shownEntries,
  useCollectionStore,
  type CollectionSort,
  type FormatFilter,
} from '../core/mybluray/collectionStore';
import type { MBCollectionEntry } from '../core/mybluray/types';

const INSET = 16;
const GAP = 12;
const NAV_ROW = 52;

export default function PhysicalCollection() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const store = useCollectionStore();
  const [searching, setSearching] = useState(store.query.length > 0);
  const scrollY = useRef(new Animated.Value(0)).current;

  useFocusEffect(
    React.useCallback(() => {
      TopBarStore.setVisible(false);
      TopBarStore.setTabBarVisible(true);
    }, [])
  );

  useEffect(() => {
    loadCollection();
  }, []);

  const lists = listsInUse(store);
  const shown = useMemo(() => shownEntries(store), [store]);
  // Sized from the window like the Library poster grid: 3 columns on a phone, more on wider screens
  const columns = Math.max(3, Math.floor((width - INSET * 2 + GAP) / (130 + GAP)));
  const cardWidth = Math.floor((width - INSET * 2 - GAP * (columns - 1)) / columns);
  const headerGlassOpacity = scrollY.interpolate({ inputRange: [0, 8, 60], outputRange: [HEADER_GLASS_MIN_OPACITY, HEADER_GLASS_MIN_OPACITY, 1], extrapolate: 'clamp' });
  const navBarHeight = insets.top + NAV_ROW;

  const openEdition = (entry: MBCollectionEntry) => nav.push('Edition', { id: entry.id, summary: entry, offersLibraryLink: true });

  const header = (
    <View style={{ paddingTop: navBarHeight + 4 }}>
      {/* List pills with counts; "All" last, as on macOS */}
      <FlatList
        horizontal
        showsHorizontalScrollIndicator={false}
        data={[...lists.map((l) => ({ id: l.list.id as string | null, name: l.list.name ?? l.list.id, count: l.count })), { id: null, name: 'All', count: store.entries.length }]}
        keyExtractor={(item) => item.id ?? 'all'}
        contentContainerStyle={styles.pillRow}
        renderItem={({ item }) => (
          <GlassPill
            label={`${item.name}  ${item.count}`}
            selected={store.listFilter === item.id}
            onPress={() => setCollectionFilters({ listFilter: item.id })}
          />
        )}
      />
      <View style={styles.controls}>
        <GlassMenu
          accessibilityLabel={`Format: ${FORMAT_TITLES[store.format]}`}
          items={(['all', 'uhd', 'bluray'] as FormatFilter[]).map((f) => ({ title: FORMAT_TITLES[f], checked: store.format === f, onPress: () => setCollectionFilters({ format: f }) }))}
        >
          <GlassDropdownPill label={FORMAT_TITLES[store.format]} selected={store.format !== 'all'} />
        </GlassMenu>
        <Text style={[styles.count, { color: theme.textTertiary }]} numberOfLines={1}>
          {shown.length === 1 ? '1 disc' : `${shown.length.toLocaleString('en-US')} discs`}
        </Text>
        <Pressable onPress={() => setSearching((v) => !v)} accessibilityRole="button" accessibilityLabel="Search your discs" hitSlop={4}>
          <RoundGlassIcon icon="search" />
        </Pressable>
        <GlassMenu
          accessibilityLabel={`Sort by ${SORT_TITLES[store.sort]}`}
          items={[
            ...(['added', 'title', 'release'] as CollectionSort[]).map((s) => ({ title: SORT_TITLES[s], checked: store.sort === s, onPress: () => setCollectionFilters({ sort: s }) })),
            { title: 'Refresh', icon: 'refresh' as const, onPress: () => loadCollection(true) },
          ]}
        >
          <RoundGlassIcon icon="swap-vertical" />
        </GlassMenu>
      </View>
      {searching ? (
        <View style={styles.searchWrap}>
          <LiquidGlass radius={12} />
          <Ionicons name="search" size={16} color="rgba(255,255,255,0.6)" />
          <TextInput
            value={store.query}
            onChangeText={(query) => setCollectionFilters({ query })}
            placeholder="Search your discs"
            placeholderTextColor="rgba(255,255,255,0.45)"
            style={styles.searchInput}
            autoFocus={!store.query}
            autoCorrect={false}
            returnKeyType="search"
            clearButtonMode="while-editing"
          />
        </View>
      ) : null}
    </View>
  );

  let body: React.ReactNode = null;
  if (store.phase === 'idle' || (store.phase === 'loading' && !store.entries.length)) {
    body = (
      <View style={[styles.centered, { paddingTop: navBarHeight + 80 }]}>
        <ActivityIndicator color="rgba(255,255,255,0.7)" size="large" />
        <Text style={styles.stateText}>Loading your collection…</Text>
      </View>
    );
  } else if (store.phase === 'notConnected') {
    body = (
      <View style={[styles.centered, { paddingTop: navBarHeight + 80 }]}>
        <Ionicons name="person-circle-outline" size={44} color="rgba(255,255,255,0.5)" />
        <Text style={styles.stateTitle}>No Blu-ray.com login on your key</Text>
        <Text style={styles.stateText}>Attach your Blu-ray.com login to your MyBluray key in the portal, then come back here.</Text>
      </View>
    );
  } else if (store.phase === 'failed') {
    body = (
      <View style={[styles.centered, { paddingTop: navBarHeight + 80 }]}>
        <Ionicons name="warning-outline" size={40} color="rgba(255,255,255,0.5)" />
        <Text style={styles.stateTitle}>Couldn't load your collection</Text>
        <Text style={styles.stateText}>{store.error}</Text>
        <Pressable onPress={() => loadCollection(true)} style={styles.retry} accessibilityRole="button">
          <Text style={styles.retryText}>Try Again</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      {body ?? (
        <Animated.FlatList
          data={shown}
          key={columns}
          numColumns={columns}
          keyExtractor={(e) => e.id}
          ListHeaderComponent={header}
          ListEmptyComponent={<Text style={[styles.stateText, { marginTop: 60 }]}>{store.query ? 'No discs match your search' : 'No discs here'}</Text>}
          columnWrapperStyle={{ gap: GAP, paddingHorizontal: INSET }}
          contentContainerStyle={{ paddingBottom: insets.bottom + 110, rowGap: 18 }}
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled"
          onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
          scrollEventThrottle={16}
          renderItem={({ item }) => (
            <EditionCoverCard edition={item} width={cardWidth} showsList={store.listFilter === null} showsCountry onPress={() => openEdition(item)} />
          )}
        />
      )}

      <View style={[styles.header, { paddingTop: insets.top }]} pointerEvents="box-none">
        <Animated.View style={[StyleSheet.absoluteFill, { opacity: headerGlassOpacity }]} pointerEvents="none">
          <HeaderGlass fallbackIntensity={80} />
        </Animated.View>
        <View style={styles.navRow}>
          <RoundGlassButton icon="chevron-back" label="Back" size={36} iconSize={22} onPress={() => nav.goBack()} />
          <Text style={styles.navTitle} numberOfLines={1}>Your Discs</Text>
          <View style={{ width: 36, alignItems: 'center' }}>
            {store.phase === 'loading' && store.entries.length ? <ActivityIndicator color="#fff" /> : null}
          </View>
        </View>
      </View>
      {store.message ? (
        <View style={[styles.toast, { bottom: insets.bottom + 100 }]} pointerEvents="none">
          <Text style={styles.toastText}>{store.message}</Text>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: { position: 'absolute', top: 0, left: 0, right: 0, zIndex: 2 },
  navRow: { height: NAV_ROW, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, gap: 8 },
  navTitle: { flex: 1, color: '#fff', fontSize: 18, fontWeight: '700', textAlign: 'center' },
  pillRow: { paddingHorizontal: INSET, gap: 8, paddingVertical: 6 },
  controls: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: INSET, paddingTop: 4, paddingBottom: 10 },
  count: { flex: 1, fontSize: 13, fontWeight: '500' },
  searchWrap: {
    marginHorizontal: INSET,
    marginBottom: 12,
    height: 40,
    borderRadius: 12,
    overflow: 'hidden',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    gap: 8,
  },
  searchInput: { flex: 1, color: '#fff', fontSize: 16 },
  centered: { alignItems: 'center', paddingHorizontal: 32, gap: 10 },
  stateTitle: { color: '#fff', fontSize: 18, fontWeight: '600', textAlign: 'center' },
  stateText: { color: 'rgba(255,255,255,0.6)', fontSize: 15, textAlign: 'center', lineHeight: 21 },
  retry: { marginTop: 8, height: 44, paddingHorizontal: 20, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.12)', justifyContent: 'center' },
  retryText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  toast: { position: 'absolute', alignSelf: 'center', paddingHorizontal: 14, paddingVertical: 9, borderRadius: 18, backgroundColor: 'rgba(30,30,32,0.95)' },
  toastText: { color: '#fff', fontSize: 13, fontWeight: '500' },
});
