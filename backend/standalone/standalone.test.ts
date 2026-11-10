/** The standalone executable's payload format and bootstrap. Run: npm test (in backend). */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { test } from 'node:test';
import { configure, ensureRuntime, parseArgs, parseEnvFile, sessionSecret } from './bootstrap';
import { pack, unpack } from './payload';

const temp = (label: string) => fs.mkdtempSync(path.join(os.tmpdir(), `flixor-${label}-`));

test('payload round-trips files, modes and symlinks', () => {
  const src = temp('src');
  fs.mkdirSync(path.join(src, 'app/lib'), { recursive: true });
  fs.writeFileSync(path.join(src, 'app/server.js'), 'module.exports = 1;');
  fs.writeFileSync(path.join(src, 'app/lib/addon.node'), Buffer.from([0, 1, 2, 255]));
  fs.writeFileSync(path.join(src, 'app/run.sh'), '#!/bin/sh\n', { mode: 0o755 });
  fs.symlinkSync('lib/addon.node', path.join(src, 'app/addon-link.node'));

  const dest = path.join(temp('dest'), 'out');
  assert.equal(unpack(pack(src), dest), 4);
  assert.equal(fs.readFileSync(path.join(dest, 'app/server.js'), 'utf8'), 'module.exports = 1;');
  assert.deepEqual([...fs.readFileSync(path.join(dest, 'app/lib/addon.node'))], [0, 1, 2, 255]);
  assert.equal(fs.statSync(path.join(dest, 'app/run.sh')).mode & 0o111, 0o111);
  assert.equal(fs.readlinkSync(path.join(dest, 'app/addon-link.node')), 'lib/addon.node');
});

test('payload refuses paths and links that leave its folder', () => {
  const evil = (rel: string, kind = 0, data = Buffer.from('x')) => {
    const name = Buffer.from(rel);
    const head = Buffer.alloc(7);
    head.writeUInt8(kind, 0);
    head.writeUInt16LE(0o644, 1);
    head.writeUInt32LE(name.length, 3);
    const size = Buffer.alloc(4);
    size.writeUInt32LE(data.length, 0);
    return zlib.gzipSync(Buffer.concat([Buffer.from('FLXP1\n'), head, name, size, data]));
  };
  assert.throws(() => unpack(evil('../outside.txt'), path.join(temp('evil'), 'out')), /escapes/);
  assert.throws(() => unpack(evil('link', 1, Buffer.from('../../etc/passwd')), path.join(temp('evil'), 'out')), /escapes/);
  assert.throws(() => unpack(zlib.gzipSync(Buffer.from('nope')), path.join(temp('evil'), 'out')), /not a Flixor payload/);
});

test('arguments', () => {
  assert.deepEqual(parseArgs([]), { help: false, version: false });
  assert.deepEqual(parseArgs(['--port', '8080', '--host=127.0.0.1', '--data-dir', '/srv/flixor']), {
    help: false, version: false, port: '8080', host: '127.0.0.1', dataDir: '/srv/flixor',
  });
  assert.equal(parseArgs(['--version']).version, true);
  assert.equal(parseArgs(['-h']).help, true);
  assert.throws(() => parseArgs(['--port']), /needs a value/);
  assert.throws(() => parseArgs(['--port', 'abc']), /must be a number/);
  assert.throws(() => parseArgs(['--bogus']), /unknown option/);
});

test('env file', () => {
  assert.deepEqual(parseEnvFile([
    '# comment',
    'PORT=8080',
    'export HOST = 127.0.0.1',
    'FFMPEG_PATH="/opt/homebrew/bin/ffmpeg"',
    "TMDB_DEFAULT_KEY='a b'",
    'LOG_LEVEL=debug # trailing comment',
    'not a line',
    '',
  ].join('\n')), {
    PORT: '8080', HOST: '127.0.0.1', FFMPEG_PATH: '/opt/homebrew/bin/ffmpeg', TMDB_DEFAULT_KEY: 'a b', LOG_LEVEL: 'debug',
  });
});

test('session secret is created once and kept', () => {
  const dir = temp('secret');
  const first = sessionSecret(dir);
  assert.ok(first.length >= 32);
  assert.equal(sessionSecret(dir), first);
  assert.equal(fs.statSync(path.join(dir, 'session-secret')).mode & 0o077, 0);
});

test('settings: flags beat the environment, which beats flixor.env, which beats defaults', () => {
  const data = temp('data');
  fs.writeFileSync(path.join(data, 'flixor.env'), 'PORT=4000\nHOST=127.0.0.1\nLOG_LEVEL=debug\n');
  const env: NodeJS.ProcessEnv = { PATH: '/usr/bin:/bin', HOST: '10.0.0.5' };
  configure(env, { help: false, version: false, port: '5000' }, data, '/web');
  assert.equal(env.PORT, '5000');
  assert.equal(env.HOST, '10.0.0.5');
  assert.equal(env.LOG_LEVEL, 'debug');
  assert.equal(env.CONFIG_DIRECTORY, path.join(data, 'config'));
  assert.equal(env.LOG_DIRECTORY, path.join(data, 'logs'));
  assert.equal(env.IMAGE_CACHE_DIR, path.join(data, 'cache', 'images'));
  assert.equal(env.NODE_ENV, 'production');
  assert.equal(env.FLIXOR_WEB_DIR, '/web');
  assert.equal(env.FRONTEND_URL, 'http://localhost:5000');
  assert.equal(env.SESSION_SECRET, fs.readFileSync(path.join(data, 'config', 'session-secret'), 'utf8').trim());
  assert.ok(env.PATH!.startsWith('/usr/bin:/bin:'));
  assert.ok(env.PATH!.includes('/opt/homebrew/bin'));
});

test('runtime is unpacked once per build and old builds are removed', () => {
  const src = temp('payload-src');
  fs.mkdirSync(path.join(src, 'app'));
  fs.writeFileSync(path.join(src, 'app/server.js'), 'v1');
  const packed = pack(src);
  const data = temp('runtime');
  let unpacked = 0;
  const payload = () => { unpacked += 1; return packed; };

  const v1 = ensureRuntime(data, { version: '1.0.0', hash: 'aaa' }, payload);
  assert.equal(fs.readFileSync(path.join(v1, 'app/server.js'), 'utf8'), 'v1');
  ensureRuntime(data, { version: '1.0.0', hash: 'aaa' }, payload);
  assert.equal(unpacked, 1);

  // A runtime without its marker (interrupted) is replaced.
  fs.rmSync(path.join(v1, '.complete'));
  ensureRuntime(data, { version: '1.0.0', hash: 'aaa' }, payload);
  assert.equal(unpacked, 2);

  const v2 = ensureRuntime(data, { version: '1.1.0', hash: 'bbb' }, payload);
  assert.deepEqual(fs.readdirSync(path.join(data, 'runtime')), [path.basename(v2)]);
});
