/**
 * Publishes the server under a .local name (default flixor.local) so devices on
 * the network, and the machine itself, can open it by name. Off unless
 * MDNS_NAME is set: the standalone server sets it to "flixor"; "off" disables.
 * macOS publishes through the system responder; elsewhere a built-in responder.
 */
import fs from 'fs';
import logger from '../../utils/logger';
import { startBonjour } from './bonjour';
import { isValidHostLabel } from './records';
import { startResponder, type Publication } from './responder';

const log = logger.child({ component: 'discovery' });

export interface DiscoveryState {
  /** e.g. "flixor.local", or null when not published. */
  name: string | null;
  /** True when the server also listens on port 80, so the name works without a port. */
  port80: boolean;
  /** The address to open, e.g. "http://flixor.local" or "http://flixor.local:3001". */
  url: string | null;
}

let publication: Publication | null = null;
let state: DiscoveryState = { name: null, port80: false, url: null };

export const discoveryState = (): DiscoveryState => {
  if (publication && state.name !== `${publication.host}.local`) {
    // A re-registration moved to another name.
    const name = `${publication.host}.local`;
    state = { ...state, name, url: state.url ? state.url.replace(/\/\/[^/:]+/, `//${name}`) : null };
  }
  return state;
};

export async function startDiscovery({ port, port80 }: { port: number; port80: boolean }): Promise<void> {
  const base = (process.env.MDNS_NAME || '').trim().toLowerCase();
  if (!base || base === 'off') return;
  if (!isValidHostLabel(base)) {
    log.warn(`MDNS_NAME "${base}" isn't a valid name (letters, digits and hyphens); not publishing one`);
    return;
  }
  const advertised = port80 ? 80 : port;
  const instance = base === 'flixor' ? 'Flixor' : `Flixor (${base})`;
  const options = { base, port: advertised, instance, log: (message: string) => log.info(message) };
  try {
    const useSystem = process.platform === 'darwin' && fs.existsSync('/usr/bin/dns-sd');
    publication = await (useSystem ? startBonjour(options) : startResponder(options));
    const name = `${publication.host}.local`;
    state = { name, port80, url: `http://${name}${advertised === 80 ? '' : `:${advertised}`}` };
    log.info(`📡 Also at ${state.url}`);
  } catch (error) {
    log.warn(`Couldn't publish ${base}.local: ${(error as Error).message}`);
  }
}

export async function stopDiscovery(): Promise<void> {
  const current = publication;
  publication = null;
  await current?.stop().catch(() => undefined);
}
