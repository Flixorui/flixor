/**
 * Original language of a title (TMDB `original_language`), for the "Original"
 * audio preference. Cached for the session; bounded so audio doesn't switch long
 * after playback started.
 * macOS reference: Services/Playback/OriginalLanguageResolver.swift
 */

import { getFlixorCore } from '../../../core';
import { parseStreamSeriesRef, resolveStreamTmdbId } from '../../../stremio/StreamEpisodeNavigator';
import type { GenericStreamParams } from '../../../stremio/types';

const LOOKUP_TIMEOUT_MS = 4_000;
const cache = new Map<string, string | null>();

async function lookup(params: GenericStreamParams): Promise<string | null> {
  const core = getFlixorCore();
  const series = parseStreamSeriesRef(params);
  const isShow = Boolean(series);
  let tmdbId: number | null | undefined = series ? await resolveStreamTmdbId(series) : params.tmdbId;

  if (!tmdbId && !isShow && params.imdbId) {
    tmdbId = (await core.tmdb.findByImdbId(params.imdbId)).movie_results?.[0]?.id;
  }
  if (!tmdbId) {
    return null;
  }

  const key = `${isShow ? 'tv' : 'movie'}:${tmdbId}`;
  const known = cache.get(key);
  if (known !== undefined) {
    return known;
  }
  const details = isShow ? await core.tmdb.getTVDetails(tmdbId) : await core.tmdb.getMovieDetails(tmdbId);
  const language = details.original_language?.trim().toLowerCase() || null;
  cache.set(key, language);
  return language;
}

/** Null when it can't be determined in time. */
export function resolveOriginalLanguage(params: GenericStreamParams): Promise<string | null> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(null), LOOKUP_TIMEOUT_MS);
    lookup(params)
      .catch(() => null)
      .then((language) => {
        clearTimeout(timer);
        resolve(language);
      });
  });
}
