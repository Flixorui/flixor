import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import MediaGrid from '../collections/MediaGrid';
import OptionSheet, { type SheetOption } from '../collections/OptionSheet';
import Chip from '../collections/Chip';
import { useTheme } from '../../hooks/useTheme';
import { useAppSettings } from '../../hooks/useAppSettings';
import type { DiscoverSortOption, SearchDiscoverFilters } from '../../core/SettingsData';
import {
  DEFAULT_DISCOVER_FILTERS,
  fetchDiscoverPage,
  getDiscoverGenres,
  hasActiveDiscoverFilters,
  normalizeDiscoverFilters,
  type SearchResult,
} from '../../core/SearchData';

const SORT_OPTIONS: Array<SheetOption<DiscoverSortOption>> = [
  { value: 'popular', label: 'Popular' },
  { value: 'topRated', label: 'Top Rated' },
  { value: 'newest', label: 'Newest' },
  { value: 'oldest', label: 'Oldest' },
  { value: 'title', label: 'Title (A-Z)' },
];

const RATING_OPTIONS: Array<SheetOption<number | undefined>> = [
  { value: undefined, label: 'Any rating' },
  { value: 5, label: '5 and up' },
  { value: 6, label: '6 and up' },
  { value: 7, label: '7 and up' },
  { value: 8, label: '8 and up' },
  { value: 9, label: '9 and up' },
];

type Picker = 'genre' | 'sort' | 'rating' | 'year' | null;

function yearLabel(filters: SearchDiscoverFilters): string {
  const { yearFrom: from, yearTo: to } = filters;
  if (from != null && to != null) return from === to ? String(from) : `${from} to ${to}`;
  if (from != null) return `From ${from}`;
  if (to != null) return `Up to ${to}`;
  return 'Year';
}

function parseYear(text: string): number | undefined {
  const year = Number(text.trim());
  return Number.isInteger(year) && year >= 1870 && year <= 2200 ? year : undefined;
}

function YearSheet({
  visible,
  filters,
  onApply,
  onClose,
}: {
  visible: boolean;
  filters: SearchDiscoverFilters;
  onApply: (from: number | undefined, to: number | undefined) => void;
  onClose: () => void;
}) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');

  useEffect(() => {
    if (visible) {
      setFrom(filters.yearFrom != null ? String(filters.yearFrom) : '');
      setTo(filters.yearTo != null ? String(filters.yearTo) : '');
    }
  }, [visible, filters.yearFrom, filters.yearTo]);

  const inputStyle = [styles.yearInput, { color: theme.textPrimary, backgroundColor: theme.surfaceOverlay }];
  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable
          style={[styles.yearSheet, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 16 }]}
          onPress={() => undefined}
        >
          <Text style={[styles.sheetTitle, { color: theme.textPrimary }]}>Year</Text>
          <View style={styles.yearRow}>
            <TextInput
              value={from}
              onChangeText={setFrom}
              placeholder="From"
              placeholderTextColor={theme.textTertiary}
              keyboardType="number-pad"
              maxLength={4}
              style={inputStyle}
            />
            <TextInput
              value={to}
              onChangeText={setTo}
              placeholder="To"
              placeholderTextColor={theme.textTertiary}
              keyboardType="number-pad"
              maxLength={4}
              style={inputStyle}
            />
          </View>
          <View style={styles.yearActions}>
            <Pressable
              onPress={() => {
                onApply(undefined, undefined);
                onClose();
              }}
              style={[styles.yearButton, { backgroundColor: theme.surfaceOverlay }]}
            >
              <Text style={{ color: theme.textPrimary, fontWeight: '600' }}>Any year</Text>
            </Pressable>
            <Pressable
              onPress={() => {
                onApply(parseYear(from), parseYear(to));
                onClose();
              }}
              style={[styles.yearButton, { backgroundColor: theme.accent }]}
            >
              <Text style={{ color: theme.onAccent, fontWeight: '700' }}>Apply</Text>
            </Pressable>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

