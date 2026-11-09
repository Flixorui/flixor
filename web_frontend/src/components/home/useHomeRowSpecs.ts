import { useCallback, useEffect, useMemo, useState } from 'react';
import { getAllCollections, getPlexLibraries, filterEnabledLibraries, type PlexCollection, type PlexLibrary } from '@/services/plexCollections';
import { useStremioCatalogRows, type StremioCatalogRow } from '@/hooks/useStremioCatalogRows';
import { useSettings, type ResolvedSettings } from '@/state/settings';
import { WATCHLIST_ROW_ID } from '@/state/homeRows';
import { stremioItemToCard } from '@/components/cards/cardMedia';
import type { CardItem } from '@/components/cards/cardTypes';
import { encodeStremioBrowseKey } from '@/components/BrowseModal';
import { useCollections } from '@/state/collections';
import {
  USER_COLLECTION_ROW_PREFIX,
  collectionSpecs,
  discoverySpecs,
  genreSpecs,
  recentlyAddedSpecs,
  traktSpecs,
  userCollectionSpecs,
  watchlistSpec,
  type HomeRowSpec,
} from './rowSpecs';

// Addon rows arrive one at a time; finished rows keep their cards so they don't re-render.
const stremioCards = new WeakMap<StremioCatalogRow, CardItem[]>();

function cardsForStremioRow(row: StremioCatalogRow) {
  let cards = stremioCards.get(row);
  if (!cards) {
    cards = row.items.map(stremioItemToCard);
    stremioCards.set(row, cards);
  }
  return cards;
}

/** Plex collection rows shown on Home, the most populated first. */
const MAX_COLLECTION_ROWS = 5;

type PlexState =
  | { status: 'idle' | 'loading' }
  | { status: 'ready'; libraries: PlexLibrary[]; collections: PlexCollection[] }
  | { status: 'error'; message: string };

function isRowEnabled(spec: HomeRowSpec, settings: ResolvedSettings) {
  // Each user collection has its own "Show on Home" switch.
  if (spec.id.startsWith(USER_COLLECTION_ROW_PREFIX)) return true;
  const visible = settings.rowsVisible;
  switch (spec.id) {
    case 'tmdb-popular':
      return settings.showPlexPopularRow !== false && visible?.popular !== false;
    case 'tmdb-trending':
      return settings.showTrendingRows !== false && visible?.trending !== false;
    case WATCHLIST_ROW_ID:
      return settings.showWatchlistRow && visible?.watchlist !== false;
  }
  if (spec.kind === 'trakt') return settings.showTraktRows !== false && visible?.trakt !== false;
  if (spec.kind === 'collection') return settings.showCollectionRows;
  if (spec.kind === 'stremioCatalog') return settings.showStremioCatalogRows;
  return true;
}

