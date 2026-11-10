/**
 * Entry point of the standalone executable (`flixor-server`).
 *
 * The executable carries the server as a payload (see payload.ts). On the first
 * run of each build this unpacks it into the data folder, then loads the server
 * from there with a normal module loader, so the native add-ons (sqlite3, sharp)
 * load exactly as they do under `node dist/server.js`.
 *
 * Settings, lowest to highest priority: built-in defaults, <data>/flixor.env,
 * the environment, command-line flags.
 *
 * Data folder (FLIXOR_HOME, default ~/.flixor):
 *   flixor.env               optional overrides (KEY=value lines)
 *   config/                  database (config/db/app.sqlite) and session secret
 *   logs/  cache/            server logs and image cache
 *   runtime/<build>/         the unpacked server; replaced on update
 */
import crypto from 'crypto';
import fs from 'fs';
import { createRequire } from 'module';
import os from 'os';
import path from 'path';
import { unpack } from './payload';

export interface Manifest {
  version: string;
  /** First 12 hex characters of the payload's SHA-256: names the runtime folder. */
  hash: string;
}

export interface Options {
  help: boolean;
  version: boolean;
  port?: string;
  host?: string;
  dataDir?: string;
}

export const HELP = `Usage: flixor-server [options]

Runs the Flixor server: the web app and its backend, on one port.

Options:
  --port <n>        Port to listen on (default 3001, or PORT)
  --host <addr>     Address to listen on (default 0.0.0.0, or HOST)
  --data-dir <dir>  Data folder (default ~/.flixor, or FLIXOR_HOME)
  --version         Print the version and exit
  --help            Print this help and exit

Settings can also go in <data folder>/flixor.env as KEY=value lines.
`;

export function parseArgs(argv: string[]): Options {
  const options: Options = { help: false, version: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const [flag, inline] = arg.startsWith('--') && arg.includes('=') ? [arg.slice(0, arg.indexOf('=')), arg.slice(arg.indexOf('=') + 1)] : [arg, undefined];
    const value = () => {
      const next = inline ?? argv[++i];
      if (next === undefined || next === '') throw new Error(`${flag} needs a value`);
      return next;
    };
    switch (flag) {
      case '-h': case '--help': options.help = true; break;
      case '-v': case '--version': options.version = true; break;
      case '--port': options.port = value(); break;
      case '--host': options.host = value(); break;
      case '--data-dir': options.dataDir = value(); break;
      default: throw new Error(`unknown option: ${arg}`);
    }
  }
  if (options.port !== undefined && !/^\d{1,5}$/.test(options.port)) throw new Error(`--port must be a number: ${options.port}`);
  return options;
}

