import { NextFunction, RequestHandler, Response, Router } from 'express';
import { pipeline } from 'stream';
import { AuthenticatedRequest } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import {
  assertAddonResourceUrl,
  buildAddonResourceUrl,
  findAddonStream,
  sanitizeRequestHeaders,
} from '../services/stremio/addonUrl';
import { isHlsResponse, rewriteHlsPlaylist } from '../services/stremio/hlsPlaylist';
import { openStreamToken, sealStreamToken } from '../services/stremio/streamToken';
import { getDefaultTMDBClient, getUserTMDBClient } from '../services/tmdb/TMDBClient';
import { OutboundUrlError, assertPublicUrl, safeFetch } from '../utils/outboundUrl';

// Mounted behind requireAuth in server.ts. Any route here that fetches a
// user-supplied URL must go through utils/outboundUrl.ts. URLs in this file can embed
// debrid keys: they arrive in POST bodies or encrypted tokens, and are never logged.
const router = Router();

const MAX_ADDON_RESPONSE_BYTES = 8 * 1024 * 1024;
const MAX_SUBTITLE_BYTES = 5 * 1024 * 1024;
const MAX_PLAYLIST_BYTES = 16 * 1024 * 1024;
const ADDON_TIMEOUT_MS = 60_000;

/** Only these reach the client. Addon responses must never render as a page on this origin. */
const MEDIA_CONTENT_TYPE =
  /^(?:video\/|audio\/|application\/(?:vnd\.apple\.mpegurl|x-mpegurl|dash\+xml|mp4|octet-stream)|binary\/octet-stream)/i;
const PASSTHROUGH_HEADERS = ['content-length', 'content-range', 'accept-ranges', 'etag', 'last-modified'];
const HLS_CONTENT_TYPE = 'application/vnd.apple.mpegurl';

type AsyncHandler = (req: AuthenticatedRequest, res: Response, next: NextFunction) => Promise<unknown>;

const wrap = (handler: AsyncHandler): RequestHandler => (req, res, next) => {
  handler(req as AuthenticatedRequest, res, next).catch(next);
};

async function fetchAddonJson(url: string): Promise<any> {
  const upstream = await safeFetch(url, {
    headers: { Accept: 'application/json', 'User-Agent': 'Flixor' },
    timeoutMs: ADDON_TIMEOUT_MS,
    idleTimeoutMs: ADDON_TIMEOUT_MS,
    maxBytes: MAX_ADDON_RESPONSE_BYTES,
  });
  if (upstream.status < 200 || upstream.status >= 300) {
    upstream.abort();
    throw new AppError(`Addon responded with status ${upstream.status}`, 502);
  }
  return upstream.json();
}

/** Addon JSON for browsers that cannot reach the addon themselves (CORS, mixed content). */
router.post('/addon', wrap(async (req, res) => {
  res.json(await fetchAddonJson(assertAddonResourceUrl(req.body?.url)));
}));

/** Subtitle file for hosts the browser cannot read. */
router.post('/subtitle', wrap(async (req, res) => {
  const url = req.body?.url;
  if (typeof url !== 'string' || !url) throw new AppError('Subtitle URL is required', 400);
  const upstream = await safeFetch(url, {
    headers: { Accept: '*/*', 'User-Agent': 'Flixor' },
    maxBytes: MAX_SUBTITLE_BYTES,
  });
  if (upstream.status < 200 || upstream.status >= 300) {
    upstream.abort();
    throw new AppError(`Subtitle host responded with status ${upstream.status}`, 502);
  }
  const body = await upstream.buffer();
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Cache-Control', 'private, no-store');
  res.send(body);
}));

/** IMDb to TMDB lookup for catalog items. `null` means TMDB has no match. */
router.get('/tmdb-id/:imdbId', wrap(async (req, res) => {
  const { imdbId } = req.params;
  if (!/^tt\d+$/.test(imdbId)) throw new AppError('Invalid IMDb id', 400);
  const client = req.user?.id ? await getUserTMDBClient(req.user.id) : getDefaultTMDBClient();
  // Bracket access reuses the client's rate limiter and cache for an endpoint it lacks.
  const found = await client['cachedRequest']<{ movie_results?: any[]; tv_results?: any[] }>(
    `/find/${imdbId}`,
    { external_source: 'imdb_id' },
    `find:${imdbId}`,
    7 * 24 * 60 * 60,
  );
  const movies = found.movie_results ?? [];
  const shows = found.tv_results ?? [];
  const preferred = req.query.type === 'series' ? [...shows, ...movies] : [...movies, ...shows];
  res.json({ tmdbId: preferred[0]?.id ?? null });
}));

