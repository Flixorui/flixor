type Entry<T> = { t: number; v: T };

const CACHE_NS = 'app.cache.v1';
const mem = new Map<string, Entry<any>>();

function now() { return Date.now(); }

function getStore(): Storage | null {
  try { return sessionStorage; } catch { return null; }
}

// Eviction / capacity management for sessionStorage
const MAX_SESSION_ENTRIES = 250; // soft cap

function listCacheKeys(store: Storage): string[] {
  const keys: string[] = [];
  for (let i = 0; i < store.length; i++) {
    const k = store.key(i);
    if (k && k.startsWith(CACHE_NS + ':')) keys.push(k);
  }
  return keys;
}

function parseTs(raw: string | null): number {
  if (!raw) return 0;
  try {
    const e = JSON.parse(raw) as Entry<any>;
    return typeof e?.t === 'number' ? e.t : 0;
  } catch { return 0; }
}

function evictOldest(store: Storage, count: number) {
  const keys = listCacheKeys(store)
    .map((k) => ({ k, t: parseTs(store.getItem(k)) }))
    .sort((a, b) => a.t - b.t);
  for (let i = 0; i < Math.min(count, keys.length); i++) {
    try { store.removeItem(keys[i].k); } catch {}
  }
}

function sweepExpired(store: Storage, ttlMs: number) {
  const keys = listCacheKeys(store);
  const nowTs = now();
  for (const k of keys) {
    try {
      const raw = store.getItem(k);
      if (!raw) continue;
      const e = JSON.parse(raw) as Entry<any>;
      if (nowTs - (e?.t || 0) >= ttlMs) store.removeItem(k);
    } catch {}
  }
}

function ensureCapacityAndSet(store: Storage, key: string, value: string) {
  try {
    // Soft cap by entries
    const keys = listCacheKeys(store);
    if (keys.length >= MAX_SESSION_ENTRIES) evictOldest(store, Math.ceil(keys.length - MAX_SESSION_ENTRIES + 10));
    store.setItem(key, value);
    return;
  } catch (e) {
    // Quota exceeded or other failures – try evicting and retrying
    try { evictOldest(store, 15); } catch {}
    try { store.setItem(key, value); return; } catch {}
    // As a last resort, sweep everything under our namespace
    try {
      for (const k of listCacheKeys(store)) store.removeItem(k);
      store.setItem(key, value);
    } catch {}
  }
}

export async function cached<T>(key: string, ttlMs: number, loader: () => Promise<T>): Promise<T> {
  const full = CACHE_NS + ':' + key;
  const store = getStore();
  try {
    const raw = store?.getItem(full);
    if (raw) {
      const e: Entry<T> = JSON.parse(raw);
      if (now() - e.t < ttlMs) return e.v;
      // Remove expired entry to free space
      try { store?.removeItem(full); } catch {}
    }
  } catch {}
  if (mem.has(full)) {
    const e = mem.get(full)! as Entry<T>;
    if (now() - e.t < ttlMs) return e.v;
  }
  const v = await loader();
  const e: Entry<T> = { t: now(), v };
  mem.set(full, e);
  try {
    if (store) {
      // Opportunistically sweep some expired entries
      sweepExpired(store, ttlMs);
      ensureCapacityAndSet(store, full, JSON.stringify(e));
    }
  } catch { /* ignore */ }
  return v;
}

export function forget(prefix: string) {
  const p = CACHE_NS + ':' + prefix;
  const store = getStore();
  if (store) {
    const keys = listCacheKeys(store);
    keys.forEach(k => { if (k.startsWith(p)) try { store.removeItem(k); } catch {} });
  }
  Array.from(mem.keys()).forEach(k => { if (k.startsWith(p)) mem.delete(k); });
}
