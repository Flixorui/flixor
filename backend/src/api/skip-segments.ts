import { NextFunction, Request, Response, Router } from 'express';
import { AppError } from '../middleware/errorHandler';
import { createLogger } from '../utils/logger';
import { OutboundUrlError, safeFetch } from '../utils/outboundUrl';

// Mounted behind requireAuth in server.ts. Providers are fixed hosts, but every
// call still goes through safeFetch so redirects are checked the same way.
const router = Router();
const logger = createLogger('skip-segments');

type SegmentType = 'intro' | 'recap' | 'credits' | 'preview' | 'postcredits';
type Provider = 'introdb' | 'aniskip' | 'animeskip';

interface SkipSegment {
  type: SegmentType;
  start: number;
  /** Seconds. Null means it runs to the end of the file. */
  end: number | null;
  provider: Provider;
}

interface SegmentRequest {
  imdbId?: string;
  tmdbId?: number;
  isMovie: boolean;
  season?: number;
  episode?: number;
  kitsuId?: string;
  malId?: string;
}

interface AnimeIds {
  malId?: string;
  anilistId?: string;
}

const INTRODB_URL = 'https://api.introdb.app/segments';
const ANISKIP_URL = 'https://api.aniskip.com/v2';
const ARM_URL = 'https://arm.haglund.dev/api/v2';
const ANIME_SKIP_URL = 'https://api.anime-skip.com/graphql';

const FOUND_TTL_MS = 6 * 60 * 60 * 1000;
const EMPTY_TTL_MS = 30 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 8_000;
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const MAX_CACHE_ENTRIES = 5_000;

const cache = new Map<string, { segments: SkipSegment[]; expiresAt: number }>();
const inFlight = new Map<string, Promise<SkipSegment[]>>();
const animeIdCache = new Map<string, AnimeIds | null>();
const animeSkipShowIds = new Map<string, string[]>();
const blockedUntil = new Map<Provider, number>();

class RateLimited extends Error {
  constructor(readonly retryAfterMs: number) {
    super('rate limited');
  }
}

function rememberBounded<V>(map: Map<string, V>, key: string, value: V) {
  if (map.size >= MAX_CACHE_ENTRIES) {
    const oldest = map.keys().next().value;
    if (oldest !== undefined) map.delete(oldest);
  }
  map.set(key, value);
}

function toNumber(value: unknown): number | undefined {
  const parsed = typeof value === 'string' ? Number(value) : value;
  return typeof parsed === 'number' && Number.isFinite(parsed) ? parsed : undefined;
}

function toIdString(value: unknown): string | undefined {
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return undefined;
}

function isValid(segment: SkipSegment): boolean {
  if (!Number.isFinite(segment.start) || segment.start < 0) return false;
  return segment.end === null || (Number.isFinite(segment.end) && segment.end > segment.start);
}

async function requestJson(
  url: string,
  init?: { method: string; body: string; headers: Record<string, string> },
): Promise<any> {
  const res = await safeFetch(url, {
    method: init?.method ?? 'GET',
    body: init?.body,
    headers: { Accept: 'application/json', 'User-Agent': 'Flixor/1.0 (web)', ...init?.headers },
    timeoutMs: REQUEST_TIMEOUT_MS,
    maxBytes: MAX_BODY_BYTES,
  });
  if (res.status === 404) {
    res.abort();
    return null; // Most providers answer "unknown title" with 404.
  }
  if (res.status === 429) {
    res.abort();
    const header = res.headers['retry-after'];
    const seconds = toNumber(Array.isArray(header) ? header[0] : header) ?? 60;
    throw new RateLimited(Math.min(seconds * 1000, 15 * 60 * 1000));
  }
  if (res.status < 200 || res.status >= 300) {
    res.abort();
    throw new Error(`provider responded ${res.status}`);
  }
  return res.json();
}

/** Runs one provider call. Every failure degrades to "no segments". */
async function guarded(provider: Provider, run: () => Promise<SkipSegment[]>): Promise<SkipSegment[]> {
  const until = blockedUntil.get(provider);
  if (until && until > Date.now()) return [];
  try {
    return await run();
  } catch (error) {
    if (error instanceof RateLimited) {
      blockedUntil.set(provider, Date.now() + error.retryAfterMs);
      logger.warn(`Rate limited by ${provider}`);
    } else {
      logger.debug(`Lookup failed on ${provider}`, { code: (error as OutboundUrlError)?.code });
    }
    return [];
  }
}

