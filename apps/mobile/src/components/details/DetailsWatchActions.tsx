/**
 * Hero action-row controls: watched toggle (movies and episodes), watched menu (shows,
 * with per-season options) and the Trakt rate button.
 * macOS reference: Views/Details/DetailsWatchActions.swift
 */

import React, { useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import DetailsActionSheet, { type DetailsAction } from './DetailsActionSheet';
import DetailsRatingSheet from './DetailsRatingSheet';
import { useDetailsTitleActions } from './useDetailsTitleActions';
import { useTheme } from '../../hooks/useTheme';
import type { WatchStateTarget } from '../../core/WatchState';

export interface DetailsSeasonOption {
  id: string;
  title: string;
  target: WatchStateTarget;
}

export function DetailsActionLabel({
  icon,
  label,
  tint,
  busy,
  badge,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  tint?: string;
  busy?: boolean;
  badge?: string;
}) {
  const theme = useTheme();
  return (
    <View style={styles.action}>
      <View style={styles.circle}>
        {busy ? (
          <ActivityIndicator size="small" color={theme.textPrimary} />
        ) : (
          <>
            <Ionicons name={icon} size={22} color={tint ?? theme.textPrimary} />
            {badge ? (
              <View style={styles.badge}>
                <Text style={styles.badgeText}>{badge}</Text>
              </View>
            ) : null}
          </>
        )}
      </View>
      <Text numberOfLines={1} style={[styles.label, { color: theme.textSecondary }]}>
        {label}
      </Text>
    </View>
  );
}

export default function DetailsWatchActions({
  target,
  title,
  episodeTotal,
  seasonOptions,
}: {
  target: WatchStateTarget | null;
  title: string;
  episodeTotal?: number;
  seasonOptions: DetailsSeasonOption[];
}) {
  const model = useDetailsTitleActions(target, episodeTotal);
  const [showMenu, setShowMenu] = useState(false);
  const [showRating, setShowRating] = useState(false);
  const [menuSeason, setMenuSeason] = useState<DetailsSeasonOption | null>(null);

  const isCollection = target?.kind === 'show' || target?.kind === 'season';
  const watched = model.isWatched === true;
  const icon: keyof typeof Ionicons.glyphMap = watched
    ? 'checkmark-circle'
    : model.isInProgress && isCollection
      ? 'contrast-outline'
      : 'checkmark-circle-outline';

  const label = watched ? 'Watched' : model.isInProgress && isCollection ? 'In progress' : 'Mark watched';

  const menuActions = useMemo<DetailsAction[]>(() => {
    if (menuSeason) {
      return [
        {
          key: 'season-watched',
          title: 'Mark as Watched',
          icon: 'checkmark-circle-outline',
          onPress: () => model.setWatched(true, menuSeason.target),
        },
        {
          key: 'season-unwatched',
          title: 'Mark as Unwatched',
          icon: 'arrow-undo-outline',
          onPress: () => model.setWatched(false, menuSeason.target),
        },
      ];
    }
    const noun = target?.kind === 'show' ? 'Show' : 'Season';
    const actions: DetailsAction[] = [
      {
        key: 'watched',
        title: `Mark ${noun} as Watched`,
        icon: 'checkmark-circle-outline',
        disabled: watched,
        onPress: () => model.setWatched(true),
      },
      {
        key: 'unwatched',
        title: `Mark ${noun} as Unwatched`,
        icon: 'arrow-undo-outline',
        disabled: model.isWatched === false && !model.isInProgress,
        onPress: () => model.setWatched(false),
      },
    ];
    for (const season of seasonOptions) {
      actions.push({
        key: `season-${season.id}`,
        title: season.title,
        icon: 'albums-outline',
        keepOpen: true,
        onPress: () => setMenuSeason(season),
      });
    }
    return actions;
  }, [menuSeason, target?.kind, watched, model.isWatched, model.isInProgress, model.setWatched, seasonOptions]);

  if (!target) return null;

  const onWatchedPress = () => {
    if (isCollection) setShowMenu(true);
    else model.setWatched(!watched);
  };

  return (
    <>
      <Pressable
        onPress={onWatchedPress}
        disabled={model.isWorking}
        accessibilityRole="button"
        accessibilityLabel={isCollection ? 'Watched status' : watched ? 'Mark as unwatched' : 'Mark as watched'}
        accessibilityValue={{ text: model.progressText ?? (watched ? 'Watched' : 'Not watched') }}
      >
        <DetailsActionLabel icon={icon} label={label} busy={model.isWorking} />
      </Pressable>

      {model.canRate ? (
        <Pressable
          onPress={() => setShowRating(true)}
          disabled={model.isRatingWorking}
          accessibilityRole="button"
          accessibilityLabel="Rate"
          accessibilityValue={{ text: model.userRating ? `${model.userRating} out of 10` : 'Not rated' }}
        >
          <DetailsActionLabel
            icon={model.userRating ? 'star' : 'star-outline'}
            label={model.userRating ? 'Rated' : 'Rate'}
            busy={model.isRatingWorking}
            badge={model.userRating ? String(model.userRating) : undefined}
          />
        </Pressable>
      ) : null}

      <DetailsActionSheet
        visible={showMenu || menuSeason !== null}
        title={menuSeason ? menuSeason.title : title}
        message={menuSeason ? undefined : model.progressText ?? undefined}
        actions={menuActions}
        onClose={() => {
          setShowMenu(false);
          setMenuSeason(null);
        }}
      />

      <DetailsRatingSheet
        visible={showRating}
        title={title}
        initialRating={model.userRating}
        onSave={(value) => {
          setShowRating(false);
          model.rate(value);
        }}
        onRemove={() => {
          setShowRating(false);
          model.removeRating();
        }}
        onClose={() => setShowRating(false)}
      />
    </>
  );
}

const styles = StyleSheet.create({
  // Round neutral buttons, as in the macOS Details hero: a 48 pt circle with a caption.
  action: {
    alignItems: 'center',
    minWidth: 64,
  },
  circle: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: 'rgba(255,255,255,0.12)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  label: {
    marginTop: 6,
    fontSize: 12,
    fontWeight: '500',
  },
  badge: {
    position: 'absolute',
    top: 2,
    right: 0,
    minWidth: 16,
    paddingHorizontal: 3,
    borderRadius: 8,
    alignItems: 'center',
    backgroundColor: '#fff',
  },
  badgeText: {
    fontSize: 10,
    fontWeight: '700',
    color: '#000',
  },
});
