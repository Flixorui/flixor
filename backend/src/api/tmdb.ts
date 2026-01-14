import { Router, Request, Response, NextFunction } from 'express';
import { getUserTMDBClient, getDefaultTMDBClient, TMDBClient } from '../services/tmdb/TMDBClient';
import { AppError } from '../middleware/errorHandler';
import { requireAuth, AuthenticatedRequest } from '../middleware/auth';
import { tmdbCache } from '../middleware/cache';
import { createLogger } from '../utils/logger';
import { AppDataSource } from '../db/data-source';
import { UserSettings } from '../db/entities';

const router = Router();
const logger = createLogger('tmdb-api');

/**
 * Get TMDB client for request
 */
async function getTMDBClient(req: Request): Promise<TMDBClient> {
  const userId = (req as any).session?.userId;
  if (userId) {
    return getUserTMDBClient(userId);
  }
  return getDefaultTMDBClient();
}

/**
 * Get trending content
 * GET /api/tmdb/trending/:mediaType/:timeWindow
 */
router.get('/trending/:mediaType/:timeWindow',
  tmdbCache('trending'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { mediaType, timeWindow } = req.params;
      const page = parseInt(req.query.page as string) || 1;

      if (!['all', 'movie', 'tv', 'person'].includes(mediaType)) {
        throw new AppError('Invalid media type', 400);
      }
      if (!['day', 'week'].includes(timeWindow)) {
        throw new AppError('Invalid time window', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.getTrending(
        mediaType as any,
        timeWindow as any,
        page
      );

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get trending', error);
      next(new AppError(error.message || 'Failed to get trending content', 500));
    }
  }
);

/**
 * Search all content types
 * GET /api/tmdb/search/multi?query=...
 */
router.get('/search/multi',
  tmdbCache('search'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const query = req.query.query as string;
      const page = parseInt(req.query.page as string) || 1;

      if (!query) {
        throw new AppError('Query parameter is required', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.searchMulti(query, page);

      res.json(data);
    } catch (error: any) {
      logger.error('Search failed', error);
      next(new AppError(error.message || 'Search failed', 500));
    }
  }
);

/**
 * Search movies
 * GET /api/tmdb/search/movie?query=...
 */
router.get('/search/movie',
  tmdbCache('search'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const query = req.query.query as string;
      const year = req.query.year ? parseInt(req.query.year as string) : undefined;
      const page = parseInt(req.query.page as string) || 1;

      if (!query) {
        throw new AppError('Query parameter is required', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.searchMovies(query, year, page);

      res.json(data);
    } catch (error: any) {
      logger.error('Movie search failed', error);
      next(new AppError(error.message || 'Movie search failed', 500));
    }
  }
);

/**
 * Search TV shows
 * GET /api/tmdb/search/tv?query=...
 */
router.get('/search/tv',
  tmdbCache('search'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const query = req.query.query as string;
      const year = req.query.year ? parseInt(req.query.year as string) : undefined;
      const page = parseInt(req.query.page as string) || 1;

      if (!query) {
        throw new AppError('Query parameter is required', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.searchTVShows(query, year, page);

      res.json(data);
    } catch (error: any) {
      logger.error('TV search failed', error);
      next(new AppError(error.message || 'TV search failed', 500));
    }
  }
);

/**
 * Get movie details
 * GET /api/tmdb/movie/:id
 */
router.get('/movie/:id',
  tmdbCache('details'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const appendToResponse = req.query.append_to_response as string;

      const client = await getTMDBClient(req);
      const data = await client.getMovieDetails(id, appendToResponse);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get movie details', error);
      next(new AppError(error.message || 'Failed to get movie details', 500));
    }
  }
);

/**
 * Get TV show details
 * GET /api/tmdb/tv/:id
 */
router.get('/tv/:id',
  tmdbCache('details'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const appendToResponse = req.query.append_to_response as string;

      const client = await getTMDBClient(req);
      const data = await client.getTVDetails(id, appendToResponse);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get TV details', error);
      next(new AppError(error.message || 'Failed to get TV details', 500));
    }
  }
);

/**
 * Get TV season details
 * GET /api/tmdb/tv/:id/season/:seasonNumber
 */
router.get('/tv/:id/season/:seasonNumber',
  tmdbCache('details'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id, seasonNumber } = req.params;

      const client = await getTMDBClient(req);
      const data = await client.getTVSeasonDetails(id, parseInt(seasonNumber));

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get TV season details', error);
      next(new AppError(error.message || 'Failed to get TV season details', 500));
    }
  }
);

