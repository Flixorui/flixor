import { useEffect, useRef } from 'react';

export interface KeyboardActions {
  enabled: boolean;
  togglePlay: () => void;
  seekBy: (seconds: number) => void;
  seekSmall: number;
  seekLarge: number;
  nudgeVolume: (delta: number) => void;
  toggleMute: () => void;
  toggleFullscreen: () => void;
  togglePiP: () => void;
  toggleStats: () => void;
  skipMarker: () => void;
  previousChapter: () => void;
  nextChapter: () => void;
  nudgeSubtitleDelay: (delta: number) => void;
  cycleSubtitles: () => void;
  cycleAudio: () => void;
  stepSpeed: (delta: number) => void;
  resetSpeed: () => void;
  playNext: () => void;
  cycleAspect: () => void;
  toggleShortcuts: () => void;
  /** Closes the top-most layer. Returns false when there was nothing left to close. */
  escape: () => boolean;
  startBoost: () => void;
  endBoost: () => void;
}

const HOLD_DELAY_MS = 400;
const FINE_SEEK_SECONDS = 2;
const VOLUME_STEP = 0.05;
const SPEED_STEP = 0.25;
const SUBTITLE_STEP = 0.1;

function isTyping(target: EventTarget | null): boolean {
  const element = target as HTMLElement | null;
  if (!element?.tagName) return false;
  return ['INPUT', 'TEXTAREA', 'SELECT'].includes(element.tagName) || element.isContentEditable;
}

export function usePlayerKeyboard(actions: KeyboardActions, isPlaying: () => boolean) {
  const latest = useRef(actions);
  latest.current = actions;
  const playingRef = useRef(isPlaying);
  playingRef.current = isPlaying;

  useEffect(() => {
    let spaceHeld = false;
    let boosted = false;
    let holdTimer: ReturnType<typeof setTimeout> | null = null;

    const clearHold = () => {
      if (holdTimer) clearTimeout(holdTimer);
      holdTimer = null;
    };

    const releaseHold = () => {
      clearHold();
      spaceHeld = false;
      if (boosted) {
        boosted = false;
        latest.current.endBoost();
      }
    };

    const onKeyUp = (e: KeyboardEvent) => {
      if (e.code !== 'Space' || !spaceHeld) return;
      e.preventDefault();
      clearHold();
      spaceHeld = false;
      if (boosted) {
        boosted = false;
        latest.current.endBoost();
      } else {
        latest.current.togglePlay();
      }
    };

    const onKeyDown = (e: KeyboardEvent) => {
      const a = latest.current;
      if (!a.enabled || isTyping(e.target)) return;

      if (e.key === 'Escape') {
        if (!e.repeat && a.escape()) e.preventDefault();
        return;
      }

      if (e.code === 'Space') {
        e.preventDefault();
        if (e.repeat || spaceHeld) return;
        spaceHeld = true;
        boosted = false;
        holdTimer = setTimeout(() => {
          // Paused: holding has nothing to speed up, so the release just plays.
          if (!spaceHeld || !playingRef.current()) return;
          boosted = true;
          latest.current.startBoost();
        }, HOLD_DELAY_MS);
        return;
      }

      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        e.preventDefault();
        const step = e.altKey ? FINE_SEEK_SECONDS : e.shiftKey ? a.seekLarge : a.seekSmall;
        a.seekBy(e.key === 'ArrowLeft' ? -step : step);
        return;
      }
      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        e.preventDefault();
        a.nudgeVolume(e.key === 'ArrowUp' ? VOLUME_STEP : -VOLUME_STEP);
        return;
      }

      // Leave Cmd+F, Ctrl+P and the like to the browser.
      if (e.metaKey || e.ctrlKey) return;

      const once = (run: () => void) => { if (!e.repeat) run(); };
      switch (e.key) {
        case 'k': case 'K': once(a.togglePlay); break;
        case 'm': case 'M': once(a.toggleMute); break;
        case 'f': case 'F': once(a.toggleFullscreen); break;
        case 'p': case 'P': once(a.togglePiP); break;
        case 'i': case 'I': once(a.toggleStats); break;
        case 's': case 'S': once(a.skipMarker); break;
        case 'j': case 'J': a.seekBy(-a.seekLarge); break;
        case 'l': case 'L': a.seekBy(a.seekLarge); break;
        case '[': a.previousChapter(); break;
        case ']': a.nextChapter(); break;
        case 'g': case 'G': a.nudgeSubtitleDelay(-SUBTITLE_STEP); break;
        case 'h': case 'H': a.nudgeSubtitleDelay(SUBTITLE_STEP); break;
        case 'v': case 'V': once(a.cycleSubtitles); break;
        case 'b': case 'B': once(a.cycleAudio); break;
        case '<': case ',': a.stepSpeed(-SPEED_STEP); break;
        case '>': case '.': a.stepSpeed(SPEED_STEP); break;
        case '/': a.resetSpeed(); break;
        case 'N': once(a.playNext); break;
        case 'a': case 'A': once(a.cycleAspect); break;
        case '?': once(a.toggleShortcuts); break;
        default: return;
      }
      e.preventDefault();
    };

    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', releaseHold);
    return () => {
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      window.removeEventListener('blur', releaseHold);
      releaseHold();
    };
  }, []);
}
