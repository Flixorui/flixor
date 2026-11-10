/**
 * Publishes the server's .local name on macOS through the system responder
 * (mDNSResponder), with `dns-sd -P`. The system then answers for it on the Mac
 * itself and on the network, and reports a name clash, on which this moves to
 * name-2, name-3, … It re-registers when the Mac's address changes.
 */
import { spawn, type ChildProcess } from 'child_process';
import { lanAddresses } from './addresses';
import { candidateName } from './records';
import type { Publication } from './responder';

const MAX_ATTEMPTS = 10;
const SETTLE_MS = 6000;

export type DnsSdEvent = 'registered' | 'conflict' | null;

/** What a line of `dns-sd -P` output says about the host record. */
export function parseDnsSdLine(line: string, host: string): DnsSdEvent {
  const lower = line.toLowerCase();
  if (!lower.includes(`record ${host.toLowerCase()}.local`)) return null;
  if (lower.includes('name in use')) return 'conflict';
  if (lower.includes('registered and active')) return 'registered';
  return null;
}

interface Options {
  base: string;
  port: number;
  instance: string;
  log: (message: string) => void;
}

/** Runs one registration; resolves with the child once the name is ours, null on a clash. */
function register(host: string, address: string, { port, instance }: Options): Promise<ChildProcess | null> {
  return new Promise((resolve, reject) => {
    const child = spawn('dns-sd', ['-P', instance, '_http._tcp', 'local', String(port), `${host}.local`, address, 'path=/'], { stdio: ['ignore', 'pipe', 'pipe'] });
    let buffer = '';
    let settled = false;
    const finish = (value: ChildProcess | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (value === null) child.kill();
      resolve(value);
    };
    // No verdict in time: the registration stands unless dns-sd objected.
    const timer = setTimeout(() => finish(child.exitCode === null ? child : null), SETTLE_MS);
    child.stdout.on('data', (chunk: Buffer) => {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';
      for (const line of lines) {
        const event = parseDnsSdLine(line, host);
        if (event === 'registered') finish(child);
        if (event === 'conflict') finish(null);
      }
    });
    child.on('error', (error) => { if (!settled) { settled = true; clearTimeout(timer); reject(error); } });
    child.on('exit', () => finish(null));
  });
}

export async function startBonjour(options: Options): Promise<Publication> {
  const { base, log } = options;
  let child: ChildProcess | null = null;
  let host = base;
  let address = '';
  let stopped = false;
  let watch: NodeJS.Timeout | undefined;

  const claim = async (): Promise<void> => {
    const primary = lanAddresses()[0]?.address;
    if (!primary) throw new Error('no network address to publish yet');
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
      const candidate = candidateName(base, attempt);
      const registered = await register(candidate, primary, options);
      if (registered) {
        child = registered;
        host = candidate;
        address = primary;
        registered.on('exit', () => {
          if (child === registered && !stopped) {
            child = null;
            log('mDNS registration ended; registering again');
            setTimeout(() => { if (!stopped) claim().catch((error) => log(`mDNS: ${error.message}`)); }, 5000);
          }
        });
        return;
      }
      log(`${candidate}.local is already used on this network; trying another name`);
    }
    throw new Error(`no free name from ${base}.local to ${candidateName(base, MAX_ATTEMPTS - 1)}.local`);
  };

  await claim();

  // The Mac's address changes with Wi-Fi networks and docking: publish the new one.
  watch = setInterval(() => {
    const primary = lanAddresses()[0]?.address;
    if (!primary || primary === address || stopped) return;
    const old = child;
    child = null;
    old?.kill();
    claim().catch((error) => log(`mDNS: ${error.message}`));
  }, 30_000);
  watch.unref();

  return {
    get host() { return host; },
    stop: async () => {
      stopped = true;
      if (watch) clearInterval(watch);
      child?.kill();
    },
  };
}