/**
 * Issues a media proxy token. The URL and headers come from this server's own request
 * to the addon, so a token only ever points at something an addon offered.
 */
router.post('/stream/token', wrap(async (req, res) => {
  const { manifestUrl, type, id, streamIndex, url, filename } = req.body ?? {};
  if (typeof manifestUrl !== 'string' || typeof type !== 'string' || typeof id !== 'string') {
    throw new AppError('Addon, type and id are required', 400);
  }
  if (!/^[a-z]+$/.test(type)) throw new AppError('Invalid content type', 400);

  const data = await fetchAddonJson(
    assertAddonResourceUrl(
      buildAddonResourceUrl(manifestUrl, `/stream/${type}/${encodeURIComponent(id)}.json`),
    ),
  );
  const stream = findAddonStream(data?.streams, url, streamIndex, filename);
  if (!stream) throw new AppError('The addon no longer offers this source', 404);

  await assertPublicUrl(stream.url);
  res.json({
    token: sealStreamToken(
      {
        url: stream.url,
        headers: sanitizeRequestHeaders(stream.behaviorHints?.proxyHeaders?.request),
      },
      req.user!.id,
    ),
  });
}));

async function readPlaylist(body: NodeJS.ReadableStream): Promise<string> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of body) {
    total += chunk.length;
    if (total > MAX_PLAYLIST_BYTES) throw new OutboundUrlError('RESPONSE_TOO_LARGE', 'Playlist is too large');
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks).toString('utf8');
}

/** Media proxy. Forwards Range and the upstream status, and stops when the client leaves. */
router.get('/stream/:token', wrap(async (req, res) => {
  const userId = req.user!.id;
  const target = openStreamToken(req.params.token, userId);

  const controller = new AbortController();
  res.on('close', () => controller.abort());

  const headers: Record<string, string> = { Accept: '*/*', 'User-Agent': 'Flixor', ...target.headers };
  for (const name of ['range', 'if-range'] as const) {
    const value = req.headers[name];
    if (typeof value === 'string') headers[name] = value;
  }

  const upstream = await safeFetch(target.url, {
    method: req.method === 'HEAD' ? 'HEAD' : 'GET',
    headers,
    timeoutMs: 20_000,
    // A paused player stops reading, so allow a pause before the upstream is dropped.
    idleTimeoutMs: 120_000,
    maxBytes: Infinity,
    signal: controller.signal,
  });

  res.setHeader('Cache-Control', 'private, no-store, no-transform'); // no-transform keeps compression off
  res.setHeader('X-Accel-Buffering', 'no');
  res.setHeader('Content-Security-Policy', "sandbox; default-src 'none'");
  res.status(upstream.status);

  if (upstream.status >= 400) {
    upstream.abort();
    return res.end();
  }

  const contentType = upstream.headers['content-type'];
  if (upstream.status === 200 && req.method !== 'HEAD' && isHlsResponse(contentType, upstream.url)) {
    const playlist = await readPlaylist(upstream.body);
    // A bare token resolves next to this playlist, whatever path the proxy is served from.
    const rewritten = rewriteHlsPlaylist(playlist, upstream.url, (url) =>
      sealStreamToken({ url, headers: target.headers }, userId),
    );
    res.setHeader('Content-Type', HLS_CONTENT_TYPE);
    return res.send(rewritten);
  }

  res.setHeader(
    'Content-Type',
    contentType && MEDIA_CONTENT_TYPE.test(contentType) ? contentType : 'application/octet-stream',
  );
  for (const name of PASSTHROUGH_HEADERS) {
    const value = upstream.headers[name];
    if (typeof value === 'string') res.setHeader(name, value);
  }
  res.flushHeaders();
  if (req.method === 'HEAD') {
    upstream.abort();
    return res.end();
  }
  pipeline(upstream.body, res, () => upstream.abort());
}));

export default router;
