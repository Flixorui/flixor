/**
 * FFmpeg argument lists for the web player. Pure functions, so they can be tested
 * without FFmpeg.
 *
 * Output is fragmented MP4 on stdout, which `<video>` plays progressively. Seeking
 * starts a new conversion at the new position (see keyframeAtOrBefore).
 */
import type { MediaInfo, VideoInfo } from './probe';
import type { VideoEncoder } from './ffmpeg';

export type PlayMode = 'remux' | 'compatible';

export interface PlayRequest {
  input: string;
  mode: PlayMode;
  /** Seconds. For remux, a key frame time from keyframeAtOrBefore. */
  start: number;
  info: MediaInfo;
  /** Stream index of the audio track to play, or null for none. */
  audioIndex: number | null;
  /** Keep the audio as it is (the browser decodes it); otherwise AAC. */
  copyAudio: boolean;
  /** AAC channel count: 2, or 6 when the browser takes 5.1 AAC. */
  audioChannels: 2 | 6;
  /** Remux only: keep Dolby Vision signalling (dvh1) for browsers that decode it. */
  keepDolbyVision: boolean;
  encoder: VideoEncoder;
  /** Filters this FFmpeg has, for picking a tone mapper. */
  filters: Set<string>;
  /** Stream index of a text subtitle to also write as WebVTT on fd 3. */
  subtitleIndex?: number | null;
  /** Compatible only: an image subtitle (PGS, VobSub) to draw into the picture. */
  burnSubtitle?: { index: number; width?: number; height?: number } | null;
  /**
   * Write HLS (fMP4 segments plus a playlist) into this folder instead of one MP4 on
   * stdout. Safari only plays progressive video from servers with byte ranges, which a
   * live conversion can't offer, but it plays HLS natively.
   */
  hlsDir?: string;
}

function hlsOutput(dir: string): string[] {
  return [
    '-f', 'hls',
    '-hls_time', '2',
    '-hls_playlist_type', 'event',
    '-hls_segment_type', 'fmp4',
    '-hls_fmp4_init_filename', 'init.mp4',
    '-hls_segment_filename', `${dir}/seg%05d.m4s`,
    '-hls_flags', 'independent_segments+temp_file',
    `${dir}/index.m3u8`,
  ];
}

/** Even output size for conversion: within 1920×1080, same shape as the source. */
export function compatibleSize(video: VideoInfo): { width: number; height: number } {
  const srcW = video.width ?? 1920;
  const srcH = video.height ?? 1080;
  const scale = Math.min(1, COMPATIBLE_MAX_WIDTH / srcW, COMPATIBLE_MAX_HEIGHT / srcH);
  const even = (n: number) => Math.max(2, Math.round(n / 2) * 2);
  return { width: even(srcW * scale), height: even(srcH * scale) };
}

/**
 * Where a burned subtitle canvas goes: scaled to fit the picture without stretching,
 * centred, as mpv draws image subtitles. Canvas size defaults by codec.
 */
export function subtitleFit(burn: NonNullable<PlayRequest['burnSubtitle']>, out: { width: number; height: number }, codec?: string) {
  const canvasW = burn.width ?? (codec === 'dvd_subtitle' ? 720 : 1920);
  const canvasH = burn.height ?? (codec === 'dvd_subtitle' ? 480 : 1080);
  const scale = Math.min(out.width / canvasW, out.height / canvasH);
  return { width: Math.max(2, Math.round((canvasW * scale) / 2) * 2), height: Math.max(2, Math.round((canvasH * scale) / 2) * 2) };
}

const COMPATIBLE_MAX_HEIGHT = 1080;
const COMPATIBLE_MAX_WIDTH = 1920;
/** Seconds past a key frame to seek to, so FFmpeg lands on it and not the one before. */
export const REMUX_SEEK_NUDGE = 0.15;

