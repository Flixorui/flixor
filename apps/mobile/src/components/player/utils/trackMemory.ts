/**
 * Remembers the audio and subtitle language chosen per title and per series.
 * macOS reference: Services/TrackPreferenceService.swift
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { getProfileKey } from '../../../core/ProfileStorage';

const STORAGE_KEY = 'flixor_track_memory';
const MAX_ENTRIES = 400;
/** Stored as the subtitle "language" when the user turned subtitles off. */
export const SUBTITLES_OFF = 'none';

type TrackKind = 'audio' | 'subtitle';
type Store = Record<TrackKind, Record<string, string>>;

export type TrackMemoryIds = { mediaId: string; seriesId?: string };
export type RememberedTracks = { audio?: string; subtitle?: string };

async function readStore(): Promise<Store> {
  try {
    const raw = await AsyncStorage.getItem(getProfileKey(STORAGE_KEY));
    const parsed = raw ? JSON.parse(raw) : null;
    return { audio: parsed?.audio ?? {}, subtitle: parsed?.subtitle ?? {} };
  } catch {
    return { audio: {}, subtitle: {} };
  }
}

export async function loadRememberedTracks(ids: TrackMemoryIds): Promise<RememberedTracks> {
  const store = await readStore();
  const seriesKey = ids.seriesId ? `series:${ids.seriesId}` : undefined;
  return {
    audio: store.audio[ids.mediaId] ?? (seriesKey ? store.audio[seriesKey] : undefined),
    subtitle: store.subtitle[ids.mediaId] ?? (seriesKey ? store.subtitle[seriesKey] : undefined),
  };
}

function setEntry(map: Record<string, string>, key: string, value: string): void {
  // Delete first so the entry moves to the end, making the oldest keys the first pruned.
  delete map[key];
  map[key] = value;
  const keys = Object.keys(map);
  for (const stale of keys.slice(0, Math.max(0, keys.length - MAX_ENTRIES))) {
    delete map[stale];
  }
}

let writes: Promise<void> = Promise.resolve();

export function saveTrackChoice(kind: TrackKind, ids: TrackMemoryIds, language: string): void {
  writes = writes.then(async () => {
    try {
      const store = await readStore();
      setEntry(store[kind], ids.mediaId, language);
      if (ids.seriesId) {
        setEntry(store[kind], `series:${ids.seriesId}`, language);
      }
      await AsyncStorage.setItem(getProfileKey(STORAGE_KEY), JSON.stringify(store));
    } catch (error) {
      console.log('[TrackMemory] Failed to save choice:', error);
    }
  });
}
