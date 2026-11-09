/**
 * Helpers for addon playback beyond the first source: re-fetching sources for the
 * same title (dead-link recovery, source refresh), bounded lookups, and building
 * the Player route for a chosen stream.
 * macOS reference: Services/StreamRecoveryService.swift
 */

import { appLogger } from '../core/AppLogger';
import { stremioService } from './StremioService';
import { stremioStreamCache } from './StremioStreamCache';
import type {
  GenericStreamParams,
  StremioAddonStreamResult,
  StremioContentIdentity,
  StremioPlayableStream,
  StremioSubtitleCandidate,
} from './types';
import { parseStreamSeriesRef, identityForEpisode } from './StreamEpisodeNavigator';

/** Replacement sources tried per playback before giving up. */
export const MAX_STREAM_RECOVERY_ATTEMPTS = 2;
/** Upper bound for one source lookup across all addons. */
const LOOKUP_TIMEOUT_MS = 30_000;

/** Stremio identity for the title in stream params, from its content key. */
export function identityForStreamParams(params: GenericStreamParams): StremioContentIdentity | null {
  if (params.stremioIdentity) {
    return params.stremioIdentity;
  }
  const series = parseStreamSeriesRef(params);
  if (series) {
    return identityForEpisode(series, series.season, series.episode);
  }
  if (params.mediaType !== 'movie' || !params.contentKey.startsWith('movie:')) {
    return null;
  }
  const baseId = params.contentKey.slice('movie:'.length);
  if (!baseId) {
    return null;
  }
  return {
    requestType: 'movie',
    baseId,
    requestId: baseId,
    imdbId: params.imdbId,
    tmdbId: params.tmdbId,
    source: 'player',
  };
}

/** Streams from all installed stream addons, or null on timeout. */
export async function fetchStreamsForRecovery(
  identity: StremioContentIdentity
): Promise<StremioAddonStreamResult[] | null> {
  const fetched = await stremioService.getStreamsWithin(identity, { timeLimitMs: LOOKUP_TIMEOUT_MS });
  return fetched.timedOut && fetched.results.length === 0 ? null : fetched.results;
}

/** Drops the cached playback source when it points at the failed URL. */
export async function removeCachedSourceIfFailed(contentKey: string, failedUrl: string): Promise<void> {
  const cached = await stremioStreamCache.get(contentKey);
  if (cached?.uri !== failedUrl) {
    return;
  }
  await stremioStreamCache.remove(contentKey);
  appLogger.info('[StreamRecovery] Removed dead source from stream cache', { contentKey });
}

/** Groups known sources by addon, keeping their order (ranking uses addon order). */
export function groupStreamsByAddon(streams: StremioPlayableStream[]): StremioAddonStreamResult[] {
  const grouped = new Map<string, StremioAddonStreamResult>();
  for (const stream of streams) {
    const key = stream.addonInstallationId || stream.addonId || 'unknown';
    let group = grouped.get(key);
    if (!group) {
      group = {
        addonId: stream.addonId || key,
        addonName: stream.addonName || 'Stremio',
        installationId: key,
        streams: [],
      };
      grouped.set(key, group);
    }
    group.streams.push(stream);
  }
  return Array.from(grouped.values());
}

export function mergedStreamHeaders(stream: StremioPlayableStream): Record<string, string> | undefined {
  const headers = {
    ...(stream.headers || {}),
    ...(stream.behaviorHints?.proxyHeaders?.request || {}),
  };
  return Object.keys(headers).length > 0 ? headers : undefined;
}

/** The stream's own subtitles plus the addon results, one per URL, sorted by language. */
export function mergeExternalSubtitles(
  stream: StremioPlayableStream,
  addonSubtitles: StremioSubtitleCandidate[]
): StremioSubtitleCandidate[] {
  const byUrl = new Map<string, StremioSubtitleCandidate>();
  for (const subtitle of [...(stream.subtitles || []), ...addonSubtitles]) {
    if (subtitle.url && !byUrl.has(subtitle.url)) {
      byUrl.set(subtitle.url, subtitle);
    }
  }
  return Array.from(byUrl.values()).sort((left, right) => left.lang.localeCompare(right.lang));
}

/** Route params for playing `stream` as the title described by `base`. */
export function streamRouteFor(
  stream: StremioPlayableStream,
  base: GenericStreamParams
): GenericStreamParams {
  return {
    ...base,
    uri: stream.url as string,
    headers: mergedStreamHeaders(stream),
    streamLabel: stream.name || stream.title || base.streamLabel,
    streamAddonId: stream.addonId,
    streamAddonName: stream.addonName,
  };
}
