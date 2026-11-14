/**
 * Physical Releases on Details (movies only), from MyBluray / Blu-ray.com:
 * the film's Blu-ray and 4K editions for the chosen market, falling back to
 * every market when that one has none. Tapping a cover opens the edition page.
 * macOS reference: Views/Details/DetailsPhysicalSection.swift
 */
import React, { useEffect, useMemo, useState } from 'react';
import { FlatList, Linking, Pressable, StyleSheet, Text, View } from 'react-native';
import { Feather, Ionicons } from '@expo/vector-icons';
import DetailsSectionHeading, { DetailsSectionStyle } from './DetailsSectionHeading';
import EditionCoverCard from './EditionCoverCard';
import { useTheme } from '../../hooks/useTheme';
import { useAppSettings } from '../../hooks/useAppSettings';
import { countryName, isMyBlurayOn } from '../../core/mybluray/options';
import { isUHD, loadCollection, useCollectionStore } from '../../core/mybluray/collectionStore';
import type { PhysicalReleases } from '../../core/mybluray/hooks';
import type { MBEditionSummary } from '../../core/mybluray/types';

type Filter = 'all' | 'uhd' | 'bluray';
const CARD_WIDTH = 132;

export default function DetailsPhysicalSection({ releases, onSelect }: { releases: PhysicalReleases; onSelect: (e: MBEditionSummary) => void }) {
  const theme = useTheme();
  const { settings } = useAppSettings();
  const collection = useCollectionStore();
  const [filter, setFilter] = useState<Filter>('all');

  useEffect(() => {
    if (isMyBlurayOn('quickAdd', settings) || isMyBlurayOn('librarySection', settings)) loadCollection();
  }, [settings.myblurayApiKey]);

  const hasBoth = releases.editions.some(isUHD) && releases.editions.some((e) => !isUHD(e));
  const shown = useMemo(() => {
    if (filter === 'uhd') return releases.editions.filter(isUHD);
    if (filter === 'bluray') return releases.editions.filter((e) => !isUHD(e));
    return releases.editions;
  }, [filter, releases.editions]);

  const count = releases.editions.length;
  const editions = count === 1 ? '1 edition' : `${count} editions`;
  const subtitle = releases.fellBack
    ? `${editions} · none in your country, showing all`
    : releases.country
      ? `${editions} · ${countryName(releases.country)}`
      : `${editions} · all countries`;
  const link = releases.movie?.websiteUrl;

  return (
    <View>
      <DetailsSectionHeading
        title="Physical Releases"
        right={
          link ? (
            <Pressable onPress={() => Linking.openURL(link)} style={[styles.linkPill, { borderColor: theme.separator, backgroundColor: theme.pressedFill }]} accessibilityRole="link">
              <Text style={[styles.linkText, { color: theme.textSecondary }]}>Blu-ray.com</Text>
              <Feather name="arrow-up-right" size={13} color={theme.textSecondary} />
            </Pressable>
          ) : undefined
        }
      />
      <View style={styles.subRow}>
        <Text numberOfLines={1} style={[styles.subtitle, { color: theme.textTertiary }]}>{subtitle}</Text>
        {hasBoth ? (
          <View style={[styles.segment, { backgroundColor: theme.pressedFill }]}>
            {(['all', 'uhd', 'bluray'] as Filter[]).map((value) => {
              const active = filter === value;
              return (
                <Pressable
                  key={value}
                  onPress={() => setFilter(value)}
                  style={[styles.segmentChip, active && { backgroundColor: 'rgba(255,255,255,0.18)' }]}
                  accessibilityRole="button"
                  accessibilityState={{ selected: active }}
                >
                  <Text style={[styles.segmentText, { color: active ? theme.textPrimary : theme.textSecondary }]}>
                    {value === 'all' ? 'All' : value === 'uhd' ? '4K' : 'Blu-ray'}
                  </Text>
                </Pressable>
              );
            })}
          </View>
        ) : null}
      </View>
      <FlatList
        horizontal
        data={shown}
        keyExtractor={(e) => e.id}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingHorizontal: DetailsSectionStyle.inset, gap: 14 }}
        renderItem={({ item }) => (
          <EditionCoverCard edition={item} width={CARD_WIDTH} showsCountry={!releases.country} onPress={() => onSelect(item)} />
        )}
      />
      {collection.message ? (
        <Text style={[styles.message, { color: theme.textSecondary }]}>{collection.message}</Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  subRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
    paddingHorizontal: DetailsSectionStyle.inset,
    marginTop: -6,
    marginBottom: 12,
  },
  subtitle: { fontSize: 13, flexShrink: 1 },
  segment: { flexDirection: 'row', borderRadius: 8, padding: 2 },
  segmentChip: { paddingHorizontal: 10, paddingVertical: 5, borderRadius: 6 },
  segmentText: { fontSize: 12, fontWeight: '600' },
  linkPill: { flexDirection: 'row', alignItems: 'center', gap: 4, height: 28, paddingHorizontal: 12, borderRadius: 14, borderWidth: StyleSheet.hairlineWidth },
  linkText: { fontSize: 13, fontWeight: '600' },
  message: { fontSize: 12, marginTop: 10, paddingHorizontal: DetailsSectionStyle.inset },
});
