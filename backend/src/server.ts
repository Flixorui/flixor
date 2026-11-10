import 'reflect-metadata';
import express, { Express } from 'express';
import session from 'express-session';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import cookieParser from 'cookie-parser';
import { TypeormStore } from 'connect-typeorm';
import dotenv from 'dotenv';
import path from 'path';

// Load environment variables
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { AppDataSource, initializeDatabase } from './db/data-source';
import { Session } from './db/entities';
import { cacheManager } from './services/cache/CacheManager';
import logger from './utils/logger';
import { authRouter } from './api/auth';
import cacheRoutes from './api/cache';
import imageProxyRoutes from './api/image-proxy';
import tmdbRoutes from './api/tmdb';
import plexRoutes from './api/plex';
import traktRoutes from './api/trakt';
import plextvRoutes from './api/plextv';
import profileRoutes from './api/profiles';
import overseerrRoutes from './api/overseerr';
import versionRoutes from './api/version';
import stremioRoutes from './api/stremio';
import skipSegmentsRoutes from './api/skip-segments';
import syncRoutes from './api/sync';
import { relayRouter } from './services/media/relay';
import { stopAllConversions } from './services/media/ffmpeg';
import { stopAllHlsSessions } from './services/media/hls';
import { requireAuth } from './middleware/auth';
import { errorHandler } from './middleware/errorHandler';
import { requestLogger } from './middleware/requestLogger';
import { mountWebApp } from './utils/webApp';
import { discoveryState, startDiscovery, stopDiscovery } from './services/discovery';

const serverLogger = logger.child({ component: 'server' });

/** Listens on an extra port; false (and a note in the log) when not allowed or already taken. */
function listenIfPossible(app: Express, port: number, host: string): Promise<boolean> {
  return new Promise((resolve) => {
    const extra = app.listen(port, host);
    extra.once('listening', () => {
      serverLogger.info(`🚀 Also listening on port ${port}`);
      resolve(true);
    });
    extra.once('error', (error: NodeJS.ErrnoException) => {
      serverLogger.info(`Port ${port} isn't available (${error.code === 'EACCES' ? 'needs permission' : error.code === 'EADDRINUSE' ? 'in use' : error.code}); using port ${process.env.PORT || '3001'} only`);
      resolve(false);
    });
  });
}

