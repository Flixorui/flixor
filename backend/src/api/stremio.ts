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
import {
  ConversionLimitError,
  mediaToolsAvailable,
  pickVideoEncoder,
  readConversionState,
  startConversion,
  stopConversion,
} from '../services/media/ffmpeg';
import { allowPrivateMedia, openRelay } from '../services/media/relay';
import { probeMedia } from '../services/media/probe';
import { buildPlayArgs, type PlayMode } from '../services/media/transcode';
import { addHlsSession, createHlsDir, getHlsSession, HLS_FILE, HLS_SESSION, hlsFile } from '../services/media/hls';
import fs from 'fs';

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

  await assertPublicUrl(stream.url, { allowPrivateNetwork: allowPrivateMedia() });
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
    allowPrivateNetwork: allowPrivateMedia(),
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

// ---------------------------------------------------------------------------
// Player engine: probe, then play directly or through FFmpeg (remux / compatible).
// FFmpeg reads through the loopback relay (services/media/relay.ts), never the
// upstream URL, so redirects get the same address checks as the proxy above.

function playerKey(req: AuthenticatedRequest): string {
  const player = typeof req.query.player === 'string' ? req.query.player : '';
  if (!/^[\w-]{1,64}$/.test(player)) throw new AppError('Invalid player id', 400);
  return `${req.user!.id}:${player}`;
}

function streamIndex(value: unknown): number | null {
  if (value === undefined || value === '' || value === 'none') return null;
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0 || n > 255) throw new AppError('Invalid track', 400);
  return n;
}

async function requireMediaTools() {
  const tools = await mediaToolsAvailable();
  if (!tools.ffmpeg || !tools.ffprobe) throw new AppError('FFmpeg is not installed on the server', 501);
  return tools;
}

/** Whether this server can convert files (FFmpeg installed). */
router.get('/engine', wrap(async (_req, res) => {
  const tools = await mediaToolsAvailable();
  res.json({ conversion: tools.ffmpeg && tools.ffprobe });
}));

/** What the file contains. `available: false` when the server has no FFmpeg. */
router.get('/stream/:token/probe', wrap(async (req, res) => {
  const target = openStreamToken(req.params.token, req.user!.id);
  const tools = await mediaToolsAvailable();
  if (!tools.ffmpeg || !tools.ffprobe) return res.json({ available: false });
  const relay = openRelay(target);
  try {
    const info = await probeMedia(relay.url, target.url);
    res.json({ available: true, info });
  } catch {
    throw new AppError('This source could not be read', 502);
  } finally {
    relay.release();
  }
}));

interface PreparedConversion {
  args: string[];
  key: string;
  relay: { url: string; release: () => void };
  subtitlePipe: boolean;
  knownStart?: number;
}

/** Reads the player's choices from the query, probes, and builds FFmpeg's arguments. */
async function prepareConversion(req: AuthenticatedRequest, hlsDir?: string): Promise<PreparedConversion> {
  const target = openStreamToken(req.params.token, req.user!.id);
  const tools = await requireMediaTools();
  const key = playerKey(req);
  const burnIndex = streamIndex(req.query.burn);
  // Drawing an image subtitle into the picture needs conversion.
  const mode: PlayMode = req.query.mode === 'compatible' || burnIndex !== null ? 'compatible' : 'remux';
  const start = Math.max(0, Number(req.query.start) || 0);
  const audioIndex = streamIndex(req.query.audio);
  const subtitleIndex = streamIndex(req.query.sub);

  const relay = openRelay(target);
  const fail = (message: string, status: number): never => {
    relay.release();
    throw new AppError(message, status);
  };
  let info;
  try {
    info = await probeMedia(relay.url, target.url);
  } catch {
    return fail('This source could not be read', 502);
  }
  if (!info.video) fail('This source has no video', 415);
  if (audioIndex !== null && !info.audio.some((a) => a.index === audioIndex)) fail('Audio track not found', 400);
  if (subtitleIndex !== null && !info.subtitles.some((s) => s.index === subtitleIndex && s.isText)) {
    fail('Subtitle track not found', 400);
  }
  const burnTrack = burnIndex === null ? undefined : info.subtitles.find((s) => s.index === burnIndex && !s.isText);
  if (burnIndex !== null && !burnTrack) fail('Subtitle track not found', 400);

  const args = buildPlayArgs({
    input: relay.url,
    mode,
    start,
    info,
    audioIndex,
    copyAudio: req.query.acopy === '1',
    audioChannels: req.query.ch === '6' ? 6 : 2,
    keepDolbyVision: req.query.dv === '1',
    encoder: await pickVideoEncoder(),
    filters: tools.filters,
    subtitleIndex,
    burnSubtitle: burnTrack ? { index: burnTrack.index, width: burnTrack.width, height: burnTrack.height } : null,
    hlsDir,
  });
  // Conversion seeks exactly; remux starts at a key frame that FFmpeg reports on fd 4.
  return { args, key, relay, subtitlePipe: subtitleIndex !== null, knownStart: mode === 'compatible' ? start : undefined };
}

