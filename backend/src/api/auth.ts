import { Router, Request, Response, NextFunction } from 'express';
import axios from 'axios';
import jwt from 'jsonwebtoken';
import { AppDataSource } from '../db/data-source';
import { User, UserSettings } from '../db/entities';
import { AppError } from '../middleware/errorHandler';
import { requireAuth, AuthenticatedRequest } from '../middleware/auth';
import { createLogger } from '../utils/logger';
import crypto from 'crypto';
import { encryptForUser, decryptForUser, isEncrypted } from '../utils/crypto';

const router = Router();
const logger = createLogger('auth');

// Plex.tv API endpoints
const PLEX_TV_URL = 'https://plex.tv';

// Helper to get Plex headers
export function getPlexHeaders(clientId: string, token?: string) {
  const headers: any = {
    'X-Plex-Product': 'Plex Web',
    'X-Plex-Version': '4.128.1',
    'X-Plex-Client-Identifier': clientId,
    'X-Plex-Device': 'OSX',
    'X-Plex-Device-Name': 'Chrome',
    'X-Plex-Device-Screen-Resolution': '1920x1080',
    'X-Plex-Platform': 'Chrome',
    'X-Plex-Platform-Version': '140.0',
    'Accept': 'application/json',
  };
  if (token) {
    headers['X-Plex-Token'] = token;
  }
  return headers;
}

// Normalize Plex resources to persisted server entries (encrypted tokens)
export async function normalizeAndPersistServers(userId: string, clientId: string): Promise<Array<any>> {
  const userRepository = AppDataSource.getRepository(User);
  const settingsRepository = AppDataSource.getRepository(UserSettings);

  const user = await userRepository.findOne({
    where: { id: userId },
    select: ['id', 'plexToken'],
  });
  if (!user?.plexToken) {
    throw new Error('Plex account token not found');
  }

  const accountToken = isEncrypted(user.plexToken)
    ? decryptForUser(userId, user.plexToken)
    : user.plexToken;

  const res = await axios.get(
    `${PLEX_TV_URL}/api/v2/resources?includeHttps=1&includeRelay=1`,
    { headers: getPlexHeaders(clientId || 'web', accountToken) }
  );

  const servers = (res.data || [])
    .filter((r: any) => r.product === 'Plex Media Server')
    .map((srv: any) => {
      const connections = Array.isArray(srv.connections) ? srv.connections : [];
      // Prefer local > remote > relay; prefer https > http
      const score = (c: any) => (c.local ? 100 : 0) + (!c.relay ? 10 : 0) + (c.protocol === 'https' ? 1 : 0);
      const best = [...connections].sort((a, b) => score(b) - score(a))[0];

      let host = '';
      let port = 32400;
      let protocol: 'http' | 'https' = 'http';
      if (best?.uri) {
        try {
          const u = new URL(best.uri);
          host = u.hostname;
          port = Number(u.port || 32400);
          protocol = (u.protocol.replace(':', '') as 'http' | 'https');
        } catch {}
      }

      // Collect addresses
      const localAddresses = Array.from(new Set(
        connections
          .filter((c: any) => c?.local && c?.address)
          .map((c: any) => String(c.address))
      ));

      const publicAddress = connections.find((c: any) => !c.local && !c.relay)?.address || undefined;

      const relayAddresses = Array.from(new Set(
        connections
          .filter((c: any) => c?.relay && c?.address)
          .map((c: any) => String(c.address))
      ));

      // Build address -> port mapping and URI mapping (address can have multiple ports with different protocols)
      const addressPorts: Record<string, Array<{port: number, protocol: string, uri?: string}>> = {};
      for (const c of connections) {
        if (c?.address && c?.port) {
          const addr = String(c.address);
          if (!addressPorts[addr]) {
            addressPorts[addr] = [];
          }
          // Avoid duplicates
          const exists = addressPorts[addr].some(p => p.port === c.port && p.protocol === c.protocol);
          if (!exists) {
            addressPorts[addr].push({
              port: Number(c.port),
              protocol: c.protocol || 'https',
              uri: c.uri ? String(c.uri) : undefined  // Store original URI for HTTPS
            });
          }
        }
      }

      const connectionSnapshot = connections
        .filter((c: any) => c?.uri)
        .map((c: any) => ({
          uri: String(c.uri),
          address: c.address ? String(c.address) : undefined,
          port: c.port ? Number(c.port) : undefined,
          protocol: c.protocol === 'https' ? 'https' : c.protocol === 'http' ? 'http' : undefined,
          local: typeof c.local === 'boolean' ? c.local : undefined,
          relay: typeof c.relay === 'boolean' ? c.relay : undefined,
          IPv6: typeof c.ipv6 === 'boolean' ? c.ipv6 : (typeof c.IPv6 === 'boolean' ? c.IPv6 : undefined),
        }));

      const serverEntry: any = {
        id: srv.clientIdentifier,
        name: srv.name,
        host,
        port,
        protocol,
        owned: !!srv.owned,
        publicAddress,
        localAddresses,
        relayAddresses,
        addressPorts,
        accessToken: encryptForUser(userId, srv.accessToken),
      };
      if (connectionSnapshot.length > 0) {
        serverEntry.connections = connectionSnapshot;
      }
      return serverEntry;
    });

  // Persist to settings
  let settings = await settingsRepository.findOne({ where: { userId } });
  if (!settings) {
    settings = settingsRepository.create({ userId });
  }

  // Preserve preferredUri if set previously
  const prev = await settingsRepository.findOne({ where: { userId } });
  if (prev?.plexServers && Array.isArray(prev.plexServers)) {
    for (const s of servers) {
      const match = (prev.plexServers as any[]).find(ps => ps.id === s.id);
      if (match?.preferredUri) {
        s.preferredUri = match.preferredUri;
        // Ensure selected endpoint persists across sync
        try {
          const u = new URL(match.preferredUri);
          s.protocol = (u.protocol.replace(':','') as any);
          s.host = u.hostname;
          s.port = parseInt(u.port || '32400', 10);
        } catch {}
      }
    }
  }

  settings.plexServers = servers;
  if (!settings.currentServerId && servers[0]) {
    // Prefer owned server if available
    const owned = servers.find((s: any) => s.owned) || servers[0];
    settings.currentServerId = owned.id;
  }

  await settingsRepository.save(settings);
  return servers;
}