async function startServer() {
  try {
    // Initialize database
    await initializeDatabase();

    // Create Express app
    const app: Express = express();
    const PORT = parseInt(process.env.PORT || '3001', 10);
    const HOST = process.env.HOST || '0.0.0.0';
    const FRONTEND_URL = process.env.FRONTEND_URL || 'http://localhost:5173';
    const frontendUrlObj = new URL(FRONTEND_URL);
    const isHttpsFrontend = frontendUrlObj.protocol === 'https:';
    const cookieSameSiteEnv = (process.env.SESSION_SAMESITE || '').toLowerCase();
    const cookieSecureEnv = (process.env.SESSION_SECURE || '').toLowerCase();
    const cookieSameSite = (cookieSameSiteEnv === 'lax' || cookieSameSiteEnv === 'strict' || cookieSameSiteEnv === 'none')
      ? cookieSameSiteEnv
      : (isHttpsFrontend ? 'none' : 'lax');
    const cookieSecure = cookieSecureEnv === 'true' ? true : cookieSecureEnv === 'false' ? false : isHttpsFrontend;

    // Trust proxy (for secure cookies behind reverse proxy)
    app.set('trust proxy', 1);

    // Basic middleware
    app.use(compression());
    app.use(helmet({
      contentSecurityPolicy: false, // We'll handle CSP separately
      crossOriginEmbedderPolicy: false,
      crossOriginResourcePolicy: { policy: 'cross-origin' }, // allow images/media to be embedded from this server
      // Helmet's default (no-referrer) breaks YouTube embeds (Error 153: YouTube requires the
      // embedding site's referrer). This sends only the origin to other sites.
      referrerPolicy: { policy: 'strict-origin-when-cross-origin' },
    }));

    // CORS configuration
    app.use(cors({
      origin: FRONTEND_URL,
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
      allowedHeaders: [
        'Content-Type',
        'Authorization',
        'X-Requested-With',
        // Allow legacy Trakt headers if the browser sends them in preflight
        'trakt-api-key',
        'trakt-api-version',
      ],
    }));

    // Body parsing
    app.use(express.json({ limit: '10mb' }));
    app.use(express.urlencoded({ extended: true, limit: '10mb' }));
    app.use(cookieParser());

    // Request logging
    app.use(requestLogger);

    // Session configuration
    const sessionRepository = AppDataSource.getRepository(Session);
    app.use(session({
      secret: process.env.SESSION_SECRET || 'change-this-in-production',
      resave: false,
      saveUninitialized: false,
      store: new TypeormStore({
        cleanupLimit: 2,
        limitSubquery: false,
        ttl: 86400, // 1 day in seconds
      }).connect(sessionRepository),
      cookie: {
        secure: cookieSecure,
        httpOnly: true,
        maxAge: 1000 * 60 * 60 * 24 * 7, // 7 days
        sameSite: cookieSameSite as any,
      },
      name: 'plex.sid',
    }));

    // Health check endpoint
    app.get('/health', (req, res) => {
      res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        environment: process.env.NODE_ENV,
        database: AppDataSource.isInitialized ? 'connected' : 'disconnected',
        discovery: discoveryState(),
      });
    });

    // API routes
    app.use('/api/auth/profiles', requireAuth, profileRoutes);
    app.use('/api/auth', authRouter);
    app.use('/api/cache', cacheRoutes);
    app.use('/api/image', imageProxyRoutes);
    app.use('/api/tmdb', tmdbRoutes);
    app.use('/api/plex', plexRoutes);
    app.use('/api/trakt', traktRoutes);
    app.use('/api/plextv', plextvRoutes);
    app.use('/api/overseerr', overseerrRoutes);
    app.use('/api/version', versionRoutes);
    // Loopback only, for FFmpeg (services/media/relay.ts).
    app.use('/internal/media-relay', relayRouter);
    app.use('/api/stremio', requireAuth, stremioRoutes);
    app.use('/api/skip-segments', requireAuth, skipSegmentsRoutes);
    app.use('/api/sync', requireAuth, syncRoutes);

    const webDir = mountWebApp(app);
    if (webDir) serverLogger.info(`🌐 Serving the web app from ${webDir}`);

    // 404 handler
    app.use((req, res) => {
      res.status(404).json({
        error: 'Not Found',
        message: `Cannot ${req.method} ${req.path}`,
      });
    });

    // Error handling middleware (must be last)
    app.use(errorHandler);

    // Start server
    app.listen(PORT, HOST, async () => {
      serverLogger.info(`🚀 Server running at http://${HOST}:${PORT}`);
      serverLogger.info(`📝 Environment: ${process.env.NODE_ENV}`);
      serverLogger.info(`🗄️  Database: ${process.env.DATABASE_PATH}`);
      serverLogger.info(`🔐 Session store: TypeORM/SQLite`);
      // Port 80 too when allowed and free (LISTEN_PORT_80=auto), so http://flixor.local needs no port.
      const port80 = (process.env.LISTEN_PORT_80 || '').toLowerCase() === 'auto' && PORT !== 80
        && await listenIfPossible(app, 80, HOST);
      await startDiscovery({ port: PORT, port80 });
    });

    // Graceful shutdown
    const shutdown = (signal: string) => async () => {
      serverLogger.info(`${signal} signal received: closing server`);
      stopAllHlsSessions();
      stopAllConversions();
      await stopDiscovery();
      await AppDataSource.destroy();
      process.exit(0);
    };
    process.on('SIGTERM', shutdown('SIGTERM'));
    process.on('SIGINT', shutdown('SIGINT'));

  } catch (error) {
    serverLogger.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Start the server
startServer();
