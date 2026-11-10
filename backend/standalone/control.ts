/**
 * The `flixor` control command: status, start/stop/restart, logs, settings,
 * update and uninstall for an installed Flixor server. Built-ins only.
 *
 * install.sh records what it set up in <data>/service.env:
 *   SERVICE=launchd | systemd-user | systemd-system | none
 *   SERVICE_NAME, LAUNCHD_LABEL, BIN_DIR
 * Installs without that file are detected from the service files on disk.
 */
import { spawn, spawnSync } from 'child_process';
import fs from 'fs';
import http from 'http';
import os from 'os';
import path from 'path';
import { parseEnvFile, setEnvValue } from './envfile';

export const INSTALL_URL = process.env.FLIXOR_INSTALL_URL || 'https://raw.githubusercontent.com/Flixorui/flixor/main/install.sh';
const RELEASES_API = 'https://api.github.com/repos/Flixorui/flixor/releases?per_page=50';
const UPDATE_CHECK_MS = 6 * 60 * 60 * 1000;

export type ServiceKind = 'launchd' | 'systemd-user' | 'systemd-system' | 'none';

export interface Install {
  dataDir: string;
  binDir: string;
  kind: ServiceKind;
  name: string;
  label: string;
}

export interface ServiceState {
  loaded: boolean;
  running: boolean;
  pid?: number;
  /** Starts by itself at login or boot. */
  enabled?: boolean;
}

export interface Status {
  version: string;
  install: Install;
  port: string;
  url: string;
  lanUrl?: string;
  service: ServiceState;
  healthy: boolean;
  database?: string;
  uptime?: string;
  ffmpeg?: string;
  latest?: string | null;
}

const isRoot = () => process.getuid?.() === 0;

export function defaultDataDir(env: NodeJS.ProcessEnv = process.env): string {
  if (env.FLIXOR_HOME) return path.resolve(env.FLIXOR_HOME);
  if (isRoot() && fs.existsSync('/var/lib/flixor')) return '/var/lib/flixor';
  return path.join(os.homedir(), '.flixor');
}

function readEnv(file: string): Record<string, string> {
  try {
    return parseEnvFile(fs.readFileSync(file, 'utf8'));
  } catch {
    return {};
  }
}

export const launchdPlist = (label: string) => path.join(os.homedir(), 'Library', 'LaunchAgents', `${label}.plist`);
const userUnit = (name: string) => path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'systemd', 'user', `${name}.service`);
const systemUnit = (name: string) => `/etc/systemd/system/${name}.service`;

export function readInstall(dataDir: string): Install {
  const recorded = readEnv(path.join(dataDir, 'service.env'));
  const name = recorded.SERVICE_NAME || 'flixor';
  const label = recorded.LAUNCHD_LABEL || (name === 'flixor' ? 'xyz.flixor.server' : `xyz.flixor.${name}`);
  let kind = recorded.SERVICE as ServiceKind | undefined;
  if (!kind) {
    if (process.platform === 'darwin' && fs.existsSync(launchdPlist(label))) kind = 'launchd';
    else if (process.platform === 'linux' && fs.existsSync(userUnit(name))) kind = 'systemd-user';
    else if (process.platform === 'linux' && fs.existsSync(systemUnit(name))) kind = 'systemd-system';
    else kind = 'none';
  }
  return { dataDir, binDir: recorded.BIN_DIR || path.dirname(process.execPath), kind, name, label };
}

function run(cmd: string, args: string[], sudo = false) {
  const [file, argv] = sudo ? ['sudo', [cmd, ...args]] : [cmd, args];
  return spawnSync(file, argv, { encoding: 'utf8' });
}

/** System units need root to change; reading their state does not. */
function systemctl(install: Install, args: string[], change = false) {
  const scoped = install.kind === 'systemd-user' ? ['--user', ...args] : args;
  return run('systemctl', scoped, change && install.kind === 'systemd-system' && !isRoot());
}

const launchdDomain = () => `gui/${process.getuid?.() ?? 0}`;

/** `launchctl print` output: the service's state and pid. */
export function parseLaunchctlPrint(text: string): ServiceState {
  const state = /^\s*state = (\S+)/m.exec(text)?.[1];
  const pid = Number(/^\s*pid = (\d+)/m.exec(text)?.[1]);
  return { loaded: true, running: state === 'running', ...(pid ? { pid } : {}) };
}

