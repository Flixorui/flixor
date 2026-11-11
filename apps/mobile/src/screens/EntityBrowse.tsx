import React, { useCallback, useEffect, useRef, useState } from 'react';
import {Animated, ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useFocusEffect, useNavigation, useRoute } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import FastImage from '@d11/react-native-fast-image';
import SettingsHeader from '../components/settings/SettingsHeader';
import { TopBarStore } from '../components/TopBarStore';
import MediaGrid from '../components/collections/MediaGrid';
import { openDetails } from '../components/collections/openDetails';
import Chip from '../components/collections/Chip';
import { KNOWN_NETWORKS } from '../components/collections/SourceEditor';
import { useTheme } from '../hooks/useTheme';
import { getFlixorCore } from '../core';
import {
  createUserCollectionId,
  fetchUserCollectionSourcePage,
  userCollectionItemRoute,
  type CollectionDiscoverSort,
  type UserCollectionItem,
  type UserCollectionSource,
} from '../core/UserCollectionsStore';

export type EntityBrowseParams = {
  kind?: 'company' | 'network' | 'collection';
  id?: number;
  name?: string;
};

type Kind = NonNullable<EntityBrowseParams['kind']>;

const SORTS: Array<{ value: CollectionDiscoverSort; label: string }> = [
  { value: 'popularity', label: 'Popular' },
  { value: 'rating', label: 'Top Rated' },
  { value: 'newest', label: 'Newest' },
];

interface EntityInfo {
  name?: string;
  subtitle: string;
  description?: string;
  logo?: string;
  backdrop?: string;
}

async function fetchEntityInfo(kind: Kind, id: number): Promise<EntityInfo> {
  const tmdb = getFlixorCore().tmdb;
  if (kind === 'collection') {
    const details = await tmdb.getCollectionDetails(id);
    const count = details.parts?.length ?? 0;
    return {
      name: details.name,
      subtitle: count === 1 ? '1 movie' : `${count} movies`,
      description: details.overview ?? undefined,
      backdrop: details.backdrop_path ? tmdb.getBackdropUrl(details.backdrop_path, 'w1280') : undefined,
    };
  }
  const details = kind === 'network' ? await tmdb.getNetworkDetails(id) : await tmdb.getCompanyDetails(id);
  const place = details.headquarters || details.origin_country;
  return {
    name: details.name,
    subtitle: [kind === 'network' ? 'TV network' : 'Production company', place].filter(Boolean).join(' · '),
    description: details.description || undefined,
    logo: details.logo_path ? tmdb.getImageUrl(details.logo_path, 'w500') : undefined,
  };
}

