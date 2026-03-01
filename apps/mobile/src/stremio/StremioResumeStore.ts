import { readResumeStateIndex, writeResumeStateIndex } from './StremioStorage';
import type { ResumeState } from './types';

class StremioResumeStore {
  async get(contentKey: string): Promise<ResumeState | null> {
    const index = await readResumeStateIndex();
    return index[contentKey] || null;
  }

  async save(state: ResumeState): Promise<void> {
    const index = await readResumeStateIndex();
    index[state.contentKey] = state;
    await writeResumeStateIndex(index);
  }

  async clear(contentKey: string): Promise<void> {
    const index = await readResumeStateIndex();
    if (!index[contentKey]) {
      return;
    }
    delete index[contentKey];
    await writeResumeStateIndex(index);
  }
}

export const stremioResumeStore = new StremioResumeStore();
