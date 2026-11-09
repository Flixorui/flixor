/**
 * Trakt comments for movies, shows, seasons and episodes. Uses the public API,
 * so it works without a Trakt login. Trakt addresses titles by Trakt id, slug or
 * IMDb id, not TMDB id, so targets are resolved first.
 */
import { API_BASE_URL } from '@/services/api';
import { traktLookupId } from '@/services/trakt';
import { resolveWatchTarget, type ResolvedTarget, type WatchTarget } from '@/services/watchState';

export type TraktCommentSort = 'likes' | 'newest';

export interface TraktComment {
  id: number;
  comment: string;
  spoiler: boolean;
  review: boolean;
  likes?: number;
  replies?: number;
  created_at?: string;
  user_rating?: number;
  user_stats?: { rating?: number | null };
  user?: { username?: string; name?: string; vip?: boolean };
}

export interface TraktCommentsPage {
  items: TraktComment[];
  page: number;
  pageCount: number;
  itemCount: number;
  hasMore: boolean;
}

export class CommentsUnresolvedError extends Error {
  constructor() {
    super('This title could not be found on Trakt.');
    this.name = 'CommentsUnresolvedError';
  }
}

const TRAKT = `${API_BASE_URL.replace(/\/$/, '')}/trakt`;

async function traktTitleId(t: ResolvedTarget): Promise<string> {
  if (t.titleImdbId?.toLowerCase().startsWith('tt')) return t.titleImdbId;
  if (t.titleTraktId != null) return String(t.titleTraktId);
  if (t.titleTmdbId != null) {
    const type = t.kind === 'movie' ? 'movie' : 'show';
    const hit = await traktLookupId('tmdb', t.titleTmdbId, type);
    const id = (type === 'movie' ? hit?.movie : hit?.show)?.ids?.trakt;
    if (id != null) return String(id);
  }
  throw new CommentsUnresolvedError();
}

function commentsPath(t: ResolvedTarget, id: string): string {
  const base = `/comments/${t.kind === 'movie' ? 'movies' : 'shows'}/${encodeURIComponent(id)}`;
  switch (t.kind) {
    case 'movie':
    case 'show':
      return base;
    case 'season':
      if (t.seasonNumber == null) throw new CommentsUnresolvedError();
      return `${base}/seasons/${t.seasonNumber}`;
    case 'episode':
      if (t.seasonNumber == null || t.episodeNumber == null) throw new CommentsUnresolvedError();
      return `${base}/seasons/${t.seasonNumber}/episodes/${t.episodeNumber}`;
  }
}

/** Resolves a target once, so paging doesn't repeat the lookups. */
export async function resolveCommentsPath(target: WatchTarget): Promise<string> {
  const resolved = await resolveWatchTarget(target, true);
  return commentsPath(resolved, await traktTitleId(resolved));
}

export async function fetchComments(
  path: string,
  sort: TraktCommentSort,
  page: number,
  limit = 10,
  signal?: AbortSignal,
): Promise<TraktCommentsPage> {
  const response = await fetch(`${TRAKT}${path}?sort=${sort}&page=${page}&limit=${limit}`, {
    credentials: 'include',
    signal,
  });
  if (response.status === 404) throw new CommentsUnresolvedError();
  if (!response.ok) throw new Error(`Comments request failed: ${response.status}`);
  const data = await response.json();
  return {
    items: data.items || [],
    page: data.page,
    pageCount: data.pageCount,
    itemCount: data.itemCount,
    hasMore: data.page < data.pageCount,
  };
}
