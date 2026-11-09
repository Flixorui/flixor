/** Resume positions for addon streams, keyed by content key. */
import { STORAGE_KEYS, readJson, tryWriteJson } from './storage';

export interface StreamResumeState {
  contentKey: string;
  positionMs: number;
  durationMs: number;
  updatedAt: number;
}

type ResumeIndex = Record<string, StreamResumeState>;

const MAX_ENTRIES = 500;

const readIndex = () => readJson<ResumeIndex>(STORAGE_KEYS.resume, {});

export function getResumeState(contentKey: string): StreamResumeState | null {
  return readIndex()[contentKey] ?? null;
}

export function saveResumeState(state: Omit<StreamResumeState, 'updatedAt'>): void {
  const index = readIndex();
  index[state.contentKey] = { ...state, updatedAt: Date.now() };
  const entries = Object.values(index)
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, MAX_ENTRIES);
  tryWriteJson(STORAGE_KEYS.resume, Object.fromEntries(entries.map((entry) => [entry.contentKey, entry])));
}

export function clearResumeState(contentKey: string): void {
  const index = readIndex();
  if (!index[contentKey]) return;
  delete index[contentKey];
  tryWriteJson(STORAGE_KEYS.resume, index);
}
