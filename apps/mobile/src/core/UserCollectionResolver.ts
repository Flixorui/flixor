/**
 * Fetches pages of a user collection's sources and merges them without duplicates.
 * Every request here happens because a collection is on screen or being previewed.
 * macOS reference: Services/UserCollectionSourceResolver.swift
 */

import { getFlixorCore } from './index';
import { fetchCatalogPage, getBrowsableCatalogs, mapCatalogMetas } from './AddonCatalogs';
import type {
  AddonCatalogSource,
  PersonSource,
  TmdbDiscoverSource,
  TraktListSource,
  UserCollection,
  UserCollectionSource,
} from './UserCollectionsStore';

export interface UserCollectionItem {
  /** `tmdb:movie:123` or `tmdb:tv:123`. */
  id: string;
  title: string;
  type: 'movie' | 'show';
  image?: string;
  backdrop?: string;
  year?: string;
  tmdbId: number;
}

export interface UserCollectionSourcePage {
  items: UserCollectionItem[];
  /** Pass back as `cursor` for the next page. Undefined when there is no more. */
  nextCursor?: number;
  /** Total titles, when the source reports one. */
  totalResults?: number;
}

export interface UserCollectionPreviewFailure {
  sourceId: string;
  sourceTitle: string;
  message: string;
}

export interface UserCollectionPreview {
  items: UserCollectionItem[];
  failures: UserCollectionPreviewFailure[];
}

const ADDON_PAGE_SIZE = 50;
const PREVIEW_LIMIT = 40;
/** Keeps a collection of several Trakt lists from flooding TMDB. */
const LOOKUP_BATCH_SIZE = 10;

function capped<T>(items: T[], limit?: number): T[] {
  return limit != null ? items.slice(0, limit) : items;
}

/** Params for `navigate('Details', ...)`. */
export function userCollectionItemRoute(item: Pick<UserCollectionItem, 'type' | 'tmdbId'>) {
  return { type: 'tmdb' as const, mediaType: item.type === 'movie' ? 'movie' : 'tv', id: String(item.tmdbId) };
}

function mapTmdb(raw: any, mediaType: 'movie' | 'tv'): UserCollectionItem {
  const tmdb = getFlixorCore().tmdb;
  const date: string | undefined = mediaType === 'movie' ? raw.release_date : raw.first_air_date;
  return {
    id: `tmdb:${mediaType}:${raw.id}`,
    title: mediaType === 'movie' ? raw.title ?? raw.name ?? '' : raw.name ?? raw.title ?? '',
    type: mediaType === 'movie' ? 'movie' : 'show',
    image: raw.poster_path ? tmdb.getPosterUrl(raw.poster_path, 'w342') : undefined,
    backdrop: raw.backdrop_path ? tmdb.getBackdropUrl(raw.backdrop_path, 'w780') : undefined,
    year: date ? date.slice(0, 4) : undefined,
    tmdbId: raw.id,
  };
}

function todayString(): string {
  return new Date().toISOString().slice(0, 10);
}

function discoverSortBy(source: TmdbDiscoverSource): string {
  const dateField = source.mediaType === 'movie' ? 'primary_release_date' : 'first_air_date';
  switch (source.sort) {
    case 'rating':
      return 'vote_average.desc';
    case 'newest':
      return `${dateField}.desc`;
    case 'oldest':
      return `${dateField}.asc`;
    case 'voteCount':
      return 'vote_count.desc';
    case 'revenue':
      return source.mediaType === 'movie' ? 'revenue.desc' : 'popularity.desc';
    default:
      return 'popularity.desc';
  }
}

async function fetchDiscover(
  source: TmdbDiscoverSource,
  page: number,
  limit?: number
): Promise<UserCollectionSourcePage> {
  const tmdb = getFlixorCore().tmdb;
  const options = {
    page,
    sortBy: discoverSortBy(source),
    withGenres: source.genreIds.length > 0 ? source.genreIds.join(',') : undefined,
    withCompanies: source.companyId != null ? String(source.companyId) : undefined,
    dateFrom: source.yearFrom != null ? `${source.yearFrom}-01-01` : undefined,
    // Sorting by date with no upper bound surfaces unreleased placeholders.
    dateTo:
      source.yearTo != null ? `${source.yearTo}-12-31` : source.sort === 'newest' ? todayString() : undefined,
    minVoteCount: source.sort === 'rating' ? 200 : undefined,
  };
  const response =
    source.mediaType === 'movie'
      ? await tmdb.discoverMovies(options)
      : await tmdb.discoverTV({
          ...options,
          withNetworks: source.networkId != null ? String(source.networkId) : undefined,
        });
  return {
    items: capped(response.results ?? [], limit).map((r) => mapTmdb(r, source.mediaType)),
    nextCursor: page < Math.min(response.total_pages ?? page, 500) ? page + 1 : undefined,
    totalResults: response.total_results,
  };
}

