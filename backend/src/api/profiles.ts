import { Router, Response, NextFunction } from 'express';
import axios from 'axios';
import crypto from 'crypto';
import { AppDataSource } from '../db/data-source';
import { User, UserSettings } from '../db/entities';
import { AppError } from '../middleware/errorHandler';
import { AuthenticatedRequest, SessionProfile } from '../middleware/auth';
import { createLogger } from '../utils/logger';
import { decryptForUser, encryptForUser, isEncrypted } from '../utils/crypto';
import { clearPlexClients } from '../services/plex/PlexClient';
import { getPlexHeaders, normalizeAndPersistServers } from './auth';

/**
 * Plex Home profiles.
 *
 * Each profile is its own User row (keyed by the Plex user id) holding the
 * profile's token and server list. Switching points the session at that row and
 * remembers the signed-in account in `session.mainUserId`, so every route that
 * reads `req.user.id` (Plex, watchlist, Trakt, addons) follows the profile with
 * no changes. Sessions without those fields keep working as the main account.
 */

const router = Router();
const logger = createLogger('profiles');
const PLEX_TV_URL = 'https://plex.tv';

const MAX_PIN_FAILURES = 5;
const PIN_LOCKOUT_MS = 60_000;

type HomeUser = {
  id: number;
  uuid: string;
  title: string;
  username: string;
  thumb?: string;
  restricted: boolean;
  protected: boolean;
  admin: boolean;
  guest: boolean;
};

type PinFailures = { count: number; lockedUntil: number };
const pinFailures = new Map<string, PinFailures>();

function isLockedOut(key: string): boolean {
  const entry = pinFailures.get(key);
  if (!entry) return false;
  if (entry.lockedUntil > Date.now()) return true;
  if (entry.lockedUntil !== 0) pinFailures.delete(key);
  return false;
}

function recordPinFailure(key: string) {
  const count = (pinFailures.get(key)?.count ?? 0) + 1;
  pinFailures.set(key, {
    count,
    lockedUntil: count >= MAX_PIN_FAILURES ? Date.now() + PIN_LOCKOUT_MS : 0,
  });
}

function clientIdFrom(value: unknown): string {
  return typeof value === 'string' && value.length > 0 && value.length <= 128 ? value : 'web';
}

function requireSessionUserId(req: AuthenticatedRequest): string {
  if (!req.session.userId) throw new AppError('Profiles require a browser session', 400);
  return req.session.mainUserId || req.session.userId;
}

async function loadAccount(userId: string): Promise<{ user: User; token: string }> {
  const user = await AppDataSource.getRepository(User)
    .createQueryBuilder('u')
    .addSelect('u.plexToken')
    .where('u.id = :userId', { userId })
    .getOne();
  if (!user?.plexToken) throw new AppError('Plex account token not found', 400);
  const token = isEncrypted(user.plexToken) ? decryptForUser(userId, user.plexToken) : user.plexToken;
  return { user, token };
}

async function fetchHomeUsers(token: string, clientId: string): Promise<HomeUser[]> {
  try {
    const response = await axios.get(`${PLEX_TV_URL}/api/v2/home/users`, {
      headers: getPlexHeaders(clientId, token),
    });
    const data = response.data;
    const users: any[] = Array.isArray(data) ? data : data?.users || [];
    return users
      .filter((u) => Number.isInteger(u?.id) && u.id > 0 && typeof u?.uuid === 'string')
      .map((u) => ({
        id: u.id,
        uuid: u.uuid,
        title: u.title || u.username || 'Unknown',
        username: u.username || '',
        thumb: u.thumb || undefined,
        restricted: Boolean(u.restricted),
        protected: Boolean(u.protected),
        admin: Boolean(u.admin),
        guest: Boolean(u.guest),
      }));
  } catch (error: any) {
    // 403 means the account is not part of a Plex Home.
    if (error?.response?.status === 403) return [];
    throw new AppError('Failed to load Plex Home profiles', 502);
  }
}

/** Returns the profile's token. The PIN is sent to plex.tv and never stored or logged. */
async function requestProfileToken(
  mainToken: string,
  clientId: string,
  uuid: string,
  pin?: string
): Promise<{ token: string } | { failure: 'invalid_pin' | 'not_allowed' | 'upstream' }> {
  try {
    const response = await axios.post(
      `${PLEX_TV_URL}/api/v2/home/users/${encodeURIComponent(uuid)}/switch`,
      null,
      { headers: getPlexHeaders(clientId, mainToken), params: pin ? { pin } : undefined }
    );
    const token = response.data?.authToken || response.data?.authenticationToken;
    return token ? { token } : { failure: 'upstream' };
  } catch (error: any) {
    const status = error?.response?.status;
    if (status === 401) return { failure: 'invalid_pin' };
    if (status === 403) return { failure: 'not_allowed' };
    logger.warn('Plex Home switch failed', { status });
    return { failure: 'upstream' };
  }
}

async function saveProfileUser(target: HomeUser, token: string): Promise<User> {
  const users = AppDataSource.getRepository(User);
  const existing = await users.findOne({ where: { plexId: target.id } });
  // The token is encrypted with a key derived from the row id, so the id comes first.
  const id = existing?.id ?? crypto.randomUUID();
  return users.save(
    users.create({
      ...existing,
      id,
      plexId: target.id,
      username: target.username || target.title,
      thumb: target.thumb,
      title: target.title,
      plexToken: encryptForUser(id, token),
      hasPassword: existing?.hasPassword ?? target.protected,
    })
  );
}

