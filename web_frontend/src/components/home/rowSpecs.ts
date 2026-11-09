/** What each Home row is and how to load it. Rows load on demand, independently. */
import { plexBackendDir, plexBackendLibrarySecondary, plexBackendRecentlyAdded } from '@/services/plex_backend';
import { plexTvWatchlist } from '@/services/plextv';
import { tmdbTrending, tmdbImage } from '@/services/tmdb';
import {
  ensureValidToken,
  getTraktTokens,
  isTraktAuthenticated,
  traktGetHistory,
  traktGetRecommendations,
  traktGetWatchlist,
  traktPopular,
  traktTrending,
} from '@/services/trakt';
import {
  collectionChildrenPath,
  getCollectionItems,
  plexImage,
  plexItemToCard,
  type PlexCollection,
  type PlexLibrary,
} from '@/services/plexCollections';
import { fetchSourcePage } from '@/components/collections/resolveSources';
import type { UserCollection } from '@/state/collections';
import { WATCHLIST_ROW_ID, type HomeRowDescriptor } from '@/state/homeRows';
import type { CardItem } from '@/components/cards/cardTypes';
import { createLimiter } from '@/components/cards/limiter';

export interface HomeRowResult {
  items: CardItem[];
  browseKey?: string;
}

export interface HomeRowSpec extends HomeRowDescriptor {
  browseKey?: string;
  /** A page to open instead of the Browse popup. */
  browseHref?: string;
  /** Already-loaded items, for rows whose data arrives from elsewhere. */
  items?: CardItem[];
  load?: () => Promise<HomeRowResult>;
  /** Shown as the error card's source label. */
  source: string;
  /** Skeleton only: the real rows are still being worked out. */
  placeholder?: boolean;
  /** Reloads the row's source instead of re-running `load`. */
  retry?: () => void;
  /** Set when a loaded result depends on more than the row id. */
  cacheKey?: string;
}

const RECENT_RAW_LIMIT = 30;
const RECENT_LIMIT = 20;
const ROW_CACHE_MS = 5 * 60 * 1000;

/** Rows load as they near the viewport, a few at a time. */
const limit = createLimiter(4);
const rowCache = new Map<string, { at: number; result: Promise<HomeRowResult> }>();

/** Loads a row, reusing a recent result so returning to Home is instant. */
export function loadHomeRow(spec: HomeRowSpec, force = false): Promise<HomeRowResult> {
  if (spec.items) return Promise.resolve({ items: spec.items, browseKey: spec.browseKey });
  if (!spec.load) return Promise.resolve({ items: [] });
  const key = spec.cacheKey ?? spec.id;
  const cached = rowCache.get(key);
  if (cached && !force && Date.now() - cached.at < ROW_CACHE_MS) return cached.result;
  const result = limit(spec.load);
  rowCache.set(key, { at: Date.now(), result });
  result.catch(() => {
    if (rowCache.get(key)?.result === result) rowCache.delete(key);
  });
  return result;
}

function tmdbResultToCard(result: any, media: 'movie' | 'tv'): CardItem {
  return {
    id: `tmdb:${media}:${result.id}`,
    title: result.name || result.title,
    image: tmdbImage(result.poster_path, 'w500') || tmdbImage(result.backdrop_path, 'w780'),
    backdrop: tmdbImage(result.backdrop_path, 'w780'),
    mediaType: media === 'movie' ? 'movie' : 'show',
    year: String(result.first_air_date || result.release_date || '').slice(0, 4) || undefined,
    rating: result.vote_average || undefined,
    overview: result.overview || undefined,
  };
}

async function trendingTv() {
  const res: any = await tmdbTrending('', 'tv', 'week');
  return (res?.results || []) as any[];
}

