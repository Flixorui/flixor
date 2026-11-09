/**
 * Turns addon catalog entries into items the rest of the app can open.
 * macOS reference: Services/Stremio/StremioCatalogMapper.swift
 *
 * Catalog addons return IMDb ids, but Details and the stream resolver work from
 * `tmdb:<media>:<id>`. Entries TMDB can't match are dropped: unlike macOS, mobile
 * Details has no way to open an addon-only title.
 */

import { getFlixorCore } from '../core/index';
import type { RowItem } from '../core/HomeData';
import type { StremioMetaPreview } from './StremioCatalogService';

const MAX_CONCURRENT_LOOKUPS = 10;

/** IMDb id to TMDB match, cached for the session. Failures are not cached. */
const tmdbIdCache = new Map<string, { movie?: number; tv?: number }>();
const inFlight = new Map<string, Promise<{ movie?: number; tv?: number } | null>>();

let active = 0;
const waiting: Array<() => void> = [];

async function withLookupSlot<T>(work: () => Promise<T>): Promise<T> {
  if (active >= MAX_CONCURRENT_LOOKUPS) {
    await new Promise<void>((resolve) => waiting.push(resolve));
  }
  active += 1;
  try {
    return await work();
  } finally {
    active -= 1;
    waiting.shift()?.();
  }
}

function lookupImdbId(imdbId: string): Promise<{ movie?: number; tv?: number } | null> {
  const cached = tmdbIdCache.get(imdbId);
  if (cached) return Promise.resolve(cached);
  const pending = inFlight.get(imdbId);
  if (pending) return pending;

  const request = withLookupSlot(async () => {
    try {
      const response = await getFlixorCore().tmdb.findByImdbId(imdbId);
      const result = { movie: response.movie_results?.[0]?.id, tv: response.tv_results?.[0]?.id };
      tmdbIdCache.set(imdbId, result);
      return result;
    } catch (e) {
      console.log('[StremioCatalogMapper] TMDB lookup failed:', e);
      return null;
    } finally {
      inFlight.delete(imdbId);
    }
  });
  inFlight.set(imdbId, request);
  return request;
}

function imdbIdOf(preview: StremioMetaPreview): string | undefined {
  if (preview.imdb_id?.startsWith('tt')) return preview.imdb_id;
  return preview.id.startsWith('tt') ? preview.id.split(':')[0] : undefined;
}

async function resolveItemId(preview: StremioMetaPreview): Promise<string | null> {
  const isSeries = preview.type === 'series';
  const media = isSeries ? 'tv' : 'movie';

  if (preview.id.startsWith('tmdb:')) {
    const numeric = preview.id.split(':').pop();
    return numeric ? `tmdb:${media}:${numeric}` : null;
  }

  const imdbId = imdbIdOf(preview);
  if (!imdbId) return null;
  const match = await lookupImdbId(imdbId);
  if (!match) return null;
  const tmdbId = isSeries ? match.tv ?? match.movie : match.movie ?? match.tv;
  if (tmdbId == null) return null;
  // A wrong-type match still has to open with the type TMDB gave it.
  const resolvedMedia = isSeries ? (match.tv != null ? 'tv' : 'movie') : match.movie != null ? 'movie' : 'tv';
  return `tmdb:${resolvedMedia}:${tmdbId}`;
}

/** Maps a catalog page in order, dropping unmatched and duplicate titles. */
export async function mapCatalogPreviews(previews: StremioMetaPreview[]): Promise<RowItem[]> {
  const items = await Promise.all(
    previews.map(async (preview): Promise<RowItem | null> => {
      const id = await resolveItemId(preview);
      if (!id) return null;
      const rating = preview.imdbRating ? Number(preview.imdbRating) : undefined;
      return {
        id,
        title: preview.name,
        image: preview.poster,
        backdrop: preview.background,
        mediaType: id.startsWith('tmdb:tv:') ? 'tv' : 'movie',
        rating: rating && !Number.isNaN(rating) ? rating : undefined,
        subtitle: preview.year ? String(preview.year) : undefined,
      };
    })
  );

  const seen = new Set<string>();
  return items.filter((item): item is RowItem => {
    if (!item || seen.has(item.id)) return false;
    seen.add(item.id);
    return true;
  });
}
