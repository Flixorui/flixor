/**
 * Decides which source to start when the Play action is automatic. Ported from
 * StreamAutoSelector.swift and StremioSourcesViewModel.findAutomaticSource.
 */
import { getSettings } from '@/state/settings';
import { hasStreamProviders } from './addons';
import { listedPlayable, resolutionBucket, rankedPlayable } from './ranking';
import { StreamRuleMatcher, StreamRulesError, getStreamRules, subjectFor } from './rules';
import { buildContentKey } from './identity';
import { getResumeState } from './resumeStore';
import { getCachedStream } from './streamCache';
import { getStreams, streamAddonsFor } from './streams';
import type {
  StremioAddonStreams,
  StremioContentIdentity,
  StremioRequestOptions,
  StremioStream,
} from './types';

export type AutoPickAction = 'playBest' | 'matchRules' | 'addonOrder';

export type AutoPickOutcome =
  | { kind: 'play'; stream: StremioStream; results: StremioAddonStreams[] }
  | { kind: 'showSources'; notice?: string; results: StremioAddonStreams[] };

async function candidates(
  results: StremioAddonStreams[],
  matcher: StreamRuleMatcher | null,
): Promise<StremioStream[]> {
  const ranked = rankedPlayable(results);
  if (!matcher) return ranked;
  const verdicts = await matcher.verdicts(ranked.map(subjectFor));
  return ranked.filter((_stream, index) => verdicts[index] === 'match');
}

function preferred(list: StremioStream[], matcher: StreamRuleMatcher | null): StremioStream | undefined {
  const addon = matcher?.rules.preferredAddonId;
  return addon ? list.find((stream) => stream.installationId === addon) : undefined;
}

/** True once there is no reason to wait for more addons. */
async function isGoodEnough(
  results: StremioAddonStreams[],
  pending: Set<string>,
  matcher: StreamRuleMatcher | null,
): Promise<boolean> {
  const list = await candidates(results, matcher);
  if (matcher?.timedOut) return true;
  if (!matcher) {
    const best = list[0];
    return Boolean(best?.behaviorHints?.cached && resolutionBucket(best) === 2160);
  }
  if (preferred(list, matcher)) return true;
  const addon = matcher.rules.preferredAddonId;
  if (addon && pending.has(addon)) return false;
  return list.length > 0;
}

/** True once the first addon with a playable stream has every addon ahead of it answered. */
export function addonOrderSettled(order: string[], results: StremioAddonStreams[], pending: Set<string>): boolean {
  for (const addon of order) {
    if (pending.has(addon)) return false;
    const result = results.find((item) => item.installationId === addon);
    if (result && listedPlayable(result).length > 0) return true;
  }
  return false;
}

function fallbackNotice(results: StremioAddonStreams[], waitedSeconds: number | null): string {
  if (results.length === 0) return `No addon answered within ${waitedSeconds ?? 0} seconds. Choose a source here.`;
  if (results.every((result) => result.error)) return 'Your addons could not be reached. Choose a source here, or try again.';
  return 'No source matched automatically. Choose one here.';
}

export async function findAutomaticSource(
  identity: StremioContentIdentity,
  action: AutoPickAction,
  options: StremioRequestOptions & { skipAddons?: Set<string> } = {},
): Promise<AutoPickOutcome> {
  const skipAddons = options.skipAddons;
  if (!hasStreamProviders(identity.requestType)) return { kind: 'showSources', results: [] };

  // Only a real resume reuses the last source; a fresh Play follows the Play action.
  if (getSettings().stremioPreferCachedSourceResume && !skipAddons?.size) {
    const cached = getCachedStream(identity);
    const resume = getResumeState(buildContentKey(identity));
    if (cached && resume && resume.positionMs > 0) return { kind: 'play', stream: cached.stream, results: [] };
  }

  let matcher: StreamRuleMatcher | null = null;
  if (action === 'matchRules') {
    try {
      matcher = new StreamRuleMatcher(getStreamRules());
    } catch (err) {
      if (!(err instanceof StreamRulesError)) throw err;
      return {
        kind: 'showSources',
        notice: 'Your source rules have an invalid pattern. Fix it in Settings, or choose a source here.',
        results: [],
      };
    }
  }

  const timeLimitSeconds = getSettings().stremioAutoPickTimeLimit;
  const addonOrder = streamAddonsFor(identity)
    .map((addon) => addon.installationId)
    .filter((id) => !skipAddons?.has(id));
  const pending = new Set(addonOrder);
  const results: StremioAddonStreams[] = [];
  const controller = new AbortController();
  const onAbort = () => controller.abort();
  options.signal?.addEventListener('abort', onAbort, { once: true });

  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort();
  }, timeLimitSeconds * 1000);

  // Serialised so a slow check on one result cannot overlap the next.
  let checks: Promise<void> = Promise.resolve();
  try {
    await getStreams(identity, {
      signal: controller.signal,
      onAddonResult(result) {
        if (skipAddons?.has(result.installationId)) return;
        results.push(result);
        pending.delete(result.installationId);
        checks = checks.then(async () => {
          if (controller.signal.aborted) return;
          const settled =
            action === 'addonOrder'
              ? addonOrderSettled(addonOrder, results, pending)
              : await isGoodEnough(results, pending, matcher);
          if (settled) controller.abort();
        });
      },
    });
  } catch (err) {
    if (options.signal?.aborted) throw err;
    if ((err as Error)?.name !== 'AbortError') throw err;
  } finally {
    clearTimeout(timer);
    options.signal?.removeEventListener('abort', onAbort);
    await checks.catch(() => {});
  }

  const sorted = streamAddonsFor(identity).flatMap((addon) =>
    results.filter((result) => result.installationId === addon.installationId),
  );
  if (action === 'addonOrder') {
    const stream = sorted.flatMap(listedPlayable)[0];
    if (stream) return { kind: 'play', stream, results: sorted };
    return { kind: 'showSources', notice: fallbackNotice(sorted, timedOut ? timeLimitSeconds : null), results: sorted };
  }

  const list = await candidates(sorted, matcher);
  if (matcher?.timedOut) {
    return {
      kind: 'showSources',
      notice: 'Your include pattern took too long to check. Simplify it in Settings, or choose a source here.',
      results: sorted,
    };
  }
  const stream = preferred(list, matcher) ?? list[0];
  if (!stream) {
    return { kind: 'showSources', notice: fallbackNotice(sorted, timedOut ? timeLimitSeconds : null), results: sorted };
  }
  return { kind: 'play', stream, results: sorted };
}
