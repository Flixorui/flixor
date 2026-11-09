/**
 * Per-page episode extras: TMDB ratings, watched state (Plex progress, local and Trakt
 * marks, optimistic overrides), watched actions and spoiler reveals.
 * macOS reference: ViewModels/DetailsEpisodeStateModel.swift
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { isStremioOnlyMode } from '../../core/AppMode';
import type { TMDBEpisodeData } from '../../core/DetailsData';
import {
  addWatchStateListener,
  episodeWatchKey,
  locallyWatchedEpisodes,
  markUnwatched,
  markWatched,
  traktWatchedEpisodes,
  type WatchStateResult,
  type WatchStateTarget,
} from '../../core/WatchState';
import { didFail, showWatchToast } from './watchToast';

export interface EpisodeStateInput {
  episodes: any[];
  seasonNumber: number | null;
  seasonKey: string | null;
  tmdbMode: boolean;
  tmdbId?: number;
  imdbId?: string;
  showTitle: string;
  tmdbEpisodeData?: Map<number, TMDBEpisodeData>;
  /** Reloads the list after a change, so Plex view counts are fresh. */
  onChanged: () => void | Promise<void>;
}

export function episodeNumberOf(ep: any): number | undefined {
  return ep.index ?? ep.episode_number;
}

export function seasonNumberOf(ep: any, fallback: number | null): number | undefined {
  return ep.parentIndex ?? ep.season_number ?? fallback ?? undefined;
}

/** 0-100, or undefined when the list carries no progress (TMDB-sourced lists). */
export function episodeProgress(ep: any, tmdbMode: boolean): number | undefined {
  if (tmdbMode) return undefined;
  const duration = (ep.duration || 0) / 1000;
  const offset = (ep.viewOffset || 0) / 1000;
  if ((ep.viewCount || 0) > 0) return 100;
  if (duration > 0 && offset / duration >= 0.95) return 100;
  if (duration > 0) return Math.round((offset / duration) * 100);
  return undefined;
}

