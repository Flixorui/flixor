/**
 * The film or show a disc is of, as a TMDB item for Details: the edition's
 * Blu-ray.com film gives the IMDb id, and TMDB finds it (movie first, then
 * TV, so season box sets open the show). Without an IMDb id, a TMDB movie
 * search by the cleaned disc title and year (±1).
 * macOS reference: PlexDiscMatcher.titleItem in Views/Library/PhysicalCollectionView.swift
 */
import { getFlixorCore } from '../index';
import { getMovie } from './service';
import { cleanedDiscTitle, normalized } from './plexMatch';
import type { MBEdition } from './types';

export type DiscTitle = { mediaType: 'movie' | 'tv'; id: string };

export async function findDiscTitle(edition: MBEdition): Promise<DiscTitle | null> {
  const tmdb = getFlixorCore().tmdb;
  try {
    const movie = edition.movieId ? await getMovie(edition.movieId) : null;
    const imdbId = /tt\d{7,10}/.exec(movie?.imdbId ?? '')?.[0];
    if (imdbId) {
      const found = await tmdb.findByImdbId(imdbId);
      const film = found?.movie_results?.[0];
      if (film?.id) return { mediaType: 'movie', id: String(film.id) };
      const show = found?.tv_results?.[0];
      if (show?.id) return { mediaType: 'tv', id: String(show.id) };
    }
    const title = cleanedDiscTitle(movie?.title ?? edition.title ?? '');
    if (!title) return null;
    const year = movie?.year ?? edition.year ?? null;
    const wanted = normalized(title);
    const results: any[] = (await tmdb.searchMovies(title))?.results ?? [];
    const hit = results.find((r) => {
      if (normalized(String(r?.title ?? '')) !== wanted) return false;
      const y = Number(String(r?.release_date ?? '').slice(0, 4));
      return !year || !y || Math.abs(y - year) <= 1;
    });
    return hit?.id ? { mediaType: 'movie', id: String(hit.id) } : null;
  } catch {
    return null;
  }
}