/**
 * Get movie credits
 * GET /api/tmdb/movie/:id/credits
 */
router.get('/movie/:id/credits',
  tmdbCache('credits'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;

      const client = await getTMDBClient(req);
      const data = await client.getMovieCredits(id);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get movie credits', error);
      next(new AppError(error.message || 'Failed to get movie credits', 500));
    }
  }
);

/**
 * Get TV credits
 * GET /api/tmdb/tv/:id/credits
 */
router.get('/tv/:id/credits',
  tmdbCache('credits'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;

      const client = await getTMDBClient(req);
      const data = await client.getTVCredits(id);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get TV credits', error);
      next(new AppError(error.message || 'Failed to get TV credits', 500));
    }
  }
);

/**
 * Get recommendations
 * GET /api/tmdb/:mediaType/:id/recommendations
 */
router.get('/:mediaType/:id/recommendations',
  tmdbCache('details'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { mediaType, id } = req.params;
      const page = parseInt(req.query.page as string) || 1;

      if (!['movie', 'tv'].includes(mediaType)) {
        throw new AppError('Invalid media type', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.getRecommendations(mediaType as any, id, page);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get recommendations', error);
      next(new AppError(error.message || 'Failed to get recommendations', 500));
    }
  }
);

/**
 * Get similar content
 * GET /api/tmdb/:mediaType/:id/similar
 */
router.get('/:mediaType/:id/similar',
  tmdbCache('details'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { mediaType, id } = req.params;
      const page = parseInt(req.query.page as string) || 1;

      if (!['movie', 'tv'].includes(mediaType)) {
        throw new AppError('Invalid media type', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.getSimilar(mediaType as any, id, page);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get similar', error);
      next(new AppError(error.message || 'Failed to get similar content', 500));
    }
  }
);

/**
 * Get images
 * GET /api/tmdb/:mediaType/:id/images
 */
router.get('/:mediaType/:id/images',
  tmdbCache('images'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { mediaType, id } = req.params;
      // Accept both include_image_language (TMDB native) and language (legacy)
      const language = (req.query.include_image_language || req.query.language) as string || 'en,null';

      if (!['movie', 'tv'].includes(mediaType)) {
        throw new AppError('Invalid media type', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.getImages(mediaType as any, id, language);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get images', error);
      next(new AppError(error.message || 'Failed to get images', 500));
    }
  }
);

/**
 * Get videos
 * GET /api/tmdb/:mediaType/:id/videos
 */
router.get('/:mediaType/:id/videos',
  tmdbCache('details'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { mediaType, id } = req.params;

      if (!['movie', 'tv'].includes(mediaType)) {
        throw new AppError('Invalid media type', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.getVideos(mediaType as any, id);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get videos', error);
      next(new AppError(error.message || 'Failed to get videos', 500));
    }
  }
);

/**
 * Get external IDs (IMDb, TVDb, etc.)
 * GET /api/tmdb/:mediaType/:id/external_ids
 */
router.get('/:mediaType/:id/external_ids',
  tmdbCache('details'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { mediaType, id } = req.params;

      if (!['movie', 'tv'].includes(mediaType)) {
        throw new AppError('Invalid media type', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.getExternalIds(mediaType as any, id);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get external IDs', error);
      next(new AppError(error.message || 'Failed to get external IDs', 500));
    }
  }
);

/**
 * Get popular content
 * GET /api/tmdb/:mediaType/popular
 */
router.get('/:mediaType/popular',
  tmdbCache('trending'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { mediaType } = req.params;
      const page = parseInt(req.query.page as string) || 1;

      if (!['movie', 'tv'].includes(mediaType)) {
        throw new AppError('Invalid media type', 400);
      }

      const client = await getTMDBClient(req);
      const data = await client.getPopular(mediaType as any, page);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get popular', error);
      next(new AppError(error.message || 'Failed to get popular content', 500));
    }
  }
);

/**
 * Get upcoming movies
 * GET /api/tmdb/movie/upcoming
 */
router.get('/movie/upcoming',
  tmdbCache('trending'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const region = req.query.region as string;
      const page = parseInt(req.query.page as string) || 1;

      const client = await getTMDBClient(req);
      const data = await client.getUpcoming(region, page);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get upcoming', error);
      next(new AppError(error.message || 'Failed to get upcoming movies', 500));
    }
  }
);

/**
 * Get person details
 * GET /api/tmdb/person/:id
 */
router.get('/person/:id',
  tmdbCache('details'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;

      const client = await getTMDBClient(req);
      const data = await client.getPersonDetails(id);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get person details', error);
      next(new AppError(error.message || 'Failed to get person details', 500));
    }
  }
);

/**
 * Get person credits
 * GET /api/tmdb/person/:id/combined_credits
 */
router.get('/person/:id/combined_credits',
  tmdbCache('credits'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;

      const client = await getTMDBClient(req);
      const data = await client.getPersonCombinedCredits(id);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to get person credits', error);
      next(new AppError(error.message || 'Failed to get person credits', 500));
    }
  }
);

/**
 * Discover movies
 * GET /api/tmdb/discover/movie
 */
router.get('/discover/movie',
  tmdbCache('search'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const client = await getTMDBClient(req);
      const data = await client.discoverMovies(req.query);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to discover movies', error);
      next(new AppError(error.message || 'Failed to discover movies', 500));
    }
  }
);

