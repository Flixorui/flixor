/**
 * Watched and rating state for the hero's actions.
 * macOS reference: ViewModels/DetailsTitleActionsModel.swift
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { getFlixorCore } from '../../core';
import { isStremioOnlyMode } from '../../core/AppMode';
import {
  addWatchStateListener,
  canRate,
  getUserRating,
  isWatchedLocally,
  locallyWatchedEpisodes,
  markUnwatched,
  markWatched,
  rate as rateTarget,
  removeRating as removeTargetRating,
  traktWatchedEpisodes,
  type WatchStateChange,
  type WatchStateTarget,
} from '../../core/WatchState';
import { didFail, showWatchToast } from './watchToast';

export interface WatchedState {
  isWatched: boolean | null;
  isInProgress: boolean;
  progressText: string | null;
}

const UNKNOWN: WatchedState = { isWatched: null, isInProgress: false, progressText: null };

function relates(other: WatchStateTarget, mine: WatchStateTarget): boolean {
  if (other.plexRatingKey && other.plexRatingKey === mine.plexRatingKey) return true;
  if (other.tmdbId != null && other.tmdbId === mine.tmdbId) return true;
  return !!other.imdbId && other.imdbId.toLowerCase() === mine.imdbId?.toLowerCase();
}

/** Reads the server's view counts for an item with a Plex copy. Null when unavailable. */
async function plexWatchedState(target: WatchStateTarget): Promise<WatchedState | null> {
  if (!target.plexRatingKey || isStremioOnlyMode()) return null;
  const core = getFlixorCore();
  if (!core.isPlexServerConnected) return null;
  const meta: any = await core.plexServer.getMetadata(target.plexRatingKey).catch(() => null);
  if (!meta) return null;
  if (target.kind === 'movie' || target.kind === 'episode') {
    const watched = (meta.viewCount ?? 0) > 0;
    const inProgress = !watched && (meta.viewOffset ?? 0) > 0;
    return { isWatched: watched, isInProgress: inProgress, progressText: inProgress ? 'In progress' : null };
  }
  const total = meta.leafCount ?? 0;
  const viewed = meta.viewedLeafCount ?? 0;
  const inProgress = viewed > 0 && viewed < total;
  return {
    isWatched: total > 0 && viewed >= total,
    isInProgress: inProgress,
    progressText: inProgress ? `${viewed} of ${total} episodes watched` : null,
  };
}

/** Local and Trakt state for a title with no Plex copy. */
async function offlineWatchedState(target: WatchStateTarget, episodeTotal: number | undefined): Promise<WatchedState> {
  if (target.kind === 'movie' || target.kind === 'episode') {
    return { isWatched: await isWatchedLocally(target), isInProgress: false, progressText: null };
  }
  const show = { tmdbId: target.tmdbId, imdbId: target.imdbId };
  const [local, trakt] = await Promise.all([
    locallyWatchedEpisodes(show, target.kind === 'season' ? target.seasonNumber : undefined),
    traktWatchedEpisodes(show),
  ]);
  const count = new Set([...local, ...trakt]).size;
  const total = episodeTotal ?? 0;
  if (total > 0) {
    const inProgress = count > 0 && count < total;
    return {
      isWatched: count >= total,
      isInProgress: inProgress,
      progressText: inProgress ? `${count} of ${total} episodes watched` : null,
    };
  }
  return {
    isWatched: false,
    isInProgress: count > 0,
    progressText: count > 0 ? `${count} episodes watched` : null,
  };
}

export function useDetailsTitleActions(target: WatchStateTarget | null, episodeTotal: number | undefined) {
  const [watched, setWatchedState] = useState<WatchedState>(UNKNOWN);
  const [isWorking, setIsWorking] = useState(false);
  const [userRating, setUserRating] = useState<number | null>(null);
  const [isRatingWorking, setIsRatingWorking] = useState(false);
  const working = useRef(false);
  const ratingWorking = useRef(false);
  const refreshId = useRef(0);

  const refresh = useCallback(async () => {
    if (!target) {
      setWatchedState(UNKNOWN);
      return;
    }
    const id = ++refreshId.current;
    const state = (await plexWatchedState(target)) ?? (await offlineWatchedState(target, episodeTotal));
    if (id === refreshId.current && !working.current) setWatchedState(state);
  }, [target, episodeTotal]);

  const loadRating = useCallback(async () => {
    if (!target || !canRate()) {
      setUserRating(null);
      return;
    }
    const rating = await getUserRating(target);
    if (!ratingWorking.current) setUserRating(rating);
  }, [target]);

  useEffect(() => {
    setWatchedState(UNKNOWN);
    refresh();
    loadRating();
  }, [refresh, loadRating]);

  useEffect(() => {
    if (!target) return;
    return addWatchStateListener((change: WatchStateChange) => {
      if (!relates(change.target, target)) return;
      if (change.action === 'rate' || change.action === 'removeRating') {
        if (change.target.kind === target.kind && !ratingWorking.current) {
          setUserRating(change.action === 'rate' ? change.rating ?? null : null);
        }
      } else if (!working.current) {
        refresh();
      }
    });
  }, [target, refresh]);

  const setWatched = useCallback(
    async (value: boolean, other?: WatchStateTarget) => {
      if (!target || working.current) return;
      const isWholeTitle = !other;
      const previous = watched;
      working.current = true;
      setIsWorking(true);
      if (isWholeTitle) setWatchedState({ isWatched: value, isInProgress: false, progressText: null });
      const result = await (value ? markWatched(other ?? target) : markUnwatched(other ?? target));
      working.current = false;
      setIsWorking(false);
      showWatchToast(result);
      if (didFail(result)) {
        if (isWholeTitle) setWatchedState(previous);
      } else {
        refresh();
      }
    },
    [target, watched, refresh]
  );

  const rate = useCallback(
    async (value: number) => {
      if (!target || ratingWorking.current) return;
      const previous = userRating;
      ratingWorking.current = true;
      setIsRatingWorking(true);
      setUserRating(value);
      const result = await rateTarget(target, value);
      ratingWorking.current = false;
      setIsRatingWorking(false);
      showWatchToast(result);
      if (didFail(result)) setUserRating(previous);
    },
    [target, userRating]
  );

  const removeRating = useCallback(async () => {
    if (!target || ratingWorking.current) return;
    const previous = userRating;
    ratingWorking.current = true;
    setIsRatingWorking(true);
    setUserRating(null);
    const result = await removeTargetRating(target);
    ratingWorking.current = false;
    setIsRatingWorking(false);
    showWatchToast(result);
    if (didFail(result)) setUserRating(previous);
  }, [target, userRating]);

  return {
    ...watched,
    isWorking,
    canRate: !!target && canRate(),
    userRating,
    isRatingWorking,
    setWatched,
    rate,
    removeRating,
  };
}