function parseIntroDB(json: any, isMovie: boolean): SkipSegment[] {
  if (!json || typeof json !== 'object') return [];
  const fields: Array<[string, SegmentType]> = [
    ['intro', 'intro'],
    ['recap', 'recap'],
    ['outro', 'credits'],
    ['post_credits', 'postcredits'],
  ];
  const segments: SkipSegment[] = [];
  for (const [key, type] of fields) {
    const raw = json[key];
    if (!raw || typeof raw !== 'object') continue;
    const startMs = toNumber(raw.start_ms);
    const endMs = toNumber(raw.end_ms);
    const start = toNumber(raw.start_sec) ?? (startMs !== undefined ? startMs / 1000 : undefined);
    const end = toNumber(raw.end_sec) ?? (endMs !== undefined ? endMs / 1000 : undefined);
    if (start === undefined || end === undefined) continue;
    const segment: SkipSegment = { type, start, end, provider: 'introdb' };
    if (isValid(segment)) segments.push(segment);
  }
  // Movies only use end credits and the post-credits scene.
  return isMovie ? segments.filter((s) => s.type === 'credits' || s.type === 'postcredits') : segments;
}

function parseAniSkip(json: any): SkipSegment[] {
  if (!json?.found || !Array.isArray(json.results)) return [];
  const types: Record<string, SegmentType> = {
    op: 'intro',
    'mixed-op': 'intro',
    ed: 'credits',
    'mixed-ed': 'credits',
    recap: 'recap',
  };
  const segments: SkipSegment[] = [];
  for (const result of json.results) {
    const type = types[String(result?.skipType ?? '').toLowerCase()];
    const start = toNumber(result?.interval?.startTime);
    const end = toNumber(result?.interval?.endTime);
    if (!type || start === undefined || end === undefined) continue;
    const segment: SkipSegment = { type, start, end, provider: 'aniskip' };
    if (isValid(segment)) segments.push(segment);
  }
  return segments;
}

/** Anime-Skip stores only starts: a segment ends where the next one begins. */
function animeSkipSegments(
  timestamps: Array<{ at: number; name: string }>,
  baseDuration: number | undefined,
): SkipSegment[] {
  const typeFor: Record<string, SegmentType> = {
    intro: 'intro',
    'new intro': 'intro',
    'mixed intro': 'intro',
    credits: 'credits',
    'new credits': 'credits',
    'mixed credits': 'credits',
    recap: 'recap',
    preview: 'preview',
  };
  const sorted = [...timestamps].sort((a, b) => a.at - b.at);
  const result: SkipSegment[] = [];
  sorted.forEach((stamp, index) => {
    const type = typeFor[stamp.name.toLowerCase()];
    if (!type) return;
    let end: number | null;
    if (index + 1 < sorted.length) {
      if (sorted[index + 1].at <= stamp.at) return;
      end = sorted[index + 1].at;
    } else if ((type === 'credits' || type === 'preview') && (baseDuration === undefined || stamp.at >= baseDuration / 2)) {
      end = null;
    } else {
      return;
    }
    const segment: SkipSegment = { type, start: stamp.at, end, provider: 'animeskip' };
    if (isValid(segment)) result.push(segment);
  });
  return result;
}

function runAnimeSkip(query: string, clientId: string): Promise<any> {
  return requestJson(ANIME_SKIP_URL, {
    method: 'POST',
    body: JSON.stringify({ query }),
    headers: { 'Content-Type': 'application/json', 'X-Client-ID': clientId },
  }).then((json) => json?.data ?? null);
}

async function fetchAnimeSkip(anilistId: string, episode: number, clientId: string): Promise<SkipSegment[]> {
  if (!/^\d+$/.test(anilistId)) return [];
  let showIds = animeSkipShowIds.get(anilistId);
  if (!showIds) {
    const data = await runAnimeSkip(
      `{ findShowsByExternalId(service: ANILIST, serviceId: "${anilistId}") { id } }`,
      clientId,
    );
    showIds = (data?.findShowsByExternalId ?? [])
      .map((show: any) => toIdString(show?.id))
      .filter((id: string | undefined): id is string => Boolean(id && /^[\w-]+$/.test(id)));
    rememberBounded(animeSkipShowIds, anilistId, showIds as string[]);
  }

  for (const showId of (showIds as string[]).slice(0, 3)) {
    const data = await runAnimeSkip(
      `{ findEpisodesByShowId(showId: "${showId}") { number baseDuration timestamps { at type { name } } } }`,
      clientId,
    );
    const candidates: SkipSegment[][] = (data?.findEpisodesByShowId ?? [])
      .filter((entry: any) => toNumber(entry?.number) === episode)
      .map((entry: any) => {
        const stamps = (entry?.timestamps ?? [])
          .map((raw: any) => ({ at: toNumber(raw?.at), name: raw?.type?.name }))
          .filter((raw: any): raw is { at: number; name: string } => raw.at !== undefined && typeof raw.name === 'string');
        return animeSkipSegments(stamps, toNumber(entry?.baseDuration));
      })
      .filter((list: SkipSegment[]) => list.length > 0);
    if (candidates.length === 0) continue;
    // Several community entries can exist; the one covering the most types wins.
    return candidates.reduce((best, list) => {
      const bestTypes = new Set(best.map((s) => s.type)).size;
      const listTypes = new Set(list.map((s) => s.type)).size;
      return listTypes > bestTypes || (listTypes === bestTypes && list.length > best.length) ? list : best;
    });
  }
  return [];
}