// Initialize Plex OAuth
router.post('/plex/pin', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const clientId = req.body.clientId || crypto.randomUUID();

    const response = await axios.post(
      `${PLEX_TV_URL}/api/v2/pins`,
      {},
      { headers: getPlexHeaders(clientId) }
    );

    const authUrl = `https://app.plex.tv/auth#?` +
      `clientID=${encodeURIComponent(clientId)}` +
      `&code=${response.data.code}` +
      `&context%5Bdevice%5D%5Bproduct%5D=Plex%20Web` +
      `&context%5Bdevice%5D%5Bplatform%5D=Chrome` +
      `&context%5Bdevice%5D%5Bdevice%5D=OSX` +
      `&context%5Bdevice%5D%5Bversion%5D=4.128.1`;

    res.json({
      id: response.data.id,
      code: response.data.code,
      clientId,
      authUrl,
    });
  } catch (error) {
    logger.error('Failed to create Plex PIN:', error);
    next(new AppError('Failed to initialize Plex authentication', 500));
  }
});

// Check Plex PIN status
router.get('/plex/pin/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;
    const { clientId } = req.query;

    if (!clientId) {
      throw new AppError('Client ID is required', 400);
    }

    let response: any;
    try {
      response = await axios.get(
        `${PLEX_TV_URL}/api/v2/pins/${id}`,
        { headers: getPlexHeaders(clientId as string) }
      );
    } catch (err: any) {
      // Treat transient/expired PIN errors as not authenticated instead of 500,
      // so the frontend can keep polling or restart.
      logger.warn('Plex PIN check request failed', {
        id,
        status: err?.response?.status,
        message: err?.message,
      });
      return res.json({ authenticated: false, pending: true });
    }

      if (response.data.authToken) {
        // PIN has been authenticated
        const token = response.data.authToken;

      // Get user info
      let userResponse: any;
      try {
        userResponse = await axios.get(
          `${PLEX_TV_URL}/api/v2/user`,
          { headers: getPlexHeaders(clientId as string, token) }
        );
      } catch (err: any) {
        logger.warn('Plex user fetch failed after PIN success', {
          status: err?.response?.status,
          message: err?.message,
        });
        return res.json({ authenticated: false, pending: true });
      }

      const plexUser = userResponse.data;

      // Save or update user in database
      const userRepository = AppDataSource.getRepository(User);
      const settingsRepository = AppDataSource.getRepository(UserSettings);

      let user = await userRepository.findOne({ where: { plexId: plexUser.id } });

      if (!user) {
        // Create new user
        user = userRepository.create({
          plexId: plexUser.id,
          username: plexUser.username || plexUser.title,
          email: plexUser.email,
          thumb: plexUser.thumb,
          title: plexUser.title,
          plexToken: token, // will re-encrypt below after we have user.id
          hasPassword: plexUser.hasPassword || false,
          subscription: plexUser.subscription ? {
            active: plexUser.subscription.active,
            status: plexUser.subscription.status,
            plan: plexUser.subscription.plan,
          } : undefined,
        });
        user = await userRepository.save(user);

        // Re-encrypt plexToken with userId-derived key
        try {
          user.plexToken = encryptForUser(user.id, token);
          await userRepository.save(user);
        } catch (e) {
          logger.warn('Failed to encrypt plexToken, leaving as-is');
        }

        // Create default settings
        const settings = settingsRepository.create({
          userId: user.id,
          preferences: {
            language: 'en',
            autoPlay: true,
            quality: 'auto',
            subtitles: false,
            theme: 'dark',
          },
        });
        await settingsRepository.save(settings);
      } else {
        // Update existing user
        user.username = plexUser.username || plexUser.title;
        user.email = plexUser.email;
        user.thumb = plexUser.thumb;
        // store encrypted token
        try {
          user.plexToken = encryptForUser(user.id, token);
        } catch {
          user.plexToken = token;
        }
        user.subscription = plexUser.subscription ? {
          active: plexUser.subscription.active,
          status: plexUser.subscription.status,
          plan: plexUser.subscription.plan,
        } : undefined;
        await userRepository.save(user);
      }

      // If already authenticated in this session, avoid re-creating the session record
      if (req.session.userId === user.id) {
        // A direct sign-in replaces any Plex Home profile this session had switched to.
        delete req.session.mainUserId;
        delete req.session.profile;
      } else {
        // Create session (regenerate to avoid fixation); rely on end-of-request save
        await new Promise<void>((resolve, reject) => {
          req.session.regenerate((err) => err ? reject(err) : resolve());
        });

        req.session.userId = user.id as any;
        (req.session as any).plexId = user.plexId;
        (req.session as any).username = user.username;
        // Do not call req.session.save() explicitly to avoid double INSERT races with the store.
      }

      logger.info(`User authenticated: ${user.username} (${user.plexId})`);

      // Attempt to sync Plex servers for this user in the background
      (async () => {
        try {
          await normalizeAndPersistServers(user.id, (req.query.clientId as string) || (req.body.clientId as string) || 'web');
          logger.info('Plex servers synchronized for user', { userId: user.id });
        } catch (syncErr) {
          logger.warn('Failed to sync Plex servers after login', { error: (syncErr as Error).message });
        }
      })();

      // If mobile hint present, also issue a JWT for React Native clients
      const wantsMobile = String(req.query.mobile || req.headers['x-mobile'] || '') === '1';
      if (wantsMobile) {
        const secret = process.env.SESSION_SECRET || 'change-this-in-production';
        const token = jwt.sign(
          { sub: user.id, plexId: user.plexId, username: user.username },
          secret,
          { expiresIn: '7d' }
        );
        return res.json({
          authenticated: true,
          token,
          user: {
            id: user.id,
            username: user.username,
            email: user.email,
            thumb: user.thumb,
            subscription: user.subscription,
          },
        });
      } else {
        res.json({
          authenticated: true,
          user: {
            id: user.id,
            username: user.username,
            email: user.email,
            thumb: user.thumb,
            subscription: user.subscription,
          },
        });
      }
    } else {
      // PIN not yet authenticated
      res.json({ authenticated: false });
    }
  } catch (error) {
    logger.error('Failed to check Plex PIN:', error);
    next(new AppError('Failed to check authentication status', 500));
  }
});

