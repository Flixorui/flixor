import { Router, Request, Response } from 'express';
import axios from 'axios';
import { createLogger } from '../utils/logger';

const router = Router();
const logger = createLogger('version');

// Current app version - update this with each release
const APP_VERSION = '1.9.5';

// External URL to check for latest version
const VERSION_CHECK_URL = process.env.VERSION_CHECK_URL || 'https://webota.flixor.xyz/version.json';

// Cache duration: 6 hours in milliseconds
const CACHE_DURATION = 6 * 60 * 60 * 1000;

interface VersionInfo {
  latest: string;
  releaseNotes?: string;
  releaseUrl?: string;
  minVersion?: string;
}

interface CachedVersion {
  data: VersionInfo | null;
  fetchedAt: number;
  error?: string;
}

// In-memory cache for version info
let versionCache: CachedVersion = {
  data: null,
  fetchedAt: 0,
};

// Fetch latest version from external URL
async function fetchLatestVersion(): Promise<VersionInfo | null> {
  try {
    const response = await axios.get<VersionInfo>(VERSION_CHECK_URL, {
      timeout: 10000,
      headers: { 'Accept': 'application/json' },
    });

    if (response.data && response.data.latest) {
      return response.data;
    }

    logger.warn('Invalid version response from remote');
    return null;
  } catch (error: any) {
    logger.debug('Failed to fetch version info:', error.message);
    return null;
  }
}

// Get version info (from cache or fetch)
async function getVersionInfo(): Promise<VersionInfo | null> {
  const now = Date.now();

  // Return cached data if still valid
  if (versionCache.data && (now - versionCache.fetchedAt) < CACHE_DURATION) {
    return versionCache.data;
  }

  // Fetch fresh data
  const freshData = await fetchLatestVersion();

  if (freshData) {
    versionCache = {
      data: freshData,
      fetchedAt: now,
    };
    return freshData;
  }

  // If fetch failed but we have stale cache, return it
  if (versionCache.data) {
    return versionCache.data;
  }

  return null;
}

// Compare semantic versions: returns 1 if a > b, -1 if a < b, 0 if equal
function compareVersions(a: string, b: string): number {
  const parseVersion = (v: string) => v.replace(/^v/, '').split('.').map(n => parseInt(n, 10) || 0);
  const aParts = parseVersion(a);
  const bParts = parseVersion(b);

  for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
    const aPart = aParts[i] || 0;
    const bPart = bParts[i] || 0;
    if (aPart > bPart) return 1;
    if (aPart < bPart) return -1;
  }
  return 0;
}

/**
 * GET /api/version
 * Returns current version and update info
 */
router.get('/', async (req: Request, res: Response) => {
  try {
    const latestInfo = await getVersionInfo();

    const response: any = {
      current: APP_VERSION,
      latest: latestInfo?.latest || APP_VERSION,
      hasUpdate: false,
    };

    if (latestInfo) {
      response.hasUpdate = compareVersions(latestInfo.latest, APP_VERSION) > 0;
      response.releaseNotes = latestInfo.releaseNotes;
      response.releaseUrl = latestInfo.releaseUrl;
    }

    res.json(response);
  } catch (error: any) {
    logger.error('Version check failed:', error);
    res.json({
      current: APP_VERSION,
      latest: APP_VERSION,
      hasUpdate: false,
    });
  }
});

/**
 * GET /api/version/current
 * Returns just the current version (no external check)
 */
router.get('/current', (req: Request, res: Response) => {
  res.json({ version: APP_VERSION });
});

export default router;
