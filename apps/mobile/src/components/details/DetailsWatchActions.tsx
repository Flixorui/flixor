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
      <View style={styles.iconBox}>
        {busy ? (
          <ActivityIndicator size="small" color={theme.textPrimary} />
        ) : (
          <>
            <Ionicons name={icon} size={22} color={tint ?? theme.textPrimary} />
            {badge ? (
              <View style={[styles.badge, { backgroundColor: theme.accent }]}>
                <Text style={[styles.badgeText, { color: theme.onAccent }]}>{badge}</Text>
              </View>
            ) : null}
          </>
        )}
      </View>
      <Text numberOfLines={1} style={[styles.label, { color: theme.textPrimary }]}>
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
  const theme = useTheme();
  const model = useDetailsTitleActions(target, episodeTotal);
  const [showMenu, setShowMenu] = useState(false);
  const [showRating, setShowRating] = useState(false);
  const [menuSeason, setMenuSeason] = useState<DetailsSeasonOption | null>(null);

  const isCollection = target?.kind === 'show' || target?.kind === 'season';
  const watched = model.isWatched === true;
  const icon: keyof typeof Ionicons.glyphMap = watched
    ? 'checkmark-circle'
    : model.isInProgress
      ? 'contrast-outline'
      : 'checkmark-circle-outline';

  const label = watched ? 'WATCHED' : model.isInProgress && isCollection ? 'PARTLY' : 'UNWATCHED';

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
        <DetailsActionLabel icon={icon} label={label} tint={watched ? theme.accentBright : undefined} busy={model.isWorking} />
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
            label={model.userRating ? 'RATED' : 'RATE'}
            tint={model.userRating ? theme.warning : undefined}
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
  action: {
    alignItems: 'center',
    minWidth: 58,
  },
  iconBox: {
    width: 28,
    height: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  label: {
    marginTop: 4,
    fontSize: 11,
    fontWeight: '600',
  },
  badge: {
    position: 'absolute',
    top: -6,
    right: -8,
    minWidth: 15,
    paddingHorizontal: 3,
    borderRadius: 8,
    alignItems: 'center',
  },
  badgeText: {
    fontSize: 9,
    fontWeight: '700',
  },
});
