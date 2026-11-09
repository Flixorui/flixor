/**
 * Clients for the community skip-segment databases.
 * macOS reference: Services/SkipSegments/{IntroDB,AniSkip,AnimeSkip,AnimeIdMapping}Client.swift
 */

import { getJson, parseInteger, parseSeconds, parseString, postJson } from './http';
import { isValidSegment, type SkipSegment, type SkipSegmentType } from './types';

const INTRODB_URL = 'https://api.introdb.app';
const ANISKIP_URL = 'https://api.aniskip.com/v2';
const ARM_URL = 'https://arm.haglund.dev/api/v2';
const ANIME_SKIP_URL = 'https://api.anime-skip.com/graphql';

function query(params: Array<[string, string]>): string {
  return params.map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`).join('&');
}

// IntroDB: intro, recap, outro and post-credits timings keyed by IMDb id.

export function parseIntroDb(json: any, isMovie: boolean): SkipSegment[] {
  if (!json || typeof json !== 'object') return [];
  const fields: Array<[string, SkipSegmentType]> = [
    ['intro', 'intro'],
    ['recap', 'recap'],
    ['outro', 'credits'],
    ['post_credits', 'postcredits'],
  ];
  const segments: SkipSegment[] = [];
  for (const [key, type] of fields) {
    const raw = json[key];
    if (!raw || typeof raw !== 'object') continue;
    const startMs = parseSeconds(raw.start_ms);
    const endMs = parseSeconds(raw.end_ms);
    const start = parseSeconds(raw.start_sec) ?? (startMs !== null ? startMs / 1000 : null);
    const end = parseSeconds(raw.end_sec) ?? (endMs !== null ? endMs / 1000 : null);
    if (start === null || end === null) continue;
    const segment: SkipSegment = { type, start, end, provider: 'introdb' };
    if (isValidSegment(segment)) segments.push(segment);
  }
  // Movies only use end credits and the post-credits scene.
  return isMovie ? segments.filter((item) => item.type === 'credits' || item.type === 'postcredits') : segments;
}

export async function fetchIntroDbEpisode(imdbId: string, season: number, episode: number): Promise<SkipSegment[]> {
  const json = await getJson(
    `${INTRODB_URL}/segments?${query([
      ['imdb_id', imdbId],
      ['season', String(season)],
      ['episode', String(episode)],
    ])}`
  );
  return parseIntroDb(json, false);
}

export async function fetchIntroDbMovie(imdbId: string): Promise<SkipSegment[]> {
  const json = await getJson(
    `${INTRODB_URL}/segments?${query([
      ['imdb_id', imdbId],
      ['is_movie', 'true'],
    ])}`
  );
  return parseIntroDb(json, true);
}

// AniSkip: anime timings keyed by MyAnimeList id and episode number.

export function parseAniSkip(json: any): SkipSegment[] {
  if (json?.found !== true || !Array.isArray(json.results)) return [];
  const segments: SkipSegment[] = [];
  for (const result of json.results) {
    const skipType = String(result?.skipType || '').toLowerCase();
    const start = parseSeconds(result?.interval?.startTime);
    const end = parseSeconds(result?.interval?.endTime);
    const type: SkipSegmentType | null =
      skipType === 'op' || skipType === 'mixed-op'
        ? 'intro'
        : skipType === 'ed' || skipType === 'mixed-ed'
          ? 'credits'
          : skipType === 'recap'
            ? 'recap'
            : null;
    if (!type || start === null || end === null) continue;
    const segment: SkipSegment = { type, start, end, provider: 'aniskip' };
    if (isValidSegment(segment)) segments.push(segment);
  }
  return segments;
}

export async function fetchAniSkip(malId: string, episode: number): Promise<SkipSegment[]> {
  const types = ['op', 'ed', 'recap', 'mixed-op', 'mixed-ed'].map((type): [string, string] => ['types', type]);
  const json = await getJson(
    `${ANISKIP_URL}/skip-times/${encodeURIComponent(malId)}/${episode}?${query([...types, ['episodeLength', '0']])}`
  );
  return parseAniSkip(json);
}

// ARM: maps TMDB, IMDb and Kitsu ids to MyAnimeList and AniList. No match means not anime.

export interface AnimeIds {
  malId?: string;
  anilistId?: string;
}

function toAnimeIds(entry: any): AnimeIds | null {
  const malId = parseString(entry?.myanimelist) ?? undefined;
  const anilistId = parseString(entry?.anilist) ?? undefined;
  return malId || anilistId ? { malId, anilistId } : null;
}

async function armLookup(path: string, id: string): Promise<any[]> {
  const json = await getJson(
    `${ARM_URL}/${path}?${query([
      ['id', id],
      ['include', 'myanimelist,anilist,themoviedb-season,thetvdb-season'],
    ])}`
  );
  if (Array.isArray(json)) return json;
  return json && typeof json === 'object' ? [json] : [];
}

/**
 * Anime ids for one season of a show. TMDB and IMDb map one show to several anime
 * entries, so only an unambiguous match is returned.
 */
export async function animeIdsForShow(
  tmdbId: number | undefined,
  imdbId: string | undefined,
  season: number
): Promise<AnimeIds | null> {
  let entries = tmdbId ? await armLookup('themoviedb', String(tmdbId)) : [];
  if (entries.length === 0 && imdbId) {
    entries = await armLookup('imdb', imdbId);
  }
  if (entries.length === 0) return null;

  const tagged = entries.filter(
    (entry) =>
      parseInteger(entry?.['themoviedb-season']) === season || parseInteger(entry?.['thetvdb-season']) === season
  );
  if (tagged.length === 1) return toAnimeIds(tagged[0]);
  if (tagged.length === 0 && entries.length === 1 && season === 1) return toAnimeIds(entries[0]);
  return null;
}

/** Anime ids for an id from an anime database (kitsu, myanimelist). */
export async function animeIdsFromSource(source: string, id: string): Promise<AnimeIds | null> {
  const json = await getJson(
    `${ARM_URL}/ids?${query([
      ['source', source],
      ['id', id],
      ['include', 'myanimelist,anilist'],
    ])}`
  );
  return toAnimeIds(json);
}

// Anime-Skip: GraphQL API that needs the user's own client id.

async function animeSkipQuery(clientId: string, graphql: string): Promise<any> {
  const json = await postJson(ANIME_SKIP_URL, { query: graphql }, { 'X-Client-ID': clientId });
  return json?.data;
}

export async function fetchAnimeSkipShowIds(clientId: string, anilistId: string): Promise<string[]> {
  if (!/^\d+$/.test(anilistId)) return [];
  const data = await animeSkipQuery(
    clientId,
    `{ findShowsByExternalId(service: ANILIST, serviceId: "${anilistId}") { id } }`
  );
  const shows = Array.isArray(data?.findShowsByExternalId) ? data.findShowsByExternalId : [];
  return shows.map((show: any) => parseString(show?.id)).filter(Boolean) as string[];
}

/**
 * Anime-Skip stores only where each segment starts; a segment ends where the next
 * begins. Only an ending or preview in the second half may run to the end of the file.
 */
export function animeSkipSegments(
  timestamps: Array<{ at: number; name: string }>,
  baseDuration: number | null
): SkipSegment[] {
  const sorted = [...timestamps].sort((left, right) => left.at - right.at);
  const result: SkipSegment[] = [];
  sorted.forEach((stamp, index) => {
    const name = stamp.name.toLowerCase();
    const type: SkipSegmentType | null =
      name === 'intro' || name === 'new intro' || name === 'mixed intro'
        ? 'intro'
        : name === 'credits' || name === 'new credits' || name === 'mixed credits'
          ? 'credits'
          : name === 'recap'
            ? 'recap'
            : name === 'preview'
              ? 'preview'
              : null;
    if (!type) return;

    let end: number | null;
    if (index + 1 < sorted.length) {
      const next = sorted[index + 1].at;
      if (next <= stamp.at) return;
      end = next;
    } else if ((type === 'credits' || type === 'preview') && (baseDuration === null || stamp.at >= baseDuration / 2)) {
      end = null;
    } else {
      return;
    }

    const segment: SkipSegment = { type, start: stamp.at, end, provider: 'animeskip' };
    if (isValidSegment(segment)) result.push(segment);
  });
  return result;
}

/** Several community entries can exist for one episode; the one covering the most types wins. */
export async function fetchAnimeSkipSegments(
  clientId: string,
  showId: string,
  episode: number
): Promise<SkipSegment[]> {
  if (!/^[a-zA-Z0-9-]+$/.test(showId)) return [];
  const data = await animeSkipQuery(
    clientId,
    `{ findEpisodesByShowId(showId: "${showId}") { season number baseDuration timestamps { at type { name } } } }`
  );
  const episodes = Array.isArray(data?.findEpisodesByShowId) ? data.findEpisodesByShowId : [];

  let best: SkipSegment[] = [];
  const coverage = (segments: SkipSegment[]) => new Set(segments.map((item) => item.type)).size;
  for (const entry of episodes) {
    if (parseInteger(entry?.number) !== episode) continue;
    const timestamps = (Array.isArray(entry?.timestamps) ? entry.timestamps : [])
      .map((raw: any) => ({ at: parseSeconds(raw?.at), name: raw?.type?.name }))
      .filter((raw: any) => raw.at !== null && typeof raw.name === 'string');
    const segments = animeSkipSegments(timestamps, parseSeconds(entry?.baseDuration));
    if (
      coverage(segments) > coverage(best) ||
      (coverage(segments) === coverage(best) && segments.length > best.length)
    ) {
      best = segments;
    }
  }
  return best;
}
