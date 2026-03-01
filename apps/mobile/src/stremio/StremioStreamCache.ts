import { appLogger } from '../core/AppLogger';
import { readStreamCacheIndex, writeStreamCacheIndex } from './StremioStorage';
import type { CachedPlaybackSource } from './types';

class StremioStreamCache {
  async save(source: CachedPlaybackSource): Promise<void> {
    const index = await readStreamCacheIndex();
    index[source.contentKey] = source;
    await writeStreamCacheIndex(index);
    appLogger.info('[Stremio] Saved cached stream', {
      contentKey: source.contentKey,
      addonId: source.addonId,
      expiresAt: source.expiresAt,
    });
  }

  async get(contentKey: string): Promise<CachedPlaybackSource | null> {
    const index = await readStreamCacheIndex();
    const entry = index[contentKey];
    if (!entry) {
      return null;
    }
    if (Date.now() > entry.expiresAt) {
      delete index[contentKey];
      await writeStreamCacheIndex(index);
      appLogger.info('[Stremio] Cached stream expired', { contentKey });
      return null;
    }
    return entry;
  }

  async remove(contentKey: string): Promise<void> {
    const index = await readStreamCacheIndex();
    if (!index[contentKey]) {
      return;
    }
    delete index[contentKey];
    await writeStreamCacheIndex(index);
  }

  async clear(): Promise<void> {
    await writeStreamCacheIndex({});
  }
}

export const stremioStreamCache = new StremioStreamCache();
