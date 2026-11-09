import { Router, Request, Response, NextFunction } from 'express';
import { TraktClient } from '../services/trakt/TraktClient';
import { requireAuth, AuthenticatedRequest } from '../middleware/auth';
import { AppError } from '../middleware/errorHandler';
import { createLogger } from '../utils/logger';
import { cacheManager } from '../services/cache/CacheManager';

const router = Router();
const logger = createLogger('trakt-api');

// Public endpoints (no auth)
router.get('/:type(trending|popular)/:media(movies|shows)', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const media = req.params.media as 'movies'|'shows';
    const type = req.params.type as 'trending'|'popular';
    const limit = req.query.limit ? Number(req.query.limit) : undefined;
    const key = `trakt:${type}:${media}:${limit||'all'}`;
    const data = await cacheManager.getOrSet('trakt', key, async () => {
      const c = new TraktClient();
      return type === 'trending' ? c.trending(media, limit) : c.popular(media, limit);
    }, 30 * 60); // 30 minutes
    res.json(data);
  } catch (e: any) {
    const status = e?.response?.status;
    const data = e?.response?.data;
    logger.error('Trakt public endpoint failed', { status, data, message: e?.message });
    next(new AppError('Failed to fetch from Trakt', status && status >= 400 && status < 600 ? status : 500));
  }
});

// Charts: most watched (public)
router.get('/:media(movies|shows)/watched/:period(daily|weekly|monthly|yearly|all)', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const media = req.params.media as 'movies'|'shows';
    const period = req.params.period as 'daily'|'weekly'|'monthly'|'yearly'|'all';
    const limit = req.query.limit ? Number(req.query.limit) : undefined;
    const key = `trakt:watched:${media}:${period}:${limit||'all'}`;
    const data = await cacheManager.getOrSet('trakt', key, async () => {
      const c = new TraktClient();
      return c.mostWatched(media, period, limit);
    }, 30 * 60); // 30 minutes
    res.json(data);
  } catch (e: any) {
    logger.error('Trakt most-watched failed', e);
    next(new AppError('Failed to fetch Trakt charts', 500));
  }
});

// Anticipated (public)
router.get('/:media(movies|shows)/anticipated', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const media = req.params.media as 'movies'|'shows';
    const limit = req.query.limit ? Number(req.query.limit) : undefined;
    const key = `trakt:anticipated:${media}:${limit||'all'}`;
    const data = await cacheManager.getOrSet('trakt', key, async () => {
      const c = new TraktClient();
      return c.anticipated(media, limit);
    }, 30 * 60);
    res.json(data);
  } catch (e: any) {
    logger.error('Trakt anticipated failed', e);
    next(new AppError('Failed to fetch Trakt anticipated', 500));
  }
});

// Device code (auth not strictly required, but we require session to save tokens later)
router.post('/oauth/device/code', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const c = new TraktClient(req.user!.id);
    const dc = await c.deviceCode();
    res.json(dc);
  } catch (e: any) {
    logger.error('Trakt device code failed', e);
    next(new AppError('Failed to request device code', 500));
  }
});

// Device token polling – stores tokens server-side
router.post('/oauth/device/token', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { code } = req.body || {};
    if (!code) throw new AppError('Missing device code', 400);
    const c = new TraktClient(req.user!.id);
    const tokens = await c.deviceToken(code);
    return res.json({ ok: true, tokens });
  } catch (e: any) {
    const status = e?.response?.status;
    const data = e?.response?.data;
    // Trakt may send various 4xx during polling: authorization_pending, slow_down, expired_token, invalid_grant
    const errCode = data?.error || 'server_error';
    logger.warn('Trakt token exchange pending/error', { status, errCode });
    // Always return 200 with ok:false so the frontend can continue polling
    return res.json({ ok: false, error: errCode, error_description: data?.error_description });
  }
});

// Recommendations (auth)
router.get('/recommendations/:media(movies|shows)', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const media = req.params.media as 'movies'|'shows';
    const limit = req.query.limit ? Number(req.query.limit) : undefined;
    const c = new TraktClient(req.user!.id);
    const data = await c.recommendations(media, limit);
    res.json(data);
  } catch (e: any) {
    logger.error('Trakt recommendations failed', e);
    next(new AppError('Failed to fetch recommendations', 500));
  }
});