/** TMDB discover with type, genre, sort, year and rating filters that persist per profile. */
export default function DiscoverPanel({
  onPressItem,
  headerAccessory,
}: {
  onPressItem: (item: SearchResult) => void;
  /** Rendered above the filters, inside the scrolling list. */
  headerAccessory?: React.ReactElement | null;
}) {
  const theme = useTheme();
  const { settings, isLoaded, updateSetting } = useAppSettings();
  const filters = settings.searchDiscoverFilters ?? DEFAULT_DISCOVER_FILTERS;

  const [items, setItems] = useState<SearchResult[]>([]);
  const [phase, setPhase] = useState<'loading' | 'loaded' | 'error'>('loading');
  const [loadingMore, setLoadingMore] = useState(false);
  const [pagingError, setPagingError] = useState(false);
  const [genres, setGenres] = useState<Array<{ id: number; name: string }>>([]);
  const [picker, setPicker] = useState<Picker>(null);

  const pageRef = useRef(0);
  const hasMoreRef = useRef(false);
  const seenRef = useRef(new Set<string>());
  const generationRef = useRef(0);
  const busyRef = useRef(false);

  const filtersKey = JSON.stringify(filters);

  const loadPage = useCallback(async (next: SearchDiscoverFilters, page: number) => {
    const generation = generationRef.current;
    busyRef.current = true;
    try {
      const result = await fetchDiscoverPage(next, page);
      if (generation !== generationRef.current) return;
      const fresh = result.items.filter((item) => !seenRef.current.has(item.id));
      fresh.forEach((item) => seenRef.current.add(item.id));
      pageRef.current = page;
      hasMoreRef.current = result.hasMore;
      setItems((prev) => (page === 1 ? fresh : [...prev, ...fresh]));
      setPhase('loaded');
      setPagingError(false);
    } catch (e) {
      if (generation !== generationRef.current) return;
      console.log('[DiscoverPanel] load error:', e);
      if (page === 1) setPhase('error');
      else setPagingError(true);
    } finally {
      if (generation === generationRef.current) {
        busyRef.current = false;
        setLoadingMore(false);
      }
    }
  }, []);

  const reload = useCallback(() => {
    generationRef.current += 1;
    seenRef.current = new Set();
    pageRef.current = 0;
    hasMoreRef.current = false;
    setItems([]);
    setPagingError(false);
    setPhase('loading');
    void loadPage(filters, 1);
    // filtersKey stands in for filters, which is a new object on each settings load
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtersKey, loadPage]);

  useEffect(() => {
    if (isLoaded) reload();
  }, [isLoaded, reload]);

  useEffect(() => {
    let cancelled = false;
    getDiscoverGenres(filters.mediaType).then((list) => {
      if (!cancelled) setGenres(list);
    });
    return () => {
      cancelled = true;
    };
  }, [filters.mediaType]);

  const update = useCallback(
    (changes: Partial<SearchDiscoverFilters>) => {
      updateSetting('searchDiscoverFilters', normalizeDiscoverFilters({ ...filters, ...changes }));
    },
    [filters, updateSetting]
  );

  const loadMore = useCallback(() => {
    if (busyRef.current || !hasMoreRef.current) return;
    setLoadingMore(true);
    void loadPage(filters, pageRef.current + 1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtersKey, loadPage]);

  const genreOptions: Array<SheetOption<number | undefined>> = [
    { value: undefined, label: 'All genres' },
    ...genres.map((genre) => ({ value: genre.id as number | undefined, label: genre.name })),
  ];
  const sortLabel = SORT_OPTIONS.find((o) => o.value === filters.sort)?.label ?? 'Popular';

  const header = (
    <View>
      {headerAccessory}
      <View style={styles.filters}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        <Chip
          label="Movies"
          active={filters.mediaType === 'movie'}
          // Genre ids differ between movies and TV, so a switch clears the selection
          onPress={() => filters.mediaType !== 'movie' && update({ mediaType: 'movie', genreId: undefined, genreName: undefined })}
        />
        <Chip
          label="TV Shows"
          active={filters.mediaType === 'tv'}
          onPress={() => filters.mediaType !== 'tv' && update({ mediaType: 'tv', genreId: undefined, genreName: undefined })}
        />
        <Chip label={filters.genreName ?? 'Genre'} caret active={filters.genreId != null} onPress={() => setPicker('genre')} />
        <Chip label={sortLabel} caret active={filters.sort !== 'popular'} onPress={() => setPicker('sort')} />
        <Chip label={yearLabel(filters)} caret active={filters.yearFrom != null || filters.yearTo != null} onPress={() => setPicker('year')} />
        <Chip
          label={filters.minimumRating != null ? `${filters.minimumRating}+` : 'Rating'}
          caret
          active={filters.minimumRating != null}
          onPress={() => setPicker('rating')}
        />
        {hasActiveDiscoverFilters(filters) ? (
          <Chip label="Reset" onPress={() => updateSetting('searchDiscoverFilters', { ...DEFAULT_DISCOVER_FILTERS, mediaType: filters.mediaType })} />
        ) : null}
      </ScrollView>
      </View>
    </View>
  );

  const message =
    phase === 'loading' ? (
      <View style={styles.center}>
        <ActivityIndicator color={theme.textPrimary} />
      </View>
    ) : phase === 'error' ? (
      <View style={styles.center}>
        <Ionicons name="cloud-offline-outline" size={36} color={theme.textTertiary} />
        <Text style={[styles.message, { color: theme.textSecondary }]}>Couldn't load titles.</Text>
        <Pressable onPress={reload} style={[styles.retry, { backgroundColor: theme.surfaceOverlay }]}>
          <Text style={{ color: theme.textPrimary, fontWeight: '600' }}>Try Again</Text>
        </Pressable>
      </View>
    ) : (
      <View style={styles.center}>
        <Ionicons name="search-outline" size={36} color={theme.textTertiary} />
        <Text style={[styles.message, { color: theme.textSecondary }]}>No titles match these filters.</Text>
      </View>
    );

  return (
    <View style={{ flex: 1 }}>
      <MediaGrid
        items={items}
        onPress={onPressItem}
        contentInsetAdjustmentBehavior="automatic"
        header={header}
        empty={message}
        onEndReached={loadMore}
        loadingMore={loadingMore}
        footer={
          pagingError ? (
            <Pressable onPress={loadMore} style={styles.pagingRetry}>
              <Text style={{ color: theme.textSecondary, fontWeight: '600' }}>Couldn't load more. Tap to retry.</Text>
            </Pressable>
          ) : null
        }
      />

      <OptionSheet
        visible={picker === 'genre'}
        title="Genre"
        options={genreOptions}
        selected={filters.genreId}
        onSelect={(id) => update({ genreId: id, genreName: genres.find((g) => g.id === id)?.name })}
        onClose={() => setPicker(null)}
      />
      <OptionSheet
        visible={picker === 'sort'}
        title="Sort By"
        options={SORT_OPTIONS}
        selected={filters.sort}
        onSelect={(sort) => update({ sort })}
        onClose={() => setPicker(null)}
      />
      <OptionSheet
        visible={picker === 'rating'}
        title="Minimum Rating"
        options={RATING_OPTIONS}
        selected={filters.minimumRating}
        onSelect={(minimumRating) => update({ minimumRating })}
        onClose={() => setPicker(null)}
      />
      <YearSheet
        visible={picker === 'year'}
        filters={filters}
        onApply={(yearFrom, yearTo) => update({ yearFrom, yearTo })}
        onClose={() => setPicker(null)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  filters: { paddingHorizontal: 8, paddingTop: 8, paddingBottom: 4 },
  center: { alignItems: 'center', paddingTop: 60, paddingHorizontal: 32 },
  message: { fontSize: 15, marginTop: 10, textAlign: 'center' },
  retry: { marginTop: 14, paddingHorizontal: 18, paddingVertical: 10, borderRadius: 10 },
  pagingRetry: { paddingVertical: 20, alignItems: 'center' },
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.55)', justifyContent: 'flex-end' },
  yearSheet: { borderTopLeftRadius: 18, borderTopRightRadius: 18, padding: 20 },
  sheetTitle: { fontSize: 17, fontWeight: '700', marginBottom: 14 },
  yearRow: { flexDirection: 'row', gap: 12 },
  yearInput: { flex: 1, borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16 },
  yearActions: { flexDirection: 'row', gap: 12, marginTop: 16 },
  yearButton: { flex: 1, alignItems: 'center', paddingVertical: 13, borderRadius: 10 },
});
