import { useCallback, useEffect, useRef, useState } from 'react';
import { plexBackendMetadata } from '@/services/plex_backend';
import {
  canRate as canRateOnTrakt,
  getRating,
  isWatchedLocally,
  locallyWatchedEpisodes,
  markUnwatched,
  markWatched,
  rate as rateOnTrakt,
  resolveWatchTarget,
  subscribeWatchState,
  WatchStateError,
  type WatchStateChange,
  type WatchTarget,
} from '@/services/watchState';

export interface DetailsTitleActions {
  kind?: WatchTarget['kind'];
  /** Null while unknown. */
  isWatched: boolean | null;
  isInProgress: boolean;
  /** For example "3 of 10 episodes watched". */
  progressText?: string;
  isWorking: boolean;
  setWatched: (watched: boolean, target?: WatchTarget) => Promise<void>;
  canRate: boolean;
  userRating: number | null;
  isRatingWorking: boolean;
  rate: (value: number | null) => Promise<void>;
}

/** Watch state and Trakt rating for the title on screen. */
export function useDetailsTitleActions(
  target: WatchTarget | undefined,
  options: { episodeTotal?: number; onMessage: (message: string) => void },
): DetailsTitleActions {
  const { episodeTotal, onMessage } = options;
  const [isWatched, setIsWatched] = useState<boolean | null>(null);
  const [isInProgress, setIsInProgress] = useState(false);
  const [progressText, setProgressText] = useState<string | undefined>(undefined);
  const [isWorking, setIsWorking] = useState(false);
  const [userRating, setUserRating] = useState<number | null>(null);
  const [isRatingWorking, setIsRatingWorking] = useState(false);

  const targetRef = useRef(target);
  targetRef.current = target;
  const workingRef = useRef(false);
  const requestRef = useRef(0);

  const refresh = useCallback(async () => {
    const current = targetRef.current;
    if (!current) return;
    const request = ++requestRef.current;
    const apply = (watched: boolean, inProgress: boolean, text?: string) => {
      if (request !== requestRef.current || workingRef.current) return;
      setIsWatched(watched);
      setIsInProgress(inProgress);
      setProgressText(text);
    };

    if (current.plexRatingKey) {
      const data: any = await plexBackendMetadata(current.plexRatingKey).catch(() => null);
      const meta = data?.MediaContainer?.Metadata?.[0];
      if (meta) {
        if (current.kind === 'movie' || current.kind === 'episode') {
          const watched = (meta.viewCount ?? 0) > 0;
          const inProgress = !watched && (meta.viewOffset ?? 0) > 0;
          apply(watched, inProgress, inProgress ? 'In progress' : undefined);
        } else {
          const total = meta.leafCount ?? 0;
          const viewed = meta.viewedLeafCount ?? 0;
          const inProgress = viewed > 0 && viewed < total;
          apply(total > 0 && viewed >= total, inProgress, inProgress ? `${viewed} of ${total} episodes watched` : undefined);
        }
        return;
      }
    }

    if (current.kind === 'movie' || current.kind === 'episode') {
      apply(await isWatchedLocally(current), false);
      return;
    }

    const resolved = await resolveWatchTarget(current, true);
    const count = locallyWatchedEpisodes(
      { tmdbId: resolved.titleTmdbId, imdbId: resolved.titleImdbId },
      current.kind === 'season' ? current.seasonNumber : undefined,
    ).size;
    if (current.kind === 'show' && episodeTotal && episodeTotal > 0) {
      const inProgress = count > 0 && count < episodeTotal;
      apply(count >= episodeTotal, inProgress, inProgress ? `${count} of ${episodeTotal} episodes watched` : undefined);
    } else {
      apply(false, count > 0, count > 0 ? `${count} episodes watched` : undefined);
    }
  }, [episodeTotal]);

  const targetKey = target ? JSON.stringify(target) : '';

  useEffect(() => {
    setIsWatched(null);
    setIsInProgress(false);
    setProgressText(undefined);
    setUserRating(null);
    if (!targetRef.current) return;
    refresh();
    let alive = true;
    if (canRateOnTrakt()) {
      getRating(targetRef.current).then((rating) => {
        if (alive) setUserRating(rating);
      });
    }
    return () => { alive = false; };
  }, [targetKey, refresh]);

  useEffect(() => subscribeWatchState((change: WatchStateChange) => {
    const current = targetRef.current;
    if (!current || workingRef.current || change.action === 'rate' || change.action === 'removeRating') return;
    if (relates(change.target, current)) refresh();
  }), [refresh]);

  const setWatched = useCallback(async (watched: boolean, actionTarget?: WatchTarget) => {
    const titleTarget = targetRef.current;
    const applied = actionTarget ?? titleTarget;
    if (!applied || workingRef.current) return;
    const affectsTitle = !actionTarget;
    const previous = { isWatched, isInProgress, progressText };

    if (affectsTitle) {
      setIsWatched(watched);
      setIsInProgress(false);
      setProgressText(undefined);
    }
    workingRef.current = true;
    setIsWorking(true);
    try {
      const result = await (watched ? markWatched(applied) : markUnwatched(applied));
      onMessage(result.message);
      workingRef.current = false;
      setIsWorking(false);
      refresh();
    } catch (error) {
      workingRef.current = false;
      setIsWorking(false);
      if (affectsTitle) {
        setIsWatched(previous.isWatched);
        setIsInProgress(previous.isInProgress);
        setProgressText(previous.progressText);
      }
      onMessage(error instanceof WatchStateError ? error.message : "Couldn't update watched status");
    }
  }, [isWatched, isInProgress, progressText, onMessage, refresh]);

  const rate = useCallback(async (value: number | null) => {
    const current = targetRef.current;
    if (!current || isRatingWorking) return;
    const previous = userRating;
    setUserRating(value);
    setIsRatingWorking(true);
    try {
      const result = await rateOnTrakt(current, value);
      onMessage(result.message);
    } catch (error) {
      setUserRating(previous);
      onMessage(error instanceof WatchStateError ? error.message : "Couldn't save rating");
    } finally {
      setIsRatingWorking(false);
    }
  }, [isRatingWorking, userRating, onMessage]);

  return {
    kind: target?.kind,
    isWatched,
    isInProgress,
    progressText,
    isWorking,
    setWatched,
    canRate: canRateOnTrakt() && !!target,
    userRating,
    isRatingWorking,
    rate,
  };
}

/** Whether a change to `other` can affect the title on screen. */
function relates(other: WatchTarget, mine: WatchTarget): boolean {
  if (mine.plexRatingKey && (mine.plexRatingKey === other.plexRatingKey || mine.plexRatingKey === other.showPlexRatingKey)) return true;
  if (mine.showPlexRatingKey && mine.showPlexRatingKey === other.plexRatingKey) return true;
  if ((mine.kind === 'movie') !== (other.kind === 'movie')) return false;
  const showTmdb = (t: WatchTarget) => t.showTmdbId ?? t.tmdbId;
  if (showTmdb(mine) != null && showTmdb(mine) === showTmdb(other)) return true;
  const showImdb = (t: WatchTarget) => (t.showImdbId ?? t.imdbId)?.toLowerCase();
  return showImdb(mine) != null && showImdb(mine) === showImdb(other);
}
