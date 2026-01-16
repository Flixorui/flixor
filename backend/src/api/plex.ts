import { Router, Request, Response, NextFunction } from 'express';
import { getPlexClient, clearPlexClients } from '../services/plex/PlexClient';
import { AppError } from '../middleware/errorHandler';
import { requireAuth, AuthenticatedRequest } from '../middleware/auth';
import { createLogger } from '../utils/logger';
import { AppDataSource } from '../db/data-source';
import { UserSettings } from '../db/entities';
import axios from 'axios';
import { User } from '../db/entities';
import { decryptForUser, isEncrypted } from '../utils/crypto';

const router = Router();
const logger = createLogger('plex-api');

// All Plex routes require authentication
router.use(requireAuth);

/**
 * Get available Plex servers
 * GET /api/plex/servers
 */
router.get('/servers',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const userId = req.user!.id;
      const settingsRepo = AppDataSource.getRepository(UserSettings);
      const settings = await settingsRepo.findOne({ where: { userId } });

      if (!settings?.plexServers) {
        return res.json([]);
      }

      // Return servers without tokens
      const servers = settings.plexServers.map((server: any) => ({
        id: server.id,
        name: server.name,
        host: server.host,
        port: server.port,
        protocol: server.protocol,
        preferredUri: server.preferredUri,
        owned: server.owned,
        publicAddress: server.publicAddress,
        localAddresses: server.localAddresses,
        relayAddresses: server.relayAddresses,
        addressPorts: server.addressPorts,
        isActive: server.id === settings.currentServerId
      }));

      res.json(servers);
    } catch (error: any) {
      logger.error('Failed to get servers', error);
      next(new AppError(error.message || 'Failed to get servers', 500));
    }
  }
);

/**
 * Get ratings for a Plex item by ratingKey
 * GET /api/plex/ratings/:ratingKey
 */
router.get('/ratings/:ratingKey',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { ratingKey } = req.params;
      if (!ratingKey) throw new AppError('ratingKey is required', 400);
      const client = await getPlexClient(req.user!.id);
      const meta: any = await client.getMetadata(String(ratingKey));
      const m = meta as any;

      // Normalize ratings
      let imdb: { rating: number; votes?: number } | null = null;
      let rtCritic: number | undefined;
      let rtAudience: number | undefined;

      try {
        const arr: any[] = Array.isArray((m as any).Rating) ? (m as any).Rating : [];
        for (const r of arr) {
          const img = String(r.image || '').toLowerCase();
          const val = typeof r.value === 'number' ? r.value : (r.value ? Number(r.value) : undefined);
          if (img.startsWith('imdb://') && val != null) {
            imdb = { rating: val };
          } else if (img.startsWith('rottentomatoes://') && val != null) {
            const v10 = Math.round(val * 10);
            if (String(r.type).toLowerCase() === 'critic') rtCritic = v10; else rtAudience = v10;
          }
        }
        // Alternative sources
        if ((m as any).imdbRatingCount && imdb) {
          const votes = Number((m as any).imdbRatingCount);
          if (!Number.isNaN(votes)) imdb.votes = votes;
        }
        if ((m as any).audienceRating && rtAudience == null) {
          const v10 = Math.round(Number((m as any).audienceRating) * 10);
          if (!Number.isNaN(v10)) rtAudience = v10;
        }
      } catch {}

      res.json({ imdb, rottenTomatoes: (rtCritic != null || rtAudience != null) ? { critic: rtCritic, audience: rtAudience } : null });
    } catch (error: any) {
      logger.error(`Failed to get ratings for ratingKey ${req.params.ratingKey}:`, {
        message: error.message,
        stack: error.stack,
        response: error.response?.data,
        status: error.response?.status,
        userId: req.user?.id
      });
      next(new AppError('Failed to get ratings', 500));
    }
  }
);

/**
 * Get connection candidates for a server (derived from stored addresses)
 * GET /api/plex/servers/:id/connections
 */
