/**
 * Keeps this browser's settings, addons and lists in step with the signed-in
 * account, through the backend (/api/sync). A new browser loads the account's copy
 * before the app decides whether setup is needed; changes made here are saved back.
 *
 * Settings objects sync field by field, so two browsers changing different settings
 * both keep their change. Other keys sync whole. Credentials for Plex, and anything
 * that identifies this browser or device, stay local.
 */
import { API_BASE_URL } from '@/services/api';

const SETTINGS_KEY = 'app.settings.v1';
const PROFILE_PREFIX = 'profile:';
const STATE_KEY = 'flixor.sync.state.v1';

/** Whole keys that follow the account. */
const SYNCED_KEYS = [
  'app.homeRowCatalog.v1',
  'flixor.userCollections.v1',
  'flixor.stremio.addons',
  'flixor.stremio.removedDefaults',
  'flixor.stremio.resume',
  'flixor.stremio.watched',
  'flixor.stremio.history',
  'player.audioTrackPreferences',
  'player.subtitleTrackPreferences',
];

/** Settings fields that belong to this browser or to the Plex sign-in, never synced. */
const LOCAL_FIELDS = new Set([
  'plexClientId',
  'plexBaseUrl', 'plexToken', 'plexTvToken', 'plexAccountToken', 'plexServer',
  'plexServers', 'plexUserProfile', 'plexUsers', 'plexCurrentUserId',
]);

const FIELD_SEPARATOR = '#';

type Units = Record<string, string>;
type SyncState = { account: string; version: number; hashes: Record<string, string> };
type Remote = { account: string; version: number; units: Units };

function isSettingsKey(key: string): boolean {
  return key === SETTINGS_KEY || (key.startsWith(PROFILE_PREFIX) && key.endsWith(`:${SETTINGS_KEY}`));
}

function readObject(key: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(localStorage.getItem(key) || '{}');
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

/** This browser's synced data, one unit per settings field or whole key. */
function collectLocal(): Units {
  const units: Units = {};
  const settingsKeys: string[] = [];
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (key && isSettingsKey(key)) settingsKeys.push(key);
  }
  for (const key of settingsKeys) {
    for (const [field, value] of Object.entries(readObject(key))) {
      if (LOCAL_FIELDS.has(field) || value === undefined) continue;
      units[`${key}${FIELD_SEPARATOR}${field}`] = JSON.stringify(value);
    }
  }
  for (const key of SYNCED_KEYS) {
    const raw = localStorage.getItem(key);
    if (raw !== null) units[key] = raw;
  }
  return units;
}

/** Writes the given units (null removes) and tells listeners in this tab. */
function applyUnits(changes: Record<string, string | null>) {
  const objects = new Map<string, Record<string, unknown>>();
  const touched = new Set<string>();
  for (const [unit, value] of Object.entries(changes)) {
    const at = unit.indexOf(FIELD_SEPARATOR);
    if (at > 0 && isSettingsKey(unit.slice(0, at))) {
      const key = unit.slice(0, at);
      const field = unit.slice(at + 1);
      if (LOCAL_FIELDS.has(field)) continue;
      if (!objects.has(key)) objects.set(key, readObject(key));
      const obj = objects.get(key)!;
      if (value === null) delete obj[field];
      else {
        try {
          obj[field] = JSON.parse(value);
        } catch {
          continue;
        }
      }
      touched.add(key);
    } else if (SYNCED_KEYS.includes(unit)) {
      if (value === null) localStorage.removeItem(unit);
      else localStorage.setItem(unit, value);
      touched.add(unit);
    }
  }
  for (const [key, obj] of objects) localStorage.setItem(key, JSON.stringify(obj));
  // Same-tab writes do not fire 'storage'; the stores listen for it to refresh.
  for (const key of touched) {
    try {
      window.dispatchEvent(new StorageEvent('storage', { key, storageArea: localStorage }));
    } catch {
      // Very old browsers: the next page load picks the values up.
    }
  }
}

// FNV-1a: only used to tell whether a unit changed since the last sync.
function hash(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return `${(h >>> 0).toString(36)}.${text.length}`;
}

function hashAll(units: Units): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(units)) out[k] = hash(v);
  return out;
}

function loadState(): SyncState | null {
  try {
    const parsed = JSON.parse(localStorage.getItem(STATE_KEY) || 'null');
    return parsed && typeof parsed.account === 'string' ? parsed : null;
  } catch {
    return null;
  }
}

function saveState(state: SyncState) {
  try {
    localStorage.setItem(STATE_KEY, JSON.stringify(state));
  } catch {
    // Storage full: the next sync redoes the merge.
  }
}

