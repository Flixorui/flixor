/**
 * A small mDNS responder (RFC 6762) for the server's .local name, used where the
 * system responder can't be asked to publish it (Linux, with or without Avahi).
 * It shares UDP 5353 with the system responder, probes for the name before
 * claiming it (taking name-2, name-3, … when taken), answers only with addresses
 * on the asker's network, and says goodbye when it stops.
 */
import dgram from 'dgram';
import packet, { type Packet, type RecordType } from 'dns-packet';
import { addressesFor, ipv4Addresses, lanAddresses } from './addresses';
import { allRecords, answersFor, candidateName, isConflict, negativeFor, type Identity } from './records';

const MDNS_GROUP = '224.0.0.251';
const MDNS_PORT = 5353;
const PROBE_WAIT_MS = 250;
const MAX_ATTEMPTS = 10;

export interface Publication {
  /** The name claimed, without .local. */
  host: string;
  stop(): Promise<void>;
}

interface Options {
  base: string;
  port: number;
  instance: string;
  log: (message: string) => void;
}

export function startResponder({ base, port, instance, log }: Options): Promise<Publication> {
  const socket = dgram.createSocket({ type: 'udp4', reuseAddr: true });
  let id: Identity = { host: base, instance, port };
  let probing: { host: string; conflict: boolean } | null = null;
  let joined = new Set<string>();
  let watch: NodeJS.Timeout | undefined;

  const send = (message: Packet, via: string, to?: { address: string; port: number }) => {
    const bytes = packet.encode(message);
    try {
      if (to) {
        socket.send(bytes, 0, bytes.length, to.port, to.address);
      } else {
        socket.setMulticastInterface(via);
        socket.send(bytes, 0, bytes.length, MDNS_PORT, MDNS_GROUP);
      }
    } catch {
      // Interface went away; the next change check rejoins.
    }
  };

  const joinAll = () => {
    const now = new Set(ipv4Addresses().map((addr) => addr.address));
    for (const address of now) {
      if (joined.has(address)) continue;
      try {
        socket.addMembership(MDNS_GROUP, address);
      } catch {
        // Already a member, or the interface can't do multicast.
      }
    }
    const changed = now.size !== joined.size || [...now].some((address) => !joined.has(address));
    joined = now;
    return changed;
  };

  /** Unsolicited responses on each real network, so caches learn the name now. */
  const announce = (ttl?: number) => {
    for (const addr of lanAddresses()) {
      send({ type: 'response', id: 0, flags: packet.AUTHORITATIVE_ANSWER, answers: allRecords(id, [addr.address], ttl) }, addr.address);
    }
  };

  socket.on('message', (message, rinfo) => {
    let decoded: Packet;
    try {
      decoded = packet.decode(message);
    } catch {
      return;
    }
    if (decoded.type === 'response') {
      if (probing && isConflict(decoded, probing.host, ipv4Addresses().map((addr) => addr.address))) probing.conflict = true;
      return;
    }
    if (probing) return; // Not ours to answer yet.
    const addresses = addressesFor(rinfo.address).map((addr) => addr.address);
    const answers = (decoded.questions || []).flatMap((question) => [...answersFor(question, id, addresses), ...negativeFor(question, id)]);
    if (!answers.length) return;
    if (rinfo.port !== MDNS_PORT) {
      // A plain DNS client asking the group directly: reply to it, echoing its question (RFC 6762 6.7).
      send({ type: 'response', id: decoded.id, flags: packet.AUTHORITATIVE_ANSWER, questions: decoded.questions, answers: answers.map((a) => ({ ...a, ttl: Math.min((a as { ttl?: number }).ttl ?? 10, 10) }) as typeof a) }, '', rinfo);
    } else {
      send({ type: 'response', id: 0, flags: packet.AUTHORITATIVE_ANSWER, answers }, addresses[0] || '0.0.0.0');
    }
  });

  /** Asks three times whether anyone answers for `host`; resolves true when someone does. */
  const taken = async (host: string): Promise<boolean> => {
    probing = { host, conflict: false };
    for (let i = 0; i < 3 && !probing.conflict; i += 1) {
      for (const addr of lanAddresses()) {
        send({ type: 'query', id: 0, questions: [{ name: `${host}.local`, type: 'ANY' as RecordType, class: 'IN' }] }, addr.address);
      }
      await new Promise((resolve) => setTimeout(resolve, PROBE_WAIT_MS));
    }
    const conflict = probing.conflict;
    probing = null;
    return conflict;
  };

  return new Promise((resolve, reject) => {
    socket.once('error', reject);
    socket.bind(MDNS_PORT, async () => {
      socket.removeListener('error', reject);
      socket.on('error', (error) => log(`mDNS socket error: ${error.message}`));
      socket.setMulticastTTL(255);
      socket.setMulticastLoopback(true);
      joinAll();

      let host = base;
      for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt += 1) {
        host = candidateName(base, attempt);
        if (!(await taken(host))) break;
        log(`${host}.local is already used on this network; trying another name`);
        if (attempt === MAX_ATTEMPTS - 1) {
          socket.close();
          return reject(new Error(`no free name from ${base}.local to ${host}.local`));
        }
      }
      id = { ...id, host };
      announce();
      setTimeout(() => announce(), 1000);
      // Networks come and go (Wi-Fi, docking): rejoin and re-announce when they change.
      watch = setInterval(() => { if (joinAll()) announce(); }, 30_000);
      watch.unref();

      resolve({
        host,
        stop: () => new Promise<void>((done) => {
          if (watch) clearInterval(watch);
          announce(0);
          setTimeout(() => socket.close(() => done()), 100);
        }),
      });
    });
  });
}
