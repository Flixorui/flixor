/**
 * Artwork with the title designed into it, as the macOS cards use: TMDB's English
 * backdrop for landscape cards and English poster for portrait ones, falling back to
 * other titled art, then textless art, then the image the row already has.
 */
import { useEffect, useState } from 'react';
import { tmdbImage, tmdbImages } from '@/services/tmdb';

type Shape = 'landscape' | 'portrait';

interface TmdbImage {
  file_path?: string;
  iso_639_1?: string | null;
  vote_average?: number;
}

const resolved = new Map<string, string | null>();

function best(list: TmdbImage[]): TmdbImage | undefined {
  return [...list].sort((a, b) => (b.vote_average ?? 0) - (a.vote_average ?? 0))[0];
}

/** Pure: the titled image to use from a TMDB images response. Exported for tests. */
export function pickTitledArtwork(images: { backdrops?: TmdbImage[]; posters?: TmdbImage[] }, shape: Shape): string | undefined {
  const list = (shape === 'landscape' ? images.backdrops : images.posters) ?? [];
  const pick = best(list.filter((i) => i.iso_639_1 === 'en'))
    ?? best(list.filter((i) => i.iso_639_1))
    ?? best(list);
  return pick?.file_path;
}

function tmdbRef(id: string): { media: 'movie' | 'tv'; tmdbId: string } | null {
  const match = /^tmdb:(movie|tv):(\d+)$/.exec(id);
  return match ? { media: match[1] as 'movie' | 'tv', tmdbId: match[2] } : null;
}

/** The titled artwork URL for a `tmdb:<media>:<id>` item, or `fallback` until (or unless) one is found. */
export function useTitledArtwork(id: string, shape: Shape, fallback?: string): string | undefined {
  const key = `${shape}:${id}`;
  const [url, setUrl] = useState<string | undefined>(() => resolved.get(key) ?? fallback);

  useEffect(() => {
    const ref = tmdbRef(id);
    if (!ref) {
      setUrl(fallback);
      return;
    }
    const known = resolved.get(key);
    if (known !== undefined) {
      setUrl(known ?? fallback);
      return;
    }
    let cancelled = false;
    tmdbImages('', ref.media, ref.tmdbId, 'en,null')
      .then((images: any) => {
        const path = pickTitledArtwork(images ?? {}, shape);
        const found = path ? tmdbImage(path, shape === 'landscape' ? 'w780' : 'w500') ?? null : null;
        resolved.set(key, found);
        if (!cancelled) setUrl(found ?? fallback);
      })
      .catch(() => {
        if (!cancelled) setUrl(fallback);
      });
    return () => {
      cancelled = true;
    };
  }, [id, key, shape, fallback]);

  return url;
}
