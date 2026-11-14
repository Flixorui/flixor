import React, { useEffect, useState } from 'react';
import { Alert, Dimensions, Pressable, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import * as Haptics from 'expo-haptics';
import { useTheme } from '../../hooks/useTheme';
import { showToast } from '../Toast';
import OptionSheet from './OptionSheet';
import UserCollectionEditor from '../../screens/UserCollectionEditor';
import {
  deleteUserCollection,
  fetchUserCollectionPreview,
  getCachedUserCollectionPreview,
  setUserCollectionShowOnHome,
  useUserCollections,
  userCollectionSummary,
  type UserCollection,
} from '../../core/UserCollectionsStore';

function CollectionCard({
  collection,
  width,
  onPress,
  onLongPress,
}: {
  collection: UserCollection;
  width: number;
  onPress: () => void;
  onLongPress: () => void;
}) {
  const theme = useTheme();
  const cached = getCachedUserCollectionPreview(collection)?.items.find((item) => item.backdrop)?.backdrop;
  const [fallback, setFallback] = useState<string | undefined>(cached);

  useEffect(() => {
    if (collection.cover || collection.sources.length === 0) return;
    let current = true;
    fetchUserCollectionPreview(collection).then((preview) => {
      if (current) setFallback(preview.items.find((item) => item.backdrop)?.backdrop);
    });
    return () => {
      current = false;
    };
    // The cover only depends on what the sources are
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [collection.cover, JSON.stringify(collection.sources)]);

  const image = collection.cover?.url ?? fallback;

  return (
    <Pressable onPress={onPress} onLongPress={onLongPress} style={{ width }}>
      <View style={[styles.cover, { height: Math.round(width * 0.6), backgroundColor: theme.surface }]}>
        {image ? (
          <FastImage
            source={{ uri: image, cache: FastImage.cacheControl.immutable }}
            style={StyleSheet.absoluteFill}
            resizeMode={FastImage.resizeMode.cover}
          />
        ) : (
          <Ionicons name="albums-outline" size={32} color={theme.textDisabled} />
        )}
        {collection.showOnHome ? (
          <View style={[styles.homeBadge, { backgroundColor: theme.accent }]}>
            <Ionicons name="home" size={11} color={theme.onAccent} />
          </View>
        ) : null}
      </View>
      <Text numberOfLines={1} style={[styles.name, { color: theme.textPrimary }]}>
        {collection.name}
      </Text>
      <Text style={[styles.summary, { color: theme.textTertiary }]}>{userCollectionSummary(collection)}</Text>
    </Pressable>
  );
}

/** The user's own collections: browse, create, edit, delete, and choose Home rows. */
export default function UserCollectionsSection({ horizontalInset = 12 }: { horizontalInset?: number }) {
  const nav: any = useNavigation();
  const theme = useTheme();
  const { collections } = useUserCollections();
  const [editor, setEditor] = useState<{ collection: UserCollection | null } | null>(null);
  const [menuFor, setMenuFor] = useState<UserCollection | null>(null);

  const screenWidth = Dimensions.get('window').width;
  const columns = screenWidth >= 800 ? 3 : 2;
  const cardWidth = Math.floor((screenWidth - horizontalInset * 2 - (columns - 1) * 12) / columns);

  const showMenu = (collection: UserCollection) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    setMenuFor(collection);
  };

  const runMenuAction = (action: 'edit' | 'home' | 'delete') => {
    const collection = menuFor;
    if (!collection) return;
    if (action === 'edit') setEditor({ collection });
    else if (action === 'home') void setUserCollectionShowOnHome(collection.id, !collection.showOnHome);
    else confirmDelete(collection);
  };

  const confirmDelete = (collection: UserCollection) => {
    Alert.alert('Delete Collection', 'This removes the collection and its Home row. Titles and sources aren\'t affected.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          deleteUserCollection(collection.id).catch(() => showToast("Couldn't delete this collection.", { kind: 'error' }));
        },
      },
    ]);
  };

  return (
    <View style={{ paddingHorizontal: horizontalInset, marginBottom: 24 }}>
      <View style={styles.header}>
        <Text style={[styles.title, { color: theme.textPrimary }]}>My Collections</Text>
        <Pressable onPress={() => setEditor({ collection: null })} hitSlop={8} style={styles.add} accessibilityLabel="New collection">
          <Ionicons name="add" size={20} color={theme.accentBright} />
          <Text style={{ color: theme.accentBright, fontWeight: '600', fontSize: 15 }}>New</Text>
        </Pressable>
      </View>

      {collections.length === 0 ? (
        <Text style={[styles.empty, { color: theme.textSecondary }]}>
          Build your own from addon catalogs, TMDB, people and Trakt lists.
        </Text>
      ) : (
        <View style={styles.grid}>
          {collections.map((collection) => (
            <CollectionCard
              key={collection.id}
              collection={collection}
              width={cardWidth}
              onPress={() => nav.navigate('UserCollection', { collectionId: collection.id, title: collection.name })}
              onLongPress={() => showMenu(collection)}
            />
          ))}
        </View>
      )}

      <OptionSheet<'edit' | 'home' | 'delete'>
        visible={menuFor !== null}
        title={menuFor?.name ?? ''}
        options={[
          { value: 'edit', label: 'Edit' },
          { value: 'home', label: menuFor?.showOnHome ? 'Remove from Home' : 'Show on Home' },
          { value: 'delete', label: 'Delete' },
        ]}
        onSelect={runMenuAction}
        onClose={() => setMenuFor(null)}
      />

      <UserCollectionEditor
        visible={editor !== null}
        collection={editor?.collection ?? null}
        onClose={() => setEditor(null)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 },
  title: { fontSize: 20, fontWeight: '700' },
  add: { flexDirection: 'row', alignItems: 'center', gap: 2 },
  empty: { fontSize: 14, lineHeight: 20 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  cover: { borderRadius: 10, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  homeBadge: { position: 'absolute', top: 6, right: 6, width: 22, height: 22, borderRadius: 11, alignItems: 'center', justifyContent: 'center' },
  name: { fontSize: 14, fontWeight: '600', marginTop: 6 },
  summary: { fontSize: 12, marginTop: 1 },
});