router.get('/servers/:id/connections',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const userId = req.user!.id;
      const { id } = req.params;
      const settingsRepo = AppDataSource.getRepository(UserSettings);
      const settings = await settingsRepo.findOne({ where: { userId } });

      if (!settings?.plexServers) throw new AppError('No servers found', 404);
      const server = settings.plexServers.find((s: any) => s.id === id);
      if (!server) throw new AppError('Server not found', 404);

      const port = server.port || 32400;
      const protos: Array<'http' | 'https'> = server.protocol === 'https' ? ['https', 'http'] : ['http', 'https'];
      const storedConnections: Array<any> = Array.isArray(server.connections) ? server.connections : [];
      const localAddressSet = new Set((server.localAddresses || []).map((addr: string) => addr.toLowerCase()));
      const addressPorts: Record<string, Array<{port: number, protocol: string, uri?: string}>> = server.addressPorts || {};

      type Candidate = {
        uri: string;
        protocol: 'http' | 'https';
        host: string;
        port: number;
      };
      const candidates = new Map<string, Candidate>();

      const needsBracket = (host: string) => host.includes(':') && !host.startsWith('[') && !host.endsWith(']');
      const stripBrackets = (host: string) => host.replace(/^\[/, '').replace(/\]$/, '');

      const registerCandidate = (protocol: 'http' | 'https', host?: string | null, overridePort?: number, explicitUri?: string | null) => {
        if (!host && !explicitUri) return undefined;

        let uri = explicitUri ?? '';
        let rawHost = host ?? '';
        let derivedProtocol: 'http' | 'https' = protocol;
        let derivedPort = overridePort ?? port;

        if (explicitUri) {
          try {
            const parsed = new URL(explicitUri);
            rawHost = parsed.hostname;
            derivedProtocol = (parsed.protocol.replace(':', '') as 'http' | 'https');
            derivedPort = parsed.port ? parseInt(parsed.port, 10) : derivedPort;
          } catch {}
        }

        // Look up address-specific port and URI from the mapping if no override
        if (!overridePort && host && addressPorts[host]) {
          const portEntry = addressPorts[host].find(p => p.protocol === protocol);
          if (portEntry) {
            derivedPort = portEntry.port;
            // For HTTPS, use the stored URI to avoid SSL certificate errors
            if (protocol === 'https' && portEntry.uri && !explicitUri) {
              uri = portEntry.uri;
              // Extract hostname from the plex.direct URI
              try {
                const parsed = new URL(portEntry.uri);
                rawHost = parsed.hostname;
                derivedProtocol = (parsed.protocol.replace(':', '') as 'http' | 'https');
                derivedPort = parsed.port ? parseInt(parsed.port, 10) : derivedPort;
              } catch {}
            }
          }
        }

        if (!uri) {
          if (!host) return undefined;
          const formattedHost = needsBracket(host) ? `[${host}]` : host;
          uri = `${protocol}://${formattedHost}:${derivedPort}`;
          rawHost = host;
        }

        if (!rawHost) {
          try {
            const parsed = new URL(uri);
            rawHost = parsed.hostname;
            derivedProtocol = (parsed.protocol.replace(':', '') as 'http' | 'https');
            derivedPort = parsed.port ? parseInt(parsed.port, 10) : derivedPort;
          } catch {}
        }

        if (!uri) return undefined;
        if (!candidates.has(uri)) {
          candidates.set(uri, { uri, protocol: derivedProtocol, host: rawHost, port: derivedPort });
        }
        return uri;
      };

      const currentUri = registerCandidate(server.protocol, server.host);

      if (server.publicAddress) {
        for (const proto of protos) {
          registerCandidate(proto, server.publicAddress);
        }
      }

      for (const addr of server.localAddresses || []) {
        for (const proto of protos) {
          registerCandidate(proto, addr);
        }
      }

      // Try relay addresses as last resort (lower priority)
      for (const addr of server.relayAddresses || []) {
        for (const proto of protos) {
          registerCandidate(proto, addr);
        }
      }

      const preferred = typeof server.preferredUri === 'string' ? server.preferredUri : undefined;
      if (preferred) {
        registerCandidate(server.protocol, undefined, undefined, preferred);
      }

      const normalizeUri = (uri?: string | null) => {
        if (!uri) return null;
        try {
          const parsed = new URL(uri);
          const proto = parsed.protocol.replace(':', '');
          const host = parsed.hostname.toLowerCase();
          const p = parsed.port ? parseInt(parsed.port, 10) : (proto === 'https' ? 443 : 32400);
          return `${proto}://${host}:${p}`;
        } catch {
          return uri;
        }
      };

      const normalizedCurrent = normalizeUri(currentUri);
      const normalizedPreferred = normalizeUri(preferred);

      const findStoredConnection = (candidate: Candidate) => {
        const lowerHost = stripBrackets(candidate.host || '').toLowerCase();
        for (const entry of storedConnections) {
          if (!entry) continue;
          if (entry.uri && entry.uri === candidate.uri) return entry;
          if (entry.uri) {
            try {
              const u = new URL(entry.uri);
              if (u.hostname.toLowerCase() === lowerHost) return entry;
            } catch {}
          }
          if (entry.address && String(entry.address).toLowerCase() === lowerHost) return entry;
        }
        return undefined;
      };

      const isPrivateIPv4 = (host: string) => {
        const cleaned = stripBrackets(host);
        const match = cleaned.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
        if (!match) return false;
        const [first, second] = [parseInt(match[1], 10), parseInt(match[2], 10)];
        if (first === 10) return true;
        if (first === 172 && second >= 16 && second <= 31) return true;
        if (first === 192 && second === 168) return true;
        if (first === 169 && second === 254) return true;
        if (first === 127) return true;
        return false;
      };

      const isLikelyLocal = (host?: string) => {
        if (!host) return false;
        const normalized = stripBrackets(host).toLowerCase();
        if (localAddressSet.has(normalized)) return true;
        if (normalized === 'localhost') return true;
        if (normalized.endsWith('.local')) return true;
        if (isPrivateIPv4(normalized)) return true;
        if (normalized.startsWith('fe80:') || normalized.startsWith('fd')) return true;
        return false;
      };

      const connections = Array.from(candidates.values()).map(candidate => {
        const match = findStoredConnection(candidate) || {};
        const rawHost = candidate.host || '';

        const localFlag = typeof match.local === 'boolean' ? match.local : isLikelyLocal(rawHost);
        const relayFlag = typeof match.relay === 'boolean' ? match.relay : undefined;
        const ipv6Flag = typeof match.IPv6 === 'boolean'
          ? match.IPv6
          : stripBrackets(rawHost).includes(':') ? true : undefined;

        const normalizedCandidate = normalizeUri(candidate.uri);
        const entry: any = {
          uri: candidate.uri,
          protocol: candidate.protocol,
          isCurrent: normalizedCurrent ? normalizedCandidate === normalizedCurrent : false,
          isPreferred: normalizedPreferred ? normalizedCandidate === normalizedPreferred : false,
        };

        if (localFlag !== undefined) entry.local = localFlag;
        if (relayFlag !== undefined) entry.relay = relayFlag;
        if (ipv6Flag !== undefined) entry.IPv6 = ipv6Flag;

        return entry;
      });

      res.json({ serverId: id, connections });
    } catch (error: any) {
      logger.error('Failed to get server connections', error);
      next(error instanceof AppError ? error : new AppError('Failed to get connections', 500));
    }
  }
);

