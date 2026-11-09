import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ActivityIndicator, FlatList, ScrollView, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import { fetchPlexSeasonEpisodes, fetchPlexSeasons } from '../../../core/DetailsData';
import { getPlayerImageUrl } from '../../../core/PlayerData';
import { useTheme } from '../../../hooks/useTheme';
import {
  loadStreamSeasonEpisodes,
  loadStreamSeasonNumbers,
  type StreamEpisodeInfo,
  type StreamSeriesRef,
} from '../../../stremio/StreamEpisodeNavigator';
import PlayerPanel from './PlayerPanel';

export type BrowserEpisode = {
  key: string;
  season: number;
  episode: number;
  title: string;
  overview?: string;
  imageUrl?: string;
  runtimeMinutes?: number;
  hasAired: boolean;
  plexRatingKey?: string;
};

export type EpisodeBrowserSource =
  | { kind: 'stream'; ref: StreamSeriesRef; seasonEpisodes: StreamEpisodeInfo[] }
  | { kind: 'plex'; showRatingKey?: string; seasonRatingKey?: string; season: number; ratingKey: string };

type Props = {
  source: EpisodeBrowserSource;
  onSelect: (episode: BrowserEpisode) => void;
  onClose: () => void;
};

type SeasonOption = { number: number; plexKey?: string };

const ROW_HEIGHT = 88;

function fromStream(episode: StreamEpisodeInfo): BrowserEpisode {
  return {
    key: `${episode.season}:${episode.episode}`,
    season: episode.season,
    episode: episode.episode,
    title: episode.title,
    overview: episode.overview,
    imageUrl: episode.stillUrl,
    runtimeMinutes: episode.runtimeMinutes,
    hasAired: episode.hasAired,
  };
}

function fromPlex(item: any, season: number): BrowserEpisode {
  return {
    key: String(item.ratingKey),
    season: item.parentIndex ?? season,
    episode: item.index ?? 0,
    title: item.title || `Episode ${item.index}`,
    overview: item.summary,
    imageUrl: item.thumb ? getPlayerImageUrl(item.thumb, 300) || undefined : undefined,
    runtimeMinutes: item.duration ? Math.round(item.duration / 60000) : undefined,
    hasAired: true,
    plexRatingKey: String(item.ratingKey),
  };
}