/** Every Home row that can exist right now, in default order, ready to load lazily. */
export function useHomeRowSpecs(active: boolean) {
  const settings = useSettings();
  const stremio = useStremioCatalogRows();
  const userCollections = useCollections();
  const [plex, setPlex] = useState<PlexState>({ status: 'idle' });
  const [traktVersion, setTraktVersion] = useState(0);
  const [reloadToken, setReloadToken] = useState(0);
  const connected = !!settings.plexBaseUrl && !!settings.plexToken;
  const reloadPlex = useCallback(() => setReloadToken((token) => token + 1), []);

  useEffect(() => {
    if (!active || !connected) return;
    let alive = true;
    setPlex({ status: 'loading' });
    (async () => {
      try {
        const libraries = await getPlexLibraries();
        const collections = await getAllCollections(libraries);
        if (alive) setPlex({ status: 'ready', libraries, collections });
      } catch (error: any) {
        if (alive) setPlex({ status: 'error', message: error?.message || 'Could not reach Plex' });
      }
    })();
    return () => {
      alive = false;
    };
  }, [active, connected, reloadToken]);

  useEffect(() => {
    const onChange = () => setTraktVersion((version) => version + 1);
    window.addEventListener('trakt-auth-changed', onChange);
    return () => window.removeEventListener('trakt-auth-changed', onChange);
  }, []);

  const enabledKeys = settings.enabledLibraryKeys.join(',');
  const hiddenCollections = settings.hiddenCollectionKeys.join(',');
  const libraryOnly = settings.discoveryDisabled === true;
  const groupEpisodes = settings.groupRecentlyAddedEpisodes;

  const groups = useMemo(() => {
    const plexReady = plex.status === 'ready';
    const libraries = plexReady ? filterEnabledLibraries(plex.libraries, settings.enabledLibraryKeys) : [];
    const enabledSet = new Set(libraries.map((library) => library.key));
    const hidden = new Set(settings.hiddenCollectionKeys);
    const collections = plexReady
      ? plex.collections
          .filter((collection) => enabledSet.has(collection.libraryKey) && !hidden.has(collection.ratingKey))
          .sort((a, b) => b.count - a.count)
          .slice(0, MAX_COLLECTION_ROWS)
      : [];
    const pending = active && connected && (plex.status === 'loading' || plex.status === 'idle');

    const recentlyAdded: HomeRowSpec[] = pending
      ? [placeholder('recent-0', 'recentlyAdded'), placeholder('recent-1', 'recentlyAdded')]
      : plex.status === 'error'
        ? [failure('recently-added', 'Recently Added', 'recentlyAdded', plex.message, reloadPlex)]
        : recentlyAddedSpecs(libraries, groupEpisodes);

    const extras: HomeRowSpec[] = [];
    if (!libraryOnly) extras.push(...discoverySpecs());
    if (connected) extras.push(watchlistSpec());
    if (plexReady) extras.push(...genreSpecs(libraries));
    if (!libraryOnly) extras.push(...traktSpecs());
    if (!libraryOnly) {
      for (const row of stremio.rows) {
        extras.push({
          id: row.id,
          defaultTitle: row.title,
          kind: 'stremioCatalog',
          group: 'extras',
          detail: row.catalog.addonName,
          source: row.catalog.addonName,
          items: cardsForStremioRow(row),
          browseKey: encodeStremioBrowseKey(row.catalog),
          retry: stremio.reload,
        });
      }
      if (stremio.loading && stremio.rows.length === 0 && settings.showStremioCatalogRows) {
        extras.push(placeholder('stremio', 'extras'));
      }
      if (stremio.error && stremio.rows.length === 0 && settings.showStremioCatalogRows) {
        extras.push({
          ...failure('stremio-catalogs', 'Addon Catalogs', 'extras', stremio.error, stremio.reload),
          kind: 'stremioCatalog',
          source: 'Addons',
        });
      }
    }

    return {
      recentlyAdded,
      collections: [...(settings.showCollectionRows ? collectionSpecs(collections) : []), ...userCollectionSpecs(userCollections)],
      extras,
      settled: { recentlyAdded: !pending, collections: !pending, extras: !pending && !stremio.loading },
    };
    // Row lists are rebuilt only when what they are built from changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [plex, active, connected, enabledKeys, hiddenCollections, libraryOnly, groupEpisodes, stremio.rows, stremio.loading, stremio.error, traktVersion, settings.showCollectionRows, settings.showStremioCatalogRows, userCollections]);

  const specs = useMemo(() => [...groups.recentlyAdded, ...groups.collections, ...groups.extras], [groups]);
  const enabledSpecs = useMemo(() => specs.filter((spec) => spec.placeholder || isRowEnabled(spec, settings)), [specs, settings]);

  return { specs, enabledSpecs, groups, connected };
}

function placeholder(id: string, group: HomeRowSpec['group']): HomeRowSpec {
  return { id: `skeleton-${id}`, defaultTitle: '', kind: 'discovery', group, source: '', placeholder: true };
}

function failure(id: string, title: string, group: HomeRowSpec['group'], message: string, retry: () => void): HomeRowSpec {
  return {
    id,
    defaultTitle: title,
    kind: group === 'recentlyAdded' ? 'recentlyAdded' : 'discovery',
    group,
    source: 'Plex',
    retry,
    load: () => Promise.reject(new Error(message)),
  };
}