/**
 * Set preferred endpoint for a server (host/port/protocol updated)
 * POST /api/plex/servers/:id/endpoint { uri: string, test?: boolean }
 */
router.post('/servers/:id/endpoint',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const userId = req.user!.id;
      const { id } = req.params;
      const { uri, test } = req.body || {};
      if (!uri || typeof uri !== 'string') throw new AppError('uri is required', 400);

      let u: URL;
      try { u = new URL(uri); } catch { throw new AppError('Invalid uri', 400); }
      const protocol = (u.protocol.replace(':','') as 'http'|'https');
      const host = u.hostname;
      const port = parseInt(u.port || '32400', 10);

      const settingsRepo = AppDataSource.getRepository(UserSettings);
      const settings = await settingsRepo.findOne({ where: { userId } });
      if (!settings) throw new AppError('Settings not found', 404);
      if (!settings.plexServers) throw new AppError('No servers configured', 400);
      const idx = settings.plexServers.findIndex((s: any) => s.id === id);
      if (idx < 0) throw new AppError('Server not found', 404);

      // Update stored endpoint and remember preferred URI
      settings.plexServers[idx].host = host;
      settings.plexServers[idx].port = port;
      settings.plexServers[idx].protocol = protocol;
      settings.plexServers[idx].preferredUri = uri;
      await settingsRepo.save(settings);

      // Clear cached client so new base is used
      clearPlexClients(userId);

      if (test) {
        try {
          const client = await getPlexClient(userId, id);
          const ok = await client.testConnection();
          if (!ok) throw new Error('Connection failed');
        } catch (e: any) {
          throw new AppError('Selected endpoint is unreachable', 400);
        }
      }

      res.json({
        message: 'Endpoint updated',
        server: {
          id,
          host,
          port,
          protocol,
          preferredUri: uri,
        }
      });
    } catch (error: any) {
      logger.error('Failed to set server endpoint', error);
      next(error instanceof AppError ? error : new AppError('Failed to set endpoint', 500));
    }
  }
);

