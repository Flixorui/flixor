import { useEffect, useRef, useState, useCallback, useMemo } from 'react';
import { VideoSeekSlider } from 'react-video-seek-slider';
import PlexVideoPlayer, { PlayerStats } from './PlexVideoPlayer';
import { apiClient } from '@/services/api';
import '../styles/player.css';
import { Replay10Icon, Forward10Icon } from '@/components/icons/Replay10';
import {
  PlexConfig,
  plexMetadata,
  plexPlayQueue,
  plexChildren,
} from '@/services/plex';
import {
  plexStreamUrl,
  plexTimelineUpdate,
  plexUniversalDecision,
  plexUpdateAudioStream,
  plexUpdateSubtitleStream,
  plexTranscodeImageUrl,
  plexKillAllTranscodeSessions,
  plexPartUrl,
  resetPlexSessionId,
} from '@/services/plex';
import { backendStreamUrl, backendUpdateProgress } from '@/services/plex_backend_player';
import {
  canDirectPlay,
  canDirectStream,
  getQualityOptions,
  getStreamDecision,
  getSubtitleOptions,
  getAudioOptions,
  getExternalSubtitleUrl,
  hasDolbyVision,
} from '@/services/plex_decision';
import { traktScrobbler } from '@/services/traktScrobble';
import PlaybackStatsHUD, { usePlaybackStats } from '@/components/PlaybackStatsHUD';

interface PlayerMarker {
  type: 'intro' | 'credits' | 'commercial';
  startTimeOffset: number;
  endTimeOffset: number;
  final?: boolean;
}

interface Stream {
  id: string;
  index: number;
  streamType: number; // 1: video, 2: audio, 3: subtitle
  codec?: string;
  language?: string;
  languageCode?: string;
  languageTag?: string;
  selected?: boolean;
  default?: boolean;
  forced?: boolean;
  displayTitle?: string;
  extendedDisplayTitle?: string;
  // Video stream fields
  bitDepth?: number;
  chromaSubsampling?: string;
  colorPrimaries?: string;
  colorRange?: string;
  colorSpace?: string;
  colorTrc?: string;
  frameRate?: number;
  profile?: string;
  bitrate?: number;
  width?: number;
  height?: number;
  // Audio stream fields
  channels?: number;
  audioChannelLayout?: string;
  samplingRate?: number;
}

interface Media {
  id: string;
  duration: number;
  bitrate: number;
  width: number;
  height: number;
  videoResolution: string;
  videoCodec: string;
  videoProfile?: string;
  videoFrameRate?: string;
  audioCodec: string;
  audioChannels?: number;
  container: string;
  // Extended video fields
  bitDepth?: number;
  colorPrimaries?: string;
  colorSpace?: string;
  colorTrc?: string;
  chromaSubsampling?: string;
  Part: Array<{
    id: string;
    key: string;
    duration: number;
    size: number;
    indexes?: boolean;
    Stream: Stream[];
    // Decision info (when transcoding)
    decision?: 'directplay' | 'transcode' | 'copy';
  }>;
  // Playback decision info
  selected?: boolean;
}

interface PlexMetadata {
  ratingKey: string;
  key: string;
  guid: string;
  type: 'movie' | 'episode';
  title: string;
  grandparentTitle?: string;
  parentTitle?: string;
  grandparentRatingKey?: string;
  parentRatingKey?: string;
  contentRating?: string;
  summary?: string;
  index?: number;
  parentIndex?: number;
  year?: number;
  thumb?: string;
  art?: string;
  duration: number;
  viewOffset?: number;
  viewCount?: number;
  Marker?: PlayerMarker[];
  Media?: Media[];
  librarySectionID?: string;
}

interface AdvancedPlayerProps {
  plexConfig: PlexConfig;
  itemId: string;
  onBack?: () => void;
  onNext?: (nextId: string) => void;
}

const QUALITY_LEVELS = {
  '4k': [
    { label: '4K High (40 Mbps)', value: 40000 },
    { label: '4K Medium (30 Mbps)', value: 30000 },
    { label: '4K Low (20 Mbps)', value: 20000 },
    { label: '1080p High (20 Mbps)', value: 20000 },
    { label: '1080p Medium (12 Mbps)', value: 12000 },
    { label: '1080p Low (10 Mbps)', value: 10000 },
    { label: '720p High (4 Mbps)', value: 4000 },
    { label: '720p Medium (3 Mbps)', value: 3000 },
    { label: '720p Low (2 Mbps)', value: 2000 },
    { label: '480p (1.5 Mbps)', value: 1500 },
    { label: '360p (0.75 Mbps)', value: 750 },
    { label: '240p (0.3 Mbps)', value: 300 },
  ],
  '1080': [
    { label: '1080p High (20 Mbps)', value: 20000 },
    { label: '1080p Medium (12 Mbps)', value: 12000 },
    { label: '1080p Low (10 Mbps)', value: 10000 },
    { label: '720p High (4 Mbps)', value: 4000 },
    { label: '720p Medium (3 Mbps)', value: 3000 },
    { label: '720p Low (2 Mbps)', value: 2000 },
    { label: '480p (1.5 Mbps)', value: 1500 },
    { label: '360p (0.75 Mbps)', value: 750 },
    { label: '240p (0.3 Mbps)', value: 300 },
  ],
  '720': [
    { label: '720p High (4 Mbps)', value: 4000 },
    { label: '720p Medium (3 Mbps)', value: 3000 },
    { label: '720p Low (2 Mbps)', value: 2000 },
    { label: '480p (1.5 Mbps)', value: 1500 },
    { label: '360p (0.75 Mbps)', value: 750 },
    { label: '240p (0.3 Mbps)', value: 300 },
  ],
};

