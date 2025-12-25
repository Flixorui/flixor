import React, { useEffect, useState, useRef, useCallback } from 'react';
import { View, Text, TouchableOpacity, ActivityIndicator, StyleSheet, StatusBar, Dimensions, Platform } from 'react-native';
import { Video, ResizeMode, AVPlaybackStatus, Audio } from 'expo-av';
import { Image as ExpoImage } from 'expo-image';
import Slider from '@react-native-community/slider';
import { useNavigation, StackActions } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import * as ScreenOrientation from 'expo-screen-orientation';
import { LinearGradient } from 'expo-linear-gradient';
import { KSPlayerComponent, KSPlayerRef, AudioTrack, TextTrack } from '../components/player';
import { useFlixor } from '../core/FlixorContext';
import {
  fetchPlayerMetadata,
  fetchMarkers,
  fetchNextEpisode,
  getTranscodeStreamUrl,
  startTranscodeSession,
  updatePlaybackTimeline,
  stopTranscodeSession,
  getPlayerImageUrl,
  startTraktScrobble,
  pauseTraktScrobble,
  stopTraktScrobble,
  isTraktAuthenticated,
  NextEpisodeInfo,
} from '../core/PlayerData';
import { Replay10Icon, Forward10Icon } from '../components/icons/SkipIcons';
import { TopBarStore } from '../components/TopBarStore';

