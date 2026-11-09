import type { Ionicons } from '@expo/vector-icons';
import type { BrowseItem } from '@flixor/core';
import {
  HOME_CONTINUE_WATCHING_ROW_ID,
  HOME_PLEX_WATCHLIST_ROW_ID,
  HOME_TRAKT_WATCHLIST_ROW_ID,
  homeRowTitle,
  orderHomeRows,
} from '../../core/HomeRowsStore';
import type { CollectionRowData, RecentlyAddedSection, RowItem } from '../../core/HomeData';
import type { AppSettings, HomeRowDescriptor, HomeRowGroup, HomeRowKind } from '../../core/SettingsData';
import type { UserCollection } from '../../core/UserCollectionsStore';
import { fetchCatalogPage, type InstalledCatalog } from '../../stremio/StremioCatalogService';
import { mapCatalogPreviews } from '../../stremio/StremioCatalogMapper';
import type { RowBadge } from '../Row';

const CATALOG_ROW_SIZE = 20;

export const HOME_GENRE_ROWS = [
  { key: 'TV Shows - Children', type: 'show', label: 'Children', mediaType: 'tv' },
  { key: 'Movie - Music', type: 'movie', label: 'Music', mediaType: 'movie' },
  { key: 'Movies - Documentary', type: 'movie', label: 'Documentary', mediaType: 'movie' },
  { key: 'Movies - History', type: 'movie', label: 'History', mediaType: 'movie' },
  { key: 'TV Shows - Reality', type: 'show', label: 'Reality', mediaType: 'tv' },
  { key: 'Movies - Drama', type: 'movie', label: 'Drama', mediaType: 'movie' },
  { key: 'TV Shows - Suspense', type: 'show', label: 'Suspense', mediaType: 'tv' },
  { key: 'Movies - Animation', type: 'movie', label: 'Animation', mediaType: 'movie' },
] as const;

interface RowModelBase {
  id: string;
  defaultTitle: string;
  kind: HomeRowKind;
  group: HomeRowGroup;
  detail?: string;
}

export interface HomeContinueRowModel extends RowModelBase {
  type: 'continueWatching';
}

export interface HomeItemsRowModel extends RowModelBase {
  type: 'items';
  items: RowItem[];
  titleIcon?: keyof typeof Ionicons.glyphMap;
  badge?: RowBadge;
  /** Rendered right away instead of through LazyRow. */
  eager?: boolean;
  /** Browse context. Some Plex contexts are only handled by the Browse screen's initial items. */
  browseContext: any;
}

export interface HomeCatalogRowModel extends RowModelBase {
  type: 'catalog';
  catalog: InstalledCatalog;
}

export interface HomeUserCollectionRowModel extends RowModelBase {
  type: 'userCollection';
  collection: UserCollection;
}

export type HomeRowModel =
  | HomeContinueRowModel
  | HomeItemsRowModel
  | HomeCatalogRowModel
  | HomeUserCollectionRowModel;

export interface HomeDisplayRow {
  model: HomeRowModel;
  title: string;
  caption?: string;
}

export interface HomeRowInputs {
  showCollectionRows: boolean;
  showRecentlyAddedRows: boolean;
  showPlexPopularRow: boolean;
  showTrendingRows: boolean;
  showPlexGenreRows: boolean;
  showTraktRows: boolean;
  collectionRows: CollectionRowData[];
  recentlyAddedSections: RecentlyAddedSection[];
  userCollections: UserCollection[];
  catalogs: InstalledCatalog[];
  popularOnPlex: RowItem[];
  trendingNow: RowItem[];
  trendingMovies: RowItem[];
  trendingAll: RowItem[];
  watchlist: RowItem[];
  genres: Record<string, RowItem[]>;
  recent: RowItem[];
  traktTrendMovies: RowItem[];
  traktTrendShows: RowItem[];
  traktWatchlist: RowItem[];
  traktHistory: RowItem[];
  traktRecommendations: RowItem[];
  traktPopularShows: RowItem[];
}

/** Fetches a catalog's first page for a Home row or the hero. Throws if the addon fails. */
export async function fetchCatalogRowItems(catalog: InstalledCatalog): Promise<RowItem[]> {
  return mapCatalogPreviews(await fetchCatalogPage(catalog, 0, CATALOG_ROW_SIZE));
}

