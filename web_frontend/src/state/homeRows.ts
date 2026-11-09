/**
 * Home screen customisation: which rows exist, their order, custom titles and
 * hidden rows. Order, titles and hidden rows live in app settings; the list of
 * known rows is kept here so Rows Settings can show it before Home has loaded.
 */
import { useSyncExternalStore } from 'react';
import { getSettings, saveSettings } from '@/state/settings';

export type HomeRowKind =
  | 'continueWatching'
  | 'recentlyAdded'
  | 'collection'
  | 'watchlist'
  | 'discovery'
  | 'genre'
  | 'trakt'
  | 'stremioCatalog';

/** Which loader produced a row. A group's rows are replaced together. */
export type HomeRowGroup = 'continueWatching' | 'recentlyAdded' | 'collections' | 'extras';

export interface HomeRowDescriptor {
  /** Stable id, for example `recently-added-3`. */
  id: string;
  /** Title the app gives the row, before any rename. */
  defaultTitle: string;
  kind: HomeRowKind;
  group: HomeRowGroup;
  /** Source shown as a secondary line in settings, for example the addon name. */
  detail?: string;
}

export const CONTINUE_WATCHING_ROW_ID = 'continue-watching';
export const WATCHLIST_ROW_ID = 'combined-watchlist';

export const HOME_ROW_KIND_LABEL: Record<HomeRowKind, string> = {
  continueWatching: 'Continue Watching',
  recentlyAdded: 'Plex library',
  collection: 'Plex collection',
  watchlist: 'Watchlist',
  discovery: 'Discovery',
  genre: 'Genre',
  trakt: 'Trakt',
  stremioCatalog: 'Addon catalog',
};

const CATALOG_KEY = 'app.homeRowCatalog.v1';
const GROUP_ORDER: HomeRowGroup[] = ['continueWatching', 'recentlyAdded', 'collections', 'extras'];

let catalog: HomeRowDescriptor[] = readCatalog();
const listeners = new Set<() => void>();

function readCatalog(): HomeRowDescriptor[] {
  try {
    const parsed = JSON.parse(localStorage.getItem(CATALOG_KEY) || '[]');
    return Array.isArray(parsed) ? parsed.filter((row) => row && typeof row.id === 'string') : [];
  } catch {
    return [];
  }
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** Known rows in default order. Re-renders the caller when the list changes. */
export function useHomeRowCatalog(): HomeRowDescriptor[] {
  return useSyncExternalStore(subscribe, getHomeRowCatalog, getHomeRowCatalog);
}

export function getHomeRowCatalog(): HomeRowDescriptor[] {
  return catalog;
}

/** Replaces the known rows of one group. Groups keep their default position. */
export function registerHomeRows(descriptors: HomeRowDescriptor[], group: HomeRowGroup) {
  const seen = new Set<string>();
  const unique = descriptors.filter((row) => {
    if (row.group !== group || seen.has(row.id)) return false;
    seen.add(row.id);
    return true;
  });
  const merged = GROUP_ORDER.flatMap((g) => (g === group ? unique : catalog.filter((row) => row.group === g)));
  if (JSON.stringify(merged) === JSON.stringify(catalog)) return;
  catalog = merged;
  try {
    localStorage.setItem(CATALOG_KEY, JSON.stringify(merged));
  } catch {
    // Storage full or blocked: the list still works for this session.
  }
  listeners.forEach((listener) => listener());
}

/**
 * Applies a user order to items in default order. Items in `userOrder` follow it;
 * items it does not know (new rows, placeholders) stay right after the nearest
 * preceding known item of the default order.
 */
export function orderHomeRows<T>(items: T[], idOf: (item: T) => string, userOrder: string[]): T[] {
  if (userOrder.length === 0) return items;
  const rank = new Map<string, number>();
  userOrder.forEach((id, index) => {
    if (!rank.has(id)) rank.set(id, index);
  });
  let lastKey = -1;
  return items
    .map((item, index) => {
      const known = rank.get(idOf(item));
      if (known !== undefined) lastKey = known;
      return { key: known !== undefined ? known : lastKey + 0.5, index, item };
    })
    .sort((a, b) => (a.key !== b.key ? a.key - b.key : a.index - b.index))
    .map((entry) => entry.item);
}

export function orderedHomeRowCatalog(rows: HomeRowDescriptor[], userOrder: string[]) {
  return orderHomeRows(rows, (row) => row.id, userOrder);
}

/** The custom title if the user set one, otherwise `defaultTitle`. */
export function homeRowTitle(titles: Record<string, string>, id: string, defaultTitle: string): string {
  const custom = titles[id];
  return custom ? custom : defaultTitle;
}

/** Sets a custom title. A blank title, or the default title, removes it. */
export function renameHomeRow(id: string, newTitle: string, defaultTitle: string) {
  const trimmed = newTitle.trim();
  const next = { ...getSettings().homeRowTitles };
  if (!trimmed || trimmed === defaultTitle) delete next[id];
  else next[id] = trimmed;
  saveSettings({ homeRowTitles: next });
}

export function setHomeRowHidden(id: string, hidden: boolean) {
  const next = new Set(getSettings().homeRowHidden);
  if (hidden) next.add(id);
  else next.delete(id);
  saveSettings({ homeRowHidden: Array.from(next).sort() });
}

export function showAllHomeRows() {
  saveSettings({ homeRowHidden: [] });
}

export function resetHomeRowOrder() {
  saveSettings({ homeRowOrder: [] });
}

/** Saves a new row order, keeping the position of rows not listed right now. */
export function setHomeRowOrder(ids: string[]) {
  const listed = new Set(ids);
  const previous = getSettings().homeRowOrder;
  saveSettings({ homeRowOrder: [...ids, ...previous.filter((id) => !listed.has(id))] });
}

/** Moves one row up (-1) or down (+1) within the ordered list. */
export function moveHomeRow(id: string, delta: number) {
  const ids = orderedHomeRowCatalog(catalog, getSettings().homeRowOrder).map((row) => row.id);
  const index = ids.indexOf(id);
  const target = index + delta;
  if (index < 0 || target < 0 || target >= ids.length) return;
  [ids[index], ids[target]] = [ids[target], ids[index]];
  setHomeRowOrder(ids);
}
