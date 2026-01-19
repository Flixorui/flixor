import React, { useEffect, useState, useRef, useCallback } from 'react';
import { View, Text, TouchableOpacity, ActivityIndicator, StyleSheet, StatusBar, Dimensions, Platform, NativeModules } from 'react-native';
import { Video, ResizeMode, AVPlaybackStatus, Audio } from 'expo-av';
import FastImage from '@d11/react-native-fast-image';
import Slider from '@react-native-community/slider';
import { useNavigation, StackActions } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import * as ScreenOrientation from 'expo-screen-orientation';
import { LinearGradient } from 'expo-linear-gradient';
import { KSPlayerComponent, KSPlayerRef, AudioTrack, TextTrack, MPVPlayerComponent, MPVPlayerRef, MPVAudioTrack, MPVSubtitleTrack } from '../components/player';
import PlaybackStatsHUD from '../components/player/PlaybackStatsHUD';
import { Stream, PlaybackInfo } from '../components/PlayerSettingsSheet';
import { useFlixor } from '../core/FlixorContext';
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
} from '../core/PlayerData';
import { Replay10Icon, Forward10Icon } from '../components/icons/SkipIcons';
import { TopBarStore } from '../components/TopBarStore';
import PlayerSettingsSheet from '../components/PlayerSettingsSheet';
import { useAppSettings } from '../hooks/useAppSettings';

type PlayerParams = {
  type: 'plex' | 'tmdb';
  ratingKey?: string;
  id?: string;
  // For transcode track switching - player restarts with these
  initialAudioStreamId?: string;
  initialSubtitleStreamId?: string;
  initialQuality?: number | 'original';
  resumePosition?: number; // Resume position in ms
  mediaIndex?: number; // Index of Media array to play (for multi-version support)
};

type RouteParams = {
  route?: {
    params?: PlayerParams;
  };
};

