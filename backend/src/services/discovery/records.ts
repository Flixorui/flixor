/**
 * mDNS records for the server: its host name (A) and a DNS-SD web service
 * (PTR, SRV, TXT), so browsers that list Bonjour services show "Flixor".
 * Pure functions, for the responder and its tests.
 */
import type { Answer, Packet, Question } from 'dns-packet';

export const SERVICE_TYPE = '_http._tcp.local';
const SERVICES_META = '_services._dns-sd._udp.local';
/** RFC 6762: 120 s for records that name a host, 75 minutes for the rest. */
const HOST_TTL = 120;
const OTHER_TTL = 4500;

export interface Identity {
  /** Host name without .local, e.g. "flixor". */
  host: string;
  /** Service instance label, e.g. "Flixor". */
  instance: string;
  port: number;
}

export const hostName = (id: Identity) => `${id.host}.local`;
const instanceName = (id: Identity) => `${id.instance}.${SERVICE_TYPE}`;

/** Every record this server owns; ttl 0 makes them goodbyes. */
export function allRecords(id: Identity, addresses: string[], ttl?: number): Answer[] {
  const t = (normal: number) => ttl ?? normal;
  return [
    ...addresses.map((address): Answer => ({ name: hostName(id), type: 'A', class: 'IN', ttl: t(HOST_TTL), flush: true, data: address })),
    { name: instanceName(id), type: 'SRV', class: 'IN', ttl: t(HOST_TTL), flush: true, data: { target: hostName(id), port: id.port, priority: 0, weight: 0 } },
    { name: instanceName(id), type: 'TXT', class: 'IN', ttl: t(OTHER_TTL), flush: true, data: ['path=/'] },
    { name: SERVICE_TYPE, type: 'PTR', class: 'IN', ttl: t(OTHER_TTL), data: instanceName(id) },
    { name: SERVICES_META, type: 'PTR', class: 'IN', ttl: t(OTHER_TTL), data: SERVICE_TYPE },
  ];
}

/** The records that answer `question`, if this server owns the name it asks about. */
export function answersFor(question: Question, id: Identity, addresses: string[]): Answer[] {
  const name = question.name.toLowerCase();
  // dns-packet's types leave out ANY (type 255), which mDNS queriers use.
  const asked = question.type as string;
  const wants = (type: string) => asked === type || asked === 'ANY';
  const records = allRecords(id, addresses);
  return records.filter((record) => record.name.toLowerCase() === name && wants(record.type));
}

/**
 * "This name has no record of the type you asked for" (an NSEC record, RFC 6762
 * 6.1). Without it, a client asking for IPv6 (AAAA) next to IPv4 waits seconds
 * for an answer that never comes before using the IPv4 one.
 */
export function negativeFor(question: Question, id: Identity): Answer[] {
  const asked = question.type as string;
  if (question.name.toLowerCase() !== hostName(id) || asked === 'A' || asked === 'ANY') return [];
  return [{ name: hostName(id), type: 'NSEC', class: 'IN', ttl: HOST_TTL, flush: true, data: { nextDomain: hostName(id), rrtypes: ['A'] } }];
}

/** True when `response` claims our host name for an address that isn't ours: someone else has it. */
export function isConflict(response: Packet, host: string, ours: string[]): boolean {
  const name = `${host}.local`.toLowerCase();
  return (response.answers || []).some((answer) => answer.type === 'A' && answer.name.toLowerCase() === name && !ours.includes(String(answer.data)));
}

/** host, host-2, host-3, … */
export const candidateName = (base: string, attempt: number) => (attempt === 0 ? base : `${base}-${attempt + 1}`);

/** Valid single DNS label for a .local name. */
export const isValidHostLabel = (label: string) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i.test(label);
