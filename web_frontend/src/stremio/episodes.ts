/** Next episode for addon series, ported from StreamEpisodeNavigator.swift. */
import { tmdbTvSeasonDetails, tmdbTvSeasons } from '@/services/tmdb';
import { getSettings } from '@/state/settings';
import { addonSupportsResource, listInstalledAddons } from './addons';
import { addonResourceUrl } from './streams';
import { fetchAddonJson, lookupTmdbId } from './transport';
import type { StremioContentIdentity, StremioRequestOptions } from './types';

export interface StreamEpisodeInfo {
  season: number;
  episode: number;
  title: string;
  overview?: string;
  stillUrl?: string;
  airDate?: string;
  runtimeMinutes?: number;
  hasAired: boolean;
}

const airedByDate = (date?: string) => Boolean(date) && new Date(date as string).getTime() <= Date.now();

function tmdbEpisode(raw: any, season: number): StreamEpisodeInfo | null {
  if (typeof raw?.episode_number !== 'number') return null;
  return {
    season,
    episode: raw.episode_number,
    title: raw.name || `Episode ${raw.episode_number}`,
    overview: raw.overview || undefined,
    stillUrl: raw.still_path ? `https://image.tmdb.org/t/p/w780${raw.still_path}` : undefined,
    airDate: raw.air_date || undefined,
    runtimeMinutes: raw.runtime || undefined,
    hasAired: airedByDate(raw.air_date),
  };
}

function nextFromSeason(list: StreamEpisodeInfo[], episode: number): StreamEpisodeInfo | undefined {
  return list.filter((item) => item.episode > episode).sort((a, b) => a.episode - b.episode)[0];
}

async function nextFromTmdb(
  tmdbId: number,
  season: number,
  episode: number,
): Promise<StreamEpisodeInfo | null | undefined> {
  const key = getSettings().tmdbBearer ?? '';
  const seasonDetails: any = await tmdbTvSeasonDetails(key, tmdbId, season);
  const current = (seasonDetails?.episodes ?? []).flatMap((raw: any) => tmdbEpisode(raw, season) ?? []);
  if (current.length === 0) return undefined;

  const next = nextFromSeason(current, episode);
  if (next) return next.hasAired ? next : null;
  if (season <= 0) return null; // Specials never roll over into season 1.

  const showDetails: any = await tmdbTvSeasons(key, tmdbId);
  const nextSeason = (showDetails?.seasons ?? [])
    .filter((item: any) => item.season_number > season && (item.episode_count ?? 0) > 0)
    .map((item: any) => item.season_number as number)
    .sort((a: number, b: number) => a - b)[0];
  if (nextSeason === undefined) return null;

  const upcoming: any = await tmdbTvSeasonDetails(key, tmdbId, nextSeason);
  const first = (upcoming?.episodes ?? [])
    .flatMap((raw: any) => tmdbEpisode(raw, nextSeason) ?? [])
    .sort((a: StreamEpisodeInfo, b: StreamEpisodeInfo) => a.episode - b.episode)[0];
  return first?.hasAired ? first : null;
}

async function nextFromAddonMeta(
  identity: StremioContentIdentity,
  season: number,
  episode: number,
  signal: AbortSignal | undefined,
): Promise<StreamEpisodeInfo | null> {
  for (const addon of listInstalledAddons()) {
    if (!addonSupportsResource(addon, 'meta', 'series', identity.baseId)) continue;
    try {
      const path = `/meta/series/${encodeURIComponent(identity.baseId)}.json`;
      const data = await fetchAddonJson<{ meta?: { videos?: any[] } }>(addonResourceUrl(addon, path), {
        signal,
        timeoutMs: 20_000,
      });
      const videos = (data?.meta?.videos ?? [])
        .map((video) => ({
          season: Number(video?.season),
          episode: Number(video?.episode ?? video?.number),
          title: video?.title || video?.name || `Episode ${video?.episode ?? video?.number}`,
          overview: video?.overview || video?.description || undefined,
          stillUrl: video?.thumbnail || undefined,
          airDate: video?.released || undefined,
          hasAired: !video?.released || airedByDate(video.released),
        }))
        .filter((video) => Number.isFinite(video.season) && Number.isFinite(video.episode))
        .sort((a, b) => a.season - b.season || a.episode - b.episode);
      if (videos.length === 0) continue;
      const next = videos.find(
        (video) =>
          (video.season === season && video.episode > episode) ||
          (season > 0 && video.season > season && video.season !== 0),
      );
      return next?.hasAired ? next : null;
    } catch (err) {
      if ((err as Error)?.name === 'AbortError') throw err;
    }
  }
  return null;
}

/**
 * The episode after `identity`, when it has aired: the next in the season, or the
 * first of the next season. TMDB first, then addon metadata for titles TMDB lacks.
 */
export async function getNextEpisode(
  identity: StremioContentIdentity,
  options: StremioRequestOptions = {},
): Promise<StreamEpisodeInfo | null> {
  const { seasonNumber: season, episodeNumber: episode } = identity;
  if (identity.requestType !== 'series' || season == null || episode == null) return null;

  try {
    const tmdbId =
      identity.tmdbId ??
      (identity.imdbId ? await lookupTmdbId(identity.imdbId, 'series', options.signal) : null);
    if (tmdbId) {
      const fromTmdb = await nextFromTmdb(tmdbId, season, episode);
      if (fromTmdb !== undefined) return fromTmdb;
    }
  } catch (err) {
    if ((err as Error)?.name === 'AbortError') throw err;
    // Fall through to addon metadata.
  }
  return nextFromAddonMeta(identity, season, episode, options.signal);
}
