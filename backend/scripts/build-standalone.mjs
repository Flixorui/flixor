#!/usr/bin/env node
/**
 * Builds the standalone Flixor server for the machine it runs on:
 * build/standalone/flixor-server-<os>-<arch>.tar.gz (one executable) and its .sha256.
 *
 *   npm run build:standalone -- [--version 1.2.3] [--skip-web] [--skip-tsc]
 *
 * Steps: compile the backend (tsc), bundle it (esbuild), build the web app, copy
 * the native add-ons' runtime files, pack all of it into one payload, then turn
 * the official Node binary into a single executable application carrying that
 * payload (see standalone/bootstrap.ts).
 *
 * On macOS the result is signed ad hoc, or with CODESIGN_IDENTITY when set.
 * NODE_SEA_NODE_VERSION picks the Node release (default below).
 */
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const backend = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.resolve(backend, '..');
const webFrontend = path.join(repo, 'web_frontend');
const out = path.join(backend, 'build', 'standalone');
const stage = path.join(out, 'stage');
const cache = path.join(backend, 'build', 'cache');

const NODE_VERSION = process.env.NODE_SEA_NODE_VERSION || '24.15.0';
const SEA_FUSE = 'NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2';
const NATIVE_PACKAGES = ['sqlite3', 'sharp'];
/** Needed to install or compile the add-ons, never at run time. */
const INSTALL_ONLY = new Set(['prebuild-install', 'tar', 'node-addon-api', 'node-gyp', 'node-pre-gyp', '@mapbox/node-pre-gyp']);
/** Per package: paths (relative to the package) that are source or build leftovers. */
const PRUNE = {
  sqlite3: ['deps', 'src', 'build/Release/obj', 'build/Release/.deps', 'build/Release/obj.target', 'build/deps', 'build/Makefile', 'build/config.gypi'],
};

const platform = process.platform;
const arch = process.arch;
if (!['darwin', 'linux'].includes(platform)) throw new Error(`unsupported platform: ${platform}`);
const target = `${platform}-${arch}`;

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};

function run(cmd, cmdArgs, opts = {}) {
  console.log(`$ ${cmd} ${cmdArgs.join(' ')}`);
  return execFileSync(cmd, cmdArgs, { stdio: 'inherit', ...opts });
}

function step(title) {
  console.log(`\n▸ ${title}`);
}

function version() {
  const given = option('--version') || process.env.FLIXOR_VERSION;
  if (given) return given.replace(/^server-v/, '').replace(/^v/, '');
  const base = JSON.parse(fs.readFileSync(path.join(backend, 'package.json'), 'utf8')).version;
  let sha = 'local';
  try {
    sha = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: repo }).toString().trim();
  } catch {
    // Not a git checkout.
  }
  return `${base}-dev.${sha}`;
}

/** Bare imports esbuild can't resolve (TypeORM's other database drivers and the like) stay external; they are never loaded. */
const externalizeMissing = {
  name: 'externalize-missing',
  setup(build) {
    build.onResolve({ filter: /^[^./]/ }, async (resolveArgs) => {
      if (resolveArgs.pluginData?.probing) return undefined;
      const result = await build.resolve(resolveArgs.path, {
        kind: resolveArgs.kind,
        resolveDir: resolveArgs.resolveDir,
        importer: resolveArgs.importer,
        pluginData: { probing: true },
      });
      return result.errors.length ? { path: resolveArgs.path, external: true } : undefined;
    });
  },
};

/** The folder of `name` as Node would find it from `fromDir`. */
function findPackage(name, fromDir) {
  for (let dir = fromDir; ; dir = path.dirname(dir)) {
    const candidate = path.join(dir, 'node_modules', name);
    if (fs.existsSync(path.join(candidate, 'package.json'))) return candidate;
    if (dir === path.dirname(dir) || dir === path.dirname(backend)) return null;
  }
}