/** Gives a new profile the account's current server and chosen endpoints, then syncs. */
async function syncProfileServers(profileId: string, mainUserId: string, clientId: string) {
  const repo = AppDataSource.getRepository(UserSettings);
  const main = await repo.findOne({ where: { userId: mainUserId } });
  let settings = await repo.findOne({ where: { userId: profileId } });
  if (!settings) {
    // The web app's synced copy belongs to the account, not each profile.
    const { webState: _webState, webStateVersion: _webStateVersion, ...preferences } = main?.preferences || {};
    settings = repo.create({ userId: profileId, preferences });
  }
  if (!settings.plexServers?.length && main?.plexServers?.length) {
    settings.plexServers = main.plexServers
      .filter((s) => s.preferredUri)
      .map((s) => ({ id: s.id, preferredUri: s.preferredUri })) as any;
  }
  if (!settings.currentServerId) settings.currentServerId = main?.currentServerId;
  await repo.save(settings);

  const servers = await normalizeAndPersistServers(profileId, clientId);

  // The account's server may not be shared with this profile.
  const saved = await repo.findOne({ where: { userId: profileId } });
  if (saved && !servers.some((s: any) => s.id === saved.currentServerId)) {
    saved.currentServerId = (servers.find((s: any) => s.owned) || servers[0])?.id;
    await repo.save(saved);
  }
  clearPlexClients(profileId);
}

function toSessionProfile(target: HomeUser): SessionProfile {
  return {
    uuid: target.uuid,
    title: target.title,
    thumb: target.thumb,
    restricted: target.restricted,
    protected: target.protected,
  };
}

// GET /api/auth/profiles
router.get('/', async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const mainUserId = requireSessionUserId(req);
    const { user, token } = await loadAccount(mainUserId);
    const users = await fetchHomeUsers(token, clientIdFrom(req.query.clientId));
    res.json({
      users: users.map(({ username, ...u }) => ({ ...u, isMain: u.id === user.plexId })),
      activeUuid: req.session.profile?.uuid ?? users.find((u) => u.id === user.plexId)?.uuid ?? null,
    });
  } catch (error) {
    next(error instanceof AppError ? error : new AppError('Failed to load profiles', 500));
  }
});

// POST /api/auth/profiles/switch { uuid, pin?, clientId? }
router.post('/switch', async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const mainUserId = requireSessionUserId(req);
    const { uuid, pin } = req.body || {};
    const clientId = clientIdFrom(req.body?.clientId);
    if (typeof uuid !== 'string' || !/^[\w-]{1,64}$/.test(uuid)) throw new AppError('Invalid profile', 400);
    if (pin !== undefined && (typeof pin !== 'string' || !/^\d{4}$/.test(pin))) {
      return res.status(400).json({ code: 'invalid_pin', message: 'Enter the 4 digit PIN' });
    }

    const lockKey = `${mainUserId}:${uuid}`;
    if (isLockedOut(lockKey)) {
      return res.status(429).json({ code: 'pin_locked', message: 'Too many attempts. Try again in a minute.' });
    }

    const { user: mainUser, token: mainToken } = await loadAccount(mainUserId);
    const users = await fetchHomeUsers(mainToken, clientId);
    const target = users.find((u) => u.uuid === uuid);
    if (!target) throw new AppError('Profile not found', 404);

    const targetIsMain = target.id === mainUser.plexId;
    const alreadyActive = targetIsMain ? !req.session.mainUserId : req.session.profile?.uuid === uuid;
    if (alreadyActive) return res.json({ profile: req.session.profile ?? null });

    if (target.protected && !pin) {
      return res.status(400).json({ code: 'pin_required', message: 'This profile needs a PIN' });
    }

    // Returning to the signed-in account still checks its PIN, so a restricted
    // profile cannot step back up without it.
    let profileToken: string | undefined;
    if (!targetIsMain || target.protected) {
      const result = await requestProfileToken(mainToken, clientId, uuid, pin);
      if ('failure' in result) {
        if (result.failure === 'invalid_pin') {
          recordPinFailure(lockKey);
          return res.status(403).json({ code: 'invalid_pin', message: 'That PIN is not correct' });
        }
        if (result.failure === 'not_allowed') {
          return res.status(403).json({ code: 'not_allowed', message: 'You cannot switch to this profile' });
        }
        throw new AppError('Plex could not switch profiles', 502);
      }
      profileToken = result.token;
    }
    pinFailures.delete(lockKey);

    if (targetIsMain) {
      req.session.userId = mainUser.id;
      req.session.plexId = mainUser.plexId;
      req.session.username = mainUser.username;
      delete req.session.mainUserId;
      delete req.session.profile;
      logger.info('Session returned to main account', { userId: mainUser.id });
      return res.json({ profile: null });
    }

    const profileUser = await saveProfileUser(target, profileToken!);
    try {
      await syncProfileServers(profileUser.id, mainUserId, clientId);
    } catch (error: any) {
      logger.warn('Profile server sync failed', { status: error?.response?.status, message: error?.message });
      throw new AppError('Could not load servers for this profile', 502);
    }

    req.session.userId = profileUser.id;
    req.session.plexId = profileUser.plexId;
    req.session.username = profileUser.username;
    req.session.mainUserId = mainUserId;
    req.session.profile = toSessionProfile(target);
    logger.info('Session switched to profile', { userId: profileUser.id });
    res.json({ profile: req.session.profile });
  } catch (error) {
    next(error instanceof AppError ? error : new AppError('Failed to switch profile', 500));
  }
});

export default router;
