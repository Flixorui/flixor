import { useEffect, useRef, useState, useCallback } from 'react';
import Hls from 'hls.js';
import * as dashjs from 'dashjs';
import { VideoSeekSlider } from 'react-video-seek-slider';
import '../styles/player.css';

// Real-time stats from player libraries
export interface PlayerStats {
  videoBitrate?: number; // bps
  audioBitrate?: number; // bps
  downloadSpeed?: number; // bps
  bufferLength?: number; // seconds
  latency?: number; // ms
  qualityLevel?: number;
  autoQuality?: boolean;
}

interface PlexVideoPlayerProps {
  src: string;
  poster?: string;
  autoPlay?: boolean;
  onTimeUpdate?: (time: number, duration: number) => void;
  onEnded?: () => void;
  onError?: (error: string) => void;
  onReady?: () => void;
  onBuffering?: (buffering: boolean) => void;
  startTime?: number;
  videoRef?: React.RefObject<HTMLVideoElement>;
  playing?: boolean;
  volume?: number;
  playbackRate?: number;
  onPlayingChange?: (playing: boolean) => void;
  onCodecError?: (error: string) => void; // Callback for codec-specific errors
  onUserSeek?: () => void;
  onStatsUpdate?: (stats: PlayerStats) => void; // Real-time stats callback
}

