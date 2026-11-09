import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { ContinueWatchingResult, PlexMediaItem } from '@flixor/core';
import { getFlixorCore } from '../../core/index';
import { getShowTmdbId, getTmdbBackdropWithTitle } from '../../core/HomeData';
import { extractTmdbIdFromGuids } from '../../core/DetailsData';
import { addContinueWatchingDismissal } from '../../core/HomeRowsStore';
import { ITEM_LIMITS } from '../../core/PerformanceConfig';
import type { AppSettings } from '../../core/SettingsData';
import {
  buildWatchStateTarget,
  effectiveContinueWatchingSource,
  fetchTraktContinueWatchingEntries,
  loadLocalContinueWatchingEntries,
  mapPlexContinueWatching,
  mergeContinueWatching,
  sortContinueWatching,
  type ContinueWatchingEntry,
} from '../../core/TraktContinueWatching';
import {
  markWatched,
  removeFromContinueWatching,
  startOver,
  type WatchStateResult,
} from '../../core/WatchState';
import { showToast } from '../Toast';

export type ContinueWatchingStateAction = 'startOver' | 'markWatched' | 'remove';

/** How long a removed card stays hidden while servers catch up. */
const REMOVAL_GRACE_MS = 10_000;
const BACKDROP_CONCURRENCY = 4;
const EMPTY_RESULT: ContinueWatchingResult = { items: [], itemsWithMultipleVersions: new Set() };

type CwSettings = Pick<
  AppSettings,
  | 'continueWatchingSource'
  | 'continueWatchingSort'
  | 'continueWatchingTraktDismissals'
  | 'showTraktContinueWatching'
  | 'discoveryDisabled'
>;

function plexSignature(items: PlexMediaItem[]): string {
  return items.map((item) => `${item.ratingKey}:${item.viewOffset ?? 0}`).join('|');
}

function entriesSignature(entries: ContinueWatchingEntry[] | null): string {
  if (!entries) return '';
  return entries.map((entry) => `${entry.key}:${entry.positionMs ?? 0}:${entry.lastActivity ?? 0}`).join('|');
}

async function fetchPlexBackdrop(item: PlexMediaItem): Promise<string | null | undefined> {
  let tmdbId: string | null | undefined = null;
  let mediaType: 'movie' | 'tv' = 'movie';
  if (item.type === 'movie') {
    tmdbId = extractTmdbIdFromGuids(item.Guid || []);
  } else if (item.type === 'episode' && item.grandparentRatingKey) {
    tmdbId = await getShowTmdbId(item.grandparentRatingKey);
    mediaType = 'tv';
  }
  return tmdbId ? getTmdbBackdropWithTitle(Number(tmdbId), mediaType) : null;
}

/**
 * The single Continue Watching row: Plex or this device's history, combined with Trakt
 * according to the chosen source, with optimistic actions. macOS reference:
 * HomeViewModel.publishContinueWatching and HomeViewModel+ContinueWatching.swift.
 */