function EntityGrid({ kind, id, name }: { kind: Kind; id: number; name?: string }) {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const theme = useTheme();

  const [info, setInfo] = useState<EntityInfo | null>(null);
  const [mediaType, setMediaType] = useState<'movie' | 'tv'>(kind === 'network' ? 'tv' : 'movie');
  const [sort, setSort] = useState<CollectionDiscoverSort>('popularity');
  const [items, setItems] = useState<UserCollectionItem[]>([]);
  const [total, setTotal] = useState<number | undefined>();
  const [phase, setPhase] = useState<'loading' | 'loaded' | 'error'>('loading');
  const [loadingMore, setLoadingMore] = useState(false);
  const [pagingError, setPagingError] = useState(false);

  const cursor = useRef<number | undefined>(undefined);
  const busy = useRef(false);
  const seen = useRef(new Set<string>());
  const generation = useRef(0);
  // A company that mostly makes TV switches to TV once if it has no movies
  const didAutoSwitch = useRef(false);

  const buildSource = useCallback((): UserCollectionSource => {
    const sourceId = createUserCollectionId();
    if (kind === 'collection') {
      return { id: sourceId, kind: 'tmdbCollection', collectionId: id, name: name ?? '' };
    }
    return {
      id: sourceId,
      kind: 'tmdbDiscover',
      mediaType,
      genreIds: [],
      genreNames: [],
      sort,
      companyId: kind === 'company' ? id : undefined,
      networkId: kind === 'network' ? id : undefined,
    };
  }, [id, kind, mediaType, name, sort]);

  const loadPage = useCallback(
    async (next?: number) => {
      const current = generation.current;
      busy.current = true;
      try {
        const page = await fetchUserCollectionSourcePage(buildSource(), next);
        if (current !== generation.current) return;

        if (next === undefined && page.items.length === 0 && kind === 'company' && mediaType === 'movie' && !didAutoSwitch.current) {
          didAutoSwitch.current = true;
          busy.current = false;
          setMediaType('tv');
          return;
        }

        const fresh = page.items.filter((item) => {
          if (seen.current.has(item.id)) return false;
          seen.current.add(item.id);
          return true;
        });
        cursor.current = page.nextCursor;
        setItems((prev) => (next === undefined ? fresh : [...prev, ...fresh]));
        if (page.totalResults !== undefined) setTotal(page.totalResults);
        setPagingError(false);
        setPhase('loaded');
      } catch (e) {
        if (current !== generation.current) return;
        console.log('[EntityBrowse] load error:', e);
        if (next === undefined) setPhase('error');
        else setPagingError(true);
      } finally {
        if (current === generation.current) {
          busy.current = false;
          setLoadingMore(false);
        }
      }
    },
    [buildSource, kind, mediaType]
  );

  const reload = useCallback(() => {
    generation.current += 1;
    cursor.current = undefined;
    seen.current = new Set();
    setItems([]);
    setTotal(undefined);
    setPagingError(false);
    setLoadingMore(false);
    setPhase('loading');
    void loadPage();
  }, [loadPage]);

  useEffect(() => {
    reload();
  }, [reload]);

  useEffect(() => {
    let current = true;
    fetchEntityInfo(kind, id)
      .then((result) => {
        if (current) setInfo(result);
      })
      .catch((e) => console.log('[EntityBrowse] details error:', e));
    return () => {
      current = false;
    };
  }, [kind, id]);

  const loadMore = useCallback(() => {
    if (busy.current || cursor.current === undefined) return;
    setLoadingMore(true);
    void loadPage(cursor.current);
  }, [loadPage]);

  const onPressItem = useCallback(
    (item: UserCollectionItem) => openDetails(nav, userCollectionItemRoute(item)),
    [nav]
  );

  const title = info?.name || name || 'Browse';
  const countText =
    total != null && total > 0
      ? `${total.toLocaleString()} ${mediaType === 'movie' ? (total === 1 ? 'movie' : 'movies') : total === 1 ? 'show' : 'shows'}`
      : null;

  const header = (
    <View style={styles.header}>
      {info?.backdrop ? (
        <View style={styles.backdrop}>
          <FastImage source={{ uri: info.backdrop, cache: FastImage.cacheControl.immutable }} style={StyleSheet.absoluteFillObject} resizeMode={FastImage.resizeMode.cover} />
        </View>
      ) : null}
      {info?.logo ? (
        <View style={styles.logoPlate}>
          <FastImage source={{ uri: info.logo, cache: FastImage.cacheControl.immutable }} style={StyleSheet.absoluteFillObject} resizeMode={FastImage.resizeMode.contain} />
        </View>
      ) : null}
      {info ? <Text style={[styles.subtitle, { color: theme.textSecondary }]}>{[info.subtitle, kind === 'collection' ? null : countText].filter(Boolean).join(' · ')}</Text> : null}
      {info?.description ? (
        <Text numberOfLines={4} style={[styles.description, { color: theme.textTertiary }]}>
          {info.description}
        </Text>
      ) : null}
      {kind !== 'collection' ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 12 }}>
          {kind === 'company' ? (
            <>
              <Chip label="Movies" active={mediaType === 'movie'} onPress={() => setMediaType('movie')} />
              <Chip label="TV Shows" active={mediaType === 'tv'} onPress={() => setMediaType('tv')} />
            </>
          ) : null}
          {SORTS.map((option) => (
            <Chip key={option.value} label={option.label} active={sort === option.value} onPress={() => setSort(option.value)} />
          ))}
        </ScrollView>
      ) : null}
    </View>
  );

  const empty =
    phase === 'loading' ? (
      <View style={styles.centerInline}>
        <ActivityIndicator color={theme.textPrimary} />
      </View>
    ) : phase === 'error' ? (
      <View style={styles.centerInline}>
        <Ionicons name="cloud-offline-outline" size={36} color={theme.textTertiary} />
        <Text style={[styles.message, { color: theme.textSecondary }]}>Couldn't load titles.</Text>
        <Pressable onPress={reload} style={[styles.retry, { backgroundColor: theme.surfaceOverlay }]}>
          <Text style={{ color: theme.textPrimary, fontWeight: '600' }}>Try Again</Text>
        </Pressable>
      </View>
    ) : (
      <View style={styles.centerInline}>
        <Ionicons name="film-outline" size={36} color={theme.textTertiary} />
        <Text style={[styles.message, { color: theme.textSecondary }]}>No titles found.</Text>
      </View>
    );

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <MediaGrid
        items={items}
        onPress={onPressItem}
        header={header}
        empty={empty}
        onEndReached={loadMore}
        loadingMore={loadingMore}
        footer={
          pagingError ? (
            <Pressable onPress={loadMore} style={styles.pagingRetry}>
              <Text style={{ color: theme.textSecondary, fontWeight: '600' }}>Couldn't load more. Tap to retry.</Text>
            </Pressable>
          ) : null
        }
        paddingTop={insets.top + 60}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
        paddingBottom={insets.bottom + 40}
      />
      <SettingsHeader scrollY={headerScrollY} title={title} onBack={() => nav.goBack()} />
    </View>
  );
}

