import { Router, Response, NextFunction } from 'express';
import { AppDataSource } from '../db/data-source';
import { User } from '../db/entities';
import { AppError } from '../middleware/errorHandler';
import { requireAuth, AuthenticatedRequest } from '../middleware/auth';
import { decryptForUser, encryptForUser, isEncrypted } from '../utils/crypto';
import { createLogger } from '../utils/logger';
import { safeFetch, SafeFetchResponse } from '../utils/outboundUrl';

declare module 'express-session' {
  interface SessionData {
    /** Overseerr's own session, for accounts signed in with Plex. Encrypted per user. */
    overseerrPlexSession?: { url: string; cookie: string; username?: string };
  }
}

const router = Router();
const logger = createLogger('overseerr-proxy');

// Self-hosted Overseerr usually lives on the LAN. Loopback, link-local and cloud
// metadata addresses stay blocked by the guard.
const OUTBOUND = { allowPrivateNetwork: true, timeoutMs: 20_000 } as const;
const ALLOWED_METHODS = new Set(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']);
const BODY_METHODS = new Set(['POST', 'PUT', 'PATCH']);

router.use(requireAuth);

interface OverseerrProxyRequest {
  targetUrl: string;
  apiKey?: string;
  authMethod?: 'api_key' | 'plex';
  endpoint: string;
  method?: string;
  body?: unknown;
}

function normalizeBaseUrl(targetUrl: unknown): string {
  if (typeof targetUrl !== 'string' || !targetUrl.trim()) {
    throw new AppError('Missing required field: targetUrl', 400);
  }
  return targetUrl.trim().replace(/\/+$/, '').replace(/\/api\/v1$/, '');
}

/** Builds the upstream URL. Only paths under `/api/v1/` of the given base are allowed. */
function buildApiUrl(baseUrl: string, endpoint: unknown): string {
  if (typeof endpoint !== 'string' || !endpoint.startsWith('/')) {
    throw new AppError('Endpoint must be a path under /api/v1/', 400);
  }
  const [endpointPath] = endpoint.split(/[?#]/, 1);
  if (/\.\.|\\|%2e|%2f|%5c/i.test(endpointPath)) {
    throw new AppError('Endpoint must be a path under /api/v1/', 400);
  }
  let url: URL;
  let base: URL;
  try {
    base = new URL(baseUrl);
    url = new URL(`${baseUrl}/api/v1${endpoint}`);
  } catch {
    throw new AppError('Overseerr URL is not valid', 400);
  }
  if (url.origin !== base.origin || !url.pathname.startsWith(`${base.pathname.replace(/\/$/, '')}/api/v1/`)) {
    throw new AppError('Endpoint must be a path under /api/v1/', 400);
  }
  return url.toString();
}

async function forward(upstream: SafeFetchResponse, res: Response) {
  const contentType = String(upstream.headers['content-type'] ?? '');
  const text = await upstream.text();
  if (contentType.includes('application/json')) {
    try {
      res.status(upstream.status).json(text ? JSON.parse(text) : null);
      return;
    } catch {
      // Fall through and forward the text as is.
    }
  }
  res.status(upstream.status).send(text);
}

/**
 * Proxy requests to the user's Overseerr instance to avoid CORS issues.
 * POST /api/overseerr/proxy
 */
router.post('/proxy', async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const { targetUrl, apiKey, authMethod, endpoint, body } = (req.body ?? {}) as OverseerrProxyRequest;
    const method = String((req.body ?? {}).method ?? 'GET').toUpperCase();

    if (!ALLOWED_METHODS.has(method)) {
      throw new AppError('Unsupported method', 400);
    }

    const baseUrl = normalizeBaseUrl(targetUrl);
    const url = buildApiUrl(baseUrl, endpoint);

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    };

    if (authMethod === 'plex') {
      const stored = req.session.overseerrPlexSession;
      if (!stored || stored.url !== baseUrl) {
        throw new AppError('Sign in to Overseerr with Plex first', 401);
      }
      headers.Cookie = decryptForUser(req.user!.id, stored.cookie);
    } else {
      if (typeof apiKey !== 'string' || !apiKey) {
        throw new AppError('Missing required field: apiKey', 400);
      }
      headers['X-Api-Key'] = apiKey;
    }

    const upstream = await safeFetch(url, {
      ...OUTBOUND,
      method,
      headers,
      body: BODY_METHODS.has(method) && body !== undefined ? JSON.stringify(body) : undefined,
    });

    if (authMethod === 'plex' && upstream.status === 401) {
      delete req.session.overseerrPlexSession;
    }

    await forward(upstream, res);
  } catch (error: any) {
    if (error instanceof AppError) return next(error);
    logger.error('Overseerr proxy error', { message: error?.message });
    next(new AppError('Failed to proxy request to Overseerr', 502));
  }
});

