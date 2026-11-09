import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import PlexVideoPlayer, { PlayerStats } from '@/components/PlexVideoPlayer';
import PlaybackStatsHUD, { usePlaybackStats } from '@/components/PlaybackStatsHUD';
import SourcesSheet from '@/components/stremio/SourcesSheet';
import { Forward10Icon, Replay10Icon } from '@/components/icons/Replay10';
import { usePictureInPicture } from '@/hooks/usePictureInPicture';
import { saveSettings, useSettings, type PlayerAspectMode } from '@/state/settings';
import '@/styles/player.css';
import { formatTime, episodeLabel } from './format';
import { useAutoSkip } from './hooks/useAutoSkip';
import { useMediaSession } from './hooks/useMediaSession';
import { usePlayerKeyboard } from './hooks/usePlayerKeyboard';
import { useTraktScrobble } from './hooks/useTraktScrobble';
import { useUpNext } from './hooks/useUpNext';
import { useWakeLock } from './hooks/useWakeLock';
import { skipLabel } from './markers';
import SubtitleOverlay from './subtitles/SubtitleOverlay';
import { useSubtitleEngine } from './subtitles/useSubtitleEngine';
import type { PlayerClock, PlayerSession } from './types';
import {
  BackIcon,
  ChaptersIcon,
  EpisodesIcon,
  FullscreenIcon,
  NextEpisodeIcon,
  PauseIcon,
  PipIcon,
  PlayIcon,
  SettingsIcon,
  SourcesIcon,
  SpeedIcon,
  SubtitlesIcon,
} from './ui/icons';
import { ASPECT_MODES, ChaptersPanel, EpisodesPanel, SettingsPanel, ShortcutsOverlay, SpeedPanel, SubtitlePanel } from './ui/panels';
import SeekBar from './ui/SeekBar';
import VolumeControl from './ui/VolumeControl';

type Panel = 'episodes' | 'chapters' | 'settings' | 'speed' | 'subtitles' | null;

const ICON_BUTTON = 'p-2 bg-transparent text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded';
const SKIP_BUTTON = 'w-12 h-12 sm:w-14 sm:h-14 bg-transparent flex items-center justify-center text-white transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded';
const ZOOM_SCALE = 'scale(1.33)';
const MIN_SPEED = 0.25;
const MAX_SPEED = 3;

function objectFitFor(mode: PlayerAspectMode): React.CSSProperties['objectFit'] {
  if (mode === 'fill') return 'cover';
  if (mode === 'stretch') return 'fill';
  return 'contain';
}

export function usePlayerClock(): PlayerClock {
  const time = useRef(0);
  const duration = useRef(0);
  const playing = useRef(true);
  const buffering = useRef(false);
  const pause = useRef<() => void>(() => {});
  const resume = useRef<() => void>(() => {});
  return useMemo(() => ({ time, duration, playing, buffering, pause, resume }), []);
}

