/**
 * Source ranking shared by the sources page (auto-play), and the player
 * (next-episode source, dead-link recovery), plus "same source" matching.
 * macOS reference: Services/Stremio/StremioSourceRanking.swift
 */

import { getAppSettings } from '../core/SettingsData';
import type { StremioAddonStreamResult, StremioPlayableStream } from './types';

export type SourceMatchTier = 'bingeGroup' | 'addonAndQuality' | 'addon' | 'quality' | 'bestRanked';

export const ALL_MATCH_TIERS: SourceMatchTier[] = [
  'bingeGroup',
  'addonAndQuality',
  'addon',
  'quality',
  'bestRanked',
];

/** Next episode per the Stremio binge rules: same addon and binge group, else best ranked. */
// Next episode stays on the source in use. Many addons send no binge group, so same
// addon and resolution have to count too.
export const NEXT_EPISODE_MATCH_TIERS: SourceMatchTier[] = ['bingeGroup', 'addonAndQuality', 'addon', 'quality', 'bestRanked'];

/** The addon in use supplied it, so no other addon can do better. */
export function isSameAddonTier(tier: SourceMatchTier | undefined): boolean {
  return tier === 'bingeGroup' || tier === 'addonAndQuality' || tier === 'addon';
}

export type SourceMatch = { stream: StremioPlayableStream; tier: SourceMatchTier };

export function resolutionBucketFromText(text: string): number | null {
  const lower = text.toLowerCase();
  if (lower.includes('2160') || lower.includes('4k') || lower.includes('uhd')) return 2160;
  if (lower.includes('1080')) return 1080;
  if (lower.includes('720')) return 720;
  if (lower.includes('480')) return 480;
  return null;
}

/** Resolution from the quality field, or the name and title text addons usually put it in. */
export function resolutionBucket(stream: StremioPlayableStream): number | null {
  return resolutionBucketFromText(
    [stream.quality, stream.name, stream.title, stream.behaviorHints?.filename].filter(Boolean).join(' ')
  );
}

function qualityScore(stream: StremioPlayableStream): number {
  switch (resolutionBucket(stream)) {
    case 2160:
      return 20_000;
    case 1080:
      return 15_000;
    case 720:
      return 10_000;
    case 480:
      return 5_000;
    default:
      return 0;
  }
}

/** Score used to pick the best source. `addonOrder` is installation ids, earlier is preferred. */
export function sourceScore(stream: StremioPlayableStream, addonOrder: string[]): number {
  let score = 0;
  if (stream.playable) score += 1_000_000;
  if (stream.behaviorHints?.cached) score += 100_000;
  if (stream.isDebrid) score += 50_000;
  score += qualityScore(stream);
  score += Math.min(Math.floor((stream.size || 0) / 1_000_000), 9_999);

  const addonIndex = stream.addonInstallationId ? addonOrder.indexOf(stream.addonInstallationId) : -1;
  if (addonIndex >= 0) {
    score += Math.max(0, 1_000 - addonIndex);
  }

  score += Math.max(0, 500 - stream.streamIndex);
  return score;
}

/** Playable streams in the order the addon listed them. */
export function listedPlayable(result: StremioAddonStreamResult): StremioPlayableStream[] {
  return result.streams.filter((stream) => stream.playable && Boolean(stream.url));
}

/** The results of the first addon, in the order given, with anything playable. */
export function firstAddonWithPlayable(results: StremioAddonStreamResult[]): StremioAddonStreamResult[] {
  const first = results.find((result) => listedPlayable(result).length > 0);
  return first ? [first] : [];
}

/** Playable streams, best first. */
export function rankedPlayable(results: StremioAddonStreamResult[]): StremioPlayableStream[] {
  const order = results.map((result) => result.installationId);
  return results
    .flatMap((result) => result.streams)
    .filter((stream) => stream.playable && Boolean(stream.url))
    .map((stream) => ({ stream, score: sourceScore(stream, order) }))
    .sort((left, right) => right.score - left.score)
    .map((entry) => entry.stream);
}

export function isSameAddon(left: StremioPlayableStream, right: StremioPlayableStream): boolean {
  if (left.addonInstallationId && right.addonInstallationId) {
    return left.addonInstallationId === right.addonInstallationId;
  }
  if (left.addonId && right.addonId) {
    return left.addonId === right.addonId;
  }
  return false;
}

/** Same non-empty `behaviorHints.bingeGroup` means the same release line. */
export function isSameBingeGroup(left: StremioPlayableStream, right: StremioPlayableStream): boolean {
  const group = left.behaviorHints?.bingeGroup;
  return Boolean(group) && group === right.behaviorHints?.bingeGroup;
}