function launch(prepared: PreparedConversion) {
  try {
    return startConversion(prepared.key, prepared.args, { subtitlePipe: prepared.subtitlePipe, knownStart: prepared.knownStart });
  } catch (error) {
    prepared.relay.release();
    if (error instanceof ConversionLimitError) throw new AppError(error.message, 503);
    throw error;
  }
}

/** The file as fragmented MP4, remuxed or converted from `start`. */
router.get('/stream/:token/play', wrap(async (req, res) => {
  const prepared = await prepareConversion(req);
  const child = launch(prepared);
  const stop = () => {
    stopConversion(child);
    prepared.relay.release();
  };
  res.on('close', stop);
  child.once('close', () => prepared.relay.release());

  res.setHeader('Content-Type', 'video/mp4');
  res.setHeader('Cache-Control', 'private, no-store, no-transform');
  res.setHeader('X-Accel-Buffering', 'no');
  res.status(200);
  res.flushHeaders();
  // Backpressure: a paused player stops reading, the pipe fills, and FFmpeg waits.
  pipeline(child.stdout!, res, () => stop());
}));

const HLS_TYPES: Record<string, string> = {
  m3u8: 'application/vnd.apple.mpegurl',
  mp4: 'video/mp4',
  m4s: 'video/iso.segment',
};

/**
 * The same conversion as HLS, for Safari (services/media/hls.ts). The first playlist
 * request of a session (`<player>-<n>`) starts FFmpeg with the query's choices; the
 * playlist's relative segment links resolve inside the same session path.
 */
router.get('/stream/:token/hls/:session/:file', wrap(async (req, res) => {
  const { session, file } = req.params;
  if (!HLS_SESSION.test(session) || !HLS_FILE.test(file)) throw new AppError('Not found', 404);
  openStreamToken(req.params.token, req.user!.id);
  const owner = req.user!.id;

  if (file === 'index.m3u8' && !getHlsSession(owner, session)) {
    const dir = createHlsDir();
    let prepared: PreparedConversion;
    try {
      prepared = await prepareConversion(req, dir);
    } catch (error) {
      fs.rm(dir, { recursive: true, force: true }, () => {});
      throw error;
    }
    const child = launch(prepared);
    const player = String(req.query.player);
    addHlsSession(owner, session, player, dir, child, prepared.relay.release);
  }

  const full = await hlsFile(owner, session, file);
  if (!full) throw new AppError('This part of the video is not ready', 404);
  res.setHeader('Content-Type', HLS_TYPES[file.split('.').pop()!] ?? 'application/octet-stream');
  if (file === 'index.m3u8') {
    // A growing EVENT playlist looks live, and Safari would start at its newest
    // segments. EXT-X-START makes it start at the beginning of the conversion.
    const playlist = await fs.promises.readFile(full, 'utf8');
    res.setHeader('Cache-Control', 'no-store');
    return res.send(playlist.replace('#EXTM3U\n', '#EXTM3U\n#EXT-X-START:TIME-OFFSET=0,PRECISE=YES\n'));
  }
  res.setHeader('Cache-Control', 'private, max-age=3600');
  res.sendFile(full);
}));

/**
 * The player's current conversion: where it really starts (null until FFmpeg has
 * written its first video packet), and WebVTT written so far after `from`.
 */
router.get('/stream/:token/conversion', wrap(async (req, res) => {
  openStreamToken(req.params.token, req.user!.id);
  const key = playerKey(req);
  const from = Math.max(0, parseInt(String(req.query.from || '0'), 10) || 0);
  res.setHeader('Cache-Control', 'no-store');
  res.json(readConversionState(key, from) ?? { start: null, text: '', next: 0, done: true, missing: true });
}));

export default router;
