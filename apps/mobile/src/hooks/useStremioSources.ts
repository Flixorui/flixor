import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert } from 'react-native';
import { StackActions, useNavigation } from '@react-navigation/native';
import { useAppSettings } from './useAppSettings';
import { stremioResumeStore } from '../stremio/StremioResumeStore';
import { stremioService } from '../stremio/StremioService';
import { stremioStreamCache } from '../stremio/StremioStreamCache';
import { appLogger } from '../core/AppLogger';
import type {
  CachedPlaybackSource,
  GenericStreamParams,
  ResumeState,
  StremioAddonStreamResult,
  StremioContentIdentity,
  StremioPlayableStream,
  StremioPlaybackMediaType,
  StremioSubtitleCandidate,
} from '../stremio/types';
import { buildStremioContentKey } from '../stremio/StremioContentResolver';
import { StreamAutoSelector, StreamRuleError } from '../stremio/StreamAutoSelector';
import { mergeExternalSubtitles, mergedStreamHeaders } from '../stremio/StreamRecovery';

export type StremioSourcesRouteParams = {
  identity: StremioContentIdentity;
  title: string;
  backdrop?: string;
  poster?: string;
  mediaType: StremioPlaybackMediaType;
  imdbId?: string;
  tmdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
  episodeTitle?: string;
  /** Open the list even when Play is set to start a source automatically. */
  disableAutoPlay?: boolean;
};

