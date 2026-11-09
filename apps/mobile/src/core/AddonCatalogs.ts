/**
 * Reads Stremio addon catalogs for search and user collections, and maps the results
 * to TMDB titles so they open in Details.
 * macOS reference: Services/Stremio/StremioService.swift, StremioCatalogMapper.swift
 */

import { getFlixorCore } from './index';
import { stremioService, stremioUtils } from '../stremio/StremioService';
import type { StremioAddonManifest, StremioRequestType } from '../stremio/types';

interface ManifestCatalogExtra {
  name?: string;
  isRequired?: boolean;
}

interface ManifestCatalog {
  type?: string;
  id?: string;
  name?: string;
  extra?: ManifestCatalogExtra[];
  /** Older manifest form. */
  extraRequired?: string[];
  extraSupported?: string[];
}

export interface InstalledCatalog {
  installationId: string;
  addonId: string;
  addonName: string;
  type: string;
  catalogId: string;
  displayName: string;
  supportsSkip: boolean;
  supportsSearch: boolean;
  isBrowsable: boolean;
}

export interface CatalogMeta {
  id: string;
  type: string;
  name: string;
  poster?: string;
  background?: string;
  year?: string;
  imdbId?: string;
  description?: string;
}

export interface MappedCatalogItem {
  id: string;
  title: string;
  type: 'movie' | 'show';
  image?: string;
  backdrop?: string;
  year?: string;
  tmdbId: number;
}

/** How many IMDb lookups run at once. Several sources can map in parallel. */
const LOOKUP_BATCH_SIZE = 10;
const REQUEST_TIMEOUT_MS = 20000;

function catalogExtras(catalog: ManifestCatalog): { supported: string[]; required: string[] } {
  const extras = Array.isArray(catalog.extra) ? catalog.extra : [];
  const supported = extras.map((e) => e?.name).filter((name): name is string => !!name);
  const required = extras
    .filter((e) => e?.isRequired && e?.name)
    .map((e) => e.name as string);
  return {
    supported: [...supported, ...(catalog.extraSupported ?? [])],
    required: [...required, ...(catalog.extraRequired ?? [])],
  };
}

function describeCatalog(addon: StremioAddonManifest, catalog: ManifestCatalog): InstalledCatalog | null {
  if (!catalog?.type || !catalog?.id) return null;
  if (catalog.type !== 'movie' && catalog.type !== 'series') return null;
  if (!stremioUtils.addonSupportsResource(addon, 'catalog', catalog.type as StremioRequestType)) return null;

  const { supported, required } = catalogExtras(catalog);
  const base = catalog.name || catalog.id.charAt(0).toUpperCase() + catalog.id.slice(1);
  return {
    installationId: addon.installationId,
    addonId: addon.id,
    addonName: addon.name,
    type: catalog.type,
    catalogId: catalog.id,
    displayName: catalog.type === 'series' ? `${base} (TV)` : base,
    supportsSkip: supported.includes('skip'),
    supportsSearch: supported.includes('search'),
    // A required extra other than skip needs user input first, so it can't be listed.
    isBrowsable: required.every((name) => name === 'skip'),
  };
}

async function installedCatalogs(): Promise<InstalledCatalog[]> {
  await stremioService.ensureInitialized();
  const addons = await stremioService.getInstalledAddons();
  const result: InstalledCatalog[] = [];
  for (const addon of addons) {
    const catalogs = (addon as StremioAddonManifest & { catalogs?: ManifestCatalog[] }).catalogs;
    if (!Array.isArray(catalogs)) continue;
    for (const catalog of catalogs) {
      const described = describeCatalog(addon, catalog);
      if (described) result.push(described);
    }
  }
  return result;
}

export async function getBrowsableCatalogs(): Promise<InstalledCatalog[]> {
  return (await installedCatalogs()).filter((c) => c.isBrowsable);
}

export async function getSearchableCatalogs(): Promise<InstalledCatalog[]> {
  return (await installedCatalogs()).filter((c) => c.supportsSearch);
}

function buildCatalogUrl(addonUrl: string, type: string, catalogId: string, extras: Record<string, string>): string {
  const [rawBase, queryString] = addonUrl.split('?');
  const base = rawBase.replace(/manifest\.json$/i, '').replace(/\/$/, '');
  let path = `/catalog/${type}/${encodeURIComponent(catalogId)}`;
  for (const key of Object.keys(extras).sort()) {
    path += `/${encodeURIComponent(key)}=${encodeURIComponent(extras[key])}`;
  }
  path += '.json';
  return queryString ? `${base}${path}?${queryString}` : `${base}${path}`;
}