export function discoverySpecs(): HomeRowSpec[] {
  return [
    {
      id: 'tmdb-popular',
      defaultTitle: 'Popular on Plex',
      kind: 'discovery',
      group: 'extras',
      source: 'TMDB',
      browseKey: 'tmdb:trending:tv:week',
      load: async () => ({ items: (await trendingTv()).slice(0, 8).map((r) => tmdbResultToCard(r, 'tv')) }),
    },
    {
      id: 'tmdb-trending',
      defaultTitle: 'Trending Now',
      kind: 'discovery',
      group: 'extras',
      source: 'TMDB',
      browseKey: 'tmdb:trending:tv:week',
      load: async () => ({ items: (await trendingTv()).slice(8, 16).map((r) => tmdbResultToCard(r, 'tv')) }),
    },
  ];
}

function tmdbIdFromGuid(guid: string): string | undefined {
  if (!guid.includes('tmdb://') && !guid.includes('themoviedb://')) return undefined;
  return guid.split('://')[1]?.match(/\d+/)?.[0];
}

function traktItemToCard(entry: any): CardItem | null {
  const isMovie = !!entry.movie;
  const media = entry.movie || entry.show || entry;
  const tmdbId = media?.ids?.tmdb;
  if (!tmdbId) return null;
  return {
    id: `tmdb:${isMovie ? 'movie' : 'tv'}:${tmdbId}`,
    title: media.title || '',
    mediaType: isMovie ? 'movie' : 'show',
    year: media.year,
    rating: media.rating || undefined,
    overview: media.overview || undefined,
  };
}

function traktCards(entries: any[]) {
  return entries.map(traktItemToCard).filter((card): card is CardItem => card !== null).slice(0, 20);
}

export function watchlistSpec(): HomeRowSpec {
  return {
    id: WATCHLIST_ROW_ID,
    cacheKey: `${WATCHLIST_ROW_ID}:${isTraktAuthenticated()}`,
    defaultTitle: 'Watchlist',
    kind: 'watchlist',
    group: 'extras',
    source: 'Plex',
    browseKey: '/plextv/watchlist',
    load: async () => {
      const [plexResult, traktResult] = await Promise.allSettled([
        plexTvWatchlist(),
        isTraktAuthenticated() && getTraktTokens()
          ? Promise.all([
              traktGetWatchlist(getTraktTokens()!.access_token, 'movies'),
              traktGetWatchlist(getTraktTokens()!.access_token, 'shows'),
            ]).then(([movies, shows]) => [...movies, ...shows])
          : Promise.resolve([]),
      ]);
      if (plexResult.status === 'rejected' && traktResult.status === 'rejected') throw plexResult.reason;

      const plexItems: any[] = plexResult.status === 'fulfilled' ? plexResult.value?.MediaContainer?.Metadata || [] : [];
      const cards: CardItem[] = [];
      for (const m of plexItems) {
        const tmdbId = tmdbIdFromGuid(String(m.tmdbGuid || m.guid || ''));
        if (!tmdbId) continue;
        const media = m.type === 'movie' ? 'movie' : 'tv';
        const art = m.Image?.find((img: any) => img.type === 'coverArt' || img.type === 'background')?.url;
        cards.push({
          id: `tmdb:${media}:${tmdbId}`,
          title: m.title || m.grandparentTitle || 'Title',
          image: art || m.thumb || undefined,
          backdrop: art || m.art || undefined,
          mediaType: media === 'movie' ? 'movie' : 'show',
          year: m.year,
        });
      }
      if (traktResult.status === 'fulfilled') cards.push(...traktCards(traktResult.value as any[]));
      const seen = new Set<string>();
      return { items: cards.filter((c) => !seen.has(c.id) && !!seen.add(c.id)).slice(0, 20) };
    },
  };
}