export default function PlayerShell({ session, clock }: { session: PlayerSession; clock: PlayerClock }) {
  const settings = useSettings();
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const containerRef = useRef<HTMLDivElement | null>(null);

  const [playing, setPlaying] = useState(true);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [buffering, setBuffering] = useState(false);
  const [volume, setVolume] = useState(() => {
    const saved = parseFloat(localStorage.getItem('player_volume') || '');
    return Number.isFinite(saved) ? Math.max(0, Math.min(1, saved)) : 1;
  });
  const lastVolume = useRef(parseFloat(localStorage.getItem('player_volume_last') || '0.8') || 0.8);
  const [rate, setRate] = useState(settings.defaultPlaybackSpeed);
  const [boosting, setBoosting] = useState(false);
  const [aspect, setAspect] = useState<PlayerAspectMode>(settings.playerAspectMode);
  const [isFullscreen, setIsFullscreen] = useState(Boolean(document.fullscreenElement));
  const [panel, setPanel] = useState<Panel>(null);
  const [showShortcuts, setShowShortcuts] = useState(false);
  const [showStats, setShowStats] = useState(false);
  const [showNextHover, setShowNextHover] = useState(false);
  const [showControls, setShowControls] = useState(true);
  const [cursorHidden, setCursorHidden] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);
  const [playerStats, setPlayerStats] = useState<PlayerStats>({});
  const lastStateUpdate = useRef(0);
  const feedbackTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const realTimeStats = usePlaybackStats(videoRef as React.RefObject<HTMLVideoElement>, undefined, showStats);
  const pip = usePictureInPicture(videoRef as React.RefObject<HTMLVideoElement>);
  const subtitles = useSubtitleEngine(session, clock);

  const showFeedback = useCallback((message: string) => {
    setFeedback(message);
    if (feedbackTimer.current) clearTimeout(feedbackTimer.current);
    feedbackTimer.current = setTimeout(() => setFeedback(null), 1500);
  }, []);

  const seekTo = useCallback((seconds: number) => {
    const video = videoRef.current;
    if (!video) return;
    const end = Number.isFinite(video.duration) ? video.duration : seconds;
    video.currentTime = Math.max(0, Math.min(end, seconds));
  }, []);
  const seekBy = useCallback((delta: number) => seekTo((videoRef.current?.currentTime ?? 0) + delta), [seekTo]);

  const play = useCallback(() => {
    videoRef.current?.play().catch(() => {});
    setPlaying(true);
  }, []);
  const pause = useCallback(() => {
    videoRef.current?.pause();
    setPlaying(false);
  }, []);
  const togglePlay = useCallback(() => {
    if (clock.playing.current) pause();
    else play();
  }, [clock, pause, play]);

  useEffect(() => {
    clock.pause.current = pause;
    clock.resume.current = play;
    clock.playing.current = playing;
    clock.buffering.current = buffering;
  }, [clock, pause, play, playing, buffering]);

  // Volume is persisted, and the last non-zero level is what unmute restores.
  useEffect(() => {
    try {
      localStorage.setItem('player_volume', String(volume));
      if (volume > 0) {
        lastVolume.current = volume;
        localStorage.setItem('player_volume_last', String(volume));
      }
    } catch {}
  }, [volume]);

  useEffect(() => {
    const onChange = () => setIsFullscreen(Boolean(document.fullscreenElement));
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);

  const toggleFullscreen = useCallback(() => {
    if (!document.fullscreenElement) containerRef.current?.requestFullscreen().catch(() => {});
    else document.exitFullscreen().catch(() => {});
  }, []);

  const closePanel = useCallback(() => setPanel(null), []);
  const togglePanel = useCallback((name: Exclude<Panel, null>) => {
    if (name === 'episodes') session.browser?.open();
    setPanel((current) => (current === name ? null : name));
  }, [session.browser]);

  const handleTimeUpdate = useCallback((time: number, total: number) => {
    clock.time.current = time;
    if (total > 0 && Number.isFinite(total)) clock.duration.current = total;
    // Throttled, since re-rendering at the timeupdate rate costs dropped frames.
    const now = performance.now();
    if (now - lastStateUpdate.current < 200) return;
    lastStateUpdate.current = now;
    setCurrentTime(time);
    if (total > 0 && Number.isFinite(total)) setDuration(total);
    const video = videoRef.current;
    if (video?.buffered.length) setBuffered(video.buffered.end(video.buffered.length - 1));
  }, [clock]);

  const autoSkip = useAutoSkip(session, currentTime, seekTo);
  const upNext = useUpNext(session, currentTime, duration, Boolean(session.status));

  useWakeLock(playing && !session.loading && !session.error);
  useTraktScrobble(session.scrobbleMedia, clock, playing, session.loading);

  const mediaActions = useMemo(() => ({
    play,
    pause,
    seekBy,
    seekTo,
    next: session.next ? session.playNext : undefined,
  }), [play, pause, seekBy, seekTo, session.next, session.playNext]);
  useMediaSession(session.media, playing, mediaActions, { time: currentTime, duration, rate: boosting ? 2 : rate });

  // Controls auto-hide while playing, unless something on screen needs them.
  const keepControls = !playing || panel !== null || showNextHover || upNext.countdown !== null || showShortcuts;
  useEffect(() => {
    let timeout: ReturnType<typeof setTimeout>;
    const hideAfter = (ms: number) => {
      clearTimeout(timeout);
      if (keepControls) return;
      timeout = setTimeout(() => {
        setShowControls(false);
        setCursorHidden(true);
      }, ms);
    };
    const onMove = () => {
      setShowControls(true);
      setCursorHidden(false);
      hideAfter(3000);
    };
    const onLeave = () => hideAfter(1000);
    const container = containerRef.current;
    document.addEventListener('mousemove', onMove);
    container?.addEventListener('mouseleave', onLeave);
    if (keepControls) {
      setShowControls(true);
      setCursorHidden(false);
    } else {
      hideAfter(3000);
    }
    return () => {
      document.removeEventListener('mousemove', onMove);
      container?.removeEventListener('mouseleave', onLeave);
      clearTimeout(timeout);
    };
  }, [keepControls]);

  const applyAspect = useCallback((mode: PlayerAspectMode) => {
    setAspect(mode);
    saveSettings({ playerAspectMode: mode });
  }, []);

  const changeRate = useCallback((next: number) => {
    const limited = Math.min(MAX_SPEED, Math.max(MIN_SPEED, Math.round(next * 100) / 100));
    setRate(limited);
    showFeedback(`Speed ${limited}x`);
  }, [showFeedback]);

  const chapterJump = useCallback((direction: -1 | 1) => {
    const { chapters } = session;
    if (chapters.length === 0) return;
    const now = videoRef.current?.currentTime ?? 0;
    const index = chapters.reduce((found, chapter, i) => (chapter.start <= now ? i : found), -1);
    if (direction === 1) {
      const next = chapters[index + 1];
      if (next) { seekTo(next.start); showFeedback(next.title); }
      return;
    }
    // Early in a chapter, go to the one before it; otherwise back to this one's start.
    const target = index > 0 && now - chapters[index].start < 3 ? chapters[index - 1] : chapters[Math.max(index, 0)];
    seekTo(target.start);
    showFeedback(target.title);
  }, [seekTo, session, showFeedback]);

  const cycleSubtitles = useCallback(() => {
    const { options, selectedId, select } = subtitles;
    if (options.length === 0) { showFeedback('No subtitle tracks'); return; }
    const index = options.findIndex((option) => option.id === selectedId);
    const next = options[index + 1] ?? null;
    select(next);
    showFeedback(next ? `Subtitles: ${next.label}` : 'Subtitles off');
  }, [showFeedback, subtitles]);

  const cycleAudio = useCallback(() => {
    const { options, selected, select } = session.audio;
    if (options.length <= 1) { showFeedback(options.length === 0 ? 'No audio tracks' : 'Only one audio track'); return; }
    const next = options[(options.findIndex((option) => option.id === selected) + 1) % options.length];
    select(next.id);
    showFeedback(`Audio: ${next.label}`);
  }, [session.audio, showFeedback]);

  usePlayerKeyboard({
    enabled: !session.sourcesRequest,
    togglePlay,
    seekBy,
    seekSmall: Math.max(1, settings.seekTimeSmall),
    seekLarge: Math.max(1, settings.seekTimeLarge),
    nudgeVolume: (delta) => setVolume((v) => Math.max(0, Math.min(1, v + delta))),
    toggleMute: () => setVolume((v) => (v === 0 ? lastVolume.current : 0)),
    toggleFullscreen,
    togglePiP: () => { pip.toggle(); },
    toggleStats: () => setShowStats((s) => !s),
    skipMarker: autoSkip.skip,
    previousChapter: () => chapterJump(-1),
    nextChapter: () => chapterJump(1),
    nudgeSubtitleDelay: (delta) => {
      const next = subtitles.delay + delta;
      subtitles.setDelay(next);
      showFeedback(`Subtitle offset ${next >= 0 ? '+' : ''}${next.toFixed(1)} s`);
    },
    cycleSubtitles,
    cycleAudio,
    stepSpeed: (delta) => changeRate(rate + delta),
    resetSpeed: () => changeRate(1),
    playNext: () => { if (session.next) session.playNext(); },
    cycleAspect: () => {
      const index = ASPECT_MODES.findIndex((mode) => mode.value === aspect);
      const next = ASPECT_MODES[(index + 1) % ASPECT_MODES.length];
      applyAspect(next.value);
      showFeedback(`Aspect: ${next.label}`);
    },
    toggleShortcuts: () => setShowShortcuts((s) => !s),
    escape: () => {
      if (showShortcuts) { setShowShortcuts(false); return true; }
      if (panel) { setPanel(null); return true; }
      if (document.fullscreenElement) { document.exitFullscreen().catch(() => {}); return true; }
      session.exit();
      return true;
    },
    startBoost: () => { setBoosting(true); showFeedback('Playing at 2x'); },
    endBoost: () => setBoosting(false),
  }, () => clock.playing.current);

  function onBackdropClick(e: React.MouseEvent) {
    const el = e.target as HTMLElement;
    if (el.closest('.player-controls') || el.closest('.player-panel') || el.closest('button') || el.closest('input') || el.closest('[role="dialog"]')) return;
    if (panel) { setPanel(null); return; }
    togglePlay();
  }

  const { media, error, status } = session;
  const hasEpisodeControls = media?.kind === 'episode';
  const heading = media?.kind === 'episode'
    ? [media.showTitle, episodeLabel(media.season, media.episode)].filter(Boolean).join(' - ')
    : media?.title;

  return (
    <div
      ref={containerRef}
      className="fixed inset-0 bg-black z-50 overflow-hidden"
      style={{ cursor: cursorHidden ? 'none' : 'auto' }}
      onClick={onBackdropClick}
    >
      {session.src && !error && (
        <div className="absolute inset-0" style={{ willChange: 'contents', transform: 'translateZ(0)', isolation: 'isolate' }}>
          <PlexVideoPlayer
            key={session.src}
            src={session.src}
            poster={media?.poster}
            videoRef={videoRef as React.RefObject<HTMLVideoElement>}
            playing={playing}
            volume={volume}
            playbackRate={boosting ? 2 : rate}
            autoPlay
            startTime={session.startAt}
            onTimeUpdate={handleTimeUpdate}
            onReady={() => { setBuffering(false); session.onReady?.(); }}
            onEnded={upNext.markEnded}
            onError={session.onEngineError}
            onBuffering={setBuffering}
            onPlayingChange={setPlaying}
            onCodecError={session.onCodecError}
            onUserSeek={upNext.clearEnded}
            onStatsUpdate={showStats ? setPlayerStats : undefined}
            streamKind={session.streamKind}
            crossOrigin={session.crossOrigin}
            objectFit={objectFitFor(aspect)}
            videoTransform={aspect === 'zoom' ? ZOOM_SCALE : undefined}
            onAudioTracks={session.onAudioTracks}
            audioTrackIndex={session.audioTrackIndex}
          />
        </div>
      )}

      {!error && <SubtitleOverlay cues={subtitles.cues} delay={subtitles.delay} videoRef={videoRef as React.RefObject<HTMLVideoElement>} controlsVisible={showControls} />}

      {(buffering || session.loading || status) && !error && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 pointer-events-none z-40">
          <div className="w-16 h-16 border-4 border-white/30 border-t-white rounded-full animate-spin" />
          {status && <div className="text-white text-base text-center px-6">{status.message}</div>}
          {status?.onCancel && (
            <button className="pointer-events-auto px-4 py-2 bg-white/10 hover:bg-white/20 rounded text-white" onClick={status.onCancel}>
              Cancel
            </button>
          )}
        </div>
      )}

      {session.notice && (
        <div className="absolute top-24 left-1/2 -translate-x-1/2 z-50">
          <div className="bg-yellow-600/90 text-white px-6 py-3 rounded-lg shadow-lg">{session.notice}</div>
        </div>
      )}

      {feedback && (
        <div className="absolute top-24 left-1/2 -translate-x-1/2 z-50 pointer-events-none">
          <div className="bg-black/80 text-white text-sm px-4 py-2 rounded-full ring-1 ring-white/15">{feedback}</div>
        </div>
      )}

      <PlaybackStatsHUD
        visible={showStats}
        position="top-left"
        stats={{
          ...session.stats,
          resolution: (session.stats.resolution as string | undefined) ?? (videoRef.current?.videoWidth ? `${videoRef.current.videoWidth}x${videoRef.current.videoHeight}` : undefined),
          currentTime,
          duration,
          bufferProgress: duration > 0 ? (buffered / duration) * 100 : 0,
          playbackRate: boosting ? 2 : rate,
          videoBitrate: playerStats.videoBitrate,
          audioBitrate: playerStats.audioBitrate ?? (session.stats.audioBitrate as number | undefined),
          downloadSpeed: playerStats.downloadSpeed,
          playableBufferSeconds: playerStats.bufferLength || realTimeStats.playableBufferSeconds,
          displayFPS: realTimeStats.displayFPS,
          droppedFrames: realTimeStats.droppedFrames,
          totalFrames: realTimeStats.totalFrames,
          isHardwareAccelerated: realTimeStats.isHardwareAccelerated,
        } as any}
      />

      {autoSkip.active && upNext.countdown === null && (
        <div className="absolute bottom-32 right-8 z-30 flex items-center gap-2">
          <button className="px-6 py-3 bg-white/20 hover:bg-white/30 backdrop-blur rounded-lg text-white font-medium transition-all" onClick={autoSkip.skip}>
            {skipLabel(autoSkip.active)}{autoSkip.countdown !== null ? ` (${autoSkip.countdown})` : ''}
          </button>
          {autoSkip.countdown !== null && (
            <button className="px-4 py-3 bg-white/10 hover:bg-white/20 backdrop-blur rounded-lg text-white" onClick={autoSkip.cancel}>Cancel</button>
          )}
        </div>
      )}

      {upNext.countdown !== null && session.next && (
        <div className="absolute bottom-32 right-8 z-40">
          <div className="bg-black/85 backdrop-blur rounded-xl p-4 ring-1 ring-white/10 shadow-2xl max-w-md">
            <div className="text-white text-base mb-1 font-semibold">Up Next • Playing in {upNext.countdown}s</div>
            <div className="text-white/90 mb-3 font-medium line-clamp-1">{session.next.title}</div>
            <div className="flex gap-2">
              <button className="px-4 py-2 bg-white/10 hover:bg-white/20 rounded text-white" onClick={() => { upNext.cancel(); autoSkip.cancel(); }}>Cancel</button>
              <button className="px-4 py-2 bg-brand hover:bg-brand-600 rounded text-white" onClick={upNext.playNow}>Play Now</button>
            </div>
          </div>
        </div>
      )}

      <div className={`absolute inset-0 bg-gradient-to-t from-black/70 via-transparent to-black/50 transition-opacity duration-300 ${showControls ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}>
        <div className="absolute top-0 left-0 right-0 p-6">
          <div className="flex items-center gap-4">
            <button className="p-2 rounded-full transition-colors text-white" onClick={session.exit} aria-label="Back">
              <BackIcon />
            </button>
            <div className="text-white">
              <div className="text-2xl font-bold">{heading}</div>
              {media?.kind === 'episode' && media.title && <div className="text-white/80">{media.title}</div>}
            </div>
          </div>
        </div>

        <div className="absolute bottom-0 left-0 right-0 p-6 player-controls">
          <div className="h-12 grid grid-cols-[1fr_auto] items-center gap-3">
            <SeekBar
              currentTime={currentTime}
              duration={duration}
              buffered={buffered}
              markers={session.markers}
              chapters={session.chapters}
              previewUrl={session.previewUrl}
              onSeek={(seconds) => { upNext.clearEnded(); seekTo(seconds); }}
            />
            {duration > 0 && (
              <span className="text-white text-sm font-medium drop-shadow whitespace-nowrap" title="Time remaining" style={{ marginTop: '-33px' }}>
                -{formatTime(Math.max(0, duration - currentTime))}
              </span>
            )}
          </div>

          <div className="flex flex-wrap items-center justify-between gap-y-1">
            <div className="flex items-center gap-1 sm:gap-4">
              <button className="w-14 h-14 sm:w-16 sm:h-16 flex items-center justify-center text-white bg-transparent transition-transform duration-150 ease-out hover:scale-110 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/30 rounded" onClick={togglePlay} aria-label={playing ? 'Pause' : 'Play'}>
                {playing ? <PauseIcon /> : <PlayIcon />}
              </button>
              <button className={SKIP_BUTTON} onClick={() => seekBy(-10)} aria-label="Back 10 seconds"><Replay10Icon className="w-8 h-8 text-white" /></button>
              <button className={SKIP_BUTTON} onClick={() => seekBy(10)} aria-label="Forward 10 seconds"><Forward10Icon className="w-8 h-8 text-white" /></button>
              <VolumeControl volume={volume} onChange={setVolume} />
            </div>

            <div className="flex flex-wrap items-center justify-end gap-1 sm:gap-4">
              {hasEpisodeControls && session.next && (
                <div className="relative">
                  <button
                    className={ICON_BUTTON}
                    onMouseEnter={() => setShowNextHover(true)}
                    onMouseLeave={() => setShowNextHover(false)}
                    onFocus={() => setShowNextHover(true)}
                    onBlur={() => setShowNextHover(false)}
                    onClick={session.playNext}
                    aria-label="Next Episode"
                    title="Next Episode"
                  >
                    <NextEpisodeIcon />
                  </button>
                  {showNextHover && (
                    <div className="absolute bottom-full right-0 mb-3 w-[42rem] max-w-[92vw] bg-black/90 rounded-xl ring-1 ring-white/10 overflow-hidden shadow-2xl z-50" role="dialog" aria-label="Next Episode">
                      <div className="px-6 py-4 text-2xl font-bold text-white bg-white/5">Next Episode</div>
                      <div className="p-4 grid grid-cols-1 md:grid-cols-2 gap-4 items-start">
                        <div className="relative aspect-video bg-black/40 rounded overflow-hidden">
                          {session.next.thumb && <img src={session.next.thumb} alt="" className="absolute inset-0 w-full h-full object-cover" />}
                          <div className="absolute inset-0 flex items-center justify-center">
                            <div className="w-16 h-16 rounded-full bg-black/50 flex items-center justify-center ring-1 ring-white/20"><PlayIcon className="w-10 h-10" /></div>
                          </div>
                        </div>
                        <div className="text-white/90">
                          <div className="text-sm text-white/60 mb-1">{session.next.label}</div>
                          <div className="text-xl font-bold mb-2">{session.next.title}</div>
                          <div className="text-white/80 leading-relaxed line-clamp-5">{session.next.summary}</div>
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              )}
              {session.browser && (
                <button className={ICON_BUTTON} onClick={() => togglePanel('episodes')} aria-label="Episodes" title="Episodes"><EpisodesIcon /></button>
              )}
              {session.chapters.length > 0 && (
                <button className={ICON_BUTTON} onClick={() => togglePanel('chapters')} aria-label="Chapters" title="Chapters"><ChaptersIcon /></button>
              )}
              {session.openSources && (
                <button className={ICON_BUTTON} onClick={session.openSources} aria-label="Sources" title="Sources"><SourcesIcon /></button>
              )}
              <button className={ICON_BUTTON} onClick={() => togglePanel('subtitles')} aria-label="Subtitles" title="Subtitles"><SubtitlesIcon /></button>
              <button className={ICON_BUTTON} onClick={() => togglePanel('settings')} aria-label="Settings" title="Settings"><SettingsIcon /></button>
              <button className={ICON_BUTTON} onClick={() => togglePanel('speed')} aria-label="Playback speed" title="Playback speed"><SpeedIcon /></button>
              {pip.supported && (
                <button className={ICON_BUTTON} onClick={() => pip.toggle()} aria-label="Picture in Picture" title="Picture in Picture"><PipIcon /></button>
              )}
              <button className={ICON_BUTTON} onClick={toggleFullscreen} aria-label={isFullscreen ? 'Exit Fullscreen' : 'Enter Fullscreen'}><FullscreenIcon active={isFullscreen} /></button>
            </div>
          </div>
        </div>

        <div className="player-panel">
          {panel === 'episodes' && session.browser && <EpisodesPanel browser={session.browser} onClose={closePanel} />}
          {panel === 'chapters' && <ChaptersPanel chapters={session.chapters} currentTime={currentTime} onSeek={seekTo} onClose={closePanel} />}
          {panel === 'speed' && <SpeedPanel rate={rate} onChange={(next) => { changeRate(next); closePanel(); }} />}
          {panel === 'settings' && <SettingsPanel session={session} aspect={aspect} onAspect={applyAspect} onDone={closePanel} />}
          {panel === 'subtitles' && <SubtitlePanel engine={subtitles} videoRef={videoRef as React.RefObject<HTMLVideoElement>} onClose={closePanel} />}
        </div>
      </div>

      {showShortcuts && <ShortcutsOverlay seekSmall={settings.seekTimeSmall} seekLarge={settings.seekTimeLarge} onClose={() => setShowShortcuts(false)} />}

      {error && (
        <div className="absolute inset-0 z-50 bg-black flex items-center justify-center p-6">
          <div className="text-white text-center max-w-lg">
            <div className="mb-6 text-lg">{error.message}</div>
            <div className="flex flex-wrap gap-2 justify-center">
              {error.canChooseSource && session.openSources && (
                <button className="px-4 py-2 bg-brand hover:bg-brand-600 rounded" onClick={session.openSources}>Choose another source</button>
              )}
              {error.detailsPath && (
                <a className="px-4 py-2 bg-white/10 hover:bg-white/20 rounded" href={error.detailsPath}>View details</a>
              )}
              <button className="px-4 py-2 bg-white/10 hover:bg-white/20 rounded" onClick={session.exit}>Go back</button>
            </div>
          </div>
        </div>
      )}

      {session.sourcesRequest && (
        <SourcesSheet
          open
          manual
          currentUrl={session.sourcesRequest.currentUrl}
          identity={session.sourcesRequest.identity}
          title={session.sourcesRequest.title}
          onClose={session.closeSources}
          onSelect={session.sourcesRequest.onSelect}
        />
      )}
    </div>
  );
}
