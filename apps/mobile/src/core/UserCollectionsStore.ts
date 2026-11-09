/**
 * Collections the user builds from one or more sources (addon catalog, TMDB discover
 * query, TMDB movie collection, a person's credits, a Trakt list). Stored per profile.
 * macOS reference: Models/UserCollection.swift, Services/UserCollectionsStore.swift
 *
 * Public API used by other screens, kept stable:
 *
 *   useUserCollections()           every collection, re-renders on change
 *   useHomeCollections()           collections with a Home row
 *   getHomeCollections()           same, outside React
 *   getUserCollection(id)
 *   userCollectionHomeRowId(c)     stable Home row id
 *   userCollectionContentKey(c)    changes only when the sources change
 *   fetchUserCollectionPreview(c)  first items for a row, cached
 *   userCollectionItemRoute(item)  params for navigate('Details', ...)
 *   navigate('UserCollection', { collectionId, title })
 */

import { useEffect, useSyncExternalStore } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { getCurrentProfile, getProfileKey } from './ProfileStorage';
import { addSettingsListener } from './SettingsData';

export {
  fetchUserCollectionPreview,
  fetchUserCollectionSourcePage,
  getCachedUserCollectionPreview,
  userCollectionItemRoute,
} from './UserCollectionResolver';
export type {
  UserCollectionItem,
  UserCollectionPreview,
  UserCollectionPreviewFailure,
  UserCollectionSourcePage,
} from './UserCollectionResolver';

const STORAGE_KEY = 'flixor_user_collections';

export type UserCollectionCoverStyle = 'poster' | 'backdrop';

export interface UserCollectionCover {
  url: string;
  style: UserCollectionCoverStyle;
}

export interface AddonCatalogSource {
  id: string;
  kind: 'addonCatalog';
  installationId: string;
  addonId: string;
  addonName: string;
  /** Stremio content type, e.g. `movie` or `series`. */
  type: string;
  catalogId: string;
  displayName: string;
}

export type CollectionDiscoverSort = 'popularity' | 'rating' | 'newest' | 'oldest' | 'voteCount' | 'revenue';

export interface TmdbDiscoverSource {
  id: string;
  kind: 'tmdbDiscover';
  mediaType: 'movie' | 'tv';
  genreIds: number[];
  genreNames: string[];
  companyId?: number;
  companyName?: string;
  networkId?: number;
  networkName?: string;
  yearFrom?: number;
  yearTo?: number;
  sort: CollectionDiscoverSort;
}

export interface TmdbCollectionSource {
  id: string;
  kind: 'tmdbCollection';
  collectionId: number;
  name: string;
  posterPath?: string;
}

export type PersonCreditsFilter = 'knownFor' | 'acting' | 'directing' | 'allCrew';
export type PersonCreditsOrder = 'popularity' | 'newest' | 'oldest';

export interface PersonSource {
  id: string;
  kind: 'person';
  personId: number;
  name: string;
  profilePath?: string;
  credits: PersonCreditsFilter;
  order: PersonCreditsOrder;
}

export interface TraktListSource {
  id: string;
  kind: 'traktList';
  listId: number;
  name: string;
  owner?: string;
}

export type UserCollectionSource =
  | AddonCatalogSource
  | TmdbDiscoverSource
  | TmdbCollectionSource
  | PersonSource
  | TraktListSource;

export type UserCollectionSourceKind = UserCollectionSource['kind'];

export interface UserCollection {
  id: string;
  name: string;
  cover?: UserCollectionCover;
  sources: UserCollectionSource[];
  showOnHome: boolean;
  /** Epoch milliseconds. */
  createdAt: number;
}

export const SOURCE_KIND_LABELS: Record<UserCollectionSourceKind, string> = {
  addonCatalog: 'Addon catalog',
  tmdbDiscover: 'TMDB discover',
  tmdbCollection: 'TMDB movie collection',
  person: "Person's credits",
  traktList: 'Trakt list',
};

export const PERSON_CREDITS_LABELS: Record<PersonCreditsFilter, string> = {
  knownFor: 'Known for',
  acting: 'Acting',
  directing: 'Directing',
  allCrew: 'All crew work',
};