export default function PlexVideoPlayer({
  src,
  poster,
  autoPlay = true,
  onTimeUpdate,
  onEnded,
  onError,
  onReady,
  onBuffering,
  startTime,
  videoRef: externalVideoRef,
  playing = true,
  volume = 1,
  playbackRate = 1,
  onPlayingChange,
  onCodecError,
  onUserSeek,
  onStatsUpdate,
}: PlexVideoPlayerProps) {
  const internalVideoRef = useRef<HTMLVideoElement>(null);
  const videoRef = externalVideoRef || internalVideoRef;
  const hlsRef = useRef<Hls | null>(null);
  const dashRef = useRef<dashjs.MediaPlayerClass | null>(null);
  const [isReady, setIsReady] = useState(false);
  // Track if we've already performed the initial seek (to avoid re-seeking on prop changes)
  const initialSeekDoneRef = useRef(false);
  // Store the initial start time in a ref so it persists across renders
  const startTimeRef = useRef(startTime);

  // Store callbacks in refs so we always call the latest version without re-running the effect
  const onTimeUpdateRef = useRef(onTimeUpdate);
  const onEndedRef = useRef(onEnded);
  const onErrorRef = useRef(onError);
  const onReadyRef = useRef(onReady);
  const onBufferingRef = useRef(onBuffering);
  const onPlayingChangeRef = useRef(onPlayingChange);
  const onCodecErrorRef = useRef(onCodecError);
  const onUserSeekRef = useRef(onUserSeek);
  const onStatsUpdateRef = useRef(onStatsUpdate);

  // Keep refs in sync with props
  useEffect(() => { onTimeUpdateRef.current = onTimeUpdate; }, [onTimeUpdate]);
  useEffect(() => { onEndedRef.current = onEnded; }, [onEnded]);
  useEffect(() => { onErrorRef.current = onError; }, [onError]);
  useEffect(() => { onReadyRef.current = onReady; }, [onReady]);
  useEffect(() => { onBufferingRef.current = onBuffering; }, [onBuffering]);
  useEffect(() => { onPlayingChangeRef.current = onPlayingChange; }, [onPlayingChange]);
  useEffect(() => { onCodecErrorRef.current = onCodecError; }, [onCodecError]);
  useEffect(() => { onUserSeekRef.current = onUserSeek; }, [onUserSeek]);
  useEffect(() => { onStatsUpdateRef.current = onStatsUpdate; }, [onStatsUpdate]);

  // Stats collection effect - collect real-time stats from dash.js/hls.js
  // Only collects when onStatsUpdate callback is provided
  useEffect(() => {
    const collectStats = () => {
      // Skip if no callback provided (stats HUD not visible)
      if (!onStatsUpdateRef.current) return;
      const stats: PlayerStats = {};

      // Collect DASH.js stats
      if (dashRef.current) {
        try {
          // Cast to any to access dash.js methods not in type definitions
          const dash = dashRef.current as any;
          const dashMetrics = dash.getDashMetrics?.();

          // Get current video quality
          const videoQuality = dash.getQualityFor?.('video');
          const videoRepresentation = dash.getBitrateInfoListFor?.('video')?.[videoQuality];
          if (videoRepresentation) {
            stats.videoBitrate = videoRepresentation.bitrate;
          }

          // Get current audio quality
          const audioQuality = dash.getQualityFor?.('audio');
          const audioRepresentation = dash.getBitrateInfoListFor?.('audio')?.[audioQuality];
          if (audioRepresentation) {
            stats.audioBitrate = audioRepresentation.bitrate;
          }

          // Get buffer length
          const bufferLevel = dash.getBufferLength?.('video');
          if (bufferLevel !== undefined) {
            stats.bufferLength = bufferLevel;
          }

          // Get download throughput
          const dashAdapter = dash.getDashAdapter?.();
          if (dashAdapter && dashMetrics) {
            const httpRequests = dashMetrics.getHttpRequests?.('video');
            if (httpRequests && httpRequests.length > 0) {
              const lastRequest = httpRequests[httpRequests.length - 1] as any;
              if (lastRequest?.tresponse && lastRequest?.trequest) {
                const latency = lastRequest.tresponse.getTime() - lastRequest.trequest.getTime();
                stats.latency = latency;
              }
            }
          }

          stats.qualityLevel = videoQuality;
          stats.autoQuality = dash.getSettings?.()?.streaming?.abr?.autoSwitchBitrate?.video ?? false;
        } catch (e) {
          // Silently fail if stats collection fails
        }
      }

      // Collect HLS.js stats
      if (hlsRef.current) {
        try {
          const hls = hlsRef.current;

          // Get current level bitrate
          const currentLevel = hls.levels[hls.currentLevel];
          if (currentLevel) {
            stats.videoBitrate = currentLevel.bitrate;
            if (currentLevel.audioCodec) {
              // HLS.js doesn't expose audio bitrate directly
            }
          }

          // Get buffer length from video element
          const video = videoRef.current;
          if (video && video.buffered.length > 0) {
            const bufferedEnd = video.buffered.end(video.buffered.length - 1);
            stats.bufferLength = bufferedEnd - video.currentTime;
          }

          // Get bandwidth estimate
          if (hls.bandwidthEstimate) {
            stats.downloadSpeed = hls.bandwidthEstimate;
          }

          stats.qualityLevel = hls.currentLevel;
          stats.autoQuality = hls.autoLevelEnabled;
        } catch (e) {
          // Silently fail if stats collection fails
        }
      }

      // Only call callback if we have some stats
      if (Object.keys(stats).length > 0) {
        onStatsUpdateRef.current?.(stats);
      }
    };

    // Collect stats every 1 second to reduce CPU overhead
    const interval = setInterval(collectStats, 1000);
    return () => clearInterval(interval);
  }, [videoRef]);

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !src) return;

    // console.log('PlexVideoPlayer: Setting up player for URL:', src);

    const setupPlayer = () => {
      // Reset ready state when setting up new player
      setIsReady(false);
      // Reset initial seek flag for new source
      initialSeekDoneRef.current = false;
      // Update start time ref with current prop value
      startTimeRef.current = startTime;
      console.log('[Resume Debug] PlexVideoPlayer setupPlayer - startTime prop:', startTime, 'startTimeRef.current:', startTimeRef.current);

      // Clean up previous HLS instance
      if (hlsRef.current) {
        // console.log('Cleaning up previous HLS instance');
        try {
          hlsRef.current.stopLoad();
          hlsRef.current.detachMedia();
          hlsRef.current.destroy();
        } catch (e) {
          console.error('Error cleaning up HLS:', e);
        }
        hlsRef.current = null;
      }

      // Clean up previous DASH instance
      if (dashRef.current) {
        // console.log('Cleaning up previous DASH instance');
        try {
          dashRef.current.reset();
        } catch (e) {
          console.error('Error cleaning up DASH:', e);
        }
        dashRef.current = null;
      }

      // Reset video element
      video.pause();
      video.removeAttribute('src');
      video.load();

      // Determine stream type
      const isDash = src.includes('.mpd');
      const isHls = src.includes('.m3u8');

      console.log('[Player] Stream type:', isDash ? 'DASH' : isHls ? 'HLS' : 'Direct', 'URL:', src.substring(0, 100));

      if (isDash) {
        // Use DASH.js for DASH streams
        // console.log('Using DASH.js for:', src);
        const dash = dashjs.MediaPlayer().create();

        // Configure DASH player for optimized buffer management and smooth playback
        // Balance between preventing QuotaExceededError and ensuring smooth playback
        // Cast to any to include settings not in dash.js type definitions
        // Use simpler DASH.js configuration - closer to defaults
        dash.updateSettings({
          streaming: {
            buffer: {
              bufferTimeAtTopQuality: 30,
              bufferTimeAtTopQualityLongForm: 60,
              fastSwitchEnabled: false,
            },
            abr: {
              autoSwitchBitrate: {
                video: false, // Manual quality control
                audio: true,
              },
            },
            scheduling: {
              scheduleWhilePaused: true,
            },
            gaps: {
              jumpGaps: true,
              jumpLargeGaps: true,
            },
          },
          debug: { logLevel: 0 },
        } as any);

        console.log('[Player] DASH.js initialized');

        // Initialize DASH player with start time if available
        // Pass startTime as 4th parameter to initialize for proper initial seek
        const initialStartTime = startTimeRef.current && startTimeRef.current > 0 ? startTimeRef.current : undefined;
        console.log('[Resume Debug] DASH initializing with startTime:', initialStartTime);
        dash.initialize(video, src, autoPlay, initialStartTime);

        // Handle DASH events
        dash.on(dashjs.MediaPlayer.events.MANIFEST_LOADED, () => {
          // console.log('DASH manifest loaded');
          if (!isReady) {
            setIsReady(true);
            onReadyRef.current?.();
          }
        });

        // Seek on CAN_PLAY for more reliable positioning (fallback if initialize didn't seek)
        dash.on(dashjs.MediaPlayer.events.CAN_PLAY, () => {
          console.log('[Resume Debug] DASH CAN_PLAY - initialSeekDoneRef:', initialSeekDoneRef.current, 'startTimeRef:', startTimeRef.current, 'currentTime:', video.currentTime);
          // Only seek if we haven't already and current position is near 0
          if (!initialSeekDoneRef.current && startTimeRef.current && startTimeRef.current > 0 && video.currentTime < 5) {
            console.log('[Resume Debug] DASH CAN_PLAY seeking to:', startTimeRef.current);
            dash.seek(startTimeRef.current);
            initialSeekDoneRef.current = true;
          }
        });

        dash.on(dashjs.MediaPlayer.events.ERROR, (e: any) => {
          console.error('DASH error:', e);
          const errorMsg = e.error?.message || e.error?.code || 'Unknown error';

          // Check for Dolby Vision codec mismatch errors
          if (errorMsg.includes('dolbyvision') ||
              errorMsg.includes('codec') ||
              errorMsg.includes('CHUNK_DEMUXER_ERROR_APPEND_FAILED')) {
            console.warn('Dolby Vision codec error detected, triggering fallback');
            onCodecErrorRef.current?.(errorMsg);
          } else {
            onErrorRef.current?.(`DASH Error: ${errorMsg}`);
          }
        });

        dash.on(dashjs.MediaPlayer.events.BUFFER_EMPTY, () => {
          onBufferingRef.current?.(true);
        });

        dash.on(dashjs.MediaPlayer.events.BUFFER_LOADED, () => {
          onBufferingRef.current?.(false);
        });

        dashRef.current = dash;
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        // Safari native HLS support
        // console.log('Using native HLS support');
        // Don't use credentials for direct Plex URLs (token is in URL params)
        const isDirectPlexUrl = src.includes('X-Plex-Token') || src.includes('plex.direct');
        try { (video as any).crossOrigin = isDirectPlexUrl ? 'anonymous' : 'use-credentials'; } catch {}
        video.src = src;
        video.load();
      } else if (Hls.isSupported()) {
        // Use HLS.js for other browsers
        // console.log('Using HLS.js for:', src);

        // Check if this is a direct Plex URL (token in URL) vs proxied URL
        const isDirectPlexUrl = src.includes('X-Plex-Token') || src.includes('plex.direct');

        // Use simple HLS.js configuration optimized for smooth playback
        const hls = new Hls({
          debug: false,
          enableWorker: true,
          lowLatencyMode: false,
          // Buffer settings for smooth high-bitrate playback
          maxBufferLength: 60,
          maxMaxBufferLength: 600,
          maxBufferSize: 120 * 1000 * 1000, // 120 MB for high bitrate content
          backBufferLength: 60,
          // Let HLS.js handle ABR
          startLevel: -1,
          // Relaxed loading timeouts
          fragLoadingTimeOut: 60000,
          fragLoadingMaxRetry: 6,
          manifestLoadingTimeOut: 30000,
          levelLoadingTimeOut: 30000,
          // Reduce append frequency to minimize main thread work
          appendErrorMaxRetry: 3,
          // Bigger buffer hole tolerance
          maxBufferHole: 0.5,
          // Smooth playback settings
          highBufferWatchdogPeriod: 3,
          nudgeMaxRetry: 5,
          xhrSetup: (xhr: XMLHttpRequest, url: string) => {
            // Only send credentials for proxied URLs, not direct Plex URLs
            if (!isDirectPlexUrl && !url.includes('X-Plex-Token') && !url.includes('plex.direct')) {
              xhr.withCredentials = true;
            }
          },
        });

        console.log('[Player] HLS.js initialized');

        hls.loadSource(src);
        hls.attachMedia(video);

        hls.on(Hls.Events.MANIFEST_PARSED, () => {
          // console.log('HLS manifest parsed');
          if (!isReady) {
            setIsReady(true);
            onReadyRef.current?.();
          }
          // Seek to start position for HLS streams (must be after manifest parsed)
          // Use ref to ensure we only seek once per source
          console.log('[Resume Debug] HLS MANIFEST_PARSED - initialSeekDoneRef:', initialSeekDoneRef.current, 'startTimeRef:', startTimeRef.current);
          if (!initialSeekDoneRef.current && startTimeRef.current && startTimeRef.current > 0) {
            console.log('[Resume Debug] HLS seeking to:', startTimeRef.current);
            video.currentTime = startTimeRef.current;
            initialSeekDoneRef.current = true;
          }
          if (autoPlay) {
            video.play().catch(e => console.warn('Autoplay failed:', e));
          }
        });

        hls.on(Hls.Events.ERROR, (event, data) => {
          // Don't log non-fatal errors unless they're important
          if (data.fatal || data.details === 'bufferStalledError' || data.details === 'bufferAppendError') {
            console.error('HLS error:', event, data);
          }

          if (data.fatal) {
            switch (data.type) {
              case Hls.ErrorTypes.NETWORK_ERROR:
                console.error('Fatal network error, trying to recover');
                hls.startLoad();
                break;
              case Hls.ErrorTypes.MEDIA_ERROR:
                console.error('Fatal media error, trying to recover');
                hls.recoverMediaError();
                break;
              default:
                console.error('Fatal error, cannot recover');
                onErrorRef.current?.(`HLS Error: ${data.details}`);
                hls.destroy();
                break;
            }
          } else {
            // Handle non-fatal errors
            switch (data.details) {
              case 'bufferStalledError':
                // Buffer stalled, restart loading
                hls.startLoad();
                break;
              case 'bufferAppendError':
                // Buffer append failed (often QuotaExceededError), try to recover
                // This can happen when the browser's media buffer is full
                console.warn('Buffer append error, attempting recovery by clearing buffer');
                try {
                  // Trigger buffer flush by seeking slightly
                  const currentTime = video.currentTime;
                  if (currentTime > 1) {
                    video.currentTime = currentTime - 0.1;
                  }
                  hls.startLoad();
                } catch (e) {
                  console.error('Failed to recover from buffer append error:', e);
                }
                break;
              case 'bufferNudgeOnStall':
                // Playback stalled, try nudging
                hls.startLoad();
                break;
            }
          }
        });

        hlsRef.current = hls;
      } else {
        // Fallback to direct playback
        // console.log('HLS not supported, trying direct playback');
        // Don't use credentials for direct Plex URLs (token is in URL params)
        const isDirectPlexUrl = src.includes('X-Plex-Token') || src.includes('plex.direct');
        try { (video as any).crossOrigin = isDirectPlexUrl ? 'anonymous' : 'use-credentials'; } catch {}
        video.src = src;
        video.load();
      }
    };

    setupPlayer();

    // Event listeners
    const handleLoadedMetadata = () => {
      // console.log('Video metadata loaded');
      if (!isReady) {
        setIsReady(true);
        onReadyRef.current?.();
      }
      // Seek to start position (for native HLS/direct playback)
      // Use ref to ensure we only seek once per source
      if (!initialSeekDoneRef.current && startTimeRef.current && startTimeRef.current > 0) {
        video.currentTime = startTimeRef.current;
        initialSeekDoneRef.current = true;
      }
      if (autoPlay) {
        video.play().catch(e => console.warn('Autoplay failed:', e));
      }
    };

    const handleTimeUpdate = () => {
      onTimeUpdateRef.current?.(video.currentTime, video.duration);
    };

    const handleEnded = () => {
      onEndedRef.current?.();
    };

    const handleError = (e: Event) => {
      const error = video.error;
      console.error('Video error:', error);
      const errorMsg = error?.message || 'Unknown error';

      // Check for Dolby Vision or codec mismatch errors
      if (errorMsg.includes('dolbyvision') ||
          errorMsg.includes('codec') ||
          errorMsg.includes('CHUNK_DEMUXER_ERROR_APPEND_FAILED') ||
          errorMsg.includes('MEDIA_ERR_SRC_NOT_SUPPORTED')) {
        console.warn('Dolby Vision or codec error detected, triggering fallback');
        onCodecErrorRef.current?.(errorMsg);
      } else {
        onErrorRef.current?.(errorMsg);
      }
    };

    const handleWaiting = () => {
      onBufferingRef.current?.(true);
    };

    const handlePlaying = () => {
      onBufferingRef.current?.(false);
      onPlayingChangeRef.current?.(true);
    };

    const handlePause = () => {
      onPlayingChangeRef.current?.(false);
    };

    const handleSeeking = () => {
      onBufferingRef.current?.(true);
      onUserSeekRef.current?.();
    };

    const handleSeeked = () => {
      onBufferingRef.current?.(false);
    };

    // Universal fallback: seek on canplay if we still haven't seeked and position is near 0
    const handleCanPlay = () => {
      console.log('[Resume Debug] canplay event - initialSeekDoneRef:', initialSeekDoneRef.current, 'startTimeRef:', startTimeRef.current, 'currentTime:', video.currentTime);
      if (!initialSeekDoneRef.current && startTimeRef.current && startTimeRef.current > 0 && video.currentTime < 5) {
        console.log('[Resume Debug] canplay fallback seeking to:', startTimeRef.current);
        video.currentTime = startTimeRef.current;
        initialSeekDoneRef.current = true;
      }
    };

    video.addEventListener('loadedmetadata', handleLoadedMetadata);
    video.addEventListener('timeupdate', handleTimeUpdate);
    video.addEventListener('ended', handleEnded);
    video.addEventListener('error', handleError);
    video.addEventListener('waiting', handleWaiting);
    video.addEventListener('playing', handlePlaying);
    video.addEventListener('pause', handlePause);
    video.addEventListener('seeking', handleSeeking);
    video.addEventListener('seeked', handleSeeked);
    video.addEventListener('canplay', handleCanPlay);

    return () => {
      video.removeEventListener('loadedmetadata', handleLoadedMetadata);
      video.removeEventListener('timeupdate', handleTimeUpdate);
      video.removeEventListener('ended', handleEnded);
      video.removeEventListener('error', handleError);
      video.removeEventListener('waiting', handleWaiting);
      video.removeEventListener('playing', handlePlaying);
      video.removeEventListener('pause', handlePause);
      video.removeEventListener('seeking', handleSeeking);
      video.removeEventListener('seeked', handleSeeked);
      video.removeEventListener('canplay', handleCanPlay);

      if (hlsRef.current) {
        try {
          hlsRef.current.stopLoad();
          hlsRef.current.detachMedia();
          hlsRef.current.destroy();
        } catch (e) {
          console.error('Error cleaning up HLS on unmount:', e);
        }
        hlsRef.current = null;
      }

      if (dashRef.current) {
        try {
          dashRef.current.reset();
        } catch (e) {
          console.error('Error cleaning up DASH on unmount:', e);
        }
        dashRef.current = null;
      }

      // Clean video element
      video.pause();
      video.removeAttribute('src');
      video.load();
    };
  // Note: startTime and callback props are intentionally not in deps
  // - startTime: we use startTimeRef to avoid re-mounting on prop changes
  // - callbacks: they may change due to parent re-renders, but we don't want to destroy/recreate the player
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [src, autoPlay]);

  // Handle play/pause
  useEffect(() => {
    const video = videoRef.current;
    if (!video || !isReady) return;

    if (playing) {
      video.play().catch(e => {
        console.warn('Play failed:', e);
      });
    } else {
      video.pause();
    }
  }, [playing, isReady, videoRef]);

  // Handle volume
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.volume = Math.max(0, Math.min(1, volume));
  }, [volume]);

  // Handle playback rate
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.playbackRate = playbackRate;
  }, [playbackRate]);

  return (
    <video
      ref={videoRef}
      className="w-full h-full object-contain"
      poster={poster}
      playsInline
      controls={false} // We'll use custom controls
      crossOrigin="anonymous"
    />
  );
}
