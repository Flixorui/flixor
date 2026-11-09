/** Installed addons: manifest parsing, install, remove, reorder, and capability checks. */
import {
  STORAGE_KEYS,
  createChangeNotifier,
  readJson,
  tryWriteJson,
  writeJson,
} from './storage';
import { loadSettings, saveSettings } from '@/state/settings';
import { fetchAddonJson } from './transport';
import type { StremioAddon, StremioCatalog, StremioRequestType } from './types';

export const DEFAULT_OPEN_SUBTITLES_URL = 'https://opensubtitles-v3.strem.io/manifest.json';
export const DEFAULT_OPEN_SUBTITLES_ID = 'org.stremio.opensubtitlesv3';

interface ResourceDef {
  name: string;
  types?: string[];
  idPrefixes?: string[];
}

/** Stored form. The extra fields are what capability checks need from the manifest. */
export interface InstalledAddon extends StremioAddon {
  resourceDefs: ResourceDef[];
}

const changes = createChangeNotifier(STORAGE_KEYS.addons);
export const subscribeAddons = changes.subscribe;

export function listInstalledAddons(): InstalledAddon[] {
  const addons = readJson<InstalledAddon[]>(STORAGE_KEYS.addons, []);
  return Array.isArray(addons) ? addons : [];
}

function saveAddons(addons: InstalledAddon[]): void {
  writeJson(STORAGE_KEYS.addons, addons);
  changes.notify();
}