type PlayerParams = {
  type: 'plex' | 'tmdb';
  ratingKey?: string;
  id?: string;
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
  const videoRef = useRef<Video>(null); // expo-av fallback for Android
  const { isLoading: flixorLoading, isConnected } = useFlixor();

  // Track selection state (iOS KSPlayer only)
  const [audioTracks, setAudioTracks] = useState<AudioTrack[]>([]);
  const [textTracks, setTextTracks] = useState<TextTrack[]>([]);
  const [selectedAudioTrack, setSelectedAudioTrack] = useState<number | null>(null);
  const [selectedTextTrack, setSelectedTextTrack] = useState<number | null>(null);

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
  const [markers, setMarkers] = useState<Array<{ type: string; startTimeOffset: number; endTimeOffset: number }>>([]);

  // Next episode for auto-play
  const [nextEpisode, setNextEpisode] = useState<NextEpisodeInfo | null>(null);
  const [nextEpisodeCountdown, setNextEpisodeCountdown] = useState<number | null>(null);

  // Session ID for transcode management
  const [sessionId, setSessionId] = useState<string>('');

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

  // Scrubbing state
  const [isScrubbing, setIsScrubbing] = useState(false);
  // Legacy pan scrub state removed (using Slider now)

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
      // @ts-ignore - navigation may not expose replace; use dispatch
      nav.dispatch(StackActions.replace('Player', { type: 'plex', ratingKey: nextEpisode.ratingKey }));
    }
  }, [nextEpisode, cleanup, nav]);

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
            // Always use HLS transcode for mobile compatibility
            console.log('[Player] Using HLS transcode');
            console.log(`[Player] Media: container=${media?.container}, videoCodec=${media?.videoCodec}`);

            const { startUrl, sessionUrl, sessionId: sid } = getTranscodeStreamUrl(params.ratingKey, {
              maxVideoBitrate: 20000,
              videoResolution: '1920x1080',
              protocol: 'hls',
            });

            // Start the transcode session first
            console.log('[Player] Starting transcode session...');
            try {
              await startTranscodeSession(startUrl);
              console.log('[Player] Transcode session started, using session URL');
              setStreamUrl(sessionUrl);
            } catch (e) {
              console.log('[Player] Failed to start session, falling back to start URL');
              setStreamUrl(startUrl);
            }

            setSessionId(sid);
            cleanupInfoRef.current.sessionId = sid;

            // Set resume position (handled in onLoad callback)
            // viewOffset will be used in onLoad to seek to resume position

            setLoading(false);
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
  const isPlayingRef = useRef(isPlaying);
  isPlayingRef.current = isPlaying;

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
        await ScreenOrientation.unlockAsync();
        await Audio.setAudioModeAsync({ playsInSilentModeIOS: true, staysActiveInBackground: true, shouldDuckAndroid: true });
        // If we just replaced into this screen, ensure playback starts and orientation is landscape
        if (isReplacingRef.current) {
          isReplacingRef.current = false;
          try { await ScreenOrientation.unlockAsync(); } catch {}
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

  // Next episode countdown logic
  useEffect(() => {
    if (metadata?.type !== 'episode' || !nextEpisode || !duration) {
      setNextEpisodeCountdown(null);
      return;
    }

    const creditsMarker = markers.find(m => m.type === 'credits');
    const triggerStart = creditsMarker ? (creditsMarker.startTimeOffset / 1000) : Math.max(0, duration - 30000) / 1000;

    if (position / 1000 >= triggerStart) {
      const remaining = Math.max(0, Math.ceil((duration - position) / 1000));
      setNextEpisodeCountdown(remaining);
    } else {
      setNextEpisodeCountdown(null);
    }
  }, [metadata, nextEpisode, duration, position, markers]);

  // Auto-play next episode
  useEffect(() => {
    if (nextEpisodeCountdown !== null && nextEpisodeCountdown <= 0 && nextEpisode) {
      playNext();
    }
  }, [nextEpisodeCountdown, nextEpisode, playNext]);

  // Movie end handling
  useEffect(() => {
    if (metadata?.type !== 'movie' || !duration) return;

    const creditsMarker = markers.find(m => m.type === 'credits');
    const creditsStart = creditsMarker ? (creditsMarker.startTimeOffset / 1000) : Math.max(0, duration - 30000) / 1000;

    if (position / 1000 > 1 && position / 1000 >= creditsStart) {
      nav.goBack();
    }
  }, [metadata, duration, position, markers, nav]);

  // KSPlayer event handlers
  const onPlayerLoad = useCallback(async (data: any) => {
    console.log('[Player] KSPlayer onLoad:', data);
    const durationMs = (data.duration || 0) * 1000;
    setDuration(durationMs);
    durationRef.current = durationMs;

    // Fetch tracks after load
    if (playerRef.current) {
      try {
        const tracks = await playerRef.current.getTracks();
        console.log('[Player] Tracks:', tracks);
        setAudioTracks(tracks.audioTracks || []);
        setTextTracks(tracks.textTracks || []);

        // Set default selected tracks based on isEnabled
        const enabledAudio = tracks.audioTracks.find((t: AudioTrack) => t.isEnabled);
        const enabledText = tracks.textTracks.find((t: TextTrack) => t.isEnabled);
        if (enabledAudio) setSelectedAudioTrack(enabledAudio.id);
        if (enabledText) setSelectedTextTrack(enabledText.id);
      } catch (e) {
        console.warn('[Player] Failed to get tracks:', e);
      }
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

    if (!isScrubbing) {
      setPosition(currentTimeMs);
      positionRef.current = currentTimeMs;
    }

    if (durationMs > 0) {
      setDuration(durationMs);
      durationRef.current = durationMs;
    }

    // Update play state - prefer isPlaying flag, fallback to playbackRate
    const currentlyPlaying = data.isPlaying ?? ((data.playbackRate || 0) > 0);
    const wasPlaying = isPlaying;
    setIsPlaying(currentlyPlaying);

    // Trakt scrobbling integration
    const progressPercent = durationMs > 0 ? Math.round((currentTimeMs / durationMs) * 100) : 0;

    // Handle scrobble state changes
    if (currentlyPlaying && lastScrobbleState.current !== 'playing') {
      lastScrobbleState.current = 'playing';
      startTraktScrobble(metadata, progressPercent);
      traktScrobbleStarted.current = true;
    } else if (!currentlyPlaying && wasPlaying && lastScrobbleState.current === 'playing') {
      lastScrobbleState.current = 'paused';
      pauseTraktScrobble(metadata, progressPercent);
    }
  }, [isScrubbing, isPlaying, metadata]);

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

  const togglePlayPause = async () => {
    if (Platform.OS === 'ios') {
      if (!playerRef.current) return;
      playerRef.current.setPaused(isPlaying);
    } else {
      // Android: expo-av
      if (!videoRef.current) return;
      if (isPlaying) {
        await videoRef.current.pauseAsync();
      } else {
        await videoRef.current.playAsync();
      }
    }
  };

  const skip = async (seconds: number) => {
    const newPositionMs = Math.max(0, Math.min(duration, position + seconds * 1000));
    if (Platform.OS === 'ios') {
      if (!playerRef.current) return;
      playerRef.current.seek(newPositionMs / 1000); // KSPlayer uses seconds
    } else {
      // Android: expo-av
      if (!videoRef.current) return;
      await videoRef.current.setPositionAsync(newPositionMs);
    }
  };

  const skipMarker = async (marker: { type: string; startTimeOffset: number; endTimeOffset: number }) => {
    const targetMs = marker.endTimeOffset + 1000;
    if (Platform.OS === 'ios') {
      if (!playerRef.current) return;
      playerRef.current.seek(targetMs / 1000); // KSPlayer uses seconds
    } else {
      // Android: expo-av
      if (!videoRef.current) return;
      await videoRef.current.setPositionAsync(targetMs);
    }
  };

  const restart = async () => {
    if (Platform.OS === 'ios') {
      if (!playerRef.current) return;
      playerRef.current.seek(0);
      playerRef.current.setPaused(false);
    } else {
      // Android: expo-av
      if (!videoRef.current) return;
      await videoRef.current.setPositionAsync(0);
      await videoRef.current.playAsync();
    }
  };

  // Track selection handlers
  const handleAudioTrackChange = (trackId: number) => {
    if (playerRef.current) {
      playerRef.current.setAudioTrack(trackId);
      setSelectedAudioTrack(trackId);
    }
  };

  const handleTextTrackChange = (trackId: number) => {
    if (playerRef.current) {
      playerRef.current.setTextTrack(trackId);
      setSelectedTextTrack(trackId);
    }
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
          // Android fallback: expo-av
          <Video
            ref={videoRef}
            source={{ uri: streamUrl }}
            style={{ width: dimensions.width, height: dimensions.height }}
            resizeMode={ResizeMode.CONTAIN}
            shouldPlay={true}
            isMuted={false}
            volume={1.0}
            onPlaybackStatusUpdate={onPlaybackStatusUpdate}
            useNativeControls={false}
          />
        )
      ) : null}

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
                  <TouchableOpacity style={styles.iconButton}>
                    <Ionicons name="ellipsis-horizontal" size={24} color="#fff" />
                  </TouchableOpacity>
                </View>
              </View>
            </LinearGradient>

            {/* Center play controls */}
            <View style={styles.centerControls}>
              <TouchableOpacity onPress={() => skip(-10)} style={styles.skipButton}>
                <Replay10Icon size={48} color="#fff" />
              </TouchableOpacity>

              <TouchableOpacity onPress={togglePlayPause} style={styles.playPauseButton}>
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
                  onSlidingComplete={async (val: number) => {
                    const targetMs = Math.max(0, Math.min(duration, val));
                    if (Platform.OS === 'ios') {
                      playerRef.current?.seek(targetMs / 1000); // KSPlayer uses seconds
                    } else {
                      await videoRef.current?.setPositionAsync(targetMs);
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

        {/* Skip Intro/Credits button */}
        {currentMarker && (
          <View style={styles.skipMarkerContainer}>
            <TouchableOpacity
              onPress={() => skipMarker(currentMarker)}
              style={styles.skipMarkerButton}
            >
              <Ionicons name="play-skip-forward" size={20} color="#000" />
              <Text style={styles.skipMarkerText}>
                SKIP {currentMarker.type === 'intro' ? 'INTRO' : currentMarker.type === 'credits' ? 'CREDITS' : 'MARKER'}
              </Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Next episode countdown */}
        {nextEpisodeCountdown !== null && nextEpisode && (
          <View style={styles.nextEpisodeContainer}>
            <View style={styles.nextEpisodeCard}>
              <TouchableOpacity
                style={styles.nextEpisodeInfo}
                onPress={playNext}
                activeOpacity={0.7}
              >
                <View style={styles.nextEpisodeThumbnail}>
                  {nextEpisode.thumb ? (
                    <ExpoImage
                      source={{ uri: getPlayerImageUrl(nextEpisode.thumb, 300) }}
                      style={{ width: '100%', height: '100%', borderRadius: 4 }}
                      contentFit="cover"
                    />
                  ) : (
                    <Ionicons name="play-circle" size={40} color="#fff" />
                  )}
                </View>
                <View style={styles.nextEpisodeDetails}>
                  <Text style={styles.nextEpisodeOverline} numberOfLines={1}>
                    {nextEpisode.episodeLabel ? `${nextEpisode.episodeLabel} •` : ''} NEXT EPISODE • Playing in {nextEpisodeCountdown}s
                  </Text>
                  <Text style={styles.nextEpisodeTitle} numberOfLines={1}>
                    {nextEpisode.title}
                  </Text>
                </View>
              </TouchableOpacity>
              <TouchableOpacity
                onPress={() => nav.goBack()}
                style={styles.seeAllButton}
              >
                <Text style={styles.seeAllText}>SEE ALL EPISODES</Text>
              </TouchableOpacity>
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
  skipMarkerContainer: {
    position: 'absolute',
    bottom: 140,
    right: 20,
  },
  skipMarkerButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: '#fff',
    paddingHorizontal: 20,
    paddingVertical: 12,
    borderRadius: 4,
  },
  skipMarkerText: {
    color: '#000',
    fontSize: 14,
    fontWeight: '700',
    letterSpacing: 0.5,
  },
  nextEpisodeContainer: {
    position: 'absolute',
    bottom: 60,
    left: 20,
    right: 20,
    zIndex: 5,
  },
  nextEpisodeCard: {
    backgroundColor: 'transparent',
    borderRadius: 8,
    overflow: 'hidden',
    flexDirection: 'row',
    alignItems: 'center',
    paddingRight: 12,
  },
  nextEpisodeInfo: {
    flexDirection: 'row',
    padding: 16,
    gap: 12,
    flex: 1,
  },
  nextEpisodeThumbnail: {
    width: 92,
    height: 52,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  nextEpisodeDetails: {
    flex: 1,
    justifyContent: 'center',
  },
  nextEpisodeOverline: {
    color: '#ddd',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 0.4,
    marginBottom: 2,
  },
  nextEpisodeTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '800',
  },
  seeAllButton: {
    borderWidth: 2,
    borderColor: '#fff',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 6,
    alignItems: 'center',
    justifyContent: 'center',
  },
  seeAllText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '900',
    letterSpacing: 1,
  },
  bufferingContainer: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    pointerEvents: 'none',
  },
});
