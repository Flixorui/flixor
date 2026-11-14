/**
 * The one place the app reads MyBluray data from. Each read is cached on
 * disk (MMKV) with its own time limit, per key id, so profiles with
 * different keys never share data. Concurrent reads share one request, a
 * "no match" is remembered for a day, and when MyBluray is down a saved copy
 * is returned even if expired. Mirrors macOS MyBlurayService.
 */
import { createMMKV, type MMKV } from 'react-native-mmkv';
import { MyBlurayClient, MyBlurayError, segment } from './client';
import { myblurayKey } from './options';
import type {
  AccessState, MBCollectionEntry, MBCollectionList, MBEdition, MBEditionSummary, MBMovie,
  MBParentsGuide, MBTitle, MyBlurayAccess,
} from './types';

const HOUR = 3600 * 1000;
export const TTL = {
  title: 24 * HOUR,
  parentsGuide: 7 * 24 * HOUR,
  movie: 30 * 24 * HOUR,
  editions: 7 * 24 * HOUR,
  edition: 7 * 24 * HOUR,
  collection: 5 * 60 * 1000,
  notFound: 24 * HOUR,
};
const MAX_EDITION_PAGES = 5;
/** A film every source has, for the key check. */
const PROBE_IMDB = 'tt0468569';
const COLLECTION_RECHECK = 10 * 60 * 1000;

let storage: MMKV | null = null;
function store(): MMKV {
  if (!storage) storage = createMMKV({ id: 'flixor-mybluray' });
  return storage;
}

interface Stored<T> { at: number; value: T | null }

const inFlight = new Map<string, Promise<any>>();
const collectionUnavailableUntil = new Map<string, number>();
export let networkRequestCount = 0;

/** Cache entries are kept per key id (the part after `mbr_`). */
function keyScope(key: string): string {
  const parts = key.split('_');
  if (parts.length >= 3 && parts[0] === 'mbr') return parts[1];
  let hash = 0;
  for (let i = 0; i < key.length; i++) hash = (hash * 31 + key.charCodeAt(i)) | 0;
  return `k${(hash >>> 0).toString(16)}`;
}

function client(): MyBlurayClient {
  const key = myblurayKey();
  if (!key) throw new MyBlurayError('noKey');
  return new MyBlurayClient(key);
}

function readStored<T>(fullKey: string): Stored<T> | null {
  try {
    const raw = store().getString(fullKey);
    return raw ? (JSON.parse(raw) as Stored<T>) : null;
  } catch {
    return null;
  }
}

async function cached<T>(key: string, ttl: number, fetcher: (c: MyBlurayClient) => Promise<T>): Promise<T | null> {
  const c = client();
  const fullKey = `${keyScope(c.apiKey)}|${key}`;
  const saved = readStored<T>(fullKey);
  if (saved) {
    const limit = saved.value === null ? TTL.notFound : ttl;
    if (Date.now() - saved.at < limit) return saved.value;
  }
  let task = inFlight.get(fullKey) as Promise<T | null> | undefined;
  if (!task) {
    networkRequestCount += 1;
    task = (async () => {
      try {
        const value = await fetcher(c);
        store().set(fullKey, JSON.stringify({ at: Date.now(), value }));
        return value;
      } catch (error) {
        if (error instanceof MyBlurayError && error.kind === 'notFound') {
          store().set(fullKey, JSON.stringify({ at: Date.now(), value: null }));
          return null;
        }
        throw error;
      } finally {
        inFlight.delete(fullKey);
      }
    })();
    inFlight.set(fullKey, task);
  }
  try {
    return await task;
  } catch (error) {
    const transient = error instanceof MyBlurayError ? error.isTransient : true;
    if (transient && saved) return saved.value;
    throw error;
  }
}

/** "tt0468569", "imdb:tt0468569" and "imdb://tt0468569" all become "tt0468569". */
export function normalizedImdbId(raw?: string | null): string | null {
  const match = /tt\d{7,10}/.exec(raw ?? '');
  return match ? match[0] : null;
}

const arr = <T>(value: any): T[] => (Array.isArray(value) ? value : []);

// MARK: Parsing (lenient: one bad item or a null never fails the whole answer)