export const PERSON_ORDER_LABELS: Record<PersonCreditsOrder, string> = {
  popularity: 'Most popular',
  newest: 'Newest first',
  oldest: 'Oldest first',
};

export const DISCOVER_SORT_LABELS: Record<CollectionDiscoverSort, string> = {
  popularity: 'Most popular',
  rating: 'Highest rated',
  newest: 'Newest first',
  oldest: 'Oldest first',
  voteCount: 'Most votes',
  revenue: 'Highest revenue',
};

export function createUserCollectionId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

export function createUserCollection(): UserCollection {
  return { id: createUserCollectionId(), name: '', sources: [], showOnHome: false, createdAt: Date.now() };
}

/** Stable id of a collection's row in the Home row system. */
export function userCollectionHomeRowId(collection: Pick<UserCollection, 'id'>): string {
  return `user-collection-${collection.id}`;
}

/** Changes only when what the collection shows changes. Ignores source ids. */
export function userCollectionContentKey(collection: Pick<UserCollection, 'sources'>): string {
  return JSON.stringify(collection.sources.map(({ id: _id, ...rest }) => rest));
}

export function userCollectionSummary(collection: Pick<UserCollection, 'sources'>): string {
  const count = collection.sources.length;
  return count === 1 ? '1 source' : `${count} sources`;
}

export function sourceTitle(source: UserCollectionSource): string {
  switch (source.kind) {
    case 'addonCatalog':
      return source.displayName;
    case 'tmdbDiscover': {
      const media = source.mediaType === 'movie' ? 'Movies' : 'TV shows';
      return source.genreNames.length > 0
        ? `${source.genreNames.join(', ')} ${media.toLowerCase()}`
        : media;
    }
    case 'tmdbCollection':
    case 'person':
    case 'traktList':
      return source.name;
  }
}

export function sourceSubtitle(source: UserCollectionSource): string {
  switch (source.kind) {
    case 'addonCatalog':
      return source.addonName;
    case 'tmdbDiscover': {
      const parts: string[] = [];
      if (source.companyName) parts.push(source.companyName);
      if (source.networkName) parts.push(source.networkName);
      const { yearFrom: from, yearTo: to } = source;
      if (from != null && to != null) parts.push(from === to ? String(from) : `${from} to ${to}`);
      else if (from != null) parts.push(`From ${from}`);
      else if (to != null) parts.push(`Up to ${to}`);
      parts.push(DISCOVER_SORT_LABELS[source.sort]);
      return parts.join(' · ');
    }
    case 'tmdbCollection':
      return SOURCE_KIND_LABELS.tmdbCollection;
    case 'person':
      return `${PERSON_CREDITS_LABELS[source.credits]}, ${PERSON_ORDER_LABELS[source.order].toLowerCase()}`;
    case 'traktList':
      return source.owner ? `Trakt list by ${source.owner}` : SOURCE_KIND_LABELS.traktList;
  }
}

// ============================================
// Decoding
// ============================================

const isString = (value: unknown): value is string => typeof value === 'string';
const isNumber = (value: unknown): value is number => typeof value === 'number' && Number.isFinite(value);
const numberOrUndefined = (value: unknown) => (isNumber(value) ? value : undefined);
const stringOrUndefined = (value: unknown) => (isString(value) && value ? value : undefined);

function oneOf<T extends string>(value: unknown, allowed: readonly T[], fallback: T): T {
  return allowed.includes(value as T) ? (value as T) : fallback;
}

const SORTS: readonly CollectionDiscoverSort[] = ['popularity', 'rating', 'newest', 'oldest', 'voteCount', 'revenue'];
const CREDITS: readonly PersonCreditsFilter[] = ['knownFor', 'acting', 'directing', 'allCrew'];
const ORDERS: readonly PersonCreditsOrder[] = ['popularity', 'newest', 'oldest'];

