/**
 * The addon sources for the title playing now, refreshable from the sources panel.
 * macOS reference: ViewModels/PlayerViewModel+EpisodeBrowser.swift (Sources)
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { fetchStreamsForRecovery, identityForStreamParams } from '../../../stremio/StreamRecovery';
import type { GenericStreamParams, StremioPlayableStream } from '../../../stremio/types';

export function useStreamSourceList(params: GenericStreamParams | null) {
  const [sources, setSources] = useState<StremioPlayableStream[]>(params?.availableStreams ?? []);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const sourcesRef = useRef(sources);
  sourcesRef.current = sources;
  const refreshingRef = useRef(false);
  const refreshedOnceRef = useRef(false);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const refresh = useCallback(async () => {
    const identity = params ? identityForStreamParams(params) : null;
    if (!identity || refreshingRef.current) {
      return;
    }
    refreshingRef.current = true;
    refreshedOnceRef.current = true;
    setIsRefreshing(true);
    try {
      const results = await fetchStreamsForRecovery(identity);
      const streams = (results ?? []).flatMap((result) => result.streams);
      if (mountedRef.current && streams.some((stream) => stream.playable)) {
        setSources(streams);
      }
    } finally {
      refreshingRef.current = false;
      if (mountedRef.current) {
        setIsRefreshing(false);
      }
    }
  }, [params]);

  /** First open only: playback can start from a cached source or before slow addons answered. */
  const refreshIfNeeded = useCallback(() => {
    if (!refreshedOnceRef.current) {
      refresh();
    }
  }, [refresh]);

  return { sources, sourcesRef, isRefreshing, refresh, refreshIfNeeded };
}
