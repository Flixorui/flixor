import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert } from 'react-native';
import { useNavigation } from '@react-navigation/native';
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
};

function getQualityScore(stream: StremioPlayableStream): number {
  const label = `${stream.name || ''} ${stream.title || ''}`.trim();
  const match = label.match(/(\d{3,4})p/i);
  return match ? Number(match[1]) : 0;
}

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

  useEffect(() => {
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

  const playableStreams = useMemo(
    () =>
      results.flatMap((result) =>
        result.streams.filter((stream) => stream.playable).map((stream) => ({
          stream,
          result,
        }))
      ),
    [results]
  );

  const bestAutoplayStream = useMemo(() => {
    if (playableStreams.length === 0) {
      return null;
    }
    return [...playableStreams].sort((left, right) => {
      const leftQuality = getQualityScore(left.stream);
      const rightQuality = getQualityScore(right.stream);
      if (leftQuality !== rightQuality) {
        return rightQuality - leftQuality;
      }
      return left.stream.streamIndex - right.stream.streamIndex;
    })[0];
  }, [playableStreams]);

  const navigateToPlayer = useCallback(
    async (stream: StremioPlayableStream, cached?: CachedPlaybackSource) => {
      if (!routeParams) {
        return;
      }
      const uri = cached?.uri || stream.url;
      if (!uri) {
        Alert.alert('Unavailable', stream.disabledReason || 'This source cannot be played in-app.');
        return;
      }

      const mergedHeaders = {
        ...(stream.headers || {}),
        ...(stream.behaviorHints?.proxyHeaders?.request || {}),
        ...(cached?.headers || {}),
      };
      const resumePositionMs = resumeState?.positionMs;
      const availableStreams = results.flatMap((result) => result.streams);

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
        availableStreams,
        externalSubtitles,
        resumePositionMs,
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
        externalSubtitles,
        availableStreams,
        stremioIdentity: routeParams.identity,
        savedAt: Date.now(),
        expiresAt: Date.now() + settings.streamCacheTTL,
      };

      await stremioStreamCache.save(cacheEntry);
      appLogger.info('[Stremio] Source selected', {
        contentKey,
        addonId: route.streamAddonId,
        addonName: route.streamAddonName,
        streamLabel: route.streamLabel,
        resumedFromCache: Boolean(cached),
      });
      nav.navigate('Player', route);
    },
    [
      contentKey,
      externalSubtitles,
      nav,
      results,
      resumeState?.positionMs,
      routeParams,
      settings.streamCacheTTL,
    ]
  );

  useEffect(() => {
    if (!settings.stremioAutoPlayBestSource || loading || !bestAutoplayStream) {
      return;
    }

    navigateToPlayer(bestAutoplayStream.stream).catch(() => {
      // Let the manual UI remain available if autoplay fails.
    });
  }, [bestAutoplayStream, loading, navigateToPlayer, settings.stremioAutoPlayBestSource]);

  return {
    loading,
    visibleResults,
    providers,
    selectedProvider,
    setSelectedProvider,
    cachedSource,
    resumePositionLabel: formatResumeLabel(resumeState),
    navigateToPlayer,
    openCachedSource: () =>
      cachedSource
        ? navigateToPlayer(
            {
              url: cachedSource.uri,
              name: cachedSource.streamLabel,
              addonId: cachedSource.addonId,
              addonName: cachedSource.addonName,
              streamIndex: 0,
              sourceType: 'url',
              playable: true,
              subtitles: cachedSource.externalSubtitles,
            },
            cachedSource
          )
        : Promise.resolve(),
    state: {
      hasAddons: hasStreamProviders,
      hasPlayableStreams: playableStreams.length > 0,
      hasAnyResults: results.some((result) => result.streams.length > 0),
      hasUnsupportedOnly:
        playableStreams.length === 0 && results.some((result) => result.streams.some((stream) => !stream.playable)),
    },
  };
}