function parseMeta(raw: any): CatalogMeta | null {
  const id = typeof raw?.id === 'string' ? raw.id : typeof raw?.imdb_id === 'string' ? raw.imdb_id : null;
  const name = typeof raw?.name === 'string' ? raw.name : null;
  if (!id || !name) return null;
  const imdbId =
    typeof raw.imdb_id === 'string' ? raw.imdb_id : id.startsWith('tt') ? id.split(':')[0] : undefined;
  const year =
    typeof raw.releaseInfo === 'string'
      ? raw.releaseInfo.slice(0, 4)
      : raw.year != null
        ? String(raw.year).slice(0, 4)
        : undefined;
  return {
    id,
    type: typeof raw.type === 'string' ? raw.type : 'movie',
    name,
    poster: typeof raw.poster === 'string' ? raw.poster : undefined,
    background: typeof raw.background === 'string' ? raw.background : undefined,
    year,
    imdbId,
    description: typeof raw.description === 'string' ? raw.description : undefined,
  };
}

/** Fetches one catalog page. Throws when the addon request fails. */
export async function fetchCatalogPage(
  installationId: string,
  type: string,
  catalogId: string,
  extras: Record<string, string> = {},
  limit: number = 50
): Promise<CatalogMeta[]> {
  await stremioService.ensureInitialized();
  const addons = await stremioService.getInstalledAddons();
  const addon = addons.find((a) => a.installationId === installationId);
  if (!addon?.url) throw new Error('Addon is not installed');

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(buildCatalogUrl(addon.url, type, catalogId, extras), {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`Addon returned ${response.status}`);
    const json = await response.json();
    const metas: unknown[] = Array.isArray(json?.metas) ? json.metas : [];
    return metas
      .slice(0, limit)
      .map(parseMeta)
      .filter((meta): meta is CatalogMeta => meta !== null);
  } finally {
    clearTimeout(timer);
  }
}

/** IMDb id to TMDB id, or null when TMDB has no match. Kept for the session. */
const tmdbIdCache = new Map<string, number | null>();

async function tmdbIdForImdb(imdbId: string, isSeries: boolean): Promise<number | null> {
  const cacheKey = `${isSeries ? 'tv' : 'movie'}:${imdbId}`;
  const cached = tmdbIdCache.get(cacheKey);
  if (cached !== undefined) return cached;
  try {
    const found = await getFlixorCore().tmdb.findByImdbId(imdbId);
    const match = isSeries
      ? found.tv_results?.[0] ?? found.movie_results?.[0]
      : found.movie_results?.[0] ?? found.tv_results?.[0];
    const id = match?.id ?? null;
    tmdbIdCache.set(cacheKey, id);
    return id;
  } catch {
    // Not cached: this may be a passing network error.
    return null;
  }
}

async function resolveTmdbId(meta: CatalogMeta, isSeries: boolean): Promise<number | null> {
  if (meta.id.startsWith('tmdb:')) {
    const numeric = Number(meta.id.split(':').pop());
    return Number.isFinite(numeric) ? numeric : null;
  }
  return meta.imdbId ? tmdbIdForImdb(meta.imdbId, isSeries) : null;
}

/**
 * Maps catalog entries to TMDB titles in bounded batches, keeping order. Titles TMDB
 * can't match are left out, since Details on mobile opens by Plex or TMDB id.
 */
export async function mapCatalogMetas(metas: CatalogMeta[]): Promise<MappedCatalogItem[]> {
  const mapped: Array<MappedCatalogItem | null> = new Array(metas.length).fill(null);
  for (let start = 0; start < metas.length; start += LOOKUP_BATCH_SIZE) {
    await Promise.all(
      metas.slice(start, start + LOOKUP_BATCH_SIZE).map(async (meta, offset) => {
        const isSeries = meta.type === 'series';
        const tmdbId = await resolveTmdbId(meta, isSeries);
        if (tmdbId == null) return;
        mapped[start + offset] = {
          id: `tmdb:${isSeries ? 'tv' : 'movie'}:${tmdbId}`,
          title: meta.name,
          type: isSeries ? 'show' : 'movie',
          image: meta.poster,
          backdrop: meta.background,
          year: meta.year,
          tmdbId,
        };
      })
    );
  }
  return mapped.filter((item): item is MappedCatalogItem => item !== null);
}

/** Searches every search-capable catalog. A failing addon is skipped. */
export async function searchAddonCatalogs(query: string, limit: number = 20): Promise<MappedCatalogItem[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];
  const catalogs = await getSearchableCatalogs();
  if (catalogs.length === 0) return [];

  const pages = await Promise.all(
    catalogs.map((c) =>
      fetchCatalogPage(c.installationId, c.type, c.catalogId, { search: trimmed }, limit).catch((e) => {
        console.log('[AddonCatalogs] search failed for', c.addonName, e?.message);
        return [] as CatalogMeta[];
      })
    )
  );

  const seen = new Set<string>();
  const metas = pages.flat().filter((meta) => {
    if (seen.has(meta.id)) return false;
    seen.add(meta.id);
    return true;
  });

  const seenItems = new Set<string>();
  return (await mapCatalogMetas(metas)).filter((item) => {
    if (seenItems.has(item.id)) return false;
    seenItems.add(item.id);
    return true;
  });
}
