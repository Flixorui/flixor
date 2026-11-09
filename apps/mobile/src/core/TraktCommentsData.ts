/**
 * Trakt comments for a title. Public API, so it works without a Trakt login.
 * macOS reference: Services/TraktCommentsService.swift
 */

import type { TraktComment, TraktCommentSort, TraktCommentTarget, TraktPage } from '@flixor/core';
import { getFlixorCore } from './index';
import { resolveWatchTarget, type WatchStateTarget } from './WatchState';

export const COMMENTS_NOT_FOUND = "This title couldn't be found on Trakt.";

/** Trakt addresses titles by IMDb id or Trakt id, never TMDB id. */
async function traktId(target: WatchStateTarget): Promise<string | number | null> {
  if (target.imdbId?.toLowerCase().startsWith('tt')) return target.imdbId;
  if (target.tmdbId == null) return null;
  const type = target.kind === 'movie' ? 'movie' : 'show';
  const found = await getFlixorCore().trakt.lookupByTmdb(target.tmdbId, type);
  return found?.ids?.trakt ?? null;
}

function commentTarget(target: WatchStateTarget, id: string | number): TraktCommentTarget | null {
  switch (target.kind) {
    case 'movie':
      return { type: 'movie', id };
    case 'show':
      return { type: 'show', id };
    case 'season':
      return target.seasonNumber == null ? null : { type: 'season', showId: id, season: target.seasonNumber };
    case 'episode':
      return target.seasonNumber == null || target.episodeNumber == null
        ? null
        : { type: 'episode', showId: id, season: target.seasonNumber, episode: target.episodeNumber };
  }
}

/** One page of comments. Throws COMMENTS_NOT_FOUND when the title can't be matched on Trakt. */
export async function fetchTraktComments(
  target: WatchStateTarget,
  sort: TraktCommentSort,
  page: number,
  limit: number = 10
): Promise<TraktPage<TraktComment>> {
  const resolved = await resolveWatchTarget(target);
  const id = await traktId(resolved);
  const trakt = id == null ? null : commentTarget(resolved, id);
  if (!trakt) throw new Error(COMMENTS_NOT_FOUND);
  return getFlixorCore().trakt.getComments(trakt, { sort, page, limit });
}

export function commentAuthor(comment: TraktComment): string {
  return comment.user?.name || comment.user?.username || 'Trakt user';
}

/** Whole comment flagged as spoiler, or inline [spoiler] tags in the text. */
export function commentHasSpoiler(comment: TraktComment): boolean {
  return comment.spoiler || /\[spoiler\]/i.test(comment.comment);
}

export function commentDisplayText(comment: TraktComment): string {
  return comment.comment.replace(/\[\/?spoiler\]/gi, '').trim();
}

/** `user_stats.rating` is what Trakt returns; `user_rating` is the legacy field. */
export function commentRating(comment: TraktComment): number | null {
  return comment.user_stats?.rating ?? comment.user_rating ?? null;
}

export function commentLikesLabel(comment: TraktComment): string {
  return comment.likes === 1 ? '1 like' : `${comment.likes} likes`;
}
