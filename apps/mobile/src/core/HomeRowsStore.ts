/**
 * Per-profile Home row customisation: order, custom titles, hidden rows, and the list
 * of known rows shown in Rows Settings. macOS reference: Services/HomeRowsStore.swift
 */

import { appSettingsEmitter } from '../hooks/useAppSettings';
import {
  getAppSettings,
  setAppSettings,
  type AppSettings,
  type ContinueWatchingSource,
  type HomeHeroSource,
  type HomeRowDescriptor,
} from './SettingsData';

export const HOME_CONTINUE_WATCHING_ROW_ID = 'continue-watching';
export const HOME_PLEX_WATCHLIST_ROW_ID = 'plex-watchlist';
export const HOME_TRAKT_WATCHLIST_ROW_ID = 'trakt-watchlist';

/** Rows that are listed in settings but can't feed the hero. */
export function isHeroEligibleRow(row: HomeRowDescriptor): boolean {
  return (
    row.id !== HOME_CONTINUE_WATCHING_ROW_ID &&
    row.id !== HOME_PLEX_WATCHLIST_ROW_ID &&
    row.id !== HOME_TRAKT_WATCHLIST_ROW_ID &&
    row.kind !== 'userCollection'
  );
}

async function commit(partial: Partial<AppSettings>): Promise<void> {
  await setAppSettings(partial);
  appSettingsEmitter.emit();
}

export function homeRowTitle(
  titles: Record<string, string>,
  id: string,
  defaultTitle: string
): string {
  return titles[id] || defaultTitle;
}

/**
 * Applies a user order to items in default order. Items the order doesn't know (new
 * rows) stay right after the nearest preceding known item of the default order.
 */
export function orderHomeRows<T>(items: T[], getId: (item: T) => string, userOrder: string[]): T[] {
  if (userOrder.length === 0) return items;
  const rank = new Map<string, number>();
  userOrder.forEach((id, index) => {
    if (!rank.has(id)) rank.set(id, index);
  });

  let lastKey = -1;
  const keyed = items.map((item, index) => {
    const known = rank.get(getId(item));
    if (known !== undefined) {
      lastKey = known;
      return { key: known, index, item };
    }
    return { key: lastKey + 0.5, index, item };
  });
  return keyed.sort((a, b) => (a.key !== b.key ? a.key - b.key : a.index - b.index)).map((entry) => entry.item);
}

export function orderedHomeRowCatalog(settings: AppSettings): HomeRowDescriptor[] {
  return orderHomeRows(settings.homeRowCatalog, (row) => row.id, settings.homeRowOrder);
}

/**
 * Records the rows Home has built. Does not emit, so rows don't re-render because
 * the settings list changed; Rows Settings reads the list when it is focused.
 */
export async function registerHomeRows(descriptors: HomeRowDescriptor[]): Promise<void> {
  const seen = new Set<string>();
  const unique = descriptors.filter((row) => {
    if (seen.has(row.id)) return false;
    seen.add(row.id);
    return true;
  });
  const current = getAppSettings().homeRowCatalog;
  if (JSON.stringify(unique) === JSON.stringify(current)) return;
  await setAppSettings({ homeRowCatalog: unique });
}

/** Sets a custom title. Blank or the default title removes it. */
export async function renameHomeRow(id: string, newTitle: string | undefined, defaultTitle: string): Promise<void> {
  const trimmed = newTitle?.trim() ?? '';
  const titles = { ...getAppSettings().homeRowTitles };
  if (!trimmed || trimmed === defaultTitle) {
    if (!(id in titles)) return;
    delete titles[id];
  } else {
    if (titles[id] === trimmed) return;
    titles[id] = trimmed;
  }
  await commit({ homeRowTitles: titles });
}

export async function setHomeRowHidden(id: string, hidden: boolean): Promise<void> {
  const current = getAppSettings().homeRowHidden;
  if (current.includes(id) === hidden) return;
  await commit({
    homeRowHidden: hidden ? [...current, id].sort() : current.filter((rowId) => rowId !== id),
  });
}

export async function showAllHomeRows(): Promise<void> {
  if (getAppSettings().homeRowHidden.length === 0) return;
  await commit({ homeRowHidden: [] });
}

/** Moves one row up (-1) or down (+1), keeping the position of rows not listed now. */
export async function moveHomeRow(id: string, delta: -1 | 1): Promise<void> {
  const settings = getAppSettings();
  const ids = orderedHomeRowCatalog(settings).map((row) => row.id);
  const index = ids.indexOf(id);
  const target = index + delta;
  if (index < 0 || target < 0 || target >= ids.length) return;
  [ids[index], ids[target]] = [ids[target], ids[index]];
  const listed = new Set(ids);
  await commit({ homeRowOrder: [...ids, ...settings.homeRowOrder.filter((rowId) => !listed.has(rowId))] });
}

export async function resetHomeRowOrder(): Promise<void> {
  if (getAppSettings().homeRowOrder.length === 0) return;
  await commit({ homeRowOrder: [] });
}

export async function setHomeHeroSource(source: HomeHeroSource): Promise<void> {
  if (getAppSettings().homeHeroSource === source) return;
  await commit({ homeHeroSource: source });
}

/** Choosing a source replaces the older separate Trakt toggle. */
export async function setContinueWatchingSource(source: ContinueWatchingSource): Promise<void> {
  await commit({ continueWatchingSource: source, showTraktContinueWatching: false });
}

/** Keeps a removed Trakt card hidden until it has newer activity. */
export async function addContinueWatchingDismissal(key: string): Promise<void> {
  await commit({
    continueWatchingTraktDismissals: { ...getAppSettings().continueWatchingTraktDismissals, [key]: Date.now() },
  });
}
