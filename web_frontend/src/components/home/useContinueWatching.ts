import { useCallback, useEffect, useRef, useState } from 'react';
import { getContinueWatching, type ContinueWatchingItem } from '@/services/continueWatching';
import { subscribeWatchState } from '@/services/watchState';
import { useSettings, type ContinueWatchingSort, type ContinueWatchingSource } from '@/state/settings';

/** Refreshes on return to the tab or page, at most this often. */
const STALE_AFTER_MS = 20_000;
/** Background refresh while the tab stays visible. */
const POLL_INTERVAL_MS = 30_000;

export type ContinueWatchingStatus = 'loading' | 'loaded' | 'empty' | 'error';

// Survives leaving Home, so coming back shows the row at once.
let lastLoaded: { source: ContinueWatchingSource; items: ContinueWatchingItem[]; at: number } | null = null;

function isPlaybackActive() {
  if (window.location.pathname.startsWith('/player/')) return true;
  if (document.pictureInPictureElement) return true;
  return !!(window as any).documentPictureInPicture?.window;
}

function isPaused() {
  return document.hidden || isPlaybackActive();
}

function sameItems(a: ContinueWatchingItem[], b: ContinueWatchingItem[]) {
  return JSON.stringify(a) === JSON.stringify(b);
}

export function sortContinueWatching(items: ContinueWatchingItem[], sort: ContinueWatchingSort) {
  if (sort === 'nextEpisodeFirst') return [...items.filter((i) => i.isNextUp), ...items.filter((i) => !i.isNextUp)];
  if (sort === 'title') {
    return [...items].sort((a, b) => a.title.localeCompare(b.title, undefined, { numeric: true, sensitivity: 'base' }));
  }
  return items;
}

/** Continue Watching items, refreshed in the background without disturbing the row. */
export function useContinueWatching(enabled: boolean) {
  const settings = useSettings();
  const source = settings.continueWatchingSource;
  const initial = lastLoaded?.source === source ? lastLoaded.items : null;
  const [items, setItems] = useState<ContinueWatchingItem[]>(initial ?? []);
  const [status, setStatus] = useState<ContinueWatchingStatus>(initial ? (initial.length ? 'loaded' : 'empty') : 'loading');
  const [error, setError] = useState<string | null>(null);
  const lastRefresh = useRef(lastLoaded?.source === source ? lastLoaded.at : 0);
  const requestId = useRef(0);
  const hasItems = useRef(!!initial?.length);

  const refresh = useCallback(async () => {
    const id = ++requestId.current;
    lastRefresh.current = Date.now();
    try {
      const fresh = await getContinueWatching(source);
      if (id !== requestId.current) return;
      lastLoaded = { source, items: fresh, at: Date.now() };
      hasItems.current = fresh.length > 0;
      setError(null);
      setItems((current) => (sameItems(current, fresh) ? current : fresh));
      setStatus(fresh.length ? 'loaded' : 'empty');
    } catch (err: any) {
      if (id !== requestId.current) return;
      // A failed background refresh keeps the row it already has.
      if (hasItems.current) return;
      setError(err?.message || 'Could not load Continue Watching');
      setStatus('error');
    }
  }, [source]);

  useEffect(() => {
    if (!enabled) return;
    if (Date.now() - lastRefresh.current >= STALE_AFTER_MS) refresh();

    const refreshIfStale = () => {
      if (isPaused() || Date.now() - lastRefresh.current < STALE_AFTER_MS) return;
      refresh();
    };
    const poll = () => {
      if (!isPaused()) refresh();
    };

    const timer = window.setInterval(poll, POLL_INTERVAL_MS);
    document.addEventListener('visibilitychange', refreshIfStale);
    window.addEventListener('focus', refreshIfStale);
    const unsubscribe = subscribeWatchState(() => refresh());
    return () => {
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', refreshIfStale);
      window.removeEventListener('focus', refreshIfStale);
      unsubscribe();
    };
  }, [enabled, refresh]);

  /** Removes an item right away. Returns a function that puts it back. */
  const removeOptimistically = useCallback((id: string) => {
    let previous: ContinueWatchingItem[] = [];
    setItems((current) => {
      previous = current;
      const next = current.filter((item) => item.id !== id);
      if (next.length === 0) setStatus('empty');
      return next;
    });
    return () => {
      setItems(previous);
      setStatus(previous.length ? 'loaded' : 'empty');
    };
  }, []);

  const retry = useCallback(() => {
    setStatus('loading');
    setError(null);
    refresh();
  }, [refresh]);

  return { items: sortContinueWatching(items, settings.continueWatchingSort), status, error, retry, refresh, removeOptimistically };
}
