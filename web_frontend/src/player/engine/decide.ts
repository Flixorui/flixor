/**
 * Picks how to play a probed file in this browser: as it is (direct), with the video
 * copied and the audio converted (remux), or fully converted to H.264 (compatible).
 *
 * Pure, so it can be tested with made-up capabilities. Mirrors the backend's
 * services/media/probe.ts types.
 */

export interface VideoInfo {
  index: number;
  codec: string;
  profile?: string;
  width?: number;
  height?: number;
  bitDepth: number;
  hdr: 'pq' | 'hlg' | null;
  dolbyVisionProfile: number | null;
  dolbyVisionCompatibility: number | null;
}

export interface AudioTrackInfo {
  index: number;
  order: number;
  codec: string;
  profile?: string;
  channels: number;
  language?: string;
  title?: string;
  isDefault: boolean;
}

export interface SubtitleTrackInfo {
  index: number;
  order: number;
  codec: string;
  language?: string;
  title?: string;
  isDefault: boolean;
  forced: boolean;
  isText: boolean;
  width?: number;
  height?: number;
}

export interface MediaInfo {
  container: string;
  duration: number;
  bitRate?: number;
  video: VideoInfo | null;
  audio: AudioTrackInfo[];
  subtitles: SubtitleTrackInfo[];
}

/** What this browser decodes. See capabilities.ts. */
export interface BrowserCaps {
  /** Containers `<video>` opens directly. */
  mp4: boolean;
  webm: boolean;
  mkv: boolean;
  h264: boolean;
  /** 8-bit HEVC Main. */
  hevc: boolean;
  /** 10-bit HEVC Main10 (HDR10). */
  hevc10: boolean;
  av1: boolean;
  av1_10: boolean;
  vp9: boolean;
  /** Dolby Vision single layer (dvh1), e.g. Safari on a Mac. */
  dolbyVision: boolean;
  aac: boolean;
  mp3: boolean;
  opus: boolean;
  flac: boolean;
  ac3: boolean;
  eac3: boolean;
}

export type PlaybackPath = 'direct' | 'remux' | 'compatible';

export type Decision =
  | {
      path: PlaybackPath;
      /** Stream index of the audio to play, or null when the file has none. */
      audioIndex: number | null;
      /** Remux: keep the audio as it is instead of converting to AAC. */
      copyAudio: boolean;
      audioChannels: 2 | 6;
      /** Remux: keep Dolby Vision signalling (dvh1). */
      keepDolbyVision: boolean;
      /** Why this path, for the stats panel. */
      reason: string;
    }
  | { path: 'unsupported'; reason: string };

/** A decision that plays (not 'unsupported'). */
export type PlayDecision = Exclude<Decision, { path: 'unsupported' }>;

export interface Choice {
  /** Stream index of the audio the user picked; default track otherwise. */
  audioIndex?: number | null;
  /** An embedded text subtitle is on; direct play can't show those. */
  embeddedSubtitle?: boolean;
  /** Skip direct play, after it failed for this file. */
  avoidDirect?: boolean;
  /** Skip remux too, after it failed. */
  avoidRemux?: boolean;
  /** An image subtitle (PGS, VobSub) is drawn into the picture, which needs conversion. */
  burnSubtitle?: boolean;
}

/** Video the browser decodes, inside an MP4 written by FFmpeg. */
export function canDecodeVideo(video: VideoInfo, caps: BrowserCaps): boolean {
  switch (video.codec) {
    case 'h264':
      return caps.h264 && video.bitDepth <= 8;
    case 'hevc':
      if (video.dolbyVisionProfile === 5) return caps.dolbyVision;
      return video.bitDepth > 8 ? caps.hevc10 : caps.hevc;
    case 'av1':
      return video.bitDepth > 8 ? caps.av1_10 : caps.av1;
    case 'vp9':
      return caps.vp9;
    default:
      return false;
  }
}