export default function EpisodesPanel({ source, onSelect, onClose }: Props) {
  const theme = useTheme();
  const currentSeason = source.kind === 'stream' ? source.ref.season : source.season;
  const currentKey =
    source.kind === 'stream' ? `${source.ref.season}:${source.ref.episode}` : source.ratingKey;

  const [seasons, setSeasons] = useState<SeasonOption[]>([]);
  const [selectedSeason, setSelectedSeason] = useState(currentSeason);
  const [episodes, setEpisodes] = useState<BrowserEpisode[]>(
    source.kind === 'stream' ? source.seasonEpisodes.map(fromStream) : []
  );
  const [loading, setLoading] = useState(source.kind === 'plex' || source.seasonEpisodes.length === 0);
  const [failed, setFailed] = useState(false);
  const requestRef = useRef(0);

  const loadSeason = useCallback(
    async (season: number, options?: SeasonOption[]) => {
      const request = ++requestRef.current;
      setSelectedSeason(season);
      setFailed(false);

      if (source.kind === 'stream' && season === source.ref.season && source.seasonEpisodes.length > 0) {
        setEpisodes(source.seasonEpisodes.map(fromStream));
        setLoading(false);
        return;
      }

      setLoading(true);
      try {
        let loaded: BrowserEpisode[];
        if (source.kind === 'stream') {
          loaded = (await loadStreamSeasonEpisodes(source.ref, season)).map(fromStream);
        } else {
          const plexKey =
            (options ?? seasons).find((option) => option.number === season)?.plexKey ??
            (season === source.season ? source.seasonRatingKey : undefined);
          const items = plexKey ? await fetchPlexSeasonEpisodes(plexKey) : [];
          loaded = items.map((item) => fromPlex(item, season));
        }
        if (request === requestRef.current) {
          setEpisodes(loaded);
          setLoading(false);
        }
      } catch {
        if (request === requestRef.current) {
          setEpisodes([]);
          setFailed(true);
          setLoading(false);
        }
      }
    },
    [seasons, source]
  );

  useEffect(() => {
    let cancelled = false;
    (async () => {
      let options: SeasonOption[] = [];
      try {
        if (source.kind === 'stream') {
          options = (await loadStreamSeasonNumbers(source.ref)).map((number) => ({ number }));
        } else if (source.showRatingKey) {
          const items = await fetchPlexSeasons(source.showRatingKey);
          options = items
            .filter((item) => typeof item.index === 'number')
            .map((item) => ({ number: item.index as number, plexKey: String(item.ratingKey) }));
        }
      } catch {
        // The current season still lists; the selector just stays hidden.
      }
      if (cancelled) return;
      setSeasons(options);
      if (source.kind === 'plex') {
        loadSeason(source.season, options);
      } else if (source.seasonEpisodes.length === 0) {
        loadSeason(source.ref.season, options);
      }
    })();
    return () => {
      cancelled = true;
    };
    // Loads once per open; `source` is fixed while the panel is open.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const initialIndex = useMemo(() => {
    const index = episodes.findIndex((episode) => episode.key === currentKey);
    return index > 0 ? index : undefined;
  }, [currentKey, episodes]);

  const renderEpisode = useCallback(
    ({ item }: { item: BrowserEpisode }) => {
      const isCurrent = item.key === currentKey;
      const disabled = !item.hasAired || isCurrent;
      return (
        <TouchableOpacity
          style={[styles.row, isCurrent && { backgroundColor: theme.accentSoft }, !item.hasAired && styles.notAired]}
          disabled={disabled}
          onPress={() => onSelect(item)}
          accessibilityRole="button"
          accessibilityState={{ selected: isCurrent, disabled }}
        >
          <View style={[styles.thumb, { backgroundColor: theme.surfaceOverlay }]}>
            {item.imageUrl ? (
              <FastImage source={{ uri: item.imageUrl }} style={StyleSheet.absoluteFill} resizeMode={FastImage.resizeMode.cover} />
            ) : (
              <Ionicons name="film-outline" size={20} color={theme.textTertiary} />
            )}
          </View>
          <View style={styles.rowText}>
            <Text style={[styles.rowTitle, { color: theme.textPrimary }]} numberOfLines={1}>
              {item.episode}. {item.title}
            </Text>
            <Text style={[styles.rowMeta, { color: isCurrent ? theme.accentBright : theme.textTertiary }]} numberOfLines={1}>
              {isCurrent
                ? 'Now playing'
                : !item.hasAired
                  ? 'Not yet aired'
                  : item.runtimeMinutes
                    ? `${item.runtimeMinutes} min`
                    : ' '}
            </Text>
            {item.overview ? (
              <Text style={[styles.rowOverview, { color: theme.textSecondary }]} numberOfLines={1}>
                {item.overview}
              </Text>
            ) : null}
          </View>
        </TouchableOpacity>
      );
    },
    [currentKey, onSelect, theme]
  );

  return (
    <PlayerPanel title="Episodes" onClose={onClose}>
      {seasons.length > 1 ? (
        <View style={[styles.seasonBar, { borderBottomColor: theme.separator }]}>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.seasonContent}>
            {seasons.map((season) => {
              const selected = season.number === selectedSeason;
              return (
                <TouchableOpacity
                  key={season.number}
                  style={[
                    styles.seasonChip,
                    { backgroundColor: selected ? theme.accent : theme.surfaceOverlay },
                  ]}
                  onPress={() => season.number !== selectedSeason && loadSeason(season.number)}
                  accessibilityRole="button"
                  accessibilityState={{ selected }}
                >
                  <Text style={[styles.seasonText, { color: selected ? theme.onAccent : theme.textPrimary }]}>
                    {season.number === 0 ? 'Specials' : `Season ${season.number}`}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </ScrollView>
        </View>
      ) : null}
      {loading ? (
        <View style={styles.state}>
          <ActivityIndicator color={theme.textSecondary} />
        </View>
      ) : episodes.length === 0 ? (
        <View style={styles.state}>
          <Text style={[styles.stateText, { color: theme.textSecondary }]}>
            {failed ? "Couldn't load these episodes." : 'No episodes found.'}
          </Text>
          {failed ? (
            <TouchableOpacity onPress={() => loadSeason(selectedSeason)} accessibilityRole="button">
              <Text style={[styles.retry, { color: theme.accentBright }]}>Try Again</Text>
            </TouchableOpacity>
          ) : null}
        </View>
      ) : (
        <FlatList
          key={selectedSeason}
          data={episodes}
          keyExtractor={(item) => item.key}
          renderItem={renderEpisode}
          initialScrollIndex={initialIndex}
          getItemLayout={(_, index) => ({ length: ROW_HEIGHT, offset: ROW_HEIGHT * index, index })}
        />
      )}
    </PlayerPanel>
  );
}

const styles = StyleSheet.create({
  seasonBar: {
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  seasonContent: {
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  seasonChip: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 14,
  },
  seasonText: {
    fontSize: 13,
    fontWeight: '600',
  },
  row: {
    height: ROW_HEIGHT,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 12,
  },
  notAired: {
    opacity: 0.5,
  },
  thumb: {
    width: 104,
    height: 64,
    borderRadius: 6,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowText: {
    flex: 1,
    gap: 2,
  },
  rowTitle: {
    fontSize: 14,
    fontWeight: '600',
  },
  rowMeta: {
    fontSize: 12,
  },
  rowOverview: {
    fontSize: 12,
  },
  state: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    padding: 24,
  },
  stateText: {
    fontSize: 14,
    textAlign: 'center',
  },
  retry: {
    fontSize: 14,
    fontWeight: '700',
  },
});
