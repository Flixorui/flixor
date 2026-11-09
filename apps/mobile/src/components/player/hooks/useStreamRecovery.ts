/**
 * Dead-link recovery for addon streams: when the source fails the streams for the
 * same title are re-fetched once, the closest match is played from the saved
 * position, and the dead URL leaves the stream cache. Attempts travel through the
 * route because each replacement is a new Player. Bounded, so it never loops.
 * macOS reference: ViewModels/PlayerViewModel+StreamRecovery.swift
 */

import { useCallback, useEffect, useRef, useState, type MutableRefObject } from 'react';
import { appLogger } from '../../../core/AppLogger';
import { bestSourceMatch } from '../../../stremio/StremioSourceRanking';
import {
  fetchStreamsForRecovery,
  groupStreamsByAddon,
  identityForStreamParams,
  MAX_STREAM_RECOVERY_ATTEMPTS,
  removeCachedSourceIfFailed,
  streamRouteFor,
} from '../../../stremio/StreamRecovery';
import type { GenericStreamParams, StremioPlayableStream } from '../../../stremio/types';

type Options = {
  params: GenericStreamParams | null;
  fileLoaded: boolean;
  sourcesRef: MutableRefObject<StremioPlayableStream[]>;
  currentStream: StremioPlayableStream | null;
  positionRef: MutableRefObject<number>;
  onReplace: (route: GenericStreamParams) => void;
  onExhausted: (early: boolean) => void;
};

function recoveryMessage(attempt: number): string {
  return `Source stopped working. Finding a replacement (${attempt} of ${MAX_STREAM_RECOVERY_ATTEMPTS})…`;
}

export function useStreamRecovery(options: Options) {
  const latest = useRef(options);
  latest.current = options;
  const [attemptInProgress, setAttemptInProgress] = useState<number | null>(null);
  const runningRef = useRef(false);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const perform = useCallback(async (params: GenericStreamParams, early: boolean, attempt: number) => {
    const failedUrls = new Set([...(params.failedStreamUrls || []), params.uri]);
    const position = latest.current.positionRef.current;
    // Resume where playback stopped, or where this load was meant to start.
    const resumeMs = position > 1000 ? position : params.resumePositionMs;

    const fetched = await (async () => {
      await removeCachedSourceIfFailed(params.contentKey, params.uri).catch(() => undefined);
      const identity = identityForStreamParams(params);
      return params.recoverySourcesFetched || !identity ? null : fetchStreamsForRecovery(identity);
    })().catch(() => null);

    if (!mountedRef.current) {
      return;
    }

    const pool = fetched?.some((result) => result.streams.some((stream) => stream.playable))
      ? fetched
      : groupStreamsByAddon(latest.current.sourcesRef.current);
    const match = bestSourceMatch(latest.current.currentStream, pool, { excludingUrls: failedUrls });

    if (!match) {
      runningRef.current = false;
      setAttemptInProgress(null);
      appLogger.warn('[StreamRecovery] No working replacement found', {
        contentKey: params.contentKey,
        attempts: attempt,
      });
      latest.current.onExhausted(early);
      return;
    }

    appLogger.info('[StreamRecovery] Playing replacement source', {
      contentKey: params.contentKey,
      addonName: match.stream.addonName,
      match: match.tier,
    });

    const fresh = pool
      .flatMap((result) => result.streams)
      .filter((stream) => stream.playable && !failedUrls.has(stream.url || ''));
    latest.current.onReplace(
      streamRouteFor(match.stream, {
        ...params,
        availableStreams: fresh.length > 0 ? fresh : params.availableStreams,
        resumePositionMs: resumeMs,
        recoveryAttempts: attempt,
        failedStreamUrls: Array.from(failedUrls),
        recoverySourcesFetched: true,
      })
    );
  }, []);

  /** Starts an attempt. False when none is possible, and the caller shows the error. */
  const attemptRecovery = useCallback(
    (early: boolean): boolean => {
      const { params } = latest.current;
      if (!params) {
        return false;
      }
      // A second failure event for the same file while already recovering.
      if (runningRef.current) {
        return true;
      }
      const attempts = params.recoveryAttempts ?? 0;
      if (attempts >= MAX_STREAM_RECOVERY_ATTEMPTS || !identityForStreamParams(params)) {
        return false;
      }

      const attempt = attempts + 1;
      runningRef.current = true;
      setAttemptInProgress(attempt);
      appLogger.warn('[StreamRecovery] Source failed, looking for a replacement', {
        contentKey: params.contentKey,
        addonName: params.streamAddonName,
        attempt,
        early,
      });
      perform(params, early, attempt);
      return true;
    },
    [perform]
  );

  // A replacement keeps the message up until its file has loaded.
  const inherited =
    !options.fileLoaded && options.params?.recoveryAttempts ? options.params.recoveryAttempts : null;
  const shownAttempt = attemptInProgress ?? inherited;

  return {
    attemptRecovery,
    hadAttempts: (options.params?.recoveryAttempts ?? 0) > 0,
    statusMessage: shownAttempt !== null ? recoveryMessage(shownAttempt) : null,
  };
}
