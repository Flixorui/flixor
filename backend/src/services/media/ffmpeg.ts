/**
 * FFmpeg and ffprobe for the web player: where the binaries are, whether they work,
 * which H.264 encoder to use, and the running conversions.
 *
 * Commands are always argument lists (never a shell). Each conversion runs in its own
 * process group, so stopping it also stops anything FFmpeg started.
 */
import { ChildProcess, execFile, spawn } from 'child_process';
import { createLogger } from '../../utils/logger';
import { firstPacketTime } from './transcode';

const logger = createLogger('media');

export const FFMPEG = process.env.FFMPEG_PATH || 'ffmpeg';
export const FFPROBE = process.env.FFPROBE_PATH || 'ffprobe';

/** At most this many conversions at once, across all users. */
const MAX_CONVERSIONS = Math.max(1, parseInt(process.env.FLIXOR_MAX_CONVERSIONS || '3', 10) || 3);

export type VideoEncoder = 'h264_videotoolbox' | 'libx264';

export interface MediaTools {
  ffmpeg: boolean;
  ffprobe: boolean;
  encoders: Set<string>;
  filters: Set<string>;
}

let availability: Promise<MediaTools> | undefined;

function run(bin: string, args: string[], timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(bin, args, { timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 }, (error, stdout) => {
      if (error) reject(error);
      else resolve(stdout);
    });
  });
}

/** Checks once per process whether both binaries run, and lists the encoders. */
export function mediaToolsAvailable(): Promise<MediaTools> {
  availability ??= (async () => {
    const [ffmpeg, filterList, ffprobe] = await Promise.all([
      run(FFMPEG, ['-hide_banner', '-encoders'], 10_000).catch(() => null),
      run(FFMPEG, ['-hide_banner', '-filters'], 10_000).catch(() => null),
      run(FFPROBE, ['-version'], 10_000).catch(() => null),
    ]);
    const encoders = new Set<string>();
    for (const line of (ffmpeg ?? '').split('\n')) {
      const match = /^\s*[VAS][.A-Z]{5}\s+(\S+)/.exec(line);
      if (match) encoders.add(match[1]);
    }
    const filters = new Set<string>();
    for (const line of (filterList ?? '').split('\n')) {
      const match = /^\s*[.A-Z|]{2,3}\s+(\S+)\s+\S+->\S+/.exec(line);
      if (match) filters.add(match[1]);
    }
    const result = { ffmpeg: ffmpeg !== null, ffprobe: ffprobe !== null, encoders, filters };
    logger.info('Media tools', { ffmpeg: result.ffmpeg, ffprobe: result.ffprobe });
    return result;
  })();
  return availability;
}

/** `FLIXOR_VIDEO_ENCODER` wins; otherwise VideoToolbox on macOS when present, else libx264. */
export async function pickVideoEncoder(): Promise<VideoEncoder> {
  const wanted = process.env.FLIXOR_VIDEO_ENCODER;
  if (wanted === 'h264_videotoolbox' || wanted === 'libx264') return wanted;
  const { encoders } = await mediaToolsAvailable();
  if (process.platform === 'darwin' && encoders.has('h264_videotoolbox')) return 'h264_videotoolbox';
  return 'libx264';
}

export function runFfprobe(args: string[], timeoutMs: number): Promise<string> {
  return run(FFPROBE, args, timeoutMs);
}

interface ConversionState {
  /** Real time where the output starts, once FFmpeg has written its first video packet. */
  start: number | null;
  /** WebVTT written so far, when a subtitle is streamed alongside. */
  text: string;
  subtitles: boolean;
  done: boolean;
}

const states = new Map<string, ConversionState>();

/** Start time and subtitle text after `from` (a character offset) for `key`'s conversion. */
export function readConversionState(key: string, from: number) {
  const state = states.get(key);
  if (!state) return null;
  return { start: state.start, text: state.text.slice(from), next: state.text.length, done: state.done, subtitles: state.subtitles };
}

interface Conversion {
  child: ChildProcess;
  key: string;
}

const running = new Map<string, Conversion>();

function killGroup(child: ChildProcess) {
  if (child.exitCode !== null || child.signalCode !== null || !child.pid) return;
  try {
    process.kill(-child.pid, 'SIGKILL');
  } catch {
    child.kill('SIGKILL');
  }
}

export class ConversionLimitError extends Error {}

/**
 * Starts FFmpeg for one player. A player (`key`) has at most one conversion: starting
 * a new one, for a seek or another track, stops the previous one first.
 */
export function startConversion(
  key: string,
  args: string[],
  options: { subtitlePipe?: boolean; knownStart?: number } = {},
): ChildProcess {
  const previous = running.get(key);
  if (previous) {
    killGroup(previous.child);
    running.delete(key);
  }
  if (running.size >= MAX_CONVERSIONS) {
    throw new ConversionLimitError('Too many videos are being converted right now');
  }
  // fd 3: WebVTT subtitles (when asked for); fd 4: framecrc of the first video packet.
  const child = spawn(FFMPEG, args, {
    stdio: ['ignore', 'pipe', 'pipe', 'pipe', 'pipe'],
    detached: true,
  });
  const state: ConversionState = { start: options.knownStart ?? null, text: '', subtitles: Boolean(options.subtitlePipe), done: false };
  states.set(key, state);
  const subtitleStream = child.stdio[3] as NodeJS.ReadableStream | null;
  subtitleStream?.on('data', (chunk: Buffer) => {
    if (state.subtitles) state.text += chunk.toString('utf8');
  });
  subtitleStream?.on('end', () => {
    state.done = true;
  });
  let crc = '';
  const crcStream = child.stdio[4] as NodeJS.ReadableStream | null;
  crcStream?.on('data', (chunk: Buffer) => {
    if (state.start !== null && options.knownStart === undefined) return;
    crc += chunk.toString('utf8');
    const time = firstPacketTime(crc);
    if (time !== null && options.knownStart === undefined) state.start = time;
  });
  const entry = { child, key };
  running.set(key, entry);
  let stderrTail = '';
  child.stderr?.on('data', (chunk: Buffer) => {
    stderrTail = (stderrTail + chunk.toString('utf8')).slice(-2000);
  });
  child.once('close', (code, signal) => {
    if (running.get(key) === entry) running.delete(key);
    // FFmpeg errors can quote the input URL; only the relay address appears there.
    if (code && signal !== 'SIGKILL') logger.warn('FFmpeg exited', { code, tail: stderrTail.slice(-300) });
  });
  return child;
}

export function stopConversion(child: ChildProcess) {
  killGroup(child);
}

/** Pauses (SIGSTOP) or resumes (SIGCONT) a conversion, to keep HLS output near playback. */
export function signalConversion(child: ChildProcess, signal: 'SIGSTOP' | 'SIGCONT') {
  if (child.exitCode !== null || child.signalCode !== null || !child.pid) return;
  try {
    process.kill(-child.pid, signal);
  } catch {
    child.kill(signal);
  }
}

export function runningConversions(): number {
  return running.size;
}

/** Stops every conversion, for shutdown. */
export function stopAllConversions() {
  for (const { child } of running.values()) killGroup(child);
  running.clear();
}
