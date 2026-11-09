import type { CollectionSource, PersonCredits, PersonOrder } from '@/state/collections';
import type { TitleGridItem } from '@/components/details/TitleGrid';
import { discoverParams } from '@/services/discover';
import { tmdbCollection, tmdbDetails, tmdbDiscoverMovies, tmdbDiscoverTV, tmdbImage, tmdbPersonCombined } from '@/services/tmdb';
import { traktLookupId } from '@/services/trakt';
import { getPublicListItems, listEntriesToItems } from '@/services/traktLists';
import { getCatalogItems, getCatalogs, type StremioCatalogItem } from '@/stremio';

export interface CollectionItem extends TitleGridItem {
  backdrop?: string;
}

export interface CollectionSourcePage {
  items: CollectionItem[];
  nextCursor: number | null;
}

const LOOKUP_BATCH = 6;

async function inBatches<T, R>(items: T[], work: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = [];
  for (let index = 0; index < items.length; index += LOOKUP_BATCH) {
    results.push(...await Promise.all(items.slice(index, index + LOOKUP_BATCH).map(work)));
  }
  return results;
}

function tmdbItem(result: any, media: 'movie' | 'tv'): CollectionItem {
  const date: string | undefined = result.release_date || result.first_air_date;
  return {
    id: `tmdb:${media}:${result.id}`,
    title: result.title || result.name || '',
    image: tmdbImage(result.poster_path, 'w500'),
    backdrop: tmdbImage(result.backdrop_path, 'w780'),
    subtitle: date ? date.slice(0, 4) : undefined,
  };
}

async function addonItem(item: StremioCatalogItem): Promise<CollectionItem | null> {
  const media = item.type === 'series' || item.type === 'tv' ? 'tv' : 'movie';
  let tmdbId = item.tmdbId;
  const imdbId = item.imdbId ?? (item.id.startsWith('tt') ? item.id.split(':')[0] : undefined);
  if (!tmdbId && imdbId) {
    const hit = await traktLookupId('imdb', imdbId, media === 'tv' ? 'show' : 'movie').catch(() => null);
    tmdbId = (media === 'tv' ? hit?.show : hit?.movie)?.ids?.tmdb;
  }
  if (!tmdbId) return null;
  return {
    id: `tmdb:${media}:${tmdbId}`,
    title: item.name,
    image: item.poster,
    backdrop: item.background,
    subtitle: item.year ? String(item.year) : undefined,
  };
}

const NON_FICTION = new Set([99, 10763, 10764, 10767]);

function personCredits(data: any, credits: PersonCredits, order: PersonOrder): any[] {
  const cast: any[] = data?.cast || [];
  const crew: any[] = data?.crew || [];
  let source: any[];
  switch (credits) {
    case 'acting': source = cast; break;
    case 'directing': source = crew.filter((credit) => credit.job === 'Director'); break;
    case 'allCrew': source = crew; break;
    case 'knownFor':
      source = [...cast, ...crew]
        .filter((credit) => !credit.genre_ids?.some((genre: number) => NON_FICTION.has(genre)))
        .sort((a, b) => (b.vote_count ?? 0) - (a.vote_count ?? 0))
        .slice(0, 40);
      break;
  }
  const dateOf = (credit: any): string => credit.release_date || credit.first_air_date || '';
  const seen = new Set<string>();
  const unique = source.filter((credit) => {
    const key = `${credit.media_type}:${credit.id}`;
    if (seen.has(key) || !credit.poster_path) return false;
    seen.add(key);
    return true;
  });
  if (order === 'popularity') return unique.sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0));
  const direction = order === 'newest' ? -1 : 1;
  return unique.sort((a, b) => dateOf(a).localeCompare(dateOf(b)) * direction);
}

/** One page of a source. `cursor` comes from the previous page's `nextCursor`. */
export async function fetchSourcePage(source: CollectionSource, cursor?: number): Promise<CollectionSourcePage> {
  switch (source.kind) {
    case 'addonCatalog': {
      const catalogs = await getCatalogs();
      const matches = catalogs.filter((catalog) => catalog.type === source.type && catalog.id === source.catalogId);
      const catalog = matches.find((c) => c.installationId === source.installationId) ?? matches.find((c) => c.addonName === source.addonName);
      if (!catalog) throw new Error(`${source.addonName} isn't installed any more, or no longer offers this catalog.`);
      const skip = cursor ?? 0;
      const page = await getCatalogItems(catalog, { skip });
      const mapped = await inBatches(page, addonItem);
      // Addons report no totals, so paging stops at an empty page.
      const hasMore = catalog.supportsSkip && page.length > 0;
      return { items: mapped.filter((item): item is CollectionItem => !!item), nextCursor: hasMore ? skip + page.length : null };
    }
    case 'tmdbDiscover': {
      const page = cursor ?? 1;
      const params = discoverParams(source.filters, page);
      const media = source.filters.mediaType;
      const data: any = await (media === 'tv' ? tmdbDiscoverTV('', params) : tmdbDiscoverMovies('', params));
      return {
        items: (data.results || []).map((result: any) => tmdbItem(result, media)),
        nextCursor: page < (data.total_pages ?? page) ? page + 1 : null,
      };
    }
    case 'tmdbCollection': {
      const data: any = await tmdbCollection(source.id);
      const parts = [...(data?.parts || [])].sort((a: any, b: any) => (a.release_date || '9').localeCompare(b.release_date || '9'));
      return { items: parts.map((part: any) => tmdbItem(part, 'movie')), nextCursor: null };
    }
    case 'person': {
      const data: any = await tmdbPersonCombined('', source.id);
      return {
        items: personCredits(data, source.credits, source.order).map((credit) => tmdbItem(credit, credit.media_type === 'tv' ? 'tv' : 'movie')),
        nextCursor: null,
      };
    }
    case 'traktList': {
      const page = cursor ?? 1;
      const data = await getPublicListItems(source.id, page, 50);
      const base = listEntriesToItems(data.items);
      const items = await inBatches(base, async (item): Promise<CollectionItem> => {
        const [, media, id] = item.id.split(':');
        const details: any = await tmdbDetails('', media as 'movie' | 'tv', id).catch(() => null);
        return { ...item, image: tmdbImage(details?.poster_path, 'w500'), backdrop: tmdbImage(details?.backdrop_path, 'w780') };
      });
      return { items, nextCursor: page < data.pageCount ? page + 1 : null };
    }
  }
}

export function sourceSummary(source: CollectionSource): string {
  switch (source.kind) {
    case 'addonCatalog': return `${source.addonName} · ${source.displayName}`;
    case 'tmdbDiscover': return `TMDB discover · ${source.label}`;
    case 'tmdbCollection': return `TMDB collection · ${source.name}`;
    case 'person': return `${source.name} · ${{ knownFor: 'Known for', acting: 'Acting', directing: 'Directing', allCrew: 'All crew work' }[source.credits]}`;
    case 'traktList': return `Trakt list · ${source.name}`;
  }
}