/**
 * Discover TV shows
 * GET /api/tmdb/discover/tv
 */
router.get('/discover/tv',
  tmdbCache('search'),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const client = await getTMDBClient(req);
      const data = await client.discoverTV(req.query);

      res.json(data);
    } catch (error: any) {
      logger.error('Failed to discover TV', error);
      next(new AppError(error.message || 'Failed to discover TV shows', 500));
    }
  }
);

/**
 * Validate API key
 * POST /api/tmdb/validate-key
 */
router.post('/validate-key',
  requireAuth,
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { apiKey } = req.body;

      if (!apiKey) {
        throw new AppError('API key is required', 400);
      }

      // Test the key
      const testClient = new TMDBClient(apiKey);
      const isValid = await testClient.validateKey();

      if (isValid) {
        // Save the key to user settings
        const settingsRepo = AppDataSource.getRepository(UserSettings);
        const userId = req.user!.id;

        let settings = await settingsRepo.findOne({ where: { userId } });
        if (!settings) {
          settings = settingsRepo.create({ userId });
        }

        settings.tmdbApiKey = apiKey;
        await settingsRepo.save(settings);

        res.json({
          valid: true,
          message: 'API key validated and saved'
        });
      } else {
        res.json({
          valid: false,
          message: 'Invalid API key'
        });
      }
    } catch (error: any) {
      logger.error('Failed to validate API key', error);
      next(new AppError('Failed to validate API key', 500));
    }
  }
);

/**
 * Get current API key info
 * GET /api/tmdb/key-info
 */
router.get('/key-info',
  requireAuth,
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const userId = req.user!.id;
      const settingsRepo = AppDataSource.getRepository(UserSettings);
      const settings = await settingsRepo.findOne({ where: { userId } });

      const hasCustomKey = !!settings?.tmdbApiKey;
      const client = await getUserTMDBClient(userId);
      const stats = client.getUsageStats();

      res.json({
        hasCustomKey,
        isUsingDefault: !hasCustomKey,
        stats,
        rateLimit: hasCustomKey
          ? { requests: 1000, window: 1, unit: 'second', concurrency: 100 }
          : { requests: 200, window: 1, unit: 'second', concurrency: 50 }
      });
    } catch (error: any) {
      logger.error('Failed to get key info', error);
      next(new AppError('Failed to get API key info', 500));
    }
  }
);

/**
 * Remove custom API key
 * DELETE /api/tmdb/key
 */
router.delete('/key',
  requireAuth,
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const userId = req.user!.id;
      const settingsRepo = AppDataSource.getRepository(UserSettings);
      const settings = await settingsRepo.findOne({ where: { userId } });

      if (settings) {
        settings.tmdbApiKey = undefined;
        await settingsRepo.save(settings);
      }

      res.json({
        message: 'Custom API key removed. Using default key.'
      });
    } catch (error: any) {
      logger.error('Failed to remove API key', error);
      next(new AppError('Failed to remove API key', 500));
    }
  }
);

/**
 * Get usage statistics
 * GET /api/tmdb/usage
 */
router.get('/usage',
  requireAuth,
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const userId = req.user!.id;
      const client = await getUserTMDBClient(userId);
      const stats = client.getUsageStats();

      res.json(stats);
    } catch (error: any) {
      logger.error('Failed to get usage stats', error);
      next(new AppError('Failed to get usage statistics', 500));
    }
  }
);

export default router;