/** Accepts `stremio://` install links and URLs with or without `/manifest.json`. */
export function normalizeManifestUrl(input: string): string {
  const trimmed = input.trim().replace(/^stremio:\/\//i, 'https://');
  if (!trimmed) return '';
  const [path, query] = trimmed.split('?');
  const withManifest = /manifest\.json$/i.test(path) ? path : `${path.replace(/\/$/, '')}/manifest.json`;
  return query ? `${withManifest}?${query}` : withManifest;
}

function coerceResources(raw: unknown): ResourceDef[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((entry): ResourceDef[] => {
    if (typeof entry === 'string') return [{ name: entry }];
    if (entry && typeof entry === 'object' && typeof (entry as any).name === 'string') {
      const { name, types, idPrefixes } = entry as any;
      return [{
        name,
        types: Array.isArray(types) ? types : undefined,
        idPrefixes: Array.isArray(idPrefixes) ? idPrefixes : undefined,
      }];
    }
    return [];
  });
}

function parseCatalogs(raw: unknown, installationId: string, addonName: string): StremioCatalog[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((entry: any): StremioCatalog[] => {
    if (typeof entry?.id !== 'string' || typeof entry?.type !== 'string') return [];
    const extras: Array<{ name: string; isRequired?: boolean }> = Array.isArray(entry.extra)
      ? entry.extra.filter((extra: any) => typeof extra?.name === 'string')
      : (entry.extraRequired || entry.extraSupported)
        ? [
            ...(entry.extraRequired ?? []).map((name: string) => ({ name, isRequired: true })),
            ...(entry.extraSupported ?? []).map((name: string) => ({ name })),
          ]
        : [];
    const has = (name: string) => extras.some((extra) => extra.name === name);
    return [{
      installationId,
      addonName,
      type: entry.type,
      id: entry.id,
      name: typeof entry.name === 'string' && entry.name ? entry.name : entry.id,
      supportsSearch: has('search'),
      supportsSkip: has('skip'),
      requiredExtras: extras.filter((extra) => extra.isRequired).map((extra) => extra.name),
    }];
  });
}

function configureUrlFor(manifest: any, manifestUrl: string): string | undefined {
  const explicit = manifest?.behaviorHints?.configurationURL;
  if (typeof explicit === 'string' && /^https?:\/\//i.test(explicit)) return explicit;
  if (!manifest?.behaviorHints?.configurable) return undefined;
  const [path, query] = manifestUrl.split('?');
  const configure = path.replace(/manifest\.json$/i, 'configure');
  return query ? `${configure}?${query}` : configure;
}

function newInstallationId(addonId: string): string {
  return `${addonId}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

async function fetchManifest(manifestUrl: string, signal?: AbortSignal): Promise<InstalledAddon> {
  if (!/^https?:\/\//i.test(manifestUrl)) throw new Error('Enter an http or https addon URL');
  const manifest = await fetchAddonJson<any>(manifestUrl, { signal });
  if (typeof manifest?.id !== 'string' || typeof manifest?.name !== 'string') {
    throw new Error('This URL did not return a Stremio addon manifest');
  }
  const installationId = newInstallationId(manifest.id);
  const resourceDefs = coerceResources(manifest.resources);
  return {
    installationId,
    id: manifest.id,
    name: manifest.name,
    version: typeof manifest.version === 'string' ? manifest.version : '',
    description: typeof manifest.description === 'string' ? manifest.description : undefined,
    logo: typeof manifest.logo === 'string' ? manifest.logo : undefined,
    manifestUrl,
    types: Array.isArray(manifest.types) ? manifest.types : [],
    resources: resourceDefs.map((resource) => resource.name),
    idPrefixes: Array.isArray(manifest.idPrefixes) ? manifest.idPrefixes : undefined,
    catalogs: parseCatalogs(manifest.catalogs, installationId, manifest.name),
    configurable: Boolean(manifest.behaviorHints?.configurable),
    configureUrl: configureUrlFor(manifest, manifestUrl),
    resourceDefs,
  };
}

export function addonSupportsResource(
  addon: InstalledAddon,
  resourceName: string,
  type?: string,
  contentId?: string,
): boolean {
  return addon.resourceDefs.some((resource) => {
    if (resource.name !== resourceName) return false;
    const types = resource.types ?? addon.types;
    if (type && types.length > 0 && !types.includes(type)) return false;
    const prefixes = resource.idPrefixes ?? addon.idPrefixes ?? [];
    return !contentId || prefixes.length === 0 || prefixes.some((prefix) => contentId.startsWith(prefix));
  });
}

export function addonProvidesStreams(addon: InstalledAddon): boolean {
  return addon.resourceDefs.some((resource) => resource.name === 'stream');
}

export function addonProvidesSubtitles(addon: InstalledAddon): boolean {
  return addon.resourceDefs.some((resource) => resource.name === 'subtitles');
}

/** True when some addon could answer for this id. Addons without id prefixes accept any. */
export function canResolveId(type: StremioRequestType, contentId: string): boolean {
  return listInstalledAddons().some((addon) => addonSupportsResource(addon, 'stream', type, contentId));
}

export function hasStreamProviders(type?: StremioRequestType): boolean {
  return listInstalledAddons().some((addon) => addonSupportsResource(addon, 'stream', type));
}

export async function installAddon(manifestUrl: string): Promise<StremioAddon> {
  const normalized = normalizeManifestUrl(manifestUrl);
  if (!normalized) throw new Error('Enter an addon URL');
  const addon = await fetchManifest(normalized);

  const installed = listInstalledAddons();
  // Stream addons can repeat with different configurations. Anything else would duplicate.
  if (installed.some((other) => other.id === addon.id) && !addonProvidesStreams(addon)) {
    throw new Error('This addon is already installed');
  }
  saveAddons([...installed, addon]);
  enablePlaybackForStreamAddons();

  const removed = readJson<string[]>(STORAGE_KEYS.removedDefaults, []);
  if (removed.includes(addon.id)) {
    tryWriteJson(STORAGE_KEYS.removedDefaults, removed.filter((id) => id !== addon.id));
  }
  return addon;
}

/**
 * Adding a stream addon means the user wants to play from it, so addon playback turns
 * on, unless they switched it off themselves (the setting is then stored).
 */
export function enablePlaybackForStreamAddons(): void {
  try {
    const stored = loadSettings();
    if (stored.stremioPlaybackEnabled || stored.stremioPlaybackSetByUser) return;
    if (!listInstalledAddons().some(addonProvidesStreams)) return;
    saveSettings({ stremioPlaybackEnabled: true });
  } catch {
    // Storage unavailable: leave the setting as it is.
  }
}

export function removeAddon(installationId: string): void {
  const installed = listInstalledAddons();
  const addon = installed.find((other) => other.installationId === installationId);
  if (!addon) return;
  const remaining = installed.filter((other) => other.installationId !== installationId);

  // Remember that the user removed the default, so it is not silently reinstalled.
  if (addon.id === DEFAULT_OPEN_SUBTITLES_ID && !remaining.some((other) => other.id === addon.id)) {
    const removed = readJson<string[]>(STORAGE_KEYS.removedDefaults, []);
    if (!removed.includes(addon.id)) tryWriteJson(STORAGE_KEYS.removedDefaults, [...removed, addon.id]);
  }
  saveAddons(remaining);
}

/** Applies the given order. Ids not listed keep their relative order at the end. */
export function reorderAddons(installationIds: string[]): void {
  const installed = listInstalledAddons();
  const position = new Map(installationIds.map((id, index) => [id, index]));
  const rank = (addon: InstalledAddon) => position.get(addon.installationId) ?? Number.MAX_SAFE_INTEGER;
  saveAddons([...installed].sort((a, b) => rank(a) - rank(b)));
}

/** Installs OpenSubtitles the first time Stremio is enabled. Failures are not user errors. */
export async function ensureDefaultAddons(): Promise<void> {
  const removed = readJson<string[]>(STORAGE_KEYS.removedDefaults, []);
  if (removed.includes(DEFAULT_OPEN_SUBTITLES_ID)) return;
  if (listInstalledAddons().some((addon) => addon.id === DEFAULT_OPEN_SUBTITLES_ID)) return;
  try {
    await installAddon(DEFAULT_OPEN_SUBTITLES_URL);
  } catch {
    // Retried the next time the Stremio settings are opened.
  }
}

// Profiles that added stream addons before this rule existed.
enablePlaybackForStreamAddons();
