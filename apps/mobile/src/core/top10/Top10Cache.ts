/**
 * Responses saved on the phone with their fetch time, so lists show straight away and the
 * APIs are asked again only once an entry is due. Kept in memory after the first read.
 * macOS reference: StreamingAvailabilityCache.swift
 */

import AsyncStorage from '@react-native-async-storage/async-storage';

export type CacheEntry = { body: string; fetchedAt: number };

const PREFIX = 'top10cache:';
const memory = new Map<string, CacheEntry | null>();
let generation = 0;

export const cacheGeneration = () => generation;

export async function readCache(key: string): Promise<CacheEntry | null> {
  if (memory.has(key)) return memory.get(key) ?? null;
  try {
    const raw = await AsyncStorage.getItem(PREFIX + key);
    const entry = raw ? (JSON.parse(raw) as CacheEntry) : null;
    memory.set(key, entry);
    return entry;
  } catch {
    return null;
  }
}

export async function writeCache(key: string, body: string): Promise<void> {
  const entry = { body, fetchedAt: Date.now() };
  memory.set(key, entry);
  generation += 1;
  try {
    await AsyncStorage.setItem(PREFIX + key, JSON.stringify(entry));
  } catch {
    // The memory copy still serves this session
  }
}

export async function clearCache(): Promise<void> {
  memory.clear();
  generation += 1;
  const keys = (await AsyncStorage.getAllKeys()).filter((k) => k.startsWith(PREFIX));
  if (keys.length) await AsyncStorage.multiRemove(keys);
}