export default function Player({ route }: RouteParams) {
  const params: Partial<PlayerParams> = route?.params || {};
  const nav = useNavigation();
  const playerRef = useRef<KSPlayerRef>(null);
  const mpvPlayerRef = useRef<MPVPlayerRef>(null); // Android MPV player
  const videoRef = useRef<Video>(null); // expo-av fallback (unused with MPV)
  const { isLoading: flixorLoading, isConnected } = useFlixor();
  const { settings } = useAppSettings();
  const KSPlayerModule = Platform.OS === 'ios' ? NativeModules.KSPlayerModule : null;

  // Multi-version support: which Media to use
  const selectedMediaIndex = params.mediaIndex ?? 0;

  // Track selection state (iOS KSPlayer only)
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
  const [isFullscreen, setIsFullscreen] = useState(false);
  const isFullscreenRef = useRef(false);

  const [loading, setLoading] = useState(true);
  const [streamUrl, setStreamUrl] = useState<string>('');
  const [metadata, setMetadata] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  // Playback state
  const [isPlaying, setIsPlaying] = useState(true);
  const [duration, setDuration] = useState(0);
  const [position, setPosition] = useState(0);
  const [buffering, setBuffering] = useState(false);
  const [showControls, setShowControls] = useState(true);

  // Markers for skip intro/credits
  const [markers, setMarkers] = useState<Array<{ id?: number | string; type: string; startTimeOffset: number; endTimeOffset: number }>>([]);

  // Auto-skip state
  const [autoSkipCountdown, setAutoSkipCountdown] = useState<number | null>(null);
  const autoSkipTriggeredMarkersRef = useRef<Set<string>>(new Set());
  const autoSkipTimerRef = useRef<NodeJS.Timeout | null>(null);

  // Next episode for auto-play
  const [nextEpisode, setNextEpisode] = useState<NextEpisodeInfo | null>(null);
  const [nextEpisodeCountdown, setNextEpisodeCountdown] = useState<number | null>(null);

  // Session ID for transcode management
  const [sessionId, setSessionId] = useState<string>('');

  // Part ID for stream selection
  const [partId, setPartId] = useState<string>('');

  // Direct play mode - allows in-player track switching
  const [isDirectPlay, setIsDirectPlay] = useState(false);

  // Player backend (KSMEPlayer for MKV, KSAVPlayer for HLS)
  const [playerBackend, setPlayerBackend] = useState<string>('');

  // HDR info from native player or Plex metadata
  const [hdrType, setHdrType] = useState<string | null>(null);
  const [colorSpace, setColorSpace] = useState<string | undefined>(undefined);

  // Quality selection state
  const [selectedQuality, setSelectedQuality] = useState<number | 'original'>('original');
  const [qualityOptions, setQualityOptions] = useState<Array<{ label: string; value: number | 'original' }>>([]);

  // Track screen dimensions for rotation
  const [dimensions, setDimensions] = useState({
    width: Dimensions.get('window').width,
    height: Dimensions.get('window').height,
  });

  const progressInterval = useRef<NodeJS.Timeout | null>(null);
  const controlsTimeout = useRef<NodeJS.Timeout | null>(null);

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

  // Track selection refs (to prevent duplicate calls and infinite loops)
  const lastAudioTrackRef = useRef<number | null>(null);
  const lastTextTrackRef = useRef<number>(-1);

  // Scrubbing state
  const [isScrubbing, setIsScrubbing] = useState(false);
  // Legacy pan scrub state removed (using Slider now)

  // Developer stats HUD (long press on play button to toggle)
  const [showStatsHUD, setShowStatsHUD] = useState(false);

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

  // Define cleanup and playNext callbacks early so they can be used in useEffects
  const cleanup = useCallback(async () => {
    const { sessionId: sid } = cleanupInfoRef.current;

    // Stop Trakt scrobble
    if (traktScrobbleStarted.current && metadataRef.current) {
      const progress = durationRef.current
        ? Math.round((positionRef.current / durationRef.current) * 100)
        : 0;
      stopTraktScrobble(metadataRef.current, progress);
      lastScrobbleState.current = 'stopped';
      traktScrobbleStarted.current = false;
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
      if (Platform.OS === 'ios') {
        playerRef.current?.setPaused(true);
      } else {
        await videoRef.current?.stopAsync?.();
      }
    } catch {}
  }, []);

  const playNext = useCallback(async () => {
    if (nextEpisode) {
      // Cleanup current player before navigating
      isReplacingRef.current = true;
      await cleanup();
      // Replace current route using stack action for compatibility
      // Preserve mediaIndex to honor user's version choice for the watch session
      // @ts-ignore - navigation may not expose replace; use dispatch
      nav.dispatch(StackActions.replace('Player', {
        type: 'plex',
        ratingKey: nextEpisode.ratingKey,
        mediaIndex: selectedMediaIndex, // Keep same version for next episode
      }));
    }
  }, [nextEpisode, cleanup, nav, selectedMediaIndex]);

  useEffect(() => {
    // Hide TopBar and TabBar when Player is shown
    TopBarStore.setVisible(false);
    TopBarStore.setTabBarVisible(false);

    if (flixorLoading || !isConnected) return;

    (async () => {
      // Configure audio session
      try {
        await Audio.setAudioModeAsync({
          playsInSilentModeIOS: true,
          staysActiveInBackground: true,
          shouldDuckAndroid: true,
        });
      } catch (e) {
        console.warn('[Player] Failed to set audio mode:', e);
      }

      // Enable landscape orientation
      try {
        await ScreenOrientation.unlockAsync();
      } catch (e) {
        console.warn('[Player] Failed to unlock orientation:', e);
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

            // iOS with KSPlayer: Try Direct Play first (allows in-player track switching)
            // But fall back to HLS transcode for high-bandwidth audio codecs that cause choppy playback
            // Android with expo-av: Use HLS transcode (limited codec support)
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
      // Restore TopBar and TabBar when Player is closed
      TopBarStore.setVisible(true);
      TopBarStore.setTabBarVisible(true);

      // Cleanup
      (async () => {
        const { sessionId: sid } = cleanupInfoRef.current;

        // Stop Trakt scrobble
        if (traktScrobbleStarted.current && metadataRef.current) {
          const progress = durationRef.current
            ? Math.round((positionRef.current / durationRef.current) * 100)
            : 0;
          stopTraktScrobble(metadataRef.current, progress);
          lastScrobbleState.current = 'stopped';
        }

        if (sid) {
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
          try {
            await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
          } catch (e) {}
          isFullscreenRef.current = false;
          setIsFullscreen(false);

          try {
            await Audio.setAudioModeAsync({
              playsInSilentModeIOS: false,
              staysActiveInBackground: false,
              shouldDuckAndroid: false,
            });
          } catch (e) {}
        }
      })();

      if (progressInterval.current) clearInterval(progressInterval.current);
      if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    };
  }, [flixorLoading, isConnected]);

  // Update progress to Plex - use refs to avoid recreating interval on every position change
  const isPlayingRef = useRef(true); // Start as playing

  useEffect(() => {
    if (!params.ratingKey || !isConnected) return;

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
  }, [params.ratingKey, isConnected]);

  // Cleanup on navigation
  useEffect(() => {
    const cleanup = async () => {
      const { sessionId: sid, ratingKey: rk } = cleanupInfoRef.current;

      // Stop Trakt scrobble
      if (traktScrobbleStarted.current && metadataRef.current) {
        const progress = durationRef.current
          ? Math.round((positionRef.current / durationRef.current) * 100)
          : 0;
        stopTraktScrobble(metadataRef.current, progress);
        lastScrobbleState.current = 'stopped';
      }

      // Send stopped timeline update with actual position
      if (rk) {
        try {
          console.log(`[Player] Sending stopped timeline: pos=${Math.floor(positionRef.current)}ms, dur=${Math.floor(durationRef.current)}ms`);
          await updatePlaybackTimeline(rk, 'stopped', Math.floor(positionRef.current), Math.floor(durationRef.current));
        } catch (e) {}
      }

      // Stop transcode session
      if (sid) {
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
        if (isFullscreenRef.current) {
          await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE);
        } else {
          await ScreenOrientation.unlockAsync();
        }
        await Audio.setAudioModeAsync({ playsInSilentModeIOS: true, staysActiveInBackground: true, shouldDuckAndroid: true });
        // If we just replaced into this screen, ensure playback starts and orientation is landscape
        if (isReplacingRef.current) {
          isReplacingRef.current = false;
          try {
            if (isFullscreenRef.current) {
              await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE);
            } else {
              await ScreenOrientation.unlockAsync();
            }
          } catch {}
          try {
            if (Platform.OS === 'ios') {
              playerRef.current?.setPaused(false);
            } else {
              await videoRef.current?.playAsync?.();
            }
          } catch {}
        }
      } catch {}
    });

    const blurSub = nav.addListener('blur', async () => {
      try {
        if (Platform.OS === 'ios') {
          playerRef.current?.setPaused(true);
        } else {
          await videoRef.current?.pauseAsync?.();
        }
      } catch {}
    });

    return () => { unsubscribe(); focusSub(); blurSub(); };
  }, [nav, params.ratingKey]);

  // Auto-hide controls
  const resetControlsTimeout = () => {
    if (controlsTimeout.current) clearTimeout(controlsTimeout.current);
    setShowControls(true);
    controlsTimeout.current = setTimeout(() => {
      setShowControls(false);
    }, 4000);
  };

  const toggleFullscreen = async () => {
    try {
      if (isFullscreen) {
        await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP);
        setIsFullscreen(false);
        isFullscreenRef.current = false;
      } else {
        await ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE);
        setIsFullscreen(true);
        isFullscreenRef.current = true;
      }
    } catch (e) {
      console.warn('[Player] Failed to toggle fullscreen:', e);
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

  // Refs for countdown/end handling to prevent infinite loops
  const nextEpisodeCountdownStartedRef = useRef(false);
  const nextEpisodeCountdownTimerRef = useRef<NodeJS.Timeout | null>(null);
  const movieEndTriggeredRef = useRef(false);

  // Next episode countdown logic - trigger 5-second countdown when credits start (or fallback)
  useEffect(() => {
    if (metadata?.type !== 'episode' || !nextEpisode || !duration) {
      // Reset countdown state
      if (nextEpisodeCountdownStartedRef.current) {
        nextEpisodeCountdownStartedRef.current = false;
        if (nextEpisodeCountdownTimerRef.current) {
          clearInterval(nextEpisodeCountdownTimerRef.current);
          nextEpisodeCountdownTimerRef.current = null;
        }
        setNextEpisodeCountdown(null);
      }
      return;
    }

    const creditsMarker = markers.find(m => m.type === 'credits');
    const fallbackSeconds = settings.creditsCountdownFallback; // User setting: seconds before end if no credits marker
    const bufferSeconds = 3; // Show overlay 3 seconds before trigger point

    let triggerStart: number;
    if (creditsMarker) {
      // Use credits marker start time (minus buffer)
      triggerStart = Math.max(0, creditsMarker.startTimeOffset / 1000 - bufferSeconds);
    } else {
      // Fallback: X seconds before end
      triggerStart = Math.max(0, duration / 1000 - fallbackSeconds);
    }

    const currentPositionSec = position / 1000;

    // Check if we've reached the trigger point
    if (currentPositionSec >= triggerStart && !nextEpisodeCountdownStartedRef.current) {
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

    // Cleanup on unmount or when seeked back
    return () => {
      // Don't clear timer on every position update - only on actual cleanup
    };
  }, [metadata, nextEpisode, duration, position, markers, settings.creditsCountdownFallback]);

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
      position >= m.startTimeOffset && position <= m.endTimeOffset
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
      (currentMarker.type === 'credits' && settings.skipCreditsAutomatically);

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
  }, [position, markers, autoSkipCountdown, settings.skipIntroAutomatically, settings.skipCreditsAutomatically, settings.autoSkipDelay]);

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
    const creditsStart = creditsMarker ? (creditsMarker.startTimeOffset / 1000) : Math.max(0, duration - fallbackMs) / 1000;

    if (position / 1000 > 1 && position / 1000 >= creditsStart) {
      movieEndTriggeredRef.current = true;
      nav.goBack();
    }
  }, [metadata, duration, position, markers, nav, settings.creditsCountdownFallback]);

  // KSPlayer event handlers
  const onPlayerLoad = useCallback(async (data: any) => {
    console.log('[Player] KSPlayer onLoad:', data);
    const durationMs = (data.duration || 0) * 1000;
    setDuration(durationMs);
    durationRef.current = durationMs;

    // Capture player backend
    if (data.playerBackend) {
      setPlayerBackend(data.playerBackend);
      console.log('[Player] Player backend:', data.playerBackend);
    }

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

    console.log('[Player] Audio tracks from onLoad:', loadedAudioTracks);
    console.log('[Player] Text tracks from onLoad:', loadedTextTracks);

    if (data.nativeLogPath) {
      console.log('[Player] Native log path:', data.nativeLogPath);
    }
    if (KSPlayerModule?.getNativeLog) {
      try {
        const nativeLog = await KSPlayerModule.getNativeLog();
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

    // Resume from viewOffset if available
    if (metadata?.viewOffset) {
      const resumeMs = parseInt(String(metadata.viewOffset));
      if (resumeMs > 0 && playerRef.current) {
        console.log('[Player] Resuming from viewOffset:', resumeMs);
        playerRef.current.seek(resumeMs / 1000); // KSPlayer uses seconds
      }
    }

    // Start Trakt scrobble
    if (metadata && !traktScrobbleStarted.current) {
      startTraktScrobble(metadata, 0);
      traktScrobbleStarted.current = true;
      lastScrobbleState.current = 'playing';
    }
  }, [metadata]);

  const onPlayerProgress = useCallback((data: any) => {
    const currentTimeMs = (data.currentTime || 0) * 1000;
    const durationMs = (data.duration || 0) * 1000;

    // Update position ref always for cleanup/timeline
    positionRef.current = currentTimeMs;

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
      startTraktScrobble(metadataRef.current, progressPercent);
      traktScrobbleStarted.current = true;
    } else if (!currentlyPlaying && wasPlaying && lastScrobbleState.current === 'playing') {
      lastScrobbleState.current = 'paused';
      pauseTraktScrobble(metadataRef.current, progressPercent);
    }
  }, [isScrubbing]);

  const onPlayerBuffering = useCallback((data: any) => {
    setBuffering(data.isBuffering || false);
  }, []);

  const onPlayerEnd = useCallback(() => {
    console.log('[Player] KSPlayer onEnd');
    setIsPlaying(false);

    // Stop Trakt scrobble
    if (traktScrobbleStarted.current && metadata) {
      stopTraktScrobble(metadata, 100);
      lastScrobbleState.current = 'stopped';
    }
  }, [metadata]);

  const onPlayerError = useCallback((error: any) => {
    console.error('[Player] KSPlayer onError:', error);
    setError(`Playback error: ${error.message || error.error || 'Unknown error'}`);
  }, []);

  // expo-av playback status handler (Android fallback)
  const onPlaybackStatusUpdate = useCallback((status: AVPlaybackStatus) => {
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
      startTraktScrobble(metadata, progressPercent);
      traktScrobbleStarted.current = true;
    } else if (!status.isPlaying && wasPlaying && lastScrobbleState.current === 'playing') {
      lastScrobbleState.current = 'paused';
      pauseTraktScrobble(metadata, progressPercent);
    }
  }, [isScrubbing, isPlaying, metadata]);

  // MPV Player callbacks (Android)
  const onMpvLoad = useCallback((data: { duration: number; width: number; height: number }) => {
    console.log('[Player] MPV onLoad:', data);
    const durationMs = (data.duration || 0) * 1000;
    setDuration(durationMs);
    durationRef.current = durationMs;

    // Set player backend for UI display
    setPlayerBackend('MPV');

    // Resume from viewOffset if available
    if (metadata?.viewOffset) {
      const resumeMs = parseInt(String(metadata.viewOffset));
      if (resumeMs > 0 && mpvPlayerRef.current) {
        console.log('[Player] Resuming from viewOffset:', resumeMs);
        mpvPlayerRef.current.seek(resumeMs / 1000);
      }
    }

    // Start Trakt scrobble
    if (metadata && !traktScrobbleStarted.current) {
      startTraktScrobble(metadata, 0);
      traktScrobbleStarted.current = true;
      lastScrobbleState.current = 'playing';
    }
  }, [metadata]);

  const onMpvProgress = useCallback((data: { currentTime: number; duration: number }) => {
    const currentTimeMs = (data.currentTime || 0) * 1000;
    const durationMs = (data.duration || 0) * 1000;

    positionRef.current = currentTimeMs;

    if (!isScrubbing) {
      setPosition(currentTimeMs);
    }

    if (durationMs > 0 && Math.abs(durationMs - durationRef.current) > 100) {
      setDuration(durationMs);
      durationRef.current = durationMs;
    }
  }, [isScrubbing]);

  const onMpvEnd = useCallback(() => {
    console.log('[Player] MPV onEnd');
    setIsPlaying(false);

    if (traktScrobbleStarted.current && metadata) {
      stopTraktScrobble(metadata, 100);
      lastScrobbleState.current = 'stopped';
    }
  }, [metadata]);

  const onMpvError = useCallback((error: { error: string }) => {
    console.error('[Player] MPV onError:', error);
    setError(`Playback error: ${error.error || 'Unknown error'}`);
  }, []);

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
    if (Platform.OS === 'ios') {
      if (!playerRef.current) return;
      playerRef.current.setPaused(isPlaying);
    } else {
      // Android: MPV player
      // Note: MPV paused prop is controlled via state, not direct method call
      // The component re-renders with updated paused prop
      setIsPlaying(!isPlaying);
    }
  };

  const skip = async (seconds: number) => {
    const newPositionMs = Math.max(0, Math.min(duration, position + seconds * 1000));
    if (Platform.OS === 'ios') {
      if (!playerRef.current) return;
      playerRef.current.seek(newPositionMs / 1000); // KSPlayer uses seconds
    } else {
      // Android: MPV player
      if (!mpvPlayerRef.current) return;
      mpvPlayerRef.current.seek(newPositionMs / 1000); // MPV uses seconds
    }
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
    if (Platform.OS === 'ios') {
      if (!playerRef.current) return;
      playerRef.current.seek(targetMs / 1000); // KSPlayer uses seconds
    } else {
      // Android: MPV player
      if (!mpvPlayerRef.current) return;
      mpvPlayerRef.current.seek(targetMs / 1000); // MPV uses seconds
    }
    console.log(`[Player] Skipped ${marker.type} to ${targetMs}ms`);
  };

  const restart = async () => {
    if (Platform.OS === 'ios') {
      if (!playerRef.current) return;
      playerRef.current.seek(0);
      playerRef.current.setPaused(false);
    } else {
      // Android: MPV player
      if (!mpvPlayerRef.current) return;
      mpvPlayerRef.current.seek(0);
      setIsPlaying(true);
    }
  };

  // Track selection handlers (native player tracks by ID)
  const handleAudioTrackChange = useCallback((trackId: number) => {
    // Prevent duplicate calls
    if (lastAudioTrackRef.current === trackId) {
      console.log('[Player] Audio track already set to:', trackId);
      return;
    }
    lastAudioTrackRef.current = trackId;

    if (Platform.OS === 'ios') {
      if (playerRef.current) {
        console.log('[Player] Setting audio track (KSPlayer):', trackId);
        playerRef.current.setAudioTrack(trackId);
        setSelectedAudioTrack(trackId);
      }
    } else {
      if (mpvPlayerRef.current) {
        console.log('[Player] Setting audio track (MPV):', trackId);
        mpvPlayerRef.current.setAudioTrack(trackId);
        setSelectedAudioTrack(trackId);
      }
    }
  }, []);

  const handleTextTrackChange = useCallback((trackId: number) => {
    // Prevent duplicate calls
    if (lastTextTrackRef.current === trackId) {
      console.log('[Player] Text track already set to:', trackId);
      return;
    }
    lastTextTrackRef.current = trackId;

    if (Platform.OS === 'ios') {
      if (playerRef.current) {
        console.log('[Player] Setting text track (KSPlayer):', trackId);
        playerRef.current.setTextTrack(trackId);
        setSelectedTextTrack(trackId);
      }
    } else {
      if (mpvPlayerRef.current) {
        console.log('[Player] Setting subtitle track (MPV):', trackId);
        mpvPlayerRef.current.setSubtitleTrack(trackId);
        setSelectedTextTrack(trackId);
      }
    }
  }, []);

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
    setSelectedPlexAudio(streamId);
    setShowSettingsSheet(false);

    if (isDirectPlay) {
      // Direct Play: Use in-player track switching (iOS KSPlayer or Android MPV)
      let availableAudioTracks = audioTracksRef.current.length ? audioTracksRef.current : audioTracks;

      // iOS: Try to refresh tracks from KSPlayer if needed
      if (Platform.OS === 'ios' && availableAudioTracks.length === 0 && playerRef.current) {
        try {
          const freshTracks = await playerRef.current.getTracks();
          availableAudioTracks = freshTracks.audioTracks || [];
          audioTracksRef.current = availableAudioTracks;
          setAudioTracks(availableAudioTracks);
        } catch (err) {
          console.warn('[Player] Failed to refresh KSPlayer audio tracks:', err);
        }
      }

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
    setSelectedPlexSubtitle(streamId);
    setShowSettingsSheet(false);

    if (isDirectPlay) {
      // Direct Play: Use in-player track switching (iOS KSPlayer or Android MPV)
      let availableTextTracks = textTracksRef.current.length ? textTracksRef.current : textTracks;

      // iOS: Try to refresh tracks from KSPlayer if needed
      if (Platform.OS === 'ios' && availableTextTracks.length === 0 && playerRef.current) {
        try {
          const freshTracks = await playerRef.current.getTracks();
          availableTextTracks = freshTracks.textTracks || [];
          textTracksRef.current = availableTextTracks;
          setTextTracks(availableTextTracks);
        } catch (err) {
          console.warn('[Player] Failed to refresh KSPlayer tracks:', err);
        }
      }

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

  const currentMarker = markers.find(m =>
    position >= m.startTimeOffset && position <= m.endTimeOffset
  );

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
        <TouchableOpacity onPress={() => nav.goBack()} style={styles.errorButton}>
          <Text style={styles.errorButtonText}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <StatusBar hidden />

      {streamUrl ? (
        Platform.OS === 'ios' ? (
          <KSPlayerComponent
            ref={playerRef}
            source={{ uri: streamUrl }}
            style={{ width: dimensions.width, height: dimensions.height }}
            resizeMode="contain"
            paused={false}
            volume={1.0}
            rate={1.0}
            allowsExternalPlayback={true}
            usesExternalPlaybackWhileExternalScreenIsActive={true}
            onLoad={onPlayerLoad}
            onProgress={onPlayerProgress}
            onBuffering={onPlayerBuffering}
            onEnd={onPlayerEnd}
            onError={onPlayerError}
          />
        ) : (
          // Android: MPV native player
          <MPVPlayerComponent
            ref={mpvPlayerRef}
            source={{ uri: streamUrl }}
            style={{ width: dimensions.width, height: dimensions.height }}
            resizeMode="contain"
            paused={!isPlaying}
            volume={1.0}
            rate={1.0}
            decoderMode="auto"
            onLoad={onMpvLoad}
            onProgress={onMpvProgress}
            onEnd={onMpvEnd}
            onError={onMpvError}
            onTracksChanged={onMpvTracksChanged}
          />
        )
      ) : null}

      {/* Developer Stats HUD (long press play button to toggle) */}
      {Platform.OS === 'ios' && (
        <PlaybackStatsHUD
          playerRef={playerRef}
          visible={showStatsHUD}
        />
      )}

      {/* Background tap area to show/hide controls */}
      <View style={styles.tapArea} pointerEvents="box-none">
        <TouchableOpacity style={StyleSheet.absoluteFillObject} activeOpacity={1} onPress={resetControlsTimeout} />
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
                      onPress={() => playerRef.current?.showAirPlayPicker()}
                    >
                      <Ionicons name="tv-outline" size={24} color="#fff" />
                    </TouchableOpacity>
                  )}
                  <TouchableOpacity
                    style={styles.iconButton}
                    onPress={toggleFullscreen}
                  >
                    <Ionicons name={isFullscreen ? 'contract-outline' : 'expand-outline'} size={24} color="#fff" />
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={styles.iconButton}
                    onPress={() => setShowSettingsSheet(true)}
                  >
                    <Ionicons name="settings-outline" size={24} color="#fff" />
                  </TouchableOpacity>
                </View>
              </View>
            </LinearGradient>

            {/* Center play controls */}
            <View style={styles.centerControls}>
              <TouchableOpacity onPress={() => skip(-10)} style={styles.skipButton}>
                <Replay10Icon size={48} color="#fff" />
              </TouchableOpacity>

              <TouchableOpacity
                onPress={togglePlayPause}
                onLongPress={() => setShowStatsHUD(prev => !prev)}
                delayLongPress={500}
                style={styles.playPauseButton}
              >
                <Ionicons
                  name={isPlaying ? 'pause' : 'play'}
                  size={50}
                  color="#fff"
                />
              </TouchableOpacity>

              <TouchableOpacity onPress={() => skip(10)} style={styles.skipButton}>
                <Forward10Icon size={48} color="#fff" />
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
                  onSlidingStart={() => setIsScrubbing(true)}
                  onValueChange={(val: number) => setPosition(val)}
                  onSlidingComplete={(val: number) => {
                    const targetMs = Math.max(0, Math.min(duration, val));
                    if (Platform.OS === 'ios') {
                      playerRef.current?.seek(targetMs / 1000); // KSPlayer uses seconds
                    } else {
                      mpvPlayerRef.current?.seek(targetMs / 1000); // MPV uses seconds
                    }
                    setIsScrubbing(false);
                  }}
                />
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
              </View>
            </LinearGradient>
          </>
        )}

        {/* Skip Intro button - only show for intro markers (credits handled by Next Episode overlay for episodes) */}
        {currentMarker && (currentMarker.type === 'intro' || (currentMarker.type === 'credits' && !nextEpisode)) && (
          <View style={styles.skipMarkerContainer}>
            <TouchableOpacity
              onPress={() => skipMarker(currentMarker)}
              style={styles.skipMarkerButton}
            >
              <Text style={styles.skipMarkerText}>
                {currentMarker.type === 'intro' ? 'Skip Intro' : 'Skip Credits'}
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
                      uri: getPlayerImageUrl(nextEpisode.thumb, 300),
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
                    // Cancel countdown
                    nextEpisodeCountdownStartedRef.current = false;
                    if (nextEpisodeCountdownTimerRef.current) {
                      clearInterval(nextEpisodeCountdownTimerRef.current);
                      nextEpisodeCountdownTimerRef.current = null;
                    }
                    setNextEpisodeCountdown(null);
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

        {/* Buffering indicator */}
        {buffering && (
          <View style={styles.bufferingContainer}>
          <ActivityIndicator size="large" color="#fff" />
        </View>
      )}
      </View>

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
        // KSPlayer tracks (iOS) - as fallback if Plex streams not available
        ksAudioTracks={plexAudioStreams.length === 0 ? audioTracks : []}
        ksTextTracks={plexSubtitleStreams.length === 0 ? textTracks : []}
        selectedKsAudioTrack={selectedAudioTrack}
        selectedKsTextTrack={selectedTextTrack}
        onKsAudioChange={handleAudioTrackChange}
        onKsTextTrack={handleTextTrackChange}
        // Quality options
        qualityOptions={qualityOptions}
        selectedQuality={selectedQuality}
        onQualityChange={handleQualityChange}
        // Playback info (uses selectedMediaIndex for multi-version support)
        playbackInfo={{
          isDirectPlay,
          videoCodec: metadata?.Media?.[selectedMediaIndex]?.videoCodec,
          videoResolution: metadata?.Media?.[selectedMediaIndex]?.videoResolution,
          videoBitrate: selectedQuality === 'original' ? metadata?.Media?.[selectedMediaIndex]?.bitrate : selectedQuality,
          audioCodec: metadata?.Media?.[selectedMediaIndex]?.audioCodec,
          audioChannels: metadata?.Media?.[selectedMediaIndex]?.audioChannels?.toString() + ' channels',
          container: metadata?.Media?.[selectedMediaIndex]?.container,
          playerBackend: playerBackend || (Platform.OS === 'ios' ? 'KSPlayer' : 'expo-av'),
          // HDR info - prefer native detection, fallback to Plex metadata
          hdrType: (hdrType as PlaybackInfo['hdrType']) || (() => {
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
          })(),
          colorSpace: colorSpace || (() => {
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
  errorButton: {
    backgroundColor: '#e50914',
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
    ...StyleSheet.absoluteFillObject,
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
    justifyContent: 'center',
    gap: 24,
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
  bufferingContainer: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    pointerEvents: 'none',
  },
});
