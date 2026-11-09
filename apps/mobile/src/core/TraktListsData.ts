/**
 * The user's Trakt personal lists: view, create, edit, delete, and add or remove titles.
 * macOS reference: ViewModels/TraktListsViewModel.swift
 *
 * Trakt allows about one write per second, so callers update local state after a write
 * instead of re-fetching.
 */

import type { TraktListEntry, TraktListPrivacy, TraktSyncItems, TraktUserList } from '@flixor/core';
import { getFlixorCore } from './index';

export type { TraktListPrivacy, TraktUserList };

export const TRAKT_LIST_PRIVACY_OPTIONS: Array<{ value: TraktListPrivacy; label: string; detail: string }> = [
  { value: 'private', label: 'Private', detail: 'Only you' },
  { value: 'link', label: 'Link', detail: 'Anyone with the link' },
  { value: 'friends', label: 'Friends', detail: 'People you follow who follow you' },
  { value: 'public', label: 'Public', detail: 'Anyone on Trakt' },
];

export interface TraktListTitle {
  type: 'movie' | 'show';
  tmdbId?: number;
  imdbId?: string;
  title: string;
}

export interface TraktListGridItem extends TraktListTitle {
  /** Entry id, unique within the list. */
  entryId: number;
  id: string;
  year?: number;
  image?: string;
  listedAt?: string;
}

export interface TraktListContents {
  items: TraktListGridItem[];
  /** People, seasons and episodes on the list, which the grid can't show. */
  hiddenCount: number;
}

/** How many TMDB poster lookups run at once. */
const POSTER_BATCH_SIZE = 12;

export function isTraktAvailable(): boolean {
  try {
    return getFlixorCore().isTraktAuthenticated;
  } catch {
    return false;
  }
}

export async function fetchTraktLists(): Promise<TraktUserList[]> {
  return getFlixorCore().trakt.getMyLists();
}

function toGridItem(entry: TraktListEntry): TraktListGridItem | null {
  const media = entry.movie ?? entry.show;
  if (!media || (entry.type !== 'movie' && entry.type !== 'show')) return null;
  return {
    entryId: entry.id,
    id: `${entry.type}:${media.ids?.trakt ?? entry.id}`,
    type: entry.type,
    title: media.title ?? 'Unknown',
    year: media.year,
    tmdbId: media.ids?.tmdb,
    imdbId: media.ids?.imdb,
    listedAt: entry.listed_at,
  };
}

async function attachPosters(items: TraktListGridItem[]): Promise<TraktListGridItem[]> {
  const tmdb = getFlixorCore().tmdb;
  const result = [...items];
  for (let start = 0; start < items.length; start += POSTER_BATCH_SIZE) {
    await Promise.all(
      items.slice(start, start + POSTER_BATCH_SIZE).map(async (item, offset) => {
        if (item.tmdbId == null) return;
        try {
          const details =
            item.type === 'movie' ? await tmdb.getMovieDetails(item.tmdbId) : await tmdb.getTVDetails(item.tmdbId);
          if (details?.poster_path) {
            result[start + offset] = { ...item, image: tmdb.getPosterUrl(details.poster_path, 'w342') };
          }
        } catch {
          // The card shows a placeholder.
        }
      })
    );
  }
  return result;
}

export async function fetchTraktListContents(listId: number): Promise<TraktListContents> {
  const entries = await getFlixorCore().trakt.getListItems(listId);
  const items = entries.map(toGridItem).filter((item): item is TraktListGridItem => item !== null);
  return { items: await attachPosters(items), hiddenCount: entries.length - items.length };
}

export async function createTraktList(options: {
  name: string;
  description?: string;
  privacy: TraktListPrivacy;
}): Promise<TraktUserList> {
  return getFlixorCore().trakt.createList(options);
}

export async function updateTraktList(
  listId: number,
  changes: { name?: string; description?: string; privacy?: TraktListPrivacy }
): Promise<TraktUserList> {
  return getFlixorCore().trakt.updateList(listId, changes);
}

export async function deleteTraktList(listId: number): Promise<void> {
  await getFlixorCore().trakt.deleteList(listId);
}

function syncItems(title: TraktListTitle): TraktSyncItems | null {
  const ids = { tmdb: title.tmdbId, imdb: title.imdbId };
  if (ids.tmdb == null && !ids.imdb) return null;
  return title.type === 'movie' ? { movies: [{ ids }] } : { shows: [{ ids }] };
}

export async function addTitleToTraktList(listId: number, title: TraktListTitle): Promise<boolean> {
  const items = syncItems(title);
  if (!items) return false;
  const result = await getFlixorCore().trakt.addToList(listId, items);
  const added = (result.added?.movies ?? 0) + (result.added?.shows ?? 0);
  const existing = (result.existing?.movies ?? 0) + (result.existing?.shows ?? 0);
  return added > 0 || existing > 0;
}

export async function removeTitleFromTraktList(listId: number, title: TraktListTitle): Promise<boolean> {
  const items = syncItems(title);
  if (!items) return false;
  const result = await getFlixorCore().trakt.removeFromList(listId, items);
  return (result.deleted?.movies ?? 0) + (result.deleted?.shows ?? 0) > 0;
}

/** User-facing text for a failed Trakt request. */
export function traktListErrorMessage(error: unknown, fallback: string): string {
  const message = error instanceof Error ? error.message : '';
  if (/\b429\b/.test(message)) return "Trakt's rate limit was reached. Try again in a moment.";
  if (/\b420\b/.test(message)) return "You've reached Trakt's limit for lists.";
  if (/\b404\b/.test(message)) return 'This list no longer exists.';
  return fallback;
}
