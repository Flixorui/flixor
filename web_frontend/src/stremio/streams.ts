/** Stream and subtitle requests across installed addons. */
import { getSettings } from '@/state/settings';
import {
  addonSupportsResource,
  listInstalledAddons,
  type InstalledAddon,
} from './addons';
import { fetchAddonJson, fetchSubtitleFile, isMixedContent, requestStreamProxyUrl } from './transport';
import type {
  StremioAddonStreams,
  StremioContentIdentity,
  StremioRequestOptions,
  StremioSourceType,
  StremioStream,
  StremioStreamRequestOptions,
  StremioSubtitle,
  StremioSubtitleRequestOptions,
} from './types';

const SIZE_IN_TEXT = /(\d+(?:\.\d+)?)\s*(GB|MB|TB)\b/i;
const SIZE_UNITS: Record<string, number> = { MB: 1e6, GB: 1e9, TB: 1e12 };

/** Replaces only the path, so a query string on the manifest URL survives. */
export function addonResourceUrl(addon: InstalledAddon, resourcePath: string): string {
  const url = new URL(addon.manifestUrl);
  url.pathname = url.pathname.replace(/\/manifest\.json$/i, '').replace(/\/$/, '') + resourcePath;
  return url.href;
}

function detectSourceType(raw: any): StremioSourceType {
  if (typeof raw?.url === 'string') return 'url';
  if (raw?.externalUrl) return 'externalUrl';
  if (raw?.ytId) return 'ytId';
  if (raw?.infoHash) return 'infoHash';
  if (raw?.nzbUrl) return 'nzbUrl';
  if (['rarUrls', 'zipUrls', '7zipUrls', 'tgzUrls', 'tarUrls'].some((key) => Array.isArray(raw?.[key]) && raw[key].length > 0)) {
    return 'archive';
  }
  return 'unknown';
}

