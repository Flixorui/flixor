import React, { useEffect, useMemo, useState, useRef, useCallback } from 'react';
import { View, Text, TouchableOpacity, ActivityIndicator, StyleSheet, StatusBar, Dimensions, Platform, NativeModules, Image, Pressable } from 'react-native';
import { setAudioModeAsync } from 'expo-audio';
import FastImage from '@d11/react-native-fast-image';
import Slider from '@react-native-community/slider';
import { useNavigation, StackActions } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import * as ScreenOrientation from 'expo-screen-orientation';
import { useKeepAwake } from 'expo-keep-awake';
import { LinearGradient } from 'expo-linear-gradient';
import { MPVPlayerComponent, MPVPlayerRef, MPVAudioTrack, MPVSubtitleTrack, PerformanceStats } from '../components/player';

// Track types (unified for both iOS and Android MPV)
type AudioTrack = {
  id: number;
  index: number;
  name: string;
  language: string;
  languageCode: string;
  isEnabled: boolean;
  bitRate: number;
  bitDepth: number;
};

type TextTrack = {
  id: number;
  index: number;
  name: string;
  language: string;
  languageCode: string;
  isEnabled: boolean;
  isImageSubtitle?: boolean;
};
import { Stream, PlaybackInfo } from '../components/PlayerSettingsSheet';
import { useFlixor } from '../core/FlixorContext';
import { appLogger } from '../core/AppLogger';
import {
  fetchPlayerMetadata,
  fetchMarkers,
  fetchNextEpisode,
  getTranscodeStreamUrl,
  getDirectStreamUrl,
  updatePlaybackTimeline,
  stopTranscodeSession,
  setStreamSelection,
  getPlayerImageUrl,
  startTraktScrobble,
  pauseTraktScrobble,
  stopTraktScrobble,
  isTraktAuthenticated,
  NextEpisodeInfo,
  startGenericTraktScrobble,
  pauseGenericTraktScrobble,
  stopGenericTraktScrobble,
} from '../core/PlayerData';
import { ReplayIcon, ForwardIcon } from '../components/icons/SkipIcons';
import { TopBarStore } from '../components/TopBarStore';
import PlayerSettingsSheet from '../components/PlayerSettingsSheet';
import { useAppSettings } from '../hooks/useAppSettings';
import {
  getOfflineMetadata,
  getOfflineMedia,
  getOfflineMarkers,
  formatMarkersForPlayer,
} from '../services/downloads';
import type {
  GenericStreamParams,
  StremioPlayableStream,
  StremioSubtitleCandidate,
} from '../stremio/types';
import { stremioResumeStore } from '../stremio/StremioResumeStore';
import { useCustomSubtitles } from '../components/player/hooks/useCustomSubtitles';
import CustomSubtitles from '../components/player/subtitles/CustomSubtitles';
import {
  findBestAudioTrack,
  findBestSubtitleTrack,
  normalizeLanguageCode,
} from '../components/player/utils/trackSelectionUtils';
import {
  loadRememberedTracks,
  saveTrackChoice,
  SUBTITLES_OFF,
  type RememberedTracks,
  type TrackMemoryIds,
} from '../components/player/utils/trackMemory';
import { resolveOriginalLanguage } from '../components/player/utils/originalLanguage';
import { useCommunitySkipMarkers, type PlayerMarker } from '../components/player/hooks/useCommunitySkipMarkers';
import { useStreamEpisodes } from '../components/player/hooks/useStreamEpisodes';
import { useStreamRecovery } from '../components/player/hooks/useStreamRecovery';
import { useStreamSourceList } from '../components/player/hooks/useStreamSourceList';
import EpisodesPanel, { type BrowserEpisode, type EpisodeBrowserSource } from '../components/player/panels/EpisodesPanel';
import SourcesPanel from '../components/player/panels/SourcesPanel';
import SpeedPanel, { formatSpeed } from '../components/player/panels/SpeedPanel';
import SubtitlePanel from '../components/player/panels/SubtitlePanel';
import SeekBarMarks from '../components/player/SeekBarMarks';
import StreamStatusPill from '../components/player/StreamStatusPill';
import { useTheme } from '../hooks/useTheme';
import type { StremioSourcesRouteParams } from '../hooks/useStremioSources';
import { localLibrary } from '../core/LocalLibrary';
import { stremioService } from '../stremio/StremioService';
import { identityForStreamParams, streamRouteFor } from '../stremio/StreamRecovery';

/** The status fields the unused expo-av fallback handler reads (expo-av was removed in the SDK 57 upgrade). */
type LegacyPlaybackStatus =
  | { isLoaded: false; error?: string }
  | { isLoaded: true; isPlaying: boolean; isBuffering: boolean; positionMillis: number; durationMillis?: number; didJustFinish: boolean };

type LegacyPlayerParams = {
  type: 'plex' | 'tmdb' | 'offline';
  ratingKey?: string;
  id?: string;
  // For transcode track switching - player restarts with these
  initialAudioStreamId?: string;
  initialSubtitleStreamId?: string;
  initialQuality?: number | 'original';
  resumePosition?: number; // Resume position in ms
  mediaIndex?: number; // Index of Media array to play (for multi-version support)
  // For offline playback
  offlineFilePath?: string;
  offlineGlobalKey?: string;
};

type PlayerParams = LegacyPlayerParams | GenericStreamParams;

type RouteParams = {
  route?: {
    params?: PlayerParams;
  };
};

