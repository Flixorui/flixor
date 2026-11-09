/**
 * Next episode and in-player episode switching for addon series streams.
 * macOS reference: ViewModels/PlayerViewModel+StreamNextEpisode.swift
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { appLogger } from '../../../core/AppLogger';
import { getAppSettings } from '../../../core/SettingsData';
import type { StremioSourcesRouteParams } from '../../../hooks/useStremioSources';
import {
  identityForEpisode,
  loadStreamEpisodes,
  parseStreamSeriesRef,
  type StreamEpisodeInfo,
  type StreamSeriesRef,
} from '../../../stremio/StreamEpisodeNavigator';
import { buildStremioContentKey } from '../../../stremio/StremioContentResolver';
import { stremioResumeStore } from '../../../stremio/StremioResumeStore';
import { stremioService } from '../../../stremio/StremioService';
import { bestSourceMatch, firstAddonWithPlayable, isSameAddonTier, NEXT_EPISODE_MATCH_TIERS } from '../../../stremio/StremioSourceRanking';
import { StreamAutoSelector } from '../../../stremio/StreamAutoSelector';
import { mergeExternalSubtitles, streamRouteFor } from '../../../stremio/StreamRecovery';
import type {
  GenericStreamParams,
  StremioPlayableStream,
  StremioSubtitleCandidate,
} from '../../../stremio/types';

const NEXT_EPISODE_LOOKUP_LIMIT_MS = 15_000;
const NEXT_EPISODE_SUBTITLE_WAIT_MS = 2_000;

type Outcome =
  | { kind: 'playable'; route: GenericStreamParams }
  | { kind: 'needsPicker'; destination: StremioSourcesRouteParams }
  | { kind: 'unavailable'; message: string };

type Options = {
  params: GenericStreamParams | null;
  /** The stream playing now; next-episode sources are matched against it. */
  currentStream: StremioPlayableStream | null;
  subtitleAddonsEnabled: boolean;
  setPlaying: (playing: boolean) => void;
  onPlay: (route: GenericStreamParams) => void;
  onNeedsPicker: (destination: StremioSourcesRouteParams) => void;
  onUnavailable: (message: string) => void;
};

async function resolveEpisodeSource(
  params: GenericStreamParams,
  ref: StreamSeriesRef,
  reference: StremioPlayableStream | null,
  subtitleAddonsEnabled: boolean,
  season: number,
  episode: number,
  episodeTitle: string | undefined
): Promise<Outcome> {
  const identity = identityForEpisode(ref, season, episode);
  const destination: StremioSourcesRouteParams = {
    identity,
    title: params.title,
    backdrop: params.backdrop,
    mediaType: 'episode',
    imdbId: identity.imdbId,
    tmdbId: identity.tmdbId,
    seasonNumber: season,
    episodeNumber: episode,
    episodeTitle,
    disableAutoPlay: true,
  };

  // Stop as soon as the addon in use returns a match; a slow addon elsewhere
  // shouldn't hold up the next episode.
  // With "Follow addon order", the highest-priority addon with this episode wins, even
  // when the current episode came from a lower one.
  const followAddonOrder = getAppSettings().stremioPlayAction === 'addonOrder';
  const orderSelector = followAddonOrder
    ? new StreamAutoSelector(null, (await stremioService.getInstalledAddons()).map((addon) => addon.installationId))
    : null;
  const fetched = await stremioService.getStreamsWithin(identity, {
    timeLimitMs: NEXT_EPISODE_LOOKUP_LIMIT_MS,
    shouldStop: (results, pending) =>
      orderSelector
        ? orderSelector.shouldStopWaiting(results, pending)
        : isSameAddonTier(bestSourceMatch(reference, results, { tiers: NEXT_EPISODE_MATCH_TIERS })?.tier),
  });
  if (fetched.timedOut) {
    appLogger.warn('[StreamNext] Source lookup hit its time limit', {
      requestId: identity.requestId,
      addonsAnswered: fetched.results.length,
    });
  }

  const match = bestSourceMatch(
    reference,
    followAddonOrder ? firstAddonWithPlayable(fetched.results) : fetched.results,
    { tiers: NEXT_EPISODE_MATCH_TIERS, followAddonOrder: false }
  );
  if (!match) {
    return { kind: 'needsPicker', destination };
  }

  const contentKey = buildStremioContentKey(identity);
  // The new player asks subtitle addons again once playback starts, so a slow
  // subtitle addon must not delay switching episodes.
  const [addonSubtitles, resume] = await Promise.all([
    subtitleAddonsEnabled
      ? stremioService.getSubtitles(identity, { deadlineMs: NEXT_EPISODE_SUBTITLE_WAIT_MS })
      : Promise.resolve([] as StremioSubtitleCandidate[]),
    stremioResumeStore.get(contentKey),
  ]);

  appLogger.info('[StreamNext] Picked next-episode source', {
    requestId: identity.requestId,
    match: match.tier,
    addonName: match.stream.addonName,
  });

  return {
    kind: 'playable',
    route: streamRouteFor(match.stream, {
      ...params,
      contentKey,
      seasonNumber: season,
      episodeNumber: episode,
      episodeTitle,
      availableStreams: fetched.results.flatMap((result) => result.streams),
      externalSubtitles: mergeExternalSubtitles(match.stream, addonSubtitles),
      subtitlesIncomplete: subtitleAddonsEnabled,
      resumePositionMs: resume?.positionMs,
      stremioIdentity: identity,
      recoveryAttempts: undefined,
      failedStreamUrls: undefined,
      recoverySourcesFetched: undefined,
    }),
  };
}