/** Audio the browser decodes inside MP4 (so remux can copy it). */
export function canDecodeAudio(codec: string, caps: BrowserCaps): boolean {
  switch (codec) {
    case 'aac': return caps.aac;
    case 'mp3': return caps.mp3;
    case 'opus': return caps.opus;
    case 'flac': return caps.flac;
    case 'ac3': return caps.ac3;
    case 'eac3': return caps.eac3;
    default: return false;
  }
}

/** Whether `<video>` opens this container itself. */
function containerOpens(info: MediaInfo, caps: BrowserCaps): boolean {
  const name = info.container;
  if (/\bmov\b|\bmp4\b/.test(name)) return caps.mp4;
  if (/matroska|webm/.test(name)) {
    // FFmpeg names both "matroska,webm". WebM-only codecs open as WebM.
    const webmOnly = (!info.video || ['vp8', 'vp9', 'av1'].includes(info.video.codec))
      && info.audio.every((a) => a.codec === 'opus' || a.codec === 'vorbis');
    return caps.mkv || (webmOnly && caps.webm);
  }
  return false;
}

/** The track the browser itself would play: the default one, else the first. */
function browserAudioTrack(info: MediaInfo): AudioTrackInfo | undefined {
  return info.audio.find((a) => a.isDefault) ?? info.audio[0];
}

export function decidePlayback(info: MediaInfo, caps: BrowserCaps, choice: Choice = {}): Decision {
  const video = info.video;
  if (!video) return { path: 'unsupported', reason: 'This source has no video.' };

  const wanted = choice.audioIndex === null
    ? undefined
    : info.audio.find((a) => a.index === choice.audioIndex) ?? browserAudioTrack(info);
  const audioIndex = wanted?.index ?? null;
  const audioOk = !wanted || canDecodeAudio(wanted.codec, caps);
  const videoOk = canDecodeVideo(video, caps);
  const audioChannels: 2 | 6 = (wanted?.channels ?? 2) >= 6 ? 6 : 2;

  if (video.dolbyVisionProfile === 5 && !caps.dolbyVision) {
    // Profile 5 has no HDR10 or SDR base layer, so converting it without Dolby's
    // reshaping gives wrong colours. Netflix and Prime only send it to devices that decode it.
    return { path: 'unsupported', reason: "This source is Dolby Vision profile 5, which this browser can't show. Choose another source, or play it in Safari or the Mac app." };
  }

  const common = { audioIndex, audioChannels, keepDolbyVision: caps.dolbyVision && video.dolbyVisionProfile !== null };

  // Profile 5 can only be shown untouched; conversion can't map its colours.
  const dv5 = video.dolbyVisionProfile === 5;
  if (dv5 && (choice.avoidRemux || choice.burnSubtitle)) {
    return {
      path: 'unsupported',
      reason: choice.burnSubtitle
        ? "Image subtitles can't be drawn on this Dolby Vision profile 5 source. Choose a text subtitle or another source."
        : "This Dolby Vision profile 5 source couldn't be played. Choose another source.",
    };
  }

  if (videoOk && audioOk && !choice.avoidDirect && !choice.embeddedSubtitle && !choice.burnSubtitle
    && containerOpens(info, caps) && wanted === browserAudioTrack(info)) {
    return { path: 'direct', ...common, copyAudio: true, reason: 'The browser plays this file as it is.' };
  }
  if (videoOk && !choice.avoidRemux && !choice.burnSubtitle) {
    return {
      path: 'remux',
      ...common,
      copyAudio: audioOk,
      reason: audioOk
        ? 'Repackaged for the browser; video and audio unchanged.'
        : `Video unchanged; ${wanted?.codec.toUpperCase()} audio converted to AAC.`,
    };
  }
  return {
    path: 'compatible',
    ...common,
    keepDolbyVision: false,
    copyAudio: false,
    reason: choice.burnSubtitle && videoOk
      ? 'Converted to H.264 to draw the image subtitle into the picture.'
      : video.hdr
        ? `${video.codec.toUpperCase()} HDR converted to H.264 SDR.`
        : `${video.codec.toUpperCase()} video converted to H.264.`,
  };
}