async function armLookup(path: string, id: string): Promise<any[]> {
  const params = new URLSearchParams({ id, include: 'myanimelist,anilist,themoviedb-season,thetvdb-season' });
  const json = await requestJson(`${ARM_URL}/${path}?${params}`);
  if (Array.isArray(json)) return json;
  return json && typeof json === 'object' ? [json] : [];
}

function animeIdsFrom(entry: any): AnimeIds | null {
  const ids = { malId: toIdString(entry?.myanimelist), anilistId: toIdString(entry?.anilist) };
  return ids.malId || ids.anilistId ? ids : null;
}

/** Only an unambiguous match is returned, since one show can map to many anime entries. */
async function animeIdsForShow(request: SegmentRequest): Promise<AnimeIds | null> {
  let entries: any[] = [];
  if (request.tmdbId) entries = await armLookup('themoviedb', String(request.tmdbId));
  if (entries.length === 0 && request.imdbId) entries = await armLookup('imdb', request.imdbId);
  if (entries.length === 0) return null;

  const tagged = entries.filter(
    (e) => toNumber(e?.['themoviedb-season']) === request.season || toNumber(e?.['thetvdb-season']) === request.season,
  );
  if (tagged.length === 1) return animeIdsFrom(tagged[0]);
  if (tagged.length === 0 && entries.length === 1 && request.season === 1) return animeIdsFrom(entries[0]);
  return null;
}

async function resolveAnimeIds(request: SegmentRequest): Promise<AnimeIds | null> {
  const key = request.malId
    ? `mal:${request.malId}`
    : request.kitsuId
      ? `kitsu:${request.kitsuId}`
      : `show:${request.tmdbId ?? request.imdbId ?? '?'}:${request.season ?? 0}`;
  const cachedIds = animeIdCache.get(key);
  if (cachedIds !== undefined) return cachedIds;

  try {
    let ids: AnimeIds | null;
    if (request.malId) {
      const params = new URLSearchParams({ source: 'myanimelist', id: request.malId, include: 'myanimelist,anilist' });
      ids = animeIdsFrom(await requestJson(`${ARM_URL}/ids?${params}`).catch(() => null)) ?? { malId: request.malId };
    } else if (request.kitsuId) {
      const params = new URLSearchParams({ source: 'kitsu', id: request.kitsuId, include: 'myanimelist,anilist' });
      ids = animeIdsFrom(await requestJson(`${ARM_URL}/ids?${params}`));
    } else {
      ids = await animeIdsForShow(request);
    }
    rememberBounded(animeIdCache, key, ids);
    return ids;
  } catch {
    return null; // Transient failure: not cached, so the next episode tries again.
  }
}

/** One segment per type, first list wins. Credits never swallow a post-credits scene. */
function merge(lists: SkipSegment[][]): SkipSegment[] {
  const chosen = new Map<SegmentType, SkipSegment>();
  for (const list of lists) {
    for (const segment of list) {
      if (isValid(segment) && !chosen.has(segment.type)) chosen.set(segment.type, segment);
    }
  }
  const credits = chosen.get('credits');
  const scene = chosen.get('postcredits');
  if (credits && scene && scene.start >= credits.start && scene.start < (credits.end ?? Infinity)) {
    const trimmed: SkipSegment = { ...credits, end: scene.start };
    if (isValid(trimmed)) chosen.set('credits', trimmed);
    else chosen.delete('credits');
  }
  return [...chosen.values()].sort((a, b) => a.start - b.start);
}