export default function Player({ route }: RouteParams) {
  const params = (route?.params || {}) as Partial<PlayerParams> & Record<string, any>;
  const nav = useNavigation();
  const mpvPlayerRef = useRef<MPVPlayerRef>(null); // Unified MPV player (iOS + Android)
  const { isLoading: flixorLoading, isConnected } = useFlixor();
  const { settings } = useAppSettings();
  const theme = useTheme();
  const MPVPlayerModule = NativeModules.MPVPlayerModule; // Native module for async methods

  // Keep screen awake during video playback
  useKeepAwake();

  // Multi-version support: which Media to use
  const selectedMediaIndex = params.mediaIndex ?? 0;
  const isStreamPlayback = params.type === 'stream';
  const streamParams = isStreamPlayback ? (params as GenericStreamParams) : null;
  const streamContentKey = streamParams?.contentKey;
  // Addon streams need no Plex server, so they also run in Stremio-only mode.
  const playerReady = !flixorLoading && (isStreamPlayback || isConnected);

  // Track selection state (MPV player - iOS + Android)
  const [audioTracks, setAudioTracks] = useState<AudioTrack[]>([]);
  const [textTracks, setTextTracks] = useState<TextTrack[]>([]);
  const audioTracksRef = useRef<AudioTrack[]>([]);
  const textTracksRef = useRef<TextTrack[]>([]);
  const [selectedAudioTrack, setSelectedAudioTrack] = useState<number | null>(null);
  const [selectedTextTrack, setSelectedTextTrack] = useState<number>(-1); // -1 = none

  // Plex stream info (from metadata, with proper names)
  const [plexAudioStreams, setPlexAudioStreams] = useState<Stream[]>([]);
  const [plexSubtitleStreams, setPlexSubtitleStreams] = useState<Stream[]>([]);
  const [selectedPlexAudio, setSelectedPlexAudio] = useState<string | null>(null);
  const [selectedPlexSubtitle, setSelectedPlexSubtitle] = useState<string>('0'); // '0' = none

  // Settings sheet state
  const [showSettingsSheet, setShowSettingsSheet] = useState(false);
  // Performance stats for Info tab in settings sheet
  const [performanceStats, setPerformanceStats] = useState<PerformanceStats>({});
  // Rotation lock state (default: locked to landscape only, matching Plezy)
  const [isRotationLocked, setIsRotationLocked] = useState(true);
  const isRotationLockedRef = useRef(true);

  const [loading, setLoading] = useState(true);
  const [streamUrl, setStreamUrl] = useState<string>('');
  const [streamHeaders, setStreamHeaders] = useState<Record<string, string> | undefined>(undefined);
  const [metadata, setMetadata] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  // Playback state
  const [isPlaying, setIsPlaying] = useState(true);
  const [duration, setDuration] = useState(0);
  const [position, setPosition] = useState(0);
  const [buffering, setBuffering] = useState(false);
  const [showControls, setShowControls] = useState(true);

  // Markers for skip intro/credits
  const [plexMarkers, setMarkers] = useState<PlayerMarker[]>([]);
  const [plexMarkersReady, setPlexMarkersReady] = useState(false);
  const markers = useCommunitySkipMarkers({
    enabled: settings.communitySkipSegmentsEnabled,
    animeSkipClientId: settings.animeSkipClientId,
    streamParams,
    plexMetadata: params.type === 'plex' ? metadata : null,
    plexMarkers,
    plexMarkersReady,
    durationMs: duration,
  });

  // Auto-skip state
  const [autoSkipCountdown, setAutoSkipCountdown] = useState<number | null>(null);
  const autoSkipTriggeredMarkersRef = useRef<Set<string>>(new Set());
  const autoSkipTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Next episode for auto-play
  const [nextEpisode, setNextEpisode] = useState<NextEpisodeInfo | null>(null);
  const [nextEpisodeCountdown, setNextEpisodeCountdown] = useState<number | null>(null);
  // Refs for countdown/end handling to prevent infinite loops
  const nextEpisodeCountdownStartedRef = useRef(false);
  const nextEpisodeCountdownTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const nextEpisodeDismissedRef = useRef(false);
  const navigatedToEpisodeRef = useRef(false);
  const movieEndTriggeredRef = useRef(false);

  // In-player panels: one open at a time, and never alongside the settings sheet
  const [activePanel, setActivePanel] = useState<'sources' | 'episodes' | 'speed' | 'subtitles' | null>(null);

  // Playback speed. Applied after load: native drops props set before mpv starts.
  const [playbackRate, setPlaybackRate] = useState(1);
  const [isSpeedBoosted, setIsSpeedBoosted] = useState(false);

  const [fileLoaded, setFileLoaded] = useState(false);
  const fileLoadedRef = useRef(false);
  const lastSeekRef = useRef({ targetMs: 0, at: 0 });
  const [streamFailed, setStreamFailed] = useState(false);
  const [streamExternalSubtitles, setStreamExternalSubtitles] = useState<StremioSubtitleCandidate[]>(
    streamParams?.externalSubtitles ?? []
  );

  // Session ID for transcode management
  const [sessionId, setSessionId] = useState<string>('');

  // Part ID for stream selection
  const [partId, setPartId] = useState<string>('');

  // Direct play mode - allows in-player track switching
  const [isDirectPlay, setIsDirectPlay] = useState(false);

  // Player backend (MPV for both iOS and Android)
  const [playerBackend, setPlayerBackend] = useState<string>('');

  // HDR info from native player or Plex metadata
  const [hdrType, setHdrType] = useState<string | null>(null);
  const [colorSpace, setColorSpace] = useState<string | undefined>(undefined);

  // Quality selection state
  const [selectedQuality, setSelectedQuality] = useState<number | 'original'>('original');
  const [qualityOptions, setQualityOptions] = useState<Array<{ label: string; value: number | 'original' }>>([]);

  // Video resize mode for pinch-to-zoom (contain = letterbox, cover = fill screen)

  // Track screen dimensions for rotation
  const [dimensions, setDimensions] = useState({
    width: Dimensions.get('window').width,
    height: Dimensions.get('window').height,
  });

  const progressInterval = useRef<ReturnType<typeof setInterval> | null>(null);
  const controlsTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Store cleanup info in refs
  const cleanupInfoRef = useRef({ sessionId: '', ratingKey: '' });
  const isReplacingRef = useRef(false);

  // Trakt scrobbling state
  const traktScrobbleStarted = useRef(false);
  const lastScrobbleState = useRef<'playing' | 'paused' | 'stopped'>('stopped');

  // Refs for cleanup access to current state
  const metadataRef = useRef<any>(null);
  const positionRef = useRef(0);
  const durationRef = useRef(0);
  const streamResumeSaveAtRef = useRef(0);
  const streamAutoSelectionAppliedRef = useRef<string | null>(null);

  // Track selection refs (to prevent duplicate calls and infinite loops)
  const lastAudioTrackRef = useRef<number | null>(null);
  const lastTextTrackRef = useRef<number>(-1);

  // Scrubbing state
  const [isScrubbing, setIsScrubbing] = useState(false);
  // Legacy pan scrub state removed (using Slider now)

  // Developer stats HUD (long press on play button to toggle)

  // Aspect ratio mode: 0=contain, 1=cover, 2=fill
  const [aspectRatioMode, setAspectRatioMode] = useState(0);
  const {
    currentText: currentExternalSubtitleText,
    selectedExternalSubtitleId,
    isLoading: isLoadingExternalSubtitle,
    error: externalSubtitleError,
    setCurrentTimeMs: setExternalSubtitleTimeMs,
    loadSubtitle: loadExternalSubtitle,
    clear: clearExternalSubtitle,
    cues: externalSubtitleCues,
    currentTimeMs: externalSubtitleTimeMs,
    delayMs: externalSubtitleDelayMs,
    setDelayMs: setExternalSubtitleDelayMs,
  } = useCustomSubtitles({ filterHearingImpaired: settings.subtitleFilterSDH });

  // PERFORMANCE FIX: Keep JS thread active during playback to prevent iOS from throttling
  // the render loop. This is a workaround for frame drops when JS is idle.
  useEffect(() => {
    if (!isPlaying || Platform.OS !== 'ios') return;

    // Low-overhead heartbeat to keep JS thread active
    const heartbeat = setInterval(() => {
      // Minimal work - just touch the ref to prevent dead code elimination
      const _ = positionRef.current;
    }, 250);

    return () => clearInterval(heartbeat);
  }, [isPlaying]);

  const buildStreamSourceId = useCallback((stream: StremioPlayableStream) => {
    const providerId = stream.addonInstallationId || stream.addonId || 'stream';
    return `${providerId}:${stream.streamIndex}`;
  }, []);

  const persistStreamResumeState = useCallback(
    async (resumePositionMs: number, totalDurationMs: number, final: boolean = false) => {
      // Before the file loads there is no position, and saving 0 would lose the real one.
      if (!streamContentKey || !streamParams || totalDurationMs <= 0) {
        return;
      }

      localLibrary
        .recordProgress(
          {
            contentKey: streamContentKey,
            mediaType: streamParams.mediaType,
            title: streamParams.title,
            episodeTitle: streamParams.episodeTitle,
            seasonNumber: streamParams.seasonNumber,
            episodeNumber: streamParams.episodeNumber,
            imdbId: streamParams.imdbId,
            tmdbId: streamParams.tmdbId,
            backdropUrl: streamParams.backdrop,
          },
          resumePositionMs,
          totalDurationMs,
          { force: final }
        )
        .catch(() => {
          // History is best-effort; playback must not depend on it.
        });

      const progressRatio = totalDurationMs > 0 ? resumePositionMs / totalDurationMs : 0;
      if (progressRatio >= 0.9) {
        await stremioResumeStore.clear(streamContentKey);
        return;
      }

      await stremioResumeStore.save({
        contentKey: streamContentKey,
        positionMs: Math.max(0, Math.floor(resumePositionMs)),
        durationMs: Math.max(0, Math.floor(totalDurationMs)),
        updatedAt: Date.now(),
      });
    },
    [streamContentKey, streamParams]
  );

  // Define cleanup and playNext callbacks early so they can be used in useEffects
  const cleanup = useCallback(async () => {
    const { sessionId: sid } = cleanupInfoRef.current;
    const progress = durationRef.current
      ? Math.round((positionRef.current / durationRef.current) * 100)
      : 0;

    // Stop Trakt scrobble
    if (traktScrobbleStarted.current && metadataRef.current) {
      if (isStreamPlayback && streamParams) {
        stopGenericTraktScrobble({
          mediaType: streamParams.mediaType,
          progress,
          imdbId: streamParams.imdbId,
          tmdbId: streamParams.tmdbId,
          seasonNumber: streamParams.seasonNumber,
          episodeNumber: streamParams.episodeNumber,
        });
      } else {
        stopTraktScrobble(metadataRef.current, progress);
      }
      lastScrobbleState.current = 'stopped';
      traktScrobbleStarted.current = false;
    }

    if (isStreamPlayback) {
      await persistStreamResumeState(positionRef.current, durationRef.current, true);
    }

    if (sid) {
      try {
        await stopTranscodeSession(sid);
        console.log('[Player] Stopped transcode session:', sid);
      } catch (e) {
        console.warn('[Player] Failed to stop transcode:', e);
      }
    }

    if (progressInterval.current) clearInterval(progressInterval.current);
    if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    try {
      // MPV player is controlled via state (paused prop), not direct method
      // Just letting the component unmount will stop playback
    } catch {}
  }, [isStreamPlayback, persistStreamResumeState, streamParams]);

  const replaceWithStreamRoute = useCallback(
    async (route: GenericStreamParams) => {
      isReplacingRef.current = true;
      await cleanup();
      nav.dispatch(StackActions.replace('Player', route as any));
    },
    [cleanup, nav]
  );

  const openSourcesPicker = useCallback(
    (destination: StremioSourcesRouteParams) => {
      nav.dispatch(StackActions.replace('StremioSources', destination as any));
    },
    [nav]
  );

  const clearNextEpisodeCountdown = useCallback(() => {
    nextEpisodeCountdownStartedRef.current = false;
    if (nextEpisodeCountdownTimerRef.current) {
      clearInterval(nextEpisodeCountdownTimerRef.current);
      nextEpisodeCountdownTimerRef.current = null;
    }
    setNextEpisodeCountdown(null);
  }, []);

  const {
    sources: streamSources,
    sourcesRef: streamSourcesRef,
    isRefreshing: isRefreshingSources,
    refresh: refreshStreamSources,
    refreshIfNeeded: refreshStreamSourcesIfNeeded,
  } = useStreamSourceList(streamParams);

  /** The stream playing now, for matching a replacement or the next episode's source. */
  const currentStream = useMemo<StremioPlayableStream | null>(() => {
    if (!streamParams) {
      return null;
    }
    return (
      streamSources.find((stream) => stream.url === streamParams.uri) ?? {
        url: streamParams.uri,
        name: streamParams.streamLabel,
        addonId: streamParams.streamAddonId,
        addonName: streamParams.streamAddonName,
        streamIndex: 0,
        sourceType: 'url',
        playable: true,
      }
    );
  }, [streamParams, streamSources]);

  const {
    seriesRef: streamSeriesRef,
    seasonEpisodes: streamSeasonEpisodes,
    next: nextStreamEpisode,
    resolvingLabel: resolvingEpisodeLabel,
    isResolving: isResolvingEpisode,
    prefetchNext: prefetchNextStreamEpisode,
    playEpisode: playStreamEpisode,
    cancelLookup: cancelEpisodeLookup,
  } = useStreamEpisodes({
    params: streamParams,
    currentStream,
    subtitleAddonsEnabled: settings.stremioSubtitleAddonsEnabled,
    setPlaying: setIsPlaying,
    onPlay: replaceWithStreamRoute,
    onNeedsPicker: openSourcesPicker,
    onUnavailable: setError,
  });

  const sourcesDestination = useMemo<StremioSourcesRouteParams | null>(() => {
    const identity = streamParams ? identityForStreamParams(streamParams) : null;
    if (!streamParams || !identity) {
      return null;
    }
    return {
      identity,
      title: streamParams.title,
      backdrop: streamParams.backdrop,
      mediaType: streamParams.mediaType,
      imdbId: identity.imdbId,
      tmdbId: identity.tmdbId,
      seasonNumber: streamParams.seasonNumber,
      episodeNumber: streamParams.episodeNumber,
      episodeTitle: streamParams.episodeTitle,
      disableAutoPlay: true,
    };
  }, [streamParams]);

  const showStreamFailure = useCallback((message: string) => {
    setStreamFailed(true);
    setError(message);
  }, []);

  const {
    attemptRecovery,
    hadAttempts: hadRecoveryAttempts,
    statusMessage: recoveryStatusMessage,
  } = useStreamRecovery({
    params: streamParams,
    fileLoaded,
    sourcesRef: streamSourcesRef,
    currentStream,
    positionRef,
    onReplace: replaceWithStreamRoute,
    onExhausted: (early) =>
      showStreamFailure(
        early
          ? "This source couldn't be loaded and no working replacement was found. Choose another source."
          : 'The stream stopped and no working replacement was found. Choose another source.'
      ),
  });

  /** Replacement source if there is one, else the error with a way to pick another. */
  const handleStreamFailure = useCallback(
    (early: boolean) => {
      if (isReplacingRef.current) {
        return;
      }
      setIsPlaying(false);
      if (attemptRecovery(early)) {
        return;
      }
      if (hadRecoveryAttempts) {
        showStreamFailure(
          early
            ? "This source couldn't be loaded and no working replacement was found. Choose another source."
            : 'The stream stopped and no working replacement was found. Choose another source.'
        );
      } else {
        showStreamFailure(
          early
            ? "This source couldn't be loaded. Choose another source."
            : 'The stream was interrupted. Choose another source.'
        );
      }
    },
    [attemptRecovery, hadRecoveryAttempts, showStreamFailure]
  );

  const playPlexEpisode = useCallback(
    async (ratingKey: string) => {
      // EOF, the countdown and the buttons can all land here: navigate once.
      if (navigatedToEpisodeRef.current) {
        return;
      }
      navigatedToEpisodeRef.current = true;
      // Cleanup current player before navigating
      isReplacingRef.current = true;
      await cleanup();
      // Replace current route using stack action for compatibility
      // Preserve mediaIndex to honor user's version choice for the watch session
      nav.dispatch(StackActions.replace('Player', {
        type: 'plex',
        ratingKey,
        mediaIndex: selectedMediaIndex, // Keep same version for next episode
      }));
    },
    [cleanup, nav, selectedMediaIndex]
  );

  const playNext = useCallback(async () => {
    if (!nextEpisode) {
      return;
    }
    if (isStreamPlayback) {
      if (nextStreamEpisode) {
        nextEpisodeDismissedRef.current = true;
        clearNextEpisodeCountdown();
        await playStreamEpisode(nextStreamEpisode.season, nextStreamEpisode.episode, nextStreamEpisode.title);
      }
      return;
    }
    await playPlexEpisode(nextEpisode.ratingKey);
  }, [clearNextEpisodeCountdown, isStreamPlayback, nextEpisode, nextStreamEpisode, playPlexEpisode, playStreamEpisode]);

  const replaceStreamSource = useCallback(
    async (stream: StremioPlayableStream) => {
      if (!streamParams || !stream.url) {
        return;
      }

      // A user's choice starts a fresh recovery budget.
      await replaceWithStreamRoute(
        streamRouteFor(stream, {
          ...streamParams,
          availableStreams: streamSourcesRef.current,
          externalSubtitles: streamExternalSubtitles,
          resumePositionMs: fileLoadedRef.current ? positionRef.current : streamParams.resumePositionMs,
          recoveryAttempts: undefined,
          failedStreamUrls: undefined,
          recoverySourcesFetched: undefined,
        })
      );
    },
    [replaceWithStreamRoute, streamExternalSubtitles, streamParams, streamSourcesRef]
  );

  // Addon series: the next episode comes from TMDB or addon meta, through the same overlay as Plex.
  useEffect(() => {
    if (!isStreamPlayback || !streamSeriesRef) {
      return;
    }
    setNextEpisode(
      nextStreamEpisode
        ? {
            ratingKey: `stream-episode:${streamSeriesRef.baseId}:${nextStreamEpisode.season}:${nextStreamEpisode.episode}`,
            title: nextStreamEpisode.title,
            thumb: nextStreamEpisode.stillUrl,
            episodeLabel: `S${nextStreamEpisode.season}:E${nextStreamEpisode.episode}`,
          }
        : null
    );
  }, [isStreamPlayback, nextStreamEpisode, streamSeriesRef]);

  useEffect(() => {
    // Hide TopBar and TabBar when Player is shown
    TopBarStore.setVisible(false);
    TopBarStore.setTabBarVisible(false);

    if (!playerReady) return;

    (async () => {
      // Configure audio session
      try {
        await setAudioModeAsync({
          playsInSilentMode: true,
          shouldPlayInBackground: true,
          interruptionMode: 'mixWithOthers',
        });
      } catch (e) {
        console.warn('[Player] Failed to set audio mode:', e);
      }

      // Lock to landscape orientation by default (matching Plezy behavior)
      try {
        await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE);
      } catch (e) {
        console.warn('[Player] Failed to lock orientation:', e);
      }

      setStreamHeaders(undefined);
      clearExternalSubtitle();

      // Handle offline playback
      if (params.type === 'offline' && params.offlineFilePath && params.offlineGlobalKey) {
        try {
          console.log('[Player] Offline playback mode');
          console.log('[Player] File path:', params.offlineFilePath);

          // Load cached metadata
          const offlineMeta = await getOfflineMetadata(params.offlineGlobalKey);
          const offlineMedia = await getOfflineMedia(params.offlineGlobalKey);

          if (!offlineMeta || !offlineMedia) {
            setError('Offline metadata not found');
            setLoading(false);
            return;
          }

          // Convert offline metadata to player-compatible format
          const playerMeta = {
            ratingKey: offlineMeta.ratingKey,
            title: offlineMeta.title,
            type: offlineMedia.type,
            summary: offlineMeta.summary,
            thumb: offlineMeta.localThumbPath,
            duration: offlineMeta.duration,
            grandparentTitle: offlineMeta.grandparentTitle,
            parentIndex: offlineMeta.parentIndex,
            index: offlineMeta.index,
          };

          setMetadata(playerMeta);
          metadataRef.current = playerMeta;

          // Load cached markers for skip intro/credits
          try {
            const cachedMarkers = await getOfflineMarkers(params.offlineGlobalKey);
            if (cachedMarkers.length > 0) {
              const formattedMarkers = formatMarkersForPlayer(cachedMarkers);
              setMarkers(formattedMarkers);
              console.log('[Player] Offline markers loaded:', formattedMarkers.length);
            }
          } catch (e) {
            console.warn('[Player] Failed to load offline markers:', e);
          }

          // Set stream URL to local file (path may already include file:// prefix)
          const fileUrl = params.offlineFilePath.startsWith('file://')
            ? params.offlineFilePath
            : `file://${params.offlineFilePath}`;
          console.log('[Player] ====== OFFLINE PLAYBACK ======');
          console.log('[Player] File URL:', fileUrl);
          console.log('[Player] =============================');

          setStreamUrl(fileUrl);
          setIsDirectPlay(true);
          setSelectedQuality('original');
          setLoading(false);

          // Note: Timeline updates and Trakt scrobbling are skipped for offline playback
          // They can be synced when back online
        } catch (e: any) {
          console.error('[Player] Offline playback error:', e);
          setError(e?.message || 'Failed to load offline content');
          setLoading(false);
        }
        return;
      }

      if (params.type === 'stream' && params.uri) {
        try {
          console.log('[Player] Stream playback mode');
          const streamMeta = {
            title: params.episodeTitle || params.title,
            grandparentTitle: params.mediaType === 'episode' ? params.title : undefined,
            type: params.mediaType,
            viewOffset: params.resumePositionMs || 0,
            thumb: params.backdrop,
            parentIndex: params.seasonNumber,
            index: params.episodeNumber,
          };

          setMetadata(streamMeta);
          metadataRef.current = streamMeta;
          setStreamUrl(params.uri);
          setStreamHeaders(params.headers);
          setSelectedQuality('original');
          setQualityOptions([]);
          setIsDirectPlay(true);

          setLoading(false);
        } catch (e: any) {
          console.error('[Player] Stream playback error:', e);
          setError(e?.message || 'Failed to load stream');
          setLoading(false);
        }
        return;
      }

      if (params.type === 'plex' && params.ratingKey) {
        try {
          // Fetch metadata
          const m = await fetchPlayerMetadata(params.ratingKey);
          console.log('[Player] Metadata:', m ? { title: m.title, type: m.type } : 'null');

          if (!m) {
            setError('Could not load media metadata');
            setLoading(false);
            return;
          }

          setMetadata(m);
          metadataRef.current = m;
          cleanupInfoRef.current.ratingKey = params.ratingKey;

          // Extract Plex streams from metadata (use mediaIndex for multi-version support)
          const mediaIdx = params.mediaIndex ?? 0;
          console.log('[Player] params.mediaIndex:', params.mediaIndex, '-> mediaIdx:', mediaIdx);
          const plexMedia = m?.Media?.[mediaIdx];
          const plexPart = plexMedia?.Part?.[0];
          const streams = plexPart?.Stream || [];

          // Store part ID for stream selection API
          if (plexPart?.id) {
            setPartId(String(plexPart.id));
            console.log('[Player] Part ID:', plexPart.id);
          }

          // Parse audio streams (streamType 2)
          const audioStreams: Stream[] = streams
            .filter((s: any) => s.streamType === 2)
            .map((s: any) => ({
              id: String(s.id),
              index: s.index,
              streamType: s.streamType,
              codec: s.codec,
              language: s.language,
              languageCode: s.languageCode,
              displayTitle: s.displayTitle || s.extendedDisplayTitle || s.language || `Audio ${s.index}`,
              extendedDisplayTitle: s.extendedDisplayTitle,
              selected: s.selected || false,
            }));

          // Parse subtitle streams (streamType 3)
          const subtitleStreams: Stream[] = streams
            .filter((s: any) => s.streamType === 3)
            .map((s: any) => ({
              id: String(s.id),
              index: s.index,
              streamType: s.streamType,
              codec: s.codec,
              language: s.language,
              languageCode: s.languageCode,
              displayTitle: s.displayTitle || s.extendedDisplayTitle || s.language || `Subtitle ${s.index}`,
              extendedDisplayTitle: s.extendedDisplayTitle,
              selected: s.selected || false,
            }));

          console.log('[Player] Plex audio streams:', audioStreams.map(s => s.displayTitle));
          console.log('[Player] Plex subtitle streams:', subtitleStreams.map(s => s.displayTitle));

          setPlexAudioStreams(audioStreams);
          setPlexSubtitleStreams(subtitleStreams);

          // Set selected audio - prefer params (from player restart), then Plex default
          if (params.initialAudioStreamId) {
            setSelectedPlexAudio(params.initialAudioStreamId);
            console.log('[Player] Using initial audio from params:', params.initialAudioStreamId);
          } else {
            const selectedAudio = audioStreams.find(s => s.selected) || audioStreams[0];
            if (selectedAudio) setSelectedPlexAudio(selectedAudio.id);
          }

          // Set selected subtitle - prefer params (from player restart), then Plex default
          if (params.initialSubtitleStreamId !== undefined) {
            setSelectedPlexSubtitle(params.initialSubtitleStreamId);
            console.log('[Player] Using initial subtitle from params:', params.initialSubtitleStreamId);
          } else {
            // Check if Plex has a default subtitle selected
            const selectedSubtitle = subtitleStreams.find(s => s.selected);
            if (selectedSubtitle) {
              setSelectedPlexSubtitle(selectedSubtitle.id);
              console.log('[Player] Using Plex default subtitle:', selectedSubtitle.displayTitle);
            }
          }

          // Generate quality options based on source resolution
          const videoWidth = plexMedia?.width || 1920;
          const videoHeight = plexMedia?.height || 1080;
          const sourceBitrate = plexMedia?.bitrate || 20000; // kbps

          const options: Array<{ label: string; value: number | 'original' }> = [];

          // Always add Original/Direct Play option first
          options.push({
            label: `Original (${videoWidth}x${videoHeight}, ${sourceBitrate >= 1000 ? (sourceBitrate / 1000).toFixed(1) + ' Mbps' : sourceBitrate + ' Kbps'})`,
            value: 'original',
          });

          // Add transcoding options based on source resolution
          if (videoHeight >= 2160) {
            // 4K source
            options.push({ label: '4K (40 Mbps)', value: 40000 });
            options.push({ label: '4K (30 Mbps)', value: 30000 });
            options.push({ label: '4K (20 Mbps)', value: 20000 });
          }
          if (videoHeight >= 1080) {
            options.push({ label: '1080p (20 Mbps)', value: 20000 });
            options.push({ label: '1080p (12 Mbps)', value: 12000 });
            options.push({ label: '1080p (8 Mbps)', value: 8000 });
          }
          if (videoHeight >= 720) {
            options.push({ label: '720p (4 Mbps)', value: 4000 });
            options.push({ label: '720p (3 Mbps)', value: 3000 });
          }
          options.push({ label: '480p (1.5 Mbps)', value: 1500 });
          options.push({ label: '360p (720 Kbps)', value: 720 });

          // Remove duplicates (same bitrate)
          const uniqueOptions = options.filter((opt, idx, arr) =>
            arr.findIndex(o => o.value === opt.value) === idx
          );

          setQualityOptions(uniqueOptions);
          console.log('[Player] Quality options:', uniqueOptions.map(o => o.label));

          // Fetch markers for skip intro/credits
          try {
            const markersList = await fetchMarkers(params.ratingKey);
            setMarkers(markersList);
            console.log('[Player] Markers found:', markersList.length, markersList.map((mk: any) => `${mk.type}: ${mk.startTimeOffset}-${mk.endTimeOffset}`));
          } catch (e) {
            console.error('[Player] Failed to fetch markers:', e);
          }
          setPlexMarkersReady(true);

          // Fetch next episode if this is an episode
          if (m?.type === 'episode' && m.parentRatingKey) {
            try {
              const nextEp = await fetchNextEpisode(params.ratingKey, String(m.parentRatingKey));
              if (nextEp) {
                setNextEpisode(nextEp);
                console.log('[Player] Next episode:', nextEp.title);
              }
            } catch (e) {
              console.warn('[Player] Failed to fetch next episode:', e);
            }
          }

          // Get stream URL
          const media = (m?.Media || [])[0];
          const part = media?.Part?.[0];

          if (part?.key) {
            console.log(`[Player] Media: container=${media?.container}, videoCodec=${media?.videoCodec}`);

            // iOS/Android with MPV: Try Direct Play first (allows in-player track switching)
            // But fall back to HLS transcode for high-bandwidth audio codecs
            if (Platform.OS === 'ios') {
              // Check if audio codec requires transcoding (high-bandwidth lossless codecs)
              const audioCodec = (media?.audioCodec || '').toLowerCase();
              const audioProfile = ((media as any)?.audioProfile || '').toLowerCase();
              // Also check the first audio stream's displayTitle for codec info
              const firstAudioStream = streams.find((s: any) => s.streamType === 2);
              const audioDisplayTitle = (firstAudioStream?.displayTitle || '').toLowerCase();

              // DTS codec can be reported as "dca" or "dca-ma" (Digital Coded Audio)
              const isDTS = audioCodec.includes('dts') || audioCodec.includes('dca');
              const isDTSHD = isDTS && (
                audioCodec.includes('ma') || // dca-ma
                audioProfile.includes('ma') ||
                audioProfile.includes('hd') ||
                audioDisplayTitle.includes('dts-hd') ||
                audioDisplayTitle.includes('dts:x')
              );

              const needsAudioTranscode =
                isDTSHD || // DTS-HD MA, DTS-HD HR, DTS:X
                audioCodec.includes('truehd') || // Dolby TrueHD
                audioDisplayTitle.includes('truehd') ||
                audioDisplayTitle.includes('atmos'); // Dolby Atmos

              console.log('[Player] Audio analysis:', { audioCodec, audioProfile, audioDisplayTitle, isDTS, isDTSHD, needsAudioTranscode });
              console.log('[Player] Initial quality from params:', params.initialQuality);

              // Determine playback mode:
              // 1. If user explicitly selected a numeric quality (e.g., 20000, 12000), use HLS transcode
              // 2. If user explicitly selected 'original', use Direct Play
              // 3. If no explicit selection (undefined), use Direct Play for compatible audio, else transcode
              const userRequestedTranscode = typeof params.initialQuality === 'number';
              const userRequestedOriginal = params.initialQuality === 'original';
              const shouldTranscode = userRequestedTranscode || (needsAudioTranscode && !userRequestedOriginal);

              if (shouldTranscode) {
                console.log('[Player] iOS: Using HLS transcode', userRequestedTranscode ? '(user selected quality)' : '(audio requires transcode)');
                await setupHlsTranscode(params.ratingKey, { mediaIndex: mediaIdx });
              } else {
                try {
                  console.log('[Player] iOS: Trying Direct Play', userRequestedOriginal ? '(user requested original)' : '(compatible audio)');
                  console.log('[Player] Calling getDirectStreamUrl with mediaIndex:', mediaIdx);
                  const directUrl = await getDirectStreamUrl(params.ratingKey, mediaIdx);
                  console.log('[Player] ====== DIRECT PLAY ======');
                  console.log('[Player] Stream URL:', directUrl);
                  console.log('[Player] Mode: Direct Play (original file)');
                  console.log('[Player] ========================');
                  // Reset track refs before loading new stream
                  lastAudioTrackRef.current = null;
                  lastTextTrackRef.current = -1;
                  setStreamUrl(directUrl);
                  setIsDirectPlay(true);
                  setSelectedQuality('original');
                  setLoading(false);
                } catch (e) {
                  console.log('[Player] Direct Play failed, falling back to HLS transcode:', e);
                  // Fall through to HLS transcode
                  await setupHlsTranscode(params.ratingKey, { mediaIndex: mediaIdx });
                }
              }
            } else {
              // Android with MPV: Can use Direct Play for compatible formats
              // MPV supports MKV, HEVC, HDR, etc.
              const userRequestedTranscode = typeof params.initialQuality === 'number';
              const userRequestedOriginal = params.initialQuality === 'original';

              // Check audio codec for transcoding requirements (same as iOS)
              const audioCodec = (media?.audioCodec || '').toLowerCase();
              const audioProfile = ((media as any)?.audioProfile || '').toLowerCase();
              const firstAudioStream = streams.find((s: any) => s.streamType === 2);
              const audioDisplayTitle = (firstAudioStream?.displayTitle || '').toLowerCase();

              // DTS codec can be reported as "dca" or "dca-ma"
              const isDTS = audioCodec.includes('dts') || audioCodec.includes('dca');
              const isDTSHD = isDTS && (
                audioCodec.includes('ma') ||
                audioProfile.includes('ma') ||
                audioProfile.includes('hd') ||
                audioDisplayTitle.includes('dts-hd') ||
                audioDisplayTitle.includes('dts:x')
              );

              const needsAudioTranscode =
                isDTSHD || // DTS-HD MA, DTS-HD HR, DTS:X
                audioCodec.includes('truehd') ||
                audioDisplayTitle.includes('truehd') ||
                audioDisplayTitle.includes('atmos');

              const shouldTranscode = userRequestedTranscode || (needsAudioTranscode && !userRequestedOriginal);

              console.log('[Player] Android audio analysis:', { audioCodec, audioProfile, audioDisplayTitle, needsAudioTranscode, userRequestedOriginal });

              if (shouldTranscode) {
                console.log('[Player] Android: Using HLS transcode', userRequestedTranscode ? '(user selected quality)' : '(audio requires transcode)');
                await setupHlsTranscode(params.ratingKey, { mediaIndex: mediaIdx });
              } else {
                try {
                  console.log('[Player] Android: Trying Direct Play with MPV', userRequestedOriginal ? '(user requested original)' : '(compatible audio)');
                  const directUrl = await getDirectStreamUrl(params.ratingKey, mediaIdx);
                  console.log('[Player] ====== DIRECT PLAY (MPV) ======');
                  console.log('[Player] Stream URL:', directUrl);
                  console.log('[Player] Mode: Direct Play (original file)');
                  console.log('[Player] ============================');
                  // Reset track refs before loading new stream
                  lastAudioTrackRef.current = null;
                  lastTextTrackRef.current = -1;
                  setStreamUrl(directUrl);
                  setIsDirectPlay(true);
                  setSelectedQuality('original');
                  setLoading(false);
                } catch (e) {
                  console.log('[Player] Direct Play failed, falling back to HLS transcode:', e);
                  await setupHlsTranscode(params.ratingKey, { mediaIndex: mediaIdx });
                }
              }
            }

            async function setupHlsTranscode(ratingKey: string, options?: { bitrate?: number; mediaIndex?: number }) {
              const bitrate = params.initialQuality && typeof params.initialQuality === 'number'
                ? params.initialQuality
                : (options?.bitrate || 20000);
              // Resolution based on bitrate: 8+ Mbps = 1080p, 3+ Mbps = 720p, 1+ Mbps = 480p
              const resolution = bitrate >= 8000 ? '1920x1080' : bitrate >= 3000 ? '1280x720' : bitrate >= 1000 ? '854x480' : '640x360';

              // Use initial stream IDs from params (player restart) if available
              const audioStreamId = params.initialAudioStreamId;
              const subtitleStreamId = params.initialSubtitleStreamId;

              // Use mediaIndex from options (for multi-version support)
              const transcodeMediaIndex = options?.mediaIndex ?? 0;

              const { startUrl, sessionUrl, sessionId: sid } = getTranscodeStreamUrl(ratingKey, {
                maxVideoBitrate: bitrate,
                videoResolution: resolution,
                protocol: 'hls',
                audioStreamID: audioStreamId,
                subtitleStreamID: subtitleStreamId,
                mediaIndex: transcodeMediaIndex,
              });

              console.log('[Player] ====== HLS TRANSCODE ======');
              console.log('[Player] Start URL:', startUrl.substring(0, 150) + '...');
              console.log('[Player] Session URL:', sessionUrl);
              console.log('[Player] Session ID:', sid);
              console.log('[Player] Bitrate:', bitrate, 'kbps');
              console.log('[Player] Resolution:', resolution);
              console.log('[Player] Audio Stream ID:', audioStreamId || 'default');
              console.log('[Player] Subtitle Stream ID:', subtitleStreamId || 'none');
              console.log('[Player] ============================');

              // Use startUrl directly - it contains all transcode parameters
              // The session URL doesn't include the transcode parameters
              console.log('[Player] Using start URL directly for playback');
              // Reset track refs before loading new stream
              lastAudioTrackRef.current = null;
              lastTextTrackRef.current = -1;
              setStreamUrl(startUrl);

              setSessionId(sid);
              cleanupInfoRef.current.sessionId = sid;
              setIsDirectPlay(false);
              setSelectedQuality(bitrate);
              setLoading(false);
            }
          } else {
            setError('No playable media found');
            setLoading(false);
          }
        } catch (e: any) {
          console.error('[Player] Error:', e);
          setError(e.message || 'Failed to load video');
          setLoading(false);
        }
      }
    })();

    return () => {
      // Don't restore TopBar/TabBar here - let the destination screen manage its own state
      // via useFocusEffect to avoid flashing TopBar on Details screen

      // Cleanup
      (async () => {
        const { sessionId: sid } = cleanupInfoRef.current;

        // Stop Trakt scrobble
        if (traktScrobbleStarted.current && metadataRef.current) {
          const progress = durationRef.current
            ? Math.round((positionRef.current / durationRef.current) * 100)
            : 0;
          if (isStreamPlayback && streamParams) {
            stopGenericTraktScrobble({
              mediaType: streamParams.mediaType,
              progress,
              imdbId: streamParams.imdbId,
              tmdbId: streamParams.tmdbId,
              seasonNumber: streamParams.seasonNumber,
              episodeNumber: streamParams.episodeNumber,
            });
            await persistStreamResumeState(positionRef.current, durationRef.current, true);
          } else {
            stopTraktScrobble(metadataRef.current, progress);
          }
          lastScrobbleState.current = 'stopped';
        }

        if (params.type === 'plex' && sid) {
          try {
            await stopTranscodeSession(sid);
            console.log('[Player] Stopped transcode session:', sid);
          } catch (e) {
            console.warn('[Player] Failed to stop transcode:', e);
          }
        }

        // Only reset orientation/audio if we're leaving the Player entirely,
        // not when we're replacing to another Player instance
        if (!isReplacingRef.current) {
          // Restore to portrait when exiting player (matching Plezy behavior for phones)
          try {
            await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
          } catch (e) {}
          isRotationLockedRef.current = true;
          setIsRotationLocked(true);

          try {
            await setAudioModeAsync({
              playsInSilentMode: false,
              shouldPlayInBackground: false,
              interruptionMode: 'mixWithOthers',
            });
          } catch (e) {}
        }
      })();

      if (progressInterval.current) clearInterval(progressInterval.current);
      if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    };
  }, [clearExternalSubtitle, playerReady, isStreamPlayback, params.type, persistStreamResumeState, streamParams]);

  // Update progress to Plex - use refs to avoid recreating interval on every position change
  const isPlayingRef = useRef(true); // Start as playing

  useEffect(() => {
    if (params.type !== 'plex' || !params.ratingKey || !isConnected) return;

    const updateProgress = async () => {
      const currentPosition = positionRef.current;
      const currentDuration = durationRef.current;
      const currentIsPlaying = isPlayingRef.current;

      if (currentPosition > 0 && currentDuration > 0) {
        console.log(`[Player] Sending timeline update: pos=${Math.floor(currentPosition)}ms, dur=${Math.floor(currentDuration)}ms, state=${currentIsPlaying ? 'playing' : 'paused'}`);
        try {
          await updatePlaybackTimeline(
            String(params.ratingKey),
            currentIsPlaying ? 'playing' : 'paused',
            Math.floor(currentPosition),
            Math.floor(currentDuration)
          );
        } catch (e) {
          console.error('[Player] Progress update failed:', e);
        }
      }
    };

    // Send initial update after a short delay to ensure player has loaded
    const initialTimeout = setTimeout(updateProgress, 2000);

    // Then send updates every 10 seconds
    progressInterval.current = setInterval(updateProgress, 10000);

    return () => {
      clearTimeout(initialTimeout);
      if (progressInterval.current) clearInterval(progressInterval.current);
    };
  }, [isConnected, params.ratingKey, params.type]);

  // Cleanup on navigation
  useEffect(() => {
    const cleanup = async () => {
      const { sessionId: sid, ratingKey: rk } = cleanupInfoRef.current;
      const progress = durationRef.current
        ? Math.round((positionRef.current / durationRef.current) * 100)
        : 0;

      // Stop Trakt scrobble
      if (traktScrobbleStarted.current && metadataRef.current) {
        if (isStreamPlayback && streamParams) {
          stopGenericTraktScrobble({
            mediaType: streamParams.mediaType,
            progress,
            imdbId: streamParams.imdbId,
            tmdbId: streamParams.tmdbId,
            seasonNumber: streamParams.seasonNumber,
            episodeNumber: streamParams.episodeNumber,
          });
        } else {
          stopTraktScrobble(metadataRef.current, progress);
        }
        lastScrobbleState.current = 'stopped';
      }

      // Send stopped timeline update with actual position
      if (params.type === 'plex' && rk) {
        try {
          console.log(`[Player] Sending stopped timeline: pos=${Math.floor(positionRef.current)}ms, dur=${Math.floor(durationRef.current)}ms`);
          await updatePlaybackTimeline(rk, 'stopped', Math.floor(positionRef.current), Math.floor(durationRef.current));
        } catch (e) {}
      }

      if (isStreamPlayback) {
        await persistStreamResumeState(positionRef.current, durationRef.current, true);
      }

      // Stop transcode session
      if (params.type === 'plex' && sid) {
        try {
          await stopTranscodeSession(sid);
        } catch (e) {}
      }
    };

    const unsubscribe = nav.addListener('beforeRemove', () => {
      cleanup();
    });

    const focusSub = nav.addListener('focus', async () => {
      try {
        // Apply rotation lock state when screen gains focus
        if (isRotationLockedRef.current) {
          await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE);
        } else {
          await ScreenOrientation.unlockAsync();
        }
        await setAudioModeAsync({ playsInSilentMode: true, shouldPlayInBackground: true, interruptionMode: 'mixWithOthers' });
        // If we just replaced into this screen, ensure playback starts and orientation is applied
        if (isReplacingRef.current) {
          isReplacingRef.current = false;
          try {
            if (isRotationLockedRef.current) {
              await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE);
            } else {
              await ScreenOrientation.unlockAsync();
            }
          } catch {}
          // MPV player auto-starts via paused prop, no manual action needed
        }
      } catch {}
    });

    const blurSub = nav.addListener('blur', async () => {
      try {
        // MPV player will pause via state change when screen loses focus
        setIsPlaying(false);
      } catch {}
    });

    return () => { unsubscribe(); focusSub(); blurSub(); };
  }, [isStreamPlayback, nav, params.ratingKey, params.type, persistStreamResumeState, streamParams]);

  // Auto-hide controls
  const resetControlsTimeout = () => {
    if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    setShowControls(true);
    controlsTimeout.current = setTimeout(() => {
      setShowControls(false);
    }, 4000);
  };

  // Toggle rotation lock (matching Plezy's behavior)
  // Locked: landscape left + right only
  // Unlocked: all orientations (portrait + landscape)
  const toggleRotationLock = async () => {
    try {
      if (isRotationLocked) {
        // Unlock: allow all orientations
        await ScreenOrientation.unlockAsync();
        setIsRotationLocked(false);
        isRotationLockedRef.current = false;
      } else {
        // Lock: landscape only
        await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE);
        setIsRotationLocked(true);
        isRotationLockedRef.current = true;
      }
    } catch (e) {
      console.warn('[Player] Failed to toggle rotation lock:', e);
    }
  };

  // Rotation lock icons (matching Plezy's Material Symbols)
  const rotationLockIcons = {
    locked: require('../../assets/player_icons/mobile-rotate-lock-outline-rounded.png'),
    unlocked: require('../../assets/player_icons/mobile-rotate-outline-rounded.png'),
  };

  // Cycle through aspect ratio modes: contain → cover → fill
  const cycleAspectRatio = async () => {
    try {
      const newMode = await mpvPlayerRef.current?.cycleAspectRatio();
      if (newMode !== undefined) {
        setAspectRatioMode(newMode);
      }
    } catch (e) {
      console.warn('[Player] Failed to cycle aspect ratio:', e);
    }
  };

  // Aspect ratio icons (matching Plezy's Material Symbols)
  const aspectRatioIcons = {
    contain: require('../../assets/player_icons/fit-screen-rounded.png'),
    cover: require('../../assets/player_icons/aspect-ratio-outline-rounded.png'),
    stretch: require('../../assets/player_icons/settings-overscan-outline-rounded.png'),
  };

  // Get icon for current aspect ratio mode
  const getAspectRatioIcon = () => {
    switch (aspectRatioMode) {
      case 0: return aspectRatioIcons.contain; // letterbox - fits content within screen
      case 1: return aspectRatioIcons.cover; // fill screen - fills screen, crops edges
      case 2: return aspectRatioIcons.stretch; // stretch - stretches to fill, distorts aspect
      default: return aspectRatioIcons.contain;
    }
  };

  useEffect(() => {
    if (isPlaying) {
      resetControlsTimeout();
    }
  }, [isPlaying]);

  // Listen for dimension changes
  useEffect(() => {
    const subscription = Dimensions.addEventListener('change', ({ window }) => {
      setDimensions({ width: window.width, height: window.height });
    });

    return () => subscription?.remove();
  }, []);

  // Fetch performance stats when settings sheet is open
  useEffect(() => {
    if (!showSettingsSheet) return;

    const fetchStats = async () => {
      try {
        const stats = await mpvPlayerRef.current?.getPerformanceStats();
        if (stats) {
          setPerformanceStats(stats);
        }
      } catch (e) {
        // Silently ignore errors
      }
    };

    // Fetch immediately and then every 1 second
    fetchStats();
    const interval = setInterval(fetchStats, 1000);
    return () => clearInterval(interval);
  }, [showSettingsSheet]);

  // Next episode countdown logic - trigger 5-second countdown when credits start (or fallback)
  useEffect(() => {
    // "Auto-Play Next" off: no automatic countdown. The Play Next button stays available.
    if (metadata?.type !== 'episode' || !nextEpisode || !duration || !settings.autoPlayNext) {
      if (nextEpisodeCountdownStartedRef.current) {
        clearNextEpisodeCountdown();
      }
      return;
    }
    if (isScrubbing) {
      return;
    }

    const creditsMarker = markers.find(m => m.type === 'credits');
    const postCreditsScene = creditsMarker
      ? markers.find(m => m.type === 'postcredits' && m.startTimeOffset >= creditsMarker.startTimeOffset)
      : undefined;
    const fallbackSeconds = settings.creditsCountdownFallback; // User setting: seconds before end if no credits marker
    const bufferSeconds = 3; // Show overlay 3 seconds before trigger point

    let triggerStart: number;
    if (postCreditsScene) {
      // Community data knows a post-credits scene: don't cut it off, trigger after it.
      triggerStart = Math.max(0, postCreditsScene.endTimeOffset / 1000 - bufferSeconds);
    } else if (creditsMarker) {
      // Use credits marker start time (minus buffer)
      triggerStart = Math.max(0, creditsMarker.startTimeOffset / 1000 - bufferSeconds);
    } else {
      // Fallback: X seconds before end
      triggerStart = Math.max(0, duration / 1000 - fallbackSeconds);
    }

    const currentPositionSec = position / 1000;

    // Addon streams: look up the next episode's source a minute ahead.
    if (isStreamPlayback && currentPositionSec >= triggerStart - 60) {
      prefetchNextStreamEpisode();
    }

    if (currentPositionSec >= triggerStart) {
      // Not after the user cancelled it, or during a source lookup.
      if (!nextEpisodeCountdownStartedRef.current && !nextEpisodeDismissedRef.current && !isResolvingEpisode) {
        // Start 5-second countdown
        console.log('[Player] Starting next episode countdown (5s)');
        nextEpisodeCountdownStartedRef.current = true;
        setNextEpisodeCountdown(5);

        nextEpisodeCountdownTimerRef.current = setInterval(() => {
          setNextEpisodeCountdown(prev => {
            if (prev === null || prev <= 1) {
              clearInterval(nextEpisodeCountdownTimerRef.current!);
              nextEpisodeCountdownTimerRef.current = null;
              return 0; // Will trigger playNext via the auto-play effect
            }
            return prev - 1;
          });
        }, 1000);
      }
    } else {
      // Seeked back before the trigger point: the countdown may run again later.
      nextEpisodeDismissedRef.current = false;
      if (nextEpisodeCountdownStartedRef.current) {
        clearNextEpisodeCountdown();
      }
    }
  }, [
    clearNextEpisodeCountdown,
    duration,
    isResolvingEpisode,
    isScrubbing,
    isStreamPlayback,
    markers,
    metadata,
    nextEpisode,
    position,
    prefetchNextStreamEpisode,
    settings.autoPlayNext,
    settings.creditsCountdownFallback,
  ]);

  // Cleanup next episode countdown timer on unmount
  useEffect(() => {
    return () => {
      if (nextEpisodeCountdownTimerRef.current) {
        clearInterval(nextEpisodeCountdownTimerRef.current);
      }
    };
  }, []);

  // Auto-play next episode
  useEffect(() => {
    if (nextEpisodeCountdown !== null && nextEpisodeCountdown <= 0 && nextEpisode) {
      setNextEpisodeCountdown(null);
      playNext();
    }
  }, [nextEpisodeCountdown, nextEpisode, playNext]);

  // Cancel auto-skip helper
  const cancelAutoSkip = useCallback(() => {
    if (autoSkipTimerRef.current) {
      clearInterval(autoSkipTimerRef.current);
      autoSkipTimerRef.current = null;
    }
    setAutoSkipCountdown(null);
  }, []);

  // Auto-skip intro/credits when enabled
  useEffect(() => {
    if (markers.length === 0) return;

    // Find current marker
    const currentMarker = markers.find(m =>
      m.type !== 'postcredits' && position >= m.startTimeOffset && position <= m.endTimeOffset
    );

    if (!currentMarker) {
      // Exited marker region - cancel any running auto-skip
      if (autoSkipCountdown !== null) {
        if (autoSkipTimerRef.current) {
          clearInterval(autoSkipTimerRef.current);
          autoSkipTimerRef.current = null;
        }
        setAutoSkipCountdown(null);
      }
      return;
    }

    // Check if already triggered for this marker
    const markerId = currentMarker.id ? String(currentMarker.id) : `${currentMarker.type}-${currentMarker.startTimeOffset}`;
    if (autoSkipTriggeredMarkersRef.current.has(markerId)) {
      return;
    }

    // Check auto-skip settings from user preferences
    const shouldAutoSkip =
      (currentMarker.type === 'intro' && settings.skipIntroAutomatically) ||
      (currentMarker.type === 'credits' && settings.skipCreditsAutomatically) ||
      (currentMarker.type === 'recap' && settings.skipRecapAutomatically);

    if (!shouldAutoSkip) return;

    // Only start countdown if not already running
    if (autoSkipCountdown === null && !autoSkipTimerRef.current) {
      const delay = settings.autoSkipDelay;
      console.log(`[Player] Starting auto-skip countdown for ${currentMarker.type}: ${delay}s`);
      setAutoSkipCountdown(delay);

      autoSkipTimerRef.current = setInterval(() => {
        setAutoSkipCountdown(prev => {
          if (prev === null || prev <= 1) {
            // Time to skip
            clearInterval(autoSkipTimerRef.current!);
            autoSkipTimerRef.current = null;
            // Perform the skip
            skipMarker(currentMarker);
            return null;
          }
          return prev - 1;
        });
      }, 1000);
    }
  }, [position, markers, autoSkipCountdown, settings.skipIntroAutomatically, settings.skipCreditsAutomatically, settings.skipRecapAutomatically, settings.autoSkipDelay]);

  // Cleanup auto-skip timer on unmount
  useEffect(() => {
    return () => {
      if (autoSkipTimerRef.current) {
        clearInterval(autoSkipTimerRef.current);
      }
    };
  }, []);

  // Movie end handling - use ref to prevent multiple triggers
  useEffect(() => {
    if (metadata?.type !== 'movie' || !duration) return;
    if (movieEndTriggeredRef.current) return; // Already triggered

    const creditsMarker = markers.find(m => m.type === 'credits');
    const fallbackMs = settings.creditsCountdownFallback * 1000;
    const postCreditsScene = creditsMarker
      ? markers.find(m => m.type === 'postcredits' && m.startTimeOffset >= creditsMarker.startTimeOffset)
      : undefined;
    const creditsStart = postCreditsScene
      ? postCreditsScene.endTimeOffset / 1000
      : creditsMarker
        ? creditsMarker.startTimeOffset / 1000
        : Math.max(0, duration - fallbackMs) / 1000;

    if (position / 1000 > 1 && position / 1000 >= creditsStart) {
      movieEndTriggeredRef.current = true;
      nav.goBack();
    }
  }, [metadata, duration, position, markers, nav, settings.creditsCountdownFallback]);

  const seekPlayer = useCallback((targetMs: number) => {
    lastSeekRef.current = { targetMs, at: Date.now() };
    mpvPlayerRef.current?.seek(targetMs / 1000); // MPV uses seconds
  }, []);

  /** Within the last 2% or 10 s, counting a seek the position hasn't caught up with. */
  const isNearStreamEnd = useCallback(() => {
    const durationMs = durationRef.current;
    if (durationMs <= 0) {
      return true;
    }
    const seek = lastSeekRef.current;
    const reachedMs = Math.max(positionRef.current, Date.now() - seek.at < 5000 ? seek.targetMs : 0);
    return reachedMs / durationMs >= 0.98 || durationMs - reachedMs <= 10_000;
  }, []);

  // MPV Player event handlers (unified for iOS and Android)
  const onPlayerLoad = useCallback(async (data: any) => {
    console.log('[Player] MPV onLoad:', data);
    fileLoadedRef.current = true;
    setFileLoaded(true);
    setPlaybackRate(Math.min(2, Math.max(0.25, settings.defaultPlaybackSpeed || 1)));
    const durationMs = (data.duration || 0) * 1000;
    setDuration(durationMs);
    durationRef.current = durationMs;

    // Capture player backend (default to MPV)
    const backend = data.playerBackend || 'MPV';
    setPlayerBackend(backend);
    console.log('[Player] Player backend:', backend);

    // Capture HDR info from native player
    if (data.hdrType) {
      setHdrType(data.hdrType);
      console.log('[Player] HDR type from native:', data.hdrType);
    }
    if (data.colorSpace) {
      setColorSpace(data.colorSpace);
      console.log('[Player] Color space from native:', data.colorSpace);
    }

    // Use tracks from onLoad event data (sent by native side)
    const loadedAudioTracks = data.audioTracks || [];
    const loadedTextTracks = data.textTracks || [];

    if (data.nativeLogPath) {
      console.log('[Player] Native log path:', data.nativeLogPath);
    }
    if (MPVPlayerModule?.getNativeLog) {
      try {
        const nativeLog = await MPVPlayerModule.getNativeLog();
        if (nativeLog) {
          console.log('[Player] Native log content (tail):\n' + nativeLog);
        } else {
          console.log('[Player] Native log content is empty');
        }
      } catch (err) {
        console.warn('[Player] Failed to read native log:', err);
      }
    }

    audioTracksRef.current = loadedAudioTracks;
    textTracksRef.current = loadedTextTracks;
    setAudioTracks(loadedAudioTracks);
    setTextTracks(loadedTextTracks);

    // Set default selected tracks based on isEnabled
    // Also sync the refs to prevent duplicate calls
    const enabledAudio = loadedAudioTracks.find((t: AudioTrack) => t.isEnabled);
    const enabledText = loadedTextTracks.find((t: TextTrack) => t.isEnabled);
    if (enabledAudio) {
      setSelectedAudioTrack(enabledAudio.id);
      lastAudioTrackRef.current = enabledAudio.id;
    }
    // For text tracks, -1 means "none", otherwise use the enabled track id
    if (enabledText) {
      setSelectedTextTrack(enabledText.id);
      lastTextTrackRef.current = enabledText.id;
    } else {
      lastTextTrackRef.current = -1;
    }

    // Resume from route or metadata viewOffset if available
    const resumeMs = Number(streamParams?.resumePositionMs || metadata?.viewOffset || 0);
    if (resumeMs > 0) {
      if (mpvPlayerRef.current) {
        console.log('[Player] Resuming from position:', resumeMs);
        seekPlayer(resumeMs);
      }
    }

    // Start Trakt scrobble
    if (isStreamPlayback && streamParams && !traktScrobbleStarted.current) {
      appLogger.info('[Stremio] Stream playback started', {
        contentKey: streamParams.contentKey,
        addonId: streamParams.streamAddonId,
        addonName: streamParams.streamAddonName,
        streamLabel: streamParams.streamLabel,
      });
      startGenericTraktScrobble({
        mediaType: streamParams.mediaType,
        progress: 0,
        imdbId: streamParams.imdbId,
        tmdbId: streamParams.tmdbId,
        seasonNumber: streamParams.seasonNumber,
        episodeNumber: streamParams.episodeNumber,
      });
      traktScrobbleStarted.current = true;
      lastScrobbleState.current = 'playing';
      return;
    }

    if (metadata?.viewOffset) {
      const legacyResumeMs = parseInt(String(metadata.viewOffset));
      if (legacyResumeMs > 0 && mpvPlayerRef.current) {
        console.log('[Player] Resuming from viewOffset:', legacyResumeMs);
        mpvPlayerRef.current.seek(legacyResumeMs / 1000); // MPV uses seconds
      }
    }

    if (metadata && !traktScrobbleStarted.current) {
      startTraktScrobble(metadata, 0);
      traktScrobbleStarted.current = true;
      lastScrobbleState.current = 'playing';
    }
  }, [isStreamPlayback, metadata, seekPlayer, settings.defaultPlaybackSpeed, streamParams]);

  const onPlayerProgress = useCallback((data: any) => {
    const currentTimeMs = (data.currentTime || 0) * 1000;
    const durationMs = (data.duration || 0) * 1000;

    // Update position ref always for cleanup/timeline
    positionRef.current = currentTimeMs;
    if (isStreamPlayback) {
      setExternalSubtitleTimeMs(currentTimeMs);
    }

    // Only update position state if not scrubbing (throttle to reduce renders)
    if (!isScrubbing) {
      setPosition(currentTimeMs);
    }

    // Only update duration if it changed (duration is usually constant)
    if (durationMs > 0 && Math.abs(durationMs - durationRef.current) > 100) {
      setDuration(durationMs);
      durationRef.current = durationMs;
    }

    // Update play state - prefer isPlaying flag, fallback to playbackRate
    const currentlyPlaying = data.isPlaying ?? ((data.playbackRate || 0) > 0);
    const wasPlaying = isPlayingRef.current;

    // Only update isPlaying state if it changed
    if (currentlyPlaying !== wasPlaying) {
      setIsPlaying(currentlyPlaying);
      isPlayingRef.current = currentlyPlaying;
    }

    // Trakt scrobbling integration
    const progressPercent = durationMs > 0 ? Math.round((currentTimeMs / durationMs) * 100) : 0;

    // Handle scrobble state changes
    if (currentlyPlaying && lastScrobbleState.current !== 'playing') {
      lastScrobbleState.current = 'playing';
      if (isStreamPlayback && streamParams) {
        startGenericTraktScrobble({
          mediaType: streamParams.mediaType,
          progress: progressPercent,
          imdbId: streamParams.imdbId,
          tmdbId: streamParams.tmdbId,
          seasonNumber: streamParams.seasonNumber,
          episodeNumber: streamParams.episodeNumber,
        });
      } else {
        startTraktScrobble(metadataRef.current, progressPercent);
      }
      traktScrobbleStarted.current = true;
    } else if (!currentlyPlaying && wasPlaying && lastScrobbleState.current === 'playing') {
      lastScrobbleState.current = 'paused';
      if (isStreamPlayback && streamParams) {
        pauseGenericTraktScrobble({
          mediaType: streamParams.mediaType,
          progress: progressPercent,
          imdbId: streamParams.imdbId,
          tmdbId: streamParams.tmdbId,
          seasonNumber: streamParams.seasonNumber,
          episodeNumber: streamParams.episodeNumber,
        });
      } else {
        pauseTraktScrobble(metadataRef.current, progressPercent);
      }
    }

    if (isStreamPlayback) {
      const now = Date.now();
      if (now - streamResumeSaveAtRef.current >= 10000) {
        streamResumeSaveAtRef.current = now;
        persistStreamResumeState(currentTimeMs, durationMs).catch(() => {
          // Ignore local resume persistence failures during playback.
        });
      }
    }
  }, [isScrubbing, isStreamPlayback, persistStreamResumeState, setExternalSubtitleTimeMs, streamParams]);

  const onPlayerBuffering = useCallback((data: any) => {
    setBuffering(data.isBuffering || false);
  }, []);

  const onPlayerEnd = useCallback(() => {
    console.log('[Player] MPV onEnd');
    if (isReplacingRef.current) {
      return;
    }

    // Native reports a dead link or dropped stream as end of file, so an end
    // that never loaded or stopped short is a source failure, not a finish.
    if (isStreamPlayback && (!fileLoadedRef.current || !isNearStreamEnd())) {
      handleStreamFailure(!fileLoadedRef.current);
      return;
    }

    setIsPlaying(false);

    // Stop Trakt scrobble
    if (traktScrobbleStarted.current) {
      if (isStreamPlayback && streamParams) {
        stopGenericTraktScrobble({
          mediaType: streamParams.mediaType,
          progress: 100,
          imdbId: streamParams.imdbId,
          tmdbId: streamParams.tmdbId,
          seasonNumber: streamParams.seasonNumber,
          episodeNumber: streamParams.episodeNumber,
        });
        if (streamContentKey) {
          stremioResumeStore.clear(streamContentKey);
        }
      } else if (metadata) {
        stopTraktScrobble(metadata, 100);
      }
      lastScrobbleState.current = 'stopped';
    }

    // Auto-play the next episode if the end arrived before the countdown finished.
    if (metadata?.type === 'episode' && nextEpisode && settings.autoPlayNext && !nextEpisodeDismissedRef.current) {
      playNext();
    }
  }, [handleStreamFailure, isNearStreamEnd, isStreamPlayback, metadata, nextEpisode, playNext, settings.autoPlayNext, streamContentKey, streamParams]);

  const onPlayerError = useCallback((error: any) => {
    const errorMessage = error?.error || error?.message || 'Unknown error';
    console.log('[Player] MPV onError:', errorMessage);

    // Don't show UI error for debug messages
    if (errorMessage.startsWith('DEBUG:')) {
      console.log('[Player] DEBUG from native:', errorMessage);
      return;
    }

    console.error('[Player] Actual playback error:', errorMessage);
    if (isStreamPlayback && streamParams) {
      appLogger.warn('[Stremio] Stream playback failed', {
        contentKey: streamParams.contentKey,
        addonId: streamParams.streamAddonId,
        addonName: streamParams.streamAddonName,
        error: errorMessage,
      });

      // Errors from the player itself aren't about this source.
      if (!/initiali[sz]/i.test(errorMessage) && !errorMessage.startsWith('No URI')) {
        if (fileLoadedRef.current && isNearStreamEnd()) {
          // Dying in the last moments counts as finishing.
          onPlayerEnd();
        } else {
          handleStreamFailure(!fileLoadedRef.current);
        }
        return;
      }
    }
    setError(`Playback error: ${errorMessage}`);
  }, [handleStreamFailure, isNearStreamEnd, isStreamPlayback, onPlayerEnd, streamParams]);

  // Playback status handler from the old expo-av fallback (not wired to a player)
  const onPlaybackStatusUpdate = useCallback((status: LegacyPlaybackStatus) => {
    if (!status.isLoaded) {
      if (status.error) {
        console.error('[Player] expo-av error:', status.error);
        setError(`Playback error: ${status.error}`);
      }
      return;
    }

    const wasPlaying = isPlaying;
    setIsPlaying(status.isPlaying);
    setDuration(status.durationMillis || 0);
    durationRef.current = status.durationMillis || 0;
    if (!isScrubbing) {
      setPosition(status.positionMillis || 0);
      positionRef.current = status.positionMillis || 0;
    }
    setBuffering(status.isBuffering);

    // Trakt scrobbling integration
    const progressPercent = status.durationMillis
      ? Math.round((status.positionMillis / status.durationMillis) * 100)
      : 0;

    // Handle scrobble state changes
    if (status.isPlaying && lastScrobbleState.current !== 'playing') {
      lastScrobbleState.current = 'playing';
      if (isStreamPlayback && streamParams) {
        startGenericTraktScrobble({
          mediaType: streamParams.mediaType,
          progress: progressPercent,
          imdbId: streamParams.imdbId,
          tmdbId: streamParams.tmdbId,
          seasonNumber: streamParams.seasonNumber,
          episodeNumber: streamParams.episodeNumber,
        });
      } else {
        startTraktScrobble(metadata, progressPercent);
      }
      traktScrobbleStarted.current = true;
    } else if (!status.isPlaying && wasPlaying && lastScrobbleState.current === 'playing') {
      lastScrobbleState.current = 'paused';
      if (isStreamPlayback && streamParams) {
        pauseGenericTraktScrobble({
          mediaType: streamParams.mediaType,
          progress: progressPercent,
          imdbId: streamParams.imdbId,
          tmdbId: streamParams.tmdbId,
          seasonNumber: streamParams.seasonNumber,
          episodeNumber: streamParams.episodeNumber,
        });
      } else {
        pauseTraktScrobble(metadata, progressPercent);
      }
    }
  }, [isScrubbing, isPlaying, isStreamPlayback, metadata, streamParams]);

  // MPV tracks changed callback (for both iOS and Android)
  const onMpvTracksChanged = useCallback((data: { audioTracks: MPVAudioTrack[]; subtitleTracks: MPVSubtitleTrack[] }) => {
    console.log('[Player] MPV onTracksChanged:', data);

    // Convert MPV tracks to AudioTrack/TextTrack format for compatibility
    const convertedAudioTracks: AudioTrack[] = (data.audioTracks || []).map((track, index) => ({
      id: track.id,
      index: index,
      name: track.name,
      language: track.language,
      languageCode: track.language,
      isEnabled: index === 0, // First track enabled by default
      bitRate: 0, // Not available from MPV
      bitDepth: 0, // Not available from MPV
    }));

    const convertedTextTracks: TextTrack[] = (data.subtitleTracks || []).map((track, index) => ({
      id: track.id,
      index: index,
      name: track.name,
      language: track.language,
      languageCode: track.language,
      isEnabled: false, // Subtitles off by default
      isImageSubtitle: track.codec === 'hdmv_pgs_subtitle' || track.codec === 'dvd_subtitle',
    }));

    audioTracksRef.current = convertedAudioTracks;
    textTracksRef.current = convertedTextTracks;
    setAudioTracks(convertedAudioTracks);
    setTextTracks(convertedTextTracks);

    // Set initial selections
    if (convertedAudioTracks.length > 0) {
      setSelectedAudioTrack(convertedAudioTracks[0].id);
      lastAudioTrackRef.current = convertedAudioTracks[0].id;
    }
    lastTextTrackRef.current = -1;
  }, []);

  const togglePlayPause = async () => {
    // MPV player paused prop is controlled via state
    // The component re-renders with updated paused prop
    setIsPlaying(!isPlaying);
  };

  const skip = async (seconds: number) => {
    seekPlayer(Math.max(0, Math.min(duration, position + seconds * 1000)));
  };

  const skipMarker = async (marker: { id?: number | string; type: string; startTimeOffset: number; endTimeOffset: number }) => {
    // Mark as triggered so auto-skip won't fire again if user seeks back
    const markerId = marker.id ? String(marker.id) : `${marker.type}-${marker.startTimeOffset}`;
    autoSkipTriggeredMarkersRef.current.add(markerId);
    // Cancel auto-skip timer
    if (autoSkipTimerRef.current) {
      clearInterval(autoSkipTimerRef.current);
      autoSkipTimerRef.current = null;
    }
    setAutoSkipCountdown(null);

    const targetMs = marker.endTimeOffset + 1000;
    seekPlayer(targetMs);
    console.log(`[Player] Skipped ${marker.type} to ${targetMs}ms`);
  };

  const restart = async () => {
    seekPlayer(0);
    setIsPlaying(true);
  };

  // Track selection handlers (native player tracks by ID)
  const handleAudioTrackChange = useCallback((trackId: number) => {
    // Prevent duplicate calls
    if (lastAudioTrackRef.current === trackId) {
      console.log('[Player] Audio track already set to:', trackId);
      return;
    }
    lastAudioTrackRef.current = trackId;

    if (mpvPlayerRef.current) {
      console.log('[Player] Setting audio track (MPV):', trackId);
      mpvPlayerRef.current.setAudioTrack(trackId);
      setSelectedAudioTrack(trackId);
    }
  }, []);

  const handleTextTrackChange = useCallback((trackId: number) => {
    // Prevent duplicate calls
    if (lastTextTrackRef.current === trackId) {
      console.log('[Player] Text track already set to:', trackId);
      return;
    }
    lastTextTrackRef.current = trackId;

    if (mpvPlayerRef.current) {
      console.log('[Player] Setting subtitle track (MPV):', trackId);
      mpvPlayerRef.current.setSubtitleTrack(trackId);
      setSelectedTextTrack(trackId);
      if (trackId !== -1 || selectedExternalSubtitleId) {
        clearExternalSubtitle();
      }
    }
  }, [clearExternalSubtitle, selectedExternalSubtitleId]);

  const trackMemoryIds = useMemo<TrackMemoryIds | null>(() => {
    if (streamContentKey) {
      return { mediaId: streamContentKey, seriesId: streamSeriesRef?.baseId };
    }
    if (params.type === 'plex' && params.ratingKey && metadata) {
      return {
        mediaId: String(params.ratingKey),
        seriesId: metadata.grandparentRatingKey ? String(metadata.grandparentRatingKey) : undefined,
      };
    }
    return null;
  }, [metadata, params.ratingKey, params.type, streamContentKey, streamSeriesRef?.baseId]);

  const [rememberedTracks, setRememberedTracks] = useState<RememberedTracks | null>(null);
  const [originalAudioLanguage, setOriginalAudioLanguage] = useState<string | null>(null);
  const userPickedAudioRef = useRef(false);
  const userPickedSubtitleRef = useRef(false);
  const plexRememberedTracksAppliedRef = useRef(false);

  useEffect(() => {
    if (!trackMemoryIds) {
      return;
    }
    if (!settings.rememberTrackSelections) {
      setRememberedTracks({});
      return;
    }
    let cancelled = false;
    loadRememberedTracks(trackMemoryIds).then((tracks) => {
      if (!cancelled) {
        setRememberedTracks(tracks);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [settings.rememberTrackSelections, trackMemoryIds]);

  useEffect(() => {
    if (!streamParams || settings.preferredAudioLanguage !== 'original') {
      return;
    }
    let cancelled = false;
    resolveOriginalLanguage(streamParams).then((language) => {
      if (!cancelled) {
        setOriginalAudioLanguage(language);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [settings.preferredAudioLanguage, streamParams]);

  // Addons cut off by the episode-switch deadline get a second chance once playback runs.
  useEffect(() => {
    if (!fileLoaded || !streamParams?.subtitlesIncomplete || !settings.stremioSubtitleAddonsEnabled) {
      return;
    }
    const identity = identityForStreamParams(streamParams);
    if (!identity) {
      return;
    }
    let cancelled = false;
    stremioService
      .getSubtitles(identity)
      .then((found) => {
        if (cancelled) return;
        setStreamExternalSubtitles((current) => {
          const known = new Set(current.map((subtitle) => subtitle.url));
          const added = found.filter((subtitle) => !known.has(subtitle.url));
          return added.length > 0 ? [...current, ...added] : current;
        });
      })
      .catch(() => {
        // The subtitles that already arrived stay available.
      });
    return () => {
      cancelled = true;
    };
  }, [fileLoaded, settings.stremioSubtitleAddonsEnabled, streamParams]);

  const rememberTrack = useCallback(
    (kind: 'audio' | 'subtitle', language: string | undefined) => {
      if (language && trackMemoryIds && settings.rememberTrackSelections) {
        saveTrackChoice(kind, trackMemoryIds, language === SUBTITLES_OFF ? language : normalizeLanguageCode(language));
      }
    },
    [settings.rememberTrackSelections, trackMemoryIds]
  );

  const handleUserAudioChange = useCallback(
    (trackId: number) => {
      userPickedAudioRef.current = true;
      const track = audioTracksRef.current.find((item) => item.id === trackId);
      rememberTrack('audio', track?.languageCode || track?.language);
      handleAudioTrackChange(trackId);
    },
    [handleAudioTrackChange, rememberTrack]
  );

  const handleUserTextChange = useCallback(
    (trackId: number) => {
      userPickedSubtitleRef.current = true;
      const track = textTracksRef.current.find((item) => item.id === trackId);
      rememberTrack('subtitle', trackId === -1 ? SUBTITLES_OFF : track?.languageCode || track?.language);
      handleTextTrackChange(trackId);
    },
    [handleTextTrackChange, rememberTrack]
  );

  useEffect(() => {
    if (!isStreamPlayback || !streamParams || rememberedTracks === null) {
      return;
    }

    const preferredAudio =
      settings.preferredAudioLanguage === 'original'
        ? originalAudioLanguage ?? undefined
        : settings.preferredAudioLanguage;
    const audioLanguage = rememberedTracks.audio ?? preferredAudio;
    const sourceSelectionKey = `${streamParams.contentKey}:${audioTracks.length}:${textTracks.length}:${streamExternalSubtitles.length}:${audioLanguage ?? ''}`;
    if (streamAutoSelectionAppliedRef.current === sourceSelectionKey) {
      return;
    }
    streamAutoSelectionAppliedRef.current = sourceSelectionKey;

    if (!userPickedAudioRef.current) {
      const audioTrack = findBestAudioTrack(audioTracks, audioLanguage);
      if (audioTrack !== null) {
        handleAudioTrackChange(audioTrack);
      }
    }

    if (userPickedSubtitleRef.current) {
      return;
    }
    if (rememberedTracks.subtitle === SUBTITLES_OFF) {
      clearExternalSubtitle();
      handleTextTrackChange(-1);
      return;
    }

    const subtitlePreference = findBestSubtitleTrack(textTracks, streamExternalSubtitles, {
      preferredSubtitleLanguage: rememberedTracks.subtitle ?? settings.preferredSubtitleLanguage,
      subtitleSourcePreference: settings.subtitleSourcePreference,
      enableSubtitleAutoSelect: rememberedTracks.subtitle ? true : settings.enableSubtitleAutoSelect,
    });

    if (subtitlePreference.type === 'internal' && subtitlePreference.internalTrackId !== undefined) {
      clearExternalSubtitle();
      handleTextTrackChange(subtitlePreference.internalTrackId);
    } else if (
      subtitlePreference.type === 'external' &&
      subtitlePreference.externalSubtitle &&
      subtitlePreference.externalSubtitle.id !== selectedExternalSubtitleId
    ) {
      handleTextTrackChange(-1);
      loadExternalSubtitle(subtitlePreference.externalSubtitle);
    }
  }, [
    audioTracks,
    clearExternalSubtitle,
    handleAudioTrackChange,
    handleTextTrackChange,
    isStreamPlayback,
    loadExternalSubtitle,
    originalAudioLanguage,
    rememberedTracks,
    selectedExternalSubtitleId,
    settings.enableSubtitleAutoSelect,
    settings.preferredAudioLanguage,
    settings.preferredSubtitleLanguage,
    settings.subtitleSourcePreference,
    streamExternalSubtitles,
    streamParams,
    textTracks,
  ]);

  // Plex direct play: apply the language remembered for this title or show. Transcodes
  // keep the server's selection, since changing tracks there restarts playback.
  useEffect(() => {
    if (
      params.type !== 'plex' ||
      !isDirectPlay ||
      !rememberedTracks ||
      plexRememberedTracksAppliedRef.current ||
      audioTracks.length === 0
    ) {
      return;
    }
    plexRememberedTracksAppliedRef.current = true;

    const indexForLanguage = (streams: Stream[], language: string) =>
      streams.findIndex((stream) => normalizeLanguageCode(stream.languageCode) === normalizeLanguageCode(language));

    if (rememberedTracks.audio && !userPickedAudioRef.current) {
      const index = indexForLanguage(plexAudioStreams, rememberedTracks.audio);
      const track = index >= 0 ? audioTracksRef.current[index] : undefined;
      if (track) {
        handleAudioTrackChange(track.id);
        setSelectedPlexAudio(plexAudioStreams[index].id);
      }
    }

    if (userPickedSubtitleRef.current) {
      return;
    }
    if (rememberedTracks.subtitle === SUBTITLES_OFF) {
      handleTextTrackChange(-1);
      setSelectedPlexSubtitle('0');
    } else if (rememberedTracks.subtitle) {
      const index = indexForLanguage(plexSubtitleStreams, rememberedTracks.subtitle);
      const track = index >= 0 ? textTracksRef.current[index] : undefined;
      if (track) {
        handleTextTrackChange(track.id);
        setSelectedPlexSubtitle(plexSubtitleStreams[index].id);
      }
    }
  }, [
    audioTracks,
    handleAudioTrackChange,
    handleTextTrackChange,
    isDirectPlay,
    params.type,
    plexAudioStreams,
    plexSubtitleStreams,
    rememberedTracks,
  ]);

  // Restart player with new settings (for transcode mode)
  // This is the most reliable way to change tracks/quality - Plex caches transcodes aggressively
  const restartPlayerWithSettings = async (options: {
    audioId?: string;
    subtitleId?: string;
    quality?: number | 'original';
  }) => {
    if (!params.ratingKey) {
      console.warn('[Player] Missing ratingKey for restart');
      return;
    }

    const { audioId, subtitleId, quality } = options;
    const newQuality = quality !== undefined ? quality : selectedQuality;

    console.log('[Player] ====== RESTARTING PLAYER ======');
    console.log('[Player] Audio ID:', audioId || 'default');
    console.log('[Player] Subtitle ID:', subtitleId || 'none');
    console.log('[Player] Quality:', newQuality);
    console.log('[Player] Media Index:', selectedMediaIndex);
    console.log('[Player] ================================');

    // Stop current transcode session before restart
    if (sessionId) {
      try {
        console.log('[Player] Stopping transcode session before restart:', sessionId);
        await stopTranscodeSession(sessionId);
      } catch (e) {
        console.warn('[Player] Failed to stop transcode:', e);
      }
    }

    // Also set stream selection on Plex server so it remembers the preference
    if (partId && (audioId || subtitleId)) {
      try {
        await setStreamSelection(partId, {
          audioStreamID: audioId,
          subtitleStreamID: subtitleId !== '0' ? subtitleId : undefined,
        });
        console.log('[Player] Stream selection saved to Plex server');
      } catch (e) {
        console.warn('[Player] Failed to set stream selection:', e);
      }
    }

    // Restart player by replacing the current screen with new params
    // Preserve mediaIndex for multi-version support
    nav.dispatch(
      StackActions.replace('Player', {
        type: params.type,
        ratingKey: params.ratingKey,
        initialAudioStreamId: audioId,
        initialSubtitleStreamId: subtitleId,
        initialQuality: newQuality, // Pass 'original' or number as-is
        mediaIndex: selectedMediaIndex, // Preserve selected media version
      })
    );
  };

  // Plex stream selection handlers
  const handlePlexAudioChange = async (streamId: string) => {
    console.log('[Player] Plex audio stream selected:', streamId);
    userPickedAudioRef.current = true;
    rememberTrack('audio', plexAudioStreams.find(s => s.id === streamId)?.languageCode);
    setSelectedPlexAudio(streamId);
    setShowSettingsSheet(false);

    if (isDirectPlay) {
      // Direct Play: Use in-player track switching (MPV)
      let availableAudioTracks = audioTracksRef.current.length ? audioTracksRef.current : audioTracks;

      // Find the Plex stream index - this is the most reliable way to match
      // since Plex streams and native player tracks are typically in the same order
      const plexStreamIndex = plexAudioStreams.findIndex(s => s.id === streamId);
      const plexStream = plexAudioStreams[plexStreamIndex];

      if (!plexStream || plexStreamIndex < 0) {
        console.log('[Player] Direct Play: Plex audio stream not found:', streamId);
        return;
      }

      console.log('[Player] Direct Play: Looking for audio track at index', plexStreamIndex, 'matching Plex stream:', {
        displayTitle: plexStream.displayTitle,
        languageCode: plexStream.languageCode,
        codec: plexStream.codec,
      });

      // PRIMARY: Use index-based matching (tracks are typically in the same order)
      let matchedTrack: AudioTrack | undefined;
      if (plexStreamIndex >= 0 && availableAudioTracks[plexStreamIndex]) {
        matchedTrack = availableAudioTracks[plexStreamIndex];
        console.log('[Player] Direct Play: Matched audio by index position:', plexStreamIndex);
      }

      // Fallback: try to match by exact name if index doesn't work
      if (!matchedTrack && plexStream.displayTitle) {
        matchedTrack = availableAudioTracks.find(t =>
          t.name?.toLowerCase().includes(plexStream.displayTitle?.toLowerCase() || '')
        );
        if (matchedTrack) {
          console.log('[Player] Direct Play: Matched audio by name');
        }
      }

      if (matchedTrack) {
        console.log('[Player] Direct Play: Matched audio track:', {
          id: matchedTrack.id,
          name: matchedTrack.name,
          languageCode: matchedTrack.languageCode,
        });
        handleAudioTrackChange(matchedTrack.id);
      } else {
        console.log('[Player] Direct Play: No matching audio track found, available:', availableAudioTracks.map((t, i) => ({ index: i, id: t.id, name: t.name })));
      }
    } else {
      // HLS Transcode: Restart player with new stream selection
      await restartPlayerWithSettings({
        audioId: streamId,
        subtitleId: selectedPlexSubtitle,
      });
    }
  };

  const handlePlexSubtitleChange = async (streamId: string) => {
    console.log('[Player] Plex subtitle stream selected:', streamId);
    userPickedSubtitleRef.current = true;
    rememberTrack('subtitle', streamId === '0' ? SUBTITLES_OFF : plexSubtitleStreams.find(s => s.id === streamId)?.languageCode);
    setSelectedPlexSubtitle(streamId);
    setShowSettingsSheet(false);

    if (isDirectPlay) {
      // Direct Play: Use in-player track switching (MPV)
      let availableTextTracks = textTracksRef.current.length ? textTracksRef.current : textTracks;

      if (streamId === '0') {
        // Disable subtitles
        console.log('[Player] Direct Play: Disabling subtitles');
        handleTextTrackChange(-1);
      } else {
        // Find the Plex stream index - this is the most reliable way to match
        // since Plex streams and native player tracks are in the same order
        const plexStreamIndex = plexSubtitleStreams.findIndex(s => s.id === streamId);
        const plexStream = plexSubtitleStreams[plexStreamIndex];

        if (!plexStream) {
          console.log('[Player] Direct Play: Plex subtitle stream not found:', streamId);
          return;
        }

        console.log('[Player] Direct Play: Looking for subtitle track at index', plexStreamIndex, 'matching Plex stream:', {
          displayTitle: plexStream.displayTitle,
          languageCode: plexStream.languageCode,
          language: plexStream.language,
        });

        // PRIMARY: Use index-based matching (tracks are in the same order)
        let matchedTrack: TextTrack | undefined;
        if (plexStreamIndex >= 0 && availableTextTracks[plexStreamIndex]) {
          matchedTrack = availableTextTracks[plexStreamIndex];
          console.log('[Player] Direct Play: Matched by index position:', plexStreamIndex);
        }

        // Fallback: try to match by exact name if index doesn't work
        if (!matchedTrack && plexStream.displayTitle) {
          matchedTrack = availableTextTracks.find(t =>
            t.name?.toLowerCase() === plexStream.displayTitle?.toLowerCase()
          );
          if (matchedTrack) {
            console.log('[Player] Direct Play: Matched by exact name');
          }
        }

        if (matchedTrack) {
          console.log('[Player] Direct Play: Matched subtitle track:', {
            id: matchedTrack.id,
            name: matchedTrack.name,
            languageCode: matchedTrack.languageCode,
            isImageSubtitle: (matchedTrack as any).isImageSubtitle,
          });
          handleTextTrackChange(matchedTrack.id);
        } else {
          console.log('[Player] Direct Play: No matching subtitle track found');
          console.log('[Player] Available tracks:', availableTextTracks.map((t, i) => ({ index: i, id: t.id, name: t.name })));
        }
      }
    } else {
      // HLS Transcode: Restart player with new stream selection
      await restartPlayerWithSettings({
        audioId: selectedPlexAudio || undefined,
        subtitleId: streamId,
      });
    }
  };

  // Quality change handler
  const handleQualityChange = async (quality: number | 'original') => {
    if (!params.ratingKey) return;

    console.log('[Player] ====== QUALITY CHANGE ======');
    console.log('[Player] Requested quality:', quality);
    console.log('[Player] Current quality:', selectedQuality);
    console.log('[Player] Current isDirectPlay:', isDirectPlay);
    console.log('[Player] ============================');

    setShowSettingsSheet(false);

    // Restart player with new quality setting
    await restartPlayerWithSettings({
      audioId: selectedPlexAudio || undefined,
      subtitleId: selectedPlexSubtitle,
      quality,
    });
  };

  const handleExternalSubtitleSelection = useCallback(
    async (subtitleId: string | null) => {
      if (!streamParams) {
        return;
      }

      userPickedSubtitleRef.current = true;
      if (!subtitleId) {
        rememberTrack('subtitle', SUBTITLES_OFF);
        clearExternalSubtitle();
        return;
      }

      const subtitle = streamExternalSubtitles.find((item) => item.id === subtitleId);
      if (!subtitle) {
        return;
      }

      rememberTrack('subtitle', subtitle.lang);
      handleTextTrackChange(-1);
      await loadExternalSubtitle(subtitle);
    },
    [clearExternalSubtitle, handleTextTrackChange, loadExternalSubtitle, rememberTrack, streamExternalSubtitles, streamParams]
  );

  const handleStreamSourceSelected = useCallback(
    async (stream: StremioPlayableStream) => {
      setActivePanel(null);
      if (!stream.playable || stream.url === streamParams?.uri) {
        return;
      }
      await replaceStreamSource(stream);
    },
    [replaceStreamSource, streamParams?.uri]
  );

  const handleEpisodeSelected = useCallback(
    (episode: BrowserEpisode) => {
      setActivePanel(null);
      if (episode.plexRatingKey) {
        playPlexEpisode(episode.plexRatingKey);
      } else if (isStreamPlayback) {
        nextEpisodeDismissedRef.current = true;
        clearNextEpisodeCountdown();
        playStreamEpisode(episode.season, episode.episode, episode.title);
      }
    },
    [clearNextEpisodeCountdown, isStreamPlayback, playPlexEpisode, playStreamEpisode]
  );

  const openPanel = useCallback((panel: 'sources' | 'episodes' | 'speed' | 'subtitles') => {
    setShowSettingsSheet(false);
    setActivePanel(panel);
  }, []);

  const handleSpeedSelected = useCallback((speed: number) => {
    setIsSpeedBoosted(false);
    setPlaybackRate(speed);
    setActivePanel(null);
  }, []);

  const episodeBrowserSource = useMemo<EpisodeBrowserSource | null>(() => {
    if (streamSeriesRef) {
      return { kind: 'stream', ref: streamSeriesRef, seasonEpisodes: streamSeasonEpisodes };
    }
    if (params.type === 'plex' && params.ratingKey && metadata?.type === 'episode') {
      return {
        kind: 'plex',
        showRatingKey: metadata.grandparentRatingKey ? String(metadata.grandparentRatingKey) : undefined,
        seasonRatingKey: metadata.parentRatingKey ? String(metadata.parentRatingKey) : undefined,
        season: metadata.parentIndex ?? 1,
        ratingKey: String(params.ratingKey),
      };
    }
    return null;
  }, [metadata, params.ratingKey, params.type, streamSeasonEpisodes, streamSeriesRef]);

  const currentMarker = markers.find(m =>
    m.type !== 'postcredits' && position >= m.startTimeOffset && position <= m.endTimeOffset
  );
  const skipMarkerLabels: Record<string, string> = {
    intro: 'Skip Intro',
    recap: 'Skip Recap',
    preview: 'Skip Preview',
    credits: 'Skip Credits',
  };
  // With auto-play off the Up Next card never appears, so credits keep their own button.
  const showSkipMarker =
    currentMarker && (currentMarker.type !== 'credits' || !nextEpisode || !settings.autoPlayNext);

  // Pan responder for draggable scrubber
  // PanResponder no longer used; Slider provides built-in seeking UX

  const formatTime = (ms: number) => {
    const totalSeconds = Math.floor(ms / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    if (hours > 0) {
      return `${hours}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  // Pinch gesture tracking for toggling aspect ratio (like Plezy)
  const isPinchingRef = useRef(false);

  const handleTouchStart = useCallback((e: any) => {
    const touchCount = e.nativeEvent.touches?.length || 0;
    if (touchCount >= 2) {
      isPinchingRef.current = true;
    }
  }, []);

  const handleTouchEnd = useCallback(async () => {
    if (isPinchingRef.current) {
      // Use the same method as the aspect ratio button
      try {
        const newMode = await mpvPlayerRef.current?.cycleAspectRatio();
        if (newMode !== undefined) {
          setAspectRatioMode(newMode);
          console.log('[Player] Pinch gesture - aspect ratio mode:', newMode);
        }
      } catch (e) {
        console.log('[Player] Pinch gesture cycleAspectRatio error:', e);
      }
      isPinchingRef.current = false;
    }
  }, []);

  // Hold anywhere on the video to play at 2x until released
  const beginSpeedBoost = useCallback(() => {
    if (!isPinchingRef.current && fileLoadedRef.current) {
      setIsSpeedBoosted(true);
    }
  }, []);

  const endSpeedBoost = useCallback(() => {
    setIsSpeedBoosted(false);
  }, []);

  const handleTouchMove = useCallback((e: any) => {
    const touchCount = e.nativeEvent.touches?.length || 0;
    if (touchCount >= 2 && !isPinchingRef.current) {
      isPinchingRef.current = true;
    }
  }, []);

  if (loading) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" color="#fff" />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.error}>
        <Text style={styles.errorText}>{error}</Text>
        {streamFailed && sourcesDestination ? (
          <TouchableOpacity
            onPress={() => openSourcesPicker(sourcesDestination)}
            style={[styles.errorButton, styles.errorButtonPrimary, { backgroundColor: theme.accent }]}
          >
            <Text style={[styles.errorButtonText, { color: theme.onAccent }]}>Choose Another Source</Text>
          </TouchableOpacity>
        ) : null}
        <TouchableOpacity onPress={() => nav.goBack()} style={styles.errorButton}>
          <Text style={styles.errorButtonText}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <StatusBar hidden />

          {/* Unified MPV Player (iOS + Android) */}
          {streamUrl ? (
            <MPVPlayerComponent
              ref={mpvPlayerRef}
              source={{ uri: streamUrl, headers: streamHeaders }}
              style={{ width: dimensions.width, height: dimensions.height }}
              paused={!isPlaying}
              volume={1.0}
              rate={isSpeedBoosted ? 2 : playbackRate}
              decoderMode="auto"
              onLoad={onPlayerLoad}
              onProgress={onPlayerProgress}
              onEnd={onPlayerEnd}
              onError={onPlayerError}
              onTracksChanged={onMpvTracksChanged}
              // Sent after load: native drops values set before mpv starts.
              subtitleSize={fileLoaded ? settings.subtitleFontSize : undefined}
              subtitleColor={fileLoaded ? settings.subtitleTextColor : undefined}
              subtitleBorderSize={fileLoaded ? settings.subtitleBorderSize : undefined}
              subtitlePosition={fileLoaded ? settings.subtitlePosition : undefined}
            />
          ) : null}

      <CustomSubtitles
        enabled={Boolean(selectedExternalSubtitleId)}
        text={currentExternalSubtitleText}
        controlsVisible={showControls}
        fontSize={settings.subtitleFontSize}
        color={settings.subtitleTextColor}
        borderSize={settings.subtitleBorderSize}
        position={settings.subtitlePosition}
      />

      {/* Background tap area to show/hide controls + pinch gesture detection */}
      <View style={styles.tapArea} pointerEvents="box-none">
        <Pressable
          style={StyleSheet.absoluteFill}
          onPress={resetControlsTimeout}
          onLongPress={beginSpeedBoost}
          onPressOut={endSpeedBoost}
          delayLongPress={400}
          onTouchStart={handleTouchStart}
          onTouchMove={handleTouchMove}
          onTouchEnd={handleTouchEnd}
        />
        {/* Controls overlay */}
        {showControls && (
          <>
            {/* Top gradient bar */}
            <LinearGradient
              colors={['rgba(0,0,0,0.7)', 'transparent']}
              style={styles.topGradient}
            >
              <View style={styles.topBar}>
                <TouchableOpacity onPress={() => nav.goBack()} style={styles.backButton}>
                  <Ionicons name="chevron-back" size={32} color="#fff" />
                </TouchableOpacity>
                {metadata && (
                  <View style={styles.titleContainer}>
                    <Text style={styles.title} numberOfLines={1}>
                      {metadata.grandparentTitle || metadata.title}
                    </Text>
                    {metadata.grandparentTitle && (
                      <Text style={styles.subtitle} numberOfLines={1}>
                        {metadata.title}
                      </Text>
                    )}
                  </View>
                )}
                <View style={styles.topIcons}>
                  {Platform.OS === 'ios' && (
                    <TouchableOpacity
                      style={styles.iconButton}
                      onPress={() => {
                        mpvPlayerRef.current?.showAirPlayPicker();
                      }}
                    >
                      <Ionicons name="tv-outline" size={24} color="#fff" />
                    </TouchableOpacity>
                  )}
                  {/* Aspect ratio button */}
                  <TouchableOpacity
                    style={styles.iconButton}
                    onPress={cycleAspectRatio}
                  >
                    <Image source={getAspectRatioIcon()} style={styles.aspectRatioIcon} />
                  </TouchableOpacity>
                  {/* Rotation lock button (matching Plezy) */}
                  <TouchableOpacity
                    style={styles.iconButton}
                    onPress={toggleRotationLock}
                  >
                    <Image
                      source={isRotationLocked ? rotationLockIcons.locked : rotationLockIcons.unlocked}
                      style={styles.aspectRatioIcon}
                    />
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={styles.iconButton}
                    onPress={() => {
                      setActivePanel(null);
                      setShowSettingsSheet(true);
                    }}
                  >
                    <Ionicons name="settings-outline" size={24} color="#fff" />
                  </TouchableOpacity>
                </View>
              </View>
            </LinearGradient>

            {/* Center play controls */}
            <View style={styles.centerControls}>
              <TouchableOpacity
                onPress={() => skip(-settings.seekTimeSmall)}
                onLongPress={() => skip(-settings.seekTimeLarge)}
                style={styles.skipButton}
                accessibilityLabel={`Back ${settings.seekTimeSmall} seconds`}
              >
                <ReplayIcon seconds={settings.seekTimeSmall} size={48} color="#fff" />
              </TouchableOpacity>

              <TouchableOpacity
                onPress={togglePlayPause}
                style={styles.playPauseButton}
              >
                <Ionicons
                  name={isPlaying ? 'pause' : 'play'}
                  size={50}
                  color="#fff"
                />
              </TouchableOpacity>

              <TouchableOpacity
                onPress={() => skip(settings.seekTimeSmall)}
                onLongPress={() => skip(settings.seekTimeLarge)}
                style={styles.skipButton}
                accessibilityLabel={`Forward ${settings.seekTimeSmall} seconds`}
              >
                <ForwardIcon seconds={settings.seekTimeSmall} size={48} color="#fff" />
              </TouchableOpacity>
            </View>

            {/* Bottom gradient controls */}
            <LinearGradient
              colors={['transparent', 'rgba(0,0,0,0.8)']}
              style={styles.bottomGradient}
              pointerEvents="box-none"
            >
              {/* Progress bar */}
              <View style={styles.progressSection} pointerEvents="box-none">
                <Slider
                  style={{ width: '100%', height: 28 }}
                  minimumValue={0}
                  maximumValue={Math.max(1, duration)}
                  value={Math.max(0, Math.min(duration, position))}
                  minimumTrackTintColor="#fff"
                  maximumTrackTintColor="rgba(255,255,255,0.3)"
                  thumbTintColor="#fff"
                  accessibilityLabel="Seek"
                  onSlidingStart={() => setIsScrubbing(true)}
                  onValueChange={(val: number) => setPosition(val)}
                  onSlidingComplete={(val: number) => {
                    const targetMs = Math.max(0, Math.min(duration, val));
                    seekPlayer(targetMs);
                    setIsScrubbing(false);
                  }}
                />
                <SeekBarMarks markers={markers} durationMs={duration} color={theme.accentBright} />
                <View style={styles.timeContainer} pointerEvents="none">
                  <Text style={styles.timeText}>{formatTime(position)}</Text>
                  <Text style={styles.timeText}>{formatTime(duration - position)}</Text>
                </View>
              </View>

              {/* Bottom action buttons */}
              <View style={styles.bottomActions}>
                <TouchableOpacity onPress={restart} style={styles.actionButton}>
                  <Ionicons name="play-skip-back" size={18} color="#fff" />
                  <Text style={styles.actionText}>RESTART</Text>
                </TouchableOpacity>

                {metadata?.type === 'episode' && (
                  <TouchableOpacity onPress={playNext} style={[styles.actionButton, !nextEpisode && styles.actionButtonDisabled]}>
                    <Ionicons name="play-skip-forward" size={18} color={nextEpisode ? "#fff" : "#666"} />
                    <Text style={[styles.actionText, !nextEpisode && styles.actionTextDisabled]}>PLAY NEXT</Text>
                  </TouchableOpacity>
                )}

                {episodeBrowserSource && (
                  <TouchableOpacity onPress={() => openPanel('episodes')} style={styles.actionButton}>
                    <Ionicons name="list" size={18} color="#fff" />
                    <Text style={styles.actionText}>EPISODES</Text>
                  </TouchableOpacity>
                )}

                {isStreamPlayback && (
                  <TouchableOpacity onPress={() => openPanel('sources')} style={styles.actionButton}>
                    <Ionicons name="layers-outline" size={18} color="#fff" />
                    <Text style={styles.actionText}>SOURCES</Text>
                  </TouchableOpacity>
                )}

                <TouchableOpacity onPress={() => openPanel('speed')} style={styles.actionButton}>
                  <Ionicons name="speedometer-outline" size={18} color="#fff" />
                  <Text style={styles.actionText}>{playbackRate === 1 ? 'SPEED' : formatSpeed(playbackRate)}</Text>
                </TouchableOpacity>

                <TouchableOpacity onPress={() => openPanel('subtitles')} style={styles.actionButton}>
                  <Ionicons name="text-outline" size={18} color="#fff" />
                  <Text style={styles.actionText}>SUBTITLE STYLE</Text>
                </TouchableOpacity>
              </View>
            </LinearGradient>
          </>
        )}

        {/* Skip button (credits are handled by the Next Episode overlay when it is showing) */}
        {currentMarker && showSkipMarker && (
          <View style={styles.skipMarkerContainer}>
            <TouchableOpacity
              onPress={() => skipMarker(currentMarker)}
              style={styles.skipMarkerButton}
            >
              <Text style={styles.skipMarkerText}>
                {skipMarkerLabels[currentMarker.type] ?? 'Skip'}
                {autoSkipCountdown !== null && autoSkipCountdown > 0 && ` (${autoSkipCountdown})`}
              </Text>
              <Ionicons name="play-forward" size={16} color="#000" />
            </TouchableOpacity>
          </View>
        )}

        {/* Next episode overlay (Plezy style) */}
        {nextEpisodeCountdown !== null && nextEpisode && (
          <View style={styles.nextEpisodeContainer}>
            <View style={styles.nextEpisodeCard}>
              {/* Episode info */}
              <View style={styles.nextEpisodeHeader}>
                <Text style={styles.nextEpisodeLabel}>Up Next</Text>
                <Text style={styles.nextEpisodeEpLabel}>{nextEpisode.episodeLabel}</Text>
              </View>

              {/* Thumbnail */}
              <View style={styles.nextEpisodeThumbnail}>
                {nextEpisode.thumb ? (
                  <FastImage
                    source={{
                      uri: isStreamPlayback ? nextEpisode.thumb : getPlayerImageUrl(nextEpisode.thumb, 300),
                      priority: FastImage.priority.high,
                      cache: FastImage.cacheControl.immutable,
                    }}
                    style={{ width: '100%', height: '100%', borderRadius: 8 }}
                    resizeMode={FastImage.resizeMode.cover}
                  />
                ) : (
                  <Ionicons name="play-circle" size={40} color="#fff" />
                )}
              </View>

              {/* Title */}
              <Text style={styles.nextEpisodeTitle} numberOfLines={2}>
                {nextEpisode.title}
              </Text>

              {/* Buttons */}
              <View style={styles.nextEpisodeButtons}>
                <TouchableOpacity
                  onPress={() => {
                    // Cancel countdown; it must not start again unless the user seeks back
                    nextEpisodeDismissedRef.current = true;
                    clearNextEpisodeCountdown();
                  }}
                  style={styles.nextEpisodeCancelButton}
                >
                  <Text style={styles.nextEpisodeCancelText}>Cancel</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  onPress={playNext}
                  style={styles.nextEpisodePlayButton}
                >
                  <Text style={styles.nextEpisodePlayText}>
                    Play Now {nextEpisodeCountdown > 0 ? `(${nextEpisodeCountdown})` : ''}
                  </Text>
                </TouchableOpacity>
              </View>
            </View>
          </View>
        )}

        {isSpeedBoosted && (
          <View style={styles.speedBoostPill} pointerEvents="none">
            <Ionicons name="play-forward" size={14} color="#fff" />
            <Text style={styles.speedBoostText}>2x</Text>
          </View>
        )}

        {resolvingEpisodeLabel ? (
          <StreamStatusPill message={`Finding a source for ${resolvingEpisodeLabel}…`} onCancel={cancelEpisodeLookup} />
        ) : recoveryStatusMessage ? (
          <StreamStatusPill message={recoveryStatusMessage} />
        ) : null}

        {/* Buffering indicator */}
        {buffering && (
          <View style={styles.bufferingContainer}>
          <ActivityIndicator size="large" color="#fff" />
        </View>
      )}
      </View>

      {activePanel === 'sources' && (
        <SourcesPanel
          sources={streamSources}
          currentSourceId={currentStream ? buildStreamSourceId(currentStream) : null}
          isRefreshing={isRefreshingSources}
          sourceId={buildStreamSourceId}
          onAppear={refreshStreamSourcesIfNeeded}
          onRefresh={refreshStreamSources}
          onSelect={handleStreamSourceSelected}
          onClose={() => setActivePanel(null)}
        />
      )}
      {activePanel === 'episodes' && episodeBrowserSource && (
        <EpisodesPanel
          source={episodeBrowserSource}
          onSelect={handleEpisodeSelected}
          onClose={() => setActivePanel(null)}
        />
      )}
      {activePanel === 'speed' && (
        <SpeedPanel speed={playbackRate} onSelect={handleSpeedSelected} onClose={() => setActivePanel(null)} />
      )}
      {activePanel === 'subtitles' && (
        <SubtitlePanel
          externalActive={Boolean(selectedExternalSubtitleId)}
          cues={externalSubtitleCues}
          currentTimeMs={externalSubtitleTimeMs}
          delayMs={externalSubtitleDelayMs}
          onDelayChange={setExternalSubtitleDelayMs}
          onClose={() => setActivePanel(null)}
        />
      )}

      {/* Player Settings Sheet */}
      <PlayerSettingsSheet
        visible={showSettingsSheet}
        onClose={() => setShowSettingsSheet(false)}
        // Plex streams (with proper names from metadata)
        audioStreams={plexAudioStreams}
        subtitleStreams={plexSubtitleStreams}
        selectedAudio={selectedPlexAudio}
        selectedSubtitle={selectedPlexSubtitle}
        onAudioChange={handlePlexAudioChange}
        onSubtitleChange={handlePlexSubtitleChange}
        // MPV tracks - as fallback if Plex streams not available
        ksAudioTracks={plexAudioStreams.length === 0 ? audioTracks : []}
        ksTextTracks={plexSubtitleStreams.length === 0 ? textTracks : []}
        selectedKsAudioTrack={selectedAudioTrack}
        selectedKsTextTrack={selectedTextTrack}
        onKsAudioChange={handleUserAudioChange}
        onKsTextTrack={handleUserTextChange}
        externalSubtitles={streamExternalSubtitles}
        selectedExternalSubtitleId={selectedExternalSubtitleId}
        onExternalSubtitleSelect={handleExternalSubtitleSelection}
        // Quality options
        qualityOptions={qualityOptions}
        selectedQuality={selectedQuality}
        onQualityChange={handleQualityChange}
        // Playback info (uses selectedMediaIndex for multi-version support + live performance stats)
        playbackInfo={{
          isDirectPlay,
          videoCodec: performanceStats.videoCodec || metadata?.Media?.[selectedMediaIndex]?.videoCodec,
          videoResolution: performanceStats.videoWidth && performanceStats.videoHeight
            ? `${performanceStats.videoWidth}x${performanceStats.videoHeight}`
            : metadata?.Media?.[selectedMediaIndex]?.videoResolution,
          videoBitrate: performanceStats.videoBitrate || (selectedQuality === 'original' ? metadata?.Media?.[selectedMediaIndex]?.bitrate : selectedQuality),
          audioCodec: performanceStats.audioCodec || metadata?.Media?.[selectedMediaIndex]?.audioCodec,
          audioChannels: performanceStats.audioChannels || metadata?.Media?.[selectedMediaIndex]?.audioChannels?.toString() + ' channels',
          container: metadata?.Media?.[selectedMediaIndex]?.container,
          playerBackend: playerBackend || 'MPV',
          // Extended performance stats from MPV
          decoder: performanceStats.hwdecCurrent
            ? (performanceStats.hwdecCurrent === 'no' || performanceStats.hwdecCurrent === '' ? 'Software' : performanceStats.hwdecCurrent)
            : undefined,
          containerFps: performanceStats.containerFps,
          actualFps: performanceStats.actualFps,
          displayFps: performanceStats.displayFps,
          aspectName: performanceStats.aspectName,
          rotate: performanceStats.rotate,
          pixelFormat: performanceStats.pixelformat,
          hwPixelFormat: performanceStats.hwPixelformat,
          colorMatrix: performanceStats.colormatrix,
          colorPrimaries: performanceStats.primaries,
          colorTransfer: performanceStats.gamma,
          // HDR metadata
          maxLuma: performanceStats.maxLuma,
          minLuma: performanceStats.minLuma,
          maxCll: performanceStats.maxCll,
          maxFall: performanceStats.maxFall,
          // Audio extended
          audioSampleRate: performanceStats.audioSamplerate,
          audioBitrate: performanceStats.audioBitrate,
          // Performance
          avSync: performanceStats.avsyncChange,
          droppedFrames: (performanceStats.frameDropCount ?? 0) + (performanceStats.decoderFrameDropCount ?? 0),
          // Buffer
          cacheDuration: performanceStats.cacheDuration,
          cacheUsed: performanceStats.cacheUsed,
          cacheSpeed: performanceStats.cacheSpeed,
          // HDR info - prefer native detection from MPV, fallback to Plex metadata
          hdrType: (() => {
            // First check MPV's gamma (transfer function) for HDR detection
            const gamma = performanceStats.gamma?.toLowerCase() || '';
            if (gamma.includes('pq') || gamma.includes('smpte2084')) return 'HDR10';
            if (gamma.includes('hlg')) return 'HLG';
            if (performanceStats.maxLuma) return 'HDR10'; // Has HDR metadata
            // Fallback: detect HDR from Plex video stream metadata
            const streams = metadata?.Media?.[selectedMediaIndex]?.Part?.[0]?.Stream || [];
            const videoStream = streams.find((s: any) => s.streamType === 1);
            if (!videoStream) return null;
            // Check for Dolby Vision
            if (/dolby.?vision|dovi/i.test(String(videoStream?.displayTitle || ''))) return 'Dolby Vision';
            // Check for HDR10+ via colorTrc
            if (/smpte2094/i.test(String(videoStream?.colorTrc || ''))) return 'HDR10+';
            // Check for HDR10 via colorTrc (PQ/SMPTE2084)
            if (/smpte2084|pq/i.test(String(videoStream?.colorTrc || ''))) return 'HDR10';
            // Check for HLG
            if (/hlg/i.test(String(videoStream?.colorTrc || ''))) return 'HLG';
            // Check bit depth
            if (videoStream?.bitDepth >= 10) return 'HDR10';
            return null;
          })() as PlaybackInfo['hdrType'],
          colorSpace: performanceStats.colormatrix || colorSpace || (() => {
            // Fallback: detect color space from Plex metadata
            const streams = metadata?.Media?.[selectedMediaIndex]?.Part?.[0]?.Stream || [];
            const videoStream = streams.find((s: any) => s.streamType === 1);
            if (!videoStream) return undefined;
            // Check for BT.2020 color primaries
            if (/bt2020|rec2020/i.test(String(videoStream?.colorPrimaries || ''))) return 'BT.2020';
            if (/bt709|rec709/i.test(String(videoStream?.colorPrimaries || ''))) return 'BT.709';
            return videoStream?.colorPrimaries || undefined;
          })(),
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  loading: {
    flex: 1,
    backgroundColor: '#000',
    alignItems: 'center',
    justifyContent: 'center',
  },
  error: {
    flex: 1,
    backgroundColor: '#000',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 20,
  },
  errorText: {
    color: '#fff',
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 20,
  },
  errorButtonPrimary: {
    marginBottom: 12,
  },
  errorButton: {
    backgroundColor: 'rgba(255,255,255,0.14)',
    paddingHorizontal: 30,
    paddingVertical: 12,
    borderRadius: 4,
  },
  errorButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
  },
  tapArea: {
    ...StyleSheet.absoluteFill,
  },
  topGradient: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    paddingTop: 50,
    paddingBottom: 20,
  },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
  },
  backButton: {
    padding: 4,
  },
  titleContainer: {
    flex: 1,
    marginLeft: 12,
  },
  title: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
  },
  subtitle: {
    color: '#ccc',
    fontSize: 14,
    marginTop: 2,
  },
  topIcons: {
    flexDirection: 'row',
    gap: 16,
  },
  iconButton: {
    padding: 4,
  },
  iconButtonActive: {
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    borderRadius: 4,
  },
  aspectRatioIcon: {
    width: 24,
    height: 24,
    tintColor: '#fff',
  },
  centerControls: {
    position: 'absolute',
    top: '50%',
    left: 0,
    right: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 60,
    transform: [{ translateY: -40 }],
  },
  skipButton: {
    position: 'relative',
    alignItems: 'center',
  },
  skipLabel: {
    position: 'absolute',
    bottom: -2,
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  playPauseButton: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: 'rgba(255, 255, 255, 0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  bottomGradient: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    paddingBottom: 30,
    paddingHorizontal: 16,
  },
  progressSection: {
    marginBottom: 16,
  },
  // legacy styles (unused now that we use Slider) kept minimal in case of fallback
  timeContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 8,
  },
  timeText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
  },
  bottomActions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: 8,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  actionText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  actionButtonDisabled: {
    opacity: 0.5,
  },
  actionTextDisabled: {
    color: '#666',
  },
  // Skip Intro/Credits button (Plezy style)
  skipMarkerContainer: {
    position: 'absolute',
    bottom: 140,
    right: 20,
  },
  skipMarkerButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.9)',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 8,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 5,
  },
  skipMarkerText: {
    color: '#000',
    fontSize: 16,
    fontWeight: '600',
  },

  // Next Episode overlay (Plezy style - vertical card)
  nextEpisodeContainer: {
    position: 'absolute',
    bottom: 100,
    right: 20,
    zIndex: 5,
  },
  nextEpisodeCard: {
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    borderRadius: 12,
    overflow: 'hidden',
    width: 200,
    padding: 16,
  },
  nextEpisodeHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  nextEpisodeLabel: {
    color: 'rgba(255, 255, 255, 0.7)',
    fontSize: 12,
    fontWeight: '500',
  },
  nextEpisodeEpLabel: {
    color: 'rgba(255, 255, 255, 0.7)',
    fontSize: 12,
    fontWeight: '500',
  },
  nextEpisodeThumbnail: {
    width: '100%',
    height: 100,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 12,
  },
  nextEpisodeTitle: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 16,
    lineHeight: 20,
  },
  nextEpisodeButtons: {
    flexDirection: 'row',
    gap: 8,
  },
  nextEpisodeCancelButton: {
    flex: 1,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    paddingVertical: 10,
    borderRadius: 8,
    alignItems: 'center',
  },
  nextEpisodeCancelText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  nextEpisodePlayButton: {
    flex: 1,
    backgroundColor: '#fff',
    paddingVertical: 10,
    borderRadius: 8,
    alignItems: 'center',
  },
  nextEpisodePlayText: {
    color: '#000',
    fontSize: 14,
    fontWeight: '600',
  },
  speedBoostPill: {
    position: 'absolute',
    top: 24,
    alignSelf: 'center',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 14,
    backgroundColor: 'rgba(0,0,0,0.7)',
  },
  speedBoostText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  bufferingContainer: {
    ...StyleSheet.absoluteFill,
    alignItems: 'center',
    justifyContent: 'center',
    pointerEvents: 'none',
  },
});