async function fetchAddon(source: AddonCatalogSource, skip: number, limit: number): Promise<UserCollectionSourcePage> {
  // Match by installation first, then by addon id so a reinstall keeps working.
  const catalogs = await getBrowsableCatalogs();
  const matches = catalogs.filter((c) => c.type === source.type && c.catalogId === source.catalogId);
  const entry =
    matches.find((c) => c.installationId === source.installationId) ??
    matches.find((c) => c.addonId === source.addonId);
  if (!entry) {
    throw new Error(`${source.addonName || 'This addon'} isn't installed any more, or no longer offers this catalog.`);
  }
  const metas = await fetchCatalogPage(
    entry.installationId,
    source.type,
    source.catalogId,
    skip > 0 ? { skip: String(skip) } : {},
    limit
  );
  return {
    items: await mapCatalogMetas(metas),
    nextCursor: entry.supportsSkip && metas.length > 0 ? skip + metas.length : undefined,
  };
}

function creditTime(credit: any): number {
  const date = credit.release_date || credit.first_air_date;
  const time = date ? Date.parse(date) : NaN;
  return Number.isNaN(time) ? 0 : time;
}

function selectCredits(cast: any[], crew: any[], person: PersonSource, department?: string): any[] {
  let credits: any[];
  switch (person.credits) {
    case 'acting':
      credits = cast;
      break;
    case 'directing':
      credits = crew.filter((c) => c.job === 'Director');
      break;
    case 'allCrew':
      credits = crew;
      break;
    default:
      // Actors are known for their roles, everyone else for their department's work.
      credits = !department || department === 'Acting' ? cast : crew.filter((c) => c.department === department);
      if (credits.length === 0) credits = cast.length > 0 ? cast : crew;
      break;
  }
  const seen = new Set<string>();
  const unique = credits.filter((c) => {
    const key = `${c.media_type}:${c.id}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return c.poster_path && (c.media_type === 'movie' || c.media_type === 'tv');
  });
  return [...unique].sort((a, b) => {
    if (person.order === 'newest') return creditTime(b) - creditTime(a);
    if (person.order === 'oldest') return creditTime(a) - creditTime(b);
    return (b.popularity ?? 0) - (a.popularity ?? 0);
  });
}

async function fetchPerson(source: PersonSource, limit?: number): Promise<UserCollectionSourcePage> {
  const tmdb = getFlixorCore().tmdb;
  const [credits, details] = await Promise.all([
    tmdb.getPersonCredits(source.personId),
    source.credits === 'knownFor' ? tmdb.getPersonDetails(source.personId).catch(() => null) : null,
  ]);
  const selected = selectCredits(credits.cast ?? [], credits.crew ?? [], source, details?.known_for_department);
  return { items: capped(selected, limit).map((c) => mapTmdb(c, c.media_type)) };
}

async function fetchTraktList(source: TraktListSource, limit?: number): Promise<UserCollectionSourcePage> {
  const core = getFlixorCore();
  if (!core.isTraktAuthenticated) {
    throw new Error('Connect Trakt in Settings to load this list.');
  }
  const entries = await core.trakt.getListItems(source.listId);
  const titled = entries.filter((e) => (e.movie?.ids?.tmdb ?? e.show?.ids?.tmdb) != null && (e.movie || e.show));
  const selected = capped(titled, limit);
  const items: UserCollectionItem[] = [];
  for (let start = 0; start < selected.length; start += LOOKUP_BATCH_SIZE) {
    const batch = await Promise.all(
      selected.slice(start, start + LOOKUP_BATCH_SIZE).map(async (entry) => {
        const isMovie = !!entry.movie;
        const media = (entry.movie ?? entry.show)!;
        const tmdbId = media.ids.tmdb as number;
        const mediaType = isMovie ? ('movie' as const) : ('tv' as const);
        let poster: string | null | undefined;
        let backdrop: string | null | undefined;
        try {
          const details = isMovie ? await core.tmdb.getMovieDetails(tmdbId) : await core.tmdb.getTVDetails(tmdbId);
          poster = details.poster_path;
          backdrop = details.backdrop_path;
        } catch {
          // The title still shows, just without artwork.
        }
        return {
          id: `tmdb:${mediaType}:${tmdbId}`,
          title: media.title ?? '',
          type: isMovie ? ('movie' as const) : ('show' as const),
          image: poster ? core.tmdb.getPosterUrl(poster, 'w342') : undefined,
          backdrop: backdrop ? core.tmdb.getBackdropUrl(backdrop, 'w780') : undefined,
          year: media.year != null ? String(media.year) : undefined,
          tmdbId,
        };
      })
    );
    items.push(...batch);
  }
  return { items };
}

/** One page of one source. `limit` caps items for short lists like Home rows. */
export async function fetchUserCollectionSourcePage(
  source: UserCollectionSource,
  cursor?: number,
  limit?: number
): Promise<UserCollectionSourcePage> {
  switch (source.kind) {
    case 'addonCatalog':
      return fetchAddon(source, cursor ?? 0, limit ?? ADDON_PAGE_SIZE);
    case 'tmdbDiscover':
      return fetchDiscover(source, cursor ?? 1, limit);
    case 'tmdbCollection': {
      const details = await getFlixorCore().tmdb.getCollectionDetails(source.collectionId);
      return { items: capped(details.parts ?? [], limit).map((p) => mapTmdb(p, 'movie')) };
    }
    case 'person':
      return fetchPerson(source, limit);
    case 'traktList':
      return fetchTraktList(source, limit);
  }
}

export function userCollectionSourceErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : '';
  if (/\b404\b/.test(message)) return 'This list is private or no longer exists.';
  if (/\b429\b/.test(message)) return 'Rate limit reached. Try again in a moment.';
  return message || "This source couldn't be loaded.";
}

// ============================================
// De-duplication
// ============================================

/** Keeps one copy of each title across sources. */
export class UserCollectionDeduper {
  private ids = new Set<string>();

  /** True the first time a title is seen. */
  insert(item: UserCollectionItem): boolean {
    if (this.ids.has(item.id)) return false;
    this.ids.add(item.id);
    return true;
  }
}

// ============================================
// First-page cache
// ============================================

const PREVIEW_TTL_MS = 30 * 60 * 1000;
/** Failures are retried sooner than good results expire. */
const FAILURE_TTL_MS = 2 * 60 * 1000;

const previewEntries = new Map<string, { preview: UserCollectionPreview; expires: number }>();
const previewLoads = new Map<string, Promise<UserCollectionPreview>>();

function previewKey(collection: Pick<UserCollection, 'sources'>): string {
  return JSON.stringify(collection.sources.map(({ id: _id, ...rest }) => rest));
}

/** A cached preview, if any. Never touches the network. */
export function getCachedUserCollectionPreview(
  collection: Pick<UserCollection, 'sources'>
): UserCollectionPreview | undefined {
  return previewEntries.get(previewKey(collection))?.preview;
}

async function loadPreview(sources: UserCollectionSource[]): Promise<UserCollectionPreview> {
  const perSource = sources.length === 1 ? 20 : Math.max(10, Math.floor(30 / sources.length));
  const settled = await Promise.allSettled(
    sources.map((source) => fetchUserCollectionSourcePage(source, undefined, perSource))
  );

  const failures: UserCollectionPreviewFailure[] = [];
  const lists: UserCollectionItem[][] = [];
  settled.forEach((result, index) => {
    if (result.status === 'fulfilled') {
      lists.push(result.value.items);
    } else {
      const source = sources[index];
      failures.push({
        sourceId: source.id,
        sourceTitle: source.kind === 'addonCatalog' ? source.displayName : source.kind === 'tmdbDiscover' ? 'TMDB discover' : source.name,
        message: userCollectionSourceErrorMessage(result.reason),
      });
    }
  });

  // Interleaved so every source is represented.
  const deduper = new UserCollectionDeduper();
  const merged: UserCollectionItem[] = [];
  const longest = lists.reduce((max, list) => Math.max(max, list.length), 0);
  for (let position = 0; position < longest; position += 1) {
    for (const list of lists) {
      if (position < list.length && deduper.insert(list[position])) merged.push(list[position]);
    }
  }
  return { items: merged.slice(0, PREVIEW_LIMIT), failures };
}

/** First items of a collection, for Home rows and the cover picker. Concurrent callers share one load. */
export async function fetchUserCollectionPreview(
  collection: Pick<UserCollection, 'sources'>,
  options?: { forceRefresh?: boolean }
): Promise<UserCollectionPreview> {
  const key = previewKey(collection);
  const entry = previewEntries.get(key);
  if (!options?.forceRefresh && entry && entry.expires > Date.now()) return entry.preview;

  const running = previewLoads.get(key);
  if (running) return running;

  const load = loadPreview(collection.sources).then((preview) => {
    previewEntries.set(key, {
      preview,
      expires: Date.now() + (preview.failures.length === 0 ? PREVIEW_TTL_MS : FAILURE_TTL_MS),
    });
    previewLoads.delete(key);
    return preview;
  });
  previewLoads.set(key, load);
  return load;
}