function subtitleFormat(url: string, declared: unknown): StremioSubtitle['format'] {
  const value = String(declared ?? '').toLowerCase();
  if (value === 'srt' || value === 'vtt' || value === 'ass' || value === 'ssa') return value;
  const extension = /\.(srt|vtt|ass|ssa)(?:$|[?#])/i.exec(url)?.[1]?.toLowerCase();
  return extension as StremioSubtitle['format'];
}

function normalizeSubtitle(raw: any, index: number, addon: InstalledAddon): StremioSubtitle | null {
  if (typeof raw?.url !== 'string' || !raw.url) return null;
  return {
    id: typeof raw.id === 'string' && raw.id ? raw.id : `${addon.id}-${index}`,
    url: raw.url,
    lang: raw.lang || raw.language || 'unknown',
    format: subtitleFormat(raw.url, raw.format),
    addonId: addon.id,
    addonName: addon.name,
  };
}

function normalizeStream(raw: any, streamIndex: number, addon: InstalledAddon): StremioStream | null {
  const sourceType = detectSourceType(raw);
  if (sourceType === 'unknown') return null;

  const hints = raw.behaviorHints && typeof raw.behaviorHints === 'object' ? raw.behaviorHints : undefined;
  const text = [raw.title, raw.description, raw.name].filter((part) => typeof part === 'string').join(' ');
  const sizeMatch = SIZE_IN_TEXT.exec(text);
  const parsedSize = sizeMatch ? Number(sizeMatch[1]) * SIZE_UNITS[sizeMatch[2].toUpperCase()] : undefined;

  return {
    name: typeof raw.name === 'string' ? raw.name : undefined,
    title: raw.title ?? raw.description ?? raw.name,
    description: typeof raw.description === 'string' ? raw.description : undefined,
    sourceType,
    url: typeof raw.url === 'string' ? raw.url : undefined,
    externalUrl: typeof raw.externalUrl === 'string' ? raw.externalUrl : undefined,
    ytId: typeof raw.ytId === 'string' ? raw.ytId : undefined,
    infoHash: typeof raw.infoHash === 'string' ? raw.infoHash : undefined,
    fileIdx: typeof raw.fileIdx === 'number' ? raw.fileIdx : undefined,
    addonId: addon.id,
    addonName: addon.name,
    installationId: addon.installationId,
    streamIndex,
    sizeBytes: hints?.videoSize || raw.size || parsedSize,
    quality: typeof raw.quality === 'string' ? raw.quality : undefined,
    subtitles: Array.isArray(raw.subtitles)
      ? raw.subtitles.flatMap((subtitle: any, index: number) => normalizeSubtitle(subtitle, index, addon) ?? [])
      : undefined,
    behaviorHints: hints,
  };
}

async function fetchAddonStreams(
  addon: InstalledAddon,
  identity: StremioContentIdentity,
  signal: AbortSignal | undefined,
): Promise<StremioAddonStreams> {
  const base = { installationId: addon.installationId, addonId: addon.id, addonName: addon.name };
  const path = `/stream/${identity.requestType}/${encodeURIComponent(identity.requestId)}.json`;
  try {
    const data = await fetchAddonJson<{ streams?: unknown }>(addonResourceUrl(addon, path), { signal });
    const streams = Array.isArray(data?.streams)
      ? data.streams.flatMap((raw, index) => normalizeStream(raw, index, addon) ?? [])
      : [];
    return { ...base, streams };
  } catch (err) {
    if ((err as Error)?.name === 'AbortError') throw err;
    return { ...base, streams: [], error: (err as Error)?.message || 'The addon request failed' };
  }
}

/** Addons that can answer for this title, in the user's priority order. */
export function streamAddonsFor(identity: StremioContentIdentity): InstalledAddon[] {
  return listInstalledAddons().filter((addon) =>
    addonSupportsResource(addon, 'stream', identity.requestType, identity.requestId),
  );
}

export async function getStreams(
  identity: StremioContentIdentity,
  options: StremioStreamRequestOptions = {},
): Promise<StremioAddonStreams[]> {
  return Promise.all(
    streamAddonsFor(identity).map(async (addon) => {
      const result = await fetchAddonStreams(addon, identity, options.signal);
      options.onAddonResult?.(result);
      return result;
    }),
  );
}

function subtitleExtraPath(stream: StremioStream | undefined): string {
  const hints = stream?.behaviorHints;
  const pairs: Array<[string, string]> = [];
  if (hints?.videoHash) pairs.push(['videoHash', hints.videoHash]);
  if (hints?.videoSize && hints.videoSize > 0) pairs.push(['videoSize', String(hints.videoSize)]);
  if (hints?.filename) pairs.push(['filename', hints.filename]);
  return pairs.length > 0
    ? `/${pairs.map(([key, value]) => `${key}=${encodeURIComponent(value)}`).join('&')}`
    : '';
}

/** Subtitles from every subtitle addon. Empty when subtitle addons are turned off. */
export async function getSubtitles(
  identity: StremioContentIdentity,
  options: StremioSubtitleRequestOptions = {},
): Promise<StremioSubtitle[]> {
  if (!getSettings().stremioSubtitleAddonsEnabled) return [];
  const addons = listInstalledAddons().filter((addon) =>
    addonSupportsResource(addon, 'subtitles', identity.requestType, identity.requestId),
  );
  const extra = subtitleExtraPath(options.stream);
  const lists = await Promise.all(
    addons.map(async (addon) => {
      const path = `/subtitles/${identity.requestType}/${encodeURIComponent(identity.requestId)}${extra}.json`;
      try {
        const data = await fetchAddonJson<{ subtitles?: unknown }>(addonResourceUrl(addon, path), {
          signal: options.signal,
          timeoutMs: 10_000,
        });
        return Array.isArray(data?.subtitles)
          ? data.subtitles.flatMap((raw, index) => normalizeSubtitle(raw, index, addon) ?? [])
          : [];
      } catch (err) {
        if ((err as Error)?.name === 'AbortError') throw err;
        return [];
      }
    }),
  );

  const byUrl = new Map<string, StremioSubtitle>();
  for (const subtitle of lists.flat()) if (!byUrl.has(subtitle.url)) byUrl.set(subtitle.url, subtitle);
  return [...byUrl.values()];
}

/** Downloads a subtitle file as text, using the backend when the host blocks CORS. */
export function fetchSubtitleText(
  subtitle: StremioSubtitle,
  options: StremioRequestOptions = {},
): Promise<string> {
  return fetchSubtitleFile(subtitle.url, options.signal);
}

function isHlsUrl(url: string): boolean {
  try {
    return /\.m3u8$/i.test(new URL(url).pathname);
  } catch {
    return false;
  }
}

async function hlsIsReadable(url: string, signal: AbortSignal | undefined): Promise<boolean> {
  try {
    const response = await fetch(url, { signal });
    await response.body?.cancel();
    return response.ok;
  } catch (err) {
    if ((err as Error)?.name === 'AbortError') throw err;
    return false;
  }
}

/**
 * Returns the stream with `playbackUrl` set. The backend proxy is used only when the
 * browser cannot play the URL itself: request headers the addon requires, http media on
 * an https page, or HLS from a host without CORS.
 */
export async function prepareStreamForPlayback(
  stream: StremioStream,
  identity: StremioContentIdentity,
  options: StremioRequestOptions = {},
): Promise<StremioStream> {
  if (!stream.url) return stream;
  const url = stream.url;
  const needsHeaders = Object.keys(stream.behaviorHints?.proxyHeaders?.request ?? {}).length > 0;
  const needsProxy =
    needsHeaders || isMixedContent(url) || (isHlsUrl(url) && !(await hlsIsReadable(url, options.signal)));
  if (!needsProxy) return { ...stream, playbackUrl: url };

  const addon = listInstalledAddons().find((other) => other.installationId === stream.installationId);
  if (!addon) throw new Error('The addon for this source is no longer installed');
  const playbackUrl = await requestStreamProxyUrl(
    {
      manifestUrl: addon.manifestUrl,
      type: identity.requestType,
      id: identity.requestId,
      streamIndex: stream.streamIndex,
      url,
      filename: stream.behaviorHints?.filename,
    },
    options.signal,
  );
  return { ...stream, playbackUrl };
}
