/** User-built collections, stored in this browser. */
import { useSyncExternalStore } from 'react';
import type { SearchDiscoverFilters } from '@/state/settings';

export type PersonCredits = 'knownFor' | 'acting' | 'directing' | 'allCrew';
export type PersonOrder = 'popularity' | 'newest' | 'oldest';

export type CollectionSourceKind =
  | { kind: 'addonCatalog'; installationId: string; addonName: string; type: string; catalogId: string; displayName: string }
  | { kind: 'tmdbDiscover'; filters: SearchDiscoverFilters; label: string }
  | { kind: 'tmdbCollection'; id: number; name: string }
  | { kind: 'person'; id: number; name: string; credits: PersonCredits; order: PersonOrder }
  | { kind: 'traktList'; id: number; name: string; owner?: string };

export type CollectionSource = CollectionSourceKind & { sourceId: string };

export interface UserCollectionCover {
  url: string;
  style: 'poster' | 'backdrop';
}

export interface UserCollection {
  id: string;
  name: string;
  cover?: UserCollectionCover;
  sources: CollectionSource[];
  /** Adds this collection as a row on Home. Off unless the user turns it on. */
  showOnHome?: boolean;
  createdAt: number;
}

const KEY = 'flixor.userCollections.v1';

let cache: { raw: string | null; value: UserCollection[] } | null = null;
const listeners = new Set<() => void>();

function read(): UserCollection[] {
  let raw: string | null = null;
  try {
    raw = localStorage.getItem(KEY);
  } catch {
    // Storage blocked: behaves as empty.
  }
  if (cache && cache.raw === raw) return cache.value;
  let value: UserCollection[] = [];
  try {
    const parsed = raw ? JSON.parse(raw) : [];
    if (Array.isArray(parsed)) value = parsed;
  } catch {
    value = [];
  }
  cache = { raw, value };
  return value;
}

function write(next: UserCollection[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    // Keep working from memory if storage is full.
  }
  listeners.forEach((listener) => listener());
}

export const getCollections = read;

export function getCollection(id: string): UserCollection | undefined {
  return read().find((collection) => collection.id === id);
}

export function saveCollection(collection: UserCollection) {
  const current = read();
  write(current.some((item) => item.id === collection.id)
    ? current.map((item) => (item.id === collection.id ? collection : item))
    : [...current, collection]);
}

export function deleteCollection(id: string) {
  write(read().filter((collection) => collection.id !== id));
}

export function newCollection(): UserCollection {
  return { id: crypto.randomUUID(), name: '', sources: [], createdAt: Date.now() };
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  const onStorage = (event: StorageEvent) => {
    if (event.key === KEY) listener();
  };
  window.addEventListener('storage', onStorage);
  return () => {
    listeners.delete(listener);
    window.removeEventListener('storage', onStorage);
  };
}

export function useCollections(): UserCollection[] {
  return useSyncExternalStore(subscribe, read, read);
}