function inputArgs(input: string, start: number, accurate: boolean): string[] {
  return [
    '-hide_banner', '-loglevel', 'error', '-nostdin',
    // Original timestamps: the side output on fd 4 reports where copied video really
    // starts, and subtitle cues come out on the film's own timeline.
    '-copyts',
    '-rw_timeout', '20000000',
    '-reconnect', '1', '-reconnect_streamed', '1', '-reconnect_on_network_error', '1', '-reconnect_delay_max', '5',
    // The probe already knows the streams; skip FFmpeg's own long analysis on (re)start.
    '-probesize', '2000000', '-analyzeduration', '0',
    ...(start > 0 ? ['-ss', start.toFixed(3)] : []),
    ...(accurate ? [] : ['-noaccurate_seek']),
    '-i', input,
  ];
}

/** Dolby Vision profiles whose video can be copied as dvh1 (single layer). */
export function canKeepDolbyVision(video: VideoInfo): boolean {
  return video.codec === 'hevc' && (video.dolbyVisionProfile === 5 || video.dolbyVisionProfile === 8);
}

function remuxVideoArgs(video: VideoInfo, keepDolbyVision: boolean): string[] {
  const args = ['-c:v', 'copy'];
  if (video.codec === 'hevc') {
    // Some releases carry HEVC parameter sets only inline, with an almost empty hvcC.
    // hvc1/dvh1 need them in hvcC, and Apple's decoder (Safari) refuses the file
    // without them. hevc_metadata rebuilds hvcC from the stream; nothing is re-encoded.
    args.push('-bsf:v', 'hevc_metadata');
    if (keepDolbyVision && canKeepDolbyVision(video)) args.push('-tag:v', 'dvh1', '-strict', 'unofficial');
    else args.push('-tag:v', 'hvc1');
  } else if (video.codec === 'h264') {
    args.push('-tag:v', 'avc1');
  }
  return args;
}

/** The scale (and tone map) filter for conversion. Exported for tests. */
export function compatibleFilter(video: VideoInfo, filters: Set<string>): { pre: string[]; vf: string } {
  const { width, height } = compatibleSize(video);
  const scale = `scale=${width}:${height}`;
  if (!video.hdr) return { pre: [], vf: `${scale},format=yuv420p` };
  if (filters.has('zscale') && filters.has('tonemap')) {
    return {
      pre: [],
      vf: [
        `zscale=w=${width}:h=${height}:t=linear:npl=100`,
        'format=gbrpf32le',
        'zscale=p=bt709',
        'tonemap=hable:desat=0',
        'zscale=t=bt709:m=bt709:r=tv',
        'format=yuv420p',
      ].join(','),
    };
  }
  if (filters.has('scale_vt')) {
    // macOS without zimg: VideoToolbox decodes and converts PQ/HLG to SDR BT.709 on the GPU.
    return {
      pre: ['-hwaccel', 'videotoolbox', '-hwaccel_output_format', 'videotoolbox_vld'],
      // VideoToolbox hands back 10-bit frames from HDR sources: download as p010, then 8-bit.
      vf: `scale_vt=w=${width}:h=${height}:color_matrix=bt709:color_primaries=bt709:color_transfer=bt709,hwdownload,format=p010le,format=yuv420p`,
    };
  }
  // No tone mapper: colours will look flat, but it still plays.
  return { pre: [], vf: `${scale},format=yuv420p` };
}

