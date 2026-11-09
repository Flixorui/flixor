/** Filtered TMDB discovery for the Search screen. */
import { tmdbDiscoverMovies, tmdbDiscoverTV, tmdbImage } from '@/services/tmdb';
import type { SearchDiscoverFilters } from '@/state/settings';
import type { CardItem } from '@/components/cards/cardTypes';

export const DEFAULT_DISCOVER_FILTERS: SearchDiscoverFilters = { mediaType: 'movie', sort: 'popular' };

export const DISCOVER_SORTS: Array<{ value: SearchDiscoverFilters['sort']; label: string }> = [
  { value: 'popular', label: 'Popular' },
  { value: 'topRated', label: 'Top Rated' },
  { value: 'newest', label: 'Newest' },
  { value: 'oldest', label: 'Oldest' },
  { value: 'title', label: 'Title (A-Z)' },
];

/** TMDB's fixed genre ids. The backend has no genre-list route. */
export const DISCOVER_GENRES: Record<'movie' | 'tv', Array<{ id: number; name: string }>> = {
  movie: [
    { id: 28, name: 'Action' }, { id: 12, name: 'Adventure' }, { id: 16, name: 'Animation' }, { id: 35, name: 'Comedy' },
    { id: 80, name: 'Crime' }, { id: 99, name: 'Documentary' }, { id: 18, name: 'Drama' }, { id: 10751, name: 'Family' },
    { id: 14, name: 'Fantasy' }, { id: 36, name: 'History' }, { id: 27, name: 'Horror' }, { id: 10402, name: 'Music' },
    { id: 9648, name: 'Mystery' }, { id: 10749, name: 'Romance' }, { id: 878, name: 'Science Fiction' }, { id: 53, name: 'Thriller' },
    { id: 10752, name: 'War' }, { id: 37, name: 'Western' },
  ],
  tv: [
    { id: 10759, name: 'Action & Adventure' }, { id: 16, name: 'Animation' }, { id: 35, name: 'Comedy' }, { id: 80, name: 'Crime' },
    { id: 99, name: 'Documentary' }, { id: 18, name: 'Drama' }, { id: 10751, name: 'Family' }, { id: 10762, name: 'Kids' },
    { id: 9648, name: 'Mystery' }, { id: 10763, name: 'News' }, { id: 10764, name: 'Reality' }, { id: 10765, name: 'Sci-Fi & Fantasy' },
    { id: 10766, name: 'Soap' }, { id: 10767, name: 'Talk' }, { id: 10768, name: 'War & Politics' }, { id: 37, name: 'Western' },
  ],
};

/** Keeps the year range ordered, and drops values TMDB would reject. */
export function normalizeDiscoverFilters(filters: SearchDiscoverFilters | null): SearchDiscoverFilters {
  const next = { ...DEFAULT_DISCOVER_FILTERS, ...(filters ?? {}) };
  if (next.yearFrom && next.yearTo && next.yearFrom > next.yearTo) {
    [next.yearFrom, next.yearTo] = [next.yearTo, next.yearFrom];
  }
  return next;
}

export function hasActiveDiscoverFilters(filters: SearchDiscoverFilters) {
  return !!(filters.genreId || filters.sort !== 'popular' || filters.yearFrom || filters.yearTo || filters.minimumRating);
}

export function discoverParams(filters: SearchDiscoverFilters, page: number, today = new Date().toISOString().slice(0, 10)) {
  const movie = filters.mediaType === 'movie';
  const dateField = movie ? 'primary_release_date' : 'first_air_date';
  const params: Record<string, string | number> = { page };

  let minimumVotes = 0;
  switch (filters.sort) {
    case 'popular':
      params.sort_by = 'popularity.desc';
      break;
    case 'topRated':
      params.sort_by = 'vote_average.desc';
      minimumVotes = 200;
      break;
    case 'newest':
      params.sort_by = `${dateField}.desc`;
      break;
    case 'oldest':
      params.sort_by = `${dateField}.asc`;
      minimumVotes = 50;
      break;
    case 'title':
      params.sort_by = movie ? 'title.asc' : 'name.asc';
      minimumVotes = 100;
      break;
  }
  if (filters.minimumRating) {
    params['vote_average.gte'] = filters.minimumRating;
    minimumVotes = Math.max(minimumVotes, 50);
  }
  if (minimumVotes) params['vote_count.gte'] = minimumVotes;
  if (filters.genreId) params.with_genres = filters.genreId;
  if (filters.yearFrom) params[`${dateField}.gte`] = `${filters.yearFrom}-01-01`;
  if (filters.yearTo) params[`${dateField}.lte`] = `${filters.yearTo}-12-31`;
  else if (filters.sort === 'newest') params[`${dateField}.lte`] = today;
  return params;
}

export async function fetchDiscoverPage(filters: SearchDiscoverFilters, page: number): Promise<{ items: CardItem[]; totalPages: number }> {
  const params = discoverParams(filters, page);
  const res: any = filters.mediaType === 'movie' ? await tmdbDiscoverMovies('', params) : await tmdbDiscoverTV('', params);
  const media = filters.mediaType;
  const items: CardItem[] = (res?.results || []).map((r: any) => ({
    id: `tmdb:${media}:${r.id}`,
    title: r.title || r.name,
    image: tmdbImage(r.poster_path, 'w500') || tmdbImage(r.backdrop_path, 'w780'),
    backdrop: tmdbImage(r.backdrop_path, 'w780'),
    mediaType: media === 'movie' ? 'movie' : 'show',
    year: String(r.release_date || r.first_air_date || '').slice(0, 4) || undefined,
    rating: r.vote_average || undefined,
    overview: r.overview || undefined,
  }));
  return { items, totalPages: res?.total_pages ?? page };
}