/** The add-ons and everything they load at run time, as package folders. */
function runtimePackages() {
  const found = new Map();
  const visit = (name, fromDir, required) => {
    if (INSTALL_ONLY.has(name)) return;
    const dir = findPackage(name, fromDir);
    if (!dir) {
      if (required) throw new Error(`${name} is not installed; run npm ci in backend first`);
      return; // An optional dependency for another platform.
    }
    if (found.has(dir)) return;
    found.set(dir, name);
    const pkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
    for (const dep of Object.keys(pkg.dependencies || {})) visit(dep, dir, true);
    for (const dep of Object.keys(pkg.optionalDependencies || {})) visit(dep, dir, false);
  };
  for (const name of NATIVE_PACKAGES) visit(name, backend, true);
  return found;
}

function copyPackage(dir, name) {
  const rel = path.relative(backend, dir);
  const dest = path.join(stage, rel);
  const pruned = (PRUNE[name] || []).map((p) => path.join(dir, p));
  fs.cpSync(dir, dest, {
    recursive: true,
    verbatimSymlinks: true,
    filter: (src) => !pruned.some((p) => src === p || src.startsWith(p + path.sep))
      && !/\.(md|markdown|map)$|\.d\.ts$/i.test(src),
  });
}

async function downloadNode() {
  const name = `node-v${NODE_VERSION}-${platform}-${arch}`;
  const binary = path.join(cache, name, 'bin', 'node');
  if (fs.existsSync(binary)) return binary;
  fs.mkdirSync(cache, { recursive: true });
  const base = `https://nodejs.org/dist/v${NODE_VERSION}`;
  const archive = path.join(cache, `${name}.tar.gz`);
  console.log(`Downloading ${base}/${name}.tar.gz`);
  const [tarball, sums] = await Promise.all([
    fetch(`${base}/${name}.tar.gz`).then((r) => { if (!r.ok) throw new Error(`Node download failed: ${r.status}`); return r.arrayBuffer(); }),
    fetch(`${base}/SHASUMS256.txt`).then((r) => { if (!r.ok) throw new Error(`Node checksums failed: ${r.status}`); return r.text(); }),
  ]);
  const expected = sums.split('\n').find((line) => line.endsWith(`  ${name}.tar.gz`))?.split(/\s+/)[0];
  const actual = crypto.createHash('sha256').update(Buffer.from(tarball)).digest('hex');
  if (!expected || expected !== actual) throw new Error(`Node checksum mismatch for ${name}.tar.gz`);
  fs.writeFileSync(archive, Buffer.from(tarball));
  run('tar', ['-xzf', archive, '-C', cache, `${name}/bin/node`]);
  fs.rmSync(archive);
  return binary;
}

