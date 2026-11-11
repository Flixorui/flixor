/**
 * Data for the Netflix-style New & Hot page: one list in four sections (Coming Soon,
 * Everyone's Watching, Top 10 Shows, Top 10 Movies), and the details each card shows
 * (title logo, textless backdrop, age rating, meta line, trailer), fetched a few at a time
 * with one TMDB request per title and kept in memory.
 */

import { getFlixorCore } from './index';
import { cachedSections } from './top10/Top10Store';

export type NewHotSection = 'coming' | 'watching' | 'top-shows' | 'top-movies';

export const SECTIONS: Array<{ id: NewHotSection; label: string }> = [
  { id: 'coming', label: 'Coming Soon' },
  { id: 'watching', label: "Everyone's Watching" },
  { id: 'top-shows', label: 'Top 10 Shows' },
  { id: 'top-movies', label: 'Top 10 Movies' },
];

export type FeedItem = {
  key: string; // unique across sections
  section: NewHotSection;
  tmdbId: number;
  mediaType: 'movie' | 'tv';
  title: string;
  backdrop?: string;
  overview?: string;
  /** yyyy-mm-dd, for Coming Soon. */
  releaseDate?: string;
  rank?: number;
};

export type CardDetails = {
  logo?: string;
  backdrop?: string;
  overview?: string;
  rating?: string;
  meta?: string;
  trailerKey?: string;
};

const DAY = 86400000;
const isoDay = (offset = 0) => new Date(Date.now() + offset * DAY).toISOString().slice(0, 10);

function fromTmdb(r: any, mediaType: 'movie' | 'tv', section: NewHotSection, rank?: number): FeedItem | null {
  const core = getFlixorCore();
  if (!r?.id) return null;
  return {
    key: `${section}:${mediaType}:${r.id}`,
    section,
    tmdbId: r.id,
    mediaType,
    title: r.title || r.name || 'Untitled',
    backdrop: r.backdrop_path ? core.tmdb.getBackdropUrl(r.backdrop_path, 'w780') : undefined,
    overview: r.overview || undefined,
    releaseDate: r.release_date || r.first_air_date || undefined,
    rank,
  };
}

/** Upcoming movies and new shows, soonest first. */
async function comingSoon(): Promise<FeedItem[]> {
  const core = getFlixorCore();
  const tomorrow = isoDay(1);
  const [upcoming, anticipated, tv] = await Promise.all([
    core.tmdb.getUpcomingMovies().catch(() => null),
    core.tmdb.discoverMovies({ sortBy: 'popularity.desc', dateFrom: tomorrow } as any).catch(() => null),
    core.tmdb.discoverTV({ sortBy: 'popularity.desc', dateFrom: tomorrow } as any).catch(() => null),
  ]);
  const seen = new Set<string>();
  const items: FeedItem[] = [];
  const add = (list: any[] | undefined, type: 'movie' | 'tv') => {
    for (const r of list ?? []) {
      const date = r.release_date || r.first_air_date;
      if (!date || date < tomorrow || !r.backdrop_path) continue;
      const id = `${type}:${r.id}`;
      if (seen.has(id)) continue;
      seen.add(id);
      const item = fromTmdb(r, type, 'coming');
      if (item) items.push(item);
    }
  };
  add(upcoming?.results, 'movie');
  add(anticipated?.results, 'movie');
  add(tv?.results?.slice(0, 10), 'tv');
  return items.sort((a, b) => (a.releaseDate ?? '').localeCompare(b.releaseDate ?? '')).slice(0, 20);
}

async function everyonesWatching(): Promise<FeedItem[]> {
  const core = getFlixorCore();
  const res = await core.tmdb.getTrendingAll('week').catch(() => null);
  return (res?.results ?? [])
    .filter((r: any) => (r.media_type === 'movie' || r.media_type === 'tv') && r.backdrop_path)
    .slice(0, 20)
    .map((r: any) => fromTmdb(r, r.media_type, 'watching'))
    .filter(Boolean) as FeedItem[];
}

/**
 * Top 10 from the user's FlixPatrol / Streaming Availability Netflix chart when one is
 * saved (Settings > Top 10 Lists), else TMDB's weekly trending.
 */
async function top10(kind: 'tv' | 'movie'): Promise<FeedItem[]> {
  const section: NewHotSection = kind === 'tv' ? 'top-shows' : 'top-movies';
  try {
    const saved = await cachedSections();
    const chart = saved.find((s) => s.id === `sa-top-netflix-${kind === 'tv' ? 'series' : 'movie'}`);
    if (chart && chart.items.length >= 5) {
      return chart.items.slice(0, 10).map((i, index) => ({
        key: `${section}:${i.mediaType}:${i.tmdbId}`,
        section,
        tmdbId: i.tmdbId,
        mediaType: i.mediaType,
        title: i.title,
        backdrop: i.backdrop,
        rank: index + 1,
      }));
    }
  } catch {
    // fall back to TMDB
  }
  const core = getFlixorCore();
  const res = await (kind === 'tv' ? core.tmdb.getTrendingTV('week') : core.tmdb.getTrendingMovies('week')).catch(() => null);
  return (res?.results ?? [])
    .slice(0, 10)
    .map((r: any, index: number) => fromTmdb(r, kind, section, index + 1))
    .filter(Boolean) as FeedItem[];
}

