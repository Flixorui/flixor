/**
 * The one record of which list each disc is in, so Details, the edition page
 * and Library → Physical always agree after a change. Port of macOS
 * PhysicalCollectionStore (Views/Library/PhysicalCollectionView.swift).
 */
import { useSyncExternalStore } from 'react';
import { MyBlurayError, myblurayErrorMessage } from './client';
import { isMyBlurayOn } from './options';
import { addToCollection, getCollection, getCollectionLists, removeFromCollection } from './service';
import type { MBCollectionEntry, MBCollectionList, MBEditionSummary, MBListRef } from './types';

export type CollectionPhase = 'idle' | 'loading' | 'loaded' | 'notConnected' | 'failed';
export type CollectionSort = 'added' | 'title' | 'release';
export type FormatFilter = 'all' | 'uhd' | 'bluray';

export const SORT_TITLES: Record<CollectionSort, string> = { added: 'Newest added', title: 'Title', release: 'Newest release' };
export const FORMAT_TITLES: Record<FormatFilter, string> = { all: 'All formats', uhd: '4K', bluray: 'Blu-ray' };
export const OWNED_LIST_ID = 'bluray:1';

interface State {
  phase: CollectionPhase;
  error?: string;
  entries: MBCollectionEntry[];
  lists: MBCollectionList[];
  /** Product id → the list it's in. */
  listFor: Record<string, MBListRef>;
  /** Result of the last add or remove, shown briefly where it happened. */
  message?: string;
  // Library tab filters, shared by the header and the grid
  listFilter: string | null;
  query: string;
  sort: CollectionSort;
  format: FormatFilter;
}

let state: State = {
  phase: 'idle',
  entries: [],
  lists: [],
  listFor: {},
  listFilter: OWNED_LIST_ID,
  query: '',
  sort: 'added',
  format: 'all',
};
const listeners = new Set<() => void>();
let messageTimer: ReturnType<typeof setTimeout> | null = null;

function set(patch: Partial<State>) {
  state = { ...state, ...patch };
  if (patch.entries) {
    const map: Record<string, MBListRef> = {};
    for (const e of state.entries) if (e.list) map[e.id] = e.list;
    state.listFor = map;
  }
  listeners.forEach((l) => l());
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function useCollectionStore(): State {
  return useSyncExternalStore(subscribe, () => state);
}

export function getCollectionState(): State {
  return state;
}

export function setCollectionFilters(patch: Partial<Pick<State, 'listFilter' | 'query' | 'sort' | 'format'>>) {
  set(patch);
}

function flash(message: string, keep = false) {
  if (messageTimer) clearTimeout(messageTimer);
  set({ message });
  if (!keep) messageTimer = setTimeout(() => set({ message: undefined }), 2600);
}

/** Loads the collection (the service caches it for 5 minutes). */
export async function loadCollection(force = false): Promise<void> {
  if (state.phase === 'loading') return;
  if (!force && (state.phase === 'loaded' || state.phase === 'notConnected')) return;
  if (!isMyBlurayOn('librarySection') && !isMyBlurayOn('quickAdd')) {
    set({ phase: 'idle' });
    return;
  }
  if (!state.entries.length) set({ phase: 'loading' });
  try {
    const [lists, entries] = await Promise.all([getCollectionLists(), getCollection()]);
    set({
      lists: [...lists].sort((a, b) => (a.displayOrder ?? 0) - (b.displayOrder ?? 0)),
      entries,
      phase: 'loaded',
      error: undefined,
    });
  } catch (error) {
    if (error instanceof MyBlurayError && error.kind === 'collectionNotConnected') set({ phase: 'notConnected' });
    else if (!state.entries.length) set({ phase: 'failed', error: myblurayErrorMessage(error) });
    else set({ phase: 'loaded' });
  }
}

/** Forget everything (a new key, MyBluray turned off). */
export function resetCollectionStore() {
  set({ phase: 'idle', entries: [], lists: [], error: undefined, message: undefined });
}

export async function addEdition(edition: MBEditionSummary, list: MBCollectionList): Promise<void> {
  const done = `Added to ${list.name ?? 'your collection'}.`;
  flash('Saving…', true);
  try {
    await addToCollection(edition.id, list.id);
    setLocally(edition, { id: list.id, alias: list.alias, name: list.name });
    flash(done);
  } catch (error) {
    // MyBluray can save a change and still answer with an error (a 502 after
    // the write), so check the collection before saying it failed.
    await loadCollection(true);
    flash(state.listFor[edition.id]?.id === list.id ? done : myblurayErrorMessage(error));
  }
}

export async function removeEdition(edition: MBEditionSummary): Promise<void> {
  const done = 'Removed from your collection.';
  flash('Saving…', true);
  try {
    await removeFromCollection(edition.id);
    set({ entries: state.entries.filter((e) => e.id !== edition.id) });
    flash(done);
  } catch (error) {
    await loadCollection(true);
    flash(!state.listFor[edition.id] && state.phase === 'loaded' ? done : myblurayErrorMessage(error));
  }
}

function setLocally(edition: MBEditionSummary, list: MBListRef) {
  const entry: MBCollectionEntry = {
    id: edition.id,
    title: edition.title,
    year: edition.year,
    country: edition.country,
    coverImage: edition.coverImage,
    releaseDate: edition.releaseDate,
    format: edition.format,
    bundle: edition.bundle,
    list,
    addedAt: new Date().toISOString(),
  };
  const index = state.entries.findIndex((e) => e.id === edition.id);
  const entries = [...state.entries];
  if (index >= 0) entries[index] = entry;
  else entries.push(entry);
  set({ entries });
}

/** `format` is often null on collection entries: a "4K" in the title counts. */
export function isUHD(e: { format?: string | null; title?: string | null }): boolean {
  if (e.format) return e.format.toLowerCase() === '4k';
  return /\b4K\b/i.test(e.title ?? '');
}

/** Lists that hold at least one disc, in Blu-ray.com's order, with counts. */
export function listsInUse(s: State): { list: MBCollectionList; count: number }[] {
  const counts: Record<string, number> = {};
  for (const e of s.entries) if (e.list?.id) counts[e.list.id] = (counts[e.list.id] ?? 0) + 1;
  return s.lists.filter((l) => counts[l.id]).map((list) => ({ list, count: counts[list.id] }));
}

export function shownEntries(s: State): MBCollectionEntry[] {
  let items = s.entries;
  if (s.listFilter) items = items.filter((e) => e.list?.id === s.listFilter);
  if (s.format === 'uhd') items = items.filter(isUHD);
  if (s.format === 'bluray') items = items.filter((e) => !isUHD(e));
  const q = s.query.trim().toLowerCase();
  if (q) items = items.filter((e) => (e.title ?? '').toLowerCase().includes(q));
  const sorted = [...items];
  if (s.sort === 'added') sorted.sort((a, b) => (b.addedAt ?? '').localeCompare(a.addedAt ?? ''));
  if (s.sort === 'title') sorted.sort((a, b) => (a.title ?? '').localeCompare(b.title ?? '', undefined, { numeric: true, sensitivity: 'base' }));
  if (s.sort === 'release') sorted.sort((a, b) => (b.releaseDate ?? '').localeCompare(a.releaseDate ?? ''));
  return sorted;
}