const words = (text: string | undefined) =>
  (text ?? '').toLowerCase().split(/[^a-z0-9]+/).filter((word) => word.length > 1);

/** File name words, without the season and episode that always differ. */
const fileWords = (stream: StremioPlayableStream) =>
  new Set(words(stream.behaviorHints?.filename).filter((word) => !/^(s\d+e\d+|s\d+|e\d+)$/.test(word)));

/** Letters only, because sizes and bitrates differ from episode to episode. */
const descriptionWords = (stream: StremioPlayableStream) =>
  new Set(words(stream.description).filter((word) => /^[a-z]+$/.test(word)));

/** The `GROUP` in `Show.S01E01.1080p.WEB-DL-GROUP.mkv`. */
function releaseGroup(stream: StremioPlayableStream): string | null {
  const match = stream.behaviorHints?.filename?.match(/-([A-Za-z0-9]+)(?:\.[a-zA-Z0-9]{2,4})?$/);
  return match ? match[1].toLowerCase() : null;
}

const sharedCount = (left: Set<string>, right: Set<string>) =>
  [...left].filter((word) => right.has(word)).length;

/** Resolution counts most, then release group, then shared file name and description words. */
function similarity(stream: StremioPlayableStream, reference: StremioPlayableStream): number {
  let value = 0;
  const bucket = resolutionBucket(reference);
  if (bucket !== null && bucket === resolutionBucket(stream)) value += 1_000;
  const group = releaseGroup(reference);
  if (group && group === releaseGroup(stream)) value += 500;
  value += 10 * sharedCount(fileWords(stream), fileWords(reference));
  value += 20 * sharedCount(descriptionWords(stream), descriptionWords(reference));
  return value;
}

/**
 * The candidate most like `reference`; the earliest wins a tie. A binge group is often
 * as broad as "WEB-DL", so a match on it can still be a very different release.
 */
function closestTo(
  reference: StremioPlayableStream,
  candidates: StremioPlayableStream[]
): StremioPlayableStream | undefined {
  let best: StremioPlayableStream | undefined;
  let bestValue = -1;
  for (const candidate of candidates) {
    const value = similarity(candidate, reference);
    if (value > bestValue) {
      best = candidate;
      bestValue = value;
    }
  }
  return best;
}

/**
 * The source closest to `reference`: same addon and binge group, same addon and
 * resolution, same addon, same resolution, then best ranked. `tiers` limits which
 * steps apply. Streams whose URL is excluded are never returned.
 */
export function bestSourceMatch(
  reference: StremioPlayableStream | null | undefined,
  results: StremioAddonStreamResult[],
  options?: { excludingUrls?: ReadonlySet<string>; tiers?: SourceMatchTier[]; followAddonOrder?: boolean }
): SourceMatch | null {
  const tiers = options?.tiers ?? ALL_MATCH_TIERS;
  const excluded = options?.excludingUrls;
  // With "Follow addon order", once the addon in use has nothing, the next addon in order wins.
  const followAddonOrder = options?.followAddonOrder ?? getAppSettings().stremioPlayAction === 'addonOrder';
  const candidates = followAddonOrder ? results.flatMap(listedPlayable) : rankedPlayable(results);
  const ranked = candidates.filter((stream) => !excluded?.has(stream.url || ''));
  if (ranked.length === 0) {
    return null;
  }
  if (!reference) {
    return tiers.includes('bestRanked') ? { stream: ranked[0], tier: 'bestRanked' } : null;
  }

  const bucket = resolutionBucket(reference);
  const checks: Array<[SourceMatchTier, (stream: StremioPlayableStream) => boolean]> = [
    ['bingeGroup', (stream) => isSameAddon(stream, reference) && isSameBingeGroup(stream, reference)],
    ['addonAndQuality', (stream) => bucket !== null && isSameAddon(stream, reference) && resolutionBucket(stream) === bucket],
    ['addon', (stream) => isSameAddon(stream, reference)],
    ['quality', (stream) => bucket !== null && resolutionBucket(stream) === bucket],
    ['bestRanked', () => true],
  ];

  for (const [tier, matches] of checks) {
    if (!tiers.includes(tier) || (followAddonOrder && tier === 'quality')) continue;
    const matching = ranked.filter(matches);
    const stream = tier === 'bestRanked' ? matching[0] : closestTo(reference, matching);
    if (stream) {
      return { stream, tier };
    }
  }
  return null;
}
