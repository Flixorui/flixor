/**
 * Probe parsing and FFmpeg arguments. With the fixtures from
 * scripts/make-media-fixtures.sh and FFmpeg installed, also runs real conversions.
 * Run: npm test (in backend).
 */
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { normalizeProbe, type MediaInfo } from './probe';
import { buildPlayArgs, compatibleFilter, compatibleSize, firstPacketTime, subtitleFit, type PlayRequest } from './transcode';

const FIXTURES = path.resolve(__dirname, '../../../../.media-fixtures');
const hasFfmpeg = spawnSync('ffprobe', ['-version']).status === 0;
const fixture = (name: string) => path.join(FIXTURES, name);
const haveFixture = (name: string) => hasFfmpeg && fs.existsSync(fixture(name));

function probeFile(name: string): MediaInfo {
  const out = execFileSync('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', fixture(name)]);
  return normalizeProbe(JSON.parse(out.toString()));
}

const baseVideo = {
  index: 0, codec: 'h264', bitDepth: 8, hdr: null, dolbyVisionProfile: null, dolbyVisionCompatibility: null,
} as const;

function request(overrides: Partial<PlayRequest> = {}): PlayRequest {
  return {
    input: 'http://127.0.0.1:3001/internal/media-relay/x',
    mode: 'remux',
    start: 0,
    info: { container: 'matroska,webm', duration: 40, video: { ...baseVideo }, audio: [], subtitles: [] },
    audioIndex: 1,
    copyAudio: false,
    audioChannels: 2,
    keepDolbyVision: false,
    encoder: 'libx264',
    filters: new Set(),
    ...overrides,
  };
}

test('normalizeProbe reads Dolby Vision profile 5 from side data', () => {
  const info = normalizeProbe({
    format: { format_name: 'matroska,webm', duration: '7200.5' },
    streams: [
      {
        index: 0, codec_type: 'video', codec_name: 'hevc', pix_fmt: 'yuv420p10le', width: 3840, height: 2160,
        avg_frame_rate: '24000/1001',
        side_data_list: [{ side_data_type: 'DOVI configuration record', dv_profile: 5, dv_bl_signal_compatibility_id: 0 }],
      },
      { index: 1, codec_type: 'audio', codec_name: 'truehd', channels: 8, tags: { language: 'eng', title: 'Atmos' }, disposition: { default: 1 } },
      { index: 2, codec_type: 'subtitle', codec_name: 'hdmv_pgs_subtitle', tags: { language: 'eng' }, disposition: {} },
      { index: 3, codec_type: 'subtitle', codec_name: 'subrip', tags: { language: 'eng' }, disposition: { forced: 1 } },
    ],
  });
  assert.equal(info.duration, 7200.5);
  assert.equal(info.video?.dolbyVisionProfile, 5);
  assert.equal(info.video?.hdr, 'pq');
  assert.equal(info.video?.bitDepth, 10);
  assert.equal(info.video?.frameRate, 23.976);
  assert.deepEqual(info.audio.map((a) => [a.index, a.order, a.codec, a.channels, a.isDefault]), [[1, 0, 'truehd', 8, true]]);
  assert.deepEqual(info.subtitles.map((s) => [s.index, s.isText, s.forced]), [[2, false, false], [3, true, true]]);
});

test('normalizeProbe skips cover art and keeps the first real video stream', () => {
  const info = normalizeProbe({
    format: { format_name: 'mov,mp4', duration: '10' },
    streams: [
      { index: 0, codec_type: 'video', codec_name: 'mjpeg', disposition: { attached_pic: 1 } },
      { index: 1, codec_type: 'video', codec_name: 'h264', pix_fmt: 'yuv420p' },
    ],
  });
  assert.equal(info.video?.index, 1);
  assert.equal(info.video?.bitDepth, 8);
});

