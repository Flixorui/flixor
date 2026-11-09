import { Router, Request, Response, NextFunction } from 'express';
import axios from 'axios';
import sharp from 'sharp';
import fs from 'fs';
import path from 'path';
import { cacheManager, CacheManager } from '../services/cache/CacheManager';
import { createLogger } from '../utils/logger';
import { AppError } from '../middleware/errorHandler';
import { requireAuth, AuthenticatedRequest } from '../middleware/auth';
import { getPlexClient } from '../services/plex/PlexClient';
import { AppDataSource } from '../db/data-source';
import { UserSettings } from '../db/entities';
import { OutboundUrlError, safeFetch } from '../utils/outboundUrl';

const router = Router();
const logger = createLogger('image-proxy');

interface ImageOptions {
  width?: number;
  height?: number;
  quality?: number;
  format?: 'jpeg' | 'png' | 'webp';
  fit?: 'cover' | 'contain' | 'fill' | 'inside' | 'outside';
}

/**
 * Parse image options from query parameters
 */
function parseImageOptions(query: any): ImageOptions {
  return {
    width: dimension(query.w),
    height: dimension(query.h),
    quality: Math.min(100, dimension(query.q) ?? 85),
    // The format names the cache file, so it must never be arbitrary text.
    format: IMAGE_FORMATS.includes(query.f) ? query.f : 'jpeg',
    fit: IMAGE_FITS.includes(query.fit) ? query.fit : 'cover',
  };
}

const IMAGE_FORMATS = ['jpeg', 'png', 'webp'];
const IMAGE_FITS = ['cover', 'contain', 'fill', 'inside', 'outside'];
const MAX_IMAGE_DIMENSION = 4096;
const MAX_IMAGE_BYTES = 30 * 1024 * 1024;

function dimension(value: unknown): number | undefined {
  const parsed = parseInt(String(value), 10);
  return Number.isFinite(parsed) && parsed > 0 ? Math.min(parsed, MAX_IMAGE_DIMENSION) : undefined;
}

/** Every hostname the user's saved Plex servers are known by. */
async function userPlexHosts(userId: string): Promise<Set<string>> {
  const settings = await AppDataSource.getRepository(UserSettings).findOne({ where: { userId } });
  const hosts = new Set<string>();
  const add = (value: unknown) => {
    if (typeof value !== 'string' || !value) return;
    try {
      hosts.add(new URL(value.includes('://') ? value : `http://${value}`).hostname.toLowerCase());
    } catch {
      // Ignore a malformed saved address.
    }
  };
  for (const server of (settings?.plexServers ?? []) as any[]) {
    add(server.host);
    add(server.publicAddress);
    (server.localAddresses ?? []).forEach(add);
    for (const connection of server.connections ?? []) {
      add(connection.uri);
      add(connection.address);
    }
  }
  return hosts;
}

/**
 * Fetches a client-supplied image URL through the SSRF guard. LAN addresses are
 * refused, except for the user's own Plex servers, whose artwork URLs reach this
 * route and commonly resolve to private addresses.
 */
async function fetchClientImage(imageUrl: string, userId: string, accept: string): Promise<Buffer> {
  const options = {
    headers: { 'User-Agent': 'PlexMediaPlayer/1.0', Accept: accept },
    timeoutMs: 10_000,
    maxBytes: MAX_IMAGE_BYTES,
  };
  let response;
  try {
    response = await safeFetch(imageUrl, options);
  } catch (err) {
    const blocked = err instanceof OutboundUrlError && err.code === 'BLOCKED_ADDRESS';
    if (!blocked || !(await userPlexHosts(userId)).has(new URL(imageUrl).hostname.toLowerCase())) {
      throw err;
    }
    response = await safeFetch(imageUrl, { ...options, allowPrivateNetwork: true });
  }
  if (response.status !== 200) {
    response.abort();
    throw response.status === 404
      ? new AppError('Image not found', 404)
      : new AppError('Failed to fetch image', 502);
  }
  return response.buffer();
}

/**
 * Proxy and cache external images
 * GET /api/image/proxy?url=https://example.com/image.jpg&w=500&h=300&q=85
 */
