/**
 * Addon catalogs: which ones are installed and how to fetch a page of one.
 * macOS reference: Services/Stremio/StremioService.swift (Catalogs).
 *
 * Addon URLs can carry tokens in their path or query, so errors from this file
 * never include the URL.
 */

import { stremioService } from './StremioService';
import type { StremioAddonManifest, StremioResource } from './types';

interface ManifestCatalogExtra {
  name?: string;
  isRequired?: boolean;
}

interface ManifestCatalog {
  type?: string;
  id?: string;
  name?: string;
  extra?: ManifestCatalogExtra[];
  /** Legacy manifest fields. */
  extraSupported?: string[];
  extraRequired?: string[];
}

type CatalogManifest = StremioAddonManifest & { catalogs?: ManifestCatalog[] };

export interface InstalledCatalog {
  /** "stremio-catalog-<installation>:<type>:<catalog>" */
  rowId: string;
  installationId: string;
  addonId: string;
  addonName: string;
  type: 'movie' | 'series';
  catalogId: string;
  title: string;
  supportsPaging: boolean;
}

export interface StremioMetaPreview {
  id: string;
  type: string;
  name: string;
  poster?: string;
  background?: string;
  description?: string;
  imdbRating?: string;
  releaseInfo?: string;
  year?: number;
  imdb_id?: string;
}

/** Most catalogs shown as Home rows, as on macOS. */
export const MAX_HOME_CATALOG_ROWS = 8;
const MAX_CONCURRENT_REQUESTS = 3;
const REQUEST_TIMEOUT_MS = 12_000;

let active = 0;
const waiting: Array<() => void> = [];

async function withRequestSlot<T>(work: () => Promise<T>): Promise<T> {
  if (active >= MAX_CONCURRENT_REQUESTS) {
    await new Promise<void>((resolve) => waiting.push(resolve));
  }
  active += 1;
  try {
    return await work();
  } finally {
    active -= 1;
    waiting.shift()?.();
  }
}

function resourceName(resource: StremioResource): string | undefined {
  return typeof resource === 'string' ? resource : resource?.name;
}

function addonServesCatalogType(addon: StremioAddonManifest, type: string): boolean {
  return (addon.resources || []).some((resource) => {
    if (resourceName(resource) !== 'catalog') return false;
    const types = (typeof resource === 'object' && resource.types) || addon.types || [];
    return types.length === 0 || types.includes(type);
  });
}

function requiredExtras(catalog: ManifestCatalog): string[] {
  const required = (catalog.extra || []).filter((extra) => extra.isRequired).map((extra) => extra.name || '');
  return [...required, ...(catalog.extraRequired || [])];
}

function supportsPaging(catalog: ManifestCatalog): boolean {
  return (
    (catalog.extra || []).some((extra) => extra.name === 'skip') ||
    (catalog.extraSupported || []).includes('skip')
  );
}

function catalogTitle(catalog: ManifestCatalog): string {
  const id = catalog.id || '';
  const base = catalog.name || (id ? id.charAt(0).toUpperCase() + id.slice(1) : 'Catalog');
  return catalog.type === 'series' ? `${base} (TV)` : base;
}

function addonBaseUrl(addon: StremioAddonManifest): string | undefined {
  return addon.url || addon.transportUrl || addon.originalUrl;
}

/**
 * Catalogs that can be listed without user input, in addon priority order. Only movie
 * and series catalogs qualify, because other types can't be matched to a details page.
 */
export async function getBrowsableCatalogs(): Promise<InstalledCatalog[]> {
  const addons = (await stremioService.getInstalledAddons()) as CatalogManifest[];
  const catalogs: InstalledCatalog[] = [];
  for (const addon of addons) {
    if (!addonBaseUrl(addon)) continue;
    for (const catalog of addon.catalogs || []) {
      const { type, id: catalogId } = catalog;
      if ((type !== 'movie' && type !== 'series') || !catalogId) continue;
      if (requiredExtras(catalog).some((name) => name !== 'skip')) continue;
      if (!addonServesCatalogType(addon, type)) continue;
      catalogs.push({
        rowId: `stremio-catalog-${addon.installationId}:${type}:${catalogId}`,
        installationId: addon.installationId,
        addonId: addon.id,
        addonName: addon.name,
        type,
        catalogId,
        title: catalogTitle(catalog),
        supportsPaging: supportsPaging(catalog),
      });
    }
  }
  return catalogs;
}

function buildCatalogUrl(addon: StremioAddonManifest, catalog: InstalledCatalog, skip: number): string {
  const [rawBase, query] = (addonBaseUrl(addon) as string).split('?');
  const base = rawBase.replace(/manifest\.json$/i, '').replace(/\/$/, '');
  const extra = skip > 0 ? `/skip=${skip}` : '';
  const path = `/catalog/${catalog.type}/${encodeURIComponent(catalog.catalogId)}${extra}.json`;
  return query ? `${base}${path}?${query}` : `${base}${path}`;
}

function parseYear(meta: any): number | undefined {
  if (typeof meta.year === 'number') return meta.year;
  const text = String(meta.releaseInfo ?? meta.year ?? '');
  const match = text.match(/\d{4}/);
  return match ? Number(match[0]) : undefined;
}

function parsePreview(meta: any): StremioMetaPreview | null {
  if (!meta || typeof meta !== 'object') return null;
  if (typeof meta.id !== 'string' || typeof meta.name !== 'string' || !meta.name) return null;
  return {
    id: meta.id,
    type: typeof meta.type === 'string' ? meta.type : 'movie',
    name: meta.name,
    poster: typeof meta.poster === 'string' ? meta.poster : undefined,
    background: typeof meta.background === 'string' ? meta.background : undefined,
    description: typeof meta.description === 'string' ? meta.description : undefined,
    imdbRating: meta.imdbRating != null ? String(meta.imdbRating) : undefined,
    releaseInfo: typeof meta.releaseInfo === 'string' ? meta.releaseInfo : undefined,
    year: parseYear(meta),
    imdb_id: typeof meta.imdb_id === 'string' ? meta.imdb_id : undefined,
  };
}

/** Fetches one catalog page. Throws when the addon request fails. */
export async function fetchCatalogPage(
  catalog: InstalledCatalog,
  skip: number = 0,
  limit: number = 30
): Promise<StremioMetaPreview[]> {
  const addons = await stremioService.getInstalledAddons();
  const addon = addons.find((candidate) => candidate.installationId === catalog.installationId);
  if (!addon) return [];

  const url = buildCatalogUrl(addon, catalog, skip);
  return withRequestSlot(async () => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`Addon returned HTTP ${response.status}`);
      const body = await response.json();
      const metas: unknown[] = Array.isArray(body?.metas) ? body.metas : [];
      return metas
        .map(parsePreview)
        .filter((preview): preview is StremioMetaPreview => preview !== null)
        .slice(0, limit);
    } catch (e: any) {
      if (e?.name === 'AbortError') throw new Error('Addon request timed out');
      if (e instanceof Error && e.message.startsWith('Addon')) throw e;
      throw new Error('Addon request failed');
    } finally {
      clearTimeout(timer);
    }
  });
}
