import { API_BASE_URL } from './api';
const BACKEND_API = API_BASE_URL.replace(/\/$/, '');

type ProgressState = 'playing' | 'paused' | 'stopped' | 'buffering';

function toDirectUrl(plexUrl: string): string { return plexUrl; }

export async function backendStreamUrl(ratingKey: string, options?: {
  quality?: number | string; // numeric bitrate or 'original'
  resolution?: string; // e.g., '1920x1080'
  mediaIndex?: number;
  partIndex?: number;
  audioStreamID?: string;
  subtitleStreamID?: string;
}): Promise<string> {
  const params = new URLSearchParams();
  if (options?.quality && typeof options.quality === 'number') params.set('quality', String(options.quality));
  if (options?.resolution) params.set('resolution', options.resolution);
  if (options?.mediaIndex != null) params.set('mediaIndex', String(options.mediaIndex));
  if (options?.partIndex != null) params.set('partIndex', String(options.partIndex));
  // Omit stream selection for DASH start URL to match legacy frontend behavior

  const res = await fetch(`${BACKEND_API}/plex/stream/${encodeURIComponent(ratingKey)}${params.size ? `?${params.toString()}` : ''}`, {
    credentials: 'include',
  });
  if (!res.ok) throw new Error(`Stream URL failed: ${res.status}`);
  const json = await res.json();
  return toDirectUrl(json.url);
}

export async function backendUpdateProgress(ratingKey: string, timeMs: number, durationMs: number, state: ProgressState = 'playing') {
  const res = await fetch(`${BACKEND_API}/plex/progress`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ratingKey, time: Math.floor(timeMs), duration: Math.floor(durationMs), state }),
  });
  if (!res.ok) throw new Error(`Progress update failed: ${res.status}`);
  return res.json();
}
