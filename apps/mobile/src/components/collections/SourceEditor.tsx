import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { getFlixorCore } from '../../core';
import { useTheme } from '../../hooks/useTheme';
import Chip from './Chip';
import { getBrowsableCatalogs, type InstalledCatalog } from '../../core/AddonCatalogs';
import { fetchTraktLists, isTraktAvailable, type TraktUserList } from '../../core/TraktListsData';
import {
  DISCOVER_SORT_LABELS,
  PERSON_CREDITS_LABELS,
  PERSON_ORDER_LABELS,
  SOURCE_KIND_LABELS,
  createUserCollectionId,
  fetchUserCollectionSourcePage,
  type CollectionDiscoverSort,
  type PersonCreditsFilter,
  type PersonCreditsOrder,
  type TmdbDiscoverSource,
  type UserCollectionItem,
  type UserCollectionSource,
  type UserCollectionSourceKind,
} from '../../core/UserCollectionsStore';

/** Well-known TV networks. TMDB has no network search, so these are listed. */
export const KNOWN_NETWORKS: Array<{ id: number; name: string }> = [
  { id: 213, name: 'Netflix' },
  { id: 1024, name: 'Prime Video' },
  { id: 2739, name: 'Disney+' },
  { id: 2552, name: 'Apple TV+' },
  { id: 453, name: 'Hulu' },
  { id: 3186, name: 'HBO Max' },
  { id: 49, name: 'HBO' },
  { id: 4330, name: 'Paramount+' },
  { id: 3353, name: 'Peacock' },
  { id: 67, name: 'Showtime' },
  { id: 318, name: 'Starz' },
  { id: 88, name: 'FX' },
  { id: 174, name: 'AMC' },
  { id: 6, name: 'NBC' },
  { id: 2, name: 'ABC' },
  { id: 16, name: 'CBS' },
  { id: 19, name: 'FOX' },
  { id: 71, name: 'The CW' },
  { id: 4, name: 'BBC One' },
];

const DEBOUNCE_MS = 350;

type SearchHit = { key: string; title: string; subtitle?: string; image?: string; select: () => void };

function emptyDiscover(id: string): TmdbDiscoverSource {
  return { id, kind: 'tmdbDiscover', mediaType: 'movie', genreIds: [], genreNames: [], sort: 'popularity' };
}

function parseYear(text: string): number | undefined {
  const year = Number(text.trim());
  return text.trim() && Number.isInteger(year) && year >= 1870 && year <= 2200 ? year : undefined;
}

