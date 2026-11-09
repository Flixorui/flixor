import { useCallback, useRef, useState } from 'react';
import type { EpisodeBrowser, EpisodeEntry } from '../types';

interface Options {
  currentSeason: number | null;
  /** Episodes of the playing season, already loaded by the session. */
  currentEpisodes: EpisodeEntry[];
  loadSeasons: () => Promise<number[]>;
  loadEpisodes: (season: number) => Promise<EpisodeEntry[]>;
  play: (entry: EpisodeEntry) => void;
}

/** Season selector and episode list state, shared by Plex and addon sessions. */
export function useEpisodeBrowserState(options: Options): EpisodeBrowser {
  const latest = useRef(options);
  latest.current = options;
  const [seasons, setSeasons] = useState<number[]>([]);
  const [browsing, setBrowsing] = useState<{ season: number; episodes: EpisodeEntry[] } | null>(null);
  const [loading, setLoading] = useState(false);
  const seasonsLoaded = useRef(false);
  const requested = useRef<number | null>(null);

  const open = useCallback(() => {
    requested.current = null;
    setBrowsing(null);
    setLoading(false);
    if (seasonsLoaded.current) return;
    seasonsLoaded.current = true;
    latest.current.loadSeasons().then(setSeasons, () => { seasonsLoaded.current = false; });
  }, []);

  const selectSeason = useCallback((season: number) => {
    requested.current = season;
    if (season === latest.current.currentSeason && latest.current.currentEpisodes.length > 0) {
      setBrowsing(null);
      setLoading(false);
      return;
    }
    setBrowsing({ season, episodes: [] });
    setLoading(true);
    latest.current.loadEpisodes(season).then(
      (episodes) => {
        if (requested.current !== season) return;
        setBrowsing({ season, episodes });
        setLoading(false);
      },
      () => {
        if (requested.current !== season) return;
        setBrowsing({ season, episodes: [] });
        setLoading(false);
      },
    );
  }, []);

  const play = useCallback((entry: EpisodeEntry) => latest.current.play(entry), []);

  return {
    seasons,
    season: browsing?.season ?? options.currentSeason,
    episodes: browsing ? browsing.episodes : options.currentEpisodes,
    loading,
    open,
    selectSeason,
    play,
  };
}