export function useStreamEpisodes(options: Options) {
  const { params } = options;
  const latest = useRef(options);
  latest.current = options;

  const ref = useMemo(() => (params ? parseStreamSeriesRef(params) : null), [params]);
  const [seasonEpisodes, setSeasonEpisodes] = useState<StreamEpisodeInfo[]>([]);
  const [next, setNext] = useState<StreamEpisodeInfo | null>(null);
  const [resolvingLabel, setResolvingLabel] = useState<string | null>(null);

  const mountedRef = useRef(true);
  const resolvingRef = useRef(false);
  const waitTokenRef = useRef(0);
  const lookupRef = useRef<{ key: string; promise: Promise<Outcome> } | null>(null);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      waitTokenRef.current += 1;
    };
  }, []);

  useEffect(() => {
    if (!ref) {
      return;
    }
    let cancelled = false;
    loadStreamEpisodes(ref)
      .then((result) => {
        if (cancelled) return;
        setSeasonEpisodes(result.seasonEpisodes);
        setNext(result.next);
      })
      .catch((error) => {
        appLogger.warn('[StreamNext] Episode lookup failed', { error: error?.message || String(error) });
      });
    return () => {
      cancelled = true;
    };
  }, [ref]);

  /** One shared lookup per episode, so prefetch and play-next reuse it. */
  const episodeLookup = useCallback(
    (season: number, episode: number, title: string | undefined): Promise<Outcome> | null => {
      const { params: currentParams, currentStream, subtitleAddonsEnabled } = latest.current;
      if (!currentParams || !ref) {
        return null;
      }
      const key = `${season}:${episode}`;
      if (lookupRef.current?.key === key) {
        return lookupRef.current.promise;
      }
      const promise = resolveEpisodeSource(
        currentParams,
        ref,
        currentStream,
        subtitleAddonsEnabled,
        season,
        episode,
        title
      ).catch(
        (error): Outcome => ({
          kind: 'unavailable',
          message: error?.message || 'Could not find a source for this episode.',
        })
      );
      lookupRef.current = { key, promise };
      return promise;
    },
    [ref]
  );

  /** Starts resolving the next episode's source ahead of time, so play-next is instant. */
  const prefetchNext = useCallback(() => {
    if (next) {
      episodeLookup(next.season, next.episode, next.title);
    }
  }, [episodeLookup, next]);

  const playEpisode = useCallback(
    async (season: number, episode: number, title: string | undefined) => {
      if (resolvingRef.current) {
        return;
      }
      const lookup = episodeLookup(season, episode, title);
      if (!lookup) {
        return;
      }

      resolvingRef.current = true;
      const token = ++waitTokenRef.current;
      setResolvingLabel(`S${season}E${episode}`);
      // Every outcome leaves this episode, so pause while the lookup runs.
      latest.current.setPlaying(false);

      const outcome = await lookup;
      if (token !== waitTokenRef.current || !mountedRef.current) {
        return;
      }
      resolvingRef.current = false;
      setResolvingLabel(null);

      if (outcome.kind === 'playable') {
        latest.current.onPlay(outcome.route);
      } else if (outcome.kind === 'needsPicker') {
        latest.current.onNeedsPicker(outcome.destination);
      } else {
        latest.current.onUnavailable(outcome.message);
      }
    },
    [episodeLookup]
  );

  /** Gives up waiting and carries on watching. The lookup keeps running, so Next can reuse it. */
  const cancelLookup = useCallback(() => {
    if (!resolvingRef.current) {
      return;
    }
    waitTokenRef.current += 1;
    resolvingRef.current = false;
    setResolvingLabel(null);
    latest.current.setPlaying(true);
  }, []);

  return {
    seriesRef: ref,
    seasonEpisodes,
    next,
    resolvingLabel,
    isResolving: resolvingLabel !== null,
    prefetchNext,
    playEpisode,
    cancelLookup,
  };
}