test('firstPacketTime reads the first framecrc packet in seconds', () => {
  const text = '#software: Lavf\n#tb 0: 1/1000\n#media_type 0: video\n#stream#, dts, pts, duration, size, hash\n0,      20000,      20083,       42,    12345, 0x1\n';
  assert.equal(firstPacketTime(text), 20.083);
  assert.equal(firstPacketTime('#tb 0: 1/1000\n'), null);
});

test('remux copies video, tags HEVC hvc1 and converts audio to AAC', () => {
  const args = buildPlayArgs(request({ info: { ...request().info, video: { ...baseVideo, codec: 'hevc' } } }));
  const s = args.join(' ');
  assert.match(s, /-c:v copy -bsf:v hevc_metadata -tag:v hvc1/);
  assert.match(s, /-c:a aac -b:a 192k -ac 2/);
  assert.match(s, /-noaccurate_seek/);
  assert.match(s, /frag_keyframe\+delay_moov\+default_base_moof/);
  assert.ok(args.includes('pipe:1'));
  assert.ok(!args.includes('pipe:3'));
  assert.ok(args.includes('-copyts'));
  assert.deepEqual(args.slice(-9), ['-map', '0:0', '-c:v', 'copy', '-frames:v', '1', '-f', 'framecrc', 'pipe:4']);
});

test('remux keeps Dolby Vision as dvh1 only when asked and the profile allows it', () => {
  const dv = { ...baseVideo, codec: 'hevc', hdr: 'pq' as const, dolbyVisionProfile: 5, dolbyVisionCompatibility: 0 };
  const info = { ...request().info, video: dv };
  assert.match(buildPlayArgs(request({ info, keepDolbyVision: true })).join(' '), /-bsf:v hevc_metadata -tag:v dvh1 -strict unofficial/);
  assert.match(buildPlayArgs(request({ info, keepDolbyVision: false })).join(' '), /-tag:v hvc1/);
  const p7 = { ...dv, dolbyVisionProfile: 7 };
  assert.match(buildPlayArgs(request({ info: { ...info, video: p7 }, keepDolbyVision: true })).join(' '), /-tag:v hvc1/);
});

test('copy audio, 5.1 AAC, no audio, start time and subtitle output', () => {
  assert.match(buildPlayArgs(request({ copyAudio: true })).join(' '), /-c:a copy/);
  assert.match(buildPlayArgs(request({ audioChannels: 6 })).join(' '), /-b:a 384k -ac 6/);
  const silent = buildPlayArgs(request({ audioIndex: null }));
  assert.ok(!silent.includes('-c:a'));
  assert.match(buildPlayArgs(request({ start: 62.5 })).join(' '), /-ss 62\.650 -noaccurate_seek -i /);
  const withSubs = buildPlayArgs(request({ subtitleIndex: 3 }));
  assert.deepEqual(withSubs.slice(-16, -9), ['-map', '0:3', '-c:s', 'webvtt', '-f', 'webvtt', 'pipe:3']);
});

test('compatible re-encodes to H.264 with accurate seeking and a 1080p cap', () => {
  const s = buildPlayArgs(request({ mode: 'compatible', start: 30 })).join(' ');
  assert.match(s, /-ss 30\.000 -i /);
  assert.doesNotMatch(s, /noaccurate_seek/);
  assert.match(s, /-c:v libx264 -preset veryfast/);
  assert.match(s, /scale=1920:1080/);
  const vt = buildPlayArgs(request({ mode: 'compatible', encoder: 'h264_videotoolbox' })).join(' ');
  assert.match(vt, /-c:v h264_videotoolbox/);
});

test('conversion size fits 1920x1080 and keeps the shape', () => {
  assert.deepEqual(compatibleSize({ ...baseVideo, width: 3840, height: 1608 }), { width: 1920, height: 804 });
  assert.deepEqual(compatibleSize({ ...baseVideo, width: 3840, height: 2160 }), { width: 1920, height: 1080 });
  assert.deepEqual(compatibleSize({ ...baseVideo, width: 1280, height: 720 }), { width: 1280, height: 720 });
  assert.deepEqual(compatibleSize({ ...baseVideo, width: 1440, height: 1080 }), { width: 1440, height: 1080 });
});