function EntityLanding() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const [text, setText] = useState('');
  const [companies, setCompanies] = useState<Array<{ id: number; name: string; origin_country?: string | null }>>([]);
  const [searching, setSearching] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const query = text.trim();
    setFailed(false);
    if (!query) {
      setCompanies([]);
      setSearching(false);
      return;
    }
    let current = true;
    setSearching(true);
    const timer = setTimeout(() => {
      getFlixorCore()
        .tmdb.searchCompanies(query)
        .then((res) => current && setCompanies((res.results ?? []).slice(0, 20)))
        .catch(() => {
          if (current) {
            setCompanies([]);
            setFailed(true);
          }
        })
        .finally(() => current && setSearching(false));
    }, 350);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [text]);

  const open = (kind: Kind, id: number, name: string) => nav.push('EntityBrowse', { kind, id, name });

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <Animated.ScrollView scrollEventThrottle={16} onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
        contentContainerStyle={{ paddingTop: insets.top + 64, paddingHorizontal: 16, paddingBottom: insets.bottom + 40 }}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
      >
        <Text style={[styles.sectionTitle, { color: theme.textPrimary }]}>Studios</Text>
        <TextInput
          value={text}
          onChangeText={setText}
          placeholder="Search production companies"
          placeholderTextColor={theme.textTertiary}
          autoCorrect={false}
          style={[styles.input, { color: theme.textPrimary, backgroundColor: theme.surfaceOverlay }]}
        />
        {searching ? <ActivityIndicator color={theme.textPrimary} style={{ marginVertical: 12 }} /> : null}
        {failed ? <Text style={[styles.message, { color: theme.textSecondary }]}>Search failed. Try again.</Text> : null}
        {!searching && !failed && text.trim() && companies.length === 0 ? (
          <Text style={[styles.message, { color: theme.textSecondary }]}>No matches.</Text>
        ) : null}
        {companies.map((company) => (
          <Pressable key={company.id} onPress={() => open('company', company.id, company.name)} style={styles.companyRow}>
            <Text numberOfLines={1} style={{ color: theme.textPrimary, fontSize: 16, flex: 1 }}>
              {company.name}
            </Text>
            {company.origin_country ? <Text style={{ color: theme.textTertiary, fontSize: 13, marginRight: 8 }}>{company.origin_country}</Text> : null}
            <Ionicons name="chevron-forward" size={18} color={theme.textTertiary} />
          </Pressable>
        ))}

        <Text style={[styles.sectionTitle, { color: theme.textPrimary, marginTop: 24 }]}>Networks</Text>
        <View style={styles.wrap}>
          {KNOWN_NETWORKS.map((network) => (
            <Chip key={network.id} label={network.name} onPress={() => open('network', network.id, network.name)} />
          ))}
        </View>
      </Animated.ScrollView>
      <SettingsHeader scrollY={headerScrollY} title="Studios & Networks" onBack={() => nav.goBack()} />
    </View>
  );
}

/** Titles from a production company, TV network or TMDB movie collection. */
export default function EntityBrowse() {
  const route: any = useRoute();
  const params: EntityBrowseParams = route.params ?? {};

  useFocusEffect(
    useCallback(() => {
      TopBarStore.setVisible(false);
    }, [])
  );

  return params.kind && params.id != null ? (
    <EntityGrid key={`${params.kind}:${params.id}`} kind={params.kind} id={Number(params.id)} name={params.name} />
  ) : (
    <EntityLanding />
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  header: { paddingHorizontal: 8, paddingBottom: 10 },
  backdrop: { height: 170, borderRadius: 12, overflow: 'hidden', marginBottom: 12 },
  logoPlate: { height: 72, width: 180, marginBottom: 12 },
  subtitle: { fontSize: 13, fontWeight: '600' },
  description: { fontSize: 13, lineHeight: 19, marginTop: 6 },
  centerInline: { alignItems: 'center', paddingTop: 60, paddingHorizontal: 32 },
  message: { fontSize: 15, marginTop: 10, textAlign: 'center' },
  retry: { marginTop: 14, paddingHorizontal: 18, paddingVertical: 10, borderRadius: 10 },
  pagingRetry: { paddingVertical: 20, alignItems: 'center' },
  sectionTitle: { fontSize: 18, fontWeight: '700', marginBottom: 10 },
  input: { borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16 },
  companyRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12 },
  wrap: { flexDirection: 'row', flexWrap: 'wrap' },
});
