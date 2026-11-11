/**
 * Season selector: text chips, or posters with episode counts.
 * macOS reference: Views/Details/DetailsEpisodeExtras.swift
 */

import React from 'react';
import { FlatList, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { DetailsSectionStyle } from './DetailsSectionHeading';
import { getPlexImageUrl, getTmdbImageUrl } from '../../core/DetailsData';
import type { DetailsSeasonPickerStyle } from '../../core/SettingsData';
import { useTheme } from '../../hooks/useTheme';

const POSTER_WIDTH = 96;
const POSTER_HEIGHT = 144;

function seasonKeyOf(season: any, index: number): string {
  return String(season.ratingKey || season.key || index);
}

function posterUrl(season: any): string | undefined {
  if (season.posterPath) return getTmdbImageUrl(season.posterPath, 'w342');
  if (season.thumb) return getPlexImageUrl(season.thumb, 300);
  return undefined;
}

function episodeCount(season: any): number | undefined {
  return season.leafCount ?? season.episodeCount;
}

export default function DetailsSeasonPicker({
  seasons,
  seasonKey,
  style,
  onChange,
}: {
  seasons: any[];
  seasonKey: string | null;
  style: DetailsSeasonPickerStyle;
  onChange: (key: string) => void;
}) {
  const theme = useTheme();
  if (!seasons?.length) return null;

  if (style === 'posters') {
    return (
      <FlatList
        horizontal
        data={seasons}
        keyExtractor={(season, index) => seasonKeyOf(season, index)}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.posterContent}
        renderItem={({ item: season, index }) => {
          const key = seasonKeyOf(season, index);
          const active = key === seasonKey;
          const uri = posterUrl(season);
          const count = episodeCount(season);
          return (
            <Pressable onPress={() => onChange(key)} style={styles.posterCard} accessibilityRole="button" accessibilityState={{ selected: active }}>
              <View
                style={[
                  styles.poster,
                  { backgroundColor: theme.surface, borderColor: active ? '#fff' : theme.separator, borderWidth: active ? 2 : StyleSheet.hairlineWidth },
                ]}
              >
                {uri ? <FastImage source={{ uri }} style={StyleSheet.absoluteFill} resizeMode="cover" /> : null}
              </View>
              <Text numberOfLines={1} style={[styles.posterTitle, { color: theme.textPrimary }]}>
                {season.title || `Season ${season.index || index + 1}`}
              </Text>
              {count ? (
                <Text numberOfLines={1} style={[styles.posterCount, { color: theme.textTertiary }]}>
                  {count} {count === 1 ? 'episode' : 'episodes'}
                </Text>
              ) : null}
            </Pressable>
          );
        }}
      />
    );
  }

  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.chipContent}>
      {seasons.map((season, index) => {
        const key = seasonKeyOf(season, index);
        const active = key === seasonKey;
        return (
          <Pressable
            key={key}
            onPress={() => onChange(key)}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            style={[
              styles.chip,
              {
                // Selected season: white with black text, as on macOS
                backgroundColor: active ? '#fff' : '#1a1b20',
                borderColor: active ? '#fff' : '#2a2b30',
              },
            ]}
          >
            <Text style={[styles.chipText, { color: active ? '#000' : theme.textPrimary }]}>
              {season.title || `Season ${season.index || index + 1}`}
            </Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  chipContent: {
    paddingHorizontal: DetailsSectionStyle.inset,
    gap: 10,
    marginBottom: 8,
  },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
  },
  chipText: {
    fontWeight: '700',
  },
  posterContent: {
    paddingHorizontal: DetailsSectionStyle.inset,
    gap: 12,
    marginBottom: 8,
  },
  posterCard: {
    width: POSTER_WIDTH,
  },
  poster: {
    width: POSTER_WIDTH,
    height: POSTER_HEIGHT,
    borderRadius: 10,
    overflow: 'hidden',
  },
  posterTitle: {
    fontSize: 13,
    fontWeight: '700',
    marginTop: 6,
  },
  posterCount: {
    fontSize: 12,
    marginTop: 1,
  },
});