/** Returns null for a source that can't be read, so the rest of the collection survives. */
function decodeSource(raw: any): UserCollectionSource | null {
  if (!raw || typeof raw !== 'object') return null;
  const id = isString(raw.id) && raw.id ? raw.id : createUserCollectionId();
  switch (raw.kind) {
    case 'addonCatalog':
      if (!isString(raw.installationId) || !isString(raw.addonId) || !isString(raw.type) || !isString(raw.catalogId)) {
        return null;
      }
      return {
        id,
        kind: 'addonCatalog',
        installationId: raw.installationId,
        addonId: raw.addonId,
        addonName: isString(raw.addonName) ? raw.addonName : '',
        type: raw.type,
        catalogId: raw.catalogId,
        displayName: isString(raw.displayName) ? raw.displayName : raw.catalogId,
      };
    case 'tmdbDiscover':
      return {
        id,
        kind: 'tmdbDiscover',
        mediaType: oneOf(raw.mediaType, ['movie', 'tv'] as const, 'movie'),
        genreIds: Array.isArray(raw.genreIds) ? raw.genreIds.filter(isNumber) : [],
        genreNames: Array.isArray(raw.genreNames) ? raw.genreNames.filter(isString) : [],
        companyId: numberOrUndefined(raw.companyId),
        companyName: stringOrUndefined(raw.companyName),
        networkId: numberOrUndefined(raw.networkId),
        networkName: stringOrUndefined(raw.networkName),
        yearFrom: numberOrUndefined(raw.yearFrom),
        yearTo: numberOrUndefined(raw.yearTo),
        sort: oneOf(raw.sort, SORTS, 'popularity'),
      };
    case 'tmdbCollection':
      if (!isNumber(raw.collectionId) || !isString(raw.name)) return null;
      return {
        id,
        kind: 'tmdbCollection',
        collectionId: raw.collectionId,
        name: raw.name,
        posterPath: stringOrUndefined(raw.posterPath),
      };
    case 'person':
      if (!isNumber(raw.personId) || !isString(raw.name)) return null;
      return {
        id,
        kind: 'person',
        personId: raw.personId,
        name: raw.name,
        profilePath: stringOrUndefined(raw.profilePath),
        credits: oneOf(raw.credits, CREDITS, 'knownFor'),
        order: oneOf(raw.order, ORDERS, 'popularity'),
      };
    case 'traktList':
      if (!isNumber(raw.listId) || !isString(raw.name)) return null;
      return { id, kind: 'traktList', listId: raw.listId, name: raw.name, owner: stringOrUndefined(raw.owner) };
    default:
      return null;
  }
}

function decodeCollection(raw: any): UserCollection | null {
  if (!raw || typeof raw !== 'object' || !isString(raw.id) || !isString(raw.name)) return null;
  const sources = Array.isArray(raw.sources)
    ? raw.sources.map(decodeSource).filter((s: UserCollectionSource | null): s is UserCollectionSource => s !== null)
    : [];
  const cover: UserCollectionCover | undefined =
    raw.cover && isString(raw.cover.url)
      ? { url: raw.cover.url, style: oneOf(raw.cover.style, ['poster', 'backdrop'] as const, 'poster') }
      : undefined;
  return {
    id: raw.id,
    name: raw.name,
    cover,
    sources,
    showOnHome: raw.showOnHome === true,
    createdAt: isNumber(raw.createdAt) ? raw.createdAt : Date.now(),
  };
}

// ============================================
// Store
// ============================================

interface StoreState {
  collections: UserCollection[];
  home: UserCollection[];
  isLoaded: boolean;
}

function buildState(collections: UserCollection[], isLoaded: boolean): StoreState {
  return {
    collections,
    home: collections.filter((c) => c.showOnHome && c.sources.length > 0),
    isLoaded,
  };
}

let state: StoreState = buildState([], false);
/** Profile the in-memory list belongs to. `undefined` until the first load. */
let loadedProfile: string | null | undefined;
let loading: Promise<UserCollection[]> | null = null;
let settingsUnsubscribe: (() => void) | null = null;
const listeners = new Set<() => void>();

function publish(next: StoreState): void {
  state = next;
  listeners.forEach((listener) => listener());
}

