/**
 * "Explore More" as a glass menu that grows out of the pill (Netflix-style),
 * with Movies and Shows genre submenus from the Plex library, and the libraries themselves.
 * "All Categories…" still opens the full sheet.
 */

import React, { useEffect, useState } from 'react';
import GlassMenu, { type GlassMenuItem } from './GlassMenu';
import { fetchLibraries, fetchMovieGenres, fetchTvGenres, type GenreItem } from '../core/HomeData';

export type CategoryPick =
  | { kind: 'genre'; type: 'movie' | 'tv'; genre: GenreItem }
  | { kind: 'library'; library: { key: string; title: string; type: string } }
  | { kind: 'all' };

type Data = {
  movies: GenreItem[];
  shows: GenreItem[];
  libraries: Array<{ key: string; title: string; type: string }>;
};

let cache: Data | null = null;

export default function CategoriesMenu({ onPick, children }: { onPick: (pick: CategoryPick) => void; children: React.ReactNode }) {
  const [data, setData] = useState<Data | null>(cache);

  useEffect(() => {
    if (cache) return;
    let cancelled = false;
    Promise.all([fetchMovieGenres(), fetchTvGenres(), fetchLibraries()]).then(([movies, shows, libraries]) => {
      cache = { movies, shows, libraries: libraries.filter((l) => l.type === 'movie' || l.type === 'show') };
      if (!cancelled) setData(cache);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const items: GlassMenuItem[] = [];
  if (data?.movies.length) {
    items.push({
      title: 'Movies',
      icon: 'film-outline',
      children: data.movies.map((g) => ({ title: g.title, onPress: () => onPick({ kind: 'genre', type: 'movie', genre: g }) })),
    });
  }
  if (data?.shows.length) {
    items.push({
      title: 'Shows',
      icon: 'tv-outline',
      children: data.shows.map((g) => ({ title: g.title, onPress: () => onPick({ kind: 'genre', type: 'tv', genre: g }) })),
    });
  }
  if (data && data.libraries.length > 1) {
    items.push({
      title: 'Libraries',
      icon: 'albums-outline',
      children: data.libraries.map((l) => ({ title: l.title, onPress: () => onPick({ kind: 'library', library: l }) })),
    });
  }
  items.push({ title: 'All Categories…', icon: 'grid-outline', onPress: () => onPick({ kind: 'all' }) });

  return (
    <GlassMenu items={items} accessibilityLabel="Explore categories">
      {children}
    </GlassMenu>
  );
}