let feedCache: { at: number; items: FeedItem[] } | null = null;

export async function loadNewHotFeed(force = false): Promise<FeedItem[]> {
  if (!force && feedCache && Date.now() - feedCache.at < 30 * 60 * 1000) return feedCache.items;
  const [a, b, c, d] = await Promise.all([comingSoon(), everyonesWatching(), top10('tv'), top10('movie')]);
  const items = [...a, ...b, ...c, ...d];
  feedCache = { at: Date.now(), items };
  return items;
}

export const cachedFeed = () => feedCache?.items ?? null;

// ---------------------------------------------------------------- card details

const details = new Map<string, CardDetails>();
const pending = new Map<string, Promise<CardDetails>>();

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/** "Thursday" within the coming week, else "18 November". */
function when(date: string): string {
  const d = new Date(`${date}T12:00:00`);
  const days = Math.round((d.getTime() - Date.now()) / DAY);
  if (days >= 0 && days < 7) return WEEKDAYS[d.getDay()];
  return `${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

function rating(data: any, mediaType: 'movie' | 'tv'): string | undefined {
  if (mediaType === 'movie') {
    const us = data?.release_dates?.results?.find((r: any) => r.iso_3166_1 === 'US');
    const cert = us?.release_dates?.map((x: any) => x.certification).find((c: string) => !!c);
    return cert || undefined;
  }
  const us = data?.content_ratings?.results?.find((r: any) => r.iso_3166_1 === 'US');
  return us?.rating || undefined;
}

function metaLine(item: FeedItem, data: any): string | undefined {
  if (item.section === 'coming') {
    if (item.mediaType === 'tv') {
      const next = data?.next_episode_to_air;
      if (next?.air_date && next.season_number > 1) return `Season ${next.season_number} coming on ${when(next.air_date)}`;
    }
    return item.releaseDate ? `Coming on ${when(item.releaseDate)}` : undefined;
  }
  if (item.mediaType === 'tv') {
    const next = data?.next_episode_to_air;
    if (next?.air_date && next.air_date >= isoDay(0)) return `New Episode ${when(next.air_date)}`;
    const seasons = data?.number_of_seasons;
    if (seasons > 1) return `Watch Season ${seasons} now`;
  }
  return undefined;
}

function pickTrailer(data: any): string | undefined {
  const videos = (data?.videos?.results ?? []).filter((v: any) => v.site === 'YouTube');
  const order = ['Trailer', 'Teaser', 'Clip'];
  videos.sort((a: any, b: any) => {
    if (a.official !== b.official) return a.official ? -1 : 1;
    return order.indexOf(a.type) - order.indexOf(b.type);
  });
  return videos.find((v: any) => order.includes(v.type))?.key;
}

export const getCardDetails = (item: FeedItem) => details.get(`${item.mediaType}:${item.tmdbId}`);

// A few requests at a time, so a page of 60 cards doesn't fire 60 at once
let running = 0;
const queue: Array<() => void> = [];
function limited<T>(task: () => Promise<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    const run = () => {
      running += 1;
      task().then(resolve, reject).finally(() => {
        running -= 1;
        queue.shift()?.();
      });
    };
    if (running < 4) run();
    else queue.push(run);
  });
}

export function fetchCardDetails(item: FeedItem): Promise<CardDetails> {
  const id = `${item.mediaType}:${item.tmdbId}`;
  const have = details.get(id);
  if (have) return Promise.resolve(have);
  const inflight = pending.get(id);
  if (inflight) return inflight;
  const task = (async () => {
    const core = getFlixorCore();
    try {
      const data: any = await limited<any>(() => (core.tmdb as any).getNewHotDetails(item.mediaType, item.tmdbId));
      const logos: any[] = data?.images?.logos ?? [];
      const logo = logos.find((l) => l.iso_639_1 === 'en') ?? logos[0];
      // Textless backdrop: the title shows as the logo underneath
      const backdrops: any[] = data?.images?.backdrops ?? [];
      const textless = backdrops.find((b) => b.iso_639_1 == null);
      const result: CardDetails = {
        logo: logo?.file_path ? core.tmdb.getImageUrl(logo.file_path, 'w500') : undefined,
        backdrop: textless?.file_path ? core.tmdb.getBackdropUrl(textless.file_path, 'w780') : undefined,
        overview: data?.overview || undefined,
        rating: rating(data, item.mediaType),
        meta: metaLine(item, data),
        trailerKey: pickTrailer(data),
      };
      details.set(id, result);
      return result;
    } catch {
      const result: CardDetails = { meta: metaLine(item, null) };
      details.set(id, result);
      return result;
    } finally {
      pending.delete(id);
    }
  })();
  pending.set(id, task);
  return task;
}