/** `systemctl show -p ...` output. */
export function parseSystemctlShow(text: string): ServiceState {
  const props = Object.fromEntries(text.split('\n').filter(Boolean).map((line) => {
    const i = line.indexOf('=');
    return [line.slice(0, i), line.slice(i + 1)];
  }));
  const pid = Number(props.MainPID);
  return {
    loaded: props.LoadState === 'loaded',
    running: props.ActiveState === 'active',
    enabled: props.UnitFileState === 'enabled',
    ...(pid > 0 ? { pid } : {}),
  };
}

export function serviceState(install: Install): ServiceState {
  if (install.kind === 'launchd') {
    const printed = run('launchctl', ['print', `${launchdDomain()}/${install.label}`]);
    const disabled = run('launchctl', ['print-disabled', launchdDomain()]).stdout || '';
    const enabled = !new RegExp(`"${install.label.replace(/\./g, '\\.')}" => (true|disabled)`).test(disabled);
    if (printed.status !== 0) return { loaded: false, running: false, enabled };
    return { ...parseLaunchctlPrint(printed.stdout), enabled };
  }
  if (install.kind === 'systemd-user' || install.kind === 'systemd-system') {
    const shown = systemctl(install, ['show', `${install.name}.service`, '-p', 'LoadState', '-p', 'ActiveState', '-p', 'MainPID', '-p', 'UnitFileState']);
    return parseSystemctlShow(shown.stdout || '');
  }
  return { loaded: false, running: false };
}

function check(result: ReturnType<typeof run>, what: string) {
  if (result.status !== 0) throw new Error(`${what} failed: ${(result.stderr || result.stdout || '').trim() || `exit ${result.status}`}`);
}

function noService(): never {
  throw new Error('No background service is set up for this install. Run the server with: flixor run');
}

/** Starts the service and makes it start at login or boot again. */
export function startService(install: Install): void {
  if (install.kind === 'launchd') {
    const target = `${launchdDomain()}/${install.label}`;
    run('launchctl', ['enable', target]);
    if (serviceState(install).loaded) check(run('launchctl', ['kickstart', target]), 'launchctl kickstart');
    else check(run('launchctl', ['bootstrap', launchdDomain(), launchdPlist(install.label)]), 'launchctl bootstrap');
  } else if (install.kind === 'systemd-user' || install.kind === 'systemd-system') {
    check(systemctl(install, ['enable', '--now', `${install.name}.service`], true), 'systemctl enable --now');
  } else {
    noService();
  }
}

/** Stops the service and keeps it off, including after a reboot, until started again. */
export function stopService(install: Install): void {
  if (install.kind === 'launchd') {
    const target = `${launchdDomain()}/${install.label}`;
    run('launchctl', ['disable', target]);
    if (serviceState(install).loaded) check(run('launchctl', ['bootout', target]), 'launchctl bootout');
  } else if (install.kind === 'systemd-user' || install.kind === 'systemd-system') {
    check(systemctl(install, ['disable', '--now', `${install.name}.service`], true), 'systemctl disable --now');
  } else {
    noService();
  }
}

export function restartService(install: Install): void {
  if (install.kind === 'launchd') {
    if (!serviceState(install).loaded) return startService(install);
    check(run('launchctl', ['kickstart', '-k', `${launchdDomain()}/${install.label}`]), 'launchctl kickstart -k');
  } else if (install.kind === 'systemd-user' || install.kind === 'systemd-system') {
    check(systemctl(install, ['restart', `${install.name}.service`], true), 'systemctl restart');
  } else {
    noService();
  }
}

/** `ps -o etime=` ([[dd-]hh:]mm:ss) as "3d 4h", "2h 5m" or "45s". */
export function formatElapsed(etime: string): string | undefined {
  const match = /^\s*(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)\s*$/.exec(etime);
  if (!match) return undefined;
  const [d, h, m, s] = [match[1], match[2], match[3], match[4]].map((v) => Number(v || 0));
  if (d) return `${d}d ${h}h`;
  if (h) return `${h}h ${m}m`;
  if (m) return `${m}m ${s}s`;
  return `${s}s`;
}

