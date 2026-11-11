import React, { useCallback, useEffect, useRef, useState } from 'react';
import {Animated, ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect, useNavigation, useRoute } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../components/settings/SettingsHeader';
import { TopBarStore } from '../components/TopBarStore';
import MediaGrid from '../components/collections/MediaGrid';
import { openDetails } from '../components/collections/openDetails';
import UserCollectionsSection from '../components/collections/UserCollectionsSection';
import UserCollectionEditor from './UserCollectionEditor';
import { useTheme } from '../hooks/useTheme';
import { UserCollectionDeduper, userCollectionSourceErrorMessage } from '../core/UserCollectionResolver';
import {
  fetchUserCollectionSourcePage,
  sourceTitle,
  useUserCollection,
  useUserCollections,
  userCollectionContentKey,
  userCollectionItemRoute,
  userCollectionSummary,
  type UserCollection as UserCollectionModel,
  type UserCollectionItem,
  type UserCollectionPreviewFailure,
  type UserCollectionSource,
} from '../core/UserCollectionsStore';

export type UserCollectionParams = {
  collectionId?: string;
  title?: string;
};

interface SourceState {
  source: UserCollectionSource;
  cursor?: number;
  finished: boolean;
  failed: boolean;
}

/** Pages a collection's sources into one grid. A failed source is reported and left out. */
function useCollectionFeed(collection: UserCollectionModel | undefined) {
  const [items, setItems] = useState<UserCollectionItem[]>([]);
  const [phase, setPhase] = useState<'loading' | 'loaded'>('loading');
  const [loadingMore, setLoadingMore] = useState(false);
  const [failures, setFailures] = useState<UserCollectionPreviewFailure[]>([]);

  const states = useRef<SourceState[]>([]);
  const deduper = useRef(new UserCollectionDeduper());
  const busy = useRef(false);
  const generation = useRef(0);
  const hasItems = useRef(false);

  const loadNext = useCallback(async () => {
    if (busy.current) return;
    const targets = states.current.filter((s) => !s.finished && !s.failed);
    if (targets.length === 0) {
      setPhase('loaded');
      return;
    }

    busy.current = true;
    setLoadingMore(hasItems.current);
    const current = generation.current;
    const results = await Promise.allSettled(
      targets.map((s) => fetchUserCollectionSourcePage(s.source, s.cursor))
    );
    if (current !== generation.current) return;

    // Applied in source order, so reordering sources reorders the grid
    const added: UserCollectionItem[] = [];
    const failed: UserCollectionPreviewFailure[] = [];
    results.forEach((result, index) => {
      const state = targets[index];
      if (result.status === 'fulfilled') {
        const fresh = result.value.items.filter((item) => deduper.current.insert(item));
        added.push(...fresh);
        state.cursor = result.value.nextCursor;
        // No new titles means the source is done, or ignores paging
        state.finished = result.value.nextCursor === undefined || fresh.length === 0;
      } else {
        state.failed = true;
        failed.push({
          sourceId: state.source.id,
          sourceTitle: sourceTitle(state.source),
          message: userCollectionSourceErrorMessage(result.reason),
        });
      }
    });

    hasItems.current = hasItems.current || added.length > 0;
    setItems((prev) => [...prev, ...added]);
    if (failed.length > 0) setFailures((prev) => [...prev, ...failed]);
    busy.current = false;
    setLoadingMore(false);
    setPhase('loaded');
  }, []);

  const restart = useCallback(
    (sources: UserCollectionSource[]) => {
      generation.current += 1;
      states.current = sources.map((source) => ({ source, finished: false, failed: false }));
      deduper.current = new UserCollectionDeduper();
      busy.current = false;
      hasItems.current = false;
      setItems([]);
      setFailures([]);
      setLoadingMore(false);
      setPhase('loading');
      void loadNext();
    },
    [loadNext]
  );

  const contentKey = collection ? userCollectionContentKey(collection) : '';
  useEffect(() => {
    if (collection) restart(collection.sources);
    // contentKey stands in for the sources; renames must not reload the grid
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [contentKey, restart]);

  const retryFailed = useCallback(() => {
    states.current.forEach((s) => {
      s.failed = false;
    });
    setFailures([]);
    if (!hasItems.current) setPhase('loading');
    void loadNext();
  }, [loadNext]);

  return { items, phase, loadingMore, failures, loadMore: loadNext, retryFailed };
}

function CollectionDetail({ collectionId, fallbackTitle }: { collectionId: string; fallbackTitle?: string }) {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const { isLoaded } = useUserCollections();
  const collection = useUserCollection(collectionId);
  const feed = useCollectionFeed(collection);
  const [editing, setEditing] = useState(false);

  const onPressItem = useCallback(
    (item: UserCollectionItem) => openDetails(nav, userCollectionItemRoute(item)),
    [nav]
  );

  const title = collection?.name ?? fallbackTitle ?? 'Collection';

  if (isLoaded && !collection) {
    return (
      <View style={[styles.container, { backgroundColor: theme.background }]}>
        <SettingsHeader scrollY={headerScrollY} title={title} onBack={() => nav.goBack()} />
        <View style={[styles.center, { paddingTop: insets.top + 52 }]}>
          <Ionicons name="albums-outline" size={40} color={theme.textTertiary} />
          <Text style={[styles.message, { color: theme.textSecondary }]}>This collection no longer exists.</Text>
        </View>
      </View>
    );
  }

  const header = (
    <View style={styles.header}>
      <View style={styles.headerRow}>
        <Text style={[styles.summary, { color: theme.textSecondary }]}>
          {collection ? userCollectionSummary(collection) : ''}
        </Text>
        {collection ? (
          <Pressable onPress={() => setEditing(true)} hitSlop={8} style={styles.edit}>
            <Ionicons name="create-outline" size={18} color={theme.accentBright} />
            <Text style={{ color: theme.accentBright, fontWeight: '600', marginLeft: 4 }}>Edit</Text>
          </Pressable>
        ) : null}
      </View>
      {feed.failures.length > 0 ? (
        <View style={[styles.failures, { backgroundColor: theme.surfaceOverlay }]}>
          {feed.failures.map((failure) => (
            <Text key={failure.sourceId} style={{ color: theme.textSecondary, fontSize: 13, marginBottom: 4 }}>
              {failure.sourceTitle}: {failure.message}
            </Text>
          ))}
          <Pressable onPress={feed.retryFailed} hitSlop={6}>
            <Text style={{ color: theme.accentBright, fontWeight: '600', marginTop: 2 }}>Try Again</Text>
          </Pressable>
        </View>
      ) : null}
    </View>
  );

  const empty =
    !isLoaded || feed.phase === 'loading' ? (
      <View style={styles.centerInline}>
        <ActivityIndicator color={theme.textPrimary} />
      </View>
    ) : (
      <View style={styles.centerInline}>
        <Ionicons name="albums-outline" size={40} color={theme.textTertiary} />
        <Text style={[styles.message, { color: theme.textSecondary }]}>
          {feed.failures.length > 0 ? "These sources couldn't be loaded." : 'Nothing in this collection right now.'}
        </Text>
      </View>
    );

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <MediaGrid
        items={feed.items}
        onPress={onPressItem}
        header={header}
        empty={empty}
        onEndReached={feed.loadMore}
        loadingMore={feed.loadingMore}
        paddingTop={insets.top + 60}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
        paddingBottom={insets.bottom + 40}
      />
      <SettingsHeader scrollY={headerScrollY} title={title} onBack={() => nav.goBack()} />
      <UserCollectionEditor visible={editing} collection={collection} onClose={() => setEditing(false)} />
    </View>
  );
}