function sha256File(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

async function main() {
  const esbuild = require('esbuild');
  const ver = version();
  console.log(`Building flixor-server ${ver} for ${target}`);
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(stage, { recursive: true });

  if (!flag('--skip-tsc')) {
    step('Compiling the backend');
    run('npx', ['tsc'], { cwd: backend });
  }

  step('Bundling the server');
  // The tsc output, not the sources: it carries the decorator metadata TypeORM reads.
  await esbuild.build({
    entryPoints: [path.join(backend, 'dist', 'server.js')],
    outfile: path.join(stage, 'app', 'server.js'),
    bundle: true,
    platform: 'node',
    target: 'node24',
    format: 'cjs',
    keepNames: true,
    external: NATIVE_PACKAGES,
    plugins: [externalizeMissing],
    logLevel: 'warning',
    legalComments: 'eof',
  });

  step('Building the web app');
  if (!flag('--skip-web')) run('npm', ['run', 'build'], { cwd: webFrontend });
  const webDist = path.join(webFrontend, 'dist');
  if (!fs.existsSync(path.join(webDist, 'index.html'))) throw new Error('web_frontend/dist is missing; build the web app first');
  fs.cpSync(webDist, path.join(stage, 'web'), {
    recursive: true,
    filter: (src) => !src.endsWith('.map') && path.basename(src) !== 'test-integration.html',
  });

  step('Copying native add-ons');
  for (const [dir, name] of runtimePackages()) {
    console.log(`  ${path.relative(backend, dir)}`);
    copyPackage(dir, name);
  }

  step('Packing the payload');
  // The same pack/unpack code the executable uses, compiled for this script.
  const packer = path.join(out, 'payload.cjs');
  await esbuild.build({
    entryPoints: [path.join(backend, 'standalone', 'payload.ts')],
    outfile: packer,
    bundle: true, platform: 'node', format: 'cjs', target: 'node24', logLevel: 'warning',
  });
  const payload = require(packer).pack(stage);
  const payloadFile = path.join(out, 'payload.bin');
  fs.writeFileSync(payloadFile, payload);
  const manifest = { version: ver, hash: crypto.createHash('sha256').update(payload).digest('hex').slice(0, 12) };
  fs.writeFileSync(path.join(out, 'manifest.json'), JSON.stringify(manifest));
  console.log(`  ${(payload.length / 1e6).toFixed(1)} MB compressed, build ${manifest.hash}`);

  step('Bundling the entry point');
  await esbuild.build({
    entryPoints: [path.join(backend, 'standalone', 'bootstrap.ts')],
    outfile: path.join(out, 'bootstrap.js'),
    bundle: true, platform: 'node', format: 'cjs', target: 'node24', logLevel: 'warning',
  });

  step(`Making the executable (Node ${NODE_VERSION})`);
  const node = await downloadNode();
  const seaConfig = path.join(out, 'sea-config.json');
  const blob = path.join(out, 'sea-prep.blob');
  fs.writeFileSync(seaConfig, JSON.stringify({
    main: path.join(out, 'bootstrap.js'),
    output: blob,
    disableExperimentalSEAWarning: true,
    useSnapshot: false,
    useCodeCache: false,
    assets: { manifest: path.join(out, 'manifest.json'), payload: payloadFile },
  }, null, 2));
  // The blob must come from the same Node build that will run it.
  run(node, ['--experimental-sea-config', seaConfig]);

  const exe = path.join(out, 'flixor-server');
  fs.copyFileSync(node, exe);
  fs.chmodSync(exe, 0o755);
  if (platform === 'darwin') run('codesign', ['--remove-signature', exe]);
  const { inject } = require('postject');
  await inject(exe, 'NODE_SEA_BLOB', fs.readFileSync(blob), {
    sentinelFuse: SEA_FUSE,
    ...(platform === 'darwin' ? { machoSegmentName: 'NODE_SEA' } : {}),
  });

  if (platform === 'darwin') {
    const identity = process.env.CODESIGN_IDENTITY;
    if (identity) {
      // Hardened runtime for notarization; V8 needs JIT, and the unpacked add-ons are signed by others.
      const entitlements = path.join(out, 'entitlements.plist');
      fs.writeFileSync(entitlements, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
`);
      run('codesign', ['--force', '--sign', identity, '--options', 'runtime', '--timestamp', '--entitlements', entitlements, exe]);
    } else {
      run('codesign', ['--force', '--sign', '-', exe]);
    }
  }

  step('Archiving');
  const archiveName = `flixor-server-${target}.tar.gz`;
  const archive = path.join(out, archiveName);
  run('tar', ['-czf', archive, '-C', out, 'flixor-server']);
  fs.writeFileSync(`${archive}.sha256`, `${sha256File(archive)}  ${archiveName}\n`);
  for (const leftover of ['stage', 'sea-prep.blob', 'bootstrap.js', 'sea-config.json', 'entitlements.plist', 'payload.cjs']) {
    fs.rmSync(path.join(out, leftover), { recursive: true, force: true });
  }

  const size = (file) => `${(fs.statSync(file).size / 1e6).toFixed(0)} MB`;
  console.log(`\n✓ ${path.relative(repo, exe)} (${size(exe)})`);
  console.log(`✓ ${path.relative(repo, archive)} (${size(archive)})`);
}

main().catch((error) => {
  console.error(`\n✗ ${error.message}`);
  process.exit(1);
});
