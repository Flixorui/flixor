/** Addon catalogs: browsable rows, paging, search, and IMDb to TMDB mapping. */
import { getSettings } from '@/state/settings';
import { addonSupportsResource, listInstalledAddons, type InstalledAddon } from './addons';
import { addonResourceUrl } from './streams';
import { fetchAddonJson, lookupTmdbId } from './transport';
import type { StremioCatalog, StremioCatalogItem, StremioRequestOptions } from './types';

const CATALOG_TIMEOUT_MS = 20_000;
const CATALOG_PAGE_CACHE_MS = 5 * 60 * 1000;
const SEARCH_LIMIT = 20;
/** Several rows map at once, so an unbounded lookup would flood TMDB. */
const TMDB_LOOKUP_CONCURRENCY = 10;
const MAX_CACHED_PAGES = 100;

const pageCache = new Map<string, { at: number; items: StremioCatalogItem[] }>();
const tmdbIds = new Map<string, number | null>();

export async function mapWithConcurrency<T, R>(
  items: T[],
  limit: number,
  run: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next;
      next += 1;
      results[index] = await run(items[index], index);
    }
  });
  await Promise.all(workers);
  return results;
}

function parseItem(raw: any): StremioCatalogItem | null {
  if (typeof raw?.id !== 'string' || typeof raw?.type !== 'string' || typeof raw?.name !== 'string') return null;
  const year = Number(/\d{4}/.exec(String(raw.releaseInfo ?? raw.year ?? ''))?.[0]);
  const tmdbFromId = /^tmdb:(\d+)$/.exec(raw.id)?.[1];
  return {
    id: raw.id,
    type: raw.type,
    name: raw.name,
    poster: typeof raw.poster === 'string' ? raw.poster : undefined,
    background: typeof raw.background === 'string' ? raw.background : undefined,
    year: Number.isFinite(year) ? year : undefined,
    imdbId: raw.id.startsWith('tt') ? raw.id : typeof raw.imdb_id === 'string' ? raw.imdb_id : undefined,
    tmdbId: tmdbFromId ? Number(tmdbFromId) : undefined,
    description: typeof raw.description === 'string' ? raw.description : undefined,
    imdbRating: raw.imdbRating != null ? String(raw.imdbRating) : undefined,
  };
}

/** Adds TMDB ids so items can open the regular Details page. Lookup failures leave them out. */
async function attachTmdbIds(
  items: StremioCatalogItem[],
  signal: AbortSignal | undefined,
): Promise<StremioCatalogItem[]> {
  return mapWithConcurrency(items, TMDB_LOOKUP_CONCURRENCY, async (item) => {
    if (item.tmdbId || !item.imdbId) return item;
    const key = `${item.type}:${item.imdbId}`;
    if (!tmdbIds.has(key)) {
      try {
        tmdbIds.set(key, await lookupTmdbId(item.imdbId, item.type, signal));
      } catch (err) {
        if ((err as Error)?.name === 'AbortError') throw err;
        return item; // Not cached: this may just be a passing network error.
      }
    }
    return { ...item, tmdbId: tmdbIds.get(key) ?? undefined };
  });
}

async function fetchPage(
  addon: InstalledAddon,
  catalog: StremioCatalog,
  extras: Record<string, string>,
  signal: AbortSignal | undefined,
): Promise<StremioCatalogItem[]> {
  const extraPath = Object.keys(extras)
    .sort()
    .map((key) => `/${encodeURIComponent(key)}=${encodeURIComponent(extras[key])}`)
    .join('');
  const path = `/catalog/${encodeURIComponent(catalog.type)}/${encodeURIComponent(catalog.id)}${extraPath}.json`;
  const data = await fetchAddonJson<{ metas?: unknown }>(addonResourceUrl(addon, path), {
    signal,
    timeoutMs: CATALOG_TIMEOUT_MS,
  });
  return Array.isArray(data?.metas) ? data.metas.flatMap((raw) => parseItem(raw) ?? []) : [];
}

function catalogHasRequired(catalog: StremioCatalog, allowed: string[]): boolean {
  return (catalog.requiredExtras ?? []).every((extra) => allowed.includes(extra));
}

/** Catalogs that can be listed without user input, in the user's addon order. */
export async function getCatalogs(): Promise<StremioCatalog[]> {
  return listInstalledAddons().flatMap((addon) =>
    addon.catalogs.filter(
      (catalog) => catalogHasRequired(catalog, ['skip']) && addonSupportsResource(addon, 'catalog', catalog.type),
    ),
  );
}

export function catalogDisplayName(catalog: StremioCatalog): string {
  return catalog.type === 'series' ? `${catalog.name} (TV)` : catalog.name;
}

/** One page of a catalog. Pass `skip` to page; addons report no totals, so stop at an empty page. */
export async function getCatalogItems(
  catalog: StremioCatalog,
  options: StremioRequestOptions & { skip?: number } = {},
): Promise<StremioCatalogItem[]> {
  const addon = listInstalledAddons().find((other) => other.installationId === catalog.installationId);
  if (!addon) return [];

  const skip = options.skip ?? 0;
  const cacheKey = `${catalog.installationId}|${catalog.type}|${catalog.id}|${skip}`;
  const cached = pageCache.get(cacheKey);
  if (cached && Date.now() - cached.at < CATALOG_PAGE_CACHE_MS) return cached.items;

  const items = await attachTmdbIds(
    await fetchPage(addon, catalog, skip > 0 ? { skip: String(skip) } : {}, options.signal),
    options.signal,
  );
  if (pageCache.size >= MAX_CACHED_PAGES) pageCache.delete(pageCache.keys().next().value as string);
  pageCache.set(cacheKey, { at: Date.now(), items });
  return items;
}

/** Searches every catalog that supports it, de-duplicated. Empty when the setting is off. */
export async function searchCatalogs(
  query: string,
  options: StremioRequestOptions = {},
): Promise<StremioCatalogItem[]> {
  const trimmed = query.trim();
  if (!trimmed || !getSettings().stremioCatalogSearchEnabled) return [];

  const searchable = listInstalledAddons().flatMap((addon) =>
    addon.catalogs
      .filter(
        (catalog) =>
          catalog.supportsSearch &&
          catalogHasRequired(catalog, ['search', 'skip']) &&
          addonSupportsResource(addon, 'catalog', catalog.type),
      )
      .map((catalog) => ({ addon, catalog })),
  );

  const pages = await Promise.all(
    searchable.map(async ({ addon, catalog }) => {
      try {
        return (await fetchPage(addon, catalog, { search: trimmed }, options.signal)).slice(0, SEARCH_LIMIT);
      } catch (err) {
        if ((err as Error)?.name === 'AbortError') throw err;
        return []; // One failing addon must not empty the whole search.
      }
    }),
  );

  const seen = new Set<string>();
  const unique = pages.flat().filter((item) => !seen.has(item.id) && Boolean(seen.add(item.id)));
  return attachTmdbIds(unique, options.signal);
}
