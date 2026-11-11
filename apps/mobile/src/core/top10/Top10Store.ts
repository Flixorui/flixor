/**
 * Settings and data for the Top 10 and "New on" rows. Two kinds of source, both supplied by
 * the user:
 * - FlixPatrol JSON APIs (URL + key): tried first for Top 10 rows, in order. No call limit.
 * - Streaming Availability keys: "New on" rows, and the Top 10 fallback when no FlixPatrol
 *   source has the list. Budgeted.
 * Lists always come from the phone first; an entry is fetched again only when it is older
 * than its refresh interval (and, for Streaming Availability, when the budget allows). A row
 * is never dropped because the budget ran out.
 * macOS reference: StreamingAvailabilityStore.swift
 */

import { useSyncExternalStore } from 'react';
import { addSettingsListener, getAppSettings, setAppSettings } from '../SettingsData';
import { appSettingsEmitter } from '../../hooks/useAppSettings';
import {
  ALL_SERVICES, SERVICE_NAMES, backdropUrl, deviceRegion, hasStreamingAvailability, isSeries, posterUrl, tmdbRef,
  type SAChangesResult, type SACountry, type SAShow, type StreamingServiceId,
} from './Top10Models';
import { fingerprint } from './sha256';
import * as Budget from './Top10Budget';
import { cacheGeneration, clearCache as clearDiskCache, readCache, writeCache } from './Top10Cache';
import { OVER_BUDGET, Top10HttpError, fpGet, saGet } from './Top10Clients';
import {
  loadKeys, loadSources, maskKey, normalizeUrl, saveKeys, saveSources, sourceHost, sourceId, type FlixPatrolSource,
} from './Top10Secrets';

export const ROW_PREFIX = 'sa-';
/** FlixPatrol charts update about once a day and calls are free: check every 6 hours at most. */
const FLIXPATROL_MAX_AGE = 6 * 3600 * 1000;
const DAY = 86400 * 1000;

export type Top10Item = {
  id: string; // "tmdb:movie:123"
  title: string;
  image?: string;
  backdrop?: string;
  year?: number;
  tmdbId: number;
  mediaType: 'movie' | 'tv';
};

export type Top10Section = { id: string; title: string; kind: 'top' | 'new'; service: StreamingServiceId; items: Top10Item[] };

type RowSpec = { id: string; title: string; service: StreamingServiceId; type: 'movie' | 'series' | 'all' | 'new' };

export type SavedList = {
  id: string;
  title: string;
  fetchedAt?: number;
  count: number;
  source: 'FlixPatrol' | 'Streaming Availability';
  /** Refetching costs a Streaming Availability call. */
  usesBudget: boolean;
};

// ---------------------------------------------------------------- state

let keys: string[] = [];
let sources: FlixPatrolSource[] = [];
let regionServices: Set<string> | null = null;
let flixPatrolServices: Set<string> | null = null;
let flixPatrolError: string | null = null;
let lastError: string | null = null;
let lastRefresh: number | null = null;
let ready = false;
let initPromise: Promise<void> | null = null;
let loading = false;

let version = 0;
const listeners = new Set<() => void>();
function changed() {
  version += 1;
  listeners.forEach((l) => l());
}

/** Home listens to this to reload its rows after Settings changes something. */
const updateListeners = new Set<() => void>();
export function onTop10Update(listener: () => void): () => void {
  updateListeners.add(listener);
  return () => updateListeners.delete(listener);
}
function notifyHome() {
  updateListeners.forEach((l) => l());
}

export function useTop10Version(): number {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => version
  );
}

// ---------------------------------------------------------------- settings

export const region = () => getAppSettings().top10Region || deviceRegion();
const settings = () => getAppSettings();

export async function initTop10(): Promise<void> {
  if (ready) return;
  if (!initPromise) {
    initPromise = (async () => {
      await Budget.loadBudget();
      keys = await loadKeys();
      sources = await loadSources();
      await loadRegionServices();
      ready = true;
      changed();
    })();
  }
  return initPromise;
}

let lastRegion: string | null = null;
addSettingsListener(() => {
  const r = region();
  if (ready && r !== lastRegion) {
    lastRegion = r;
    loadRegionServices().then(changed);
  } else {
    changed();
  }
});

async function loadRegionServices() {
  lastRegion = region();
  regionServices = servicesOf(await readCache(`country|${region()}`));
  flixPatrolServices = servicesOf(await readCache(`fp-country|${region()}`));
}