function uptime(pid?: number): string | undefined {
  if (!pid) return undefined;
  const result = run('ps', ['-o', 'etime=', '-p', String(pid)]);
  return result.status === 0 ? formatElapsed(result.stdout) : undefined;
}

export function settings(install: Install): Record<string, string> {
  return readEnv(path.join(install.dataDir, 'flixor.env'));
}

export function serverPort(install: Install): string {
  return settings(install).PORT || '3001';
}

function lanAddress(): string | undefined {
  for (const list of Object.values(os.networkInterfaces())) {
    for (const addr of list || []) {
      if (addr.family === 'IPv4' && !addr.internal) return addr.address;
    }
  }
  return undefined;
}

export function health(port: string, timeoutMs = 1500): Promise<{ healthy: boolean; database?: string }> {
  return new Promise((resolve) => {
    const req = http.get({ host: '127.0.0.1', port: Number(port), path: '/health', timeout: timeoutMs }, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          resolve({ healthy: parsed.status === 'healthy', database: parsed.database });
        } catch {
          resolve({ healthy: false });
        }
      });
    });
    req.on('timeout', () => req.destroy());
    req.on('error', () => resolve({ healthy: false }));
  });
}

/** Numeric x.y.z comparison; anything after the patch number is ignored. */
export function compareVersions(a: string, b: string): number {
  const parse = (v: string) => (/^(\d+)\.(\d+)\.(\d+)/.exec(v) || [0, 0, 0, 0]).slice(1).map(Number);
  const [x, y] = [parse(a), parse(b)];
  for (let i = 0; i < 3; i += 1) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1;
  return 0;
}

/** Newest release with a server build for this machine, checked at most every 6 hours. */
export async function latestVersion(install: Install, force = false): Promise<string | null> {
  const cacheFile = path.join(install.dataDir, 'cache', 'update-check.json');
  try {
    const cached = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
    if (!force && Date.now() - cached.checkedAt < UPDATE_CHECK_MS) return cached.version ?? null;
  } catch {
    // No cache yet.
  }
  try {
    const asset = `flixor-server-${process.platform}-${process.arch}.tar.gz`;
    const res = await fetch(RELEASES_API, { headers: { 'User-Agent': 'flixor-server', Accept: 'application/vnd.github+json' }, signal: AbortSignal.timeout(4000) });
    if (!res.ok) return null;
    const releases = (await res.json()) as Array<{ tag_name: string; draft: boolean; assets: Array<{ name: string }> }>;
    const release = releases.find((r) => !r.draft && r.assets.some((a) => a.name === asset));
    const version = release ? release.tag_name.replace(/^server-v/, '').replace(/^v/, '') : null;
    fs.mkdirSync(path.dirname(cacheFile), { recursive: true });
    fs.writeFileSync(cacheFile, JSON.stringify({ checkedAt: Date.now(), version }));
    return version;
  } catch {
    return null;
  }
}

export async function getStatus(install: Install, version: string, latest?: string | null): Promise<Status> {
  const port = serverPort(install);
  const service = serviceState(install);
  const { healthy, database } = await health(port);
  const lan = lanAddress();
  return {
    version,
    install,
    port,
    url: `http://localhost:${port}`,
    ...(lan ? { lanUrl: `http://${lan}:${port}` } : {}),
    service,
    healthy,
    ...(database ? { database } : {}),
    ...(service.pid ? { uptime: uptime(service.pid) } : {}),
    ffmpeg: settings(install).FFMPEG_PATH,
    latest,
  };
}

export function serviceDescription(install: Install): string {
  switch (install.kind) {
    case 'launchd': return `launchd agent ${install.label}`;
    case 'systemd-user': return `systemd user service ${install.name}`;
    case 'systemd-system': return `systemd service ${install.name}`;
    default: return 'none (run it with: flixor run)';
  }
}

export function stateLabel(status: Status): 'running' | 'starting' | 'stopped' | 'not responding' {
  if (status.healthy) return 'running';
  // launchd reports a pid a moment before it calls the service running.
  if (status.service.running || status.service.pid) return status.uptime && !/^\d+s$/.test(status.uptime) ? 'not responding' : 'starting';
  return 'stopped';
}

const home = (p: string) => (p.startsWith(os.homedir()) ? `~${p.slice(os.homedir().length)}` : p);

