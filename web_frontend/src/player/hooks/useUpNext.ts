import { useCallback, useEffect, useRef, useState } from 'react';
import { useSettings } from '@/state/settings';
import { nextEpisodeTrigger } from '../markers';
import type { PlayerSession } from '../types';

const COUNTDOWN_SECONDS = 5;
const PREFETCH_LEAD_SECONDS = 60;

/** Next-episode countdown near the end, and the movie exit at the credits. */
export function useUpNext(session: PlayerSession, currentTime: number, duration: number, busy: boolean) {
  const { autoPlayNext, creditsCountdownFallback } = useSettings();
  const { media, next, markers, chapters } = session;
  const [countdown, setCountdown] = useState<number | null>(null);
  const dismissed = useRef(false);
  const ended = useRef(false);
  const sessionRef = useRef(session);
  sessionRef.current = session;

  useEffect(() => {
    if (media?.kind !== 'episode' || !next || duration <= 0 || !autoPlayNext) {
      setCountdown(null);
      return;
    }
    const trigger = nextEpisodeTrigger(markers, chapters, duration, creditsCountdownFallback);
    if (currentTime >= trigger - PREFETCH_LEAD_SECONDS) sessionRef.current.prefetchNext?.();
    if (currentTime >= trigger) {
      if (!dismissed.current && !busy) setCountdown((value) => value ?? COUNTDOWN_SECONDS);
    } else {
      // Seeked back before the trigger: the countdown may run again later.
      dismissed.current = false;
      setCountdown(null);
    }
  }, [media, next, markers, chapters, duration, currentTime, autoPlayNext, creditsCountdownFallback, busy]);

  useEffect(() => {
    if (countdown === null) return;
    if (countdown <= 0) {
      setCountdown(null);
      dismissed.current = true; // A cancelled lookup must not restart the countdown.
      sessionRef.current.playNext();
      return;
    }
    const timer = setTimeout(() => setCountdown((value) => (value === null ? null : value - 1)), 1000);
    return () => clearTimeout(timer);
  }, [countdown]);

  const cancel = useCallback(() => {
    dismissed.current = true;
    setCountdown(null);
  }, []);

  const playNow = useCallback(() => {
    dismissed.current = true;
    setCountdown(null);
    sessionRef.current.playNext();
  }, []);

  // Movies from Plex leave for Details at the credits.
  useEffect(() => {
    if (!session.exitAtCredits || media?.kind !== 'movie' || duration <= 0 || currentTime <= 1) return;
    const credits = markers.find((marker) => marker.type === 'credits');
    if (currentTime >= (credits ? credits.start : Math.max(0, duration - creditsCountdownFallback))) {
      sessionRef.current.goToDetails();
    }
  }, [session.exitAtCredits, media, markers, currentTime, duration, creditsCountdownFallback]);

  // Some MSE edge cases reach the end without firing `ended`.
  useEffect(() => {
    if (duration <= 0 || ended.current) return;
    if (currentTime >= Math.max(0, duration - 0.25)) {
      ended.current = true;
      sessionRef.current.onEnded();
    }
  }, [currentTime, duration]);

  const markEnded = useCallback(() => {
    if (ended.current) return;
    ended.current = true;
    sessionRef.current.onEnded();
  }, []);

  const clearEnded = useCallback(() => {
    ended.current = false;
  }, []);

  return { countdown, cancel, playNow, markEnded, clearEnded };
}