const GENRE_ROWS: Array<{ label: string; type: 'movie' | 'show'; genre: string }> = [
  { label: 'TV Shows - Children', type: 'show', genre: 'Children' },
  { label: 'Movie - Music', type: 'movie', genre: 'Music' },
  { label: 'Movies - Documentary', type: 'movie', genre: 'Documentary' },
  { label: 'Movies - History', type: 'movie', genre: 'History' },
  { label: 'TV Shows - Reality', type: 'show', genre: 'Reality' },
  { label: 'Movies - Drama', type: 'movie', genre: 'Drama' },
  { label: 'TV Shows - Suspense', type: 'show', genre: 'Suspense' },
  { label: 'Movies - Animation', type: 'movie', genre: 'Animation' },
];

export function genreSpecs(libraries: PlexLibrary[]): HomeRowSpec[] {
  return GENRE_ROWS.flatMap((row) => {
    const library = libraries.find((candidate) => candidate.type === row.type);
    if (!library) return [];
    const spec: HomeRowSpec = {
      id: `genre-${row.genre.toLowerCase()}-${row.type}`,
      defaultTitle: row.label,
      kind: 'genre',
      group: 'extras',
      source: 'Plex',
      load: async () => {
        const genres: any = await plexBackendLibrarySecondary(library.key, 'genre');
        const match = (genres?.MediaContainer?.Directory || []).find(
          (g: any) => String(g.title).toLowerCase() === row.genre.toLowerCase(),
        );
        if (!match) return { items: [] };
        const path = `/library/sections/${library.key}/genre/${match.key}`;
        const data: any = await plexBackendDir(path);
        return { items: (data?.MediaContainer?.Metadata || []).slice(0, 12).map(plexItemToCard), browseKey: path };
      },
    };
    return [spec];
  });
}