function servicesOf(entry: { body: string } | null): Set<string> | null {
  if (!entry) return null;
  try {
    return new Set((JSON.parse(entry.body) as SACountry).services.map((s) => s.id));
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------- status

export const hasKey = () => keys.length > 0;
export const hasFlixPatrol = () => sources.length > 0;
export const hasAnySource = () => hasKey() || hasFlixPatrol();
export const isActive = () => hasAnySource() && settings().top10Enabled;
export const isReady = () => ready;
export const getFlixPatrolError = () => flixPatrolError;
export const getLastError = () => lastError;
export const getLastRefresh = () => lastRefresh;
export const getFlixPatrolServices = () => flixPatrolServices;

export type KeyInfo = { id: string; masked: string };
export const keyInfos = (): KeyInfo[] => keys.map((k) => ({ id: fingerprint(k), masked: maskKey(k) }));
export const keyFingerprints = () => keys.map(fingerprint);

export type SourceInfo = { id: string; host: string; masked: string };
export const sourceInfos = (): SourceInfo[] => sources.map((s) => ({ id: sourceId(s), host: sourceHost(s), masked: maskKey(s.key) }));

/** A FlixPatrol source has charts for the service in the region (assumed until known). */
export const flixPatrolCovers = (s: StreamingServiceId) => hasFlixPatrol() && (flixPatrolServices?.has(s) ?? true);

/** A Streaming Availability key can fetch the service's lists in the region (assumed until known). */
export const streamingAvailabilityCovers = (s: StreamingServiceId) =>
  hasKey() && hasStreamingAvailability(s) && (regionServices?.has(s) ?? true);

/** Services with a Top 10 list from any source. */
export const availableServices = () => ALL_SERVICES.filter((s) => flixPatrolCovers(s) || streamingAvailabilityCovers(s));

/** Services with "New on" rows (Streaming Availability only). */
export const newRowServices = () => ALL_SERVICES.filter(streamingAvailabilityCovers);

export function allowanceToday(): number {
  return Budget.totalAllowance(keyFingerprints());
}

// ---------------------------------------------------------------- keys

export async function addKey(raw: string): Promise<string | null> {
  await initTop10();
  const key = raw.trim();
  if (!key) return null;
  if (keys.includes(key)) return 'That key is already added.';
  const fp = fingerprint(key);
  try {
    const { body, quota } = await saGet(key, `countries/${region()}`);
    Budget.recordQuota(fp, quota);
    await writeCache(`country|${region()}`, body);
    regionServices = servicesOf({ body });
    keys = [...keys, key];
    await saveKeys(keys);
    lastError = null;
    changed();
    notifyHome();
    return null;
  } catch (e: any) {
    return e?.message || 'The key could not be checked.';
  }
}

export async function removeKey(fp: string): Promise<void> {
  keys = keys.filter((k) => fingerprint(k) !== fp);
  await saveKeys(keys);
  Budget.forgetKey(fp);
  changed();
  notifyHome();
}

function reserveKey(): { key: string; fp: string } | null {
  const fp = Budget.spend(keyFingerprints());
  const key = fp ? keys.find((k) => fingerprint(k) === fp) : undefined;
  return fp && key ? { key, fp } : null;
}

// ---------------------------------------------------------------- FlixPatrol sources

export async function addFlixPatrolSource(rawUrl: string, rawKey: string): Promise<string | null> {
  await initTop10();
  const url = normalizeUrl(rawUrl);
  const key = rawKey.trim();
  if (!url || !key) return 'Enter both the URL and the API key.';
  if (!/^https?:\/\/[^/\s]+/i.test(url)) return "That isn't a valid URL.";
  const source = { url, key };
  if (sources.some((s) => sourceId(s) === sourceId(source))) return 'That API is already added.';
  try {
    const body = await fpGet(source, `countries/${region()}`);
    const services = servicesOf({ body });
    if (!services) return 'FlixPatrol sent an unexpected response.';
    await writeCache(`fp-country|${region()}`, body);
    flixPatrolServices = services;
  } catch (e: any) {
    if (e instanceof Top10HttpError && e.status === 404) {
      // The API works but has no charts for this region: keep it for other regions
      flixPatrolServices = new Set();
    } else {
      return e?.message || 'The API could not be checked.';
    }
  }
  sources = [...sources, source];
  await saveSources(sources);
  flixPatrolError = null;
  changed();
  notifyHome();
  return null;
}

export async function removeFlixPatrolSource(id: string): Promise<void> {
  sources = sources.filter((s) => sourceId(s) !== id);
  await saveSources(sources);
  if (!sources.length) {
    flixPatrolServices = null;
    flixPatrolError = null;
  }
  changed();
  notifyHome();
}

/** Moves a source to the top, so it's tried first. */
export async function preferFlixPatrolSource(id: string): Promise<void> {
  const first = sources.find((s) => sourceId(s) === id);
  if (!first) return;
  sources = [first, ...sources.filter((s) => sourceId(s) !== id)];
  await saveSources(sources);
  changed();
}

// ---------------------------------------------------------------- fetching

/** Cached FlixPatrol data, refreshed when older than `maxAge`; sources tried in order. */
async function flixPatrolData(cacheKey: string, path: string, query: Record<string, string>, maxAge: number, force: boolean): Promise<string | null> {
  const cached = await readCache(cacheKey);
  const due = force || !cached || Date.now() - cached.fetchedAt > maxAge;
  if (!due || !hasFlixPatrol()) return cached?.body ?? null;
  let failure: string | null = null;
  for (const source of sources) {
    try {
      const body = await fpGet(source, path, query);
      await writeCache(cacheKey, body);
      flixPatrolError = null;
      return body;
    } catch (e: any) {
      failure = e?.message ?? 'FlixPatrol failed.';
    }
  }
  flixPatrolError = failure;
  return cached?.body ?? null;
}

/** Cached Streaming Availability data, refreshed when due and a call is allowed. */
async function saData(cacheKey: string, path: string, query: Record<string, string>, maxAge: number, force: boolean): Promise<string | null> {
  const cached = await readCache(cacheKey);
  const due = force || !cached || Date.now() - cached.fetchedAt > maxAge;
  if (!due || !hasKey()) return cached?.body ?? null;
  const reserved = reserveKey();
  if (!reserved) {
    lastError = OVER_BUDGET;
    return cached?.body ?? null;
  }
  try {
    const { body, quota } = await saGet(reserved.key, path, query);
    Budget.recordQuota(reserved.fp, quota);
    await writeCache(cacheKey, body);
    lastError = null;
    return body;
  } catch (e: any) {
    if (e instanceof Top10HttpError && e.status === 429) Budget.markExhausted(reserved.fp);
    lastError = e?.message ?? 'Streaming Availability failed.';
    return cached?.body ?? null;
  }
}

/** The region's FlixPatrol services: saved for a week, then asked again. */
async function loadFlixPatrolCountry(force: boolean) {
  const key = `fp-country|${region()}`;
  const cached = await readCache(key);
  if (!force && cached && Date.now() - cached.fetchedAt < 7 * DAY) {
    flixPatrolServices = servicesOf(cached);
    if (flixPatrolServices) return;
  }
  for (const source of sources) {
    try {
      const body = await fpGet(source, `countries/${region()}`);
      const services = servicesOf({ body });
      if (!services) continue;
      await writeCache(key, body);
      flixPatrolServices = services;
      return;
    } catch (e: any) {
      if (e instanceof Top10HttpError && e.status === 404) {
        flixPatrolServices = new Set(); // FlixPatrol doesn't cover this region
        return;
      }
      flixPatrolError = e?.message ?? 'FlixPatrol failed.';
    }
  }
}

async function loadCountry() {
  const body = await saData(`country|${region()}`, `countries/${region()}`, {}, 30 * DAY, false);
  const services = body ? servicesOf({ body }) : null;
  if (services) regionServices = services;
}

// ---------------------------------------------------------------- rows

export function rowSpecs(): RowSpec[] {
  if (!isActive()) return [];
  const s = settings();
  const specs: RowSpec[] = [];
  for (const service of availableServices()) {
    if (!s.top10Services.includes(service)) continue;
    const name = SERVICE_NAMES[service];
    if (s.top10SplitByType) {
      specs.push({ id: `${ROW_PREFIX}top-${service}-movie`, title: `Top 10 Movies on ${name}`, service, type: 'movie' });
      specs.push({ id: `${ROW_PREFIX}top-${service}-series`, title: `Top 10 Shows on ${name}`, service, type: 'series' });
    } else {
      specs.push({ id: `${ROW_PREFIX}top-${service}`, title: `Top 10 on ${name}`, service, type: 'all' });
    }
  }
  for (const service of newRowServices()) {
    if (s.top10NewServices.includes(service)) {
      specs.push({ id: `${ROW_PREFIX}new-${service}`, title: `New on ${SERVICE_NAMES[service]}`, service, type: 'new' });
    }
  }
  return specs;
}

const fpCacheKey = (spec: RowSpec) => `fp|top|${region()}|${spec.service}|${spec.type}`;
const saCacheKey = (spec: RowSpec) =>
  spec.type === 'new' ? `new2|${region()}|${spec.service}` : `top|${region()}|${spec.service}|${spec.type}`;
const servedByFlixPatrol = (spec: RowSpec) => spec.type !== 'new' && flixPatrolCovers(spec.service);

/** FlixPatrol's top 10 in chart order; a mixed row alternates movie and show charts by rank. */
export function flixPatrolRanked(shows: SAShow[], type: 'movie' | 'series' | 'all'): SAShow[] {
  const rank = (show: SAShow) => {
    const rankings = show.rankings ?? [];
    const chart = isSeries(show) ? 'tv-shows' : 'movies';
    const match = rankings.find((r) => r.category === chart) ?? [...rankings].sort((a, b) => a.rank - b.rank)[0];
    return match?.rank ?? Number.MAX_SAFE_INTEGER;
  };
  const ordered = shows
    .map((show, index) => ({ show, index }))
    .sort((a, b) => rank(a.show) - rank(b.show) || a.index - b.index)
    .map((x) => x.show);
  if (type !== 'all') return ordered.slice(0, 10);
  const movies = ordered.filter((s) => !isSeries(s));
  const series = ordered.filter(isSeries);
  const mixed: SAShow[] = [];
  for (let i = 0; i < Math.max(movies.length, series.length); i++) {
    if (i < movies.length) mixed.push(movies[i]);
    if (i < series.length) mixed.push(series[i]);
  }
  return mixed.slice(0, 10);
}

/** Titles new on the service's own subscription, once each, newest first. */
export function newShows(result: SAChangesResult): SAShow[] {
  const seen = new Set<string>();
  const out: SAShow[] = [];
  for (const change of result.changes ?? []) {
    const type = change.streamingOptionType;
    if ((type && type !== 'subscription') || seen.has(change.showId)) continue;
    seen.add(change.showId);
    const show = result.shows?.[change.showId];
    if (show) out.push(show);
  }
  return out;
}

function parse<T>(body: string | null): T | null {
  if (!body) return null;
  try {
    return JSON.parse(body) as T;
  } catch {
    return null;
  }
}

function section(spec: RowSpec, shows: SAShow[]): Top10Section | null {
  const items: Top10Item[] = [];
  for (const show of shows) {
    const ref = tmdbRef(show);
    if (!ref) continue;
    items.push({
      id: `tmdb:${ref.mediaType}:${ref.tmdbId}`,
      title: show.title,
      image: posterUrl(show),
      backdrop: backdropUrl(show),
      year: show.releaseYear ?? show.firstAirYear,
      ...ref,
    });
  }
  return items.length ? { id: spec.id, title: spec.title, kind: spec.type === 'new' ? 'new' : 'top', service: spec.service, items } : null;
}

const topQuery = (spec: RowSpec): Record<string, string> => ({
  country: region(),
  service: spec.service,
  ...(spec.type === 'movie' || spec.type === 'series' ? { show_type: spec.type } : {}),
});

function newQuery(spec: RowSpec): Record<string, string> {
  return {
    country: region(),
    // ".subscription": the service itself, not its rent/buy store or the channels sold
    // through it (Apple TV's add-ons, Prime's AMC+, ...)
    catalogs: `${spec.service}.subscription`,
    change_type: 'new',
    item_type: 'show',
    from: String(Math.floor((Date.now() - 7 * DAY) / 1000)),
    order_direction: 'desc',
  };
}

/** One list: cached, or fetched when due (or forced) within the budget. */
async function fetchList(spec: RowSpec, maxAge: number, force: boolean): Promise<Top10Section | null> {
  if (spec.type !== 'new') {
    if (flixPatrolCovers(spec.service)) {
      const body = await flixPatrolData(fpCacheKey(spec), 'shows/top', topQuery(spec), Math.min(maxAge, FLIXPATROL_MAX_AGE), force);
      const shows = parse<SAShow[]>(body);
      const result = shows ? section(spec, flixPatrolRanked(shows, spec.type)) : null;
      if (result) return result;
    }
    // Fallback: Streaming Availability, within its budget
    if (!streamingAvailabilityCovers(spec.service)) return null;
    const shows = parse<SAShow[]>(await saData(saCacheKey(spec), 'shows/top', topQuery(spec), maxAge, force));
    return shows ? section(spec, shows.slice(0, 10)) : null;
  }
  const result = parse<SAChangesResult>(await saData(saCacheKey(spec), 'changes', newQuery(spec), Math.max(maxAge, 2 * DAY), force));
  return result ? section(spec, newShows(result).slice(0, 20)) : null;
}

/** Rows from whatever is saved, with no network at all. */
export async function cachedSections(): Promise<Top10Section[]> {
  await initTop10();
  const out: Top10Section[] = [];
  for (const spec of rowSpecs()) {
    let result: Top10Section | null = null;
    if (spec.type !== 'new') {
      if (flixPatrolCovers(spec.service)) {
        const shows = parse<SAShow[]>((await readCache(fpCacheKey(spec)))?.body ?? null);
        result = shows ? section(spec, flixPatrolRanked(shows, spec.type)) : null;
      }
      if (!result && streamingAvailabilityCovers(spec.service)) {
        const shows = parse<SAShow[]>((await readCache(saCacheKey(spec)))?.body ?? null);
        result = shows ? section(spec, shows.slice(0, 10)) : null;
      }
    } else {
      const changes = parse<SAChangesResult>((await readCache(saCacheKey(spec)))?.body ?? null);
      result = changes ? section(spec, newShows(changes).slice(0, 20)) : null;
    }
    if (result) out.push(result);
  }
  return out;
}

/** The Home rows: saved copies, refreshing whatever is due within the budget. */
export async function top10Sections(force = false): Promise<Top10Section[]> {
  await initTop10();
  if (!isActive()) return [];
  if (loading) return cachedSections();
  loading = true;
  try {
    if (hasFlixPatrol() && (flixPatrolServices === null || force)) await loadFlixPatrolCountry(force);
    if (hasKey() && (regionServices === null || force)) await loadCountry();
    const maxAge = settings().top10RefreshHours * 3600 * 1000;
    const specs = rowSpecs();
    const results: Array<Top10Section | null> = new Array(specs.length).fill(null);
    // A few lists at a time. Each Streaming Availability call reserves its budget before it
    // awaits, so the budget holds with several in flight.
    let next = 0;
    const worker = async () => {
      while (next < specs.length) {
        const index = next++;
        results[index] = await fetchList(specs[index], maxAge, force);
      }
    };
    await Promise.all([worker(), worker(), worker()]);
    lastRefresh = Date.now();
    return results.filter((r): r is Top10Section => r !== null);
  } finally {
    loading = false;
    changed();
  }
}

// ---------------------------------------------------------------- Settings actions

export async function savedLists(): Promise<SavedList[]> {
  await initTop10();
  const counts = new Map((await cachedSections()).map((s) => [s.id, s.items.length]));
  const lists: SavedList[] = [];
  for (const spec of rowSpecs()) {
    const fpEntry = servedByFlixPatrol(spec) ? await readCache(fpCacheKey(spec)) : null;
    const entry = fpEntry ?? (await readCache(saCacheKey(spec)));
    lists.push({
      id: spec.id,
      title: spec.title,
      fetchedAt: entry?.fetchedAt,
      count: counts.get(spec.id) ?? 0,
      source: fpEntry || (!entry && servedByFlixPatrol(spec)) ? 'FlixPatrol' : 'Streaming Availability',
      usesBudget: !servedByFlixPatrol(spec),
    });
  }
  return lists;
}

export const savedListsKey = () => `${version}|${cacheGeneration()}|${region()}`;

/** Fetches one list now (free from FlixPatrol, else 1 call), then asks Home to reload. */
export async function refetch(rowId: string): Promise<void> {
  const spec = rowSpecs().find((s) => s.id === rowId);
  if (!spec) return;
  await fetchList(spec, 0, true);
  changed();
  notifyHome();
}

/** Refreshes every row now (still within the budget) and asks Home to reload. */
export async function refreshNow(): Promise<void> {
  await top10Sections(true);
  notifyHome();
}

export async function clearSavedLists(): Promise<void> {
  await clearDiskCache();
  regionServices = null;
  flixPatrolServices = null;
  changed();
  notifyHome();
}

/** Streaming Availability calls a full refresh costs (FlixPatrol lists are free). */
export const callsPerRefresh = () => rowSpecs().filter((s) => !servedByFlixPatrol(s)).length;

export async function updateTop10Settings(patch: Parameters<typeof setAppSettings>[0]): Promise<void> {
  await setAppSettings(patch);
  // Screens using useAppSettings refresh on its own emitter
  appSettingsEmitter.emit();
  notifyHome();
}
