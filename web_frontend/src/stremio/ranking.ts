/** Source ranking and "same source" matching, ported from StremioSourceRanking.swift. */
import { getSettings } from '@/state/settings';
import { listInstalledAddons } from './addons';
import { classifyPlayability } from './playability';
import type { RankStreamsOptions, StremioAddonStreams, StremioStream } from './types';

/** Resolution bucket from the quality field or the name and title addons put it in. */
export function resolutionBucket(stream: StremioStream): number | undefined {
  const text = [stream.quality, stream.name, stream.title, stream.behaviorHints?.filename]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
  if (text.includes('2160') || text.includes('4k') || text.includes('uhd')) return 2160;
  if (text.includes('1080')) return 1080;
  if (text.includes('720')) return 720;
  if (text.includes('480')) return 480;
  return undefined;
}

const QUALITY_SCORE: Record<number, number> = { 2160: 20_000, 1080: 15_000, 720: 10_000, 480: 5_000 };

function score(stream: StremioStream, addonOrder: string[], options: RankStreamsOptions): number {
  let total = 0;
  if (classifyPlayability(stream).playable) total += 10_000_000_000;
  const group = stream.behaviorHints?.bingeGroup;
  if (group && group === options.preferredBingeGroup) total += 1_000_000_000;
  if (stream.behaviorHints?.cached) total += 100_000;
  total += QUALITY_SCORE[resolutionBucket(stream) ?? 0] ?? 0;
  total += Math.min(Math.floor((stream.sizeBytes ?? 0) / 1_000_000), 9_999);
  const position = addonOrder.indexOf(stream.installationId);
  if (position >= 0) total += Math.max(0, 1_000 - position);
  total += Math.max(0, 500 - stream.streamIndex);
  return total;
}

/** Returns a new array, browser-playable streams first. */
export function rankStreams(streams: StremioStream[], options: RankStreamsOptions = {}): StremioStream[] {
  const addonOrder = listInstalledAddons().map((addon) => addon.installationId);
  return streams
    .map((stream) => ({ stream, value: score(stream, addonOrder, options) }))
    .sort((a, b) => b.value - a.value)
    .map(({ stream }) => stream);
}

/** Streams that can play here, best first. */
export function rankedPlayable(
  results: StremioAddonStreams[],
  options: RankStreamsOptions = {},
): StremioStream[] {
  return rankStreams(results.flatMap((result) => result.streams), options).filter(
    (stream) => classifyPlayability(stream).playable && stream.url,
  );
}

export type MatchTier = 'bingeGroup' | 'addonAndQuality' | 'addon' | 'quality' | 'bestRanked';

// Next episode stays on the source in use. Many addons send no binge group, so same
// addon and resolution have to count too.
export const NEXT_EPISODE_TIERS: MatchTier[] = ['bingeGroup', 'addonAndQuality', 'addon', 'quality', 'bestRanked'];

/** The addon in use supplied it, so no other addon can do better. */
export function isSameAddonTier(tier: MatchTier | undefined): boolean {
  return tier === 'bingeGroup' || tier === 'addonAndQuality' || tier === 'addon';
}

/** Results in the user's addon order, each addon's streams as the addon listed them. */
function playableInAddonOrder(results: StremioAddonStreams[]): StremioStream[] {
  const order = listInstalledAddons().map((addon) => addon.installationId);
  const position = (id: string) => {
    const index = order.indexOf(id);
    return index < 0 ? order.length : index;
  };
  return [...results]
    .sort((a, b) => position(a.installationId) - position(b.installationId))
    .flatMap(listedPlayable);
}

/** The results of the first addon in the user's order with anything playable. */
export function firstAddonWithPlayable(results: StremioAddonStreams[]): StremioAddonStreams[] {
  const order = listInstalledAddons().map((addon) => addon.installationId);
  const position = (id: string) => {
    const index = order.indexOf(id);
    return index < 0 ? order.length : index;
  };
  const first = [...results]
    .sort((a, b) => position(a.installationId) - position(b.installationId))
    .find((result) => listedPlayable(result).length > 0);
  return first ? [first] : [];
}

