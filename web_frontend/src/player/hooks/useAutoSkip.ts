import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { getSettings } from '@/state/settings';
import { isSkippable } from '../markers';
import type { PlayerMarker, PlayerSession } from '../types';

function shouldAutoSkip(type: string): boolean {
  const settings = getSettings();
  if (type === 'intro') return settings.skipIntroAutomatically;
  if (type === 'credits') return settings.skipCreditsAutomatically;
  if (type === 'recap') return settings.skipRecapAutomatically;
  return false;
}

/** The skip button's marker, and the countdown that presses it automatically. */
export function useAutoSkip(session: PlayerSession, currentTime: number, seek: (seconds: number) => void) {
  const { markers, media, next } = session;
  const [countdown, setCountdown] = useState<number | null>(null);
  const triggered = useRef(new Set<string>());

  const active = useMemo<PlayerMarker | null>(
    () => markers.find((marker) => isSkippable(marker) && currentTime >= marker.start && currentTime <= marker.end) ?? null,
    [markers, currentTime],
  );
  const activeId = active?.id ?? null;

  const skip = useCallback(() => {
    if (!active) return;
    triggered.current.add(active.id);
    setCountdown(null);
    if (active.type === 'credits') {
      if (media?.kind === 'movie') { session.goToDetails(); return; }
      if (active.final && next) { session.playNext(); return; }
    }
    seek(active.end + 1);
  }, [active, media, next, seek, session]);

  const cancel = useCallback(() => {
    if (active) triggered.current.add(active.id);
    setCountdown(null);
  }, [active]);

  // A new marker starts the countdown once; leaving it cancels.
  useEffect(() => {
    if (!active || triggered.current.has(active.id) || !shouldAutoSkip(active.type)) {
      setCountdown(null);
      return;
    }
    triggered.current.add(active.id);
    setCountdown(Math.max(0, getSettings().autoSkipDelay));
    // Keyed on the id: `active` is a new object whenever the marker list rebuilds.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeId]);

  const skipRef = useRef(skip);
  skipRef.current = skip;
  useEffect(() => {
    if (countdown === null) return;
    if (countdown <= 0) { skipRef.current(); return; }
    const timer = setTimeout(() => setCountdown((value) => (value === null ? null : value - 1)), 1000);
    return () => clearTimeout(timer);
  }, [countdown]);

  return { active, countdown, skip, cancel };
}
