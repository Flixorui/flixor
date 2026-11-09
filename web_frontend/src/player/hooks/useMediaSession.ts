import { useEffect, useRef } from 'react';
import type { PlayerMedia } from '../types';

interface Actions {
  play: () => void;
  pause: () => void;
  seekBy: (seconds: number) => void;
  seekTo: (seconds: number) => void;
  next?: () => void;
}

/** Now Playing metadata and media keys through the Media Session API. */
export function useMediaSession(
  media: PlayerMedia | null,
  playing: boolean,
  actions: Actions,
  position: { time: number; duration: number; rate: number },
) {
  const latest = useRef(actions);
  latest.current = actions;
  const hasNext = Boolean(actions.next);

  useEffect(() => {
    if (!('mediaSession' in navigator) || !media) return;
    const title = media.kind === 'episode' ? media.title || `Episode ${media.episode ?? ''}` : media.title;
    navigator.mediaSession.metadata = new MediaMetadata({
      title,
      artist: media.showTitle ?? '',
      album: media.kind === 'episode' && media.season !== undefined ? `Season ${media.season}` : '',
      artwork: media.poster ? [{ src: media.poster }] : [],
    });
    return () => { navigator.mediaSession.metadata = null; };
  }, [media]);

  useEffect(() => {
    if (!('mediaSession' in navigator)) return;
    navigator.mediaSession.playbackState = playing ? 'playing' : 'paused';
  }, [playing]);

  useEffect(() => {
    if (!('mediaSession' in navigator)) return;
    const session = navigator.mediaSession;
    const handlers: Array<[MediaSessionAction, MediaSessionActionHandler | null]> = [
      ['play', () => latest.current.play()],
      ['pause', () => latest.current.pause()],
      ['seekbackward', (detail) => latest.current.seekBy(-(detail.seekOffset || 10))],
      ['seekforward', (detail) => latest.current.seekBy(detail.seekOffset || 10)],
      ['seekto', (detail) => { if (detail.seekTime !== undefined) latest.current.seekTo(detail.seekTime); }],
      ['nexttrack', hasNext ? () => latest.current.next?.() : null],
    ];
    for (const [action, handler] of handlers) {
      try { session.setActionHandler(action, handler); } catch {}
    }
    return () => {
      for (const [action] of handlers) {
        try { session.setActionHandler(action, null); } catch {}
      }
    };
  }, [hasNext]);

  // Whole seconds: an exact position would update the OS UI on every tick.
  const seconds = Math.floor(position.time);
  useEffect(() => {
    if (!('mediaSession' in navigator) || !navigator.mediaSession.setPositionState) return;
    if (!(position.duration > 0) || !Number.isFinite(position.duration)) return;
    try {
      navigator.mediaSession.setPositionState({
        duration: position.duration,
        position: Math.min(seconds, position.duration),
        playbackRate: position.rate || 1,
      });
    } catch {}
  }, [seconds, position.duration, position.rate]);
}