async function plexAccountToken(userId: string): Promise<string> {
  const user = await AppDataSource.getRepository(User)
    .createQueryBuilder('u')
    .addSelect('u.plexToken')
    .where('u.id = :id', { id: userId })
    .getOne();
  if (!user?.plexToken) throw new AppError('Not signed in to Plex', 401);
  return isEncrypted(user.plexToken) ? decryptForUser(userId, user.plexToken) : user.plexToken;
}

/**
 * Sign in to Overseerr with the user's Plex account. The browser can't read
 * Overseerr's Set-Cookie, so the session cookie stays here.
 * POST /api/overseerr/auth/plex
 */
router.post('/auth/plex', async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const baseUrl = normalizeBaseUrl(req.body?.targetUrl);
    const url = buildApiUrl(baseUrl, '/auth/plex');
    const authToken = await plexAccountToken(req.user!.id);

    const upstream = await safeFetch(url, {
      ...OUTBOUND,
      // No redirects: a redirected POST would resend the Plex token to another host.
      maxRedirects: 0,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ authToken }),
    });

    if (upstream.status === 401 || upstream.status === 403) {
      upstream.abort();
      return res.json({ valid: false, error: 'Plex account not authorized on this Overseerr server' });
    }
    if (upstream.status < 200 || upstream.status >= 300) {
      upstream.abort();
      return res.json({ valid: false, error: `Authentication failed (${upstream.status})` });
    }

    const setCookie = upstream.headers['set-cookie'] ?? [];
    const cookie = setCookie.map((c) => /connect\.sid=[^;]+/.exec(c)?.[0]).find(Boolean);
    if (!cookie) {
      upstream.abort();
      return res.json({ valid: false, error: 'Overseerr did not return a session' });
    }

    const data = await upstream.json<any>().catch(() => null);
    const username: string = data?.username || data?.plexUsername || data?.displayName || data?.email || 'Plex User';

    req.session.overseerrPlexSession = {
      url: baseUrl,
      cookie: encryptForUser(req.user!.id, cookie),
      username,
    };
    res.json({ valid: true, username });
  } catch (error: any) {
    if (error instanceof AppError) return next(error);
    logger.error('Overseerr Plex sign-in failed', { message: error?.message });
    next(new AppError('Could not reach Overseerr', 502));
  }
});

/**
 * Whether this browser session holds an Overseerr sign-in for a URL.
 * POST /api/overseerr/auth/plex/status
 */
router.post('/auth/plex/status', (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const baseUrl = normalizeBaseUrl(req.body?.targetUrl);
    const stored = req.session.overseerrPlexSession;
    res.json(stored?.url === baseUrl ? { signedIn: true, username: stored.username } : { signedIn: false });
  } catch (error) {
    next(error);
  }
});

/**
 * Forget the Overseerr session.
 * POST /api/overseerr/auth/plex/signout
 */
router.post('/auth/plex/signout', (req: AuthenticatedRequest, res: Response) => {
  delete req.session.overseerrPlexSession;
  res.json({ ok: true });
});

export default router;