/**
 * Set current server
 * POST /api/plex/servers/current
 */
router.post('/servers/current',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const userId = req.user!.id;
      const { serverId } = req.body;

      if (!serverId) {
        throw new AppError('Server ID is required', 400);
      }

      const settingsRepo = AppDataSource.getRepository(UserSettings);
      const settings = await settingsRepo.findOne({ where: { userId } });

      if (!settings) {
        throw new AppError('Settings not found', 404);
      }

      const server = settings.plexServers?.find((s: any) => s.id === serverId);
      if (!server) {
        throw new AppError('Server not found', 404);
      }

      settings.currentServerId = serverId;
      await settingsRepo.save(settings);

      // Clear cached clients for this user
      clearPlexClients(userId);

      res.json({
        message: 'Current server updated',
        serverId
      });
    } catch (error: any) {
      logger.error('Failed to set current server', error);
      next(error instanceof AppError ? error : new AppError('Failed to set current server', 500));
    }
  }
);

/**
 * Get libraries
 * GET /api/plex/libraries
 */
router.get('/libraries',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const client = await getPlexClient(req.user!.id);
      const libraries = await client.getLibraries();
      res.json(libraries);
    } catch (error: any) {
      logger.error('Failed to get libraries', error);
      next(new AppError(error.message || 'Failed to get libraries', 500));
    }
  }
);

/**
 * Get library contents
 * GET /api/plex/library/:id/all
 */
router.get('/library/:id/all',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const offset = parseInt(req.query.offset as string) || 0;
      const limit = parseInt(req.query.limit as string) || 50;

      // Collect additional query params (e.g., sort, type)
      const extraParams: Record<string, any> = {};
      Object.entries(req.query).forEach(([k, v]) => {
        if (!['offset', 'limit'].includes(k) && v !== undefined) {
          extraParams[k] = v;
        }
      });

      const client = await getPlexClient(req.user!.id);
      const container = await client.getLibraryContents(id, offset, limit, extraParams);

      res.json(container);
    } catch (error: any) {
      logger.error('Failed to get library contents', error);
      next(new AppError(error.message || 'Failed to get library contents', 500));
    }
  }
);

/**
 * Get secondary directory entries (e.g., genre/year)
 * GET /api/plex/library/:id/:directory
 */
router.get('/library/:id/:directory',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { id, directory } = req.params;
      const client = await getPlexClient(req.user!.id);
      const mc = await client.getLibrarySecondary(id, directory);
      res.json(mc);
    } catch (error: any) {
      logger.error('Failed to get library secondary', error);
      next(new AppError(error.message || 'Failed to get library secondary', 500));
    }
  }
);

/**
 * Get collections for a library section
 * GET /api/plex/library/:id/collections
 */
router.get('/library/:id/collections',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      const client = await getPlexClient(req.user!.id);
      const mc = await client.getLibraryCollections(id);
      res.json(mc);
    } catch (error: any) {
      logger.error('Failed to get collections', error);
      next(new AppError(error.message || 'Failed to get collections', 500));
    }
  }
);

/**
 * Generic directory fetch under /library
 * GET /api/plex/dir/*
 */
router.get('/dir/*',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const path = '/' + (req.params[0] || '').replace(/^\//, '');
      if (!path.startsWith('/library/')) {
        throw new AppError('Only /library paths are allowed', 400);
      }
      const client = await getPlexClient(req.user!.id);
      const mc = await client.getDir(path, req.query as any);
      res.json(mc);
    } catch (error: any) {
      logger.error('Failed to fetch directory', error);
      next(new AppError(error.message || 'Failed to fetch directory', 500));
    }
  }
);