test('burned image subtitles fit the picture without stretching, like mpv', () => {
  // A 1920x1080 PGS canvas over a scope picture shrinks to fit its height.
  assert.deepEqual(subtitleFit({ index: 3 }, { width: 1920, height: 804 }, 'hdmv_pgs_subtitle'), { width: 1430, height: 804 });
  assert.deepEqual(subtitleFit({ index: 3 }, { width: 1920, height: 1080 }, 'dvd_subtitle'), { width: 1620, height: 1080 });
  assert.deepEqual(subtitleFit({ index: 3, width: 720, height: 576 }, { width: 1024, height: 576 }), { width: 720, height: 576 });
  const info = { ...request().info, subtitles: [{ index: 3, order: 0, codec: 'hdmv_pgs_subtitle', isDefault: false, forced: false, isText: false }] };
  const args = buildPlayArgs(request({ mode: 'compatible', info, burnSubtitle: { index: 3 } }));
  const graph = args[args.indexOf('-filter_complex') + 1];
  assert.match(graph, /\[0:0\]scale=1920:1080,format=yuv420p\[v\];\[0:3\]scale=1920:1080\[s\];\[v\]\[s\]overlay=/);
  assert.ok(args.join(' ').includes('-map [out]'));
  assert.ok(!args.includes('-vf'));
});

test('HDR tone mapping uses zscale when present, VideoToolbox on macOS otherwise', () => {
  const hdr = { ...baseVideo, codec: 'hevc', hdr: 'pq' as const, bitDepth: 10 };
  assert.match(compatibleFilter(hdr, new Set(['zscale', 'tonemap'])).vf, /tonemap=hable/);
  const vt = compatibleFilter(hdr, new Set(['scale_vt']));
  assert.deepEqual(vt.pre.slice(0, 2), ['-hwaccel', 'videotoolbox']);
  assert.match(vt.vf, /color_transfer=bt709/);
  assert.doesNotMatch(compatibleFilter({ ...baseVideo }, new Set(['zscale', 'tonemap'])).vf, /tonemap/);
});

// --- Real FFmpeg runs against the fixtures -------------------------------------------

const HTTP_ONLY = ['-rw_timeout', '-reconnect', '-reconnect_streamed', '-reconnect_on_network_error', '-reconnect_delay_max'];

/** Runs FFmpeg on a fixture; fd 3 and fd 4 outputs go to files, returned as text. */
function run(args: string[]): { video: Buffer; vtt: string; crc: string } {
  const vttPath = path.join(FIXTURES, `out-${process.pid}.vtt`);
  const crcPath = path.join(FIXTURES, `out-${process.pid}.crc`);
  const cleaned: string[] = [];
  for (let i = 0; i < args.length; i++) {
    // File inputs reject HTTP options.
    if (HTTP_ONLY.includes(args[i])) { i++; continue; }
    cleaned.push(args[i] === 'pipe:3' ? vttPath : args[i] === 'pipe:4' ? crcPath : args[i]);
  }
  const result = spawnSync('ffmpeg', ['-y', ...cleaned], { maxBuffer: 64 * 1024 * 1024 });
  assert.equal(result.status, 0, result.stderr.toString().slice(-500));
  const read = (p: string) => (fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '');
  const out = { video: result.stdout, vtt: read(vttPath), crc: read(crcPath) };
  for (const p of [vttPath, crcPath]) if (fs.existsSync(p)) fs.unlinkSync(p);
  return out;
}

function convert(name: string, overrides: Partial<PlayRequest>): { video: Buffer; vtt: string; crc: string } {
  const info = probeFile(name);
  const audio = info.audio[0];
  return run(buildPlayArgs(request({ input: fixture(name), info, audioIndex: audio?.index ?? null, ...overrides })));
}

function probeBuffer(buffer: Buffer) {
  const result = spawnSync('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', '-i', 'pipe:0'], { input: buffer });
  return normalizeProbe(JSON.parse(result.stdout.toString()));
}

