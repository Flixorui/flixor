/**
 * Browser storage for the addon platform. The addon list, resume points and history
 * also follow the account through services/accountSync.ts, which the backend stores
 * encrypted because manifest URLs can embed debrid keys. The stream cache stays here.
 */

const PREFIX = 'flixor.stremio.';

export const STORAGE_KEYS = {
  addons: `${PREFIX}addons`,
  removedDefaults: `${PREFIX}removedDefaults`,
  streamCache: `${PREFIX}streamCache`,
  resume: `${PREFIX}resume`,
  history: `${PREFIX}history`,
  watched: `${PREFIX}watched`,
} as const;

export function readJson<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

/** Throws when storage is full or unavailable. Use for data the user is waiting on. */
export function writeJson(key: string, value: unknown): void {
  localStorage.setItem(key, JSON.stringify(value));
}

/** For caches and history, where a lost write only costs a convenience. */
export function tryWriteJson(key: string, value: unknown): boolean {
  try {
    writeJson(key, value);
    return true;
  } catch {
    return false;
  }
}

/** A keyed store that notifies listeners when it changes, in this tab and others. */
export function createChangeNotifier(storageKey: string) {
  const listeners = new Set<() => void>();
  const notify = () => listeners.forEach((listener) => listener());
  if (typeof window !== 'undefined') {
    window.addEventListener('storage', (event) => {
      if (event.key === storageKey || event.key === null) notify();
    });
  }
  return {
    notify,
    subscribe(listener: () => void): () => void {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
}
