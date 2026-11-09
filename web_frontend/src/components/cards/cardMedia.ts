/** Looks up what a card id refers to: Plex and TMDB ids, and the player route. */
import { getSettings } from '@/state/settings';
import { plexBackendDir, plexBackendFindByGuid, plexBackendMetadata } from '@/services/plex_backend';
import { tmdbBestBackdropUrl, tmdbDetails, tmdbImage, tmdbSearchTitle } from '@/services/tmdb';
import type { StremioCatalogItem } from '@/stremio';
import { createLimiter } from './limiter';
import { parseCardId, type CardItem, type CardMediaType } from './cardTypes';

const limit = createLimiter(6);

export interface CardMedia {
  mediaType?: CardMediaType;
  plexRatingKey?: string;
  tmdbId?: string;
  tmdbMedia?: 'movie' | 'tv';
  imdbId?: string;
  /** The show's rating key, for episodes and seasons. */
  showRatingKey?: string;
  plexMeta?: any;
}

const mediaCache = new Map<string, Promise<CardMedia>>();

function guidValue(meta: any, prefixes: string[]): string | undefined {
  const guids: string[] = (meta?.Guid || []).map((g: any) => String(g.id || ''));
  const match = guids.find((g) => prefixes.some((p) => g.includes(`${p}://`)));
  return match?.split('://')[1]?.split('?')[0];
}

/** Resolves a card id to its Plex and TMDB identity. Results are cached per session. */
export function resolveCardMedia(id: string, hint?: CardMediaType): Promise<CardMedia> {
  const key = id.replaceAll('%3A', ':');
  let pending = mediaCache.get(key);
  if (!pending) {
    pending = limit(() => loadCardMedia(key, hint)).catch((error) => {
      mediaCache.delete(key);
      throw error;
    });
    mediaCache.set(key, pending);
  }
  return pending;
}

async function loadCardMedia(id: string, hint?: CardMediaType): Promise<CardMedia> {
  const parsed = parseCardId(id);
  if (parsed.source === 'plex') {
    const res: any = await plexBackendMetadata(parsed.ratingKey);
    const meta = res?.MediaContainer?.Metadata?.[0];
    const type = String(meta?.type || hint || '') as CardMediaType;
    const tmdbMedia = type === 'movie' ? 'movie' : 'tv';
    return {
      mediaType: type || undefined,
      plexRatingKey: parsed.ratingKey,
      tmdbId: type === 'movie' || type === 'show' ? guidValue(meta, ['tmdb', 'themoviedb']) : undefined,
      tmdbMedia,
      imdbId: guidValue(meta, ['imdb']),
      showRatingKey: meta?.grandparentRatingKey
        ? String(meta.grandparentRatingKey)
        : meta?.parentRatingKey && type === 'season'
          ? String(meta.parentRatingKey)
          : undefined,
      plexMeta: meta,
    };
  }
  if (parsed.source === 'tmdb') {
    return {
      mediaType: parsed.media === 'movie' ? 'movie' : 'show',
      tmdbId: parsed.tmdbId,
      tmdbMedia: parsed.media,
      plexRatingKey: await findPlexKey(parsed.tmdbId, parsed.media),
    };
  }
  return { mediaType: hint };
}

async function findPlexKey(tmdbId: string, media: 'movie' | 'tv'): Promise<string | undefined> {
  const s = getSettings();
  if (!s.plexBaseUrl || !s.plexToken) return undefined;
  const type = media === 'movie' ? 1 : 2;
  for (const guid of [`tmdb://${tmdbId}`, `themoviedb://${tmdbId}`]) {
    try {
      const res: any = await plexBackendFindByGuid(guid, type as 1 | 2);
      const hit = res?.MediaContainer?.Metadata?.[0];
      if (hit?.ratingKey) return String(hit.ratingKey);
    } catch {
      // Try the next guid form; not being in the library is the common case.
    }
  }
  return undefined;
}

/** Plex id of the series for an episode or season, or the item's own TMDB reference. */
async function tmdbReference(id: string, hint?: CardMediaType): Promise<{ media: 'movie' | 'tv'; tmdbId: string } | null> {
  const parsed = parseCardId(id);
  if (parsed.source === 'tmdb') return { media: parsed.media, tmdbId: parsed.tmdbId };
  if (parsed.source !== 'plex') return null;
  const media = await resolveCardMedia(id, hint);
  if (media.tmdbId && media.tmdbMedia) return { media: media.tmdbMedia, tmdbId: media.tmdbId };
  if (media.showRatingKey) {
    const show = await resolveCardMedia(`plex:${media.showRatingKey}`, 'show');
    if (show.tmdbId) return { media: 'tv', tmdbId: show.tmdbId };
  }
  return null;
}

