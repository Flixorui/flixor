/** The `flixor` control command and dashboard: parsing, settings and rendering. Run: npm test. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import {
  compareVersions, formatElapsed, formatStatus, parseLaunchctlPrint, parseSystemctlShow, readInstall, stateLabel,
  tailLines, type Status,
} from './control';
import { parseEnvFile, setEnvValue } from './envfile';
import { cleanLogLine, render, visibleLength } from './tui';

const temp = (label: string) => fs.mkdtempSync(path.join(os.tmpdir(), `flixor-${label}-`));
const plain = (text: string) => text.replace(/\x1b\[[0-9;]*m/g, '');

test('settings edits keep other lines and comments', () => {
  const text = '# Flixor\nPORT=3001\nFFMPEG_PATH=/usr/bin/ffmpeg\n';
  assert.equal(setEnvValue(text, 'PORT', '3100'), '# Flixor\nPORT=3100\nFFMPEG_PATH=/usr/bin/ffmpeg\n');
  assert.equal(setEnvValue(text, 'LOG_LEVEL', 'debug'), `${text}LOG_LEVEL=debug\n`);
  assert.equal(setEnvValue(text, 'PORT', null), '# Flixor\nFFMPEG_PATH=/usr/bin/ffmpeg\n');
  assert.equal(setEnvValue('PORT=1\nPORT=2\n', 'PORT', '3'), 'PORT=3\n');
  assert.equal(setEnvValue('', 'PORT', '3001'), 'PORT=3001\n');
  assert.equal(setEnvValue('PORT=1\n', 'PORT', null), '');
  // Values with spaces are quoted and read back intact.
  assert.equal(parseEnvFile(setEnvValue('', 'TMDB_DEFAULT_KEY', 'a b #c')).TMDB_DEFAULT_KEY, 'a b #c');
  assert.throws(() => setEnvValue('', 'BAD KEY', 'x'), /not a valid setting name/);
});

test('launchctl and systemctl output', () => {
  assert.deepEqual(parseLaunchctlPrint('gui/501/xyz.flixor.server = {\n\tactive count = 1\n\tstate = running\n\tpid = 4242\n}'), { loaded: true, running: true, pid: 4242 });
  assert.deepEqual(parseLaunchctlPrint('gui/501/xyz.flixor.server = {\n\tstate = not running\n}'), { loaded: true, running: false });
  assert.deepEqual(parseSystemctlShow('LoadState=loaded\nActiveState=active\nMainPID=99\nUnitFileState=enabled\n'), { loaded: true, running: true, enabled: true, pid: 99 });
  assert.deepEqual(parseSystemctlShow('LoadState=loaded\nActiveState=inactive\nMainPID=0\nUnitFileState=disabled\n'), { loaded: true, running: false, enabled: false });
  assert.deepEqual(parseSystemctlShow('LoadState=not-found\nActiveState=inactive\nMainPID=0\nUnitFileState=\n'), { loaded: false, running: false, enabled: false });
});

test('uptime and versions', () => {
  assert.equal(formatElapsed('   00:42'), '42s');
  assert.equal(formatElapsed('05:07'), '5m 7s');
  assert.equal(formatElapsed('02:05:07'), '2h 5m');
  assert.equal(formatElapsed('3-04:05:06'), '3d 4h');
  assert.equal(formatElapsed('nonsense'), undefined);
  assert.equal(compareVersions('1.1.0', '1.0.9'), 1);
  assert.equal(compareVersions('1.0.0', '1.0.0-dev.abc'), 0);
  assert.equal(compareVersions('0.9.0', '1.0.0'), -1);
});

test('the install is read from service.env', () => {
  const data = temp('install');
  fs.writeFileSync(path.join(data, 'service.env'), 'SERVICE=none\n');
  assert.equal(readInstall(data).kind, 'none');
  fs.writeFileSync(path.join(data, 'service.env'), 'SERVICE=systemd-user\nSERVICE_NAME=flixortest\nBIN_DIR=/opt/flixor/bin\n');
  assert.deepEqual(readInstall(data), { dataDir: data, binDir: '/opt/flixor/bin', kind: 'systemd-user', name: 'flixortest', label: 'xyz.flixor.flixortest' });
});

test('log tail reads only the last lines', () => {
  const file = path.join(temp('log'), 'service.log');
  fs.writeFileSync(file, Array.from({ length: 500 }, (_, i) => `line ${i}`).join('\n') + '\n');
  assert.deepEqual(tailLines(file, 3), ['line 497', 'line 498', 'line 499']);
  assert.deepEqual(tailLines(path.join(path.dirname(file), 'missing.log'), 3), []);
});

const status = (overrides: Partial<Status> = {}): Status => ({
  version: '1.1.0',
  install: { dataDir: '/home/me/.flixor', binDir: '/home/me/.local/bin', kind: 'systemd-user', name: 'flixor', label: 'xyz.flixor.server' },
  port: '3001',
  url: 'http://localhost:3001',
  lanUrl: 'http://10.0.0.5:3001',
  service: { loaded: true, running: true, pid: 77, enabled: true },
  healthy: true,
  uptime: '2h 5m',
  ffmpeg: '/usr/bin/ffmpeg',
  nameUrl: 'http://flixor.local',
  latest: '1.1.0',
  ...overrides,
});

test('state label', () => {
  assert.equal(stateLabel(status()), 'running');
  assert.equal(stateLabel(status({ healthy: false, uptime: '4s' })), 'starting');
  assert.equal(stateLabel(status({ healthy: false, uptime: '3m 2s' })), 'not responding');
  assert.equal(stateLabel(status({ healthy: false, service: { loaded: false, running: false } })), 'stopped');
  assert.equal(stateLabel(status({ healthy: false, uptime: '0s', service: { loaded: true, running: false, pid: 5 } })), 'starting');
});

test('status text', () => {
  const text = formatStatus(status());
  assert.match(text, /State:\s+running \(pid 77, up 2h 5m\)/);
  assert.match(text, /Network:\s+http:\/\/10\.0\.0\.5:3001/);
  assert.match(text, /Name:\s+http:\/\/flixor\.local\n/);
  assert.match(text, /systemd user service flixor, starts automatically/);
  assert.doesNotMatch(text, /Update:/);
  assert.match(formatStatus(status({ latest: '1.2.0' })), /Update:\s+1\.2\.0 is available/);
  assert.match(formatStatus(status({ service: { loaded: false, running: false, enabled: false }, healthy: false })), /off until started/);
});

test('dashboard fits the terminal and offers the right action', () => {
  const logs = Array.from({ length: 50 }, (_, i) => `\x1b[32minfo\x1b[39m log line ${i} ${'x'.repeat(200)}`);
  const screen = render(status(), logs, { mode: 'main' }, 80, 24);
  const lines = screen.split('\n');
  assert.ok(lines.length <= 24, `${lines.length} lines`);
  assert.ok(lines.every((line) => visibleLength(line) <= 80), 'every line fits 80 columns');
  const text = plain(screen);
  assert.match(text, /FLIXOR server\s+1\.1\.0/);
  assert.match(text, /Running\s+pid 77 · up 2h 5m/);
  assert.match(text, /s stop/);
  assert.match(text, /Name\s+http:\/\/flixor\.local/);
  assert.match(text, /log line 49/);
  assert.match(text, /up to date/);

  const stopped = plain(render(status({ healthy: false, service: { loaded: false, running: false } }), [], { mode: 'main' }, 80, 24));
  assert.match(stopped, /Stopped/);
  assert.match(stopped, /s start/);
  assert.match(stopped, /\(no log yet\)/);

  assert.match(plain(render(status({ latest: '2.0.0' }), [], { mode: 'main' }, 80, 24)), /2\.0\.0 available, press u/);
  assert.match(plain(render(status(), [], { mode: 'port', input: '31' }, 80, 24)), /New port: 31/);
  const logView = plain(render(status(), logs, { mode: 'logs' }, 80, 24)).split('\n');
  assert.ok(logView.length <= 24);
  assert.match(logView.join('\n'), /q \/ esc back/);
});

test('dashboard log lines drop colors and the logger metadata', () => {
  assert.equal(cleanLogLine('00:37:42 [\x1b[32minfo\x1b[39m] Server running {"component":"server","service":"plex-media-backend"}'), '00:37:42 [info] Server running');
  assert.equal(cleanLogLine('✅ Database initialized'), '✅ Database initialized');
});