/** Replaces episodes with one card per series, in order of first appearance. */
export function groupEpisodesBySeries(items: any[]): CardItem[] {
  const counts = new Map<string, number>();
  for (const item of items) {
    if (item.type === 'episode' && item.grandparentRatingKey) {
      const key = String(item.grandparentRatingKey);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }

  const seen = new Set<string>();
  const cards: CardItem[] = [];
  for (const item of items) {
    if (item.type !== 'episode' || !item.grandparentRatingKey) {
      cards.push(plexItemToCard(item));
      continue;
    }
    const key = String(item.grandparentRatingKey);
    if (seen.has(key)) continue;
    seen.add(key);
    const count = counts.get(key) ?? 1;
    cards.push({
      id: `plex:${key}`,
      title: item.grandparentTitle || item.title,
      subtitle: count === 1 ? '1 new episode' : `${count} new episodes`,
      image: plexImage(item.grandparentThumb || item.thumb),
      backdrop: plexImage(item.grandparentArt || item.art),
      mediaType: 'show',
      newEpisodeCount: count,
    });
  }
  return cards;
}

export function recentlyAddedSpecs(libraries: PlexLibrary[], groupEpisodes: boolean): HomeRowSpec[] {
  return libraries.map((library) => ({
    id: `recently-added-${library.key}`,
    cacheKey: `recently-added-${library.key}:${groupEpisodes}`,
    defaultTitle: `Recently Added in ${library.title}`,
    kind: 'recentlyAdded' as const,
    group: 'recentlyAdded' as const,
    source: 'Plex',
    browseKey: `/library/sections/${library.key}/recentlyAdded`,
    load: async () => {
      const res: any = await plexBackendRecentlyAdded(library.key);
      const raw: any[] = res?.MediaContainer?.Metadata || [];
      const items = groupEpisodes
        ? groupEpisodesBySeries(raw.slice(0, RECENT_RAW_LIMIT)).slice(0, RECENT_LIMIT)
        : raw.slice(0, RECENT_LIMIT).map(plexItemToCard);
      return { items };
    },
  }));
}

export function collectionSpecs(collections: PlexCollection[]): HomeRowSpec[] {
  return collections.map((collection) => ({
    id: `collection-${collection.ratingKey}`,
    defaultTitle: collection.title,
    kind: 'collection' as const,
    group: 'collections' as const,
    source: 'Plex',
    browseKey: collectionChildrenPath(collection.ratingKey),
    load: async () => ({ items: await getCollectionItems(collection.ratingKey, 15) }),
  }));
}

export const USER_COLLECTION_ROW_PREFIX = 'user-collection-';
const USER_COLLECTION_ROW_LIMIT = 20;

async function userCollectionCards(collection: UserCollection): Promise<CardItem[]> {
  const pages = await Promise.allSettled(collection.sources.map((source) => fetchSourcePage(source)));
  const loaded = pages.flatMap((page) => (page.status === 'fulfilled' ? [page.value] : []));
  if (loaded.length === 0) {
    const failed = pages.find((page) => page.status === 'rejected');
    if (failed?.status === 'rejected') throw failed.reason;
    return [];
  }
  const seen = new Set<string>();
  const cards: CardItem[] = [];
  for (const item of loaded.flatMap((page) => page.items)) {
    if (seen.has(item.id)) continue;
    seen.add(item.id);
    cards.push({
      id: item.id,
      title: item.title,
      image: item.image || item.backdrop,
      backdrop: item.backdrop,
      year: item.subtitle,
      mediaType: item.id.startsWith('tmdb:tv:') ? 'show' : 'movie',
    });
  }
  return cards.slice(0, USER_COLLECTION_ROW_LIMIT);
}

/** A row for each user-built collection with "Show on Home" turned on. */
export function userCollectionSpecs(collections: UserCollection[]): HomeRowSpec[] {
  return collections
    .filter((collection) => collection.showOnHome && collection.sources.length > 0)
    .map((collection) => ({
      id: `${USER_COLLECTION_ROW_PREFIX}${collection.id}`,
      cacheKey: `${USER_COLLECTION_ROW_PREFIX}${collection.id}:${collection.sources.map((source) => source.sourceId).join(',')}`,
      defaultTitle: collection.name,
      kind: 'collection' as const,
      group: 'collections' as const,
      detail: 'Your collection',
      source: 'Collection',
      browseHref: `/collections/${encodeURIComponent(collection.id)}`,
      load: async () => ({ items: await userCollectionCards(collection) }),
    }));
}

export function traktSpecs(): HomeRowSpec[] {
  const spec = (id: string, defaultTitle: string, browseKey: string, fetch: () => Promise<any[]>): HomeRowSpec => ({
    id,
    cacheKey: `${id}:${isTraktAuthenticated()}`,
    defaultTitle,
    kind: 'trakt',
    group: 'extras',
    source: 'Trakt',
    browseKey,
    load: async () => ({ items: traktCards(await fetch()) }),
  });

  const withToken = async <T,>(run: (token: string) => Promise<T>): Promise<T> => {
    const token = await ensureValidToken();
    if (!token) throw new Error('Not signed in to Trakt');
    return run(token);
  };

  const rows = [
    spec('trakt-trending-movies', 'Trending Movies on Trakt', 'trakt:trending:movies', () => traktTrending('movies', 20)),
    spec('trakt-trending-shows', 'Trending TV Shows on Trakt', 'trakt:trending:shows', () => traktTrending('shows', 20)),
  ];
  if (isTraktAuthenticated()) {
    rows.push(
      spec('trakt-watchlist', 'Your Trakt Watchlist', 'trakt:watchlist:movies', () =>
        withToken(async (token) => {
          const [movies, shows] = await Promise.all([traktGetWatchlist(token, 'movies'), traktGetWatchlist(token, 'shows')]);
          return [...movies, ...shows];
        }),
      ),
      spec('trakt-history', 'Recently Watched', 'trakt:history:shows', () => withToken((token) => traktGetHistory(token, 'shows', 20))),
      spec('trakt-recs', 'Recommended for You', 'trakt:recommendations:movies', () =>
        withToken((token) => traktGetRecommendations(token, 'movies', 20)),
      ),
    );
  }
  rows.push(spec('trakt-popular-shows', 'Popular TV Shows on Trakt', 'trakt:popular:shows', () => traktPopular('shows', 20)));
  return rows;
}