// Get current session
router.get('/session', async (req: Request, res: Response, next: NextFunction) => {
  try {
    if (!req.session.userId) {
      return res.json({ authenticated: false });
    }

    const userRepository = AppDataSource.getRepository(User);
    const user = await userRepository.findOne({
      where: { id: req.session.userId },
      select: ['id', 'username', 'email', 'thumb', 'subscription'],
    });

    if (!user) {
      req.session.destroy(() => {});
      return res.json({ authenticated: false });
    }

    res.json({
      authenticated: true,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        thumb: user.thumb,
        subscription: user.subscription,
      },
      profile: req.session.profile ?? null,
    });
  } catch (error) {
    logger.error('Failed to get session:', error);
    next(new AppError('Failed to get session', 500));
  }
});

// Validate session
router.get('/validate', requireAuth, async (req: AuthenticatedRequest, res: Response) => {
  res.json({
    valid: true,
    user: req.user,
  });
});

// Logout
router.post('/logout', (req: Request, res: Response, next: NextFunction) => {
  // Capture cookie attributes to correctly clear the cookie
  const cookieOpts: any = {
    path: '/',
  };
  try {
    const c: any = (req as any).session?.cookie;
    if (c) {
      if (typeof c.secure === 'boolean') cookieOpts.secure = c.secure;
      if (c.sameSite) cookieOpts.sameSite = c.sameSite;
      if (c.domain) cookieOpts.domain = c.domain;
      if (c.path) cookieOpts.path = c.path;
    }
  } catch {}

  req.session.destroy((err) => {
    if (err) {
      logger.error('Failed to destroy session:', err);
      return next(new AppError('Failed to logout', 500));
    }

    try { res.clearCookie('plex.sid', cookieOpts); } catch {}
    res.json({ success: true });
  });
});