function slug(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

const TRAKT_BADGE: RowBadge = { text: 'Trakt' };

/** Every row with content, in default order. Hidden rows are still included here. */
export function buildHomeRowModels(input: HomeRowInputs): HomeRowModel[] {
  const rows: HomeRowModel[] = [
    {
      type: 'continueWatching',
      id: HOME_CONTINUE_WATCHING_ROW_ID,
      defaultTitle: 'Continue Watching',
      kind: 'continueWatching',
      group: 'continueWatching',
    },
  ];

  const add = (
    id: string,
    defaultTitle: string,
    kind: HomeRowKind,
    group: HomeRowGroup,
    items: RowItem[],
    browseContext: any,
    extra?: Partial<HomeItemsRowModel>
  ) => {
    if (items.length > 0) rows.push({ type: 'items', id, defaultTitle, kind, group, items, browseContext, ...extra });
  };
  const trakt = (id: string, title: string, items: RowItem[], kind: string, mediaType: 'movie' | 'tv') =>
    add(id, title, id === HOME_TRAKT_WATCHLIST_ROW_ID ? 'watchlist' : 'trakt', 'extras', items, { type: 'trakt', kind, mediaType, title }, { badge: TRAKT_BADGE });
  const tmdb = (id: string, title: string, items: RowItem[], mediaType: 'movie' | 'tv', extra?: Partial<HomeItemsRowModel>) =>
    add(id, title, 'discovery', 'extras', items, { type: 'tmdb', kind: 'trending', mediaType, title }, extra);

  if (input.showCollectionRows) {
    for (const collection of input.collectionRows) {
      add(`collection-${collection.ratingKey}`, collection.title, 'collection', 'collections', collection.items,
        { type: 'plexCollection', collectionKey: collection.ratingKey }, { titleIcon: 'sparkles' });
    }
  }

  if (input.showRecentlyAddedRows) {
    for (const section of input.recentlyAddedSections) {
      add(section.id, section.title, 'recentlyAdded', 'recentlyAdded', section.items,
        { type: 'plexDirectory', path: `/library/sections/${section.libraryKey}/recentlyAdded`, title: section.title },
        { titleIcon: 'time-outline' });
    }
  }

  for (const collection of input.userCollections) {
    rows.push({
      type: 'userCollection',
      id: `user-collection-${collection.id}`,
      defaultTitle: collection.name,
      kind: 'userCollection',
      group: 'userCollections',
      collection,
    });
  }

  // Addon catalogs lead the extras: they are the user's own configured sources.
  for (const catalog of input.catalogs) {
    rows.push({
      type: 'catalog',
      id: catalog.rowId,
      defaultTitle: catalog.title,
      kind: 'stremioCatalog',
      group: 'extras',
      detail: catalog.addonName,
      catalog,
    });
  }

  if (input.showPlexPopularRow) tmdb('popular-on-plex', 'Popular on Plex', input.popularOnPlex, 'tv', { eager: true });
  if (input.showTrendingRows) {
    tmdb('trending-now', 'Trending Now', input.trendingNow, 'tv');
    tmdb('trending-movies', 'Trending Movies', input.trendingMovies, 'movie');
    tmdb('trending-week', 'Trending This Week', input.trendingAll, 'movie');
  }
  add(HOME_PLEX_WATCHLIST_ROW_ID, 'Watchlist', 'watchlist', 'extras', input.watchlist, { type: 'plexWatchlist' });

  if (input.showPlexGenreRows) {
    for (const genre of HOME_GENRE_ROWS) {
      add(`genre-${slug(genre.key)}`, genre.key, 'genre', 'extras', input.genres[genre.key] || [],
        { type: 'plexGenre', genre: genre.label, mediaType: genre.mediaType });
    }
  }

  add('plex-recent', 'Recently Added', 'recentlyAdded', 'extras', input.recent, { type: 'plexRecent' });

  if (input.showTraktRows) {
    trakt('trakt-trending-movies', 'Trending Movies', input.traktTrendMovies, 'trending', 'movie');
    trakt('trakt-trending-shows', 'Trending Shows', input.traktTrendShows, 'trending', 'tv');
    trakt(HOME_TRAKT_WATCHLIST_ROW_ID, 'Watchlist', input.traktWatchlist, 'watchlist', 'movie');
    trakt('trakt-history', 'Recently Watched', input.traktHistory, 'history', 'movie');
    trakt('trakt-recommendations', 'Recommended for You', input.traktRecommendations, 'recommendations', 'movie');
    trakt('trakt-popular-shows', 'Popular Shows', input.traktPopularShows, 'trending', 'tv');
  }

  return rows;
}

export function toRowDescriptors(models: HomeRowModel[]): HomeRowDescriptor[] {
  return models.map(({ id, defaultTitle, kind, group, detail }) => ({
    id,
    defaultTitle,
    kind,
    group,
    ...(detail ? { detail } : null),
  }));
}

function normalizedTitle(title: string): string {
  return title.trim().toLowerCase();
}

/** Applies the user's hidden rows, titles and order, and the Movies/Shows filter. */
export function arrangeHomeRows(
  models: HomeRowModel[],
  settings: Pick<AppSettings, 'homeRowHidden' | 'homeRowTitles' | 'homeRowOrder'>,
  tab: 'all' | 'movies' | 'shows'
): HomeDisplayRow[] {
  const hidden = new Set(settings.homeRowHidden);
  const visible = models.filter((model) => {
    if (hidden.has(model.id)) return false;
    if (tab === 'shows' && model.id === 'trakt-trending-movies') return false;
    if (tab === 'movies' && model.id === 'trakt-trending-shows') return false;
    return true;
  });

  const rows = orderHomeRows(visible, (model) => model.id, settings.homeRowOrder).map(
    (model): HomeDisplayRow => ({ model, title: homeRowTitle(settings.homeRowTitles, model.id, model.defaultTitle) })
  );

  // Two rows can share a title; addon rows then say which addon they come from.
  const counts = new Map<string, number>();
  rows.forEach((row) => counts.set(normalizedTitle(row.title), (counts.get(normalizedTitle(row.title)) ?? 0) + 1));
  return rows.map((row) =>
    row.model.type === 'catalog' && (counts.get(normalizedTitle(row.title)) ?? 0) > 1
      ? { ...row, caption: row.model.detail }
      : row
  );
}

export function toBrowseItems(items: RowItem[]): BrowseItem[] {
  return items.map((item) => ({ id: item.id, title: item.title, image: item.image, subtitle: item.subtitle }));
}
