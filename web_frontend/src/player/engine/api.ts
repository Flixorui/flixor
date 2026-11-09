/**
 * Backend calls for the player engine (backend/src/api/stremio.ts). `base` is a
 * stream's proxy address, `.../stremio/stream/<token>`.
 */
import { API_BASE_URL } from '@/services/api';
import { setServerConversion } from '@/stremio';
import type { MediaInfo, PlayDecision } from './decide';

let engineCheck: Promise<boolean> | null = null;

/** Asks once per page whether the server can convert, and tells the source labels. */
export function checkServerConversion(): Promise<boolean> {
  engineCheck ??= fetch(`${API_BASE_URL.replace(/\/$/, '')}/stremio/engine`, { credentials: 'include' })
    .then((res) => {
      if (!res.ok) throw new Error(String(res.status));
      return res.json();
    })
    .then((body: { conversion?: boolean }) => {
      const available = body.conversion === true;
      setServerConversion(available);
      return available;
    })
    .catch(() => {
      engineCheck = null; // Not signed in yet, or offline: ask again later.
      return false;
    });
  return engineCheck;
}

export async function probeStream(base: string, signal?: AbortSignal): Promise<MediaInfo | null> {
  const res = await fetch(`${base}/probe`, { credentials: 'include', signal });
  if (!res.ok) throw new Error(`Probe failed (${res.status})`);
  const body = (await res.json()) as { available: boolean; info?: MediaInfo };
  return body.available && body.info ? body.info : null;
}

export interface PlayParams {
  /** A remux or compatible decision. */
  decision: PlayDecision;
  start: number;
  player: string;
  /** Embedded text subtitle to stream alongside, as a stream index. */
  subtitleIndex: number | null;
  /** Embedded image subtitle to draw into the picture, as a stream index. */
  burnIndex?: number | null;
}

export function conversionUrl(base: string, { decision, start, player, subtitleIndex, burnIndex }: PlayParams, delivery: { hls: boolean; nonce: number }): string {
  const q = new URLSearchParams({
    mode: decision.path,
    start: start.toFixed(3),
    player,
    acopy: decision.copyAudio ? '1' : '0',
    ch: String(decision.audioChannels),
    dv: decision.keepDolbyVision ? '1' : '0',
  });
  if (decision.audioIndex !== null) q.set('audio', String(decision.audioIndex));
  if (subtitleIndex !== null) q.set('sub', String(subtitleIndex));
  if (burnIndex !== null && burnIndex !== undefined) q.set('burn', String(burnIndex));
  // HLS: each conversion is its own session path, so the playlist's relative segment
  // links stay inside it.
  if (delivery.hls) return `${base}/hls/${player}-${delivery.nonce}/index.m3u8?${q.toString()}`;
  q.set('n', String(delivery.nonce));
  return `${base}/play?${q.toString()}`;
}

export interface ConversionState {
  /** Film time where the conversion starts; null until FFmpeg has started writing. */
  start: number | null;
  /** WebVTT after `from`, on the film's timeline. */
  text: string;
  next: number;
  done: boolean;
  subtitles?: boolean;
  missing?: boolean;
}

export async function fetchConversionState(base: string, player: string, from: number, signal?: AbortSignal): Promise<ConversionState> {
  const res = await fetch(`${base}/conversion?player=${encodeURIComponent(player)}&from=${from}`, { credentials: 'include', signal });
  if (!res.ok) throw new Error(`Conversion state failed (${res.status})`);
  return res.json();
}