// Watchlist (auth)
router.get('/users/me/watchlist/:media?', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const media = req.params.media as ('movies'|'shows'|undefined);
    const c = new TraktClient(req.user!.id);
    const data = await c.watchlist(media);
    res.json(data);
  } catch (e: any) {
    const status = e?.response?.status;
    if (status === 401 || status === 403) {
      return next(new AppError('Trakt not authenticated', 401));
    }
    logger.error('Trakt watchlist failed', e);
    next(new AppError('Failed to fetch watchlist', 500));
  }
});

// History (auth)
router.get('/users/me/history/:media?', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const media = req.params.media as ('movies'|'shows'|undefined);
    const limit = req.query.limit ? Number(req.query.limit) : undefined;
    const c = new TraktClient(req.user!.id);
    const data = await c.history(media, limit);
    res.json(data);
  } catch (e: any) {
    const status = e?.response?.status;
    if (status === 401 || status === 403) {
      return next(new AppError('Trakt not authenticated', 401));
    }
    logger.error('Trakt history failed', e);
    next(new AppError('Failed to fetch history', 500));
  }
});

// Profile (auth)
router.get('/users/me', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const c = new TraktClient(req.user!.id);
    const data = await c.userProfile();
    res.json(data);
  } catch (e: any) {
    const status = e?.response?.status;
    if (status === 401 || status === 403) {
      return next(new AppError('Trakt not authenticated', 401));
    }
    logger.error('Trakt user profile failed', e);
    next(new AppError('Failed to fetch user profile', 500));
  }
});

// Watchlist modify (auth)
router.post('/watchlist', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const c = new TraktClient(req.user!.id);
    const result = await c.watchlistAdd(req.body);
    res.json(result);
  } catch (e: any) {
    logger.error('Trakt watchlist add failed', e);
    next(new AppError('Failed to modify watchlist', 500));
  }
});

router.post('/watchlist/remove', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const c = new TraktClient(req.user!.id);
    const result = await c.watchlistRemove(req.body);
    res.json(result);
  } catch (e: any) {
    logger.error('Trakt watchlist remove failed', e);
    next(new AppError('Failed to modify watchlist', 500));
  }
});

// Sign out (clear tokens)
router.post('/signout', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const c = new TraktClient(req.user!.id);
    await c.clearTokens();
    res.json({ ok: true, message: 'Signed out from Trakt' });
  } catch (e: any) {
    logger.error('Trakt signout failed', e);
    next(new AppError('Failed to sign out', 500));
  }
});

// Scrobbling (auth)
router.post('/scrobble/start', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const c = new TraktClient(req.user!.id);
    const result = await c.scrobbleStart(req.body);
    res.json(result);
  } catch (e: any) {
    const status = e?.response?.status;
    // 409 = already scrobbling, which is fine
    if (status === 409) {
      return res.json({ action: 'scrobbling' });
    }
    logger.error('Trakt scrobble start failed', e);
    next(new AppError('Failed to start scrobble', status && status >= 400 && status < 600 ? status : 500));
  }
});

router.post('/scrobble/pause', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const c = new TraktClient(req.user!.id);
    const result = await c.scrobblePause(req.body);
    res.json(result);
  } catch (e: any) {
    logger.error('Trakt scrobble pause failed', e);
    next(new AppError('Failed to pause scrobble', 500));
  }
});

router.post('/scrobble/stop', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const c = new TraktClient(req.user!.id);
    const result = await c.scrobbleStop(req.body);
    res.json(result);
  } catch (e: any) {
    logger.error('Trakt scrobble stop failed', e);
    next(new AppError('Failed to stop scrobble', 500));
  }
});

type TraktHandler = (req: AuthenticatedRequest, res: Response) => Promise<unknown>;

