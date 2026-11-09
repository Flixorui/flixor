import React from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import Chip from '../collections/Chip';
import type { TraktUserList } from '../../core/TraktListsData';

/** Chooses between the watchlist and the user's Trakt lists. */
export default function ListSwitcher({
  lists,
  selectedId,
  onSelect,
  onCreate,
}: {
  lists: TraktUserList[];
  /** `null` is the watchlist. */
  selectedId: number | null;
  onSelect: (id: number | null) => void;
  onCreate: () => void;
}) {
  return (
    <View style={styles.container}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 8 }}>
        <Chip label="My List" active={selectedId === null} onPress={() => onSelect(null)} />
        {lists.map((list) => (
          <Chip
            key={list.ids.trakt}
            label={list.name}
            active={selectedId === list.ids.trakt}
            onPress={() => onSelect(list.ids.trakt)}
          />
        ))}
        <Chip label="+ New List" onPress={onCreate} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { paddingTop: 8, paddingBottom: 4 },
});
