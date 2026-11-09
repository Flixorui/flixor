/**
 * Whether this browser can play an addon stream. There is no transcoder, so a source
 * either plays as it is or is labelled as unplayable. Decisions come from the source
 * type, the file extension, release-name tokens and `canPlayType`. A source with no
 * negative signal counts as playable, as the addon protocol tells addons to flag the rest.
 */
import type {
  BrowserPlayability,
  PlayabilityReason,
  StremioStream,
} from './types';

const supportCache = new Map<string, boolean>();

function canPlay(type: string): boolean {
  let supported = supportCache.get(type);
  if (supported === undefined) {
    supported =
      typeof document !== 'undefined' && document.createElement('video').canPlayType(type) !== '';
    supportCache.set(type, supported);
  }
  return supported;
}

function hasMediaSource(): boolean {
  return typeof window !== 'undefined' && 'MediaSource' in window;
}

const unplayable = (reason: PlayabilityReason, label: string): BrowserPlayability => ({
  playable: false,
  reason,
  label,
});
const unsupported = (name: string) => `${name} isn't supported in this browser`;
const PLAYABLE: BrowserPlayability = { playable: true };

/** Token matchers. Letters and digits count as word characters, so `DTS` skips `HDTS`. */
const token = (body: string) => new RegExp(`(?<![a-z0-9])(?:${body})(?![a-z0-9])`, 'i');

const HEVC = token('x\\.?265|h\\.?265|hevc');
const AV1 = token('av1');
const VP9 = token('vp9');
const H264 = token('x\\.?264|h\\.?264|avc');
const HI10 = token('hi10p?|10[ ._-]?bit');
const DOLBY_VISION = token('dolby[ ._-]?vision|dovi|dv|dvhe|dvh1');
const EAC3 = token('(?:ddp|dd\\+|ddplus|e[ ._-]?ac[ ._-]?3|dolby[ ._-]?digital[ ._-]?plus)(?:[ ._-]?\\d\\.\\d)?');
const AC3 = token('(?:ac[ ._-]?3|dd[ ._-]?\\d\\.\\d|dolby[ ._-]?digital)');
const DTS = token('dts(?:[ ._-]?(?:hd|x|ma|es|hr))*|dca');
const TRUEHD = token('true[ ._-]?hd|mlp');

/** Extensions a browser may open directly, each with the type to probe. */
const PROBED_CONTAINERS: Record<string, string> = {
  mp4: 'video/mp4',
  m4v: 'video/mp4',
  mov: 'video/mp4',
  webm: 'video/webm',
  ogv: 'video/ogg',
  ogg: 'video/ogg',
  mkv: 'video/x-matroska',
};

const UNPLAYABLE_CONTAINERS = new Set([
  'avi', 'wmv', 'flv', 'mpg', 'mpeg', 'ts', 'm2ts', 'mts', 'vob', 'divx', 'rmvb', 'iso', '3gp', 'asf',
]);

function fileNameOf(stream: StremioStream): string {
  if (stream.behaviorHints?.filename) return stream.behaviorHints.filename;
  if (!stream.url) return '';
  try {
    const path = new URL(stream.url).pathname;
    return decodeURIComponent(path.slice(path.lastIndexOf('/') + 1));
  } catch {
    return '';
  }
}

function extensionOf(fileName: string): string {
  return /\.([a-z0-9]{2,5})$/i.exec(fileName)?.[1]?.toLowerCase() ?? '';
}

function classifyVideo(text: string): BrowserPlayability | null {
  if (HEVC.test(text) && !canPlay('video/mp4; codecs="hvc1.1.6.L93.B0"')) {
    return unplayable('videoCodec', unsupported('HEVC video'));
  }
  if (AV1.test(text) && !canPlay('video/mp4; codecs="av01.0.05M.08"')) {
    return unplayable('videoCodec', unsupported('AV1 video'));
  }
  if (VP9.test(text) && !canPlay('video/webm; codecs="vp9"')) {
    return unplayable('videoCodec', unsupported('VP9 video'));
  }
  if (H264.test(text) && HI10.test(text)) {
    return unplayable('videoCodec', unsupported('10-bit H.264'));
  }
  if (DOLBY_VISION.test(text) && !canPlay('video/mp4; codecs="dvh1.05.06"')) {
    return unplayable('hdrFormat', unsupported('Dolby Vision'));
  }
  return null;
}

function classifyAudio(text: string): BrowserPlayability | null {
  if (TRUEHD.test(text) && !canPlay('audio/mp4; codecs="mlpa"')) {
    return unplayable('audioCodec', unsupported('TrueHD audio'));
  }
  if (DTS.test(text) && !canPlay('audio/mp4; codecs="dtsc"')) {
    return unplayable('audioCodec', unsupported('DTS audio'));
  }
  // EAC3 first: a name with E-AC-3 also matches the plain AC3 pattern.
  if (EAC3.test(text)) {
    return canPlay('audio/mp4; codecs="ec-3"') ? null : unplayable('audioCodec', unsupported('Dolby Digital Plus audio'));
  }
  if (AC3.test(text) && !canPlay('audio/mp4; codecs="ac-3"')) {
    return unplayable('audioCodec', unsupported('Dolby Digital audio'));
  }
  return null;
}

export function classifyPlayability(stream: StremioStream): BrowserPlayability {
  switch (stream.sourceType) {
    case 'infoHash':
      return unplayable('torrent', "Torrents can't play in a browser");
    case 'nzbUrl':
      return unplayable('nzb', "NZB sources can't play in a browser");
    case 'archive':
      return unplayable('archive', "Archive sources can't play in a browser");
    case 'externalUrl':
      return unplayable('external', 'Opens outside Flixor');
    case 'ytId':
      return unplayable('external', 'Opens on YouTube');
    case 'url':
      break;
    default:
      return unplayable('unknownSource', 'Unsupported source');
  }
  if (!/^https?:\/\//i.test(stream.url ?? '')) {
    return unplayable('unknownSource', 'Unsupported link');
  }

  const fileName = fileNameOf(stream);
  const extension = extensionOf(fileName);
  const isManifest = extension === 'm3u8' || extension === 'mpd';

  if (isManifest && !hasMediaSource() && !canPlay('application/vnd.apple.mpegurl')) {
    return unplayable('container', unsupported('Adaptive streaming'));
  }
  if (UNPLAYABLE_CONTAINERS.has(extension)) {
    return unplayable('container', unsupported(`${extension.toUpperCase()} video`));
  }
  const probe = PROBED_CONTAINERS[extension];
  if (probe && !canPlay(probe)) {
    return unplayable('container', unsupported(`${extension.toUpperCase()} video`));
  }

  // Addons set this for anything that is not an MP4 served over https. The proxy covers
  // http, so only a known web container can overrule it.
  const isWebContainer = isManifest || extension === 'mp4' || extension === 'm4v' || extension === 'webm';
  if (stream.behaviorHints?.notWebReady && !isWebContainer) {
    return unplayable('notWebReady', "This source isn't ready for browser playback");
  }

  const text = [stream.name, stream.title, stream.description, stream.quality, fileName]
    .filter(Boolean)
    .join(' ');
  return classifyVideo(text) ?? classifyAudio(text) ?? PLAYABLE;
}