router.get('/proxy', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    const imageUrl = req.query.url;

    if (typeof imageUrl !== 'string' || !imageUrl) {
      throw new AppError('Image URL is required', 400);
    }

    // Validate URL
    try {
      new URL(imageUrl);
    } catch {
      throw new AppError('Invalid image URL', 400);
    }

    const options = parseImageOptions(req.query);

    // Generate cache key based on URL and options
    const cacheKey = CacheManager.generateHashKey(
      JSON.stringify({ url: imageUrl, ...options })
    );
    const cacheDir = path.join(process.cwd(), 'cache', 'images');
    const cachePath = path.join(cacheDir, `${cacheKey}.${options.format}`);

    // Check if image exists in disk cache
    if (fs.existsSync(cachePath)) {
      const stats = fs.statSync(cachePath);
      const maxAge = 7 * 24 * 60 * 60; // 7 days

      // Check if cache is still valid
      if (Date.now() - stats.mtimeMs < maxAge * 1000) {
        logger.debug(`Serving cached image: ${cacheKey}`);
        res.setHeader('X-Cache', 'HIT');
        res.setHeader('Cache-Control', `private, max-age=${maxAge}`);
        res.setHeader('Content-Type', `image/${options.format}`);
        return fs.createReadStream(cachePath).pipe(res);
      }
    }

    // Fetch through the SSRF guard. The URL can hold a Plex token, so it is not logged.
    const imageData = await fetchClientImage(imageUrl, req.user!.id, 'image/*');

    // Process image with sharp
    let sharpInstance = sharp(imageData);

    // Apply resizing if specified
    if (options.width || options.height) {
      sharpInstance = sharpInstance.resize(options.width, options.height, {
        fit: options.fit as any,
        withoutEnlargement: true,
      });
    }

    // Apply format and quality
    switch (options.format) {
      case 'jpeg':
        sharpInstance = sharpInstance.jpeg({ quality: options.quality });
        break;
      case 'png':
        sharpInstance = sharpInstance.png({ quality: options.quality });
        break;
      case 'webp':
        sharpInstance = sharpInstance.webp({ quality: options.quality });
        break;
    }

    // Process the image
    const processedImage = await sharpInstance.toBuffer().catch(() => {
      throw new AppError('Unsupported image', 415);
    });

    // Ensure cache directory exists
    if (!fs.existsSync(cacheDir)) {
      fs.mkdirSync(cacheDir, { recursive: true });
    }

    // Save to disk cache
    fs.writeFileSync(cachePath, processedImage);
    logger.debug(`Cached image: ${cacheKey}`);

    // Send response
    res.setHeader('X-Cache', 'MISS');
    res.setHeader('Cache-Control', 'private, max-age=604800'); // 7 days
    res.setHeader('Content-Type', `image/${options.format}`);
    res.send(processedImage);

  } catch (error) {
    next(error);
  }
});

/**
 * Proxy Plex images with authentication
 * GET /api/image/plex?url=/library/metadata/123/thumb&token=xxx&w=500
 */