/** Runs a handler and maps Trakt's status to ours. Never logs request bodies or tokens. */
const traktRoute = (failure: string, handler: TraktHandler) =>
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const data = await handler(req, res);
      if (!res.headersSent) res.json(data ?? { ok: true });
    } catch (e: any) {
      if (e instanceof AppError) return next(e);
      const status = e?.response?.status as number | undefined;
      if (status === 401 || status === 403) {
        return next(new AppError('Trakt not authenticated', 401));
      }
      logger.error(failure, { status, message: e?.message });
      next(new AppError(failure, status && status >= 400 && status < 600 ? status : 500));
    }
  };

const queryInt = (value: unknown, fallback: number, max: number) => {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? Math.min(parsed, max) : fallback;
};

const requireBodyObject = (body: unknown) => {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new AppError('A JSON object is required', 400);
  }
  return body;
};

const client = (req: AuthenticatedRequest) => new TraktClient(req.user!.id);

// Token lifecycle: the backend holds the tokens, so the client never sends them.
router.post('/oauth/token', requireAuth, traktRoute('Failed to refresh token', async (req) => {
  const tokens = await client(req).refreshStoredTokens();
  if (!tokens) throw new AppError('Trakt not authenticated', 401);
  return tokens;
}));

router.post('/oauth/revoke', requireAuth, traktRoute('Failed to revoke token', async (req) => {
  await client(req).revokeStoredTokens();
  return { ok: true };
}));

// History
router.post('/sync/history', requireAuth, traktRoute('Failed to add to history', (req) =>
  client(req).syncHistoryAdd(requireBodyObject(req.body))));
router.post('/sync/history/remove', requireAuth, traktRoute('Failed to remove from history', (req) =>
  client(req).syncHistoryRemove(requireBodyObject(req.body))));
router.get('/sync/history/:type(movies|shows|seasons|episodes)/:id(\\d+)', requireAuth, traktRoute('Failed to fetch item history', (req) =>
  client(req).itemHistory(req.params.type, Number(req.params.id), queryInt(req.query.limit, 1, 100))));

// Playback progress
router.get('/sync/playback/:type(movies|episodes)?', requireAuth, traktRoute('Failed to fetch playback progress', (req) =>
  client(req).playback(req.params.type as 'movies' | 'episodes' | undefined)));
router.delete('/sync/playback/:id(\\d+)', requireAuth, traktRoute('Failed to remove playback progress', async (req) => {
  await client(req).playbackRemove(Number(req.params.id));
  return { ok: true };
}));

// Ratings
router.get('/sync/ratings/:type(movies|shows|seasons|episodes)', requireAuth, traktRoute('Failed to fetch ratings', (req) =>
  client(req).ratings(req.params.type)));
router.post('/sync/ratings', requireAuth, traktRoute('Failed to save rating', (req) =>
  client(req).ratingsAdd(requireBodyObject(req.body))));
router.post('/sync/ratings/remove', requireAuth, traktRoute('Failed to remove rating', (req) =>
  client(req).ratingsRemove(requireBodyObject(req.body))));

// Watched shows and per-show progress
router.get('/sync/watched/shows', requireAuth, traktRoute('Failed to fetch watched shows', (req) =>
  client(req).watchedShows()));
router.get('/shows/:id([\\w.-]+)/progress/watched', requireAuth, traktRoute('Failed to fetch show progress', (req) =>
  client(req).showProgress(req.params.id)));

// Search (public)
router.get('/search/id/:source(tmdb|imdb|tvdb)/:id([\\w.-]+)', traktRoute('Failed to look up id', async (req) => {
  const { source, id } = req.params;
  const type = req.query.type === 'movie' || req.query.type === 'show' ? req.query.type : undefined;
  const key = `trakt:lookup:${source}:${id}:${type || 'any'}`;
  return cacheManager.getOrSet('trakt', key, () => new TraktClient().lookupId(source as any, id, type), 24 * 60 * 60);
}));
router.get('/search/:types(movie|show|episode|movie,show)', traktRoute('Failed to search', async (req) => {
  const query = String(req.query.query || '').trim();
  if (!query) throw new AppError('Missing query', 400);
  return new TraktClient().search(req.params.types, query, queryInt(req.query.limit, 20, 100));
}));

