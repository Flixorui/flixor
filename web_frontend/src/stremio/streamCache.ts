/** The last source picked for a title, so it can be resumed without asking again. */
import { getSettings } from '@/state/settings';
import { buildContentKey } from './identity';
import { STORAGE_KEYS, readJson, tryWriteJson } from './storage';
import type { StremioContentIdentity, StremioStream } from './types';

export interface CachedStreamSource {
  contentKey: string;
  stream: StremioStream;
  savedAt: number;
  expiresAt: number;
}

type CacheIndex = Record<string, CachedStreamSource>;

const MAX_ENTRIES = 100;

function readIndex(): CacheIndex {
  return readJson<CacheIndex>(STORAGE_KEYS.streamCache, {});
}

export function isStreamCacheEnabled(): boolean {
  const settings = getSettings();
  return settings.useCachedStreams || settings.stremioPreferCachedSourceResume;
}

export function saveCachedStream(identity: StremioContentIdentity, stream: StremioStream): void {
  if (!isStreamCacheEnabled() || !stream.url) return;
  const now = Date.now();
  // A proxy link outlives its use and is reissued when the source is next played.
  const { playbackUrl: _playbackUrl, ...storable } = stream;
  const contentKey = buildContentKey(identity);
  const entries = Object.values(readIndex())
    .filter((entry) => entry.expiresAt > now && entry.contentKey !== contentKey)
    .sort((a, b) => b.savedAt - a.savedAt)
    .slice(0, MAX_ENTRIES - 1);
  const next: CachedStreamSource = {
    contentKey,
    stream: storable,
    savedAt: now,
    expiresAt: now + getSettings().streamCacheTTL,
  };
  tryWriteJson(
    STORAGE_KEYS.streamCache,
    Object.fromEntries([next, ...entries].map((entry) => [entry.contentKey, entry])),
  );
}

export function getCachedStream(identity: StremioContentIdentity): CachedStreamSource | null {
  const index = readIndex();
  const entry = index[buildContentKey(identity)];
  if (!entry) return null;
  if (entry.expiresAt < Date.now()) {
    removeCachedStream(identity);
    return null;
  }
  return entry;
}

export function removeCachedStream(identity: StremioContentIdentity): void {
  const index = readIndex();
  const contentKey = buildContentKey(identity);
  if (!index[contentKey]) return;
  delete index[contentKey];
  tryWriteJson(STORAGE_KEYS.streamCache, index);
}

export function clearStreamCache(): void {
  tryWriteJson(STORAGE_KEYS.streamCache, {});
}