function formatResumeLabel(resumeState: ResumeState | null): string | undefined {
  if (!resumeState || resumeState.positionMs <= 0) {
    return undefined;
  }
  const totalSeconds = Math.floor(resumeState.positionMs / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0) {
    return `${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

type OpenPlayerContext = {
  availableStreams: StremioPlayableStream[];
  addonSubtitles: StremioSubtitleCandidate[];
  resumePositionMs?: number;
  cached?: CachedPlaybackSource;
  /** Replace this screen, so backing out of the player doesn't land on a list nobody asked for. */
  replace?: boolean;
  subtitlesIncomplete?: boolean;
};

function streamFromCache(cached: CachedPlaybackSource): StremioPlayableStream {
  return {
    url: cached.uri,
    name: cached.streamLabel,
    addonId: cached.addonId,
    addonName: cached.addonName,
    streamIndex: 0,
    sourceType: 'url',
    playable: true,
    subtitles: cached.externalSubtitles,
  };
}

function fallbackNotice(results: StremioAddonStreamResult[], waitedSeconds: number | null): string | null {
  if (results.some((result) => result.streams.some((stream) => stream.playable))) {
    return waitedSeconds !== null
      ? `No source matched your rules within ${waitedSeconds} seconds. Showing all sources.`
      : 'No source matched your rules. Showing all sources.';
  }
  return waitedSeconds !== null
    ? `No playable source arrived within ${waitedSeconds} seconds. Showing all sources.`
    : null;
}

export function useStremioSources(routeParams?: StremioSourcesRouteParams) {
  const nav: any = useNavigation();
  const { settings } = useAppSettings();
  const [loading, setLoading] = useState(true);
  const [results, setResults] = useState<StremioAddonStreamResult[]>([]);
  const [selectedProvider, setSelectedProvider] = useState('all');
  const [cachedSource, setCachedSource] = useState<CachedPlaybackSource | null>(null);
  const [resumeState, setResumeState] = useState<ResumeState | null>(null);
  const [externalSubtitles, setExternalSubtitles] = useState<StremioSubtitleCandidate[]>([]);
  const [hasStreamProviders, setHasStreamProviders] = useState(true);
  const [autoSelecting, setAutoSelecting] = useState(false);
  const [autoSelectNotice, setAutoSelectNotice] = useState<string | null>(null);

  const autoAttemptedRef = useRef(false);
  const autoTokenRef = useRef(0);
  const autoAbortRef = useRef<AbortController | null>(null);
  const settingsRef = useRef(settings);
  settingsRef.current = settings;

  const contentKey = useMemo(
    () => (routeParams ? buildStremioContentKey(routeParams.identity) : ''),
    [routeParams]
  );

  const load = useCallback(async () => {
    setLoading(true);
    try {
      if (!routeParams) {
        setResults([]);
        setCachedSource(null);
        setResumeState(null);
        setExternalSubtitles([]);
        setHasStreamProviders(false);
        return;
      }
      await stremioService.ensureInitialized({
        installDefaults: settings.stremioPlaybackEnabled,
      });
      const [streamProvidersAvailable, streamResults, cached, resume, subtitles] = await Promise.all([
        stremioService.hasStreamProviders(routeParams.identity.requestType),
        stremioService.getStreams(routeParams.identity),
        stremioStreamCache.get(contentKey),
        stremioResumeStore.get(contentKey),
        settings.stremioSubtitleAddonsEnabled
          ? stremioService.getSubtitles(routeParams.identity)
          : Promise.resolve([] as StremioSubtitleCandidate[]),
      ]);
      setHasStreamProviders(streamProvidersAvailable);
      setResults(streamResults);
      setCachedSource(cached);
      setResumeState(resume);
      setExternalSubtitles(subtitles);
      appLogger.info('[Stremio] Sources loaded', {
        contentKey,
        addonCount: streamResults.length,
        playableStreamCount: streamResults.reduce(
          (total, result) => total + result.streams.filter((stream) => stream.playable).length,
          0
        ),
        subtitleCount: subtitles.length,
      });
    } catch (error: any) {
      appLogger.warn('[Stremio] Failed to load sources', {
        contentKey,
        error: error?.message || String(error),
      });
      setResults([]);
      setCachedSource(null);
      setResumeState(null);
      setExternalSubtitles([]);
      setHasStreamProviders(false);
    } finally {
      setLoading(false);
    }
  }, [
    contentKey,
    routeParams,
    settings.stremioPlaybackEnabled,
    settings.stremioSubtitleAddonsEnabled,
  ]);

  const openPlayer = useCallback(
    async (stream: StremioPlayableStream, context: OpenPlayerContext) => {
      if (!routeParams) {
        return;
      }
      const { cached } = context;
      const uri = cached?.uri || stream.url;
      if (!uri) {
        Alert.alert('Unavailable', stream.disabledReason || 'This source cannot be played in-app.');
        return;
      }

      const mergedHeaders = { ...(mergedStreamHeaders(stream) || {}), ...(cached?.headers || {}) };
      const subtitles = mergeExternalSubtitles(stream, context.addonSubtitles);

      const route: GenericStreamParams = {
        type: 'stream',
        provider: 'stremio',
        uri,
        headers: Object.keys(mergedHeaders).length > 0 ? mergedHeaders : undefined,
        title: routeParams.title,
        mediaType: routeParams.mediaType,
        contentKey,
        imdbId: routeParams.imdbId || routeParams.identity.imdbId,
        tmdbId: routeParams.tmdbId || routeParams.identity.tmdbId,
        seasonNumber: routeParams.seasonNumber || routeParams.identity.seasonNumber,
        episodeNumber: routeParams.episodeNumber || routeParams.identity.episodeNumber,
        episodeTitle: routeParams.episodeTitle,
        backdrop: routeParams.backdrop,
        streamLabel: cached?.streamLabel || stream.name || stream.title,
        streamAddonId: cached?.addonId || stream.addonId,
        streamAddonName: cached?.addonName || stream.addonName,
        availableStreams: context.availableStreams,
        externalSubtitles: subtitles,
        subtitlesIncomplete: context.subtitlesIncomplete,
        resumePositionMs: context.resumePositionMs,
        stremioIdentity: routeParams.identity,
      };

      const cacheEntry: CachedPlaybackSource = {
        kind: 'stream',
        provider: 'stremio',
        contentKey,
        uri,
        headers: route.headers,
        title: route.title,
        mediaType: route.mediaType,
        imdbId: route.imdbId,
        tmdbId: route.tmdbId,
        seasonNumber: route.seasonNumber,
        episodeNumber: route.episodeNumber,
        episodeTitle: route.episodeTitle,
        backdrop: route.backdrop,
        streamLabel: route.streamLabel,
        addonId: route.streamAddonId,
        addonName: route.streamAddonName,
        externalSubtitles: subtitles,
        availableStreams: context.availableStreams,
        stremioIdentity: routeParams.identity,
        savedAt: Date.now(),
        expiresAt: Date.now() + settingsRef.current.streamCacheTTL,
      };

      await stremioStreamCache.save(cacheEntry);
      appLogger.info('[Stremio] Source selected', {
        contentKey,
        addonId: route.streamAddonId,
        addonName: route.streamAddonName,
        streamLabel: route.streamLabel,
        resumedFromCache: Boolean(cached),
      });
      if (context.replace) {
        nav.dispatch(StackActions.replace('Player', route as any));
      } else {
        nav.navigate('Player', route);
      }
    },
    [contentKey, nav, routeParams]
  );

  /**
   * Waits on addons up to the time limit and starts a source. True when playback
   * started; otherwise the list loads as usual, with a notice saying why.
   * macOS reference: StremioSourcesViewModel.findAutomaticSource
   */
  const runAutomaticSelection = useCallback(
    async (action: 'playBest' | 'matchRules' | 'addonOrder'): Promise<boolean> => {
      if (!routeParams) {
        return false;
      }
      const current = settingsRef.current;
      const token = ++autoTokenRef.current;
      const controller = new AbortController();
      autoAbortRef.current = controller;
      const stillWanted = () => token === autoTokenRef.current;
      setAutoSelecting(true);

      try {
        await stremioService.ensureInitialized({ installDefaults: current.stremioPlaybackEnabled });
        if (!(await stremioService.hasStreamProviders(routeParams.identity.requestType))) {
          return false;
        }

        if (current.stremioPreferCachedSourceResume) {
          const [cached, resume] = await Promise.all([
            stremioStreamCache.get(contentKey),
            stremioResumeStore.get(contentKey),
          ]);
          if (!stillWanted()) return true;
          if (cached && resume && resume.positionMs > 0) {
            await openPlayer(streamFromCache(cached), {
              cached,
              availableStreams: cached.availableStreams ?? [],
              addonSubtitles: cached.externalSubtitles ?? [],
              resumePositionMs: resume.positionMs,
              replace: true,
            });
            return true;
          }
        }

        let selector: StreamAutoSelector;
        try {
          const addonOrder =
            action === 'addonOrder'
              ? (await stremioService.getInstalledAddons()).map((addon) => addon.installationId)
              : undefined;
          selector = new StreamAutoSelector(action === 'matchRules' ? current.stremioStreamRules : null, addonOrder);
        } catch (error) {
          if (!(error instanceof StreamRuleError)) throw error;
          setAutoSelectNotice('Your source rules have an invalid pattern. Fix it in Settings, or choose a source here.');
          return false;
        }

        const timeLimitSeconds = current.stremioAutoPickTimeLimit;
        const deadline = Date.now() + timeLimitSeconds * 1000;
        const fetched = await stremioService.getStreamsWithin(routeParams.identity, {
          timeLimitMs: timeLimitSeconds * 1000,
          shouldStop: (partial, pending) => selector.shouldStopWaiting(partial, pending),
          signal: controller.signal,
        });
        if (!stillWanted()) return true;

        const picked = selector.pick(fetched.results);
        if (selector.rulesTimedOut) {
          setAutoSelectNotice('Your include pattern took too long to check. Simplify it in Settings, or choose a source here.');
          return false;
        }
        if (!picked) {
          setAutoSelectNotice(fallbackNotice(fetched.results, fetched.timedOut ? timeLimitSeconds : null));
          return false;
        }

        const [addonSubtitles, resume] = await Promise.all([
          current.stremioSubtitleAddonsEnabled
            ? stremioService.getSubtitles(routeParams.identity, {
                deadlineMs: Math.max(500, deadline - Date.now()),
              })
            : Promise.resolve([] as StremioSubtitleCandidate[]),
          stremioResumeStore.get(contentKey),
        ]);
        if (!stillWanted()) return true;

        appLogger.info('[Stremio] Auto-selected source', {
          contentKey,
          action,
          addonName: picked.addonName,
          timedOut: fetched.timedOut,
        });
        await openPlayer(picked, {
          availableStreams: fetched.results.flatMap((result) => result.streams),
          addonSubtitles,
          resumePositionMs: resume?.positionMs,
          replace: true,
          subtitlesIncomplete: current.stremioSubtitleAddonsEnabled,
        });
        return true;
      } catch (error: any) {
        appLogger.warn('[Stremio] Automatic source selection failed', {
          contentKey,
          error: error?.message || String(error),
        });
        if (stillWanted()) {
          setAutoSelectNotice('The chosen source could not be started. Choose another one here.');
        }
        return false;
      } finally {
        if (stillWanted()) {
          setAutoSelecting(false);
        }
      }
    },
    [contentKey, openPlayer, routeParams]
  );

  useEffect(() => {
    const action = routeParams?.disableAutoPlay ? 'showSources' : settingsRef.current.stremioPlayAction;
    if (action === 'showSources' || autoAttemptedRef.current) {
      load();
      return;
    }

    // Once per screen, so coming back from the player can't start another source.
    autoAttemptedRef.current = true;
    runAutomaticSelection(action).then((started) => {
      if (!started) {
        load();
      }
    });
  }, [load, routeParams?.disableAutoPlay, runAutomaticSelection]);

  /** Stops looking and shows the list. */
  const chooseSourceInstead = useCallback(() => {
    autoTokenRef.current += 1;
    autoAbortRef.current?.abort();
    setAutoSelecting(false);
    load();
  }, [load]);

  const visibleResults = useMemo(() => {
    return results
      .map((result) => ({
        ...result,
        streams: result.streams.filter((stream) => {
          if (selectedProvider !== 'all' && result.installationId !== selectedProvider) {
            return false;
          }
          if (stream.playable) {
            return true;
          }
          return settings.stremioUnsupportedSourceVisibility === 'show_disabled';
        }),
      }))
      .filter((result) => result.streams.length > 0 || result.error);
  }, [results, selectedProvider, settings.stremioUnsupportedSourceVisibility]);

  const providers = useMemo(() => {
    const entries = [
      { id: 'all', label: 'All Sources' },
      ...results.map((result) => ({
        id: result.installationId,
        label: result.addonName,
      })),
    ];
    const deduped = new Map(entries.map((entry) => [entry.id, entry]));
    return Array.from(deduped.values());
  }, [results]);

  const playableCount = useMemo(
    () => results.reduce((total, result) => total + result.streams.filter((stream) => stream.playable).length, 0),
    [results]
  );

  const navigateToPlayer = useCallback(
    (stream: StremioPlayableStream, cached?: CachedPlaybackSource) =>
      openPlayer(stream, {
        cached,
        availableStreams: results.flatMap((result) => result.streams),
        addonSubtitles: externalSubtitles,
        resumePositionMs: resumeState?.positionMs,
      }),
    [externalSubtitles, openPlayer, results, resumeState?.positionMs]
  );

  return {
    loading,
    autoSelecting,
    autoSelectNotice,
    chooseSourceInstead,
    visibleResults,
    providers,
    selectedProvider,
    setSelectedProvider,
    cachedSource,
    resumePositionLabel: formatResumeLabel(resumeState),
    navigateToPlayer,
    openCachedSource: () =>
      cachedSource ? navigateToPlayer(streamFromCache(cachedSource), cachedSource) : Promise.resolve(),
    state: {
      hasAddons: hasStreamProviders,
      hasPlayableStreams: playableCount > 0,
      hasAnyResults: results.some((result) => result.streams.length > 0),
      hasUnsupportedOnly:
        playableCount === 0 && results.some((result) => result.streams.some((stream) => !stream.playable)),
    },
  };
}