export function formatStatus(status: Status): string {
  const state = stateLabel(status);
  const lines = [
    `Flixor server ${status.version}`,
    `  State:    ${state}${status.service.pid ? ` (pid ${status.service.pid}${status.uptime ? `, up ${status.uptime}` : ''})` : ''}`,
    `  Open:     ${status.url}`,
    ...(status.lanUrl ? [`  Network:  ${status.lanUrl}`] : []),
    `  Service:  ${serviceDescription(status.install)}${status.install.kind !== 'none' ? (status.service.enabled === false ? ', off until started' : ', starts automatically') : ''}`,
    `  Data:     ${home(status.install.dataDir)}`,
    `  FFmpeg:   ${status.ffmpeg || 'not set (addon conversions need it)'}`,
  ];
  if (status.latest && compareVersions(status.latest, status.version) > 0) lines.push(`  Update:   ${status.latest} is available (flixor update)`);
  return `${lines.join('\n')}\n`;
}

/** The last `count` lines of a file, reading only its end. */
export function tailLines(file: string, count: number): string[] {
  try {
    const fd = fs.openSync(file, 'r');
    try {
      const size = fs.fstatSync(fd).size;
      const length = Math.min(size, 256 * 1024);
      const buffer = Buffer.alloc(length);
      fs.readSync(fd, buffer, 0, length, size - length);
      const lines = buffer.toString('utf8').split('\n');
      if (lines[lines.length - 1] === '') lines.pop();
      return lines.slice(-count);
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    return [];
  }
}

export const serviceLog = (install: Install) => path.join(install.dataDir, 'logs', 'service.log');

/** Runs install.sh with this install's folders, e.g. to update or uninstall. Returns its exit code. */
export function runInstaller(install: Install, extra: string[]): number {
  const args = ['--bin-dir', install.binDir, '--data-dir', install.dataDir, ...extra];
  const script = 'if command -v curl >/dev/null 2>&1; then curl -fsSL "$0"; else wget -qO- "$0"; fi | sh -s -- "$@"';
  const vars = [
    ...(install.name !== 'flixor' ? [`FLIXOR_SERVICE_NAME=${install.name}`] : []),
    ...(process.env.FLIXOR_RELEASE_BASE ? [`FLIXOR_RELEASE_BASE=${process.env.FLIXOR_RELEASE_BASE}`] : []),
  ];
  const command = ['env', ...vars, 'sh', '-c', script, INSTALL_URL, ...args];
  const asRoot = install.kind === 'systemd-system' && !isRoot();
  const result = spawnSync(asRoot ? 'sudo' : command[0], asRoot ? command : command.slice(1), { stdio: 'inherit' });
  return result.status ?? 1;
}

export function openInBrowser(url: string): void {
  const opener = process.platform === 'darwin' ? 'open' : 'xdg-open';
  const child = spawn(opener, [url], { stdio: 'ignore', detached: true });
  child.on('error', () => process.stdout.write(`Open ${url} in your browser.\n`));
  child.unref();
}

/** Waits for /health after a start or restart. */
export async function waitForHealth(port: string, timeoutMs = 20000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if ((await health(port, 1000)).healthy) return true;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return false;
}

export function writeSetting(install: Install, key: string, value: string | null): void {
  const file = path.join(install.dataDir, 'flixor.env');
  const current = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  fs.mkdirSync(install.dataDir, { recursive: true });
  fs.writeFileSync(file, setEnvValue(current, key, value));
}

export const COMMANDS_HELP = `Usage: flixor [command]

Controls the Flixor server installed on this machine. With no command, opens the
dashboard (in a terminal) or prints the status.

Commands:
  status               Show whether the server is running, its address and version
  start                Start the server (and start it at login/boot again)
  stop                 Stop the server; it stays off until you start it again
  restart              Restart the server
  logs [-f] [-n N]     Show the last N log lines (default 50); -f keeps following
  open                 Open Flixor in your browser
  config               Show the settings in flixor.env
  config set KEY VAL   Change a setting (restarts a running server)
  config unset KEY     Remove a setting (restarts a running server)
  port N               Serve on port N (restarts a running server)
  update               Install the newest release
  uninstall [--purge]  Remove the server and its service (--purge also deletes data)
  run [options]        Run the server in this terminal (see flixor run --help)
  version              Print the version
`;

async function applySetting(install: Install, key: string, value: string | null): Promise<number> {
  writeSetting(install, key, value);
  process.stdout.write(value === null ? `Removed ${key}.\n` : `Set ${key}=${value}.\n`);
  if (serviceState(install).running) {
    restartService(install);
    const up = await waitForHealth(serverPort(install));
    process.stdout.write(up ? `Restarted: ${`http://localhost:${serverPort(install)}`}\n` : 'Restarted, but it is not answering yet. See: flixor logs\n');
  }
  return 0;
}

function followFile(file: string): Promise<number> {
  return new Promise(() => {
    let position = fs.existsSync(file) ? fs.statSync(file).size : 0;
    fs.watchFile(file, { interval: 500 }, (curr) => {
      if (curr.size < position) position = 0; // rotated or truncated
      if (curr.size === position) return;
      const fd = fs.openSync(file, 'r');
      const buffer = Buffer.alloc(curr.size - position);
      fs.readSync(fd, buffer, 0, buffer.length, position);
      fs.closeSync(fd);
      position = curr.size;
      process.stdout.write(buffer);
    });
  });
}

/** Runs one control command; returns the process exit code. */
export async function runCommand(command: string, args: string[], version: string): Promise<number> {
  const install = readInstall(defaultDataDir());
  switch (command) {
    case 'status': {
      const status = await getStatus(install, version, await latestVersion(install));
      process.stdout.write(formatStatus(status));
      return status.healthy ? 0 : 3;
    }
    case 'start':
    case 'restart': {
      (command === 'start' ? startService : restartService)(install);
      process.stdout.write(command === 'start' ? 'Starting… ' : 'Restarting… ');
      const up = await waitForHealth(serverPort(install));
      process.stdout.write(up ? `running at http://localhost:${serverPort(install)}\n` : 'not answering yet. See: flixor logs\n');
      return up ? 0 : 1;
    }
    case 'stop':
      stopService(install);
      process.stdout.write('Stopped. It stays off until you run: flixor start\n');
      return 0;
    case 'logs': {
      const follow = args.includes('-f') || args.includes('--follow');
      const n = Number(args[args.indexOf('-n') + 1]) || 50;
      const file = serviceLog(install);
      if (!fs.existsSync(file) && install.kind.startsWith('systemd')) {
        const scope = install.kind === 'systemd-user' ? ['--user'] : [];
        return spawnSync('journalctl', [...scope, '-u', install.name, '-n', String(n), ...(follow ? ['-f'] : [])], { stdio: 'inherit' }).status ?? 1;
      }
      const lines = tailLines(file, n);
      process.stdout.write(lines.length ? `${lines.join('\n')}\n` : `No log yet (${file}).\n`);
      return follow ? followFile(file) : 0;
    }
    case 'open':
      openInBrowser(`http://localhost:${serverPort(install)}`);
      return 0;
    case 'config': {
      const [action, key, ...rest] = args;
      if (!action) {
        const file = path.join(install.dataDir, 'flixor.env');
        const text = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
        process.stdout.write(`${file}\n${text || '(no settings; defaults are used)\n'}`);
        return 0;
      }
      if (action === 'set' && key && rest.length) return applySetting(install, key, rest.join(' '));
      if (action === 'unset' && key) return applySetting(install, key, null);
      throw new Error('usage: flixor config [set KEY VALUE | unset KEY]');
    }
    case 'port': {
      if (!/^\d{1,5}$/.test(args[0] || '')) throw new Error('usage: flixor port <number>');
      return applySetting(install, 'PORT', args[0]);
    }
    case 'update': {
      const latest = await latestVersion(install, true);
      if (latest && compareVersions(latest, version) <= 0 && !args.includes('--force')) {
        process.stdout.write(`Already up to date (${version}). Use flixor update --force to reinstall.\n`);
        return 0;
      }
      return runInstaller(install, []);
    }
    case 'uninstall':
      return runInstaller(install, ['--uninstall', ...(args.includes('--purge') ? ['--purge'] : [])]);
    case 'version':
      process.stdout.write(`flixor-server ${version} (${process.platform}-${process.arch}, node ${process.versions.node})\n`);
      return 0;
    case 'help':
      process.stdout.write(COMMANDS_HELP);
      return 0;
    default:
      throw new Error(`unknown command: ${command} (see flixor help)`);
  }
}
