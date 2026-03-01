import AsyncStorage from '@react-native-async-storage/async-storage';
import { getProfileKey, PROFILE_SCOPED_KEYS } from '../core/ProfileStorage';
import type {
  CachedPlaybackSource,
  ResumeState,
  StremioAddonManifest,
} from './types';

export const STREMIO_DEFAULT_OPEN_SUBTITLES_URL = 'https://opensubtitles-v3.strem.io/manifest.json';
export const STREMIO_DEFAULT_OPEN_SUBTITLES_ID = 'org.stremio.opensubtitlesv3';

export function normalizeManifestUrl(url: string): string {
  const trimmed = url.trim();
  if (!trimmed) return '';
  return trimmed.endsWith('manifest.json')
    ? trimmed
    : `${trimmed.replace(/\/$/, '')}/manifest.json`;
}

async function readJson<T>(baseKey: string, fallback: T): Promise<T> {
  try {
    const value = await AsyncStorage.getItem(getProfileKey(baseKey));
    if (!value) return fallback;
    return JSON.parse(value) as T;
  } catch {
    return fallback;
  }
}

async function writeJson<T>(baseKey: string, value: T): Promise<void> {
  await AsyncStorage.setItem(getProfileKey(baseKey), JSON.stringify(value));
}

export async function readInstalledAddons(): Promise<StremioAddonManifest[]> {
  return readJson<StremioAddonManifest[]>(PROFILE_SCOPED_KEYS.STREMIO_ADDONS, []);
}

export async function writeInstalledAddons(addons: StremioAddonManifest[]): Promise<void> {
  await writeJson(PROFILE_SCOPED_KEYS.STREMIO_ADDONS, addons);
}

export async function readAddonOrder(): Promise<string[]> {
  return readJson<string[]>(PROFILE_SCOPED_KEYS.STREMIO_ADDON_ORDER, []);
}

export async function writeAddonOrder(order: string[]): Promise<void> {
  await writeJson(PROFILE_SCOPED_KEYS.STREMIO_ADDON_ORDER, order);
}

export async function readRemovedDefaultAddons(): Promise<string[]> {
  return readJson<string[]>(PROFILE_SCOPED_KEYS.STREMIO_REMOVED_DEFAULT_ADDONS, []);
}

export async function writeRemovedDefaultAddons(addonIds: string[]): Promise<void> {
  await writeJson(PROFILE_SCOPED_KEYS.STREMIO_REMOVED_DEFAULT_ADDONS, addonIds);
}

export async function readStreamCacheIndex(): Promise<Record<string, CachedPlaybackSource>> {
  return readJson<Record<string, CachedPlaybackSource>>(PROFILE_SCOPED_KEYS.STREMIO_STREAM_CACHE, {});
}

export async function writeStreamCacheIndex(index: Record<string, CachedPlaybackSource>): Promise<void> {
  await writeJson(PROFILE_SCOPED_KEYS.STREMIO_STREAM_CACHE, index);
}

export async function readResumeStateIndex(): Promise<Record<string, ResumeState>> {
  return readJson<Record<string, ResumeState>>(PROFILE_SCOPED_KEYS.STREMIO_RESUME_STATE, {});
}

export async function writeResumeStateIndex(index: Record<string, ResumeState>): Promise<void> {
  await writeJson(PROFILE_SCOPED_KEYS.STREMIO_RESUME_STATE, index);
}