/**
 * Get metadata for an item
 * GET /api/plex/metadata/:id
 */
router.get('/metadata/:id',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;

      const client = await getPlexClient(req.user!.id);
      const includeExtras = req.query.includeExtras === '1' || req.query.includeExtras === 'true';
      const includeExternalMedia = req.query.includeExternalMedia === '1' || req.query.includeExternalMedia === 'true';
      const includeChildren = req.query.includeChildren === '1' || req.query.includeChildren === 'true';

      if (includeExtras || includeExternalMedia || includeChildren) {
        const metadata = await client.getMetadataWithParams(id, {
          includeExtras: includeExtras ? 1 : undefined,
          includeExternalMedia: includeExternalMedia ? 1 : undefined,
          includeChildren: includeChildren ? 1 : undefined,
        });
        res.json(metadata);
      } else {
        const metadata = await client.getMetadata(id);
        res.json(metadata);
      }
    } catch (error: any) {
      logger.error(`Failed to get metadata for ratingKey ${req.params.id}:`, {
        message: error.message,
        stack: error.stack,
        response: error.response?.data,
        status: error.response?.status,
        userId: req.user?.id
      });
      next(new AppError(error.message || 'Failed to get metadata', 500));
    }
  }
);

/**
 * Search across all libraries
 * GET /api/plex/search
 */
router.get('/search',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const query = req.query.query as string;
      const type = req.query.type ? parseInt(req.query.type as string, 10) as 1|2 : undefined;

      if (!query) {
        throw new AppError('Query parameter is required', 400);
      }

      const client = await getPlexClient(req.user!.id);
      const results = typeof type === 'number' ? await client.searchTyped(query, type) : await client.search(query);

      res.json(results);
    } catch (error: any) {
      logger.error('Search failed', error);
      next(error instanceof AppError ? error : new AppError('Search failed', 500));
    }
  }
);

/**
 * Find by GUID across libraries (optional type 1=movie, 2=show)
 * GET /api/plex/findByGuid?guid=tmdb://1234[&type=1]
 */
router.get('/findByGuid',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const guid = String(req.query.guid || '');
      const type = req.query.type ? parseInt(String(req.query.type), 10) as 1|2 : undefined;
      if (!guid) throw new AppError('guid is required', 400);
      const client = await getPlexClient(req.user!.id);
      const mc = await client.findByGuid(guid, type);
      res.json(mc);
    } catch (error: any) {
      logger.error('Find by GUID failed', error);
      next(error instanceof AppError ? error : new AppError('Find by GUID failed', 500));
    }
  }
);

/**
 * Get on deck items
 * GET /api/plex/ondeck
 */
router.get('/ondeck',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const client = await getPlexClient(req.user!.id);
      const onDeck = await client.getOnDeck();

      res.json(onDeck);
    } catch (error: any) {
      logger.error('Failed to get on deck', error);
      next(new AppError(error.message || 'Failed to get on deck items', 500));
    }
  }
);

/**
 * Get continue watching
 * GET /api/plex/continue
 */
router.get('/continue',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const client = await getPlexClient(req.user!.id);
      const continueWatching = await client.getContinueWatching();

      res.json(continueWatching);
    } catch (error: any) {
      logger.error('Failed to get continue watching', error);
      next(new AppError(error.message || 'Failed to get continue watching', 500));
    }
  }
);

/**
 * Get recently added
 * GET /api/plex/recent
 */
router.get('/recent',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const libraryKey = req.query.library as string | undefined;

      const client = await getPlexClient(req.user!.id);
      const recent = await client.getRecentlyAdded(libraryKey);

      res.json(recent);
    } catch (error: any) {
      logger.error('Failed to get recently added', error);
      next(new AppError(error.message || 'Failed to get recently added', 500));
    }
  }
);

/**
 * Update playback progress
 * POST /api/plex/progress
 */
