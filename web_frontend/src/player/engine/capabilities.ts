/** What this browser's `<video>` decodes, for decide.ts. Asked once per page. */
import type { BrowserCaps } from './decide';

let cached: BrowserCaps | null = null;

/**
 * Safari (WebKit, not Chromium) only plays progressive video from servers with byte
 * ranges, which a live conversion can't offer; it gets conversions as HLS instead.
 */
export function prefersHlsDelivery(): boolean {
  const ua = navigator.userAgent;
  return /AppleWebKit/.test(ua) && !/Chrome|Chromium|CriOS|Edg|FxiOS|Android/.test(ua)
    && document.createElement('video').canPlayType('application/vnd.apple.mpegurl') !== '';
}

export function browserCaps(): BrowserCaps {
  if (cached) return cached;
  const video = document.createElement('video');
  const can = (type: string) => video.canPlayType(type) !== '';
  const mp4 = (codecs: string) => can(`video/mp4; codecs="${codecs}"`);
  cached = {
    mp4: can('video/mp4'),
    webm: can('video/webm'),
    mkv: can('video/x-matroska; codecs="avc1.640028, mp4a.40.2"'),
    h264: mp4('avc1.640028'),
    hevc: mp4('hvc1.1.6.L120.90'),
    hevc10: mp4('hvc1.2.4.L153.B0'),
    av1: mp4('av01.0.08M.08'),
    av1_10: mp4('av01.0.08M.10'),
    vp9: mp4('vp09.00.40.08') || can('video/webm; codecs="vp9"'),
    dolbyVision: mp4('dvh1.05.06'),
    aac: mp4('mp4a.40.2'),
    mp3: mp4('mp4a.6B') || can('audio/mpeg'),
    opus: mp4('opus'),
    flac: mp4('flac'),
    ac3: mp4('ac-3'),
    eac3: mp4('ec-3'),
  };
  return cached;
}