export function addUserCollectionsListener(listener: () => void): () => void {
  listeners.add(listener);
  // Settings reload on a profile switch, which is when this list has to follow.
  if (!settingsUnsubscribe) {
    settingsUnsubscribe = addSettingsListener(() => {
      if (loadedProfile !== undefined && loadedProfile !== getCurrentProfile()) {
        void loadUserCollections();
      }
    });
  }
  return () => {
    listeners.delete(listener);
  };
}

/** Reads the current profile's collections. Concurrent callers share one read. */
export function loadUserCollections(): Promise<UserCollection[]> {
  const profile = getCurrentProfile();
  if (loading && loadedProfile === profile) return loading;
  loadedProfile = profile;

  const work: Promise<UserCollection[]> = (async () => {
    let collections: UserCollection[] = [];
    try {
      const raw = await AsyncStorage.getItem(getProfileKey(STORAGE_KEY));
      const parsed = raw ? JSON.parse(raw) : [];
      if (Array.isArray(parsed)) {
        collections = parsed
          .map(decodeCollection)
          .filter((c: UserCollection | null): c is UserCollection => c !== null);
      }
    } catch (e) {
      console.log('[UserCollectionsStore] load error:', e);
    }
    // A newer switch has taken over; its load publishes instead.
    if (loadedProfile === profile) publish(buildState(collections, true));
    return collections;
  })();

  loading = work;
  work.finally(() => {
    if (loading === work) loading = null;
  });
  return work;
}

async function ensureCurrent(): Promise<void> {
  if (!state.isLoaded || loadedProfile !== getCurrentProfile()) {
    await loadUserCollections();
  } else if (loading) {
    await loading;
  }
}

async function apply(next: UserCollection[]): Promise<void> {
  publish(buildState(next, true));
  try {
    await AsyncStorage.setItem(getProfileKey(STORAGE_KEY), JSON.stringify(next));
  } catch (e) {
    console.log('[UserCollectionsStore] save error:', e);
    throw e;
  }
}

export function getUserCollections(): UserCollection[] {
  return state.collections;
}

export function getHomeCollections(): UserCollection[] {
  return state.home;
}

export function getUserCollection(id: string): UserCollection | undefined {
  return state.collections.find((c) => c.id === id);
}

export function isUserCollectionsLoaded(): boolean {
  return state.isLoaded;
}

/** Adds a new collection or replaces the one with the same id. */
export async function saveUserCollection(collection: UserCollection): Promise<void> {
  await ensureCurrent();
  const exists = state.collections.some((c) => c.id === collection.id);
  await apply(
    exists
      ? state.collections.map((c) => (c.id === collection.id ? collection : c))
      : [...state.collections, collection]
  );
}

export async function deleteUserCollection(id: string): Promise<void> {
  await ensureCurrent();
  if (!state.collections.some((c) => c.id === id)) return;
  await apply(state.collections.filter((c) => c.id !== id));
}

export async function setUserCollectionShowOnHome(id: string, showOnHome: boolean): Promise<void> {
  await ensureCurrent();
  const collection = state.collections.find((c) => c.id === id);
  if (!collection || collection.showOnHome === showOnHome) return;
  await apply(state.collections.map((c) => (c.id === id ? { ...c, showOnHome } : c)));
}

function getState(): StoreState {
  return state;
}

function useStoreState(): StoreState {
  const current = useSyncExternalStore(addUserCollectionsListener, getState, getState);
  useEffect(() => {
    if (!state.isLoaded || loadedProfile !== getCurrentProfile()) void loadUserCollections();
  }, []);
  return current;
}

export function useUserCollections(): { collections: UserCollection[]; isLoaded: boolean } {
  const { collections, isLoaded } = useStoreState();
  return { collections, isLoaded };
}

export function useHomeCollections(): UserCollection[] {
  return useStoreState().home;
}

export function useUserCollection(id: string | undefined): UserCollection | undefined {
  const { collections } = useStoreState();
  return id ? collections.find((c) => c.id === id) : undefined;
}
