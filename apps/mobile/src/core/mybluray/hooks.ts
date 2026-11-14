/**
 * React hooks over MyBlurayService. They never block a screen: Details
 * renders from Plex/TMDB and these fill in (a title the server hasn't stored
 * can take ~9 s).
 */
import { useEffect, useState } from 'react';
import type { AppSettings } from '../SettingsData';
import { effectiveDiscCountry, isMyBlurayActive, isMyBlurayOn } from './options';
import { getEdition, getEditions, getParentsGuide, getTitle, normalizedImdbId, resolveMovie } from './service';
import type { MBEdition, MBEditionSummary, MBMovie, MBParentsGuide, MBTitle } from './types';

/** Settings that change what MyBluray loads (so hooks re-run when they change). */
function settingsKey(s: AppSettings): string {
  return [s.myblurayApiKey ?? '', s.myblurayEnabled, JSON.stringify(s.myblurayOptions ?? {}), s.myblurayDiscCountry].join('|');
}

/** Ratings, Common Sense, certifications, videos and source links for one title. */
export function useMyBlurayTitle(imdbId: string | undefined, settings: AppSettings) {
  const [title, setTitle] = useState<MBTitle | null>(null);
  const [loading, setLoading] = useState(false);
  /** The id whose lookup has finished (found or not). */
  const [settledId, setSettledId] = useState<string | null>(null);
  const id = normalizedImdbId(imdbId);
  const active = isMyBlurayActive(settings);
  const allVideos = isMyBlurayOn('bonusVideos', settings);
  useEffect(() => {
    setTitle(null);
    if (!id || !active) return;
    let cancelled = false;
    setLoading(true);
    getTitle(id, allVideos)
      .then((t) => !cancelled && setTitle(t))
      .catch((e) => console.log('[MyBluray] title', id, e?.kind ?? e))
      .finally(() => {
        if (cancelled) return;
        setLoading(false);
        setSettledId(id);
      });
    return () => {
      cancelled = true;
    };
  }, [id, active, allVideos, settings.myblurayApiKey]);
  return { title, loading, settled: !!id && settledId === id };
}

/** IMDb's parents guide; null when there isn't one worth showing. */
export function useParentsGuide(imdbId: string | undefined, settings: AppSettings) {
  const [guide, setGuide] = useState<MBParentsGuide | null>(null);
  const id = normalizedImdbId(imdbId);
  const on = isMyBlurayOn('imdbGuide', settings);
  useEffect(() => {
    setGuide(null);
    if (!id || !on) return;
    let cancelled = false;
    getParentsGuide(id)
      .then((g) => !cancelled && setGuide(g && g.categories.length ? g : null))
      .catch((e) => console.log('[MyBluray] guide', id, e?.kind ?? e));
    return () => {
      cancelled = true;
    };
  }, [id, on, settings.myblurayApiKey]);
  return guide;
}

export interface PhysicalReleases {
  movie: MBMovie | null;
  editions: MBEditionSummary[];
  /** The market asked for; undefined for all markets. */
  country?: string;
  /** The chosen market had none, so these are from every market. */
  fellBack: boolean;
  loading: boolean;
  error?: string;
}

/** Blu-ray.com editions of a movie for the chosen market, falling back to all markets. */
export function usePhysicalReleases(imdbId: string | undefined, isMovie: boolean, settings: AppSettings): PhysicalReleases {
  const [result, setResult] = useState<PhysicalReleases>({ movie: null, editions: [], fellBack: false, loading: false });
  const id = normalizedImdbId(imdbId);
  const on = isMovie && isMyBlurayOn('physicalReleases', settings);
  const key = settingsKey(settings);
  useEffect(() => {
    setResult({ movie: null, editions: [], fellBack: false, loading: false });
    if (!id || !on) return;
    let cancelled = false;
    const formats: string[] = [];
    if (isMyBlurayOn('blurayFormat', settings)) formats.push('bluray');
    if (isMyBlurayOn('uhdFormat', settings)) formats.push('4k');
    if (!formats.length) return;
    const boxSets = isMyBlurayOn('boxSets', settings);
    const country = effectiveDiscCountry(settings);
    setResult((r) => ({ ...r, loading: true }));
    (async () => {
      try {
        const movie = await resolveMovie(id);
        if (!movie) {
          if (!cancelled) setResult({ movie: null, editions: [], fellBack: false, loading: false });
          return;
        }
        const filter = (list: MBEditionSummary[]) => (boxSets ? list : list.filter((e) => !e.bundle));
        let editions = filter(await getEditions(movie.id, country, formats));
        let fellBack = false;
        if (!editions.length && country) {
          editions = filter(await getEditions(movie.id, undefined, formats));
          fellBack = editions.length > 0;
        }
        editions = sortEditions(editions);
        if (!cancelled) setResult({ movie, editions, country: fellBack ? undefined : country, fellBack, loading: false });
      } catch (e: any) {
        console.log('[MyBluray] editions', id, e?.kind ?? e);
        if (!cancelled) setResult({ movie: null, editions: [], fellBack: false, loading: false, error: String(e?.kind ?? e) });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [id, on, key]);
  return result;
}

/** 4K first, then newest first. */
export function sortEditions(list: MBEditionSummary[]): MBEditionSummary[] {
  return [...list].sort((a, b) => {
    const ua = (a.format ?? '').toLowerCase() === '4k' ? 0 : 1;
    const ub = (b.format ?? '').toLowerCase() === '4k' ? 0 : 1;
    if (ua !== ub) return ua - ub;
    return (b.releaseDate ?? '').localeCompare(a.releaseDate ?? '');
  });
}

export function useEdition(id: string | undefined) {
  const [edition, setEdition] = useState<MBEdition | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);
  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    getEdition(id)
      .then((e) => !cancelled && setEdition(e))
      .catch((e) => !cancelled && setError(e))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [id]);
  return { edition, loading, error };
}
