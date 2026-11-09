/** Trakt lists: the user's own lists with editing, and public lists. */
import { API_BASE_URL } from '@/services/api';
import { tmdbImage } from '@/services/tmdb';
import { TraktApiError } from '@/services/trakt';
import { resolveWatchTarget, traktSyncItems, type WatchTarget } from '@/services/watchState';

const TRAKT = `${API_BASE_URL.replace(/\/$/, '')}/trakt`;

export type TraktListPrivacy = 'private' | 'friends' | 'public';

export interface TraktUserList {
  name: string;
  description?: string | null;
  privacy: TraktListPrivacy;
  item_count?: number;
  ids: { trakt: number; slug?: string };
  user?: { username?: string; ids?: { slug?: string } };
}

export interface TraktListEntry {
  rank?: number;
  id?: number;
  type: 'movie' | 'show' | 'season' | 'episode';
  movie?: any;
  show?: any;
  season?: any;
  episode?: any;
}

async function request<T = any>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${TRAKT}${path}`, {
    ...init,
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...init?.headers },
  });
  if (!response.ok) {
    let message = `Trakt request failed: ${response.status}`;
    try {
      const body = await response.json();
      if (body?.message) message = String(body.message);
    } catch { /* keep the status message */ }
    throw new TraktApiError(response.status, message);
  }
  return response.json();
}

export const getMyLists = () => request<TraktUserList[]>('/users/me/lists');

export const getListItems = (listId: number) => request<TraktListEntry[]>(`/users/me/lists/${listId}/items`);

export const createList = (input: { name: string; description?: string; privacy: TraktListPrivacy }) =>
  request<TraktUserList>('/users/me/lists', { method: 'POST', body: JSON.stringify(input) });

export const updateList = (listId: number, input: { name?: string; description?: string; privacy?: TraktListPrivacy }) =>
  request<TraktUserList>(`/users/me/lists/${listId}`, { method: 'PUT', body: JSON.stringify(input) });

export const deleteList = (listId: number) => request(`/users/me/lists/${listId}`, { method: 'DELETE' });

async function targetItems(target: WatchTarget): Promise<Record<string, unknown>> {
  const items = traktSyncItems(await resolveWatchTarget(target, true));
  if (!items) throw new Error("Couldn't match this title on Trakt");
  return items;
}

export async function addToList(listId: number, target: WatchTarget) {
  return request(`/users/me/lists/${listId}/items`, { method: 'POST', body: JSON.stringify(await targetItems(target)) });
}

export async function removeFromList(listId: number, target: WatchTarget) {
  return request(`/users/me/lists/${listId}/items/remove`, { method: 'POST', body: JSON.stringify(await targetItems(target)) });
}

/** Removes one entry shown in a list view, using the ids that entry already carries. */
export function removeEntryFromList(listId: number, entry: TraktListEntry) {
  const ids = (entry.movie ?? entry.show)?.ids;
  const body = entry.type === 'movie' ? { movies: [{ ids }] } : { shows: [{ ids }] };
  return request(`/users/me/lists/${listId}/items/remove`, { method: 'POST', body: JSON.stringify(body) });
}

// --- Public lists ---

export interface TraktPublicList extends TraktUserList {
  likes?: number;
}

/** Parses a trakt.tv list URL, `user/list`, or a numeric id into an API path. */
export function publicListPath(input: string): string | null {
  const raw = input.trim();
  if (!raw) return null;
  if (/^\d+$/.test(raw)) return `/lists/${raw}`;
  const path = raw.replace(/^https?:\/\/(www\.)?trakt\.tv\//i, '').split(/[?#]/)[0].replace(/\/+$/, '');
  const byId = /^lists\/(\d+)$/.exec(path);
  if (byId) return `/lists/${byId[1]}`;
  const byUser = /^(?:users\/)?([\w.-]+)\/lists\/([\w.-]+)$/.exec(path) ?? /^([\w.-]+)\/([\w.-]+)$/.exec(path);
  return byUser ? `/users/${encodeURIComponent(byUser[1])}/lists/${encodeURIComponent(byUser[2])}` : null;
}

export const getPublicList = (path: string) => request<TraktPublicList>(path);

export async function searchPublicLists(query: string): Promise<TraktPublicList[]> {
  const hits = await request<any[]>(`/lists/search?query=${encodeURIComponent(query)}&limit=20`);
  return hits.map((hit) => hit.list).filter(Boolean);
}

export const getPublicListItems = (listId: number, page = 1, limit = 50) =>
  request<{ items: TraktListEntry[]; page: number; pageCount: number; itemCount: number }>(
    `/lists/${listId}/items?page=${page}&limit=${limit}`,
  );

// --- Display helpers ---

export interface ListGridItem {
  id: string;
  title: string;
  image?: string;
  subtitle?: string;
  entry: TraktListEntry;
}

/** Movies and shows with a TMDB id, ready for a poster grid. Artwork is filled in by the caller. */
export function listEntriesToItems(entries: TraktListEntry[]): ListGridItem[] {
  const items: ListGridItem[] = [];
  for (const entry of entries) {
    const media = entry.type === 'movie' ? entry.movie : entry.type === 'show' ? entry.show : undefined;
    if (!media?.ids?.tmdb) continue;
    items.push({
      id: `tmdb:${entry.type === 'movie' ? 'movie' : 'tv'}:${media.ids.tmdb}`,
      title: media.title,
      subtitle: media.year ? String(media.year) : undefined,
      entry,
    });
  }
  return items;
}

export const posterUrl = (path?: string) => tmdbImage(path, 'w500');
