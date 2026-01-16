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

export default router;