function parseTitle(data: any): MBTitle {
  const videos = arr<any>(data?.videos).filter((v) => v && typeof v.host === 'string');
  let youtube = 0;
  return {
    id: data?.id,
    imdbId: data?.imdbId ?? data?.externalIds?.imdb ?? null,
    title: data?.title ?? null,
    year: data?.year ?? null,
    ratings: arr<any>(data?.ratings).filter((r) => r && typeof r.provider === 'string'),
    parentalGuidance: arr<any>(data?.parentalGuidance).map((g) => ({ ...g, categories: arr(g?.categories) })),
    certifications: arr(data?.certifications),
    // Keep Apple videos, JustWatch MP4 clips (not vertical shorts), and up to 10 YouTube trailers.
    videos: videos.filter((v) => {
      if (v.host === 'apple-tv') return true;
      if (v.host === 'justwatch') return v.playback === 'direct-mp4' && v.kind !== 'vertical';
      if (v.host === 'youtube' && (v.kind === 'trailer' || v.kind === 'teaser') && youtube < 10) { youtube += 1; return true; }
      return false;
    }),
    sources: arr<any>(data?.sources).filter((s) => s && typeof s.provider === 'string')
      .map((s) => ({ provider: s.provider, status: s.status, sourceUrl: s.sourceUrl ?? null })),
  };
}

function parseScoreSet(set: any) {
  if (!set) return null;
  const scores: Record<string, number> = {};
  for (const [k, v] of Object.entries(set.scores ?? {})) if (typeof v === 'number') scores[k] = v;
  return { scale: set.scale ?? null, scores: Object.keys(scores).length ? scores : null, voteCount: set.voteCount ?? null, author: set.author ?? null, sourceUrl: set.sourceUrl ?? null };
}

function parseEdition(data: any): MBEdition {
  return {
    ...data,
    screenshots: arr<any>(data?.screenshots).filter((s) => s?.url),
    artwork: arr<any>(data?.artwork).filter((a) => a?.url),
    reviewScores: data?.reviewScores ? {
      critic: parseScoreSet(data.reviewScores.critic),
      communityReviews: parseScoreSet(data.reviewScores.communityReviews),
      communityRatings: parseScoreSet(data.reviewScores.communityRatings),
    } : null,
    digitalCopy: data?.digitalCopy ? { ...data.digitalCopy, platforms: arr(data.digitalCopy.platforms) } : null,
  };
}

// MARK: Titles

/** Ratings, Common Sense, certifications, videos and source links: one request. */
export async function getTitle(imdbId: string, allVideos = false): Promise<MBTitle | null> {
  const id = normalizedImdbId(imdbId);
  if (!id) return null;
  return cached(`${allVideos ? 'title-all-v2' : 'title-v2'}:${id}`, TTL.title, async (c) => {
    const json = await c.get(`/v2/titles/${segment(`imdb:${id}`)}`, allVideos ? { videoSelection: 'all' } : undefined);
    return parseTitle(json?.data);
  });
}

/** IMDb's parents guide; spoilers included and marked. */
export async function getParentsGuide(imdbId: string): Promise<MBParentsGuide | null> {
  const id = normalizedImdbId(imdbId);
  if (!id) return null;
  return cached(`parents-guide:${id}`, TTL.parentsGuide, async (c) => {
    const json = await c.get(`/v2/titles/${segment(`imdb:${id}`)}/parents-guide`, { spoilers: 'include' });
    const d = json?.data ?? {};
    return {
      titleId: d.titleId ?? null,
      status: d.status ?? null,
      websiteUrl: d.websiteUrl ?? null,
      certification: d.certification ?? null,
      categories: arr<any>(d.categories).map((cat) => ({ ...cat, descriptions: arr<any>(cat?.descriptions).filter((x) => x?.text) })),
    };
  });
}

// MARK: Blu-ray.com

export async function resolveMovie(imdbId: string): Promise<MBMovie | null> {
  const id = normalizedImdbId(imdbId);
  if (!id) return null;
  return cached(`movie:${id}`, TTL.movie, async (c) => (await c.get('/v2/movies/resolve', { imdbId: id }))?.data ?? null);
}

export async function getEditions(movieId: string, country?: string, formats = ['bluray', '4k']): Promise<MBEditionSummary[]> {
  const formatList = formats.join(',');
  const result = await cached(`editions:${movieId}:${country ?? 'all'}:${formatList}`, TTL.editions, async (c) => {
    const query: Record<string, string> = { category: 'bluray', formats: formatList, pageSize: '100' };
    if (country) query.country = country;
    let page = await c.get(`/v2/movies/${segment(movieId)}/editions`, query);
    let all = arr<MBEditionSummary>(page?.data).filter((e: any) => e?.id);
    let pages = 1;
    while (page?.links?.next && pages < MAX_EDITION_PAGES) {
      const next = new URL(page.links.next, 'https://x');
      const q: Record<string, string> = {};
      next.searchParams.forEach((v, k) => { q[k] = v; });
      page = await c.get(next.pathname, q);
      all = all.concat(arr<MBEditionSummary>(page?.data).filter((e: any) => e?.id));
      pages += 1;
    }
    return all;
  });
  return result ?? [];
}

