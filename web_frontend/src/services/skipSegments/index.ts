import { API_BASE_URL } from '@/services/api';

export type SkipSegmentType = 'intro' | 'recap' | 'credits' | 'preview' | 'postcredits';

export interface SkipSegment {
  type: SkipSegmentType;
  start: number;
  /** Seconds. Null means it runs to the end of the file. */
  end: number | null;
  provider: string;
}

export interface SkipSegmentRequest {
  imdbId?: string;
  tmdbId?: number;
  isMovie: boolean;
  season?: number;
  episode?: number;
  kitsuId?: string;
  malId?: string;
  animeSkipClientId?: string;
}

const API = `${API_BASE_URL.replace(/\/$/, '')}/skip-segments`;

/** Community intro, recap and credits timings. Any failure means "no segments". */
export async function fetchSkipSegments(request: SkipSegmentRequest, signal?: AbortSignal): Promise<SkipSegment[]> {
  try {
    const res = await fetch(`${API}/lookup`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request),
      signal,
    });
    if (!res.ok) return [];
    const json = await res.json();
    return Array.isArray(json?.segments) ? json.segments : [];
  } catch {
    return [];
  }
}
