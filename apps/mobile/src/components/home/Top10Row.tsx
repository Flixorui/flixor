/**
 * Top 10 row: this week's most-watched titles with large outlined rank numbers beside the
 * posters, Netflix style. "10" gets a wider column so it stays as tall as the single
 * digits and is never clipped.
 * macOS reference: Views/Home/TopTenRow.swift (fed by Streaming Availability there; the
 * mobile app uses TMDB's weekly trending until that integration is ported).
 */

import React, { useEffect, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import Svg, { Defs, Mask, Rect, Text as SvgText } from 'react-native-svg';
import * as Haptics from 'expo-haptics';
import { getTop10Movies, getTop10Shows, getTrendingAll, type ContentItem } from '../../core/NewHotData';
import { useAppSettings } from '../../hooks/useAppSettings';

const POSTER_W = 104;
const POSTER_H = 156;
const DIGIT_W = 104; // fits a full 150 pt heavy digit plus its outline; "10" gets about twice this
const OVERLAP = 12; // how far the poster sits over the number's lower right
const NUMBER_SIZE = 150;

type Top10Kind = 'all' | 'movie' | 'tv';
const cache: Partial<Record<Top10Kind, { at: number; items: ContentItem[] }>> = {};
const TITLES: Record<Top10Kind, string> = { all: 'Top 10 This Week', movie: 'Top 10 Movies This Week', tv: 'Top 10 Shows This Week' };
const CACHE_MS = 30 * 60 * 1000;

/*
 * Outlined rank number with a see-through middle, so the page tint shows inside it. The
 * system font's digits are built from overlapping contours, so a plain stroked glyph shows
 * lines inside the number (a "star" in the 2). Instead a doubled stroke is drawn and the
 * glyph's own fill is masked out of it, leaving only the clean outer half of the outline.
 */
function RankNumber({ rank }: { rank: number }) {
  // A "1" is narrow, so its column is too; "10" gets about two digits' width
  const width = rank >= 10 ? DIGIT_W * 1.85 : rank === 1 ? DIGIT_W * 0.72 : DIGIT_W;
  const maskId = `rank-${rank}`;
  const glyph = {
    x: width - 2,
    y: POSTER_H - 2,
    textAnchor: 'end' as const,
    fontSize: NUMBER_SIZE,
    fontWeight: '800' as const,
    letterSpacing: rank >= 10 ? -12 : 0,
  };
  return (
    <Svg width={width} height={POSTER_H} style={{ marginRight: -OVERLAP }}>
      <Defs>
        <Mask id={maskId} x={0} y={0} width={width} height={POSTER_H} maskUnits="userSpaceOnUse">
          <Rect x={0} y={0} width={width} height={POSTER_H} fill="#fff" />
          <SvgText {...glyph} fill="#000">
            {String(rank)}
          </SvgText>
        </Mask>
      </Defs>
      <SvgText
        {...glyph}
        fill="none"
        stroke="rgba(255,255,255,0.85)"
        strokeWidth={5}
        strokeLinejoin="round"
        mask={`url(#${maskId})`}
      >
        {String(rank)}
      </SvgText>
    </Svg>
  );
}

/** A ranked title. FlixPatrol / Streaming Availability lists pass these in; the TMDB fallback builds them. */
export type RankedItem = { id: string; title: string; image?: string; tmdbId?: number; mediaType?: 'movie' | 'tv' };

export default function Top10Row({
  onItemPress,
  kind = 'all',
  items: given,
  title,
}: {
  onItemPress: (item: RankedItem) => void;
  kind?: Top10Kind;
  /** A ready list in rank order (FlixPatrol / Streaming Availability); skips the TMDB fetch. */
  items?: RankedItem[];
  title?: string;
}) {
  const { settings } = useAppSettings();
  const [fetched, setItems] = useState<ContentItem[]>(cache[kind]?.items ?? []);
  const items: RankedItem[] = given ? given.filter((i) => i.image).slice(0, 10) : fetched;

  useEffect(() => {
    if (given || settings.discoveryDisabled) return;
    const hit = cache[kind];
    if (hit && Date.now() - hit.at < CACHE_MS) {
      setItems(hit.items);
      return;
    }
    let cancelled = false;
    const load = kind === 'movie' ? getTop10Movies('week') : kind === 'tv' ? getTop10Shows('week') : getTrendingAll('week');
    load.then((all) => {
      const top = all.filter((i) => i.image).slice(0, 10).map((i, index) => ({ ...i, rank: index + 1 }));
      cache[kind] = { at: Date.now(), items: top };
      if (!cancelled) setItems(top);
    });
    return () => {
      cancelled = true;
    };
  }, [settings.discoveryDisabled, kind, given]);

  if ((!given && settings.discoveryDisabled) || items.length === 0) return null;

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.title}>{title ?? TITLES[kind]}</Text>
      </View>
      <FlatList
        horizontal
        data={items}
        keyExtractor={(item) => item.id}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.list}
        renderItem={({ item, index }) => (
          <Pressable
            onPress={() => {
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
              onItemPress(item);
            }}
            style={styles.item}
            accessibilityRole="button"
            accessibilityLabel={`Number ${index + 1}, ${item.title}`}
          >
            <RankNumber rank={index + 1} />
            <FastImage
              source={{ uri: item.image!, priority: FastImage.priority.normal, cache: FastImage.cacheControl.immutable }}
              style={[styles.poster, { borderRadius: settings.posterBorderRadius }]}
              resizeMode={FastImage.resizeMode.cover}
            />
          </Pressable>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { marginBottom: 8 },
  header: { flexDirection: 'row', alignItems: 'center', marginTop: 15, marginBottom: 12, paddingHorizontal: 16 },
  title: { color: '#fff', fontSize: 18, fontWeight: 'bold' },
  list: { paddingHorizontal: 8, gap: 6 },
  item: { flexDirection: 'row', alignItems: 'flex-end' },
  poster: { width: POSTER_W, height: POSTER_H, backgroundColor: '#1c1c1e' },
});