export default function AdvancedPlayer({ plexConfig, itemId, onBack, onNext }: AdvancedPlayerProps) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const seekSliderRef = useRef<any>(null);
  const sessionId = useRef<string>(Math.random().toString(36).substring(2, 15));
  // Refs for cleanup effect (to access current values on unmount)
  const metadataRef = useRef<PlexMetadata | null>(null);
  const currentTimeRef = useRef<number>(0);
  const durationRef = useRef<number>(0);
  // Ref for throttling time updates to reduce React re-render overhead
  const lastTimeUpdateRef = useRef<number>(0);

  const [metadata, setMetadata] = useState<PlexMetadata | null>(null);
  const [streamUrl, setStreamUrl] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // Playback state
  const [playing, setPlaying] = useState(true);
  const [duration, setDuration] = useState(0);
  const [currentTime, setCurrentTime] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [buffering, setBuffering] = useState(false);
  const [exiting, setExiting] = useState(false);
  const [volume, setVolume] = useState(() => {
    const saved = localStorage.getItem('player_volume');
    return saved ? parseFloat(saved) : 1;
  });
  const lastVolRef = useRef<number>(parseFloat(localStorage.getItem('player_volume_last') || '0.8') || 0.8);
  const [playbackRate, setPlaybackRate] = useState(1);
  const [initialStartAt, setInitialStartAt] = useState<number | undefined>(undefined);
  const volumeSliderRef = useRef<HTMLInputElement | null>(null); // legacy (removed input), kept for blur calls
  const volTrackRef = useRef<HTMLDivElement | null>(null);
  const [isDraggingVolume, setIsDraggingVolume] = useState(false);
  const isDraggingVolumeRef = useRef(false);
  useEffect(() => { isDraggingVolumeRef.current = isDraggingVolume; }, [isDraggingVolume]);
  const [volumeSliderKey, setVolumeSliderKey] = useState(0);
  const [showSpeed, setShowSpeed] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState<boolean>(!!document.fullscreenElement);
  
  // UI state
  const [showControls, setShowControls] = useState(true);
  const [showSettings, setShowSettings] = useState(false);
  const [settingsTab, setSettingsTab] = useState<'quality' | 'audio' | 'subtitles'>('quality');
  const [showVolumeSlider, setShowVolumeSlider] = useState(false);
  const volumePopoverRef = useRef<HTMLDivElement | null>(null);
  const volumeButtonRef = useRef<HTMLButtonElement | null>(null);
  const episodesPanelRef = useRef<HTMLDivElement | null>(null);
  const episodesButtonRef = useRef<HTMLButtonElement | null>(null);
  
  // Quality settings
  const [quality, setQuality] = useState<string | number>(() => {
    const saved = localStorage.getItem('player_quality');
    // Parse as number if it's a numeric string, otherwise keep as string
    if (saved && saved !== 'original' && !isNaN(Number(saved))) {
      return Number(saved);
    }
    return saved || 'original';
  });
  
  // Stream selections
  const [selectedAudioStream, setSelectedAudioStream] = useState<string | null>(null);
  const [selectedSubtitleStream, setSelectedSubtitleStream] = useState<string | null>('0');
  const [qualityOptions, setQualityOptions] = useState<any[]>([]);
  const [audioOptions, setAudioOptions] = useState<any[]>([]);
  const [subtitleOptions, setSubtitleOptions] = useState<any[]>([]);

  // Play queue
  const [playQueue, setPlayQueue] = useState<PlexMetadata[]>([]);
  const [nextEpisodeCountdown, setNextEpisodeCountdown] = useState<number | null>(null);
  const [showNextHover, setShowNextHover] = useState(false);
  const [showEpisodes, setShowEpisodes] = useState(false);
  const [seasonEpisodes, setSeasonEpisodes] = useState<PlexMetadata[] | null>(null);
  const [episodesLoading, setEpisodesLoading] = useState(false);
  const nextEpisode = useMemo(() => {
    if (playQueue && playQueue[1]) return playQueue[1];
    if (metadata?.type === 'episode' && seasonEpisodes && seasonEpisodes.length > 0) {
      const idx = seasonEpisodes.findIndex(ep => String(ep.ratingKey) === String(metadata.ratingKey));
      if (idx >= 0 && seasonEpisodes[idx + 1]) return seasonEpisodes[idx + 1];
    }
    return null;
  }, [playQueue, seasonEpisodes, metadata]);

  // Codec error handling
  const [codecErrorMessage, setCodecErrorMessage] = useState<string | null>(null);
  const [retryingWithTranscode, setRetryingWithTranscode] = useState(false);
  const hasRetriedWithTranscode = useRef(false);

  // Stats HUD
  const [showStats, setShowStats] = useState(false);
  // Real-time playback stats - only collect when HUD is visible to avoid React re-render overhead
  const realTimeStats = usePlaybackStats(videoRef as React.RefObject<HTMLVideoElement>, undefined, showStats);
  const [isTranscoding, setIsTranscoding] = useState(false);
  const [videoDecision, setVideoDecision] = useState<'directplay' | 'copy' | 'transcode'>('directplay');
  const [audioDecision, setAudioDecision] = useState<'directplay' | 'copy' | 'transcode'>('directplay');
  const [playerStats, setPlayerStats] = useState<PlayerStats>({});

  // Timeline update interval
  const timelineIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const pingIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Trakt scrobbling
  const scrobbleStarted = useRef(false);
  const lastScrobbleState = useRef<'playing' | 'paused' | null>(null);

  // Start/update Trakt scrobble based on playback state
  useEffect(() => {
    if (!metadata || loading) return;

    const progress = duration > 0 ? Math.round((currentTime / duration) * 100) : 0;

    // Start scrobble when playback begins
    if (playing && !scrobbleStarted.current) {
      const mediaInfo = traktScrobbler.convertPlexToTraktMedia(metadata);
      if (mediaInfo) {
        traktScrobbler.startScrobble(mediaInfo, progress).then(success => {
          if (success) {
            scrobbleStarted.current = true;
            lastScrobbleState.current = 'playing';
          }
        });
      }
    }

    // Handle play/pause state changes after scrobble started
    if (scrobbleStarted.current && lastScrobbleState.current !== (playing ? 'playing' : 'paused')) {
      if (playing) {
        traktScrobbler.resumeScrobble(progress);
        lastScrobbleState.current = 'playing';
      } else {
        traktScrobbler.pauseScrobble(progress);
        lastScrobbleState.current = 'paused';
      }
    }

    // Update progress periodically (every 30 seconds approx)
    if (scrobbleStarted.current && playing) {
      traktScrobbler.updateProgress(progress);
    }
  }, [metadata, playing, loading, currentTime, duration]);

  // Stop scrobble when component unmounts
  useEffect(() => {
    return () => {
      if (scrobbleStarted.current && duration > 0) {
        const progress = Math.round((currentTime / duration) * 100);
        traktScrobbler.stopScrobble(progress);
        scrobbleStarted.current = false;
        lastScrobbleState.current = null;
      }
    };
  }, []);

  // Keep refs in sync with state for cleanup effect
  useEffect(() => {
    metadataRef.current = metadata;
  }, [metadata]);
  useEffect(() => {
    currentTimeRef.current = currentTime;
    durationRef.current = duration;
  }, [currentTime, duration]);

  // Cleanup: send stopped status and kill transcode session when component unmounts
  useEffect(() => {
    return () => {
      const meta = metadataRef.current;
      const time = currentTimeRef.current;
      const dur = durationRef.current;
      if (meta && dur > 0) {
        // Send stopped timeline update to Plex
        backendUpdateProgress(meta.ratingKey, time * 1000, dur * 1000, 'stopped').catch(() => {
          // Fallback to direct Plex call
          try {
            plexTimelineUpdate(plexConfig, meta.ratingKey, time * 1000, dur * 1000, 'stopped');
          } catch {}
        });
      }
      // Kill any active transcode sessions
      plexKillAllTranscodeSessions(plexConfig).catch(() => {});
    };
  }, [plexConfig]);

  // Persist volume and track last non-zero
  useEffect(() => {
    try {
      localStorage.setItem('player_volume', String(volume));
      if (volume > 0) {
        lastVolRef.current = volume;
        localStorage.setItem('player_volume_last', String(volume));
      }
      const v = videoRef.current; if (v) v.volume = Math.max(0, Math.min(1, volume));
    } catch {}
  }, [volume]);

  // Keyboard shortcuts for volume
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'm' || e.key === 'M') {
        e.preventDefault();
        setVolume((v) => v === 0 ? (parseFloat(localStorage.getItem('player_volume_last')||'0.8')||0.8) : 0);
      } else if (e.key === 'ArrowUp') {
        e.preventDefault(); setVolume((v)=> Math.min(1, v + 0.05));
      } else if (e.key === 'ArrowDown') {
        e.preventDefault(); setVolume((v)=> Math.max(0, v - 0.05));
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // Ensure release on any global pointer-up (covers Safari missing mouseup outside window)
  useEffect(() => {
    const release = () => {
      if (!isDraggingVolume) return;
      setIsDraggingVolume(false);
      try { volumeSliderRef.current?.blur(); } catch {}
      // Force remount to drop any stuck active state in WebKit
      setVolumeSliderKey((k) => k + 1);
    };

    window.addEventListener('mouseup', release);
    window.addEventListener('pointerup', release as any);
    window.addEventListener('touchend', release as any);
    window.addEventListener('dragend', release);
    window.addEventListener('blur', release);
    // Detect cursor leaving window (Safari sometimes misses mouseup)
    const onOut = (e: MouseEvent) => {
      const to = (e.relatedTarget || (e as any).toElement) as Node | null;
      if (!to) release();
    };
    window.addEventListener('mouseout', onOut);
    return () => {
      window.removeEventListener('mouseup', release);
      window.removeEventListener('pointerup', release as any);
      window.removeEventListener('touchend', release as any);
      window.removeEventListener('dragend', release);
      window.removeEventListener('blur', release);
      window.removeEventListener('mouseout', onOut);
    };
  }, [isDraggingVolume]);

  // Close episodes panel when clicking outside
  useEffect(() => {
    if (!showEpisodes) return;
    const onDocDown = (e: MouseEvent | TouchEvent) => {
      const el = e.target as Node;
      // Ignore clicks on the episodes toggle button itself
      if (episodesButtonRef.current && episodesButtonRef.current.contains(el)) return;
      if (episodesPanelRef.current && !episodesPanelRef.current.contains(el)) {
        setShowEpisodes(false);
      }
    };
    document.addEventListener('mousedown', onDocDown);
    document.addEventListener('touchstart', onDocDown as any, { passive: true } as any);
    return () => {
      document.removeEventListener('mousedown', onDocDown);
      document.removeEventListener('touchstart', onDocDown as any);
    };
  }, [showEpisodes]);

  // Custom volume slider handlers (to avoid Safari range issues)
  const updateVolumeFromEvent = useCallback((ev: MouseEvent | TouchEvent | PointerEvent) => {
    const track = volTrackRef.current; if (!track) return;
    const rect = track.getBoundingClientRect();
    let clientX = 0;
    if ((ev as TouchEvent).touches && (ev as TouchEvent).touches.length) {
      clientX = (ev as TouchEvent).touches[0].clientX;
    } else if ((ev as any).clientX !== undefined) {
      clientX = (ev as MouseEvent).clientX;
    }
    let ratio = (clientX - rect.left) / rect.width;
    ratio = Math.max(0, Math.min(1, ratio));
    setVolume(ratio);
  }, []);

  const endVolDrag = useCallback(() => {
    setIsDraggingVolume(false);
    try { volumeSliderRef.current?.blur(); } catch {}
    try { document.body.style.userSelect = ''; } catch {}
    window.removeEventListener('mousemove', onVolMove as any);
    window.removeEventListener('pointermove', onVolMove as any);
    window.removeEventListener('touchmove', onVolMove as any);
    window.removeEventListener('mouseup', endVolDrag);
    window.removeEventListener('pointerup', endVolDrag as any);
    window.removeEventListener('touchend', endVolDrag as any);
  }, []);

  const onVolMove = useCallback((e: any) => {
    if (!isDraggingVolumeRef.current) return;
    try { e.preventDefault?.(); } catch {}
    updateVolumeFromEvent(e);
  }, []);

  const startVolDrag = useCallback((e: any) => {
    setIsDraggingVolume(true);
    try { e.preventDefault?.(); } catch {}
    const nat = e?.nativeEvent || e;
    updateVolumeFromEvent(nat);
    try { if (nat?.target?.setPointerCapture && nat.pointerId != null) nat.target.setPointerCapture(nat.pointerId); } catch {}
    try { document.body.style.userSelect = 'none'; } catch {}
    window.addEventListener('mousemove', onVolMove as any, { passive: false } as any);
    window.addEventListener('pointermove', onVolMove as any, { passive: false } as any);
    window.addEventListener('touchmove', onVolMove as any, { passive: false } as any);
    window.addEventListener('mouseup', endVolDrag, { passive: true } as any);
    window.addEventListener('pointerup', endVolDrag as any, { passive: true } as any);
    window.addEventListener('touchend', endVolDrag as any, { passive: true } as any);
  }, [endVolDrag]);

  // Close volume popover when clicking outside
  useEffect(() => {
    if (!showVolumeSlider) return;
    const onDocPointerDown = (e: MouseEvent | TouchEvent) => {
      const el = e.target as Node;
      if (!volumePopoverRef.current) return;
      // Ignore clicks on the toggle button itself
      if (volumeButtonRef.current && volumeButtonRef.current.contains(el)) return;
      if (!volumePopoverRef.current.contains(el)) {
        setShowVolumeSlider(false);
        setIsDraggingVolume(false);
        try { volumeSliderRef.current?.blur(); } catch {}
      }
    };
    document.addEventListener('mousedown', onDocPointerDown);
    document.addEventListener('pointerdown', onDocPointerDown as any);
    document.addEventListener('touchstart', onDocPointerDown as any, { passive: true } as any);
    return () => {
      document.removeEventListener('mousedown', onDocPointerDown);
      document.removeEventListener('pointerdown', onDocPointerDown as any);
      document.removeEventListener('touchstart', onDocPointerDown as any);
    };
  }, [showVolumeSlider]);

  // Persist and restore playback rate
  useEffect(() => {
    try {
      const saved = localStorage.getItem('player_rate');
      if (saved) {
        const num = parseFloat(saved);
        if (!Number.isNaN(num) && num > 0) setPlaybackRate(num);
      }
    } catch {}
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    try { localStorage.setItem('player_rate', String(playbackRate)); } catch {}
  }, [playbackRate]);

  // Detect transcoding status from stream URL and quality setting
  useEffect(() => {
    if (!streamUrl || !metadata) {
      setIsTranscoding(false);
      setVideoDecision('directplay');
      setAudioDecision('directplay');
      return;
    }

    // Check for transcode indicators in URL
    const isTranscodeUrl = streamUrl.includes('/transcode/') ||
                           streamUrl.includes('directPlay=0') ||
                           streamUrl.includes('directStream=0');

    // Determine decisions based on URL pattern and quality setting
    // If URL contains /transcode/ and quality is not 'original', it's transcoding
    // If quality is 'original' but URL has transcode, it's likely direct stream (container remux)
    const isOriginalQuality = quality === 'original';
    const media = metadata.Media?.[0];
    const videoCodec = media?.videoCodec?.toLowerCase() || '';

    // Check if browser can play the codec directly
    const canPlayCodec = ['h264', 'avc', 'vp8', 'vp9', 'av1'].some(c => videoCodec.includes(c));

    if (!isTranscodeUrl) {
      // Not using transcode path - likely direct play
      setIsTranscoding(false);
      setVideoDecision('directplay');
      setAudioDecision('directplay');
    } else if (isOriginalQuality) {
      // Using transcode path but original quality - direct stream (container remux, video copied)
      setIsTranscoding(false);
      setVideoDecision('copy'); // Video is copied, not transcoded
      // Audio might be transcoded if not a compatible format
      const audioCodec = media?.audioCodec?.toLowerCase() || '';
      const audioNeedsTranscode = ['dts', 'truehd', 'flac'].some(c => audioCodec.includes(c));
      setAudioDecision(audioNeedsTranscode ? 'transcode' : 'copy');
    } else {
      // Using transcode path with specific quality - full transcode
      setIsTranscoding(true);
      setVideoDecision('transcode');
      setAudioDecision('transcode');
    }
  }, [streamUrl, metadata, quality]);

  // Click anywhere on video to toggle play/pause (ignore controls)
  function handleBackdropClick(e: React.MouseEvent) {
    const el = e.target as HTMLElement;
    if (el.closest('.player-controls') || el.closest('button') || el.closest('input') || el.closest('select') || el.closest('textarea')) return;
    const v = videoRef.current; if (!v) return;
    if (playing) { v.pause(); setPlaying(false); } else { v.play().catch(()=>{}); setPlaying(true); }
  }

  // Load metadata and initialize player
  useEffect(() => {
    if (!itemId) return;

    const loadContent = async () => {
      try {
        setLoading(true);
        setError(null);
        hasRetriedWithTranscode.current = false; // Reset retry flag when loading new content
        
        // Load metadata
        // Prefer backend for metadata; fallback to direct if it fails
        const metaResponse = await (await import('@/services/plex_backend')).plexBackendMetadata(itemId);
        const meta = metaResponse.MediaContainer.Metadata[0] as PlexMetadata;
        setMetadata(meta);
        // Record initial start time once per item
        try {
          const start = meta.viewOffset ? Math.max(0, Math.floor(meta.viewOffset / 1000)) : undefined;
          const durSec = meta.duration ? Math.floor(meta.duration / 1000) : undefined;
          // If item was fully watched (>=95%), start from beginning
          const fromStart = (start !== undefined && durSec && durSec > 0 && start / durSec >= 0.95) ? 0 : start;
          console.log('[Resume Debug] viewOffset from metadata:', meta.viewOffset, 'start (seconds):', start, 'fromStart:', fromStart);
          setInitialStartAt(fromStart);
        } catch {}

        // Fetch markers (intro/credits) if available from Plex for this item (backend session avoids token issues)
        try {
          const { plexBackendDir } = await import('@/services/plex_backend');
          const mjson: any = await plexBackendDir(`/library/metadata/${itemId}?includeMarkers=1`);
          const m2 = mjson?.MediaContainer?.Metadata?.[0];
          if (m2?.Marker && Array.isArray(m2.Marker)) {
            setMetadata(prev => prev ? { ...prev, Marker: m2.Marker } as PlexMetadata : prev);
          }
        } catch {}
        
        // Get quality, audio, and subtitle options
        const qualOpts = getQualityOptions(meta);
        const audioOpts = getAudioOptions(meta);
        const subOpts = getSubtitleOptions(meta);
        
        setQualityOptions(qualOpts);
        setAudioOptions(audioOpts);
        setSubtitleOptions(subOpts);
        
        // Set default selections
        const defaultAudio = audioOpts.find((a: any) => a.selected || a.default);
        if (defaultAudio) setSelectedAudioStream(defaultAudio.id);
        
        const defaultSub = subOpts.find(s => s.selected);
        setSelectedSubtitleStream(defaultSub ? defaultSub.id : '0');
        
        // Check for Dolby Vision
        const hasDV = hasDolbyVision(meta);
        let effectiveQuality = quality;

        // If Dolby Vision is detected and quality is original, auto-switch to highest transcoded quality
        if (hasDV && quality === 'original' && !hasRetriedWithTranscode.current) {
          console.warn('Dolby Vision detected - automatically switching to transcoded quality');
          setCodecErrorMessage('Dolby Vision detected - using transcoded quality for compatibility');

          const transcodedOptions = qualOpts.filter(opt => opt.value !== 'original');
          effectiveQuality = transcodedOptions[0]?.value || 20000;
          setQuality(effectiveQuality);
          localStorage.setItem('player_quality', effectiveQuality.toString());

          // Clear message after delay
          setTimeout(() => setCodecErrorMessage(null), 5000);
        }

        // Build stream URL using the same logic as commit 147b572 (direct, not proxied)
        const decision = getStreamDecision(meta, {
          quality: effectiveQuality,
          directPlay: effectiveQuality === 'original' && !hasDV,
          audioStreamId: selectedAudioStream || undefined,
          subtitleStreamId: selectedSubtitleStream || undefined,
        });

        // Call decision API to see what Plex will actually do
        const plexDecision = await plexUniversalDecision(plexConfig, itemId, {
          maxVideoBitrate: effectiveQuality === 'original' ? undefined : Number(effectiveQuality),
          protocol: 'dash',
          autoAdjustQuality: false,
          directPlay: decision.directPlay,
          directStream: decision.directStream,
          audioStreamID: selectedAudioStream || undefined,
          subtitleStreamID: selectedSubtitleStream || undefined,
        });

        // Generate stream URL based on actual Plex decision
        let url: string;
        if (plexDecision.canDirectPlay && meta.Media?.[0]?.Part?.[0]?.key && !hasDV) {
          url = plexPartUrl(plexConfig.baseUrl, plexConfig.token, meta.Media[0].Part[0].key);
        } else {
          url = plexStreamUrl(plexConfig, itemId, {
            maxVideoBitrate: effectiveQuality === 'original' ? undefined : Number(effectiveQuality),
            protocol: 'dash',
            autoAdjustQuality: false,
            directPlay: false,
            directStream: plexDecision.willDirectStream || false,
            audioStreamID: selectedAudioStream || undefined,
            subtitleStreamID: selectedSubtitleStream || undefined,
          });
        }
        setStreamUrl(url);
        
        // Load play queue and season episodes for TV content
        if (meta.type === 'episode') {
          try {
            const queue = await plexPlayQueue(plexConfig, itemId);
            if (queue.MediaContainer?.Metadata) {
              setPlayQueue(queue.MediaContainer.Metadata);
            }
          } catch (err) {
            console.warn('Failed to load play queue:', err);
          }
          // Fetch episodes in current season (parentRatingKey)
          try {
            if (meta.parentRatingKey) {
              setEpisodesLoading(true);
              const chJson: any = await plexChildren(plexConfig, meta.parentRatingKey);
              const eps: PlexMetadata[] = (chJson?.MediaContainer?.Metadata || []) as PlexMetadata[];
              setSeasonEpisodes(eps);
            } else {
              setSeasonEpisodes(null);
            }
          } catch (err) {
            console.warn('Failed to load season episodes:', err);
            setSeasonEpisodes(null);
          } finally {
            setEpisodesLoading(false);
          }
        }
        
        setLoading(false);
      } catch (err) {
        console.error('Failed to load content:', err);
        setError(err instanceof Error ? err.message : 'Failed to load content');
        setLoading(false);
      }
    };
    
    loadContent();
  }, [itemId, plexConfig]);

  // Timeline updates
  useEffect(() => {
    if (!metadata || !duration) return;

    const updateTimeline = () => {
      const state = buffering ? 'buffering' : playing ? 'playing' : 'paused';
      // Keep backend for progress updates, pass isTranscoding for proper Plex dashboard reporting
      backendUpdateProgress(metadata.ratingKey, currentTime * 1000, duration * 1000, state as any, isTranscoding).catch(console.warn);
    };

    // Initial update
    updateTimeline();

    // Set up interval
    timelineIntervalRef.current = setInterval(updateTimeline, 5000);

    return () => {
      if (timelineIntervalRef.current) {
        clearInterval(timelineIntervalRef.current);
      }
    };
  }, [metadata, currentTime, duration, playing, buffering, plexConfig, isTranscoding]);

  // Ping interval - removed as not needed based on NevuForPlex

  // Controls auto-hide
  // Cursor auto-hide state
  const [cursorHidden, setCursorHidden] = useState(false);

  useEffect(() => {
    let timeout: ReturnType<typeof setTimeout>;

    const handleMouseMove = () => {
      setShowControls(true);
      setCursorHidden(false);
      clearTimeout(timeout);
      if (playing && !showEpisodes && !showNextHover && nextEpisodeCountdown === null) {
        timeout = setTimeout(() => {
          setShowControls(false);
          setCursorHidden(true);
        }, 3000);
      }
    };

    const handleMouseLeave = () => {
      if (playing && !showEpisodes && !showNextHover && nextEpisodeCountdown === null) {
        timeout = setTimeout(() => {
          setShowControls(false);
          setCursorHidden(true);
        }, 1000);
      }
    };

    document.addEventListener('mousemove', handleMouseMove);
    containerRef.current?.addEventListener('mouseleave', handleMouseLeave);

    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      containerRef.current?.removeEventListener('mouseleave', handleMouseLeave);
      clearTimeout(timeout);
    };
  }, [playing, showEpisodes, showNextHover, nextEpisodeCountdown]);

  // Wake Lock to prevent screen sleep during playback
  useEffect(() => {
    let wakeLock: WakeLockSentinel | null = null;

    const requestWakeLock = async () => {
      if (!('wakeLock' in navigator)) return;
      try {
        wakeLock = await navigator.wakeLock.request('screen');
        console.log('Wake Lock active');
      } catch (err) {
        console.warn('Wake Lock request failed:', err);
      }
    };

    const releaseWakeLock = async () => {
      if (wakeLock) {
        try {
          await wakeLock.release();
          wakeLock = null;
          console.log('Wake Lock released');
        } catch {}
      }
    };

    // Request wake lock when playing, release when paused
    if (playing && !loading) {
      requestWakeLock();
    } else {
      releaseWakeLock();
    }

    // Handle visibility change - re-request when tab becomes visible
    const handleVisibilityChange = async () => {
      if (document.visibilityState === 'visible' && playing && !loading) {
        await requestWakeLock();
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      releaseWakeLock();
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [playing, loading]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyPress = (e: KeyboardEvent) => {
      const video = videoRef.current;
      if (!video) return;
      
      switch (e.key) {
        case ' ':
        case 'k':
          e.preventDefault();
          if (video) {
            if (playing) {
              video.pause();
            } else {
              video.play().catch(err => console.warn('Play failed:', err));
            }
          }
          setPlaying(p => !p);
          break;
        case 'Escape':
          if (showEpisodes || showNextHover) {
            setShowEpisodes(false);
            setShowNextHover(false);
            setShowControls(true);
            e.preventDefault();
            return;
          }
          break;
        case 'ArrowLeft':
        case 'j':
          video.currentTime = Math.max(0, currentTime - 10);
          break;
        case 'ArrowRight':
        case 'l':
          video.currentTime = Math.min(duration, currentTime + 10);
          break;
        case 'ArrowUp':
          setVolume(v => Math.min(1, v + 0.1));
          break;
        case 'ArrowDown':
          setVolume(v => Math.max(0, v - 0.1));
          break;
        case 'f':
          toggleFullscreen();
          break;
        case 'm':
          setVolume(v => v > 0 ? 0 : 1);
          break;
        case 's':
          skipCurrentMarker();
          break;
        case 'i':
          e.preventDefault();
          setShowStats(s => !s);
          break;
      }
    };

    document.addEventListener('keydown', handleKeyPress);
    return () => document.removeEventListener('keydown', handleKeyPress);
  }, [currentTime, duration, showEpisodes, showNextHover]);

  // Volume persistence
  useEffect(() => {
    localStorage.setItem('player_volume', volume.toString());
  }, [volume]);

  // Quality change handler - cleanly recreates the player with new settings
  const handleQualityChange = useCallback(async (newQuality: string | number) => {
    if (!metadata || !itemId) return;

    try {
      const currentPos = currentTime;

      // 1. Send "stopped" timeline update to clear session from Plex dashboard
      try {
        await backendUpdateProgress(metadata.ratingKey, currentPos * 1000, duration * 1000, 'stopped', isTranscoding);
      } catch {
        try { await plexTimelineUpdate(plexConfig, metadata.ratingKey, currentPos * 1000, duration * 1000, 'stopped'); } catch {}
      }

      // 2. Stop existing transcode session and reset session ID
      await plexKillAllTranscodeSessions(plexConfig);
      resetPlexSessionId();

      // 3. Update quality setting
      setQuality(newQuality);
      localStorage.setItem('player_quality', newQuality.toString());

      // 4. Clear stream URL to unmount/reset player
      setStreamUrl('');
      setLoading(true);

      // 5. Small delay for cleanup
      await new Promise(resolve => setTimeout(resolve, 300));

      // 6. Get Plex decision for new quality
      const decision = getStreamDecision(metadata, {
        quality: newQuality,
        directPlay: newQuality === 'original',
        audioStreamId: selectedAudioStream || undefined,
        subtitleStreamId: selectedSubtitleStream || undefined,
      });

      const plexDecision = await plexUniversalDecision(plexConfig, itemId, {
        maxVideoBitrate: newQuality === 'original' ? undefined : Number(newQuality),
        protocol: 'dash',
        autoAdjustQuality: false,
        directPlay: decision.directPlay,
        directStream: decision.directStream,
        audioStreamID: selectedAudioStream || undefined,
        subtitleStreamID: selectedSubtitleStream || undefined,
      });

      // 7. Generate new stream URL and determine transcoding state
      let url: string;
      let newIsTranscoding = false;
      let newVideoDecision: 'directplay' | 'copy' | 'transcode' = 'directplay';
      let newAudioDecision: 'directplay' | 'copy' | 'transcode' = 'directplay';

      if (plexDecision.canDirectPlay && metadata.Media?.[0]?.Part?.[0]?.key) {
        url = plexPartUrl(plexConfig.baseUrl, plexConfig.token, metadata.Media[0].Part[0].key);
        newIsTranscoding = false;
        newVideoDecision = 'directplay';
        newAudioDecision = 'directplay';
      } else {
        url = plexStreamUrl(plexConfig, itemId, {
          maxVideoBitrate: newQuality === 'original' ? undefined : Number(newQuality),
          protocol: 'dash',
          autoAdjustQuality: false,
          directPlay: false,
          directStream: plexDecision.willDirectStream || false,
          audioStreamID: selectedAudioStream || undefined,
          subtitleStreamID: selectedSubtitleStream || undefined,
        });

        // Determine transcoding state based on quality
        if (newQuality === 'original') {
          // Direct stream - video copied, audio might transcode
          newIsTranscoding = false;
          newVideoDecision = 'copy';
          const audioCodec = metadata.Media?.[0]?.audioCodec?.toLowerCase() || '';
          const audioNeedsTranscode = ['dts', 'truehd', 'flac'].some(c => audioCodec.includes(c));
          newAudioDecision = audioNeedsTranscode ? 'transcode' : 'copy';
        } else {
          // Full transcode
          newIsTranscoding = true;
          newVideoDecision = 'transcode';
          newAudioDecision = 'transcode';
        }
      }

      // 8. Set transcoding state BEFORE setting stream URL to ensure correct timeline reporting
      setIsTranscoding(newIsTranscoding);
      setVideoDecision(newVideoDecision);
      setAudioDecision(newAudioDecision);

      // 9. Set resume position and new stream URL to recreate player
      setInitialStartAt(currentPos);
      setStreamUrl(url);
      setLoading(false);

    } catch (err) {
      console.error('Failed to change quality:', err);
      setLoading(false);
    }
  }, [metadata, itemId, currentTime, duration, isTranscoding, plexConfig, selectedAudioStream, selectedSubtitleStream]);

  // Audio stream change
  const handleAudioStreamChange = useCallback(async (streamId: string) => {
    if (!metadata?.Media?.[0]?.Part?.[0]) return;

    try {
      const currentPos = currentTime;
      const partId = metadata.Media[0].Part[0].id;

      // 1. Send "stopped" timeline update to clear session from Plex dashboard
      try {
        await backendUpdateProgress(metadata.ratingKey, currentPos * 1000, duration * 1000, 'stopped', isTranscoding);
      } catch {
        try { await plexTimelineUpdate(plexConfig, metadata.ratingKey, currentPos * 1000, duration * 1000, 'stopped'); } catch {}
      }

      // 2. Stop existing transcode session and reset session ID
      await plexKillAllTranscodeSessions(plexConfig);
      resetPlexSessionId();

      // 3. Update audio stream selection on the part
      await plexUpdateAudioStream(plexConfig, partId, streamId);
      setSelectedAudioStream(streamId);

      // 4. Clear stream URL to unmount/reset player
      setStreamUrl('');
      setLoading(true);

      // 5. Small delay for cleanup
      await new Promise(resolve => setTimeout(resolve, 300));

      // 6. Generate new stream URL with new audio
      const decision = getStreamDecision(metadata, {
        quality: quality,
        directPlay: quality === 'original',
        audioStreamId: streamId,
        subtitleStreamId: selectedSubtitleStream || undefined,
      });

      const url = plexStreamUrl(plexConfig, itemId, {
        maxVideoBitrate: quality === 'original' ? undefined : Number(quality),
        protocol: 'dash',
        autoAdjustQuality: false,
        directPlay: decision.directPlay,
        directStream: decision.directStream,
        audioStreamID: streamId,
        subtitleStreamID: selectedSubtitleStream || undefined,
      });

      // 7. Set resume position and new stream URL to recreate player
      setInitialStartAt(currentPos);
      setStreamUrl(url);
      setLoading(false);

    } catch (err) {
      console.error('Failed to change audio stream:', err);
      setLoading(false);
    }
  }, [metadata, itemId, currentTime, duration, isTranscoding, quality, plexConfig, selectedSubtitleStream]);

  // Subtitle stream change - cleanly recreates the player with new settings
  const handleSubtitleStreamChange = useCallback(async (streamId: string) => {
    if (!metadata?.Media?.[0]?.Part?.[0]) return;

    try {
      const currentPos = currentTime;
      const partId = metadata.Media[0].Part[0].id;

      // 1. Send "stopped" timeline update to clear session from Plex dashboard
      try {
        await backendUpdateProgress(metadata.ratingKey, currentPos * 1000, duration * 1000, 'stopped', isTranscoding);
      } catch {
        try { await plexTimelineUpdate(plexConfig, metadata.ratingKey, currentPos * 1000, duration * 1000, 'stopped'); } catch {}
      }

      // 2. Stop existing transcode session and reset session ID
      await plexKillAllTranscodeSessions(plexConfig);
      resetPlexSessionId();

      // 3. Update subtitle stream selection on the part
      await plexUpdateSubtitleStream(plexConfig, partId, streamId);
      setSelectedSubtitleStream(streamId);

      // 4. Clear stream URL to unmount/reset player
      setStreamUrl('');
      setLoading(true);

      // 5. Small delay for cleanup
      await new Promise(resolve => setTimeout(resolve, 300));

      // 6. Generate new stream URL with new subtitle
      const decision = getStreamDecision(metadata, {
        quality: quality,
        directPlay: quality === 'original',
        audioStreamId: selectedAudioStream || undefined,
        subtitleStreamId: streamId,
      });

      const url = plexStreamUrl(plexConfig, itemId, {
        maxVideoBitrate: quality === 'original' ? undefined : Number(quality),
        protocol: 'dash',
        autoAdjustQuality: false,
        directPlay: decision.directPlay,
        directStream: decision.directStream,
        audioStreamID: selectedAudioStream || undefined,
        subtitleStreamID: streamId,
      });

      // 7. Set resume position and new stream URL to recreate player
      setInitialStartAt(currentPos);
      setStreamUrl(url);
      setLoading(false);

    } catch (err) {
      console.error('Failed to change subtitle stream:', err);
      setLoading(false);
    }
  }, [metadata, itemId, currentTime, duration, isTranscoding, quality, plexConfig, selectedAudioStream]);

  // Navigate to Details page for current item (declared early to avoid TDZ)
  const goToDetails = useCallback(async () => {
    const m = metadata;
    if (!m) return;
    try {
      setExiting(true);
      setPlaying(false);
      const v = videoRef.current; if (v) { try { v.pause(); } catch {} }
    } catch {}
    // Send stopped timeline and cleanup BEFORE navigating to ensure Plex dashboard clears
    const time = currentTimeRef.current;
    const dur = durationRef.current;
    if (dur > 0) {
      try {
        await backendUpdateProgress(m.ratingKey, time * 1000, dur * 1000, 'stopped', isTranscoding);
      } catch {
        try { await plexTimelineUpdate(plexConfig, m.ratingKey, time * 1000, dur * 1000, 'stopped'); } catch {}
      }
      try { await plexKillAllTranscodeSessions(plexConfig); } catch {}
    }
    const target = m.type === 'episode' && m.grandparentRatingKey ? `plex:${m.grandparentRatingKey}` : `plex:${m.ratingKey}`;
    window.location.href = `/details/${encodeURIComponent(target)}`;
  }, [metadata, plexConfig, isTranscoding]);

  // Skip current marker
  const skipCurrentMarker = useCallback(() => {
    if (!metadata?.Marker || !videoRef.current) return;
    
    const marker = metadata.Marker.find(m => 
      currentTime * 1000 >= m.startTimeOffset &&
      currentTime * 1000 <= m.endTimeOffset
    );
    
    if (marker) {
      if (marker.type === 'credits') {
        if (metadata.type === 'movie') { goToDetails(); return; }
        if (marker.final && nextEpisode) { onNext?.(String(nextEpisode.ratingKey)); return; }
      }
      // Skip past the marker
      videoRef.current.currentTime = (marker.endTimeOffset / 1000) + 1;
    }
  }, [metadata, currentTime, nextEpisode, onNext, goToDetails]);

  // Toggle fullscreen
  const toggleFullscreen = useCallback(() => {
    if (!document.fullscreenElement) {
      containerRef.current?.requestFullscreen();
    } else {
      document.exitFullscreen();
    }
  }, []);

  // Track fullscreen state for icon swap
  useEffect(() => {
    const onFs = () => setIsFullscreen(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onFs);
    return () => document.removeEventListener('fullscreenchange', onFs);
  }, []);

  // Next episode countdown (credits start if available, else last 30s)
  useEffect(() => {
    if (!metadata?.type || metadata.type !== 'episode') return;
    if (!nextEpisode) { setNextEpisodeCountdown(null); return; }
    if (!duration) { setNextEpisodeCountdown(null); return; }

    const credits = metadata?.Marker?.find(m => m.type === 'credits');
    const triggerStart = credits ? (credits.startTimeOffset / 1000) : Math.max(0, duration - 30);

    if (currentTime >= triggerStart) {
      if (nextEpisodeCountdown === null) setNextEpisodeCountdown(10);
    } else {
      if (nextEpisodeCountdown !== null) setNextEpisodeCountdown(null);
    }
  }, [metadata, duration, currentTime, nextEpisode, nextEpisodeCountdown]);

  useEffect(() => {
    if (nextEpisodeCountdown === null || nextEpisodeCountdown <= 0) return;
    
    const timer = setTimeout(() => {
      if (nextEpisodeCountdown === 1 && nextEpisode) {
        onNext?.(String(nextEpisode.ratingKey));
      } else {
        setNextEpisodeCountdown(c => (c ?? 0) - 1);
      }
    }, 1000);
    
    return () => clearTimeout(timer);
  }, [nextEpisodeCountdown, nextEpisode, onNext]);

  // Get current marker
  const currentMarker = metadata?.Marker?.find(m =>
    currentTime * 1000 >= m.startTimeOffset &&
    currentTime * 1000 <= m.endTimeOffset
  );

  // Format time
  const formatTime = (seconds: number) => {
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    
    if (h > 0) {
      return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
    }
    return `${m}:${s.toString().padStart(2, '0')}`;
  };

  // Memoized callbacks for player - must be defined before any conditional returns
  // Note: We no longer clear initialStartAt here. PlexVideoPlayer uses initialSeekDoneRef
  // to prevent double-seeking, so clearing initialStartAt is unnecessary and causes bugs
  // when the component remounts (React Strict Mode) - the new mount would get undefined startTime.
  const handleTimeUpdate = useCallback((time: number, dur: number) => {
    // Always update refs for accurate values (used for progress reporting, cleanup, etc.)
    currentTimeRef.current = time;
    if (dur && dur > 0) durationRef.current = dur;

    // Throttle React state updates to reduce re-render overhead (update every 200ms max)
    // This significantly reduces dropped frames by avoiding excessive React reconciliation
    const now = performance.now();
    if (now - lastTimeUpdateRef.current >= 200) {
      lastTimeUpdateRef.current = now;
      setCurrentTime(time);
      if (dur && dur > 0) setDuration(dur);
    }
  }, []);

  const handleUserSeek = useCallback(() => {
    endedRef.current = false; // user intent overrides pending end state
  }, []);

  const handleReady = useCallback(() => {
    // console.log('Player ready');
    setBuffering(false);
  }, []);

  const endedRef = useRef(false);
  const headerRetryRef = useRef(false);
  const handleEnded = useCallback(() => {
    if (endedRef.current) return;
    endedRef.current = true;
    if (metadata?.type === 'movie') {
      goToDetails();
      return;
    }
    if (nextEpisode) {
      onNext?.(String(nextEpisode.ratingKey));
    } else if (metadata) {
      plexTimelineUpdate(plexConfig, metadata.ratingKey, duration * 1000, duration * 1000, 'stopped');
      goToDetails();
    }
  }, [nextEpisode, metadata, duration, plexConfig, onNext, goToDetails]);

  // Safety: if we reach the end but 'ended' doesn't fire (some MSE edge cases), trigger once
  useEffect(() => {
    if (!duration) return;
    if (endedRef.current) return;
    if (currentTime >= Math.max(0, duration - 0.25)) {
      if (metadata?.type === 'movie') {
        endedRef.current = true;
        goToDetails();
        return;
      }
      if (nextEpisode) {
        endedRef.current = true;
        onNext?.(String(nextEpisode.ratingKey));
      }
    }
  }, [currentTime, duration, nextEpisode, onNext, metadata, goToDetails]);

  const handleError = useCallback(async (err: string) => {
    console.error('Player error:', err);
    const msg = String(err || '').toLowerCase();
    if (exiting) return; // already leaving; ignore
    // If we're at or near the end of a movie, prefer returning to details rather than retrying
    if (metadata?.type === 'movie' && duration && (currentTime >= duration - 1 || (currentTime / duration) >= 0.95 || (duration - currentTime) <= 30)) {
      goToDetails();
      return;
    }
    // If transcode session header is not available (stale PMS session), try one clean retry
    if (!headerRetryRef.current && (msg.includes('header is not available') || (msg.includes('mpd') && msg.includes('header')))) {
      headerRetryRef.current = true;
      // Send stopped timeline update to clear session from Plex dashboard
      try {
        await backendUpdateProgress(metadata!.ratingKey, currentTime * 1000, duration * 1000, 'stopped', isTranscoding);
      } catch {
        try { await plexTimelineUpdate(plexConfig, metadata!.ratingKey, currentTime * 1000, duration * 1000, 'stopped'); } catch {}
      }
      try {
        await plexKillAllTranscodeSessions(plexConfig);
      } catch {}
      try {
        // Re-generate stream URL from the beginning with same quality settings
        const url = plexStreamUrl(plexConfig, itemId, {
          maxVideoBitrate: quality === 'original' ? undefined : Number(quality),
          protocol: 'dash',
          autoAdjustQuality: false,
          directPlay: false,
          directStream: false,
          audioStreamID: selectedAudioStream || undefined,
          subtitleStreamID: selectedSubtitleStream || undefined,
          forceReload: true,
        });
        // Resume from current position to avoid a restart near the end (e.g., ~22s remaining)
        const resumeSec = Math.max(0, Math.floor(currentTime));
        setInitialStartAt(resumeSec);
        endedRef.current = false;
        setStreamUrl(url);
        setError(null);
        return; // swallow error on first retry
      } catch (e) {
        console.error('Header retry failed:', e);
      }
    }
    setError(err);
  }, [plexConfig, itemId, quality, selectedAudioStream, selectedSubtitleStream]);

  const handleCodecError = useCallback(async (err: string) => {
    console.error('Codec error detected:', err);

    // Only retry once to avoid infinite loops
    if (hasRetriedWithTranscode.current || !metadata || !itemId) {
      setError(err);
      return;
    }

    hasRetriedWithTranscode.current = true;
    setCodecErrorMessage('Dolby Vision Profile 7 not supported. Switching to transcoded quality...');
    setRetryingWithTranscode(true);

    try {
      // Send stopped timeline update to clear session from Plex dashboard
      try {
        await backendUpdateProgress(metadata.ratingKey, currentTime * 1000, duration * 1000, 'stopped', isTranscoding);
      } catch {
        try { await plexTimelineUpdate(plexConfig, metadata.ratingKey, currentTime * 1000, duration * 1000, 'stopped'); } catch {}
      }

      // Kill existing transcode sessions
      await plexKillAllTranscodeSessions(plexConfig);

      // Reset session ID for fresh session
      resetPlexSessionId();

      // Get the highest available transcoded quality
      const transcodedOptions = qualityOptions.filter(opt => opt.value !== 'original');
      const maxQuality = transcodedOptions[0]?.value || 20000; // Default to 20 Mbps if no options

      console.log('Retrying with transcoded quality:', maxQuality);

      // Force transcode with maximum quality
      const url = plexStreamUrl(plexConfig, itemId, {
        maxVideoBitrate: Number(maxQuality),
        protocol: 'dash',
        autoAdjustQuality: false,
        directPlay: false,
        directStream: false, // Force transcode
        audioStreamID: selectedAudioStream || undefined,
        subtitleStreamID: selectedSubtitleStream || undefined,
        forceReload: true,
      });

      setStreamUrl(url);
      setQuality(maxQuality);
      localStorage.setItem('player_quality', maxQuality.toString());

      // Clear error states after a delay
      setTimeout(() => {
        setCodecErrorMessage(null);
        setRetryingWithTranscode(false);
      }, 5000);
    } catch (error) {
      console.error('Failed to retry with transcode:', error);
      setError(err);
      setRetryingWithTranscode(false);
    }
  }, [metadata, itemId, plexConfig, qualityOptions, selectedAudioStream, selectedSubtitleStream]);

  const handleBuffering = useCallback((isBuffering: boolean) => {
    setBuffering(isBuffering);
  }, []);

  const handlePlayingChange = useCallback((isPlaying: boolean) => {
    setPlaying(isPlaying);
  }, []);

  // Use the options from state that were set during metadata load
  const canPlayDirect = metadata ? canDirectPlay(metadata) : false;
  const canStreamDirect = metadata ? canDirectStream(metadata) : false;
  const hasDV = metadata ? hasDolbyVision(metadata) : false;

  // Compute poster URL with optional backend proxy
  const posterUrl = metadata?.thumb
    ? apiClient.getPlexImageNoToken(metadata.thumb)
    : undefined;

  // Compute credits trigger start for movies
  const creditsStartSec = useMemo(() => {
    if (metadata?.type !== 'movie') return undefined;
    if (!duration || duration <= 0) return undefined;
    const credits = metadata?.Marker?.find(m => m.type === 'credits');
    const start = credits ? (credits.startTimeOffset / 1000) : Math.max(0, duration - 30);
    return start;
  }, [metadata, duration]);

  // Proactive movie exit at credits start (no loop/retry)
  useEffect(() => {
    if (exiting) return;
    if (metadata?.type !== 'movie') return;
    if (creditsStartSec === undefined) return;
    if (currentTime > 1 && currentTime >= creditsStartSec) {
      goToDetails();
    }
  }, [metadata, creditsStartSec, currentTime, goToDetails, exiting]);

  if (error) {
    return (
      <div className="fixed inset-0 bg-black flex items-center justify-center">
        <div className="text-white text-center">
          <div className="mb-4">Error: {error}</div>
          <div className="mb-2 text-xs max-w-2xl break-all">
            Stream URL: {streamUrl}
          </div>
          <div className="flex gap-2 justify-center">
            <button
              className="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded"
              onClick={() => window.open(streamUrl, '_blank')}
            >
              Test URL
            </button>
            <button
              className="px-4 py-2 bg-red-600 hover:bg-red-700 rounded"
              onClick={async () => {
                // Clean up before exiting
                try { await plexKillAllTranscodeSessions(plexConfig); } catch {}
                onBack?.();
              }}
            >
              Go Back
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="fixed inset-0 bg-black flex items-center justify-center">
        <div className="text-white">Loading...</div>
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className="fixed inset-0 bg-black z-50"
      style={{ cursor: cursorHidden ? 'none' : 'auto' }}
      onClick={handleBackdropClick}
    >
      {streamUrl && (
        <div
          className="absolute inset-0"
          style={{
            // Hardware acceleration hints for the video container
            willChange: 'contents',
            transform: 'translateZ(0)',
            isolation: 'isolate',
          }}
        >
          <PlexVideoPlayer
            key={streamUrl} // Force remount when URL changes
            src={streamUrl}
            poster={posterUrl}
            videoRef={videoRef}
            playing={playing}
            volume={volume}
            playbackRate={playbackRate}
            autoPlay={true}
            startTime={initialStartAt}
            onTimeUpdate={handleTimeUpdate}
            onReady={handleReady}
            onEnded={handleEnded}
            onError={handleError}
            onBuffering={handleBuffering}
            onPlayingChange={handlePlayingChange}
            onCodecError={handleCodecError}
            onUserSeek={handleUserSeek}
            onStatsUpdate={showStats ? setPlayerStats : undefined}
          />
        </div>
      )}

      {/* Buffering indicator */}
      {buffering && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none z-40">
          <div className="w-16 h-16 border-4 border-white/30 border-t-white rounded-full animate-spin" />
        </div>
      )}

      {/* Codec error notification */}
      {codecErrorMessage && (
        <div className="absolute top-24 left-1/2 -translate-x-1/2 z-50">
          <div className="bg-yellow-600/90 text-white px-6 py-3 rounded-lg shadow-lg">
            <div className="flex items-center gap-3">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
              <span>{codecErrorMessage}</span>
            </div>
          </div>
        </div>
      )}

      {/* Stats HUD - toggle with 'i' key */}
      <PlaybackStatsHUD
        visible={showStats}
        position="top-left"
        stats={(() => {
          const media = metadata?.Media?.[0];
          const videoStream = media?.Part?.[0]?.Stream?.find(s => s.streamType === 1);
          const audioStream = media?.Part?.[0]?.Stream?.find(s => s.streamType === 2 && s.selected);

          // Determine dynamic range from video profile or stream info
          const getDynamicRange = () => {
            const profile = media?.videoProfile?.toLowerCase() || '';
            const colorTrc = (media?.colorTrc || videoStream?.colorTrc || '').toLowerCase();
            const colorSpace = (media?.colorSpace || videoStream?.colorSpace || '').toLowerCase();

            if (profile.includes('dv') || profile.includes('dolby')) return 'Dolby Vision';
            if (colorTrc.includes('smpte2084') || colorTrc.includes('pq')) {
              if (colorSpace.includes('bt2020')) return 'HDR10';
              return 'HDR';
            }
            if (colorTrc.includes('arib-std-b67') || colorTrc.includes('hlg')) return 'HLG';
            if (profile.includes('hdr10+')) return 'HDR10+';
            if (profile.includes('hdr')) return 'HDR10';
            return 'SDR';
          };

          return {
            // Video info
            videoCodec: media?.videoCodec,
            videoProfile: media?.videoProfile,
            resolution: media?.width && media?.height
              ? `${media.width}x${media.height}`
              : undefined,
            width: media?.width,
            height: media?.height,
            frameRate: media?.videoFrameRate
              ? parseFloat(media.videoFrameRate)
              : (videoStream?.frameRate || undefined),
            bitrate: media?.bitrate,
            bitDepth: media?.bitDepth || videoStream?.bitDepth,
            colorSpace: media?.colorSpace || videoStream?.colorSpace,
            container: media?.container,
            dynamicRange: getDynamicRange(),

            // Audio info
            audioCodec: media?.audioCodec || audioStream?.codec,
            audioChannels: media?.audioChannels || audioStream?.channels,
            audioSampleRate: audioStream?.samplingRate,

            // Playback info
            currentTime,
            duration,
            bufferProgress: buffered,
            playbackRate,

            // Transcoding status - use actual Plex decision
            isTranscoding: isTranscoding,
            videoDecision: videoDecision,
            audioDecision: audioDecision,

            // Real-time stats from player libraries (dash.js/hls.js)
            videoBitrate: playerStats.videoBitrate,
            audioBitrate: playerStats.audioBitrate || (audioStream?.bitrate ? audioStream.bitrate * 1000 : undefined),
            downloadSpeed: playerStats.downloadSpeed,
            playableBufferSeconds: playerStats.bufferLength || realTimeStats.playableBufferSeconds,

            // Real-time performance stats from video element
            displayFPS: realTimeStats.displayFPS,
            droppedFrames: realTimeStats.droppedFrames,
            totalFrames: realTimeStats.totalFrames,
            isHardwareAccelerated: realTimeStats.isHardwareAccelerated,
          };
        })()}
      />

      {/* Skip marker button */}
      {currentMarker && (
        <div className="absolute bottom-32 right-8 z-20">
          <button
            className="px-6 py-3 bg-white/20 hover:bg-white/30 backdrop-blur rounded-lg text-white font-medium transition-all"
            onClick={skipCurrentMarker}
          >
            Skip {currentMarker.type === 'intro' ? 'Intro' : currentMarker.type === 'credits' ? 'Credits' : 'Marker'}
          </button>
        </div>
      )}

      {/* Next episode countdown */}
      {nextEpisodeCountdown !== null && nextEpisode && (
        <div className="absolute bottom-32 right-8 z-40">
          <div className="bg-black/85 backdrop-blur rounded-xl p-4 ring-1 ring-white/10 shadow-2xl max-w-md">
            <div className="text-white text-base mb-1 font-semibold">Up Next • Playing in {nextEpisodeCountdown}s</div>
            <div className="text-white/90 mb-3 font-medium line-clamp-1">{nextEpisode.title}</div>
            <div className="flex gap-2">
              <button
                className="px-4 py-2 bg-white/10 hover:bg-white/20 rounded text-white"
                onClick={() => setNextEpisodeCountdown(null)}
              >
                Cancel
              </button>
              <button
                className="px-4 py-2 bg-red-600 hover:bg-red-700 rounded text-white"
                onClick={() => onNext?.(String(nextEpisode.ratingKey))}
              >
                Play Now
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Controls overlay */}
      <div
        className={`absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-black/50 transition-opacity duration-300 ${
          showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'
        }`}
      >
        {/* Top bar */}
        <div className="absolute top-0 left-0 right-0 p-6">
          <div className="flex items-center gap-4">
            <button
              className="p-2 rounded-full transition-colors"
              onClick={async () => {
                // Send stopped timeline and cleanup BEFORE navigating
                try {
                  await backendUpdateProgress(metadata!.ratingKey, currentTime * 1000, duration * 1000, 'stopped', isTranscoding);
                } catch {
                  try { await plexTimelineUpdate(plexConfig, metadata!.ratingKey, currentTime * 1000, duration * 1000, 'stopped'); } catch {}
                }
                try { await plexKillAllTranscodeSessions(plexConfig); } catch {}
                // Navigate after cleanup
                if (metadata?.type === 'episode' && metadata.grandparentRatingKey) {
                  window.location.href = `/details/${encodeURIComponent(`plex:${metadata.grandparentRatingKey}`)}`;
                } else if (metadata?.type === 'movie') {
                  window.location.href = `/details/${encodeURIComponent(`plex:${metadata.ratingKey}`)}`;
                } else {
                  onBack?.();
                }
              }}
            >
              <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
              </svg>
            </button>
            <div className="text-white">
              <div className="text-2xl font-bold">
                {metadata?.type === 'episode' 
                  ? `${metadata.grandparentTitle} - S${metadata.parentIndex}E${metadata.index}`
                  : metadata?.title}
              </div>
              {metadata?.type === 'episode' && (
                <div className="text-white/80">{metadata.title}</div>
              )}
            </div>
          </div>
        </div>

        {/* Bottom controls */}
        <div className="absolute bottom-0 left-0 right-0 p-6 player-controls">
          <div className="mx-auto">
            {/* Seek bar */}
            <div className="h-12 grid grid-cols-[1fr_auto] items-center gap-3">
              <VideoSeekSlider
                max={duration * 1000}
                currentTime={currentTime * 1000}
                bufferTime={buffered * 1000}
                onChange={(time: number) => {
                  handleUserSeek();
                  const video = videoRef.current;
                  if (video) video.currentTime = time / 1000;
                }}
                offset={0}
                secondsPrefix="00:00:"
                minutesPrefix="00:"
                getPreviewScreenUrl={metadata?.Media?.[0]?.Part?.[0]?.indexes ? (time: number) => {
                  const partId = metadata.Media![0].Part[0].id;
                  return plexTranscodeImageUrl(plexConfig, `/library/parts/${partId}/indexes/sd/${Math.floor(time)}`, 320, 180);
                } : undefined}
              />
              {duration > 0 && (
                <span className="text-white text-sm font-medium drop-shadow whitespace-nowrap" title="Time remaining" style={{ marginTop: '-33px' }}>
                  -{formatTime(Math.max(0, duration - currentTime))}
                </span>
              )}
          </div>

          {/* Control buttons */}
          <div className="flex items-center justify-between">
              <div className="flex items-center gap-4">
                {/* Play/Pause */}
                <button
                  className="w-14 h-14 sm:w-16 sm:h-16 flex items-center justify-center text-white bg-transparent transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                  onClick={() => {
                    const video = videoRef.current;
                    if (video) {
                      if (playing) {
                        video.pause();
                      } else {
                        video.play().catch(e => console.warn('Play failed:', e));
                      }
                    }
                    setPlaying(!playing);
                  }}
                >
                  {playing ? (
                    // PauseMedium
                    <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-9 h-9 sm:w-10 sm:h-10 text-white">
                      <path fillRule="evenodd" clipRule="evenodd" d="M4.5 3C4.22386 3 4 3.22386 4 3.5V20.5C4 20.7761 4.22386 21 4.5 21H9.5C9.77614 21 10 20.7761 10 20.5V3.5C10 3.22386 9.77614 3 9.5 3H4.5ZM14.5 3C14.2239 3 14 3.22386 14 3.5V20.5C14 20.7761 14.2239 21 14.5 21H19.5C19.7761 21 20 20.7761 20 20.5V3.5C20 3.22386 19.7761 3 19.5 3H14.5Z" />
                    </svg>
                  ) : (
                    // PlayMedium
                    <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-9 h-9 sm:w-10 sm:h-10 text-white">
                      <path d="M5 2.69127C5 1.93067 5.81547 1.44851 6.48192 1.81506L23.4069 11.1238C24.0977 11.5037 24.0977 12.4963 23.4069 12.8762L6.48192 22.1849C5.81546 22.5515 5 22.0693 5 21.3087V2.69127Z" />
                    </svg>
                  )}
                </button>

                {/* Skip buttons */}
                <button
                  className="w-12 h-12 sm:w-14 sm:h-14 bg-transparent flex items-center justify-center text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                  onClick={() => {
                    const video = videoRef.current;
                    if (video) video.currentTime = Math.max(0, currentTime - 10);
                  }}
                >
                  <Replay10Icon className="w-8 h-8 text-white" />
                </button>
                <button
                  className="w-12 h-12 sm:w-14 sm:h-14 bg-transparent flex items-center justify-center text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                  onClick={() => {
                    const video = videoRef.current;
                    if (video) video.currentTime = Math.min(duration, currentTime + 10);
                  }}
                >
                  <Forward10Icon className="w-8 h-8 text-white" />
                </button>

                {/* Volume */}
                <div className="flex items-center">
                  <button
                    ref={volumeButtonRef}
                    className="w-12 h-12 sm:w-14 sm:h-14 bg-transparent flex items-center justify-center text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                    onClick={() => setShowVolumeSlider(!showVolumeSlider)}
                    aria-label="Volume"
                    title="Volume"
                  >
                    {(() => {
                      const state = volume === 0 ? 'off' : volume <= 0.33 ? 'low' : volume <= 0.66 ? 'medium' : 'high';
                      if (state === 'off') {
                        return (
                          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-8 h-8 text-white">
                            <path fillRule="evenodd" clipRule="evenodd" d="M11 4.00003C11 3.59557 10.7564 3.23093 10.3827 3.07615C10.009 2.92137 9.57889 3.00692 9.29289 3.29292L4.58579 8.00003H1C0.447715 8.00003 0 8.44774 0 9.00003V15C0 15.5523 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0787 10.3827 20.9239C10.7564 20.7691 11 20.4045 11 20V4.00003ZM5.70711 9.70714L9 6.41424V17.5858L5.70711 14.2929L5.41421 14H5H2V10H5H5.41421L5.70711 9.70714ZM15.2929 9.70714L17.5858 12L15.2929 14.2929L16.7071 15.7071L19 13.4142L21.2929 15.7071L22.7071 14.2929L20.4142 12L22.7071 9.70714L21.2929 8.29292L19 10.5858L16.7071 8.29292L15.2929 9.70714Z" />
                          </svg>
                        );
                      }
                      if (state === 'low') {
                        return (
                          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-8 h-8 text-white">
                            <path fillRule="evenodd" clipRule="evenodd" d="M11 4.00003C11 3.59557 10.7564 3.23093 10.3827 3.07615C10.009 2.92137 9.57889 3.00692 9.29289 3.29292L4.58579 8.00003H1C0.447715 8.00003 0 8.44774 0 9.00003V15C0 15.5523 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0787 10.3827 20.9239C10.7564 20.7691 11 20.4045 11 20V4.00003ZM5.70711 9.70714L9 6.41424V17.5858L5.70711 14.2929L5.41421 14H5H2V10H5H5.41421L5.70711 9.70714ZM16.0001 12C16.0001 10.4087 15.368 8.88262 14.2428 7.7574L12.8285 9.17161C13.5787 9.92176 14.0001 10.9392 14.0001 12C14.0001 13.0609 13.5787 14.0783 12.8285 14.8285L14.2428 16.2427C15.368 15.1175 16.0001 13.5913 16.0001 12Z" />
                          </svg>
                        );
                      }
                      if (state === 'medium') {
                        return (
                          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-8 h-8 text-white">
                            <path fillRule="evenodd" clipRule="evenodd" d="M11 4.00003C11 3.59557 10.7564 3.23093 10.3827 3.07615C10.009 2.92137 9.57889 3.00692 9.29289 3.29292L4.58579 8.00003H1C0.447715 8.00003 0 8.44774 0 9.00003V15C0 15.5523 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0787 10.3827 20.9239C10.7564 20.7691 11 20.4045 11 20V4.00003ZM5.70711 9.70714L9 6.41424V17.5858L5.70711 14.2929L5.41421 14H5H2V10H5H5.41421L5.70711 9.70714ZM17.0709 4.92897C18.9462 6.80433 19.9998 9.34787 19.9998 12C19.9998 14.6522 18.9462 17.1957 17.0709 19.0711L15.6567 17.6569C17.157 16.1566 17.9998 14.1218 17.9998 12C17.9998 9.87831 17.157 7.84347 15.6567 6.34318L17.0709 4.92897ZM14.2428 7.7574C15.368 8.88262 16.0001 10.4087 16.0001 12C16.0001 13.5913 15.368 15.1175 14.2428 16.2427L12.8285 14.8285C13.5787 14.0783 14.0001 13.0609 14.0001 12C14.0001 10.9392 13.5787 9.92176 12.8285 9.17161L14.2428 7.7574Z" />
                          </svg>
                        );
                      }
                      // high
                      return (
                        <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-7 h-7 text-white">
                          <path fillRule="evenodd" clipRule="evenodd" d="M24 12C24 8.28693 22.525 4.72597 19.8995 2.10046L18.4853 3.51468C20.7357 5.76511 22 8.81736 22 12C22 15.1826 20.7357 18.2348 18.4853 20.4852L19.8995 21.8995C22.525 19.2739 24 15.713 24 12ZM11 3.99995C11 3.59549 10.7564 3.23085 10.3827 3.07607C10.009 2.92129 9.57889 3.00685 9.29289 3.29285L4.58579 7.99995H1C0.447715 7.99995 0 8.44767 0 8.99995V15C0 15.5522 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0786 10.3827 20.9238C10.7564 20.7691 11 20.4044 11 20V3.99995ZM5.70711 9.70706L9 6.41417V17.5857L5.70711 14.2928L5.41421 14H5H2V9.99995H5H5.41421L5.70711 9.70706ZM16.0001 12C16.0001 10.4087 15.368 8.88254 14.2428 7.75732L12.8285 9.17154C13.5787 9.92168 14.0001 10.9391 14.0001 12C14.0001 13.0608 13.5787 14.0782 12.8285 14.8284L14.2428 16.2426C15.368 15.1174 16.0001 13.5913 16.0001 12ZM17.0709 4.92889C18.9462 6.80426 19.9998 9.3478 19.9998 12C19.9998 14.6521 18.9462 17.1957 17.0709 19.071L15.6567 17.6568C17.157 16.1565 17.9998 14.1217 17.9998 12C17.9998 9.87823 17.157 7.8434 15.6567 6.34311L17.0709 4.92889Z" />
                        </svg>
                      );
                    })()}
                  </button>
                  <div className="ml-3 overflow-hidden transition-[width] duration-200" style={{ width: showVolumeSlider ? '18rem' : 0 }}>
                    <div ref={volumePopoverRef} className={`bg-black/90 rounded-2xl px-4 py-3 ring-1 ring-white/10 shadow-xl w-[18rem] transition-all duration-200 ${showVolumeSlider ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-2'}`}>
                      <div className="flex items-center gap-3">
                        {(() => {
                          const state = volume === 0 ? 'off' : volume <= 0.33 ? 'low' : volume <= 0.66 ? 'medium' : 'high';
                          const cls = 'w-5 h-5 text-white flex-shrink-0';
                          if (state === 'off') {
                            return (
                        <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className={cls}>
                                <path fillRule="evenodd" clipRule="evenodd" d="M11 4.00003C11 3.59557 10.7564 3.23093 10.3827 3.07615C10.009 2.92137 9.57889 3.00692 9.29289 3.29292L4.58579 8.00003H1C0.447715 8.00003 0 8.44774 0 9.00003V15C0 15.5523 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0787 10.3827 20.9239C10.7564 20.7691 11 20.4045 11 20V4.00003ZM5.70711 9.70714L9 6.41424V17.5858L5.70711 14.2929L5.41421 14H5H2V10H5H5.41421L5.70711 9.70714ZM15.2929 9.70714L17.5858 12L15.2929 14.2929L16.7071 15.7071L19 13.4142L21.2929 15.7071L22.7071 14.2929L20.4142 12L22.7071 9.70714L21.2929 8.29292L19 10.5858L16.7071 8.29292L15.2929 9.70714Z" />
                              </svg>
                            );
                          }
                          if (state === 'low') {
                            return (
                              <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className={cls}>
                                <path fillRule="evenodd" clipRule="evenodd" d="M11 4.00003C11 3.59557 10.7564 3.23093 10.3827 3.07615C10.009 2.92137 9.57889 3.00692 9.29289 3.29292L4.58579 8.00003H1C0.447715 8.00003 0 8.44774 0 9.00003V15C0 15.5523 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0787 10.3827 20.9239C10.7564 20.7691 11 20.4045 11 20V4.00003ZM5.70711 9.70714L9 6.41424V17.5858L5.70711 14.2929L5.41421 14H5H2V10H5H5.41421L5.70711 9.70714ZM16.0001 12C16.0001 10.4087 15.368 8.88262 14.2428 7.7574L12.8285 9.17161C13.5787 9.92176 14.0001 10.9392 14.0001 12C14.0001 13.0609 13.5787 14.0783 12.8285 14.8285L14.2428 16.2427C15.368 15.1175 16.0001 13.5913 16.0001 12Z" />
                              </svg>
                            );
                          }
                          if (state === 'medium') {
                            return (
                              <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className={cls}>
                                <path fillRule="evenodd" clipRule="evenodd" d="M11 4.00003C11 3.59557 10.7564 3.23093 10.3827 3.07615C10.009 2.92137 9.57889 3.00692 9.29289 3.29292L4.58579 8.00003H1C0.447715 8.00003 0 8.44774 0 9.00003V15C0 15.5523 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0787 10.3827 20.9239C10.7564 20.7691 11 20.4045 11 20V4.00003ZM5.70711 9.70714L9 6.41424V17.5858L5.70711 14.2929L5.41421 14H5H2V10H5H5.41421L5.70711 9.70714ZM17.0709 4.92897C18.9462 6.80433 19.9998 9.34787 19.9998 12C19.9998 14.6522 18.9462 17.1957 17.0709 19.0711L15.6567 17.6569C17.157 16.1566 17.9998 14.1218 17.9998 12C17.9998 9.87831 17.157 7.84347 15.6567 6.34318L17.0709 4.92897ZM14.2428 7.7574C15.368 8.88262 16.0001 10.4087 16.0001 12C16.0001 13.5913 15.368 15.1175 14.2428 16.2427L12.8285 14.8285C13.5787 14.0783 14.0001 13.0609 14.0001 12C14.0001 10.9392 13.5787 9.92176 12.8285 9.17161L14.2428 7.7574Z" />
                              </svg>
                            );
                          }
                          return (
                            <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className={cls}>
                              <path fillRule="evenodd" clipRule="evenodd" d="M24 12C24 8.28693 22.525 4.72597 19.8995 2.10046L18.4853 3.51468C20.7357 5.76511 22 8.81736 22 12C22 15.1826 20.7357 18.2348 18.4853 20.4852L19.8995 21.8995C22.525 19.2739 24 15.713 24 12ZM11 3.99995C11 3.59549 10.7564 3.23085 10.3827 3.07607C10.009 2.92129 9.57889 3.00685 9.29289 3.29285L4.58579 7.99995H1C0.447715 7.99995 0 8.44767 0 8.99995V15C0 15.5522 0.447715 16 1 16H4.58579L9.29289 20.7071C9.57889 20.9931 10.009 21.0786 10.3827 20.9238C10.7564 20.7691 11 20.4044 11 20V3.99995ZM5.70711 9.70706L9 6.41417V17.5857L5.70711 14.2928L5.41421 14H5H2V9.99995H5H5.41421L5.70711 9.70706ZM16.0001 12C16.0001 10.4087 15.368 8.88254 14.2428 7.75732L12.8285 9.17154C13.5787 9.92168 14.0001 10.9391 14.0001 12C14.0001 13.0608 13.5787 14.0782 12.8285 14.8284L14.2428 16.2426C15.368 15.1174 16.0001 13.5913 16.0001 12ZM17.0709 4.92889C18.9462 6.80426 19.9998 9.3478 19.9998 12C19.9998 14.6521 18.9462 17.1957 17.0709 19.071L15.6567 17.6568C17.157 16.1565 17.9998 14.1217 17.9998 12C17.9998 9.87823 17.157 7.8434 15.6567 6.34311L17.0709 4.92889Z" />
                            </svg>
                          );
                        })()}
                        <div className="relative flex-1 h-1.5 select-none">
                          <div className="absolute inset-0 bg-white/20 rounded-full overflow-hidden">
                            <div className="h-full rounded-full bg-gradient-to-r from-red-500 to-red-600" style={{ width: `${Math.round(volume*100)}%`, transition: 'width 160ms ease' }} />
                          </div>
                          {/* Visible thumb to mirror Netflix */}
                          <div
                            className={`absolute top-1/2 -translate-y-1/2 -translate-x-1/2 z-20 pointer-events-none transition-transform ${isDraggingVolume ? 'scale-105' : ''}`}
                            style={{ left: `${Math.round(volume * 100)}%` }}
                            aria-hidden
                          >
                            <div className="w-5 h-5 rounded-full border-4 border-white/60 flex items-center justify-center">
                              <span className="block w-2.5 h-2.5 rounded-full bg-white" />
                            </div>
                          </div>
                          <div
                            ref={volTrackRef}
                            role="slider"
                            aria-label="Volume"
                            aria-valuemin={0}
                            aria-valuemax={100}
                            aria-valuenow={Math.round(volume * 100)}
                            tabIndex={0}
                            className="absolute inset-0 w-full h-full cursor-pointer"
                            style={{ touchAction: 'none' }}
                            onMouseDown={startVolDrag}
                            onPointerDown={startVolDrag}
                            onTouchStart={startVolDrag}
                            onKeyDown={(e) => {
                              if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') { e.preventDefault(); setVolume(v => Math.max(0, v - 0.05)); }
                              if (e.key === 'ArrowRight' || e.key === 'ArrowUp') { e.preventDefault(); setVolume(v => Math.min(1, v + 0.05)); }
                              if (e.key === 'Home') { e.preventDefault(); setVolume(0); }
                              if (e.key === 'End') { e.preventDefault(); setVolume(1); }
                            }}
                          />
                        </div>
                        <div className="w-12 text-right text-xs text-white/70">{Math.round(volume * 100)}%</div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-4">
                {metadata?.type === 'episode' && (
                  <>
                    {nextEpisode && (
                      <div className="relative">
                        <button
                          className="p-2 bg-transparent text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                          onMouseEnter={() => setShowNextHover(true)}
                          onMouseLeave={() => setShowNextHover(false)}
                          onFocus={() => setShowNextHover(true)}
                          onBlur={() => setShowNextHover(false)}
                          onClick={() => onNext?.(String(nextEpisode.ratingKey))}
                          aria-label="Next Episode"
                          title="Next Episode"
                        >
                          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-8 h-8 text-white">
                            <path fillRule="evenodd" clipRule="evenodd" d="M22 3H20V21H22V3ZM4.28615 3.61729C3.28674 3.00228 2 3.7213 2 4.89478V19.1052C2 20.2787 3.28674 20.9977 4.28615 20.3827L15.8321 13.2775C16.7839 12.6918 16.7839 11.3082 15.8321 10.7225L4.28615 3.61729ZM4 18.2104V5.78956L14.092 12L4 18.2104Z" />
                          </svg>
                        </button>

                        {showNextHover && (
                          <div className="absolute bottom-full right-0 mb-3 w-[42rem] max-w-[92vw] bg-black/90 rounded-xl ring-1 ring-white/10 overflow-hidden shadow-2xl z-50" role="dialog" aria-label="Next Episode">
                            <div className="px-6 py-4 text-2xl font-bold text-white bg-white/5">Next Episode</div>
                            <div className="p-4 grid grid-cols-1 md:grid-cols-2 gap-4 items-start">
                              <div className="relative aspect-video bg-black/40 rounded overflow-hidden">
                                {nextEpisode?.thumb && (
                                  <img src={apiClient.getPlexImageNoToken(nextEpisode.thumb)} alt={nextEpisode.title} className="absolute inset-0 w-full h-full object-cover" />
                                )}
                                <div className="absolute inset-0 flex items-center justify-center">
                                  <div className="w-16 h-16 rounded-full bg-black/50 flex items-center justify-center ring-1 ring-white/20">
                                    <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor" className="w-10 h-10 text-white">
                                      <path d="M5 2.69127C5 1.93067 5.81547 1.44851 6.48192 1.81506L23.4069 11.1238C24.0977 11.5037 24.0977 12.4963 23.4069 12.8762L6.48192 22.1849C5.81546 22.5515 5 22.0693 5 21.3087V2.69127Z" />
                                    </svg>
                                  </div>
                                </div>
                              </div>
                              <div className="text-white/90">
                                <div className="text-xl font-semibold mb-1">{nextEpisode?.index ?? ''} <span className="opacity-80 font-normal">Episode {nextEpisode?.index ?? ''}</span></div>
                                <div className="text-xl font-bold mb-2">{nextEpisode?.title}</div>
                                <div className="text-white/80 leading-relaxed line-clamp-5">{nextEpisode?.summary}</div>
                              </div>
                            </div>
                          </div>
                        )}
                      </div>
                    )}

                    <div className="relative">
                      <button
                        ref={episodesButtonRef}
                        className="p-2 bg-transparent text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                        onClick={() => setShowEpisodes(s => !s)}
                        aria-label="Episodes"
                        title="Episodes"
                      >
                        <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-8 h-8 text-white">
                          <path fillRule="evenodd" clipRule="evenodd" d="M8 5H22V13H24V5C24 3.89543 23.1046 3 22 3H8V5ZM18 9H4V7H18C19.1046 7 20 7.89543 20 9V17H18V9ZM0 13C0 11.8954 0.895431 11 2 11H14C15.1046 11 16 11.8954 16 13V19C16 20.1046 15.1046 21 14 21H2C0.895431 21 0 20.1046 0 19V13ZM14 19V13H2V19H14Z" />
                        </svg>
                      </button>
                    </div>
                  </>
                )}
                {/* Settings */}
                <div className="relative">
                  <button
                    className="p-2 bg-transparent text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                    onClick={() => setShowSettings(!showSettings)}
                  >
                    <svg className="w-8 h-8 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                  </button>
                  
                  {showSettings && (
                    <div className="absolute bottom-full right-0 mb-2 w-80 bg-black/95 backdrop-blur rounded-lg overflow-hidden">
                      <div className="flex border-b border-white/10">
                        <button
                          className={`flex-1 px-4 py-2 text-sm ${settingsTab === 'quality' ? 'bg-white/10 text-white' : 'text-white/60 hover:text-white'}`}
                          onClick={() => setSettingsTab('quality')}
                        >
                          Quality
                        </button>
                        <button
                          className={`flex-1 px-4 py-2 text-sm ${settingsTab === 'audio' ? 'bg-white/10 text-white' : 'text-white/60 hover:text-white'}`}
                          onClick={() => setSettingsTab('audio')}
                        >
                          Audio
                        </button>
                        <button
                          className={`flex-1 px-4 py-2 text-sm ${settingsTab === 'subtitles' ? 'bg-white/10 text-white' : 'text-white/60 hover:text-white'}`}
                          onClick={() => setSettingsTab('subtitles')}
                        >
                          Subtitles
                        </button>
                      </div>
                      
                      <div className="max-h-64 overflow-y-auto">
                        {settingsTab === 'quality' && (
                          <div className="p-2">
                            {hasDV && (
                              <div className="mb-2 p-2 bg-yellow-600/20 rounded text-yellow-400 text-sm">
                                <div className="flex items-start gap-2">
                                  <svg className="w-4 h-4 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                                  </svg>
                                  <div>
                                    <div className="font-semibold">Dolby Vision Content</div>
                                    <div className="text-xs text-yellow-300/80 mt-1">
                                      Direct play may not work. Select a transcoded quality for best compatibility.
                                    </div>
                                  </div>
                                </div>
                              </div>
                            )}
                            {qualityOptions.map((option) => (
                              <button
                                key={option.label}
                                className={`w-full text-left px-3 py-2 rounded hover:bg-white/10 transition-colors ${
                                  (quality === option.value || (typeof quality === 'number' && typeof option.value === 'number' && quality === option.value)) ? 'text-red-500' : 'text-white'
                                }`}
                                onClick={() => {
                                  hasRetriedWithTranscode.current = false; // Reset retry flag when manually changing quality
                                  handleQualityChange(option.value);
                                  setShowSettings(false);
                                }}
                              >
                                {option.label}
                                {option.value === 'original' && canPlayDirect && !hasDV && (
                                  <span className="text-xs text-white/60 ml-2">(Direct Play)</span>
                                )}
                                {option.value === 'original' && !canPlayDirect && !hasDV && (
                                  <span className="text-xs text-white/60 ml-2">(Direct Stream/Original)</span>
                                )}
                                {option.value === 'original' && hasDV && (
                                  <span className="text-xs text-yellow-400 ml-2">⚠ DV - May not play</span>
                                )}
                                {option.value !== 'original' && hasDV && (
                                  <span className="text-xs text-green-400 ml-2">✓ Compatible</span>
                                )}
                                {retryingWithTranscode && option.value !== 'original' && option.value === quality && (
                                  <span className="text-xs text-green-400 ml-2">(Auto-selected)</span>
                                )}
                              </button>
                            ))}
                          </div>
                        )}
                        
                        {settingsTab === 'audio' && (
                          <div className="p-2">
                            {audioOptions.length === 0 ? (
                              <div className="text-white/60 text-center py-4">No audio tracks available</div>
                            ) : (
                              audioOptions.map((option) => (
                                <button
                                  key={option.id}
                                  className={`w-full text-left px-3 py-2 rounded hover:bg-white/10 transition-colors ${
                                    selectedAudioStream === option.id ? 'text-red-500' : 'text-white'
                                  }`}
                                  onClick={() => {
                                    handleAudioStreamChange(option.id);
                                    setShowSettings(false);
                                  }}
                                >
                                  {option.title}
                                </button>
                              ))
                            )}
                          </div>
                        )}
                        
                        {settingsTab === 'subtitles' && (
                          <div className="p-2">
                            {subtitleOptions.map((option) => (
                              <button
                                key={option.id}
                                className={`w-full text-left px-3 py-2 rounded hover:bg-white/10 transition-colors ${
                                  selectedSubtitleStream === option.id ? 'text-red-500' : 'text-white'
                                }`}
                                onClick={() => {
                                  handleSubtitleStreamChange(option.id);
                                  setShowSettings(false);
                                }}
                              >
                                {option.title}
                                {option.forced && <span className="text-xs text-white/60 ml-2">(Forced)</span>}
                                {option.external && <span className="text-xs text-white/60 ml-2">(External)</span>}
                              </button>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>
                  )}
                </div>

                {/* Playback speed (Netflix-style) */}
                <div className="relative">
                  <button
                    className="p-2 bg-transparent text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                    onClick={() => setShowSpeed(!showSpeed)}
                    aria-label="Playback speed"
                    title="Playback speed"
                  >
                    {/* InternetSpeedMedium icon */}
                    <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-8 h-8 text-white">
                      <path fillRule="evenodd" clipRule="evenodd" d="M19.0569 6.27006C15.1546 2.20629 8.84535 2.20629 4.94312 6.27006C1.01896 10.3567 1.01896 16.9985 4.94312 21.0852L3.50053 22.4704C-1.16684 17.6098 -1.16684 9.7454 3.50053 4.88481C8.18984 0.0013696 15.8102 0.0013696 20.4995 4.88481C25.1668 9.7454 25.1668 17.6098 20.4995 22.4704L19.0569 21.0852C22.981 16.9985 22.981 10.3567 19.0569 6.27006ZM15 14.0001C15 15.6569 13.6569 17.0001 12 17.0001C10.3431 17.0001 9 15.6569 9 14.0001C9 12.3432 10.3431 11.0001 12 11.0001C12.4632 11.0001 12.9018 11.105 13.2934 11.2924L16.2929 8.29296L17.7071 9.70717L14.7076 12.7067C14.895 13.0983 15 13.5369 15 14.0001Z" />
                    </svg>
                  </button>

                  {showSpeed && (
                    <div className="absolute bottom-full right-0 mb-2 w-[28rem] max-w-[92vw] bg-black/95 backdrop-blur rounded-lg ring-1 ring-white/10 shadow-2xl p-5">
                      <div className="text-white font-bold text-2xl mb-6">Playback Speed</div>
                      {/* Discrete slider track */}
                      <div className="relative my-5 pt-2">
                        <div className="absolute left-2 right-2 top-[1.375rem] h-0.5 bg-white/20" />
                        <div className="relative flex justify-between items-center px-2">
                          {[0.5, 0.75, 1, 1.25, 1.5].map((s) => {
                            const selected = Math.abs(playbackRate - s) < 0.001;
                            return (
                              <button
                                key={s}
                                onClick={() => { setPlaybackRate(s); setShowSpeed(false); }}
                                className="group relative flex items-center justify-center"
                                aria-label={`${s}x`}
                              >
                                {selected ? (
                                  <span className="w-10 h-10 rounded-full border-4 border-white/60 flex items-center justify-center">
                                    <span className="w-4 h-4 rounded-full bg-white" />
                                  </span>
                                ) : (
                                  <span className="w-4 h-4 rounded-full bg-white/60 group-hover:bg-white" />
                                )}
                              </button>
                            );
                          })}
                        </div>
                        <div className="mt-5 grid grid-cols-5 gap-0 text-center">
                          {[0.5, 0.75, 1, 1.25, 1.5].map((s) => {
                            const selected = Math.abs(playbackRate - s) < 0.001;
                            return (
                              <div key={`label-${s}`} className={selected ? 'text-white text-lg font-semibold' : 'text-white/80'}>
                                {s === 1 ? '1x (Normal)' : `${s}x`}
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    </div>
                  )}
                </div>

                {/* Picture-in-Picture */}
                <PiPButton videoRef={videoRef} />

                {/* Fullscreen */}
                <button
                  className="p-2 bg-transparent text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded"
                  onClick={toggleFullscreen}
                  aria-label={isFullscreen ? 'Exit Fullscreen' : 'Enter Fullscreen'}
                >
                  {isFullscreen ? (
                    // FullscreenExitMedium
                    <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-8 h-8 text-white">
                      <path fillRule="evenodd" clipRule="evenodd" d="M24 8H19V3H17V9V10H18H24V8ZM0 16H5V21H7V15V14H6H0V16ZM7 10H6H0V8H5V3H7V9V10ZM19 21V16H24V14H18H17V15V21H19Z" />
                    </svg>
                  ) : (
                    // FullscreenEnterMedium
                    <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="currentColor" role="img" className="w-8 h-8 text-white">
                      <path fillRule="evenodd" clipRule="evenodd" d="M0 5C0 3.89543 0.895431 3 2 3H9V5H2V9H0V5ZM22 5H15V3H22C23.1046 3 24 3.89543 24 5V9H22V5ZM2 15V19H9V21H2C0.895431 21 0 20.1046 0 19V15H2ZM22 19V15H24V19C24 20.1046 23.1046 21 22 21H15V19H22Z" />
                    </svg>
                  )}
                </button>
              </div>
            </div>
          </div>
          
          {/* Episodes overlay */}
          {showEpisodes && (
            <div className="absolute bottom-24 left-0 right-0 z-40 px-6 flex" style={{ justifyContent: 'right' }}>
              <div ref={episodesPanelRef} className="max-w-2xl bg-black/90 rounded-xl ring-1 ring-white/10 shadow-2xl overflow-hidden">
                <div className="flex items-center justify-between pl-6 pr-3 py-4 bg-white/10 border-b border-white/10">
                  <div className="text-2xl font-semibold text-white">Season {metadata?.parentIndex ?? ''}</div>
                  <button className="px-3 py-1.5 text-sm bg-white/10 hover:bg-white/20 rounded text-white" onClick={() => setShowEpisodes(false)}>Close</button>
                </div>
                <div className="max-h-[55vh] overflow-y-auto p-4">
                  {episodesLoading && (
                    <div className="text-white/80 p-6">Loading episodes…</div>
                  )}
                  {!episodesLoading && (!seasonEpisodes || seasonEpisodes.length === 0) && (
                    <div className="text-white/70 p-6">No episodes found.</div>
                  )}
                  {!episodesLoading && seasonEpisodes && seasonEpisodes.length > 0 && (
                    <div className="divide-y divide-white/10">
                      {seasonEpisodes.map((ep) => (
                        <button
                          key={ep.ratingKey}
                          className="w-full text-left flex items-start gap-4 px-2 py-3 hover:bg-white/5 transition-colors"
                          onClick={() => onNext?.(String(ep.ratingKey))}
                        >
                          <div className="w-40 aspect-video bg-black/30 rounded overflow-hidden flex-shrink-0 relative">
                            {ep.thumb && (
                              <img src={apiClient.getPlexImageNoToken(ep.thumb)} alt={ep.title} className="w-full h-full object-cover" />
                            )}
                            {ep.viewOffset && ep.duration && ep.duration > 0 && (
                              <div className="absolute bottom-0 left-0 right-0 h-1.5 bg-white/20">
                                <div className="h-full bg-brand" style={{ width: `${Math.min(100, Math.max(0, Math.round((ep.viewOffset/ep.duration)*100)))}%` }} />
                              </div>
                            )}
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="text-white font-semibold text-base mb-1">{ep.index ? `${ep.index}  ` : ''}<span className="font-bold">{ep.title}</span></div>
                            {ep.summary && (
                              <div className="text-white/80 text-sm leading-relaxed line-clamp-2">{ep.summary}</div>
                            )}
                          </div>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// Lightweight PiP button that prefers Document PiP and falls back to element PiP
import { usePictureInPicture } from '@/hooks/usePictureInPicture';
function PiPButton({ videoRef }: { videoRef: React.RefObject<HTMLVideoElement> }) {
  const { supported, active, toggle } = usePictureInPicture(videoRef);
  if (!supported) return null;
  return (
    <button
      className={`p-2 bg-transparent text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded`}
      onClick={() => toggle()}
      title="Picture in Picture"
    >
      {/* Simple PiP glyph */}
      <svg className="w-8 h-8 text-white" viewBox="0 0 24 24" fill="currentColor">
        <path d="M3 5a2 2 0 012-2h14a2 2 0 012 2v6h-2V5H5v14h6v2H5a2 2 0 01-2-2V5z"/>
        <rect x="13" y="13" width="8" height="6" rx="1"/>
      </svg>
    </button>
  );
}
