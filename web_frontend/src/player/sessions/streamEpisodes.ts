import { tmdbImage, tmdbTvSeasonDetails, tmdbTvSeasons } from '@/services/tmdb';
import type { StremioContentIdentity } from '@/stremio';
import { lookupTmdbId } from '@/stremio/transport';

export interface StreamEpisode {
  season: number;
  episode: number;
  title: string;
  overview?: string;
  still?: string;
  hasAired: boolean;
}

interface CinemetaMeta {
  name?: string;
  videos?: Array<{
    season?: number;
    episode?: number;
    number?: number;
    name?: string;
    title?: string;
    overview?: string;
    description?: string;
    thumbnail?: string;
    released?: string;
  }>;
}

const CINEMETA = 'https://v3-cinemeta.strem.io/meta';
const metaCache = new Map<string, Promise<CinemetaMeta | null>>();

function isAired(date?: string): boolean {
  if (!date) return true;
  const time = new Date(date).getTime();
  return Number.isNaN(time) || time <= Date.now();
}

/** Addon meta from Cinemeta, for titles known only by IMDb id. */
export function cinemetaMeta(type: 'movie' | 'series', imdbId: string): Promise<CinemetaMeta | null> {
  const key = `${type}:${imdbId}`;
  let pending = metaCache.get(key);
  if (!pending) {
    pending = fetch(`${CINEMETA}/${type}/${encodeURIComponent(imdbId)}.json`)
      .then((res) => (res.ok ? res.json() : null))
      .then((json) => json?.meta ?? null)
      .catch(() => null);
    metaCache.set(key, pending);
  }
  return pending;
}

async function tmdbIdFor(identity: StremioContentIdentity): Promise<number | null> {
  if (identity.tmdbId) return identity.tmdbId;
  if (!identity.imdbId) return null;
  return lookupTmdbId(identity.imdbId, 'series').catch(() => null);
}

async function cinemetaEpisodes(identity: StremioContentIdentity): Promise<StreamEpisode[]> {
  if (!identity.imdbId) return [];
  const meta = await cinemetaMeta('series', identity.imdbId);
  return (meta?.videos ?? [])
    .filter((video) => video.season !== undefined && (video.episode ?? video.number) !== undefined)
    .map((video) => ({
      season: Number(video.season),
      episode: Number(video.episode ?? video.number),
      title: video.name || video.title || `Episode ${video.episode ?? video.number}`,
      overview: video.overview || video.description,
      still: video.thumbnail,
      hasAired: isAired(video.released),
    }));
}

/** Season numbers of the series, regular seasons first and specials last. */
export async function streamSeasonNumbers(identity: StremioContentIdentity): Promise<number[]> {
  const tmdbId = await tmdbIdFor(identity);
  let numbers: number[] = [];
  if (tmdbId) {
    const details: any = await tmdbTvSeasons('', tmdbId).catch(() => null);
    numbers = (details?.seasons ?? [])
      .filter((season: any) => (season.episode_count ?? 0) > 0)
      .map((season: any) => Number(season.season_number));
  }
  if (numbers.length === 0) {
    numbers = [...new Set((await cinemetaEpisodes(identity)).map((episode) => episode.season))];
  }
  return [...numbers.filter((n) => n > 0).sort((a, b) => a - b), ...numbers.filter((n) => n === 0)];
}

/** All episodes of one season, in order. */
export async function streamSeasonEpisodes(identity: StremioContentIdentity, season: number): Promise<StreamEpisode[]> {
  const tmdbId = await tmdbIdFor(identity);
  if (tmdbId) {
    const details: any = await tmdbTvSeasonDetails('', tmdbId, season).catch(() => null);
    const episodes: StreamEpisode[] = (details?.episodes ?? []).map((ep: any) => ({
      season,
      episode: Number(ep.episode_number),
      title: ep.name || `Episode ${ep.episode_number}`,
      overview: ep.overview,
      still: ep.still_path ? tmdbImage(ep.still_path, 'w500') : undefined,
      hasAired: isAired(ep.air_date),
    }));
    if (episodes.length > 0) return episodes.sort((a, b) => a.episode - b.episode);
  }
  return (await cinemetaEpisodes(identity))
    .filter((episode) => episode.season === season)
    .sort((a, b) => a.episode - b.episode);
}