/** Units changed in this browser since it last synced with `state`. */
function dirtyUnits(local: Units, state: SyncState | null): Set<string> {
  const dirty = new Set<string>();
  const hashes = state?.hashes ?? {};
  for (const [k, v] of Object.entries(local)) if (hashes[k] !== hash(v)) dirty.add(k);
  for (const k of Object.keys(hashes)) if (!(k in local)) dirty.add(k);
  return dirty;
}

/**
 * Brings the account's copy into this browser. Units changed here since the last
 * sync keep the local value; everything else takes the account's. A browser that
 * last synced another account (or never synced) takes the account's copy, and keeps
 * only data the account does not have yet if it never synced at all.
 */
function mergeRemote(remote: Remote): { local: Units; dirty: Set<string> } {
  const state = loadState();
  const local = collectLocal();
  const sameAccount = state?.account === remote.account;
  const neverSynced = !state;
  const dirty = sameAccount ? dirtyUnits(local, state) : new Set<string>();

  const changes: Record<string, string | null> = {};
  for (const [k, v] of Object.entries(remote.units)) {
    if (!dirty.has(k) && local[k] !== v) changes[k] = v;
  }
  for (const k of Object.keys(local)) {
    if (k in remote.units || dirty.has(k)) continue;
    if (sameAccount) {
      // Removed by another browser since this one last synced.
      if (state!.hashes[k] !== undefined) changes[k] = null;
    } else if (neverSynced) {
      // This browser's data from before sync existed: give it to the account.
      dirty.add(k);
    } else {
      // Left over from the account this browser used before.
      changes[k] = null;
    }
  }
  applyUnits(changes);
  saveState({ account: remote.account, version: remote.version, hashes: hashAll(remote.units) });
  return { local: collectLocal(), dirty };
}

async function fetchRemote(): Promise<Remote | null> {
  const res = await fetch(`${API_BASE_URL}/sync`, { credentials: 'include', cache: 'no-store' });
  if (res.status === 401) return null;
  if (!res.ok) throw new Error(`Sync load failed (${res.status})`);
  return res.json();
}

let pushing: Promise<void> | null = null;

/** Saves this browser's changes. On a conflict, merges the newer copy and tries again. */
async function push(attempt = 0): Promise<void> {
  const state = loadState();
  if (!state) return;
  const units = collectLocal();
  if (dirtyUnits(units, state).size === 0) return;

  const res = await fetch(`${API_BASE_URL}/sync`, {
    method: 'PUT',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ baseVersion: state.version, units }),
  });
  if (res.status === 409 && attempt < 2) {
    mergeRemote(await res.json());
    return push(attempt + 1);
  }
  if (!res.ok) throw new Error(`Sync save failed (${res.status})`);
  const body = await res.json();
  saveState({ account: body.account, version: body.version, hashes: hashAll(units) });
}

let lastPushAt = 0;
const MIN_PUSH_GAP_MS = 10_000;

function pushSoon() {
  if (pushing) return;
  lastPushAt = Date.now();
  pushing = push()
    .catch((error) => console.warn('[sync] save failed', error))
    .finally(() => {
      pushing = null;
    });
}

let pulled: Promise<boolean> | null = null;
let watching = false;

async function pull(): Promise<boolean> {
  const remote = await fetchRemote();
  if (!remote) return false;
  const { dirty } = mergeRemote(remote);
  if (dirty.size > 0) pushSoon();
  watch();
  return true;
}

/**
 * Resolves once this browser has the signed-in account's settings, or straight away
 * when nobody is signed in or the backend cannot be reached. Call before deciding
 * anything from settings that a new browser would not have, such as onboarding.
 */
export function ensureAccountSynced(): Promise<boolean> {
  if (!pulled) {
    pulled = pull().catch((error) => {
      console.warn('[sync] load failed', error);
      return false;
    });
    // Not signed in yet: try again after sign-in.
    pulled.then((ok) => {
      if (!ok) pulled = null;
    });
  }
  return pulled;
}

/** Saves local changes every few seconds, and loads other browsers' changes on focus. */
function watch() {
  if (watching) return;
  watching = true;
  let lastLocal = JSON.stringify(collectLocal());
  // Playback updates resume points often; one save per ten seconds is enough.
  window.setInterval(() => {
    if (pushing || Date.now() - lastPushAt < MIN_PUSH_GAP_MS) return;
    const now = JSON.stringify(collectLocal());
    if (now === lastLocal) return;
    lastLocal = now;
    pushSoon();
  }, 3000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') {
      pushSoon();
    } else if (!pushing) {
      fetchRemote()
        .then((remote) => {
          if (!remote || remote.version <= (loadState()?.version ?? 0)) return;
          const { dirty } = mergeRemote(remote);
          lastLocal = JSON.stringify(collectLocal());
          if (dirty.size > 0) pushSoon();
        })
        .catch(() => {});
    }
  });
}