export async function getEdition(id: string): Promise<MBEdition | null> {
  return cached(`edition:${id}`, TTL.edition, async (c) => parseEdition((await c.get(`/v2/editions/${segment(id)}`))?.data));
}

// MARK: Collection (Blu-ray.com login attached to the key)

function checkCollectionAvailable() {
  const until = collectionUnavailableUntil.get(keyScope(myblurayKey()));
  if (until && until > Date.now()) throw new MyBlurayError('collectionNotConnected');
}

function noteCollectionUnavailable() {
  collectionUnavailableUntil.set(keyScope(myblurayKey()), Date.now() + COLLECTION_RECHECK);
}

export function resetCollectionStatus() {
  collectionUnavailableUntil.clear();
}

async function collectionRead<T>(fn: () => Promise<T>): Promise<T> {
  checkCollectionAvailable();
  try {
    return await fn();
  } catch (error) {
    if (error instanceof MyBlurayError && error.kind === 'collectionNotConnected') noteCollectionUnavailable();
    throw error;
  }
}

export async function getCollectionLists(): Promise<MBCollectionList[]> {
  return collectionRead(async () => (await cached('collection-lists:bluray', TTL.collection, async (c) =>
    arr<MBCollectionList>((await c.get('/v2/collection/lists', { category: 'bluray' }))?.data))) ?? []);
}

export async function getCollection(): Promise<MBCollectionEntry[]> {
  return collectionRead(async () => (await cached('collection:bluray', TTL.collection, async (c) =>
    arr<MBCollectionEntry>((await c.get('/v2/collection', { category: 'bluray' }))?.data).filter((e: any) => e?.id))) ?? []);
}

function invalidateCollection() {
  const scope = keyScope(myblurayKey());
  store().remove(`${scope}|collection:bluray`);
}

export async function addToCollection(productId: string, listId: string): Promise<void> {
  try {
    await client().write('POST', '/v2/collection/items', { productId, listId });
  } finally {
    invalidateCollection();
  }
}

export async function removeFromCollection(productId: string): Promise<void> {
  try {
    await client().write('DELETE', `/v2/collection/items/${segment(productId)}`);
  } finally {
    invalidateCollection();
  }
}

// MARK: Key check

async function probe(fn: () => Promise<any>): Promise<{ ok: true; data: any } | { ok: false; error: unknown }> {
  try { return { ok: true, data: await fn() }; } catch (error) { return { ok: false, error }; }
}

function stateFor(error: unknown): AccessState {
  if (!(error instanceof MyBlurayError)) return 'unknown';
  if (error.kind === 'scopeNotAllowed' || error.kind === 'collectionNotConnected') return 'no';
  if (error.kind === 'notFound' || error.kind === 'ambiguous' || error.kind === 'unsupported') return 'yes';
  return 'unknown';
}

/**
 * Checks a key, saved or not, and what it can reach. There's no route that
 * lists a key's scopes, so this asks for The Dark Knight from each source:
 * 5 uncached requests. Throws when the key itself is refused.
 */
export async function checkKey(rawKey: string): Promise<MyBlurayAccess> {
  const c = new MyBlurayClient(rawKey.trim());
  await c.get('/v2/titles/providers');
  const id = segment(`imdb:${PROBE_IMDB}`);
  const [title, guide, movie, account] = await Promise.all([
    probe(() => c.get(`/v2/titles/${id}`)),
    probe(() => c.get(`/v2/titles/${id}/parents-guide`)),
    probe(() => c.get('/v2/movies/resolve', { imdbId: PROBE_IMDB })),
    probe(() => c.get('/v2/account')),
  ]);
  const access: MyBlurayAccess = { 'apple-tv': 'unknown', justwatch: 'unknown', letterboxd: 'unknown', imdb: 'unknown', bluray: 'unknown', collection: 'unknown' };
  if (title.ok) {
    const sources = new Set(arr<any>(title.data?.data?.sources).map((s) => s.provider));
    (['apple-tv', 'justwatch', 'letterboxd'] as const).forEach((p) => { access[p] = sources.has(p) ? 'yes' : 'no'; });
  } else {
    const s = stateFor(title.error);
    (['apple-tv', 'justwatch', 'letterboxd'] as const).forEach((p) => { access[p] = s; });
  }
  access.imdb = guide.ok ? 'yes' : stateFor(guide.error);
  access.bluray = movie.ok ? 'yes' : stateFor(movie.error);
  access.collection = account.ok ? 'yes' : stateFor(account.error);
  if (access.collection === 'yes') resetCollectionStatus();
  return access;
}

/** Forgets every saved result (Settings, or after changing the key). */
export function clearMyBlurayCache() {
  store().clearAll();
  inFlight.clear();
  resetCollectionStatus();
}

export function myblurayCacheSize(): number {
  try { return store().size ?? 0; } catch { return 0; }
}