/** Add or edit one collection source. Requests only follow typing or pressing Preview. */
export default function SourceEditor({
  kind,
  existing,
  onSave,
  onClose,
}: {
  /** The kind of source. `null` hides the editor. */
  kind: UserCollectionSourceKind | null;
  existing?: UserCollectionSource | null;
  onSave: (source: UserCollectionSource) => void;
  onClose: () => void;
}) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const sourceId = useRef(createUserCollectionId());

  const [selected, setSelected] = useState<UserCollectionSource | null>(null);
  const [discover, setDiscover] = useState<TmdbDiscoverSource>(() => emptyDiscover(sourceId.current));
  const [yearFrom, setYearFrom] = useState('');
  const [yearTo, setYearTo] = useState('');
  const [genres, setGenres] = useState<Array<{ id: number; name: string }>>([]);

  const [companyText, setCompanyText] = useState('');
  const [companyHits, setCompanyHits] = useState<Array<{ id: number; name: string }>>([]);

  const [searchText, setSearchText] = useState('');
  const [hits, setHits] = useState<SearchHit[]>([]);
  const [searching, setSearching] = useState(false);
  const [searched, setSearched] = useState(false);
  const [searchError, setSearchError] = useState(false);

  const [catalogs, setCatalogs] = useState<InstalledCatalog[]>([]);
  const [traktLists, setTraktLists] = useState<TraktUserList[]>([]);
  const [listPhase, setListPhase] = useState<'loading' | 'loaded' | 'error'>('loading');

  const [preview, setPreview] = useState<
    { state: 'idle' } | { state: 'loading' } | { state: 'loaded'; items: UserCollectionItem[] } | { state: 'failed'; message: string }
  >({ state: 'idle' });

  // Reset for each presentation
  useEffect(() => {
    if (!kind) return;
    sourceId.current = existing?.id ?? createUserCollectionId();
    const initialDiscover = existing?.kind === 'tmdbDiscover' ? existing : emptyDiscover(sourceId.current);
    setDiscover(initialDiscover);
    setYearFrom(initialDiscover.yearFrom != null ? String(initialDiscover.yearFrom) : '');
    setYearTo(initialDiscover.yearTo != null ? String(initialDiscover.yearTo) : '');
    setSelected(existing && existing.kind !== 'tmdbDiscover' ? existing : null);
    setCompanyText('');
    setCompanyHits([]);
    setSearchText('');
    setHits([]);
    setSearched(false);
    setSearchError(false);
    setPreview({ state: 'idle' });
  }, [kind, existing]);

  // Lists to choose from
  useEffect(() => {
    let current = true;
    if (kind === 'addonCatalog' || kind === 'traktList') {
      setListPhase('loading');
      const work: Promise<unknown> =
        kind === 'addonCatalog'
          ? getBrowsableCatalogs().then((list) => current && setCatalogs(list))
          : isTraktAvailable()
            ? fetchTraktLists().then((list) => current && setTraktLists(list))
            : Promise.resolve();
      work.then(
        () => current && setListPhase('loaded'),
        (e) => {
          console.log('[SourceEditor] list load error:', e);
          if (current) setListPhase('error');
        }
      );
    }
    return () => {
      current = false;
    };
  }, [kind]);

  // Genre ids differ between movies and TV
  useEffect(() => {
    if (kind !== 'tmdbDiscover') return;
    let current = true;
    getFlixorCore()
      .tmdb.getGenres(discover.mediaType)
      .then((list) => current && setGenres(list))
      .catch(() => current && setGenres([]));
    return () => {
      current = false;
    };
  }, [kind, discover.mediaType]);

  // Company search
  useEffect(() => {
    const query = companyText.trim();
    if (kind !== 'tmdbDiscover' || !query) {
      setCompanyHits([]);
      return;
    }
    let current = true;
    const timer = setTimeout(() => {
      getFlixorCore()
        .tmdb.searchCompanies(query)
        .then((res) => current && setCompanyHits((res.results ?? []).slice(0, 8)))
        .catch(() => current && setCompanyHits([]));
    }, DEBOUNCE_MS);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [kind, companyText]);

  // Name search for movie collections and people
  useEffect(() => {
    const query = searchText.trim();
    setSearchError(false);
    if ((kind !== 'tmdbCollection' && kind !== 'person') || !query) {
      setHits([]);
      setSearched(false);
      setSearching(false);
      return;
    }
    let current = true;
    const timer = setTimeout(async () => {
      setSearching(true);
      const tmdb = getFlixorCore().tmdb;
      try {
        let next: SearchHit[];
        if (kind === 'tmdbCollection') {
          const res = await tmdb.searchCollections(query);
          next = (res.results ?? []).map((c) => ({
            key: String(c.id),
            title: c.name,
            image: c.poster_path ? tmdb.getPosterUrl(c.poster_path, 'w185') : undefined,
            select: () =>
              setSelected({
                id: sourceId.current,
                kind: 'tmdbCollection',
                collectionId: c.id,
                name: c.name,
                posterPath: c.poster_path ?? undefined,
              }),
          }));
        } else {
          const res = await tmdb.searchPeople(query);
          next = (res.results ?? []).map((p) => ({
            key: String(p.id),
            title: p.name,
            subtitle: p.known_for_department ?? undefined,
            image: p.profile_path ? tmdb.getProfileUrl(p.profile_path, 'w185') : undefined,
            select: () =>
              setSelected({
                id: sourceId.current,
                kind: 'person',
                personId: p.id,
                name: p.name,
                profilePath: p.profile_path ?? undefined,
                credits: 'knownFor',
                order: 'popularity',
              }),
          }));
        }
        if (!current) return;
        setHits(next);
        setSearched(true);
      } catch (e) {
        console.log('[SourceEditor] search error:', e);
        if (current) {
          setHits([]);
          setSearchError(true);
        }
      } finally {
        if (current) setSearching(false);
      }
    }, DEBOUNCE_MS);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [kind, searchText]);

  const draft: UserCollectionSource | null = useMemo(() => {
    if (kind !== 'tmdbDiscover') return selected;
    const isTv = discover.mediaType === 'tv';
    return {
      ...discover,
      id: sourceId.current,
      yearFrom: parseYear(yearFrom),
      yearTo: parseYear(yearTo),
      networkId: isTv ? discover.networkId : undefined,
      networkName: isTv ? discover.networkName : undefined,
    };
  }, [kind, selected, discover, yearFrom, yearTo]);

  // A changed draft makes the old preview wrong
  const draftKey = JSON.stringify(draft);
  useEffect(() => {
    setPreview({ state: 'idle' });
  }, [draftKey]);

  const runPreview = async () => {
    if (!draft) return;
    setPreview({ state: 'loading' });
    try {
      const page = await fetchUserCollectionSourcePage(draft, undefined, 12);
      setPreview({ state: 'loaded', items: page.items });
    } catch (e: any) {
      setPreview({ state: 'failed', message: e?.message || "This source couldn't be loaded." });
    }
  };

  const updateSelectedPerson = (changes: { credits?: PersonCreditsFilter; order?: PersonCreditsOrder }) => {
    setSelected((prev) => (prev?.kind === 'person' ? { ...prev, ...changes } : prev));
  };

  const inputStyle = [styles.input, { color: theme.textPrimary, backgroundColor: theme.surfaceOverlay }];
  const heading = (text: string) => <Text style={[styles.heading, { color: theme.textSecondary }]}>{text}</Text>;

  const selectedRow = (title: string, subtitle?: string) => (
    <View style={[styles.selected, { backgroundColor: theme.accentSoft }]}>
      <Ionicons name="checkmark-circle" size={20} color={theme.accentBright} />
      <View style={{ flex: 1, marginLeft: 10 }}>
        <Text numberOfLines={1} style={{ color: theme.textPrimary, fontWeight: '600', fontSize: 15 }}>{title}</Text>
        {subtitle ? <Text numberOfLines={1} style={{ color: theme.textTertiary, fontSize: 13 }}>{subtitle}</Text> : null}
      </View>
    </View>
  );

  const pickRow = (key: string, title: string, subtitle: string | undefined, active: boolean, onPress: () => void, image?: string) => (
    <Pressable key={key} onPress={onPress} style={[styles.pick, active && { backgroundColor: theme.accentSoft }]}>
      {image ? <FastImage source={{ uri: image }} style={styles.pickImage} resizeMode={FastImage.resizeMode.cover} /> : null}
      <View style={{ flex: 1 }}>
        <Text numberOfLines={1} style={{ color: active ? theme.accentBright : theme.textPrimary, fontSize: 15, fontWeight: '500' }}>{title}</Text>
        {subtitle ? <Text numberOfLines={1} style={{ color: theme.textTertiary, fontSize: 13 }}>{subtitle}</Text> : null}
      </View>
      {active ? <Ionicons name="checkmark" size={20} color={theme.accentBright} /> : null}
    </Pressable>
  );

  const message = (text: string) => <Text style={[styles.message, { color: theme.textSecondary }]}>{text}</Text>;
  const loadingRow = (
    <View style={{ paddingVertical: 20, alignItems: 'center' }}>
      <ActivityIndicator color={theme.textPrimary} />
    </View>
  );

  const renderAddon = () => {
    if (listPhase === 'loading') return loadingRow;
    if (listPhase === 'error') return message("Couldn't read your addons.");
    if (catalogs.length === 0) return message('None of your installed addons offer a catalog.');
    return catalogs.map((c) => {
      const active =
        selected?.kind === 'addonCatalog' &&
        selected.addonId === c.addonId &&
        selected.type === c.type &&
        selected.catalogId === c.catalogId;
      return pickRow(`${c.installationId}:${c.type}:${c.catalogId}`, c.displayName, c.addonName, active, () =>
        setSelected({
          id: sourceId.current,
          kind: 'addonCatalog',
          installationId: c.installationId,
          addonId: c.addonId,
          addonName: c.addonName,
          type: c.type,
          catalogId: c.catalogId,
          displayName: c.displayName,
        })
      );
    });
  };

  const renderTrakt = () => {
    if (!isTraktAvailable()) return message('Connect Trakt in Settings to use your lists.');
    if (listPhase === 'loading') return loadingRow;
    if (listPhase === 'error') return message("Couldn't load your Trakt lists.");
    if (traktLists.length === 0) return message("You don't have any Trakt lists yet.");
    return traktLists.map((list) => {
      const active = selected?.kind === 'traktList' && selected.listId === list.ids.trakt;
      return pickRow(String(list.ids.trakt), list.name, list.item_count === 1 ? '1 title' : `${list.item_count} titles`, active, () =>
        setSelected({ id: sourceId.current, kind: 'traktList', listId: list.ids.trakt, name: list.name })
      );
    });
  };

  const renderSearch = () => (
    <>
      <TextInput
        value={searchText}
        onChangeText={setSearchText}
        placeholder={kind === 'person' ? 'Search people' : 'Search movie collections'}
        placeholderTextColor={theme.textTertiary}
        style={inputStyle}
        autoCorrect={false}
      />
      {selected?.kind === 'tmdbCollection' ? selectedRow(selected.name) : null}
      {selected?.kind === 'person' ? (
        <>
          {selectedRow(selected.name)}
          {heading('Credits')}
          <View style={styles.wrap}>
            {(Object.keys(PERSON_CREDITS_LABELS) as PersonCreditsFilter[]).map((value) => (
              <Chip key={value} label={PERSON_CREDITS_LABELS[value]} active={selected.credits === value} onPress={() => updateSelectedPerson({ credits: value })} />
            ))}
          </View>
          {heading('Order')}
          <View style={styles.wrap}>
            {(Object.keys(PERSON_ORDER_LABELS) as PersonCreditsOrder[]).map((value) => (
              <Chip key={value} label={PERSON_ORDER_LABELS[value]} active={selected.order === value} onPress={() => updateSelectedPerson({ order: value })} />
            ))}
          </View>
        </>
      ) : null}
      {searching ? loadingRow : null}
      {searchError ? message('Search failed. Check your connection and try again.') : null}
      {!searching && !searchError && searched && hits.length === 0 ? message('No matches.') : null}
      {hits.map((hit) => pickRow(hit.key, hit.title, hit.subtitle, false, hit.select, hit.image))}
    </>
  );

  const renderDiscover = () => (
    <>
      {heading('Type')}
      <View style={styles.wrap}>
        <Chip
          label="Movies"
          active={discover.mediaType === 'movie'}
          onPress={() => setDiscover((d) => (d.mediaType === 'movie' ? d : { ...d, mediaType: 'movie', genreIds: [], genreNames: [] }))}
        />
        <Chip
          label="TV Shows"
          active={discover.mediaType === 'tv'}
          onPress={() => setDiscover((d) => (d.mediaType === 'tv' ? d : { ...d, mediaType: 'tv', genreIds: [], genreNames: [] }))}
        />
      </View>

      {heading('Genres')}
      <View style={styles.wrap}>
        {genres.map((genre) => {
          const active = discover.genreIds.includes(genre.id);
          return (
            <Chip
              key={genre.id}
              label={genre.name}
              active={active}
              onPress={() =>
                setDiscover((d) =>
                  active
                    ? { ...d, genreIds: d.genreIds.filter((id) => id !== genre.id), genreNames: d.genreNames.filter((n) => n !== genre.name) }
                    : { ...d, genreIds: [...d.genreIds, genre.id], genreNames: [...d.genreNames, genre.name] }
                )
              }
            />
          );
        })}
      </View>

      {heading('Sort')}
      <View style={styles.wrap}>
        {(Object.keys(DISCOVER_SORT_LABELS) as CollectionDiscoverSort[]).map((sort) => (
          <Chip key={sort} label={DISCOVER_SORT_LABELS[sort]} active={discover.sort === sort} onPress={() => setDiscover((d) => ({ ...d, sort }))} />
        ))}
      </View>

      {heading('Years')}
      <View style={{ flexDirection: 'row', gap: 10 }}>
        <TextInput value={yearFrom} onChangeText={setYearFrom} placeholder="From" placeholderTextColor={theme.textTertiary} keyboardType="number-pad" maxLength={4} style={[inputStyle, { flex: 1 }]} />
        <TextInput value={yearTo} onChangeText={setYearTo} placeholder="To" placeholderTextColor={theme.textTertiary} keyboardType="number-pad" maxLength={4} style={[inputStyle, { flex: 1 }]} />
      </View>

      {heading('Production company')}
      {discover.companyId != null ? (
        <View style={styles.wrap}>
          <Chip label={`${discover.companyName ?? 'Company'}  ×`} active onPress={() => setDiscover((d) => ({ ...d, companyId: undefined, companyName: undefined }))} />
        </View>
      ) : (
        <>
          <TextInput value={companyText} onChangeText={setCompanyText} placeholder="Search companies" placeholderTextColor={theme.textTertiary} style={inputStyle} autoCorrect={false} />
          {companyHits.map((company) =>
            pickRow(String(company.id), company.name, undefined, false, () => {
              setDiscover((d) => ({ ...d, companyId: company.id, companyName: company.name }));
              setCompanyText('');
              setCompanyHits([]);
            })
          )}
        </>
      )}

      {discover.mediaType === 'tv' ? (
        <>
          {heading('Network')}
          <View style={styles.wrap}>
            <Chip label="Any" active={discover.networkId == null} onPress={() => setDiscover((d) => ({ ...d, networkId: undefined, networkName: undefined }))} />
            {KNOWN_NETWORKS.map((network) => (
              <Chip
                key={network.id}
                label={network.name}
                active={discover.networkId === network.id}
                onPress={() => setDiscover((d) => ({ ...d, networkId: network.id, networkName: network.name }))}
              />
            ))}
          </View>
        </>
      ) : null}
    </>
  );

  return (
    <Modal visible={kind !== null} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        style={{ flex: 1, backgroundColor: theme.surfaceElevated, paddingTop: Platform.OS === 'android' ? insets.top : 0 }}
      >
        <View style={[styles.bar, { borderBottomColor: theme.separator }]}>
          <Pressable onPress={onClose} hitSlop={8}>
            <Text style={{ color: theme.textPrimary, fontSize: 16 }}>Cancel</Text>
          </Pressable>
          <Text numberOfLines={1} style={[styles.barTitle, { color: theme.textPrimary }]}>
            {kind ? SOURCE_KIND_LABELS[kind] : ''}
          </Text>
          <Pressable
            disabled={!draft}
            onPress={() => {
              if (draft) {
                onSave(draft);
                onClose();
              }
            }}
            hitSlop={8}
          >
            <Text style={{ color: draft ? theme.accentBright : theme.textDisabled, fontSize: 16, fontWeight: '700' }}>Done</Text>
          </Pressable>
        </View>

        <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: insets.bottom + 32 }} keyboardShouldPersistTaps="handled">
          {kind === 'addonCatalog' ? renderAddon() : null}
          {kind === 'traktList' ? renderTrakt() : null}
          {kind === 'tmdbCollection' || kind === 'person' ? renderSearch() : null}
          {kind === 'tmdbDiscover' ? renderDiscover() : null}

          {draft ? (
            <View style={{ marginTop: 20 }}>
              <Pressable onPress={runPreview} style={[styles.previewButton, { backgroundColor: theme.surfaceOverlay }]}>
                <Text style={{ color: theme.textPrimary, fontWeight: '600' }}>Preview</Text>
              </Pressable>
              {preview.state === 'loading' ? loadingRow : null}
              {preview.state === 'failed' ? message(preview.message) : null}
              {preview.state === 'loaded' && preview.items.length === 0 ? message('Nothing here right now.') : null}
              {preview.state === 'loaded' && preview.items.length > 0 ? (
                <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 12 }}>
                  {preview.items.map((item) => (
                    <View key={item.id} style={[styles.previewPoster, { backgroundColor: theme.surface }]}>
                      {item.image ? <FastImage source={{ uri: item.image }} style={StyleSheet.absoluteFill} resizeMode={FastImage.resizeMode.cover} /> : null}
                    </View>
                  ))}
                </ScrollView>
              ) : null}
            </View>
          ) : null}
        </ScrollView>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  bar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 14, borderBottomWidth: StyleSheet.hairlineWidth },
  barTitle: { fontSize: 16, fontWeight: '700', flex: 1, textAlign: 'center', marginHorizontal: 12 },
  heading: { fontSize: 13, fontWeight: '600', marginTop: 14, marginBottom: 8 },
  wrap: { flexDirection: 'row', flexWrap: 'wrap' },
  input: { borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16, marginBottom: 8 },
  message: { fontSize: 14, paddingVertical: 12, textAlign: 'center' },
  selected: { flexDirection: 'row', alignItems: 'center', padding: 12, borderRadius: 10, marginBottom: 8 },
  pick: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 10, paddingVertical: 10, borderRadius: 10 },
  pickImage: { width: 36, height: 54, borderRadius: 4, marginRight: 10 },
  previewButton: { alignItems: 'center', paddingVertical: 12, borderRadius: 10 },
  previewPoster: { width: 80, height: 120, borderRadius: 6, overflow: 'hidden', marginRight: 8 },
});