function compatibleVideoArgs(video: VideoInfo, encoder: VideoEncoder, picture: string[]): string[] {
  const height = Math.min(video.height ?? COMPATIBLE_MAX_HEIGHT, COMPATIBLE_MAX_HEIGHT);
  const codec = encoder === 'h264_videotoolbox'
    // No -realtime: encoding ahead of playback is what builds the player's buffer.
    ? ['-c:v', 'h264_videotoolbox', '-b:v', height > 720 ? '8M' : '5M', '-maxrate', height > 720 ? '12M' : '7M', '-allow_sw', '1']
    : ['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '21', '-maxrate', '12M', '-bufsize', '24M'];
  return [
    ...picture,
    ...codec,
    '-profile:v', 'high',
    '-force_key_frames', 'expr:gte(t,n_forced*2)',
    '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
  ];
}

function audioArgs(request: PlayRequest): string[] {
  if (request.audioIndex === null) return [];
  if (request.copyAudio) return ['-c:a', 'copy'];
  const channels = request.audioChannels;
  return ['-c:a', 'aac', '-b:a', channels === 6 ? '384k' : '192k', '-ac', String(channels)];
}

export function buildPlayArgs(request: PlayRequest): string[] {
  const video = request.info.video;
  if (!video) throw new Error('No video stream');
  const remux = request.mode === 'remux';
  const filter = remux ? null : compatibleFilter(video, request.filters);
  // Picture: a plain filter, or with a burned image subtitle a graph that scales the
  // subtitle canvas to the converted picture and lays it on top.
  let picture: string[] = [];
  let videoMap = ['-map', `0:${video.index}`];
  if (filter) {
    const burn = request.burnSubtitle;
    if (burn) {
      const codec = request.info.subtitles.find((s) => s.index === burn.index)?.codec;
      const fit = subtitleFit(burn, compatibleSize(video), codec);
      picture = ['-filter_complex', `[0:${video.index}]${filter.vf}[v];[0:${burn.index}]scale=${fit.width}:${fit.height}[s];[v][s]overlay=(W-w)/2:(H-h)/2:eof_action=pass,format=yuv420p[out]`];
      videoMap = ['-map', '[out]'];
    } else {
      picture = ['-vf', filter.vf];
    }
  }
  const args = [
    ...(filter?.pre ?? []),
    // Copied video starts at the key frame at or before `start`; fd 4 reports which.
    // A key frame's display time sits a little after its time in the index (B-frame
    // reordering), so aim just past `start` to land on one exactly there.
    ...inputArgs(request.input, remux && request.start > 0 ? request.start + REMUX_SEEK_NUDGE : request.start, !remux),
    ...videoMap,
    ...(request.audioIndex !== null ? ['-map', `0:${request.audioIndex}`] : []),
    '-map_metadata', '-1', '-map_chapters', '-1', '-dn',
    ...(remux ? remuxVideoArgs(video, request.keepDolbyVision) : compatibleVideoArgs(video, request.encoder, picture)),
    ...audioArgs(request),
    '-max_muxing_queue_size', '4096',
    '-avoid_negative_ts', 'make_zero',
    ...(request.hlsDir
      ? hlsOutput(request.hlsDir)
      : [
          // Small fragments: the browser starts once it has a whole fragment, so 2 s of
          // 4K video (about 10 MB) would delay every start and seek.
          // delay_moov: the header waits for the first fragment, so copied EAC3/AC3 audio
          // has been parsed (empty_moov fails with "Cannot write moov atom before EAC3 packets parsed").
          '-movflags', 'frag_keyframe+delay_moov+default_base_moof',
          '-frag_duration', '500000',
          '-f', 'mp4', 'pipe:1',
        ]),
  ];
  if (request.subtitleIndex !== null && request.subtitleIndex !== undefined) {
    args.push('-map', `0:${request.subtitleIndex}`, '-c:s', 'webvtt', '-f', 'webvtt', 'pipe:3');
  }
  // The first video packet's time, as `framecrc` text on fd 4 (see firstPacketTime).
  args.push('-map', `0:${video.index}`, '-c:v', 'copy', '-frames:v', '1', '-f', 'framecrc', 'pipe:4');
  return args;
}

/**
 * Pure: the first packet's presentation time in seconds from `framecrc` output
 * ("#tb 0: 1/1000" then "0, dts, pts, duration, size, crc"), or null.
 */
export function firstPacketTime(text: string): number | null {
  const tb = /#tb 0:\s*(\d+)\/(\d+)/.exec(text);
  if (!tb) return null;
  for (const line of text.split('\n')) {
    if (line.startsWith('#') || !line.trim()) continue;
    const fields = line.split(',').map((f) => f.trim());
    if (fields.length < 3) continue;
    const pts = Number(fields[2]);
    if (!Number.isFinite(pts)) continue;
    return (pts * Number(tb[1])) / Number(tb[2]);
  }
  return null;
}