// Get Plex servers for authenticated user
router.get('/servers', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const userRepository = AppDataSource.getRepository(User);
    const user = await userRepository.findOne({
      where: { id: req.user!.id },
      select: ['plexToken'],
    });

    if (!user) {
      throw new AppError('User not found', 404);
    }

    const accountToken = isEncrypted(user.plexToken)
      ? decryptForUser(req.user!.id, user.plexToken)
      : user.plexToken;

    const response = await axios.get(
      `${PLEX_TV_URL}/api/v2/resources?includeHttps=1&includeRelay=1`,
      {
        headers: getPlexHeaders(req.body.clientId || 'web', accountToken),
      }
    );

    const servers = response.data
      .filter((r: any) => r.product === 'Plex Media Server')
      .map((server: any) => {
        // Find best connection
        const connections = server.connections || [];
        const local = connections.find((c: any) => c.local);
        const remote = connections.find((c: any) => !c.local && !c.relay);
        const relay = connections.find((c: any) => c.relay);

        const bestConnection = local || remote || relay;

        return {
          name: server.name,
          clientIdentifier: server.clientIdentifier,
          baseUrl: bestConnection?.uri,
          token: server.accessToken,
          connections: connections.map((c: any) => ({
            uri: c.uri,
            local: c.local,
            relay: c.relay,
            protocol: c.protocol,
          })),
        };
      });

    res.json(servers);
  } catch (error) {
    logger.error('Failed to get Plex servers:', error);
    next(new AppError('Failed to get servers', 500));
  }
});

// Persist and return Plex servers for authenticated user
router.post('/servers/sync', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const clientId = (req.body?.clientId as string) || 'web';
    const servers = await normalizeAndPersistServers(req.user!.id, clientId);
    res.json({ saved: servers.length, servers: servers.map(s => ({ id: s.id, name: s.name })) });
  } catch (error: any) {
    logger.error('Failed to sync Plex servers:', error);
    next(new AppError('Failed to sync servers', 500));
  }
});

export { router as authRouter };
export default router;
