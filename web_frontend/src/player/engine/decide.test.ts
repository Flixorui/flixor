/** Decision table for the player engine. Run: npm test (in web_frontend). */
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decidePlayback, type BrowserCaps, type Decision, type MediaInfo, type VideoInfo } from './decide';

const CHROME: BrowserCaps = {
  mp4: true, webm: true, mkv: true, h264: true, hevc: true, hevc10: true, av1: true, av1_10: true, vp9: true,
  dolbyVision: false, aac: true, mp3: true, opus: true, flac: true, ac3: false, eac3: false,
};
const SAFARI: BrowserCaps = { ...CHROME, mkv: false, webm: true, dolbyVision: true, ac3: true, eac3: true, opus: true };
const OLD_CHROME: BrowserCaps = { ...CHROME, hevc: false, hevc10: false };

function file(overrides: Omit<Partial<MediaInfo>, 'video'> & { video?: Partial<VideoInfo> } = {}): MediaInfo {
  const { video, ...rest } = overrides;
  return {
    container: 'matroska,webm',
    duration: 7200,
    video: { index: 0, codec: 'h264', bitDepth: 8, hdr: null, dolbyVisionProfile: null, dolbyVisionCompatibility: null, ...video },
    audio: [{ index: 1, order: 0, codec: 'aac', channels: 2, isDefault: true }],
    subtitles: [],
    ...rest,
  };
}

const truehd = [{ index: 1, order: 0, codec: 'truehd', channels: 8, isDefault: true }];

test('H.264 + AAC in MKV plays directly in Chrome, remuxed in Safari', () => {
  assert.equal(decidePlayback(file(), CHROME).path, 'direct');
  const safari: Decision = decidePlayback(file(), SAFARI);
  assert.ok(safari.path === 'remux' && safari.copyAudio);
});

test('MP4 plays directly everywhere', () => {
  assert.equal(decidePlayback(file({ container: 'mov,mp4,m4a,3gp,3g2,mj2' }), SAFARI).path, 'direct');
});

test('TrueHD Atmos REMUX: video copied, audio converted to 5.1 AAC', () => {
  const d: Decision = decidePlayback(file({ audio: truehd }), CHROME);
  if (d.path !== 'remux') return assert.fail(d.path);
  assert.equal(d.copyAudio, false);
  assert.equal(d.audioChannels, 6);
  assert.match(d.reason, /TRUEHD audio converted/);
});

test('DTS and AC3 convert in Chrome; Safari copies AC3', () => {
  const dts = decidePlayback(file({ audio: [{ index: 1, order: 0, codec: 'dts', channels: 6, isDefault: true }] }), CHROME);
  assert.ok(dts.path === 'remux' && !dts.copyAudio);
  const ac3 = [{ index: 1, order: 0, codec: 'ac3', channels: 6, isDefault: true }];
  const chrome = decidePlayback(file({ audio: ac3 }), CHROME);
  assert.ok(chrome.path === 'remux' && !chrome.copyAudio);
  const safari = decidePlayback(file({ audio: ac3, container: 'mov,mp4' }), SAFARI);
  assert.equal(safari.path, 'direct');
});

test('AVI always remuxes', () => {
  const d = decidePlayback(file({ container: 'avi', audio: [{ index: 1, order: 0, codec: 'mp3', channels: 2, isDefault: true }] }), CHROME);
  assert.ok(d.path === 'remux' && d.copyAudio);
});

test('HEVC 10-bit HDR keeps HDR where HEVC decodes, converts where it does not', () => {
  const hdr = file({ video: { codec: 'hevc', bitDepth: 10, hdr: 'pq' } });
  assert.equal(decidePlayback(hdr, CHROME).path, 'direct');
  const old: Decision = decidePlayback(hdr, OLD_CHROME);
  if (old.path !== 'compatible') return assert.fail(old.path);
  assert.match(old.reason, /HDR converted/);
});

test('Dolby Vision 5: Safari keeps it as dvh1, Chrome refuses with a reason', () => {
  const dv5 = file({ video: { codec: 'hevc', bitDepth: 10, hdr: 'pq', dolbyVisionProfile: 5, dolbyVisionCompatibility: 0 }, audio: truehd });
  const safari = decidePlayback(dv5, SAFARI);
  assert.ok(safari.path === 'remux' && safari.keepDolbyVision);
  const chrome = decidePlayback(dv5, CHROME);
  assert.equal(chrome.path, 'unsupported');
  assert.match(chrome.reason, /profile 5/);
});

test('Dolby Vision 5 never falls back to conversion, even in Safari', () => {
  const dv5 = file({ video: { codec: 'hevc', bitDepth: 10, hdr: 'pq', dolbyVisionProfile: 5, dolbyVisionCompatibility: 0 } });
  assert.equal(decidePlayback(dv5, SAFARI, { avoidDirect: true, avoidRemux: true }).path, 'unsupported');
  assert.equal(decidePlayback(dv5, SAFARI, { burnSubtitle: true }).path, 'unsupported');
});

test('Safari remux of EAC3 audio copies it instead of converting', () => {
  const d: Decision = decidePlayback(file({ audio: [{ index: 1, order: 0, codec: 'eac3', channels: 6, isDefault: true }] }), SAFARI);
  if (d.path !== 'remux') return assert.fail(d.path);
  assert.equal(d.copyAudio, true);
});

test('Dolby Vision 8 plays as HDR10 HEVC in Chrome', () => {
  const dv8 = file({ video: { codec: 'hevc', bitDepth: 10, hdr: 'pq', dolbyVisionProfile: 8, dolbyVisionCompatibility: 1 } });
  const d = decidePlayback(dv8, CHROME);
  assert.ok(d.path === 'direct' && !d.keepDolbyVision);
});

test('picking a non-default audio track or an embedded subtitle forces remux', () => {
  const two = file({ audio: [
    { index: 1, order: 0, codec: 'aac', channels: 2, isDefault: true, language: 'eng' },
    { index: 2, order: 1, codec: 'aac', channels: 2, isDefault: false, language: 'spa' },
  ] });
  assert.equal(decidePlayback(two, CHROME).path, 'direct');
  const spanish = decidePlayback(two, CHROME, { audioIndex: 2 });
  assert.ok(spanish.path === 'remux' && spanish.audioIndex === 2);
  assert.equal(decidePlayback(two, CHROME, { embeddedSubtitle: true }).path, 'remux');
});

test('a burned image subtitle needs conversion, even for a direct-play file', () => {
  const d: Decision = decidePlayback(file(), CHROME, { burnSubtitle: true });
  if (d.path !== 'compatible') return assert.fail(d.path);
  assert.match(d.reason, /image subtitle/);
});

test('fallbacks: avoidDirect gives remux, avoidRemux gives compatible', () => {
  assert.equal(decidePlayback(file(), CHROME, { avoidDirect: true }).path, 'remux');
  assert.equal(decidePlayback(file(), CHROME, { avoidDirect: true, avoidRemux: true }).path, 'compatible');
});

test('MPEG-2 / VC-1 video converts; no video is unsupported', () => {
  assert.equal(decidePlayback(file({ video: { codec: 'vc1' } }), CHROME).path, 'compatible');
  assert.equal(decidePlayback({ ...file(), video: null }, CHROME).path, 'unsupported');
});
