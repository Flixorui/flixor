import { useEffect, useRef } from 'react';
import { traktScrobbler } from '@/services/traktScrobble';
import type { PlayerClock, TraktMediaInfo } from '../types';

function percent(clock: PlayerClock): number {
  const duration = clock.duration.current;
  return duration > 0 ? Math.round((clock.time.current / duration) * 100) : 0;
}

/** Starts, pauses, updates and stops a Trakt scrobble for `media`. */
export function useTraktScrobble(media: TraktMediaInfo | null, clock: PlayerClock, playing: boolean, loading: boolean) {
  const started = useRef(false);
  const lastState = useRef<'playing' | 'paused' | null>(null);

  useEffect(() => {
    if (!media || loading) return;
    if (playing && !started.current) {
      started.current = true;
      traktScrobbler.startScrobble(media, percent(clock)).then((ok) => {
        started.current = ok;
        if (ok) lastState.current = 'playing';
      });
      return;
    }
    if (started.current && lastState.current && lastState.current !== (playing ? 'playing' : 'paused')) {
      if (playing) traktScrobbler.resumeScrobble(percent(clock));
      else traktScrobbler.pauseScrobble(percent(clock));
      lastState.current = playing ? 'playing' : 'paused';
    }
  }, [media, playing, loading, clock]);

  useEffect(() => {
    const interval = setInterval(() => {
      if (started.current && clock.playing.current) traktScrobbler.updateProgress(percent(clock));
    }, 15_000);
    return () => clearInterval(interval);
  }, [clock]);

  useEffect(() => () => {
    if (started.current && clock.duration.current > 0) traktScrobbler.stopScrobble(percent(clock));
    started.current = false;
    lastState.current = null;
  }, [clock]);
}