// Comments (public)
const COMMENT_SORTS = new Set(['likes', 'newest', 'oldest', 'replies', 'highest', 'lowest', 'plays']);
const commentsRoute: TraktHandler = async (req) => {
  const { media, id, season, episode } = req.params;
  const sort = COMMENT_SORTS.has(String(req.query.sort)) ? String(req.query.sort) : 'likes';
  const page = queryInt(req.query.page, 1, 10000);
  const limit = queryInt(req.query.limit, 10, 100);
  let target = `/${media}/${encodeURIComponent(id)}`;
  if (season !== undefined) target += `/seasons/${season}`;
  if (episode !== undefined) target += `/episodes/${episode}`;
  const key = `trakt:comments:${target}:${sort}:${page}:${limit}`;
  return cacheManager.getOrSet('trakt', key, () => new TraktClient().comments(target, sort, page, limit), 10 * 60);
};
router.get('/comments/:media(movies|shows)/:id([\\w.-]+)', traktRoute('Failed to fetch comments', commentsRoute));
router.get('/comments/:media(shows)/:id([\\w.-]+)/seasons/:season(\\d+)', traktRoute('Failed to fetch comments', commentsRoute));
router.get('/comments/:media(shows)/:id([\\w.-]+)/seasons/:season(\\d+)/episodes/:episode(\\d+)', traktRoute('Failed to fetch comments', commentsRoute));
router.get('/comments/:id(\\d+)/replies', traktRoute('Failed to fetch replies', (req) =>
  new TraktClient().commentReplies(Number(req.params.id), queryInt(req.query.page, 1, 10000), queryInt(req.query.limit, 10, 100))));

// Personal lists (auth)
router.get('/users/me/lists', requireAuth, traktRoute('Failed to fetch lists', (req) =>
  client(req).myLists()));
router.post('/users/me/lists', requireAuth, traktRoute('Failed to create list', (req) =>
  client(req).listCreate(requireBodyObject(req.body))));
router.put('/users/me/lists/:id(\\d+)', requireAuth, traktRoute('Failed to update list', (req) =>
  client(req).listUpdate(Number(req.params.id), requireBodyObject(req.body))));
router.delete('/users/me/lists/:id(\\d+)', requireAuth, traktRoute('Failed to delete list', async (req) => {
  await client(req).listDelete(Number(req.params.id));
  return { ok: true };
}));
router.get('/users/me/lists/:id(\\d+)/items/:type(movies|shows|seasons|episodes)?', requireAuth, traktRoute('Failed to fetch list items', (req) =>
  client(req).listItems(Number(req.params.id), req.params.type)));
router.post('/users/me/lists/:id(\\d+)/items', requireAuth, traktRoute('Failed to add to list', (req) =>
  client(req).listItemsAdd(Number(req.params.id), requireBodyObject(req.body))));
router.post('/users/me/lists/:id(\\d+)/items/remove', requireAuth, traktRoute('Failed to remove from list', (req) =>
  client(req).listItemsRemove(Number(req.params.id), requireBodyObject(req.body))));

// Public lists
router.get('/lists/search', traktRoute('Failed to search lists', async (req) => {
  const query = String(req.query.query || '').trim();
  if (!query) throw new AppError('Missing query', 400);
  return new TraktClient().publicListSearch(query, queryInt(req.query.page, 1, 10000), queryInt(req.query.limit, 20, 100));
}));
router.get('/lists/:id(\\d+)/items', traktRoute('Failed to fetch list items', (req) =>
  new TraktClient().publicListItems(Number(req.params.id), queryInt(req.query.page, 1, 10000), queryInt(req.query.limit, 50, 100))));
router.get('/lists/:id(\\d+)', traktRoute('Failed to fetch list', (req) =>
  new TraktClient().publicList(`/lists/${req.params.id}`)));
router.get('/users/:user([\\w.-]+)/lists/:list([\\w.-]+)', traktRoute('Failed to fetch list', (req) =>
  new TraktClient().publicList(`/users/${encodeURIComponent(req.params.user)}/lists/${encodeURIComponent(req.params.list)}`)));

export default router;
