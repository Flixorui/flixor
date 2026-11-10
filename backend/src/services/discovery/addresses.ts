/**
 * Which of this machine's IPv4 addresses to give out under its .local name.
 * Docker bridges, VPNs (Tailscale, WireGuard), link-local and similar addresses
 * are left out unless the asker is on that network itself.
 */
import os from 'os';

export interface LocalAddress {
  iface: string;
  address: string;
  netmask: string;
}

type Interfaces = ReturnType<typeof os.networkInterfaces>;

/** Interfaces that aren't the machine's real network: containers, VPNs, Apple peer-to-peer links. */
const VIRTUAL_IFACE = /^(lo|docker|br-|veth|virbr|vmnet|vboxnet|utun|tun|tap|tailscale|zt|wg|awdl|llw|bridge|anpi|gif|stf|ipsec|ppp|cni|flannel|cali|kube)/i;
/** Interfaces most likely to be the main network, in order of preference. */
const PREFERRED_IFACE = [/^en0$/, /^eth0$/, /^en\d/, /^eth\d/, /^eno/, /^enp/, /^ens/, /^wl/];

const toInt = (ip: string) => ip.split('.').reduce((n, part) => ((n << 8) | Number(part)) >>> 0, 0);

function inRange(ip: string, base: string, bits: number): boolean {
  const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
  return ((toInt(ip) & mask) >>> 0) === ((toInt(base) & mask) >>> 0);
}

export function ipv4Addresses(interfaces: Interfaces = os.networkInterfaces()): LocalAddress[] {
  const out: LocalAddress[] = [];
  for (const [iface, list] of Object.entries(interfaces)) {
    for (const addr of list || []) {
      if (addr.family === 'IPv4' && !addr.internal) out.push({ iface, address: addr.address, netmask: addr.netmask });
    }
  }
  return out;
}

export function isVirtual(addr: LocalAddress): boolean {
  return VIRTUAL_IFACE.test(addr.iface) || inRange(addr.address, '100.64.0.0', 10) || inRange(addr.address, '169.254.0.0', 16);
}

const preference = (iface: string) => {
  const i = PREFERRED_IFACE.findIndex((pattern) => pattern.test(iface));
  return i === -1 ? PREFERRED_IFACE.length : i;
};

/** The machine's real network addresses, the most likely main one first. */
export function lanAddresses(interfaces?: Interfaces): LocalAddress[] {
  return ipv4Addresses(interfaces)
    .filter((addr) => !isVirtual(addr))
    .sort((a, b) => preference(a.iface) - preference(b.iface) || a.iface.localeCompare(b.iface));
}

export function sameSubnet(addr: LocalAddress, ip: string): boolean {
  const mask = toInt(addr.netmask);
  return ((toInt(addr.address) & mask) >>> 0) === ((toInt(ip) & mask) >>> 0);
}

/**
 * Addresses to answer a question from `asker` with: the address on the asker's
 * network when it is on one of ours, otherwise (this machine itself, or a routed
 * network) the real network addresses.
 */
export function addressesFor(asker: string, interfaces?: Interfaces): LocalAddress[] {
  const all = ipv4Addresses(interfaces);
  const own = asker.startsWith('127.') || all.some((addr) => addr.address === asker);
  if (!own) {
    const onAskersNetwork = all.filter((addr) => sameSubnet(addr, asker));
    if (onAskersNetwork.length) return onAskersNetwork;
  }
  return lanAddresses(interfaces);
}
