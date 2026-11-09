import { useEffect, useMemo, useState } from 'react';
import {
  convertPlexItemsToHero,
  getTmdbLogo,
  getTmdbOverview,
  getTmdbTextlessBackdrop,
  getTmdbTextlessPoster,
  type HeroItem,
  type RowItem,
} from '../../core/HomeData';
import { HOME_PLEX_WATCHLIST_ROW_ID, HOME_TRAKT_WATCHLIST_ROW_ID } from '../../core/HomeRowsStore';
import type { HomeHeroSource } from '../../core/SettingsData';
import type { ContinueWatchingEntry } from '../../core/TraktContinueWatching';
import { fetchCatalogRowItems, type HomeRowModel } from './homeRowModels';

/** Rows that feed the default hero when there is no Plex library, in order. */
const DISCOVERY_FALLBACK_ROWS = ['popular-on-plex', 'trending-movies', 'trending-week'];
const ENRICH_CONCURRENCY = 3;

interface Candidate extends RowItem {
  plex?: ContinueWatchingEntry['plex'];
}

const enrichedCache = new Map<string, HeroItem>();

async function enrich(candidate: Candidate): Promise<HeroItem> {
  const cached = enrichedCache.get(candidate.id);
  if (cached) return cached;

  let hero: HeroItem = {
    id: candidate.id,
    title: candidate.title,
    image: candidate.image,
    backdrop: candidate.backdrop,
    mediaType: candidate.mediaType,
  };

  if (candidate.plex) {
    const [converted] = await convertPlexItemsToHero([candidate.plex], 1);
    if (converted) hero = converted;
  } else {
    const match = candidate.id.match(/^tmdb:(movie|tv):(\d+)/);
    if (match) {
      const mediaType = match[1] as 'movie' | 'tv';
      const tmdbId = Number(match[2]);
      hero.id = `tmdb:${mediaType}:${tmdbId}`;
      const [poster, backdrop, logo, overview] = await Promise.all([
        getTmdbTextlessPoster(tmdbId, mediaType).catch(() => null),
        getTmdbTextlessBackdrop(tmdbId, mediaType).catch(() => null),
        getTmdbLogo(tmdbId, mediaType).catch(() => null),
        getTmdbOverview(tmdbId, mediaType).catch(() => null),
      ]);
      if (poster) hero.image = poster;
      if (backdrop) hero.backdrop = backdrop;
      if (logo) hero.logo = logo;
      if (overview) hero.description = overview;
    }
  }

  enrichedCache.set(candidate.id, hero);
  return hero;
}

async function enrichAll(candidates: Candidate[]): Promise<HeroItem[]> {
  const results: HeroItem[] = [];
  let next = 0;
  const worker = async () => {
    while (next < candidates.length) {
      const index = next++;
      results[index] = await enrich(candidates[index]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(ENRICH_CONCURRENCY, candidates.length) }, worker));
  return results;
}

function entryToCandidate(entry: ContinueWatchingEntry): Candidate {
  return {
    id: entry.plex
      ? `plex:${entry.plexRatingKey}`
      : `tmdb:${entry.mediaType === 'movie' ? 'movie' : 'tv'}:${entry.tmdbId}`,
    title: entry.title,
    image: entry.image,
    backdrop: entry.backdrop,
    mediaType: entry.mediaType === 'movie' ? 'movie' : 'tv',
    plex: entry.plex,
  };
}

function rowItems(models: HomeRowModel[], id: string): RowItem[] {
  const model = models.find((row) => row.id === id);
  return model?.type === 'items' ? model.items : [];
}

/**
 * Hero items for the chosen source. Null means use the default Plex hero, which is
 * also what happens when the chosen source has nothing to show.
 */
export function useHeroOverride(
  source: HomeHeroSource,
  entries: ContinueWatchingEntry[],
  models: HomeRowModel[],
  hasPlexHero: boolean,
  limit: number
): HeroItem[] | null {
  const catalogRow = useMemo(() => {
    if (!source.startsWith('row:')) return null;
    const model = models.find((row) => row.id === source.slice(4));
    return model?.type === 'catalog' ? model : null;
  }, [source, models]);
  const catalog = catalogRow?.catalog;

  const [catalogItems, setCatalogItems] = useState<RowItem[]>([]);
  useEffect(() => {
    setCatalogItems([]);
    if (!catalog) return;
    let active = true;
    fetchCatalogRowItems(catalog)
      .then((items) => {
        if (active) setCatalogItems(items);
      })
      .catch((e) => console.log('[Home] Hero catalog failed:', e));
    return () => {
      active = false;
    };
  }, [catalog]);

  const candidates = useMemo<Candidate[]>(() => {
    let list: Candidate[] = [];
    if (source === 'continueWatching') {
      list = entries.map(entryToCandidate);
    } else if (source === 'myList') {
      const seen = new Set<string>();
      list = [...rowItems(models, HOME_PLEX_WATCHLIST_ROW_ID), ...rowItems(models, HOME_TRAKT_WATCHLIST_ROW_ID)].filter(
        (item) => {
          if (seen.has(item.id)) return false;
          seen.add(item.id);
          return true;
        }
      );
    } else if (source.startsWith('row:')) {
      list = catalog ? catalogItems : rowItems(models, source.slice(4));
    }
    if (list.length === 0 && !hasPlexHero) {
      for (const rowId of DISCOVERY_FALLBACK_ROWS) {
        list = rowItems(models, rowId);
        if (list.length > 0) break;
      }
    }
    return list.slice(0, limit);
  }, [source, entries, models, catalog, catalogItems, hasPlexHero, limit]);

  const key = candidates.map((candidate) => candidate.id).join('|');
  const [state, setState] = useState<{ key: string; items: HeroItem[] }>({ key: '', items: [] });

  useEffect(() => {
    if (!key) return;
    let active = true;
    enrichAll(candidates)
      .then((items) => {
        if (active) setState({ key, items });
      })
      .catch((e) => console.log('[Home] Hero enrichment failed:', e));
    return () => {
      active = false;
    };
    // `key` identifies the candidates.
  }, [key]);

  return key && state.key === key && state.items.length > 0 ? state.items : null;
}
