import { Router, Response, NextFunction } from 'express';
import { AppDataSource } from '../db/data-source';
import { UserSettings } from '../db/entities';
import { AppError } from '../middleware/errorHandler';
import { AuthenticatedRequest } from '../middleware/auth';
import { createLogger } from '../utils/logger';
import { decryptForUser, encryptForUser } from '../utils/crypto';

/**
 * The web app's settings, addons and lists for the signed-in account, so a new
 * browser starts where the last one left off. Stored encrypted, because addon
 * URLs and some settings carry keys.
 */
const router = Router();
const logger = createLogger('sync');

const MAX_UNITS = 5000;
const MAX_BYTES = 5 * 1024 * 1024;

type SyncUnits = Record<string, string>;

/** The account that signed in, also while a Plex Home profile is active. */
function accountId(req: AuthenticatedRequest): string {
  const id = req.session?.mainUserId || req.session?.userId || req.user?.id;
  if (!id) throw new AppError('Not signed in', 401);
  return id;
}

async function load(userId: string): Promise<{ settings: UserSettings | null; units: SyncUnits; version: number }> {
  const settings = await AppDataSource.getRepository(UserSettings).findOne({ where: { userId } });
  const prefs = settings?.preferences;
  if (!prefs?.webState) return { settings, units: {}, version: 0 };
  try {
    const parsed = JSON.parse(decryptForUser(userId, prefs.webState));
    return { settings, units: isUnits(parsed) ? parsed : {}, version: prefs.webStateVersion || 0 };
  } catch (error: any) {
    // A changed SESSION_SECRET makes old copies unreadable. Start again.
    logger.warn('Stored web settings could not be read', { message: error?.message });
    return { settings, units: {}, version: 0 };
  }
}

function isUnits(value: unknown): value is SyncUnits {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const entries = Object.entries(value as Record<string, unknown>);
  return entries.length <= MAX_UNITS && entries.every(([k, v]) => k.length <= 256 && typeof v === 'string');
}

// GET /api/sync → { account, version, units }
router.get('/', async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const userId = accountId(req);
    const { units, version } = await load(userId);
    res.set('Cache-Control', 'no-store');
    res.json({ account: userId, version, units });
  } catch (error) {
    next(error instanceof AppError ? error : new AppError('Failed to load settings', 500));
  }
});

// PUT /api/sync { baseVersion, units } → { version } or 409 { version, units }
router.put('/', async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const userId = accountId(req);
    const { baseVersion, units } = req.body || {};
    if (typeof baseVersion !== 'number' || !isUnits(units)) throw new AppError('Invalid settings', 400);
    const json = JSON.stringify(units);
    if (json.length > MAX_BYTES) throw new AppError('Settings are too large to save', 413);

    const { settings, units: stored, version } = await load(userId);
    if (version > baseVersion) {
      // Another browser saved since this one last loaded. It merges and tries again.
      return res.status(409).json({ account: userId, version, units: stored });
    }

    const repo = AppDataSource.getRepository(UserSettings);
    const row = settings ?? repo.create({ userId });
    const nextVersion = Math.max(Date.now(), version + 1);
    row.preferences = { ...(row.preferences || {}), webState: encryptForUser(userId, json), webStateVersion: nextVersion };
    await repo.save(row);
    res.json({ account: userId, version: nextVersion });
  } catch (error) {
    next(error instanceof AppError ? error : new AppError('Failed to save settings', 500));
  }
});

export default router;