const artworkCache = new Map<string, Promise<string | undefined>>();

/** TMDB artwork for a card, or undefined when the card should keep the image it has. */
export function upgradedArtwork(id: string, kind: 'poster' | 'backdrop', hint?: CardMediaType) {
  if (getSettings().enrichMetadataWithTMDB === false) return Promise.resolve(undefined);
  const key = `${kind}:${id}`;
  let pending = artworkCache.get(key);
  if (!pending) {
    pending = limit(async () => {
      const ref = await tmdbReference(id, hint);
      if (!ref) return undefined;
      if (kind === 'backdrop') return tmdbBestBackdropUrl('', ref.media, ref.tmdbId, 'en');
      const details: any = await tmdbDetails('', ref.media, ref.tmdbId);
      return details?.poster_path ? tmdbImage(details.poster_path, 'w500') : undefined;
    }).catch(() => undefined);
    artworkCache.set(key, pending);
  }
  return pending;
}

/** Whether Play can start right away: a Plex item that holds a video, or a show with episodes. */
export async function resolvePlayerRoute(id: string, hint?: CardMediaType): Promise<string | null> {
  const media = await resolveCardMedia(id, hint).catch(() => null);
  const ratingKey = media?.plexRatingKey;
  if (!media || !ratingKey) return null;

  let type = media.mediaType;
  if (parseCardId(id).source === 'tmdb' && media.tmdbMedia === 'tv') type = 'show';
  if (type === 'movie' || type === 'episode') return playerPath(`plex:${ratingKey}`);
  if (type !== 'show' && type !== 'season') return null;

  const onDeck: any = await plexBackendDir(`/library/metadata/${ratingKey}/onDeck`);
  const next = onDeck?.MediaContainer?.Metadata?.[0];
  if (next?.ratingKey) return playerPath(`plex:${next.ratingKey}`);

  const leaves: any = await plexBackendDir(`/library/metadata/${ratingKey}/allLeaves`);
  const episodes: any[] = leaves?.MediaContainer?.Metadata || [];
  const first = episodes.find((e) => !e.viewCount) || episodes[0];
  return first?.ratingKey ? playerPath(`plex:${first.ratingKey}`) : null;
}

export function playerPath(id: string) {
  return `/player/${encodeURIComponent(id)}`;
}

export function detailsPath(id: string) {
  return `/details/${encodeURIComponent(id)}`;
}

/** Where Play should go: the player when there is a video, otherwise the details page. */
export async function resolvePlayRoute(id: string, hint?: CardMediaType): Promise<string> {
  try {
    const route = await resolvePlayerRoute(id, hint);
    if (route) return route;
  } catch {
    // Fall through to details, which explains what can be played.
  }
  return detailsPath(id);
}

/** Row item for an addon catalog entry. Entries with a TMDB id use the normal pipeline. */
export function stremioItemToCard(item: StremioCatalogItem): CardItem {
  const isSeries = item.type === 'series';
  return {
    id: item.tmdbId
      ? `tmdb:${isSeries ? 'tv' : 'movie'}:${item.tmdbId}`
      : `stremio:${item.type}:${item.imdbId || item.id}`,
    title: item.name,
    image: item.poster,
    backdrop: item.background,
    mediaType: isSeries ? 'show' : 'movie',
    year: item.year,
    subtitle: item.year ? String(item.year) : undefined,
  };
}

/**
 * Details id for a card. Addon entries without a TMDB id are matched by title and
 * year when opened, so a row of them does not cost a lookup per card up front.
 */
export async function resolveDetailsId(item: Pick<CardItem, 'id' | 'title' | 'year'>): Promise<string | null> {
  const parsed = parseCardId(item.id);
  if (parsed.source !== 'stremio') return item.id;
  const media = parsed.type === 'series' ? 'tv' : 'movie';
  try {
    const res: any = await tmdbSearchTitle('', media, item.title, item.year);
    const hit = res?.results?.[0];
    return hit?.id ? `tmdb:${media}:${hit.id}` : null;
  } catch {
    return null;
  }
}
