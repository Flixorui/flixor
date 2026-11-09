/**
 * HLS delivery of a conversion, for Safari. FFmpeg writes fMP4 segments and an EVENT
 * playlist into a temporary folder; the player fetches them through the API.
 *
 * FFmpeg is paused (SIGSTOP) once it is well ahead of the last segment the player
 * asked for and resumed as playback catches up, so it never downloads the whole film.
 * A session ends when its player starts another conversion, goes quiet, or the
 * conversion exits; its folder is deleted then.
 */
import { ChildProcess } from 'child_process';
import crypto from 'crypto';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { signalConversion, stopConversion } from './ffmpeg';

interface Session {
  owner: string;
  dir: string;
  child: ChildProcess;
  lastAccess: number;
  /** Highest segment number the player has asked for. */
  requested: number;
  paused: boolean;
  timer: NodeJS.Timeout;
  release: () => void;
}

const ROOT = path.join(os.tmpdir(), 'flixor-hls');
const sessions = new Map<string, Session>();

/** Pause when this many segments (about 2 s each) are ready beyond the player. */
const AHEAD_PAUSE = 15;
const AHEAD_RESUME = 8;
const IDLE_MS = 90_000;
const WAIT_MS = 25_000;

export const HLS_FILE = /^(?:index\.m3u8|init\.mp4|seg\d{5}\.m4s)$/;
export const HLS_SESSION = /^[\w-]{1,80}$/;

export function createHlsDir(): string {
  fs.mkdirSync(ROOT, { recursive: true });
  return fs.mkdtempSync(path.join(ROOT, `${crypto.randomBytes(4).toString('hex')}-`));
}

function sessionKey(owner: string, id: string) {
  return `${owner}:${id}`;
}

/** Highest segment number written so far (temp files are renamed when complete). */
function producedSegments(dir: string): number {
  let highest = -1;
  try {
    for (const name of fs.readdirSync(dir)) {
      const match = /^seg(\d{5})\.m4s$/.exec(name);
      if (match) highest = Math.max(highest, Number(match[1]));
    }
  } catch {
    // Folder already removed.
  }
  return highest;
}

function endSession(key: string) {
  const session = sessions.get(key);
  if (!session) return;
  sessions.delete(key);
  clearInterval(session.timer);
  if (session.paused) signalConversion(session.child, 'SIGCONT');
  stopConversion(session.child);
  session.release();
  fs.rm(session.dir, { recursive: true, force: true }, () => {});
}

export function getHlsSession(owner: string, id: string): Session | undefined {
  return sessions.get(sessionKey(owner, id));
}

/** Tracks a started conversion as an HLS session. Ends any other session of the same owner and player. */
export function addHlsSession(owner: string, id: string, playerPrefix: string, dir: string, child: ChildProcess, release: () => void) {
  for (const [key, session] of sessions) {
    if (session.owner === owner && key.startsWith(`${owner}:${playerPrefix}-`)) endSession(key);
  }
  const key = sessionKey(owner, id);
  const session: Session = {
    owner, dir, child, lastAccess: Date.now(), requested: 0, paused: false, release,
    timer: setInterval(() => {
      if (Date.now() - session.lastAccess > IDLE_MS) return endSession(key);
      const ahead = producedSegments(dir) - session.requested;
      if (!session.paused && ahead > AHEAD_PAUSE) {
        session.paused = true;
        signalConversion(child, 'SIGSTOP');
      } else if (session.paused && ahead < AHEAD_RESUME) {
        session.paused = false;
        signalConversion(child, 'SIGCONT');
      }
    }, 1000),
  };
  sessions.set(key, session);
  child.once('close', () => {
    // Keep finished output a while for the player to read, then clean up.
    setTimeout(() => {
      if (sessions.get(key) === session) endSession(key);
    }, IDLE_MS);
  });
}

function running(child: ChildProcess) {
  return child.exitCode === null && child.signalCode === null;
}

/**
 * Path of a session file once it exists. The playlist waits for its first segment,
 * and a segment the player asks for early waits until FFmpeg writes it.
 */
export async function hlsFile(owner: string, id: string, file: string): Promise<string | null> {
  const session = sessions.get(sessionKey(owner, id));
  if (!session || !HLS_FILE.test(file)) return null;
  session.lastAccess = Date.now();
  const segment = /^seg(\d{5})\.m4s$/.exec(file);
  if (segment) {
    session.requested = Math.max(session.requested, Number(segment[1]));
    // Asking ahead of what is written: let FFmpeg run.
    if (session.paused && producedSegments(session.dir) - session.requested < AHEAD_RESUME) {
      session.paused = false;
      signalConversion(session.child, 'SIGCONT');
    }
  }
  const full = path.join(session.dir, file);
  const ready = () => fs.existsSync(full) && (file !== 'index.m3u8' || producedSegments(session.dir) >= 0);
  const deadline = Date.now() + WAIT_MS;
  while (!ready()) {
    if (!running(session.child) || Date.now() > deadline) return ready() ? full : null;
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  return full;
}

/** Ends every session, for shutdown. */
export function stopAllHlsSessions() {
  for (const key of [...sessions.keys()]) endSession(key);
}