router.post('/progress',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { ratingKey, time, duration, state, sessionId, isTranscoding } = req.body as any;

      if (!ratingKey || time === undefined || duration === undefined) {
        throw new AppError('Missing required parameters', 400);
      }

      const client = await getPlexClient(req.user!.id);
      await client.updateProgress(String(ratingKey), Number(time), Number(duration), state, sessionId, isTranscoding);

      res.json({
        message: 'Progress updated',
        ratingKey,
        time,
        duration,
        state: state || null,
      });
    } catch (error: any) {
      logger.error('Failed to update progress', error);
      next(error instanceof AppError ? error : new AppError(error.message || 'Failed to update progress', 500));
    }
  }
);

/**
 * Scrobble (mark as watched)
 * POST /api/plex/scrobble
 */
router.post('/scrobble',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { ratingKey } = req.body;

      if (!ratingKey) {
        throw new AppError('Rating key is required', 400);
      }

      const client = await getPlexClient(req.user!.id);
      await client.scrobble(ratingKey);

      res.json({
        message: 'Item marked as watched',
        ratingKey
      });
    } catch (error: any) {
      logger.error('Failed to scrobble', error);
      next(error instanceof AppError ? error : new AppError('Failed to scrobble', 500));
    }
  }
);

/**
 * Rate an item
 * POST /api/plex/rate
 */
router.post('/rate',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { ratingKey, rating } = req.body;

      if (!ratingKey || rating === undefined) {
        throw new AppError('Rating key and rating are required', 400);
      }

      if (rating < 0 || rating > 10) {
        throw new AppError('Rating must be between 0 and 10', 400);
      }

      const client = await getPlexClient(req.user!.id);
      await client.rate(ratingKey, rating);

      res.json({
        message: 'Rating updated',
        ratingKey,
        rating
      });
    } catch (error: any) {
      logger.error('Failed to rate item', error);
      next(error instanceof AppError ? error : new AppError('Failed to rate item', 500));
    }
  }
);

/**
 * Get transcode decision
 * POST /api/plex/transcode/decision
 */
router.post('/transcode/decision',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { ratingKey, ...options } = req.body;

      if (!ratingKey) {
        throw new AppError('Rating key is required', 400);
      }

      const client = await getPlexClient(req.user!.id);
      const decision = await client.getTranscodeDecision(ratingKey, options);

      res.json(decision);
    } catch (error: any) {
      logger.error('Failed to get transcode decision', error);
      next(error instanceof AppError ? error : new AppError('Failed to get transcode decision', 500));
    }
  }
);

/**
 * Get streaming URL
 * GET /api/plex/stream/:ratingKey
 */
router.get('/stream/:ratingKey',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { ratingKey } = req.params;

      // Accept both 'quality' and 'maxVideoBitrate' (macOS app uses maxVideoBitrate)
      const quality = req.query.quality || req.query.maxVideoBitrate;
      const resolution = req.query.resolution || req.query.videoResolution;

      const options = {
        quality,
        resolution,
        protocol: req.query.protocol,
        directPlay: req.query.directPlay,
        directStream: req.query.directStream,
        autoAdjustQuality: req.query.autoAdjustQuality,
        mediaIndex: req.query.mediaIndex,
        partIndex: req.query.partIndex,
        audioStreamID: req.query.audioStreamID,
        subtitleStreamID: req.query.subtitleStreamID,
      };

      const client = await getPlexClient(req.user!.id);
      const { url: streamUrl, sessionId } = await client.getStreamingUrl(ratingKey, options);

      res.json({
        url: streamUrl,
        sessionId,
        ratingKey,
        options
      });
    } catch (error: any) {
      logger.error('Failed to get streaming URL', error);
      next(error instanceof AppError ? error : new AppError('Failed to get streaming URL', 500));
    }
  }
);

/**
 * Proxy media stream
 * GET /api/plex/proxy/:path*
 */