function CollectionsOverview() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const theme = useTheme();

  return (
    <View style={[styles.container, { backgroundColor: theme.background }]}>
      <Animated.ScrollView scrollEventThrottle={16} onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })} contentContainerStyle={{ paddingTop: insets.top + 64, paddingBottom: insets.bottom + 40 }}>
        <UserCollectionsSection />
      </Animated.ScrollView>
      <SettingsHeader scrollY={headerScrollY} title="Your Collections" onBack={() => nav.goBack()} />
    </View>
  );
}

/** A user collection's page, or the list of all of them when opened with no id. */
export default function UserCollection() {
  const route: any = useRoute();
  const params: UserCollectionParams = route.params ?? {};

  useFocusEffect(
    useCallback(() => {
      TopBarStore.setVisible(false);
    }, [])
  );

  return params.collectionId ? (
    <CollectionDetail collectionId={params.collectionId} fallbackTitle={params.title} />
  ) : (
    <CollectionsOverview />
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 32 },
  centerInline: { alignItems: 'center', paddingTop: 80, paddingHorizontal: 32 },
  message: { fontSize: 15, marginTop: 10, textAlign: 'center' },
  header: { paddingHorizontal: 8, paddingBottom: 10 },
  headerRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  summary: { fontSize: 13, fontWeight: '600' },
  edit: { flexDirection: 'row', alignItems: 'center' },
  failures: { borderRadius: 10, padding: 12, marginTop: 10 },
});
