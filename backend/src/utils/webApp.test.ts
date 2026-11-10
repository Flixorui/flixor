/** Serving the built web app from the backend (standalone server). Run: npm test. */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import type { AddressInfo } from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import express from 'express';
import { mountWebApp } from './webApp';

let base = '';
let close: () => void = () => {};
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'flixor-web-'));

before(async () => {
  fs.mkdirSync(path.join(dir, 'assets'));
  fs.writeFileSync(path.join(dir, 'index.html'), '<!doctype html><title>app</title>');
  fs.writeFileSync(path.join(dir, 'assets', 'index-abc123.js'), 'console.log(1)');
  fs.writeFileSync(path.join(dir, 'logo.png'), 'png');

  const app = express();
  app.get('/api/ping', (_req, res) => res.json({ ok: true }));
  assert.equal(mountWebApp(app, dir), dir);
  app.use((_req, res) => res.status(404).json({ error: 'Not Found' }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  close = () => server.close();
});

after(() => {
  close();
  fs.rmSync(dir, { recursive: true, force: true });
});

test('client-side routes get index.html, uncached', async () => {
  for (const route of ['/', '/details/tmdb:movie:1', '/settings/appearance']) {
    const res = await fetch(base + route);
    assert.equal(res.status, 200, route);
    assert.match(await res.text(), /<title>app<\/title>/);
    assert.equal(res.headers.get('cache-control'), 'no-cache');
  }
});

test('hashed assets are cached for a year, other files are revalidated', async () => {
  const asset = await fetch(`${base}/assets/index-abc123.js`);
  assert.equal(asset.status, 200);
  assert.equal(asset.headers.get('cache-control'), 'public, max-age=31536000, immutable');
  const logo = await fetch(`${base}/logo.png`);
  assert.equal(logo.status, 200);
  assert.equal(logo.headers.get('cache-control'), 'no-cache');
});

test('API, missing files and non-GET requests are left to the server', async () => {
  assert.deepEqual(await (await fetch(`${base}/api/ping`)).json(), { ok: true });
  assert.equal((await fetch(`${base}/api/missing`)).status, 404);
  assert.equal((await fetch(`${base}/internal/media-relay/x`)).status, 404);
  assert.equal((await fetch(`${base}/assets/missing.js`)).status, 404);
  assert.equal((await fetch(`${base}/settings`, { method: 'POST' })).status, 404);
});

test('nothing is mounted without a built app', () => {
  assert.equal(mountWebApp(express(), undefined), null);
  assert.equal(mountWebApp(express(), path.join(dir, 'nope')), null);
});
