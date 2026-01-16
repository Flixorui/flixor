import { API_BASE_URL } from './api';
const BACKEND_API = API_BASE_URL.replace(/\/$/, '');

type ProgressState = 'playing' | 'paused' | 'stopped' | 'buffering';

function toDirectUrl(plexUrl: string): string { return plexUrl; }

// Current session ID for timeline updates (set when stream URL is fetched)
let currentSessionId: string = '';

// Get session ID from sessionStorage (fallback for frontend direct path)
function getSessionStorageId(): string {
  try {
    return sessionStorage.getItem('plex_session_id') || '';
  } catch {
    return '';
  }
}

// Get the current session ID (set by backendStreamUrl, or from sessionStorage as fallback)
export function getCurrentSessionId(): string {
  return currentSessionId || getSessionStorageId();
}

// Set the current session ID (called when stream URL is fetched)
export function setCurrentSessionId(sessionId: string): void {
  currentSessionId = sessionId;
  // Also sync to sessionStorage so Plex frontend direct path and backend path are consistent
  try {
    if (sessionId) {
      sessionStorage.setItem('plex_session_id', sessionId);
    }
  } catch {}
}

// Clear the current session ID (called when session is reset, e.g., quality change)
// This forces getCurrentSessionId to read from sessionStorage
export function clearCurrentSessionId(): void {
  currentSessionId = '';
}

export interface BackendStreamResult {
  url: string;
  sessionId: string;
}

export type StreamDecision = 'directplay' | 'copy' | 'transcode';

export interface TranscodeDecisionResult {
  generalDecisionCode: number;
  generalDecisionText: string;
  videoDecision: StreamDecision;
  audioDecision: StreamDecision;
  subtitleDecision?: StreamDecision;
  transcodeHwRequested?: boolean;
  transcodeHwFullPipeline?: boolean;
}

// Get transcode decision from Plex
export async function backendTranscodeDecision(ratingKey: string, options?: {
  quality?: number | string;
  resolution?: string;
  mediaIndex?: number;
  partIndex?: number;
  audioStreamID?: string;
  subtitleStreamID?: string;
}): Promise<TranscodeDecisionResult> {
  const res = await fetch(`${BACKEND_API}/plex/transcode/decision`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      ratingKey,
      quality: options?.quality,
      resolution: options?.resolution,
      mediaIndex: options?.mediaIndex,
      partIndex: options?.partIndex,
      audioStreamID: options?.audioStreamID,
      subtitleStreamID: options?.subtitleStreamID,
    }),
  });
  if (!res.ok) throw new Error(`Transcode decision failed: ${res.status}`);
  const json = await res.json();

  // Parse the Plex decision response
  const container = json.MediaContainer || json;
  const metadata = container.Metadata?.[0];
  const media = metadata?.Media?.[0];
  const part = media?.Part?.[0];
  const streams = part?.Stream || [];

  // Find video and audio stream decisions
  const videoStream = streams.find((s: any) => s.streamType === 1);
  const audioStream = streams.find((s: any) => s.streamType === 2);
  const subtitleStream = streams.find((s: any) => s.streamType === 3);

  return {
    generalDecisionCode: container.generalDecisionCode || 0,
    generalDecisionText: container.generalDecisionText || '',
    videoDecision: (videoStream?.decision || 'transcode') as StreamDecision,
    audioDecision: (audioStream?.decision || 'transcode') as StreamDecision,
    subtitleDecision: subtitleStream?.decision as StreamDecision | undefined,
    transcodeHwRequested: container.transcodeHwRequested,
    transcodeHwFullPipeline: container.transcodeHwFullPipeline,
  };
}

export async function backendStreamUrl(ratingKey: string, options?: {
  quality?: number | string; // numeric bitrate or 'original'
  resolution?: string; // e.g., '1920x1080'
  mediaIndex?: number;
  partIndex?: number;
  audioStreamID?: string;
  subtitleStreamID?: string;
}): Promise<BackendStreamResult> {
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

  // Store the session ID for timeline updates (also syncs to sessionStorage)
  if (json.sessionId) {
    setCurrentSessionId(json.sessionId);
  }

  return { url: toDirectUrl(json.url), sessionId: json.sessionId || '' };
}

export async function backendUpdateProgress(
  ratingKey: string,
  timeMs: number,
  durationMs: number,
  state: ProgressState = 'playing',
  isTranscoding?: boolean,
  sessionIdOverride?: string
) {
  // Use provided session ID, or fall back to the current session ID (with sessionStorage fallback)
  const sessionId = sessionIdOverride || getCurrentSessionId();
  const res = await fetch(`${BACKEND_API}/plex/progress`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      ratingKey,
      time: Math.floor(timeMs),
      duration: Math.floor(durationMs),
      state,
      sessionId: sessionId || undefined,
      isTranscoding: isTranscoding || false,
    }),
  });
  if (!res.ok) throw new Error(`Progress update failed: ${res.status}`);
  return res.json();
}