export function useContinueWatching(settings: CwSettings, isStremioOnly: boolean) {
  const [plexResult, setPlexResult] = useState<ContinueWatchingResult>(EMPTY_RESULT);
  const [backdrops, setBackdrops] = useState<Record<string, string>>({});
  const [traktEntries, setTraktEntries] = useState<ContinueWatchingEntry[] | null>(null);
  const [localEntries, setLocalEntries] = useState<ContinueWatchingEntry[]>([]);
  const [removed, setRemoved] = useState<Record<string, number>>({});

  const source = effectiveContinueWatchingSource(settings);
  const sourceRef = useRef(source);
  sourceRef.current = source;
  const stremioOnlyRef = useRef(isStremioOnly);
  stremioOnlyRef.current = isStremioOnly;

  const backdropsRequestedRef = useRef(new Set<string>());
  const refreshTokenRef = useRef(0);
  const busyRef = useRef(new Set<string>());

  const loadBackdrops = useCallback((items: PlexMediaItem[]) => {
    const pending = items.filter((item) => item.ratingKey && !backdropsRequestedRef.current.has(item.ratingKey));
    pending.forEach((item) => backdropsRequestedRef.current.add(item.ratingKey));
    let next = 0;
    const worker = async () => {
      while (next < pending.length) {
        const item = pending[next++];
        try {
          const backdrop = await fetchPlexBackdrop(item);
          if (backdrop) setBackdrops((prev) => ({ ...prev, [item.ratingKey]: backdrop }));
        } catch {
          // Falls back to Plex art.
        }
      }
    };
    for (let i = 0; i < Math.min(BACKDROP_CONCURRENCY, pending.length); i += 1) worker();
  }, []);

  /** Applies a Plex result. Leaves the row alone when nothing changed. */
  const applyPlexResult = useCallback(
    (result: ContinueWatchingResult) => {
      setPlexResult((prev) => (plexSignature(prev.items) === plexSignature(result.items) ? prev : result));
      loadBackdrops(result.items);
    },
    [loadBackdrops]
  );

  /** Refreshes Trakt and local history. Failures keep what is on screen. */
  const refresh = useCallback(async (options?: { force?: boolean }) => {
    const token = ++refreshTokenRef.current;
    const startedAt = Date.now();
    const wantsTrakt = sourceRef.current !== 'library' && getFlixorCore().isTraktAuthenticated;

    const [trakt, local] = await Promise.all([
      wantsTrakt
        ? fetchTraktContinueWatchingEntries(options).catch((e) => {
            console.log('[Home] Trakt Continue Watching failed:', e);
            return undefined;
          })
        : Promise.resolve(null),
      stremioOnlyRef.current ? loadLocalContinueWatchingEntries().catch(() => undefined) : Promise.resolve([]),
    ]);

    if (token !== refreshTokenRef.current) return;
    if (trakt !== undefined) {
      setTraktEntries((prev) => (entriesSignature(prev) === entriesSignature(trakt) && (prev === null) === (trakt === null) ? prev : trakt));
    }
    if (local !== undefined) {
      setLocalEntries((prev) => (entriesSignature(prev) === entriesSignature(local) ? prev : local));
    }
    setRemoved((prev) => {
      const kept = Object.entries(prev).filter(([, removedAt]) => startedAt - removedAt <= REMOVAL_GRACE_MS);
      return kept.length === Object.keys(prev).length ? prev : Object.fromEntries(kept);
    });
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh, source, isStremioOnly]);

  const plexEntries = useMemo(() => mapPlexContinueWatching(plexResult, backdrops), [plexResult, backdrops]);

  const entries = useMemo(() => {
    const primary = isStremioOnly ? localEntries : plexEntries;
    let merged = primary;
    if (source !== 'library' && traktEntries) {
      merged = mergeContinueWatching(
        source === 'trakt' ? [] : primary,
        traktEntries,
        settings.continueWatchingTraktDismissals
      );
    }
    const visible = merged.filter((entry) => removed[entry.key] === undefined);
    return sortContinueWatching(visible, settings.continueWatchingSort).slice(0, ITEM_LIMITS.ROW);
  }, [
    isStremioOnly,
    localEntries,
    plexEntries,
    source,
    traktEntries,
    settings.continueWatchingTraktDismissals,
    settings.continueWatchingSort,
    removed,
  ]);

  /** Runs a watch-state action. The card leaves right away and returns on failure. */
  const performAction = useCallback(
    async (action: ContinueWatchingStateAction, entry: ContinueWatchingEntry): Promise<WatchStateResult | null> => {
      if (busyRef.current.has(entry.key)) return null;
      busyRef.current.add(entry.key);
      const target = buildWatchStateTarget(entry);
      if (action !== 'startOver') setRemoved((prev) => ({ ...prev, [entry.key]: Date.now() }));

      let result: WatchStateResult | null = null;
      try {
        if (action === 'startOver') result = await startOver(target);
        else if (action === 'markWatched') result = await markWatched(target);
        else result = await removeFromContinueWatching(target);
      } catch (e) {
        console.log('[Home] Continue Watching action failed:', e);
      }
      busyRef.current.delete(entry.key);

      const succeeded = !!result && (result.isSuccess || result.isPartialSuccess);
      if (action !== 'startOver') {
        if (succeeded) {
          // A next-up card has nothing to delete on Trakt, so remember it was removed.
          await addContinueWatchingDismissal(entry.key);
        } else {
          setRemoved((prev) => {
            const { [entry.key]: _restored, ...rest } = prev;
            return rest;
          });
        }
      }

      if (result) {
        showToast(result.message, { kind: result.isSuccess ? 'success' : result.isPartialSuccess ? 'info' : 'error' });
      } else {
        showToast("Couldn't update this item", { kind: 'error' });
      }
      return result;
    },
    []
  );

  return { entries, plexItems: plexResult.items, applyPlexResult, refresh, performAction };
}