for (const [name, expectVideo] of [
  ['h264-truehd.mkv', 'h264'],
  ['h264-dts.mkv', 'h264'],
  ['h264-eac3-51.mkv', 'h264'],
  ['h264-mp3.avi', 'h264'],
  ['hevc-main10-hdr10.mkv', 'hevc'],
  ['av1-opus.webm', 'av1'],
] as const) {
  test(`remux ${name} gives fragmented MP4 with ${expectVideo} and AAC`, { skip: !haveFixture(name) }, () => {
    const out = probeBuffer(convert(name, { mode: 'remux' }).video);
    assert.equal(out.video?.codec, expectVideo);
    assert.equal(out.audio[0]?.codec, 'aac');
  });
}

test('remux can copy EAC3 5.1 audio (Safari decodes it)', { skip: !haveFixture('h264-eac3-51.mkv') }, () => {
  const out = probeBuffer(convert('h264-eac3-51.mkv', { mode: 'remux', copyAudio: true }).video);
  assert.equal(out.audio[0]?.codec, 'eac3');
  assert.equal(out.audio[0]?.channels, 6);
});

test('HLS output writes fMP4 segments and an EVENT playlist (Safari)', { skip: !haveFixture('h264-eac3-51.mkv') }, () => {
  const dir = fs.mkdtempSync(path.join(FIXTURES, 'hls-'));
  try {
    const info = probeFile('h264-eac3-51.mkv');
    const args = buildPlayArgs(request({ input: fixture('h264-eac3-51.mkv'), info, audioIndex: info.audio[0].index, copyAudio: true, hlsDir: dir }));
    assert.ok(!args.includes('pipe:1'));
    assert.deepEqual(args.slice(args.indexOf('-f'), args.indexOf('-f') + 2), ['-f', 'hls']);
    run(args);
    const playlist = fs.readFileSync(path.join(dir, 'index.m3u8'), 'utf8');
    assert.match(playlist, /#EXT-X-PLAYLIST-TYPE:EVENT/);
    assert.match(playlist, /#EXT-X-MAP:URI="init.mp4"/);
    assert.match(playlist, /seg00000\.m4s/);
    const out = probeBuffer(fs.readFileSync(path.join(dir, 'init.mp4')));
    assert.equal(out.audio[0]?.codec, 'eac3');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('compatible converts HDR10 HEVC to 8-bit H.264', { skip: !haveFixture('hevc-main10-hdr10.mkv') }, () => {
  const tools = execFileSync('ffmpeg', ['-hide_banner', '-filters']).toString();
  const filters = new Set(['zscale', 'tonemap', 'scale_vt'].filter((f) => new RegExp(`\\s${f}\\s`).test(tools)));
  if (process.platform === 'darwin') assert.ok(filters.has('scale_vt') || filters.has('zscale'), 'a tone mapper is available');
  const out = probeBuffer(convert('hevc-main10-hdr10.mkv', { mode: 'compatible', filters }).video);
  assert.equal(out.video?.codec, 'h264');
  assert.equal(out.video?.bitDepth, 8);
});

/** First and last video packet times; fragmented MP4 on a pipe reports no reliable duration. */
function videoSpan(buffer: Buffer): [number, number] {
  const result = spawnSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'packet=pts_time', '-of', 'csv=p=0', '-i', 'pipe:0'], { input: buffer, maxBuffer: 64 * 1024 * 1024 });
  const times = result.stdout.toString().trim().split('\n').map(Number).filter(Number.isFinite);
  return [Math.min(...times), Math.max(...times)];
}

test('remux started at the 20 s key frame begins at 0 and runs 20 s', { skip: !haveFixture('h264-truehd.mkv') }, () => {
  const out = convert('h264-truehd.mkv', { mode: 'remux', start: 20 });
  const [first, last] = videoSpan(out.video);
  // The first frame sits a B-frame delay (about 0.1 s) after 0.
  assert.ok(first < 0.15, `first ${first}`);
  assert.ok(Math.abs(last - 20) < 0.2, `last ${last}`);
  // fd 4 reports the key frame on the film's timeline.
  const start = firstPacketTime(out.crc);
  assert.ok(start !== null && Math.abs(start - 20) < 0.1, `start ${start}`);
});

test('compatible started at 21 s runs exactly 19 s', { skip: !haveFixture('h264-aac.mkv') }, () => {
  const [first, last] = videoSpan(convert('h264-aac.mkv', { mode: 'compatible', start: 21 }).video);
  assert.ok(first < 0.1, `first ${first}`);
  assert.ok(Math.abs(last - 19) < 0.2, `last ${last}`);
});

// h264-pgs.mkv is a short local clip with a PGS track (FFmpeg can't create image
// subtitles from text, so the fixture script can't make one). Skipped without it.
test('HDR conversion with a burned PGS subtitle runs', { skip: !haveFixture('hdr-pgs.mkv') }, () => {
  const tools = execFileSync('ffmpeg', ['-hide_banner', '-filters']).toString();
  const filters = new Set(['zscale', 'tonemap', 'scale_vt'].filter((f) => new RegExp(`\\s${f}\\s`).test(tools)));
  const info = probeFile('hdr-pgs.mkv');
  if (info.video) info.video.hdr = 'pq';
  const sub = info.subtitles[0];
  const out = probeBuffer(convert('hdr-pgs.mkv', { mode: 'compatible', info, filters, burnSubtitle: { index: sub.index, width: sub.width, height: sub.height } }).video);
  assert.equal(out.video?.codec, 'h264');
  assert.equal(out.video?.bitDepth, 8);
});

test('PGS burn-in draws the subtitle into converted video', { skip: !haveFixture('h264-pgs.mkv') }, () => {
  const info = probeFile('h264-pgs.mkv');
  const sub = info.subtitles[0];
  assert.equal(sub.isText, false);
  assert.deepEqual([sub.width, sub.height], [1920, 1080]);
  const blank = convert('h264-pgs.mkv', { mode: 'compatible', info });
  const burned = convert('h264-pgs.mkv', { mode: 'compatible', info, burnSubtitle: { index: sub.index, width: sub.width, height: sub.height } });
  // At 5 s a subtitle is on screen; the frames differ only where it is drawn.
  const frame = (buffer: Buffer) => spawnSync('ffmpeg', ['-v', 'error', '-i', 'pipe:0', '-ss', '5', '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'gray', '-'], { input: buffer, maxBuffer: 256 * 1024 * 1024 }).stdout;
  const a = frame(blank.video);
  const b = frame(burned.video);
  assert.equal(a.length, b.length);
  let changed = 0;
  for (let i = 0; i < a.length; i++) if (Math.abs(a[i] - b[i]) > 40) changed++;
  assert.ok(changed > 1000, `changed pixels ${changed}`);
});

test('subtitle track is written as WebVTT next to the video', { skip: !haveFixture('multi-audio-subs.mkv') }, () => {
  const info = probeFile('multi-audio-subs.mkv');
  assert.deepEqual(info.audio.map((a) => [a.codec, a.language]), [['aac', 'eng'], ['ac3', 'spa']]);
  assert.deepEqual(info.subtitles.map((s) => [s.codec, s.isText]), [['subrip', true], ['subrip', true]]);
  const { vtt } = run(buildPlayArgs(request({ input: fixture('multi-audio-subs.mkv'), info, audioIndex: info.audio[1].index, subtitleIndex: info.subtitles[0].index, start: 20 })));
  assert.match(vtt, /WEBVTT/);
  // Cues keep the film's timeline (-copyts), so the player adds no offset.
  assert.match(vtt, /00:(?:00:)?20\.000 --> 00:(?:00:)?24\.000/);
  assert.match(vtt, /English line at twenty/);
  assert.doesNotMatch(vtt, /English line one/);
});