export function useDetailsEpisodeState(input: EpisodeStateInput) {
  const { episodes, seasonNumber, seasonKey, tmdbMode, tmdbId, imdbId, showTitle, tmdbEpisodeData, onChanged } = input;

  const [marked, setMarked] = useState<Set<string>>(new Set());
  const [overrides, setOverrides] = useState<Map<string, boolean>>(new Map());
  const [revealed, setRevealed] = useState<Set<string>>(new Set());
  const [seasonBusy, setSeasonBusy] = useState(false);

  const onChangedRef = useRef(onChanged);
  onChangedRef.current = onChanged;

  const episodeId = useCallback(
    (ep: any) => String(ep.ratingKey ?? `${seasonNumberOf(ep, seasonNumber)}:${episodeNumberOf(ep)}`),
    [seasonNumber]
  );

  const refreshMarks = useCallback(async () => {
    if (tmdbId == null && !imdbId) {
      setMarked(new Set());
      return;
    }
    const show = { tmdbId, imdbId };
    const [local, trakt] = await Promise.all([
      locallyWatchedEpisodes(show),
      // Plex lists carry their own view counts
      tmdbMode ? traktWatchedEpisodes(show) : Promise.resolve(new Set<string>()),
    ]);
    setMarked(new Set([...local, ...trakt]));
  }, [tmdbId, imdbId, tmdbMode]);

  useEffect(() => {
    refreshMarks();
  }, [refreshMarks]);

  useEffect(() => {
    setOverrides(new Map());
    setRevealed(new Set());
  }, [seasonKey]);

  useEffect(() => {
    return addWatchStateListener((change) => {
      if (change.target.kind === 'movie' || change.action === 'rate' || change.action === 'removeRating') return;
      const sameShow =
        (tmdbId != null && change.target.tmdbId === tmdbId) ||
        (!!imdbId && change.target.imdbId?.toLowerCase() === imdbId.toLowerCase());
      const canCompare = tmdbId != null || !!imdbId;
      if (canCompare && !sameShow) return;
      Promise.resolve(onChangedRef.current())
        .then(refreshMarks)
        .finally(() => setOverrides(new Map()));
    });
  }, [tmdbId, imdbId, tmdbMode, refreshMarks]);

  const isWatched = useCallback(
    (ep: any): boolean => {
      const override = overrides.get(episodeId(ep));
      if (override !== undefined) return override;
      if ((episodeProgress(ep, tmdbMode) ?? 0) >= 85) return true;
      const season = seasonNumberOf(ep, seasonNumber);
      const episode = episodeNumberOf(ep);
      return season != null && episode != null && marked.has(episodeWatchKey(season, episode));
    },
    [overrides, marked, tmdbMode, seasonNumber, episodeId]
  );

  const isRevealed = useCallback((ep: any) => revealed.has(episodeId(ep)), [revealed, episodeId]);

  const toggleRevealed = useCallback(
    (ep: any) => {
      const id = episodeId(ep);
      setRevealed((current) => {
        const next = new Set(current);
        if (!next.delete(id)) next.add(id);
        return next;
      });
    },
    [episodeId]
  );

  const rating = useCallback(
    (ep: any): number | null => {
      const number = episodeNumberOf(ep);
      const value = tmdbMode ? ep.vote_average : number != null ? tmdbEpisodeData?.get(number)?.vote_average : undefined;
      return typeof value === 'number' && value > 0 ? value : null;
    },
    [tmdbMode, tmdbEpisodeData]
  );

  const episodeTarget = useCallback(
    (ep: any): WatchStateTarget => ({
      kind: 'episode',
      plexRatingKey: tmdbMode || isStremioOnlyMode() || !ep.ratingKey ? undefined : String(ep.ratingKey),
      tmdbId,
      imdbId,
      seasonNumber: seasonNumberOf(ep, seasonNumber),
      episodeNumber: episodeNumberOf(ep),
      title: showTitle,
    }),
    [tmdbMode, tmdbId, imdbId, seasonNumber, showTitle]
  );

  const seasonTarget = useMemo((): WatchStateTarget | null => {
    const plexKey = !tmdbMode && seasonKey && !isStremioOnlyMode() ? seasonKey : undefined;
    if (!plexKey && seasonNumber == null) return null;
    return { kind: 'season', plexRatingKey: plexKey, seasonNumber: seasonNumber ?? undefined, tmdbId, imdbId, title: showTitle };
  }, [tmdbMode, seasonKey, seasonNumber, tmdbId, imdbId, showTitle]);

  const applyResult = useCallback((result: WatchStateResult, rollback: () => void) => {
    if (didFail(result)) rollback();
    showWatchToast(result);
  }, []);

  const setEpisodeWatched = useCallback(
    async (ep: any, watched: boolean) => {
      const id = episodeId(ep);
      const previous = overrides.get(id);
      setOverrides((current) => new Map(current).set(id, watched));
      const target = episodeTarget(ep);
      const result = await (watched ? markWatched(target) : markUnwatched(target));
      applyResult(result, () =>
        setOverrides((current) => {
          const next = new Map(current);
          if (previous === undefined) next.delete(id);
          else next.set(id, previous);
          return next;
        })
      );
    },
    [episodeId, overrides, episodeTarget, applyResult]
  );

  const setSeasonWatched = useCallback(
    async (watched: boolean) => {
      if (seasonBusy || !seasonTarget) return;
      setSeasonBusy(true);
      const previous = overrides;
      setOverrides((current) => {
        const next = new Map(current);
        episodes.forEach((ep) => next.set(episodeId(ep), watched));
        return next;
      });
      const result = await (watched ? markWatched(seasonTarget) : markUnwatched(seasonTarget));
      setSeasonBusy(false);
      applyResult(result, () => setOverrides(previous));
    },
    [seasonBusy, seasonTarget, overrides, episodes, episodeId, applyResult]
  );

  return { isWatched, isRevealed, toggleRevealed, rating, episodeTarget, setEpisodeWatched, setSeasonWatched, seasonBusy };
}
