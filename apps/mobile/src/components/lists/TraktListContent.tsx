import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import MediaGrid from '../collections/MediaGrid';
import { useTheme } from '../../hooks/useTheme';
import { showToast } from '../Toast';
import {
  TRAKT_LIST_PRIVACY_OPTIONS,
  deleteTraktList,
  fetchTraktListContents,
  removeTitleFromTraktList,
  traktListErrorMessage,
  type TraktListGridItem,
  type TraktUserList,
} from '../../core/TraktListsData';
import type { FilterOption, SortOption } from '../../core/MyListData';

/** One Trakt list as a grid, with edit, delete and remove. */
export default function TraktListContent({
  list,
  filter,
  sort,
  switcher,
  paddingTop,
  onScroll,
  onPressItem,
  onAddToList,
  onEdit,
  onDeleted,
  onCountChanged,
}: {
  list: TraktUserList;
  filter: FilterOption;
  sort: SortOption;
  /** The list chooser, rendered at the top of the grid. */
  switcher: React.ReactElement;
  paddingTop: number;
  onScroll?: (event: any) => void;
  onPressItem: (item: TraktListGridItem) => void;
  onAddToList: (item: TraktListGridItem) => void;
  onEdit: () => void;
  onDeleted: () => void;
  onCountChanged: (listId: number, count: number) => void;
}) {
  const theme = useTheme();
  const listId = list.ids.trakt;
  const [items, setItems] = useState<TraktListGridItem[]>([]);
  const [hiddenCount, setHiddenCount] = useState(0);
  const [phase, setPhase] = useState<'loading' | 'loaded' | 'error'>('loading');
  const [errorMessage, setErrorMessage] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(
    async (isCurrent: () => boolean = () => true) => {
      try {
        const contents = await fetchTraktListContents(listId);
        if (!isCurrent()) return;
        setItems(contents.items);
        setHiddenCount(contents.hiddenCount);
        setPhase('loaded');
        onCountChanged(listId, contents.items.length + contents.hiddenCount);
      } catch (e) {
        if (!isCurrent()) return;
        console.log('[TraktListContent] load error:', e);
        setErrorMessage(traktListErrorMessage(e, "Couldn't load this list."));
        setPhase('error');
      }
    },
    [listId, onCountChanged]
  );

  useEffect(() => {
    let current = true;
    setItems([]);
    setHiddenCount(0);
    setPhase('loading');
    void load(() => current);
    return () => {
      current = false;
    };
  }, [load]);

  const visible = useMemo(() => {
    const filtered = items.filter(
      (item) => filter === 'all' || (filter === 'movies' ? item.type === 'movie' : item.type === 'show')
    );
    return [...filtered].sort((a, b) => {
      if (sort === 'title') return a.title.localeCompare(b.title);
      if (sort === 'year') return (b.year ?? 0) - (a.year ?? 0);
      return new Date(b.listedAt ?? 0).getTime() - new Date(a.listedAt ?? 0).getTime();
    });
  }, [items, filter, sort]);

  const refresh = useCallback(async () => {
    setRefreshing(true);
    await load();
    setRefreshing(false);
  }, [load]);

  const remove = useCallback(
    async (item: TraktListGridItem) => {
      try {
        const removed = await removeTitleFromTraktList(listId, item);
        if (!removed) {
          showToast("Couldn't remove this title.", { kind: 'error' });
          return;
        }
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        const next = items.filter((other) => other.entryId !== item.entryId);
        setItems(next);
        onCountChanged(listId, next.length + hiddenCount);
        showToast(`Removed from ${list.name}`, { kind: 'success' });
      } catch (e) {
        console.log('[TraktListContent] remove error:', e);
        showToast(traktListErrorMessage(e, "Couldn't remove this title."), { kind: 'error' });
      }
    },
    [hiddenCount, items, list.name, listId, onCountChanged]
  );

  const showItemMenu = useCallback(
    (item: TraktListGridItem) => {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      Alert.alert(item.title, undefined, [
        { text: 'Add to Another List', onPress: () => onAddToList(item) },
        { text: `Remove from ${list.name}`, style: 'destructive', onPress: () => void remove(item) },
        { text: 'Cancel', style: 'cancel' },
      ]);
    },
    [list.name, onAddToList, remove]
  );

  const confirmDelete = () => {
    Alert.alert('Delete List', `Delete "${list.name}" from Trakt? This can't be undone.`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          try {
            await deleteTraktList(listId);
            showToast(`Deleted ${list.name}`, { kind: 'success' });
            onDeleted();
          } catch (e) {
            console.log('[TraktListContent] delete error:', e);
            showToast(traktListErrorMessage(e, "Couldn't delete this list."), { kind: 'error' });
          }
        },
      },
    ]);
  };

  const privacy = TRAKT_LIST_PRIVACY_OPTIONS.find((o) => o.value === list.privacy)?.label;
  const count = phase === 'loaded' ? items.length : list.item_count;
  const summary = [
    count === 1 ? '1 title' : `${count} titles`,
    hiddenCount > 0 ? (hiddenCount === 1 ? '1 item not shown' : `${hiddenCount} items not shown`) : null,
    privacy,
  ]
    .filter(Boolean)
    .join(' · ');

  const header = (
    <View>
      {switcher}
      <View style={styles.header}>
        <View style={{ flex: 1 }}>
          <Text style={[styles.summary, { color: theme.textSecondary }]}>{summary}</Text>
          {list.description ? (
            <Text numberOfLines={3} style={[styles.description, { color: theme.textTertiary }]}>
              {list.description}
            </Text>
          ) : null}
        </View>
        <Pressable onPress={onEdit} hitSlop={8} style={styles.icon} accessibilityLabel="Edit list">
          <Ionicons name="create-outline" size={22} color={theme.textPrimary} />
        </Pressable>
        <Pressable onPress={confirmDelete} hitSlop={8} style={styles.icon} accessibilityLabel="Delete list">
          <Ionicons name="trash-outline" size={21} color={theme.danger} />
        </Pressable>
      </View>
    </View>
  );

  const empty =
    phase === 'loading' ? (
      <View style={styles.center}>
        <ActivityIndicator color={theme.textPrimary} />
      </View>
    ) : phase === 'error' ? (
      <View style={styles.center}>
        <Text style={[styles.message, { color: theme.textSecondary }]}>{errorMessage}</Text>
        <Pressable onPress={() => { setPhase('loading'); void load(); }} style={[styles.retry, { backgroundColor: theme.surfaceOverlay }]}>
          <Text style={{ color: theme.textPrimary, fontWeight: '600' }}>Try Again</Text>
        </Pressable>
      </View>
    ) : (
      <View style={styles.center}>
        <Ionicons name="list-outline" size={40} color={theme.textDisabled} />
        <Text style={[styles.message, { color: theme.textSecondary }]}>
          {items.length > 0 ? 'Nothing matches this filter.' : 'This list is empty.'}
        </Text>
      </View>
    );

  return (
    <MediaGrid
      items={visible}
      onPress={onPressItem}
      onLongPress={showItemMenu}
      header={header}
      empty={empty}
      paddingTop={paddingTop}
      onScroll={onScroll}
      refreshing={refreshing}
      onRefresh={refresh}
    />
  );
}

const styles = StyleSheet.create({
  header: { flexDirection: 'row', alignItems: 'flex-start', paddingHorizontal: 8, paddingTop: 6, paddingBottom: 10 },
  summary: { fontSize: 13, fontWeight: '600' },
  description: { fontSize: 13, marginTop: 3 },
  icon: { paddingLeft: 14, paddingVertical: 2 },
  center: { alignItems: 'center', paddingTop: 60, paddingHorizontal: 32 },
  message: { fontSize: 15, marginTop: 10, textAlign: 'center' },
  retry: { marginTop: 14, paddingHorizontal: 18, paddingVertical: 10, borderRadius: 10 },
});
