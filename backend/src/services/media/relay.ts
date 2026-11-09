/**
 * A loopback relay that FFmpeg and ffprobe read from, instead of the upstream URL.
 *
 * FFmpeg's own HTTP client would follow redirects anywhere, including private
 * addresses. Reading through safeFetch keeps the same checks as the media proxy on
 * every hop, adds the addon's request headers, and keeps upstream URLs (which can
 * hold debrid keys) out of FFmpeg's command line and error output.
 */
import crypto from 'crypto';
import { Request, Response, Router } from 'express';
import { pipeline } from 'stream';
import { safeFetch } from '../../utils/outboundUrl';
import type { StreamTokenPayload } from '../stremio/streamToken';

interface Ticket {
  target: StreamTokenPayload;
  expiresAt: number;
}

/** A ticket outlives its FFmpeg run only briefly; renewed while in use. */
const TICKET_TTL_MS = 6 * 60 * 60 * 1000;
const tickets = new Map<string, Ticket>();

/**
 * Addon files on the local network (a home media server) are blocked unless the
 * server owner turns this on. Loopback and cloud metadata stay blocked either way.
 */
export const allowPrivateMedia = (): boolean => process.env.STREMIO_ALLOW_PRIVATE_MEDIA === 'true';

function relayOrigin(): string {
  return process.env.MEDIA_RELAY_ORIGIN || `http://127.0.0.1:${parseInt(process.env.PORT || '3001', 10)}`;
}

function sweep() {
  const now = Date.now();
  for (const [id, ticket] of tickets) if (ticket.expiresAt < now) tickets.delete(id);
}

/** A loopback URL that reads `target`. Call `release` when the process using it ends. */
export function openRelay(target: StreamTokenPayload): { url: string; release: () => void } {
  sweep();
  const id = crypto.randomBytes(24).toString('base64url');
  tickets.set(id, { target, expiresAt: Date.now() + TICKET_TTL_MS });
  return {
    url: `${relayOrigin()}/internal/media-relay/${id}`,
    release: () => tickets.delete(id),
  };
}

/**
 * Where each upstream URL last redirected to. FFmpeg makes many range requests per
 * file (header, index, every seek), and debrid links often redirect twice; going
 * straight to the final address saves those round trips.
 */
const resolved = new Map<string, { url: string; expiresAt: number }>();
const RESOLVED_TTL_MS = 10 * 60 * 1000;

function resolvedUrl(original: string): string | undefined {
  const hit = resolved.get(original);
  if (hit && hit.expiresAt > Date.now()) return hit.url;
  resolved.delete(original);
  return undefined;
}

function isLoopback(req: Request): boolean {
  const address = req.socket.remoteAddress || '';
  return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1';
}

export const relayRouter = Router();

relayRouter.get('/:id', async (req: Request, res: Response) => {
  const ticket = tickets.get(req.params.id);
  if (!ticket || !isLoopback(req)) return res.status(404).end();
  ticket.expiresAt = Date.now() + TICKET_TTL_MS;

  const controller = new AbortController();
  res.on('close', () => controller.abort());
  const original = ticket.target.url;
  const range = typeof req.headers.range === 'string' ? req.headers.range : undefined;

  const fetchFrom = (url: string) => {
    // Addon headers go only to the addon's own origin, as safeFetch does on redirects.
    const sameOrigin = new URL(url).origin === new URL(original).origin;
    const headers: Record<string, string> = {
      Accept: '*/*', 'User-Agent': 'Flixor', ...(sameOrigin ? ticket.target.headers : {}),
    };
    if (range) headers.range = range;
    return safeFetch(url, {
      headers,
      timeoutMs: 25_000,
      idleTimeoutMs: 120_000,
      maxBytes: Infinity,
      signal: controller.signal,
      allowPrivateNetwork: allowPrivateMedia(),
      keepAlive: true,
    });
  };

  try {
    const shortcut = resolvedUrl(original);
    let upstream = await fetchFrom(shortcut ?? original);
    if (shortcut && upstream.status >= 400) {
      // The final address expired: start from the addon's link again.
      upstream.abort();
      resolved.delete(original);
      upstream = await fetchFrom(original);
    }
    if (upstream.status < 400 && upstream.url !== (shortcut ?? original)) {
      resolved.set(original, { url: upstream.url, expiresAt: Date.now() + RESOLVED_TTL_MS });
    }
    res.status(upstream.status);
    for (const name of ['content-length', 'content-range', 'accept-ranges', 'content-type']) {
      const value = upstream.headers[name];
      if (typeof value === 'string') res.setHeader(name, value);
    }
    if (upstream.status >= 400) {
      upstream.abort();
      return res.end();
    }
    pipeline(upstream.body, res, () => upstream.abort());
  } catch {
    if (!res.headersSent) res.status(502).end();
    else res.destroy();
  }
});
