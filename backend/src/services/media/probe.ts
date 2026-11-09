/**
 * What a media file contains, from ffprobe: container, duration, the video stream
 * (codec, bit depth, HDR, Dolby Vision), and every audio and subtitle track. The web
 * player uses it to decide between direct play, remux and conversion.
 */
import crypto from 'crypto';
import { runFfprobe } from './ffmpeg';

export interface VideoInfo {
  index: number;
  codec: string;
  profile?: string;
  /** Four-character tag in the source, e.g. hvc1, hev1, dvh1, avc1. */
  codecTag?: string;
  width?: number;
  height?: number;
  bitDepth: number;
  pixFmt?: string;
  frameRate?: number;
  /** PQ (HDR10, Dolby Vision) or HLG; null for SDR. */
  hdr: 'pq' | 'hlg' | null;
  /** Dolby Vision profile (5, 7, 8...), or null without Dolby Vision. */
  dolbyVisionProfile: number | null;
  /** 1 = HDR10 base layer, 2 = SDR, 4 = HLG, 0 = none (profile 5). */
  dolbyVisionCompatibility: number | null;
}

export interface AudioTrack {
  /** Stream index in the file. */
  index: number;
  /** Position among audio tracks (FFmpeg `0:a:N`). */
  order: number;
  codec: string;
  profile?: string;
  channels: number;
  language?: string;
  title?: string;
  isDefault: boolean;
}

export interface SubtitleTrack {
  index: number;
  order: number;
  codec: string;
  language?: string;
  title?: string;
  isDefault: boolean;
  forced: boolean;
  /** Text subtitles can become WebVTT; image ones (PGS, VobSub) are burned in. */
  isText: boolean;
  /** Canvas size of an image subtitle, when the file states it. */
  width?: number;
  height?: number;
}

export interface MediaInfo {
  container: string;
  duration: number;
  bitRate?: number;
  video: VideoInfo | null;
  audio: AudioTrack[];
  subtitles: SubtitleTrack[];
}

const TEXT_SUBTITLES = new Set(['subrip', 'srt', 'ass', 'ssa', 'webvtt', 'mov_text', 'text']);

function num(value: unknown): number | undefined {
  const n = typeof value === 'string' ? parseFloat(value) : typeof value === 'number' ? value : NaN;
  return Number.isFinite(n) ? n : undefined;
}

function rate(value: unknown): number | undefined {
  if (typeof value !== 'string') return undefined;
  const [a, b] = value.split('/').map(Number);
  return b ? Math.round((a / b) * 1000) / 1000 : num(a);
}

function bitDepthOf(stream: any): number {
  const raw = num(stream.bits_per_raw_sample);
  if (raw) return raw;
  const fmt = String(stream.pix_fmt || '');
  const match = /p(\d{2})(?:le|be)?$/.exec(fmt);
  return match ? parseInt(match[1], 10) : 8;
}

/** Pure: turns `ffprobe -show_streams -show_format -of json` output into MediaInfo. */
export function normalizeProbe(json: any): MediaInfo {
  const streams: any[] = Array.isArray(json?.streams) ? json.streams : [];
  const format = json?.format ?? {};
  let videoStream: any;
  const audio: AudioTrack[] = [];
  const subtitles: SubtitleTrack[] = [];

  for (const s of streams) {
    const tags = s.tags ?? {};
    const disposition = s.disposition ?? {};
    if (s.codec_type === 'video' && !disposition.attached_pic && !videoStream) {
      videoStream = s;
    } else if (s.codec_type === 'audio') {
      audio.push({
        index: s.index,
        order: audio.length,
        codec: String(s.codec_name || 'unknown'),
        profile: s.profile,
        channels: num(s.channels) ?? 2,
        language: tags.language,
        title: tags.title,
        isDefault: disposition.default === 1,
      });
    } else if (s.codec_type === 'subtitle') {
      const codec = String(s.codec_name || 'unknown');
      subtitles.push({
        index: s.index,
        order: subtitles.length,
        codec,
        language: tags.language,
        title: tags.title,
        isDefault: disposition.default === 1,
        forced: disposition.forced === 1,
        isText: TEXT_SUBTITLES.has(codec),
        width: num(s.width) || undefined,
        height: num(s.height) || undefined,
      });
    }
  }

  let video: VideoInfo | null = null;
  if (videoStream) {
    const dovi = (videoStream.side_data_list ?? []).find((d: any) =>
      String(d.side_data_type || '').toLowerCase().includes('dovi'),
    );
    const transfer = String(videoStream.color_transfer || '');
    const hdr = transfer === 'smpte2084' ? 'pq' : transfer === 'arib-std-b67' ? 'hlg' : null;
    const dvProfile = dovi ? num(dovi.dv_profile) ?? null : null;
    video = {
      index: videoStream.index,
      codec: String(videoStream.codec_name || 'unknown'),
      profile: videoStream.profile,
      codecTag: videoStream.codec_tag_string && videoStream.codec_tag_string !== '[0][0][0][0]'
        ? videoStream.codec_tag_string
        : undefined,
      width: num(videoStream.width),
      height: num(videoStream.height),
      bitDepth: bitDepthOf(videoStream),
      pixFmt: videoStream.pix_fmt,
      frameRate: rate(videoStream.avg_frame_rate) ?? rate(videoStream.r_frame_rate),
      // Profile 5 carries no transfer tag but is PQ.
      hdr: hdr ?? (dvProfile !== null ? 'pq' : null),
      dolbyVisionProfile: dvProfile,
      dolbyVisionCompatibility: dovi ? num(dovi.dv_bl_signal_compatibility_id) ?? null : null,
    };
  }

  return {
    container: String(format.format_name || 'unknown'),
    duration: num(format.duration) ?? num(videoStream?.duration) ?? 0,
    bitRate: num(format.bit_rate),
    video,
    audio,
    subtitles,
  };
}

const cache = new Map<string, { info: MediaInfo; expiresAt: number }>();
const CACHE_TTL_MS = 30 * 60 * 1000;

function cacheKey(url: string): string {
  return crypto.createHash('sha256').update(url).digest('base64url');
}

/**
 * Probes `input` (a relay URL). `cacheUrl` is the upstream URL, so the same file is
 * probed once however many tokens point at it.
 */
export async function probeMedia(input: string, cacheUrl: string): Promise<MediaInfo> {
  const key = cacheKey(cacheUrl);
  const hit = cache.get(key);
  if (hit && hit.expiresAt > Date.now()) return hit.info;
  const out = await runFfprobe(
    ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', '-rw_timeout', '20000000', input],
    45_000,
  );
  const info = normalizeProbe(JSON.parse(out));
  if (cache.size > 500) cache.clear();
  cache.set(key, { info, expiresAt: Date.now() + CACHE_TTL_MS });
  return info;
}
