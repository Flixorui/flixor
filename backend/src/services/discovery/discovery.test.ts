/** .local name publishing: address choice, records, clash detection, dns-sd output. Run: npm test. */
import assert from 'node:assert/strict';
import type os from 'node:os';
import { test } from 'node:test';
import { addressesFor, lanAddresses } from './addresses';
import { parseDnsSdLine } from './bonjour';
import { allRecords, answersFor, candidateName, isConflict, isValidHostLabel, negativeFor, type Identity } from './records';

type Interfaces = ReturnType<typeof os.networkInterfaces>;
const v4 = (address: string, netmask = '255.255.255.0', internal = false) =>
  ({ address, netmask, family: 'IPv4', mac: '00:00:00:00:00:00', internal, cidr: null }) as os.NetworkInterfaceInfo;

// gpu-server's shape: LAN, Docker bridges, Tailscale.
const linuxBox: Interfaces = {
  lo: [v4('127.0.0.1', '255.0.0.0', true)],
  docker0: [v4('172.17.0.1', '255.255.0.0')],
  'br-3f2a': [v4('172.18.0.1', '255.255.0.0')],
  enp5s0: [v4('10.0.0.29')],
  tailscale0: [v4('100.101.241.72', '255.255.255.255')],
};
// A Mac on Wi-Fi with Tailscale and a link-local Thunderbolt bridge.
const mac: Interfaces = {
  utun4: [v4('100.75.160.83', '255.255.255.255')],
  bridge0: [v4('169.254.10.2', '255.255.0.0')],
  en1: [v4('192.168.1.40')],
  en0: [v4('10.0.0.66')],
};

test('real network addresses leave out containers, VPNs and link-local, main interface first', () => {
  assert.deepEqual(lanAddresses(linuxBox).map((a) => a.address), ['10.0.0.29']);
  assert.deepEqual(lanAddresses(mac).map((a) => a.address), ['10.0.0.66', '192.168.1.40']);
});

test('answers carry the address on the asker’s network', () => {
  assert.deepEqual(addressesFor('10.0.0.66', linuxBox).map((a) => a.address), ['10.0.0.29']); // the Mac on the LAN
  assert.deepEqual(addressesFor('172.18.0.5', linuxBox).map((a) => a.address), ['172.18.0.1']); // a container
  assert.deepEqual(addressesFor('127.0.0.1', linuxBox).map((a) => a.address), ['10.0.0.29']); // the box itself
  assert.deepEqual(addressesFor('172.17.0.1', linuxBox).map((a) => a.address), ['10.0.0.29']); // its own bridge address
  assert.deepEqual(addressesFor('8.8.8.8', linuxBox).map((a) => a.address), ['10.0.0.29']); // routed: real network
});

const id: Identity = { host: 'flixor', instance: 'Flixor', port: 80 };
const data = (record: unknown) => (record as { data: unknown }).data;

test('records answer only their own names and types', () => {
  const a = answersFor({ name: 'Flixor.local', type: 'A', class: 'IN' }, id, ['10.0.0.29']);
  assert.deepEqual(a.map((r) => [r.type, data(r)]), [['A', '10.0.0.29']]);
  const any = answersFor({ name: 'flixor.local', type: 'ANY' as 'A', class: 'IN' }, id, ['10.0.0.29']);
  assert.equal(any.length, 1);
  const ptr = answersFor({ name: '_http._tcp.local', type: 'PTR', class: 'IN' }, id, ['10.0.0.29']);
  assert.deepEqual(ptr.map(data), ['Flixor._http._tcp.local']);
  const srv = answersFor({ name: 'Flixor._http._tcp.local', type: 'SRV', class: 'IN' }, id, ['10.0.0.29']);
  assert.deepEqual(data(srv[0]), { target: 'flixor.local', port: 80, priority: 0, weight: 0 });
  assert.equal(answersFor({ name: 'other.local', type: 'A', class: 'IN' }, id, ['10.0.0.29']).length, 0);
  assert.equal(answersFor({ name: 'flixor.local', type: 'AAAA', class: 'IN' }, id, ['10.0.0.29']).length, 0);
});

test('asking for IPv6 gets a "no such record" answer, so clients use IPv4 at once', () => {
  const nsec = negativeFor({ name: 'flixor.local', type: 'AAAA', class: 'IN' }, id);
  assert.deepEqual(nsec.map((r) => [r.type, data(r)]), [['NSEC', { nextDomain: 'flixor.local', rrtypes: ['A'] }]]);
  assert.equal(negativeFor({ name: 'flixor.local', type: 'A', class: 'IN' }, id).length, 0);
  assert.equal(negativeFor({ name: 'other.local', type: 'AAAA', class: 'IN' }, id).length, 0);
});

test('goodbyes are the same records with ttl 0', () => {
  assert.ok(allRecords(id, ['10.0.0.29'], 0).every((r) => (r as { ttl?: number }).ttl === 0));
  assert.ok(allRecords(id, ['10.0.0.29']).every((r) => ((r as { ttl?: number }).ttl ?? 0) > 0));
});

test('a clash is another address claiming the name', () => {
  const response = (data: string) => ({ type: 'response' as const, answers: [{ name: 'flixor.local', type: 'A' as const, class: 'IN' as const, data }] });
  assert.equal(isConflict(response('10.0.0.66'), 'flixor', ['10.0.0.29']), true);
  assert.equal(isConflict(response('10.0.0.29'), 'flixor', ['10.0.0.29']), false); // our own answer, looped back
  assert.equal(isConflict(response('10.0.0.66'), 'flixor-2', ['10.0.0.29']), false);
});

test('names', () => {
  assert.deepEqual([0, 1, 2].map((n) => candidateName('flixor', n)), ['flixor', 'flixor-2', 'flixor-3']);
  assert.ok(isValidHostLabel('flixor'));
  assert.ok(isValidHostLabel('my-media-2'));
  assert.ok(!isValidHostLabel('-flixor'));
  assert.ok(!isValidHostLabel('flixor.home'));
  assert.ok(!isValidHostLabel('flix or'));
});

test('dns-sd output', () => {
  assert.equal(parseDnsSdLine(' 1:27:43.566  Got a reply for record flixor.local: Name now registered and active', 'flixor'), 'registered');
  assert.equal(parseDnsSdLine(' 1:27:46.716  Got a reply for record flixor.local: Name in use, please choose another', 'flixor'), 'conflict');
  assert.equal(parseDnsSdLine(' 1:27:43.566  Got a reply for service Flixor._http._tcp.local.: Name now registered and active', 'flixor'), null);
  assert.equal(parseDnsSdLine(' 1:27:43.566  Got a reply for record flixor-2.local: Name now registered and active', 'flixor'), null);
});