router.get('/proxy/*',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const path = req.params[0];
      const client = await getPlexClient(req.user!.id);
      const serverInfo = client.getServerInfo();

      // Build the full URL
      const qs = new URLSearchParams(req.query as any).toString();
      const base = `${serverInfo.protocol}://${serverInfo.host}:${serverInfo.port}/${path}`;
      const url = qs ? `${base}?${qs}` : base;

      // Add token if not present
      const urlWithToken = url.includes('X-Plex-Token')
        ? url
        : `${url}${url.includes('?') ? '&' : '?'}X-Plex-Token=${serverInfo.accessToken}`;

      // Proxy the request
      const axios = require('axios');
      const response = await axios({
        method: 'GET',
        url: urlWithToken,
        responseType: 'stream',
        headers: {
          'Range': req.headers.range,
          'Accept': req.headers.accept,
        }
      });

      // Forward headers
      Object.keys(response.headers).forEach(key => {
        res.setHeader(key, response.headers[key]);
      });

      // Pipe the stream
      response.data.pipe(res);
    } catch (error: any) {
      logger.error('Failed to proxy media', error);
      next(new AppError('Failed to proxy media stream', 500));
    }
  }
);

/**
 * Test server connection
 * GET /api/plex/test
 */
router.get('/test',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const serverId = req.query.serverId as string | undefined;
      const client = await getPlexClient(req.user!.id, serverId);

      const isConnected = await client.testConnection();
      const capabilities = isConnected ? await client.getServerCapabilities() : null;

      res.json({
        connected: isConnected,
        server: client.getServerInfo().name,
        capabilities
      });
    } catch (error: any) {
      logger.error('Connection test failed', error);
      next(new AppError(error.message || 'Connection test failed', 500));
    }
  }
);

export default router;
/**
 * Get ratings from Plex VOD for an item id (Discover/Watch)
 * GET /api/plex/vod/ratings/:id
 */
router.get('/vod/ratings/:id',
  async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    try {
      const { id } = req.params;
      if (!id) throw new AppError('id is required', 400);
      // Get Plex account token for current user
      const userRepo = AppDataSource.getRepository(User);
      const user = await userRepo.findOne({ where: { id: req.user!.id }, select: ['id', 'plexToken'] });
      if (!user?.plexToken) throw new AppError('Plex account not authenticated', 401);
      const accountToken = isEncrypted(user.plexToken) ? decryptForUser(user.id, user.plexToken) : user.plexToken;

      const params = new URLSearchParams({
        includeReviews: '1',
        includeExternalMedia: '1',
        'X-Plex-Product': process.env.PLEX_PRODUCT || 'Plex Web',
        'X-Plex-Version': process.env.PLEX_VERSION || '4.128.1',
        'X-Plex-Client-Identifier': process.env.PLEX_CLIENT_ID || 'plex-media-backend',
        'X-Plex-Platform': 'Web',
        'X-Plex-Language': 'en',
      });
      const url = `https://vod.provider.plex.tv/library/metadata/${encodeURIComponent(id)}?${params.toString()}`;
      const resp = await axios.get(url, {
        headers: { 'X-Plex-Token': accountToken, Accept: 'application/json' },
        timeout: 10000,
      });
      const m = resp.data?.MediaContainer?.Metadata?.[0] || {};

      // Normalize ratings as in server endpoint
      let imdb: { rating: number; votes?: number } | null = null;
      let rtCritic: number | undefined;
      let rtAudience: number | undefined;
      try {
        const arr: any[] = Array.isArray(m.Rating) ? m.Rating : [];
        for (const r of arr) {
          const img = String(r.image || '').toLowerCase();
          const val = typeof r.value === 'number' ? r.value : (r.value ? Number(r.value) : undefined);
          if (img.startsWith('imdb://') && val != null) {
            imdb = { rating: val };
          } else if (img.startsWith('rottentomatoes://') && val != null) {
            const v10 = Math.round(val * 10);
            if (String(r.type).toLowerCase() === 'critic') rtCritic = v10; else rtAudience = v10;
          }
        }
        if (m.imdbRatingCount && imdb) {
          const votes = Number(m.imdbRatingCount);
          if (!Number.isNaN(votes)) imdb.votes = votes;
        }
        if (m.audienceRating && rtAudience == null) {
          const v10 = Math.round(Number(m.audienceRating) * 10);
          if (!Number.isNaN(v10)) rtAudience = v10;
        }
      } catch {}

      res.json({ imdb, rottenTomatoes: (rtCritic != null || rtAudience != null) ? { critic: rtCritic, audience: rtAudience } : null });
    } catch (e: any) {
      logger.error('Failed to get VOD ratings', e);
      next(new AppError('Failed to get VOD ratings', 500));
    }
  }
);
