/** Which titles feed the Home hero, and the artwork and text shown for each. */
import { apiClient } from '@/services/api';
import { plexBackendMetadata, plexBackendMetadataWithExtras } from '@/services/plex_backend';
import { plexPartUrl } from '@/services/plex';
import { tmdbDetails, tmdbImage, tmdbImages, tmdbVideos } from '@/services/tmdb';
import { getSettings } from '@/state/settings';
import { WATCHLIST_ROW_ID, CONTINUE_WATCHING_ROW_ID } from '@/state/homeRows';
import { parseCardId, type CardItem } from '@/components/cards/cardTypes';
import { loadHomeRow, type HomeRowSpec } from './rowSpecs';

const HERO_ITEM_COUNT = 5;

export interface HeroMetadata {
  backdropUrl?: string;
  logoUrl?: string;
  title: string;
  overview?: string;
  genres: string[];
  year?: string;
  runtime?: number;
  rating?: string;
}

function preferringArt(items: CardItem[]) {
  const withArt = items.filter((item) => item.backdrop);
  return withArt.length > 0 ? withArt : items;
}

async function itemsFor(spec: HomeRowSpec | undefined): Promise<CardItem[]> {
  if (!spec || spec.placeholder) return [];
  return (await loadHomeRow(spec).catch(() => ({ items: [] as CardItem[] }))).items;
}

async function preferredItems(
  source: string,
  specs: HomeRowSpec[],
  continueWatching: CardItem[],
): Promise<CardItem[]> {
  if (source === 'continueWatching' || source === `row:${CONTINUE_WATCHING_ROW_ID}`) return continueWatching;
  if (source === 'myList') return itemsFor(specs.find((spec) => spec.id === WATCHLIST_ROW_ID));
  if (source.startsWith('row:')) return itemsFor(specs.find((spec) => spec.id === source.slice(4)));
  return [];
}

async function defaultItems(specs: HomeRowSpec[], continueWatching: CardItem[]): Promise<CardItem[]> {
  if (continueWatching.length > 0) return continueWatching;
  for (const spec of specs.filter((candidate) => candidate.kind === 'recentlyAdded')) {
    const items = await itemsFor(spec);
    if (items.length > 0) return items;
  }
  for (const spec of specs.filter((candidate) => candidate.kind === 'discovery' || candidate.kind === 'stremioCatalog')) {
    const items = (await itemsFor(spec)).filter((item) => item.backdrop);
    if (items.length > 0) return items;
  }
  return [];
}

/** Titles for the hero. A source with nothing to show falls back to the default. */
export async function resolveHeroItems(source: string, specs: HomeRowSpec[], continueWatching: CardItem[]) {
  const preferred = source && source !== 'default' ? await preferredItems(source, specs, continueWatching) : [];
  const items = preferred.length > 0 ? preferred : await defaultItems(specs, continueWatching);
  return preferringArt(items).slice(0, HERO_ITEM_COUNT);
}

const metadataCache = new Map<string, Promise<HeroMetadata>>();

/** Artwork, title and genres for one hero item. Loaded once per session. */
export function heroMetadata(item: CardItem): Promise<HeroMetadata> {
  let pending = metadataCache.get(item.id);
  if (!pending) {
    pending = loadHeroMetadata(item).catch(() => ({
      title: item.showTitle || item.title,
      overview: item.overview,
      genres: [],
      backdropUrl: item.backdrop,
    }));
    metadataCache.set(item.id, pending);
  }
  return pending;
}