/** KEY=value lines; blank lines and # comments ignored; optional single or double quotes. */
export function parseEnvFile(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split(/\r?\n/)) {
    const match = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!match || line.trimStart().startsWith('#')) continue;
    let value = match[2];
    const quoted = /^(['"])(.*)\1$/.exec(value);
    if (quoted) value = quoted[2];
    else value = value.replace(/\s+#.*$/, '');
    out[match[1]] = value;
  }
  return out;
}

/** The session secret kept in the data folder, created on first use. */
export function sessionSecret(configDir: string): string {
  const file = path.join(configDir, 'session-secret');
  try {
    const existing = fs.readFileSync(file, 'utf8').trim();
    if (existing.length >= 32) return existing;
  } catch {
    // First run.
  }
  const secret = crypto.randomBytes(48).toString('base64url');
  fs.mkdirSync(configDir, { recursive: true });
  fs.writeFileSync(file, `${secret}\n`, { mode: 0o600 });
  return secret;
}

/** Sets the server's settings in `env` for a data folder, keeping anything already set. */
export function configure(env: NodeJS.ProcessEnv, options: Options, dataDir: string, webDir: string): void {
  const envFile = path.join(dataDir, 'flixor.env');
  if (fs.existsSync(envFile)) {
    for (const [key, value] of Object.entries(parseEnvFile(fs.readFileSync(envFile, 'utf8')))) {
      if (env[key] === undefined) env[key] = value;
    }
  }
  if (options.port) env.PORT = options.port;
  if (options.host) env.HOST = options.host;

  const configDir = env.CONFIG_DIRECTORY ||= path.join(dataDir, 'config');
  env.LOG_DIRECTORY ||= path.join(dataDir, 'logs');
  env.IMAGE_CACHE_DIR ||= path.join(dataDir, 'cache', 'images');
  env.NODE_ENV ||= 'production';
  env.PORT ||= '3001';
  env.HOST ||= '0.0.0.0';
  env.FRONTEND_URL ||= `http://localhost:${env.PORT}`;
  env.FLIXOR_WEB_DIR ||= webDir;
  env.SESSION_SECRET ||= sessionSecret(configDir);

  // Services (launchd, systemd) start with a bare PATH; FFmpeg usually lives in one of these.
  const extra = [path.join(dataDir, 'bin'), '/opt/homebrew/bin', '/usr/local/bin'];
  const current = (env.PATH || '/usr/bin:/bin').split(path.delimiter);
  env.PATH = [...current, ...extra.filter((dir) => !current.includes(dir))].join(path.delimiter);
}

/**
 * The unpacked server for this build, unpacking it first if needed. Unpacks into a
 * temporary folder and renames it into place, so an interrupted run never leaves
 * a half-written runtime. Older builds' runtimes are removed.
 */
export function ensureRuntime(dataDir: string, manifest: Manifest, payload: () => Uint8Array): string {
  const runtimes = path.join(dataDir, 'runtime');
  const name = `${manifest.version}-${manifest.hash}`;
  const dir = path.join(runtimes, name);
  const marker = path.join(dir, '.complete');

  if (!fs.existsSync(marker)) {
    fs.mkdirSync(runtimes, { recursive: true });
    const temp = path.join(runtimes, `.unpack-${process.pid}-${crypto.randomBytes(4).toString('hex')}`);
    try {
      unpack(payload(), temp);
      fs.writeFileSync(path.join(temp, '.complete'), `${new Date().toISOString()}\n`);
      fs.rmSync(dir, { recursive: true, force: true });
      try {
        fs.renameSync(temp, dir);
      } catch (error) {
        // Another process finished first: use its copy.
        if (!fs.existsSync(marker)) throw error;
      }
    } finally {
      fs.rmSync(temp, { recursive: true, force: true });
    }
  }

  for (const entry of fs.readdirSync(runtimes)) {
    if (entry !== name && !entry.startsWith('.unpack-')) {
      fs.rmSync(path.join(runtimes, entry), { recursive: true, force: true });
    }
  }
  return dir;
}

/** Manifest and payload: embedded assets in the executable, or files beside this script when run by node for testing. */
function assets(): { manifest: Manifest; payload: () => Uint8Array } {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const sea = require('node:sea') as typeof import('node:sea');
  if (sea.isSea()) {
    return {
      manifest: JSON.parse(sea.getAsset('manifest', 'utf8')),
      payload: () => new Uint8Array(sea.getRawAsset('payload') as ArrayBuffer),
    };
  }
  const dir = process.env.FLIXOR_PAYLOAD_DIR || __dirname;
  return {
    manifest: JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8')),
    payload: () => fs.readFileSync(path.join(dir, 'payload.bin')),
  };
}

export function main(argv = process.argv.slice(2)): void {
  let options: Options;
  try {
    options = parseArgs(argv);
  } catch (error) {
    process.stderr.write(`flixor-server: ${(error as Error).message}\n\n${HELP}`);
    process.exit(2);
  }
  if (options.help) {
    process.stdout.write(HELP);
    return;
  }
  const { manifest, payload } = assets();
  if (options.version) {
    process.stdout.write(`flixor-server ${manifest.version} (${process.platform}-${process.arch}, node ${process.versions.node})\n`);
    return;
  }

  const dataDir = path.resolve(options.dataDir || process.env.FLIXOR_HOME || path.join(os.homedir(), '.flixor'));
  fs.mkdirSync(dataDir, { recursive: true });
  const runtime = ensureRuntime(dataDir, manifest, payload);
  configure(process.env, options, dataDir, path.join(runtime, 'web'));
  process.env.FLIXOR_VERSION = manifest.version;
  // The image proxy caches under the working folder.
  process.chdir(dataDir);

  const serverFile = path.join(runtime, 'app', 'server.js');
  createRequire(serverFile)(serverFile);
}

if (require.main === module || require('node:sea').isSea()) main();