/** Streams that can play here, in the order the addon listed them. */
export function listedPlayable(result: StremioAddonStreams): StremioStream[] {
  return result.streams.filter((stream) => classifyPlayability(stream).playable && stream.url);
}

const words = (text: string | undefined) =>
  (text ?? '').toLowerCase().split(/[^a-z0-9]+/).filter((word) => word.length > 1);

/** File name words, without the season and episode that always differ. */
const fileWords = (stream: StremioStream) =>
  new Set(words(stream.behaviorHints?.filename).filter((word) => !/^(s\d+e\d+|s\d+|e\d+)$/.test(word)));

/** Letters only, because sizes and bitrates differ from episode to episode. */
const descriptionWords = (stream: StremioStream) =>
  new Set(words(stream.description).filter((word) => /^[a-z]+$/.test(word)));

/** The `GROUP` in `Show.S01E01.1080p.WEB-DL-GROUP.mkv`. */
function releaseGroup(stream: StremioStream): string | undefined {
  return stream.behaviorHints?.filename?.match(/-([A-Za-z0-9]+)(?:\.[a-zA-Z0-9]{2,4})?$/)?.[1].toLowerCase();
}

const sharedCount = (left: Set<string>, right: Set<string>) =>
  [...left].filter((word) => right.has(word)).length;

/** Resolution counts most, then release group, then shared file name and description words. */
function similarity(stream: StremioStream, reference: StremioStream): number {
  let value = 0;
  const bucket = resolutionBucket(reference);
  if (bucket !== undefined && bucket === resolutionBucket(stream)) value += 1_000;
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
function closestTo(reference: StremioStream, candidates: StremioStream[]): StremioStream | undefined {
  let best: StremioStream | undefined;
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
export const ALL_MATCH_TIERS: MatchTier[] = ['bingeGroup', 'addonAndQuality', 'addon', 'quality', 'bestRanked'];

/**
 * The source closest to `reference`: same addon and binge group, then same addon and
 * resolution, then same addon, then any addon at that resolution, then best ranked.
 * `tiers` limits the steps. For the next episode pass NEXT_EPISODE_TIERS, and for
 * dead-link recovery pass the failed URL in `excludingUrls`.
 */
export function findBestMatch(
  reference: StremioStream | undefined,
  results: StremioAddonStreams[],
  options: { excludingUrls?: Set<string>; tiers?: MatchTier[]; followAddonOrder?: boolean } = {},
): { stream: StremioStream; tier: MatchTier } | null {
  const tiers = options.tiers ?? ALL_MATCH_TIERS;
  // With "Follow addon order", once the addon in use has nothing, the next addon in order wins.
  const followAddonOrder = options.followAddonOrder ?? getSettings().stremioPlayAction === 'addonOrder';
  const candidates = followAddonOrder ? playableInAddonOrder(results) : rankedPlayable(results);
  const ranked = candidates.filter((stream) => !options.excludingUrls?.has(stream.url ?? ''));
  if (ranked.length === 0) return null;
  if (!reference) return tiers.includes('bestRanked') ? { stream: ranked[0], tier: 'bestRanked' } : null;

  const bucket = resolutionBucket(reference);
  const sameAddon = (stream: StremioStream) => stream.installationId === reference.installationId;
  const sameBucket = (stream: StremioStream) => bucket !== undefined && resolutionBucket(stream) === bucket;
  const group = reference.behaviorHints?.bingeGroup;
  const checks: Array<[MatchTier, (stream: StremioStream) => boolean]> = [
    ['bingeGroup', (stream) => sameAddon(stream) && Boolean(group) && stream.behaviorHints?.bingeGroup === group],
    ['addonAndQuality', (stream) => sameAddon(stream) && sameBucket(stream)],
    ['addon', sameAddon],
    ['quality', sameBucket],
    ['bestRanked', () => true],
  ];
  for (const [tier, matches] of checks) {
    if (!tiers.includes(tier) || (followAddonOrder && tier === 'quality')) continue;
    const matching = ranked.filter(matches);
    const stream = tier === 'bestRanked' ? matching[0] : closestTo(reference, matching);
    if (stream) return { stream, tier };
  }
  return null;
}
