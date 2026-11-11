/**
 * Data for the Netflix-style Shows / Movies pages: a billboard from the library and rows
 * built from Plex sorts and genres. A genre (picked by title, since Plex genre keys belong
 * to one library) narrows every row.
 */

import { getFlixorCore } from './index';
import type { PlexMediaItem } from '@flixor/core';
import { convertPlexItemsToHero, type HeroItem } from './HomeData';

export type LibraryHomeType = 'movie' | 'show';

export type LibraryRef = { key: string; title: string; type: string };

export type LibraryRowItem = {
  id: string;
  title: string;
  image?: string;
  mediaType: 'movie' | 'tv';
  ratingKey: string;
};

export type LibraryHomeRow = {
  id: string;
  title: string;
  items: LibraryRowItem[];
  /** Set on genre rows: opening the row's title narrows the page to this genre. */
  genre?: string;
};

export type LibraryHomeData = {
  library: LibraryRef;
  libraries: LibraryRef[];
  genres: Array<{ key: string; title: string }>;
  /** The genre's key in this library, when the page is narrowed to a genre. */
  genreKey?: string;
  hero: HeroItem[];
  rows: LibraryHomeRow[];
};

const ROW_SIZE = 20;

// Genres that make good rows, in the order Netflix-style pages tend to show them
const GENRE_ROW_ORDER = [
  'Action', 'Comedy', 'Drama', 'Thriller', 'Science Fiction', 'Sci-Fi & Fantasy', 'Crime', 'Animation',
  'Adventure', 'Horror', 'Mystery', 'Romance', 'Fantasy', 'Family', 'Documentary', 'Reality',
  'Action & Adventure', 'War', 'History', 'Music', 'Western',
];
const GENRE_ROWS = 6;

export async function fetchTypeLibraries(type: LibraryHomeType): Promise<LibraryRef[]> {
  const core = getFlixorCore();
  const libraries = await core.plexServer.getLibraries();
  return libraries
    .filter((l: any) => l.type === type)
    .map((l: any) => ({ key: String(l.key), title: l.title, type: l.type }));
}

function toRowItems(items: PlexMediaItem[], type: LibraryHomeType): LibraryRowItem[] {
  const core = getFlixorCore();
  return items
    .filter((m) => m.thumb)
    .map((m) => ({
      id: `plex:${m.ratingKey}`,
      ratingKey: String(m.ratingKey),
      title: m.title || 'Untitled',
      image: core.plexServer.getImageUrl(m.thumb!, 300),
      mediaType: type === 'movie' ? ('movie' as const) : ('tv' as const),
    }));
}

async function query(
  libraryKey: string,
  type: LibraryHomeType,
  sort: string,
  genreKey?: string,
  filter?: Record<string, string>,
  size: number = ROW_SIZE
): Promise<PlexMediaItem[]> {
  const core = getFlixorCore();
  try {
    return await core.plexServer.getLibraryItems(libraryKey, {
      type: type === 'movie' ? 1 : 2,
      sort,
      limit: size,
      filter: { ...(genreKey ? { genre: genreKey } : {}), ...(filter ?? {}) },
    });
  } catch (e) {
    console.log('[LibraryHomeData] query failed', sort, e);
    return [];
  }
}

function shuffle<T>(list: T[]): T[] {
  const out = list.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

export async function fetchLibraryHome(
  type: LibraryHomeType,
  options: { libraryKey?: string; genre?: string } = {}
): Promise<LibraryHomeData | null> {
  const core = getFlixorCore();
  const libraries = await fetchTypeLibraries(type);
  const library = libraries.find((l) => l.key === options.libraryKey) ?? libraries[0];
  if (!library) return null;

  const genres = await core.plexServer.getGenres(library.key);
  const genreKey = options.genre
    ? genres.find((g) => g.title.toLowerCase() === options.genre!.toLowerCase())?.key
    : undefined;
  // A genre this library doesn't have leaves nothing to show
  if (options.genre && !genreKey) {
    return { library, libraries, genres, hero: [], rows: [] };
  }

  const noun = type === 'movie' ? 'Movies' : 'Shows';
  const label = options.genre ?? '';
  const [recent, popular, topRated, released] = await Promise.all([
    query(library.key, type, 'addedAt:desc', genreKey),
    query(library.key, type, 'viewCount:desc', genreKey),
    query(library.key, type, 'audienceRating:desc', genreKey),
    query(library.key, type, 'originallyAvailableAt:desc', genreKey),
  ]);

  // Billboard: a few titles from what's new and what's rated highest, in a fresh order
  const seen = new Set<string>();
  const heroSource = shuffle([...recent.slice(0, 10), ...topRated.slice(0, 10)]).filter((m) => {
    const k = String(m.ratingKey);
    if (seen.has(k) || !m.thumb) return false;
    seen.add(k);
    return true;
  });
  const hero = await convertPlexItemsToHero(heroSource, 6);

  const rows: LibraryHomeRow[] = [
    { id: 'recent', title: genreKey ? `New in ${label}` : `New in ${library.title}`, items: toRowItems(recent, type) },
    { id: 'popular', title: genreKey ? `Most Watched ${label}` : `Most Watched ${noun}`, items: toRowItems(popular, type) },
    { id: 'top', title: genreKey ? `Top Rated ${label}` : `Top Rated ${noun}`, items: toRowItems(topRated, type) },
    { id: 'released', title: 'Recently Released', items: toRowItems(released, type) },
  ];

  if (!genreKey) {
    // A row for each of the main genres the library has
    const byTitle = new Map(genres.map((g) => [g.title, g]));
    const picked = GENRE_ROW_ORDER.map((t) => byTitle.get(t)).filter(Boolean) as Array<{ key: string; title: string }>;
    for (const g of genres) {
      if (picked.length >= GENRE_ROWS) break;
      if (!picked.includes(g)) picked.push(g);
    }
    const genreRows = await Promise.all(
      picked.slice(0, GENRE_ROWS).map(async (g) => ({
        id: `genre-${g.key}`,
        title: g.title,
        genre: g.title,
        items: toRowItems(await query(library.key, type, 'audienceRating:desc', g.key), type),
      }))
    );
    // Genre rows go after the first two rows, Netflix-style
    rows.splice(2, 0, ...genreRows);
  } else if (type === 'movie') {
    const unwatched = await query(library.key, type, 'audienceRating:desc', genreKey, { unwatched: '1' });
    rows.push({ id: 'unwatched', title: `${label} You Haven't Seen`, items: toRowItems(unwatched, type) });
  }

  return {
    library,
    libraries,
    genres,
    genreKey,
    hero,
    // The newest row always shows (a small library still gets something); others need a few titles
    rows: rows.filter((r) => r.items.length >= (r.id === 'recent' ? 1 : 3)),
  };
}
