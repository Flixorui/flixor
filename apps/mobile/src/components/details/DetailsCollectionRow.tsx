/**
 * The franchise a movie belongs to: "Part of <name>", its films in release order with a
 * position badge and year, and the current film marked "Viewing" and not tappable.
 * macOS reference: Views/Details/DetailsCollectionSection.swift
 */

import React from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import DetailsSectionHeading, { DetailsSectionStyle } from './DetailsSectionHeading';
import { POSTER_GAP, POSTER_SIZES } from '../Poster';
import type { RowItem } from '../../core/DetailsData';
import { useAppSettings } from '../../hooks/useAppSettings';

export default function DetailsCollectionRow({
  name,
  items,
  currentId,
  onItemPress,
  onTitlePress,
}: {
  name: string;
  items: RowItem[];
  /** Row id of the movie on screen ("tmdb:movie:<id>"). */
  currentId?: string;
  onItemPress: (item: RowItem) => void;
  onTitlePress?: () => void;
}) {
  // Same poster size, corner radius and "Show titles" setting as every other poster row
  const { settings } = useAppSettings();
  const { width: CARD_WIDTH, height: CARD_HEIGHT } = POSTER_SIZES[settings.posterSize] || POSTER_SIZES.medium;
  const radius = settings.posterBorderRadius;
  return (
    <View>
      <DetailsSectionHeading title={`Part of ${name}`} onPress={onTitlePress} />
      <Text style={styles.caption}>{items.length} movies, in release order</Text>
      <FlatList
        horizontal
        data={items}
        keyExtractor={(item) => item.id}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingHorizontal: DetailsSectionStyle.inset }}
        renderItem={({ item, index }) => {
          const current = item.id === currentId;
          return (
            <Pressable
              onPress={() => onItemPress(item)}
              disabled={current}
              style={{ width: CARD_WIDTH, marginRight: POSTER_GAP }}
              accessibilityRole="button"
              accessibilityLabel={`${index + 1}. ${item.title}${current ? ', viewing now' : ''}`}
            >
              <View style={[styles.poster, { width: CARD_WIDTH, height: CARD_HEIGHT, borderRadius: radius }, current && styles.posterCurrent]}>
                {item.image ? <FastImage source={{ uri: item.image }} style={StyleSheet.absoluteFill} resizeMode="cover" /> : null}
                {/* Neutral badges: white marks the current film (red is only for switches and progress) */}
                <View style={[styles.badge, current ? styles.badgeCurrent : styles.badgeIndex]}>
                  <Text style={[styles.badgeText, current && styles.badgeTextCurrent]}>
                    {current ? 'Viewing' : String(index + 1)}
                  </Text>
                </View>
              </View>
              {settings.showPosterTitles ? (
                <>
                  <Text style={styles.title} numberOfLines={2}>{item.title}</Text>
                  <Text style={styles.year}>{item.year ?? 'TBA'}</Text>
                </>
              ) : null}
            </Pressable>
          );
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  caption: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 13,
    marginHorizontal: DetailsSectionStyle.inset,
    marginTop: -6,
    marginBottom: 12,
  },
  poster: {
    overflow: 'hidden',
    backgroundColor: '#222',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.12)',
  },
  posterCurrent: { borderWidth: 2, borderColor: '#fff' },
  badge: { position: 'absolute', top: 6, left: 6, paddingHorizontal: 6, paddingVertical: 2, borderRadius: 4 },
  badgeIndex: { backgroundColor: 'rgba(0,0,0,0.6)' },
  badgeCurrent: { backgroundColor: '#fff' },
  badgeText: { color: '#fff', fontSize: 11, fontWeight: '700' },
  badgeTextCurrent: { color: '#000' },
  title: { color: '#fff', fontSize: 13, fontWeight: '600', marginTop: 6 },
  year: { color: 'rgba(255,255,255,0.5)', fontSize: 12, marginTop: 2 },
});