router.get('/plex', requireAuth, async (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
  try {
    // Support either full url+token or just a library-relative path resolved via current user's Plex server
    const { url, path: plexPath, token, server } = req.query as any;

    let baseUrl: string | undefined = typeof server === 'string' && server ? server : undefined;
    let accessToken: string | undefined = typeof token === 'string' && token ? token : undefined;
    let resourcePath: string | undefined = typeof plexPath === 'string' && plexPath ? plexPath : (typeof url === 'string' ? url : undefined);

    if (!resourcePath) {
      throw new AppError('Missing image path or url', 400);
    }

    // If token/server not provided, derive from current user's active server
    if (!baseUrl || !accessToken) {
      const client = await getPlexClient(req.user!.id);
      const serverInfo = client.getServerInfo();
      baseUrl = `${serverInfo.protocol}://${serverInfo.host}:${serverInfo.port}`;
      accessToken = serverInfo.accessToken;
    }

    // Build full URL from path if needed
    let fullUrl: string;
    let clientSuppliedTarget = Boolean(server && token);
    try {
      // If already absolute URL, keep as is
      new URL(resourcePath);
      fullUrl = resourcePath;
      clientSuppliedTarget = true;
    } catch {
      const sep = resourcePath.includes('?') ? '&' : '?';
      fullUrl = `${String(baseUrl).replace(/\/$/, '')}${resourcePath}${sep}X-Plex-Token=${accessToken}`;
    }

    const options = parseImageOptions(req.query);

    // Generate cache key
    const cacheKey = CacheManager.generateHashKey(JSON.stringify({ url: fullUrl, ...options }));
    const cacheDir = path.join(process.cwd(), 'cache', 'images', 'plex');
    const cachePath = path.join(cacheDir, `${cacheKey}.${options.format}`);

    // Check disk cache
    if (fs.existsSync(cachePath)) {
      const stats = fs.statSync(cachePath);
      const maxAge = 24 * 60 * 60; // 24 hours for Plex images

      if (Date.now() - stats.mtimeMs < maxAge * 1000) {
        logger.debug(`Serving cached Plex image: ${cacheKey}`);
        res.setHeader('X-Cache', 'HIT');
        res.setHeader('Cache-Control', `private, max-age=${maxAge}`);
        res.setHeader('Content-Type', `image/${options.format}`);
        return fs.createReadStream(cachePath).pipe(res);
      }
    }

    // Only a target that came from the client needs the SSRF guard. The session's own
    // server is trusted configuration and may legitimately be on the same host.
    let imageData: Buffer;
    if (clientSuppliedTarget) {
      imageData = await fetchClientImage(fullUrl, req.user!.id, 'image/*');
    } else {
      const response = await axios.get(fullUrl, {
        responseType: 'arraybuffer',
        timeout: 10000,
        headers: {
          'Accept': 'image/*',
        },
      });
      imageData = response.data;
    }

    // Process with sharp
    let sharpInstance = sharp(imageData);

    if (options.width || options.height) {
      sharpInstance = sharpInstance.resize(options.width, options.height, {
        fit: options.fit as any,
        withoutEnlargement: true,
      });
    }

    // Apply format and quality
    switch (options.format) {
      case 'jpeg':
        sharpInstance = sharpInstance.jpeg({ quality: options.quality });
        break;
      case 'png':
        sharpInstance = sharpInstance.png({ quality: options.quality });
        break;
      case 'webp':
        sharpInstance = sharpInstance.webp({ quality: options.quality });
        break;
    }

    const processedImage = await sharpInstance.toBuffer();

    // Ensure cache directory exists
    if (!fs.existsSync(cacheDir)) {
      fs.mkdirSync(cacheDir, { recursive: true });
    }

    // Save to cache
    fs.writeFileSync(cachePath, processedImage);

    res.setHeader('X-Cache', 'MISS');
    res.setHeader('Cache-Control', 'private, max-age=86400');
    res.setHeader('Content-Type', `image/${options.format}`);
    res.send(processedImage);

  } catch (error: any) {
    if (error instanceof AppError) return next(error);
    // Only the message: the error object carries a URL with the Plex token in it.
    logger.error('Failed to proxy Plex image:', error?.message);
    next(new AppError('Failed to fetch Plex image', 500));
  }
});

/**
 * Clear image cache
 * DELETE /api/image/cache
 */
router.delete('/cache', requireAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const maxAge = req.query.maxAge ? parseInt(req.query.maxAge as string, 10) : 7 * 24 * 60 * 60 * 1000;
    const deleted = await cacheManager.cleanupImageCache(maxAge);

    res.json({
      message: 'Image cache cleaned',
      filesDeleted: deleted,
    });
  } catch (error) {
    next(new AppError('Failed to clean image cache', 500));
  }
});

/**
 * Get image cache statistics
 * GET /api/image/cache/stats
 */
router.get('/cache/stats', requireAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const cacheDir = path.join(process.cwd(), 'cache', 'images');

    if (!fs.existsSync(cacheDir)) {
      return res.json({
        files: 0,
        totalSize: 0,
        oldestFile: null,
        newestFile: null,
      });
    }

    const files = fs.readdirSync(cacheDir, { withFileTypes: true })
      .filter(dirent => dirent.isFile())
      .map(dirent => {
        const filePath = path.join(cacheDir, dirent.name);
        const stats = fs.statSync(filePath);
        return {
          name: dirent.name,
          size: stats.size,
          modified: stats.mtime,
        };
      });

    const totalSize = files.reduce((sum, file) => sum + file.size, 0);
    const sorted = files.sort((a, b) => a.modified.getTime() - b.modified.getTime());

    res.json({
      files: files.length,
      totalSize,
      totalSizeMB: Math.round(totalSize / 1024 / 1024 * 100) / 100,
      oldestFile: sorted[0] || null,
      newestFile: sorted[sorted.length - 1] || null,
    });
  } catch (error) {
    next(new AppError('Failed to get cache statistics', 500));
  }
});

export default router;