async function loadHeroMetadata(item: CardItem): Promise<HeroMetadata> {
  const parsed = parseCardId(item.id);
  const result: HeroMetadata = {
    title: item.showTitle || item.title,
    overview: item.overview,
    genres: [],
    backdropUrl: item.backdrop,
    year: item.year ? String(item.year) : undefined,
  };

  let reference: { media: 'movie' | 'tv'; id: string } | null = null;
  if (parsed.source === 'tmdb') reference = { media: parsed.media, id: parsed.tmdbId };

  if (parsed.source === 'plex') {
    let res: any = await plexBackendMetadata(parsed.ratingKey);
    let meta = res?.MediaContainer?.Metadata?.[0];
    // Episodes and seasons present their series.
    const seriesKey = meta?.type === 'episode' ? meta.grandparentRatingKey : meta?.type === 'season' ? meta.parentRatingKey : undefined;
    if (seriesKey) {
      res = await plexBackendMetadata(String(seriesKey));
      meta = res?.MediaContainer?.Metadata?.[0] || meta;
    }
    if (meta) {
      result.title = meta.title || result.title;
      result.overview = meta.summary || result.overview;
      result.year = meta.year ? String(meta.year) : result.year;
      result.rating = meta.contentRating || undefined;
      result.runtime = meta.duration ? Math.round(meta.duration / 60000) : undefined;
      result.genres = (meta.Genre || []).slice(0, 3).map((g: any) => g.tag);
      if (meta.art) result.backdropUrl = apiClient.getPlexImageNoToken(meta.art);
      const guid = (meta.Guid || []).map((g: any) => String(g.id || '')).find((g: string) => g.includes('tmdb://') || g.includes('themoviedb://'));
      const id = guid?.split('://')[1];
      if (id) reference = { media: meta.type === 'movie' ? 'movie' : 'tv', id };
    }
  }

  if (!reference) return result;

  const [images, details]: any[] = await Promise.all([
    tmdbImages('', reference.media, reference.id, 'en,null').catch(() => null),
    tmdbDetails('', reference.media, reference.id).catch(() => null),
  ]);

  // Textless artwork first, since the logo goes on top.
  const backdrops: any[] = images?.backdrops || [];
  const best = (list: any[]) => [...list].sort((a, b) => (b.vote_average ?? 0) - (a.vote_average ?? 0))[0];
  const backdrop = best(backdrops.filter((b) => b.iso_639_1 == null)) || best(backdrops);
  if (backdrop?.file_path) result.backdropUrl = tmdbImage(backdrop.file_path, 'original');
  const logos: any[] = images?.logos || [];
  const logo = logos.find((l) => l.iso_639_1 === 'en') || logos[0];
  if (logo?.file_path) result.logoUrl = tmdbImage(logo.file_path, 'w500');

  if (details) {
    if (result.genres.length === 0) result.genres = (details.genres || []).slice(0, 3).map((g: any) => g.name);
    result.overview = result.overview || details.overview;
    result.title = result.title || details.title || details.name;
    result.year = result.year || String(details.release_date || details.first_air_date || '').slice(0, 4) || undefined;
    result.runtime = result.runtime || details.runtime || details.episode_run_time?.[0];
  }
  return result;
}

/** Trailer for the non-carousel hero: a Plex extra, or a YouTube key from TMDB. */
export async function heroTrailer(item: CardItem): Promise<{ videoUrl?: string; ytKey?: string }> {
  const parsed = parseCardId(item.id);
  if (parsed.source === 'plex') {
    const s = getSettings();
    const res: any = await plexBackendMetadataWithExtras(parsed.ratingKey).catch(() => null);
    const extra = res?.MediaContainer?.Metadata?.[0]?.Extras?.Metadata?.[0]?.Media?.[0]?.Part?.[0]?.key as string | undefined;
    if (extra && s.plexBaseUrl && s.plexToken) return { videoUrl: plexPartUrl(s.plexBaseUrl, s.plexToken, extra) };
    return {};
  }
  if (parsed.source === 'tmdb') {
    const videos: any = await tmdbVideos('', parsed.media, parsed.tmdbId).catch(() => null);
    return { ytKey: (videos?.results || []).find((v: any) => v.site === 'YouTube')?.key };
  }
  return {};
}