async function lookup(request: SegmentRequest, animeSkipClientId: string): Promise<SkipSegment[]> {
  if (request.isMovie) {
    if (!request.imdbId) return [];
    const params = new URLSearchParams({ imdb_id: request.imdbId, is_movie: 'true' });
    return merge([await guarded('introdb', async () => parseIntroDB(await requestJson(`${INTRODB_URL}?${params}`), true))]);
  }

  const episode = request.episode as number;
  const introDB =
    request.imdbId && request.season !== undefined && !request.kitsuId && !request.malId
      ? guarded('introdb', async () => {
          const params = new URLSearchParams({
            imdb_id: request.imdbId as string,
            season: String(request.season),
            episode: String(episode),
          });
          return parseIntroDB(await requestJson(`${INTRODB_URL}?${params}`), false);
        })
      : Promise.resolve([]);

  const animeIds = await resolveAnimeIds(request);
  const aniSkip = animeIds?.malId
    ? guarded('aniskip', async () => {
        const params = new URLSearchParams({ episodeLength: '0' });
        ['op', 'ed', 'recap', 'mixed-op', 'mixed-ed'].forEach((type) => params.append('types', type));
        return parseAniSkip(await requestJson(`${ANISKIP_URL}/skip-times/${animeIds.malId}/${episode}?${params}`));
      })
    : Promise.resolve([]);
  const animeSkip =
    animeIds?.anilistId && animeSkipClientId
      ? guarded('animeskip', () => fetchAnimeSkip(animeIds.anilistId as string, episode, animeSkipClientId))
      : Promise.resolve([]);

  return merge(await Promise.all([introDB, aniSkip, animeSkip]));
}

function cacheKey(request: SegmentRequest): string {
  if (request.isMovie) return `movie:${request.imdbId}`;
  const base = request.malId
    ? `mal${request.malId}`
    : request.kitsuId
      ? `kitsu${request.kitsuId}`
      : (request.imdbId ?? `tmdb${request.tmdbId}`);
  return `episode:${base}:${request.season ?? 0}:${request.episode}`;
}

function isLookupPossible(request: SegmentRequest): boolean {
  if (request.isMovie) return Boolean(request.imdbId);
  if (!request.episode || request.episode <= 0) return false;
  if (request.kitsuId || request.malId) return true;
  return request.season !== undefined && Boolean(request.imdbId || request.tmdbId);
}

function parseRequest(body: any): SegmentRequest {
  const imdbId = toIdString(body?.imdbId);
  if (imdbId && !/^tt\d{1,12}$/.test(imdbId)) throw new AppError('Invalid IMDb id', 400);
  const kitsuId = toIdString(body?.kitsuId);
  if (kitsuId && !/^\d{1,12}$/.test(kitsuId)) throw new AppError('Invalid Kitsu id', 400);
  const malId = toIdString(body?.malId);
  if (malId && !/^\d{1,12}$/.test(malId)) throw new AppError('Invalid MyAnimeList id', 400);

  const positive = (value: unknown, label: string, min: number) => {
    if (value === undefined || value === null) return undefined;
    const number = toNumber(value);
    if (number === undefined || !Number.isInteger(number) || number < min || number > 1_000_000_000) {
      throw new AppError(`Invalid ${label}`, 400);
    }
    return number;
  };

  return {
    imdbId,
    kitsuId,
    malId,
    isMovie: body?.isMovie === true,
    tmdbId: positive(body?.tmdbId, 'TMDB id', 1),
    season: positive(body?.season, 'season', 0),
    episode: positive(body?.episode, 'episode', 1),
  };
}

router.post('/lookup', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const request = parseRequest(req.body);
    if (!isLookupPossible(request)) {
      res.json({ segments: [] });
      return;
    }

    const rawClientId = typeof req.body?.animeSkipClientId === 'string' ? req.body.animeSkipClientId.trim() : '';
    if (rawClientId && !/^[\w-]{1,128}$/.test(rawClientId)) throw new AppError('Invalid Anime-Skip client id', 400);

    const key = cacheKey(request);
    const entry = cache.get(key);
    if (entry && entry.expiresAt > Date.now()) {
      res.json({ segments: entry.segments });
      return;
    }

    let pending = inFlight.get(key);
    if (!pending) {
      pending = lookup(request, rawClientId).finally(() => inFlight.delete(key));
      inFlight.set(key, pending);
    }
    const segments = await pending;
    rememberBounded(cache, key, {
      segments,
      expiresAt: Date.now() + (segments.length > 0 ? FOUND_TTL_MS : EMPTY_TTL_MS),
    });
    res.json({ segments });
  } catch (error) {
    next(error);
  }
});

router.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

export default router;
