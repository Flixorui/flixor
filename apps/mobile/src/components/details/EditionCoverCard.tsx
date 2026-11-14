/**
 * A disc cover in the poster-card style: no badges on the art, a caption with
 * the edition, format, release and collection list, and (with a Blu-ray.com
 * login on the key) a round button that adds, moves or removes it.
 * macOS reference: EditionCoverCard in Views/Details/DetailsPhysicalSection.swift
 */
import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import GlassMenu, { type GlassMenuItem } from '../GlassMenu';
import { useTheme } from '../../hooks/useTheme';
import { useAppSettings } from '../../hooks/useAppSettings';
import { isMyBlurayOn } from '../../core/mybluray/options';
import { addEdition, removeEdition, useCollectionStore } from '../../core/mybluray/collectionStore';
import { editionCaption, editionName } from '../../core/mybluray/editionText';
import type { MBEditionSummary } from '../../core/mybluray/types';

/** Height over width of a Blu-ray case (squatter than a film poster's 1.5). */
export const EDITION_ASPECT = 1.26;

export default function EditionCoverCard({
  edition,
  width,
  showsList = true,
  showsCountry = false,
  onPress,
}: {
  edition: MBEditionSummary;
  width: number;
  showsList?: boolean;
  showsCountry?: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  const { settings } = useAppSettings();
  const collection = useCollectionStore();
  const list = collection.listFor[edition.id];
  const canEdit = isMyBlurayOn('quickAdd', settings) && collection.phase === 'loaded' && collection.lists.length > 0;
  const height = Math.round(width * EDITION_ASPECT);
  const radius = settings.posterBorderRadius ?? 8;

  return (
    <View style={{ width }}>
      <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={edition.title ?? editionName(edition)}>
        {({ pressed }) => (
          <View
            style={[
              styles.cover,
              { width, height, borderRadius: radius, borderColor: pressed ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.15)' },
            ]}
          >
            {edition.coverImage ? (
              <FastImage
                source={{ uri: edition.coverImage, cache: FastImage.cacheControl.immutable }}
                style={StyleSheet.absoluteFill}
                resizeMode={FastImage.resizeMode.cover}
              />
            ) : (
              <Ionicons name="disc-outline" size={32} color="rgba(255,255,255,0.3)" />
            )}
          </View>
        )}
      </Pressable>
      {canEdit ? (
        <View style={styles.menuButtonWrap}>
          <CollectionMenuButton edition={edition} />
        </View>
      ) : null}
      <Text numberOfLines={2} style={[styles.name, { color: theme.textPrimary }]}>{editionName(edition)}</Text>
      <Text numberOfLines={1} style={[styles.caption, { color: theme.textTertiary }]}>
        {showsList && list ? (
          <Text style={{ color: theme.textSecondary }}>
            {list.alias === 'owned' ? '✓ ' : ''}
            {list.name ?? ''} ·{' '}
          </Text>
        ) : null}
        {editionCaption(edition, showsCountry)}
      </Text>
    </View>
  );
}

/** The lists, with the current one ticked, then Remove. */
export function collectionMenuItems(edition: MBEditionSummary, current: string | null | undefined, lists: { id: string; name?: string | null }[]): GlassMenuItem[] {
  const items: GlassMenuItem[] = lists.map((option) => ({
    title: option.name ?? option.id,
    checked: current === option.id,
    onPress: current === option.id ? undefined : () => addEdition(edition, option as any),
  }));
  if (current) items.push({ title: 'Remove from Collection', icon: 'trash-outline', onPress: () => removeEdition(edition) });
  return items;
}

/** Round button on a cover: add to a list, move it, or remove it. */
export function CollectionMenuButton({ edition }: { edition: MBEditionSummary }) {
  const collection = useCollectionStore();
  const list = collection.listFor[edition.id];
  return (
    <GlassMenu
      items={collectionMenuItems(edition, list?.id, collection.lists)}
      accessibilityLabel={list ? `In ${list.name ?? 'your collection'}. Change` : 'Add to collection'}
    >
      <View style={styles.menuButton}>
        <Ionicons name={list ? 'ellipsis-horizontal' : 'add'} size={list ? 14 : 16} color="#fff" />
      </View>
    </GlassMenu>
  );
}

const styles = StyleSheet.create({
  cover: {
    overflow: 'hidden',
    borderWidth: 1,
    backgroundColor: 'rgba(255,255,255,0.05)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  menuButtonWrap: { position: 'absolute', top: 8, right: 8 },
  menuButton: {
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: 'rgba(0,0,0,0.7)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.3)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  name: { fontSize: 14, fontWeight: '500', marginTop: 8, lineHeight: 18 },
  caption: { fontSize: 12, marginTop: 2 },
});
