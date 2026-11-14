/**
 * Everything in the Episodes section: heading, season menu, picker, and the episode list
 * with ratings, watched state and spoiler hiding.
 * macOS reference: Views/Details/DetailsEpisodesSection.swift
 */

import React, { useMemo, useState } from 'react';
import { ActivityIndicator, Dimensions, FlatList, Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import FastImage from '@d11/react-native-fast-image';
import * as Haptics from 'expo-haptics';
import { DownloadButton } from '../downloads';
import DetailsActionSheet, { type DetailsAction } from './DetailsActionSheet';
import DetailsRatingSheet from './DetailsRatingSheet';
import DetailsSeasonPicker from './DetailsSeasonPicker';
import DetailsSectionHeading, { DetailsSectionStyle } from './DetailsSectionHeading';
import { useDetailsEpisodeState, episodeProgress, episodeNumberOf, seasonNumberOf } from './useDetailsEpisodeState';
import { showWatchToast } from './watchToast';
import { getPlexImageUrl, getTmdbImageUrl, type TMDBEpisodeData } from '../../core/DetailsData';
import type { DetailsSeasonPickerStyle } from '../../core/SettingsData';
import {
  canRate,
  getUserRating,
  rate as rateTarget,
  removeRating as removeTargetRating,
  type WatchStateTarget,
} from '../../core/WatchState';
import { useTheme } from '../../hooks/useTheme';

const HORIZONTAL_ITEM_SPACING = 14;
const CARD_HEIGHT = 180;
/** A sheet presented while another is still dismissing fails silently on iOS. */
const SHEET_HANDOFF_DELAY_MS = 350;

function formatAirDate(date?: string): string | undefined {
  if (!date) return undefined;
  try {
    return new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  } catch {
    return date;
  }
}

export default function DetailsEpisodesSection({
  seasons,
  seasonKey,
  seasonNumber,
  seasonPickerStyle,
  onSeasonChange,
  episodes,
  loading,
  tmdbMode,
  tmdbId,
  imdbId,
  showTitle,
  tmdbEpisodeData,
  horizontalLayout,
  hideSpoilers,
  showRatings,
  stremioEnabled,
  onPlayEpisode,
  onOpenStremioEpisode,
  onChanged,
}: {
  seasons: any[];
  seasonKey: string | null;
  seasonNumber: number | null;
  seasonPickerStyle: DetailsSeasonPickerStyle;
  onSeasonChange: (key: string) => void;
  episodes: any[];
  loading: boolean;
  tmdbMode: boolean;
  tmdbId?: number;
  imdbId?: string;
  showTitle: string;
  tmdbEpisodeData?: Map<number, TMDBEpisodeData>;
  horizontalLayout: boolean;
  hideSpoilers: boolean;
  showRatings: boolean;
  stremioEnabled: boolean;
  onPlayEpisode: (episode: any) => void;
  onOpenStremioEpisode: (episode: any) => void;
  onChanged: () => void | Promise<void>;
}) {
  const theme = useTheme();
  const state = useDetailsEpisodeState({
    episodes,
    seasonNumber,
    seasonKey,
    tmdbMode,
    tmdbId,
    imdbId,
    showTitle,
    tmdbEpisodeData,
    onChanged,
  });

  const [menuEpisode, setMenuEpisode] = useState<any | null>(null);
  const [seasonMenu, setSeasonMenu] = useState(false);
  const [ratingFor, setRatingFor] = useState<{ target: WatchStateTarget; title: string; current: number | null } | null>(null);

  const cardWidth = Math.min(Dimensions.get('window').width * 0.75, 340);

  const hidesSpoilers = (ep: any) => hideSpoilers && !state.isWatched(ep) && !state.isRevealed(ep);

  const imageFor = (ep: any): string | undefined => {
    const tmdbData = tmdbEpisodeData?.get(episodeNumberOf(ep) ?? -1);
    if (tmdbMode && ep.still_path) return getTmdbImageUrl(ep.still_path, 'w780');
    if (tmdbData?.still_path) return getTmdbImageUrl(tmdbData.still_path, 'w780');
    const path = ep.thumb || ep.art;
    return path ? getPlexImageUrl(path, 640) : undefined;
  };

  const airDateFor = (ep: any): string | undefined => {
    if (tmdbMode && ep.air_date) return formatAirDate(ep.air_date);
    const tmdbData = tmdbEpisodeData?.get(episodeNumberOf(ep) ?? -1);
    if (tmdbData?.air_date) return formatAirDate(tmdbData.air_date);
    return ep.originallyAvailableAt ? formatAirDate(ep.originallyAvailableAt) : undefined;
  };

  const durationFor = (ep: any): string => {
    if (tmdbMode) return ep.runtime ? `${ep.runtime}m` : '';
    return ep.duration ? `${Math.round(ep.duration / 60000)}m` : '';
  };

  const onEpisodePress = (ep: any) => {
    if (!tmdbMode && ep.ratingKey) onPlayEpisode(ep);
    else if (stremioEnabled) onOpenStremioEpisode(ep);
  };

  const openMenu = (ep: any) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    setMenuEpisode(ep);
  };

  const openEpisodeRating = async (ep: any) => {
    const target = state.episodeTarget(ep);
    const current = await getUserRating(target);
    const season = seasonNumberOf(ep, seasonNumber);
    const number = episodeNumberOf(ep);
    const title = `${ep.title || ep.name || 'Episode'}${season != null && number != null ? ` (S${season} E${number})` : ''}`;
    setRatingFor({ target, title, current });
  };

  const episodeActions = useMemo<DetailsAction[]>(() => {
    if (!menuEpisode) return [];
    const watched = state.isWatched(menuEpisode);
    const actions: DetailsAction[] = [
      {
        key: 'toggle',
        title: watched ? 'Mark as Unwatched' : 'Mark as Watched',
        icon: watched ? 'arrow-undo-outline' : 'checkmark-circle-outline',
        onPress: () => state.setEpisodeWatched(menuEpisode, !watched),
      },
    ];
    if (canRate()) {
      actions.push({
        key: 'rate',
        title: 'Rate on Trakt',
        icon: 'star-outline',
        onPress: () => {
          const ep = menuEpisode;
          setTimeout(() => openEpisodeRating(ep), SHEET_HANDOFF_DELAY_MS);
        },
      });
    }
    if (hideSpoilers && !watched) {
      const shown = state.isRevealed(menuEpisode);
      actions.push({
        key: 'spoilers',
        title: shown ? 'Hide Spoilers' : 'Reveal Spoilers',
        icon: shown ? 'eye-off-outline' : 'eye-outline',
        onPress: () => state.toggleRevealed(menuEpisode),
      });
    }
    return actions;
  }, [menuEpisode, state, hideSpoilers]);

  const seasonActions: DetailsAction[] = [
    {
      key: 'season-watched',
      title: 'Mark Season as Watched',
      icon: 'checkmark-circle-outline',
      disabled: state.seasonBusy,
      onPress: () => state.setSeasonWatched(true),
    },
    {
      key: 'season-unwatched',
      title: 'Mark Season as Unwatched',
      icon: 'arrow-undo-outline',
      disabled: state.seasonBusy,
      onPress: () => state.setSeasonWatched(false),
    },
  ];

  const seasonMenuButton = (
    <Pressable onPress={() => setSeasonMenu(true)} hitSlop={10} accessibilityRole="button" accessibilityLabel="Season options">
      <Ionicons name="ellipsis-horizontal" size={20} color={theme.textPrimary} />
    </Pressable>
  );

  const renderThumbnail = (ep: any, width: number | string, height: number, blurRadius: number) => {
    const uri = imageFor(ep);
    const hidden = hidesSpoilers(ep);
    return uri ? (
      hidden ? (
        <Image source={{ uri }} blurRadius={blurRadius} style={{ width: width as number, height }} resizeMode="cover" />
      ) : (
        <FastImage source={{ uri }} style={{ width: width as number, height }} resizeMode="cover" />
      )
    ) : null;
  };

  const renderRevealButton = (ep: any) =>
    hidesSpoilers(ep) ? (
      <Pressable
        onPress={() => state.toggleRevealed(ep)}
        hitSlop={12}
        accessibilityRole="button"
        accessibilityLabel="Reveal spoilers"
        style={styles.revealButton}
      >
        <Ionicons name="eye-outline" size={18} color="#fff" />
      </Pressable>
    ) : null;

  const renderRating = (ep: any) => {
    const rating = showRatings ? state.rating(ep) : null;
    return rating ? (
      <View style={styles.ratingChip} accessibilityLabel={`Rated ${rating.toFixed(1)} out of 10`}>
        <Ionicons name="star" size={10} color={theme.warning} />
        <Text style={styles.ratingText}>{rating.toFixed(1)}</Text>
      </View>
    ) : null;
  };

  const renderWatchedButton = (ep: any, size: number) => {
    const watched = state.isWatched(ep);
    return (
      <Pressable
        onPress={() => state.setEpisodeWatched(ep, !watched)}
        hitSlop={8}
        accessibilityRole="button"
        accessibilityLabel={watched ? 'Mark as unwatched' : 'Mark as watched'}
      >
        <Ionicons
          name={watched ? 'checkmark-circle' : 'checkmark-circle-outline'}
          size={size}
          color={watched ? '#fff' : 'rgba(255,255,255,0.75)'}
        />
      </Pressable>
    );
  };

  const renderHorizontalCard = ({ item: ep, index }: { item: any; index: number }) => {
    const progress = episodeProgress(ep, tmdbMode);
    const overview = ep.summary || ep.description || ep.overview || ep.synopsis || '';
    const durationLabel = durationFor(ep);
    const airDate = airDateFor(ep);
    const showProgress = typeof progress === 'number' && progress > 0 && progress < 85;
    const hidden = hidesSpoilers(ep);
    return (
      <Pressable
        onPress={() => onEpisodePress(ep)}
        onLongPress={() => openMenu(ep)}
        accessibilityHint="Long press for episode options"
        style={[styles.card, { width: cardWidth, backgroundColor: theme.surface, borderColor: theme.separatorStrong }]}
      >
        {renderThumbnail(ep, '100%', CARD_HEIGHT, 24)}
        <LinearGradient
          colors={['rgba(0,0,0,0.05)', 'rgba(0,0,0,0.2)', 'rgba(0,0,0,0.6)', 'rgba(0,0,0,0.9)']}
          locations={[0, 0.25, 0.6, 1]}
          style={styles.cardOverlay}
        >
          <View style={styles.cardBody}>
            <View style={styles.cardTags}>
              <View style={styles.cardTag}>
                <Text style={styles.cardTagText}>EPISODE {index + 1}</Text>
              </View>
              {renderRating(ep)}
            </View>
            <Text style={styles.cardTitle} numberOfLines={2}>
              {ep.title || ep.name || 'Episode'}
            </Text>
            {hidden ? (
              <Text style={styles.spoilerNotice} numberOfLines={1}>
                Description hidden. Tap the eye to reveal.
              </Text>
            ) : overview ? (
              <Text style={styles.cardOverview} numberOfLines={3}>
                {overview}
              </Text>
            ) : null}
            <View style={styles.cardMeta}>
              {durationLabel ? (
                <View style={styles.metaItem}>
                  <Ionicons name="time-outline" size={12} color="#9ca3af" />
                  <Text style={styles.metaText}>{durationLabel}</Text>
                </View>
              ) : null}
              {airDate ? (
                <View style={styles.metaItem}>
                  <Ionicons name="calendar-outline" size={11} color="#9ca3af" />
                  <Text style={styles.metaText}>{airDate}</Text>
                </View>
              ) : null}
            </View>
            {stremioEnabled ? (
              <Pressable
                onPress={(event) => {
                  event.stopPropagation();
                  onOpenStremioEpisode(ep);
                }}
                style={styles.stremioPill}
              >
                <Text style={styles.stremioText}>STREMIO</Text>
              </Pressable>
            ) : null}
          </View>
          {showProgress ? (
            <View style={styles.progressTrack}>
              <View style={[styles.progressFill, { width: `${Math.min(100, Math.max(0, progress as number))}%` }]} />
            </View>
          ) : null}
          <View style={styles.cardWatched}>{renderWatchedButton(ep, 22)}</View>
          {hidden ? <View style={styles.cardReveal}>{renderRevealButton(ep)}</View> : null}
          {!tmdbMode && ep.ratingKey ? (
            <View style={styles.cardDownload}>
              <DownloadButton metadata={ep} variant="icon" size="small" />
            </View>
          ) : null}
        </LinearGradient>
      </Pressable>
    );
  };

  const renderListRow = (ep: any, idx: number) => {
    const progress = episodeProgress(ep, tmdbMode);
    const durationLabel = durationFor(ep);
    const airDate = airDateFor(ep);
    const hidden = hidesSpoilers(ep);
    return (
      <Pressable
        key={idx}
        onPress={() => onEpisodePress(ep)}
        onLongPress={() => openMenu(ep)}
        accessibilityHint="Long press for episode options"
        style={styles.listRow}
      >
        <View style={[styles.thumb, { backgroundColor: theme.surface }]}>
          {renderThumbnail(ep, '100%', styles.thumb.height, 18)}
          {typeof progress === 'number' && progress > 0 ? (
            <View style={styles.progressTrack}>
              <View style={[styles.progressFill, { width: `${Math.min(100, Math.max(0, progress))}%` }]} />
            </View>
          ) : null}
          {hidden ? <View style={styles.thumbReveal}>{renderRevealButton(ep)}</View> : null}
        </View>
        <View style={styles.listBody}>
          <Text style={[styles.listTitle, { color: theme.textPrimary }]}>
            {idx + 1}. {ep.title || ep.name || 'Episode'}
          </Text>
          <View style={styles.listMeta}>
            {durationLabel ? <Text style={[styles.listMetaText, { color: theme.textSecondary }]}>{durationLabel}</Text> : null}
            {durationLabel && airDate ? <Text style={[styles.listMetaText, { color: theme.textSecondary, marginHorizontal: 6 }]}>•</Text> : null}
            {airDate ? <Text style={[styles.listMetaText, { color: theme.textSecondary }]}>{airDate}</Text> : null}
            {renderRating(ep)}
          </View>
          {hidden ? (
            <Text style={[styles.spoilerNoticeList, { color: theme.textTertiary }]} numberOfLines={1}>
              Description hidden
            </Text>
          ) : null}
          {stremioEnabled ? (
            <Pressable
              onPress={(event) => {
                event.stopPropagation();
                onOpenStremioEpisode(ep);
              }}
              style={styles.stremioPillList}
            >
              <Text style={styles.stremioText}>STREMIO</Text>
            </Pressable>
          ) : null}
        </View>
        <View style={styles.listActions}>
          {renderWatchedButton(ep, 24)}
          {!tmdbMode && ep.ratingKey ? <DownloadButton metadata={ep} variant="icon" size="small" /> : null}
        </View>
      </Pressable>
    );
  };

  return (
    <View>
      <DetailsSectionHeading title="Episodes" right={seasonMenuButton} />
      <DetailsSeasonPicker seasons={seasons} seasonKey={seasonKey} style={seasonPickerStyle} onChange={onSeasonChange} />

      {loading ? (
        <View style={styles.loading}>
          <ActivityIndicator color={theme.textPrimary} />
        </View>
      ) : episodes.length === 0 ? (
        <Text style={[styles.empty, { color: theme.textSecondary }]}>No episodes found for this season.</Text>
      ) : horizontalLayout ? (
        <FlatList
          data={episodes}
          renderItem={renderHorizontalCard}
          keyExtractor={(item, index) => String(item?.ratingKey || item?.id || `${seasonKey}-${index}`)}
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.horizontalContent}
          snapToInterval={cardWidth + HORIZONTAL_ITEM_SPACING}
          snapToAlignment="start"
          decelerationRate="fast"
          extraData={state}
        />
      ) : (
        <View style={styles.list}>{episodes.map(renderListRow)}</View>
      )}

      <DetailsActionSheet
        visible={menuEpisode !== null}
        title={menuEpisode ? menuEpisode.title || menuEpisode.name || 'Episode' : undefined}
        actions={episodeActions}
        onClose={() => setMenuEpisode(null)}
      />
      <DetailsActionSheet
        visible={seasonMenu}
        title="Season"
        actions={seasonActions}
        onClose={() => setSeasonMenu(false)}
      />
      <DetailsRatingSheet
        visible={ratingFor !== null}
        title={ratingFor?.title ?? ''}
        initialRating={ratingFor?.current ?? null}
        onSave={async (value) => {
          const request = ratingFor;
          setRatingFor(null);
          if (!request) return;
          const result = await rateTarget(request.target, value);
          showWatchToast(result);
        }}
        onRemove={async () => {
          const request = ratingFor;
          setRatingFor(null);
          if (!request) return;
          const result = await removeTargetRating(request.target);
          showWatchToast(result);
        }}
        onClose={() => setRatingFor(null)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  loading: {
    marginTop: 12,
    alignItems: 'center',
    paddingVertical: 20,
  },
  empty: {
    marginTop: 12,
    marginHorizontal: DetailsSectionStyle.inset,
  },
  horizontalContent: {
    paddingHorizontal: DetailsSectionStyle.inset,
    gap: HORIZONTAL_ITEM_SPACING,
    paddingTop: 12,
  },
  card: {
    height: CARD_HEIGHT,
    borderRadius: 16,
    overflow: 'hidden',
    borderWidth: 1,
  },
  cardOverlay: {
    ...StyleSheet.absoluteFill,
    justifyContent: 'flex-end',
  },
  cardBody: {
    padding: 12,
  },
  cardTags: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  cardTag: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  cardTagText: {
    color: '#e5e7eb',
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 0.8,
  },
  cardTitle: {
    color: '#fff',
    fontWeight: '800',
    fontSize: 15,
    marginTop: 6,
  },
  cardOverview: {
    color: 'rgba(255,255,255,0.82)',
    fontSize: 12,
    marginTop: 6,
  },
  spoilerNotice: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 12,
    fontStyle: 'italic',
    marginTop: 6,
  },
  cardMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
    gap: 12,
  },
  metaItem: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  metaText: {
    color: '#9ca3af',
    fontSize: 11,
    marginLeft: 4,
  },
  stremioPill: {
    alignSelf: 'flex-start',
    marginTop: 10,
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.16)',
  },
  stremioPillList: {
    alignSelf: 'flex-start',
    marginTop: 8,
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  stremioText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.6,
  },
  progressTrack: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    height: 4,
    backgroundColor: 'rgba(255,255,255,0.2)',
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#fff',
  },
  cardWatched: {
    position: 'absolute',
    top: 10,
    left: 10,
  },
  cardDownload: {
    position: 'absolute',
    top: 10,
    right: 10,
  },
  cardReveal: {
    position: 'absolute',
    top: 10,
    alignSelf: 'center',
  },
  ratingChip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    paddingHorizontal: 6,
    paddingVertical: 3,
    borderRadius: 6,
    marginLeft: 6,
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  ratingText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  revealButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  list: {
    marginTop: 12,
  },
  listRow: {
    flexDirection: 'row',
    marginHorizontal: DetailsSectionStyle.inset,
    marginBottom: 12,
  },
  thumb: {
    width: 140,
    height: 78,
    borderRadius: 10,
    overflow: 'hidden',
  },
  thumbReveal: {
    ...StyleSheet.absoluteFill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  listBody: {
    flex: 1,
    marginLeft: 12,
    justifyContent: 'center',
  },
  listTitle: {
    fontWeight: '800',
  },
  listMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    marginTop: 2,
  },
  listMetaText: {
    fontSize: 13,
  },
  spoilerNoticeList: {
    fontSize: 12,
    fontStyle: 'italic',
    marginTop: 2,
  },
  listActions: {
    alignItems: 'center',
    justifyContent: 'center',
    marginLeft: 8,
    gap: 8,
  },
});
