/**
 * Streaming Availability keys and FlixPatrol sources, shared across profiles, in the iOS
 * Keychain (expo-secure-store). Every key is registered with the logger so it is blanked
 * out of any log line.
 */

import * as SecureStore from 'expo-secure-store';
import { appLogger } from '../AppLogger';
import { fingerprint } from './sha256';

const KEYS = 'streamingAvailability.apiKeys';
const SOURCES = 'flixPatrol.sources';

export type FlixPatrolSource = { url: string; key: string };

export const sourceId = (s: FlixPatrolSource) => fingerprint(`${s.url}|${s.key}`);
export const maskKey = (key: string) => '••••••••' + key.slice(-4);

export function sourceHost(s: FlixPatrolSource): string {
  const match = s.url.match(/^[a-z]+:\/\/([^/:?#]+)/i);
  return match ? match[1] : s.url;
}

/** The URL as typed, without spaces or a trailing slash, with https:// added when missing. */
export function normalizeUrl(raw: string): string {
  let url = raw.trim().replace(/\/+$/, '');
  if (url && !url.includes('://')) url = 'https://' + url;
  return url;
}

async function readJson<T>(name: string): Promise<T[]> {
  try {
    const raw = await SecureStore.getItemAsync(name);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function writeJson(name: string, value: unknown[]): Promise<void> {
  if (value.length === 0) await SecureStore.deleteItemAsync(name);
  else await SecureStore.setItemAsync(name, JSON.stringify(value));
}

export async function loadKeys(): Promise<string[]> {
  const keys = (await readJson<string>(KEYS)).filter((k) => typeof k === 'string' && k.length > 0);
  keys.forEach((k) => appLogger.registerSensitiveValue(k));
  return keys;
}

export async function saveKeys(keys: string[]): Promise<void> {
  keys.forEach((k) => appLogger.registerSensitiveValue(k));
  await writeJson(KEYS, keys);
}

export async function loadSources(): Promise<FlixPatrolSource[]> {
  const sources = (await readJson<FlixPatrolSource>(SOURCES)).filter((s) => s && s.url && s.key);
  sources.forEach((s) => appLogger.registerSensitiveValue(s.key));
  return sources;
}

export async function saveSources(sources: FlixPatrolSource[]): Promise<void> {
  sources.forEach((s) => appLogger.registerSensitiveValue(s.key));
  await writeJson(SOURCES, sources);
}
