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
      const results = await fetchStreamsForRecovery(identity, params?.title);
      const streams = (results ?? []).flatMap((result) => result.streams);
      if (mountedRef.current && streams.some((stream) => stream.playable)) {
        // The addon can leave the playing source out this time (aggregators vary between
        // fetches). Keep it, first in its addon's group, so it stays listed and ticked.
        const playing = params?.uri ? sourcesRef.current.find((stream) => stream.url === params.uri) : undefined;
        if (playing && !streams.some((stream) => stream.url === playing.url)) {
          const index = streams.findIndex((stream) => stream.addonName === playing.addonName);
          streams.splice(index < 0 ? 0 : index, 0, playing);
        }
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
