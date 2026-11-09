/**
 * Decides which addon stream to start automatically when Play is pressed. Only
 * streams the app can play are candidates.
 * macOS reference: Services/Stremio/StreamAutoSelector.swift
 *
 * JS has no regex timeout and `RegExp.test` cannot be interrupted, and on mobile it
 * runs on the JS thread. macOS can stop a running match; here a user pattern has to
 * be proven cheap before it runs. Three layers keep a bad pattern from freezing the app:
 *
 * 1. `checkIncludePattern` rejects patterns that can backtrack badly. It extends the
 *    macOS nested-repeat check with the other shapes that are expensive in a
 *    backtracking engine, and bounds the worst case by the length of text matched.
 * 2. Rules run against capped text.
 * 3. A total time budget stops further matching if patterns are slower than expected.
 *
 * Word lists never use RegExp at all, so they are always linear.
 */

import type { StremioStreamRules } from '../core/SettingsData';
import { listedPlayable, rankedPlayable, resolutionBucket } from './StremioSourceRanking';
import type { StremioAddonStreamResult, StremioPlayableStream } from './types';

export type StreamRuleVerdict =
  | { kind: 'match' }
  | { kind: 'missingInclude' }
  | { kind: 'excluded'; word: string }
  | { kind: 'aboveResolutionLimit' }
  /** The include pattern used up its matching time, so the stream can't be judged. */
  | { kind: 'timedOut' };

export type StreamRuleProblem = 'invalid' | 'unsafe' | 'tooLong';

const MAX_PATTERN_LENGTH = 256;
/** Longest text a pattern runs against when it has at most one open-ended repeat. */
const MAX_TEXT_LENGTH = 1_000;
/** Text is capped harder when repeats can multiply against each other. */
const MAX_TEXT_LENGTH_MULTIPLE_REPEATS = 300;
/** Worst-case backtracking steps a pattern may need. Roughly a few hundred ms on a phone. */
const MAX_ESTIMATED_STEPS = 2e7;
/** Total time all include matches may use during one automatic selection. */
const MATCHING_BUDGET_MS = 250;
/** One match this slow means the pattern is misbehaving, so stop using it. */
const SINGLE_MATCH_LIMIT_MS = 100;

/**
 * True when a group containing an open-ended repeat is itself repeated, like `(a+)+`.
 * Direct port of the macOS check.
 */
export function hasNestedRepeat(pattern: string): boolean {
  const chars = Array.from(pattern);
  const groupHasRepeat: boolean[] = [];
  let closedGroupHadRepeat = false;
  let inCharacterClass = false;
  let index = 0;

  while (index < chars.length) {
    const char = chars[index];
    index += 1;

    if (char === '\\') {
      index += 1;
      closedGroupHadRepeat = false;
      continue;
    }
    if (inCharacterClass) {
      if (char === ']') inCharacterClass = false;
      continue;
    }

    let isRepeat = char === '*' || char === '+';
    if (char === '{') {
      const close = chars.indexOf('}', index);
      if (close >= 0) {
        // {3} repeats a fixed number of times; {3,} and {3,9} vary.
        isRepeat = chars.slice(index, close).includes(',');
        index = close + 1;
        if (!isRepeat) continue;
      }
    }

    if (isRepeat) {
      if (closedGroupHadRepeat) return true;
      if (groupHasRepeat.length > 0) groupHasRepeat[groupHasRepeat.length - 1] = true;
      closedGroupHadRepeat = false;
      continue;
    }

    closedGroupHadRepeat = false;
    if (char === '[') {
      inCharacterClass = true;
    } else if (char === '(') {
      groupHasRepeat.push(false);
    } else if (char === ')') {
      const hadRepeat = groupHasRepeat.pop() ?? false;
      closedGroupHadRepeat = hadRepeat;
      if (hadRepeat && groupHasRepeat.length > 0) {
        groupHasRepeat[groupHasRepeat.length - 1] = true;
      }
    }
  }
  return false;
}

type GroupState = { hasRepeat: boolean; hasAlternation: boolean; branches: number };

type PatternShape = {
  /** A repeated group contains a repeat or alternatives, or the pattern uses a backreference. */
  unsafe: boolean;
  /** Repeats with no small fixed count: `*`, `+`, `{m,}`, `{m,n}`. */
  variableRepeats: number;
  /** Paths multiplied by optional items and alternatives inside groups. */
  branchProduct: number;
};

/** Walks the pattern for shapes that make a backtracking engine slow. */
function inspectPattern(pattern: string): PatternShape {
  const chars = Array.from(pattern);
  const groups: GroupState[] = [];
  let closed: { hadRepeat: boolean; hadAlternation: boolean } | null = null;
  let inCharacterClass = false;
  let unsafe = false;
  let variableRepeats = 0;
  let branchProduct = 1;
  let index = 0;

  const markRepeat = () => {
    if (groups.length > 0) groups[groups.length - 1].hasRepeat = true;
  };

  while (index < chars.length) {
    const char = chars[index];
    index += 1;

    if (char === '\\') {
      const next = chars[index];
      if (next !== undefined && (/[1-9]/.test(next) || next === 'k')) unsafe = true;
      index += 1;
      closed = null;
      continue;
    }
    if (inCharacterClass) {
      if (char === ']') inCharacterClass = false;
      continue;
    }

    // A `?` straight after a repeat only makes it lazy, which changes nothing here.
    const skipLazySuffix = () => {
      if (chars[index] === '?') index += 1;
    };

    if (char === '*' || char === '+') {
      if (closed?.hadRepeat || closed?.hadAlternation) unsafe = true;
      variableRepeats += 1;
      markRepeat();
      closed = null;
      skipLazySuffix();
      continue;
    }

    if (char === '?') {
      branchProduct *= 2;
      closed = null;
      continue;
    }

    if (char === '{') {
      const close = chars.indexOf('}', index);
      const body = close >= 0 ? chars.slice(index, close).join('') : '';
      if (/^\d+(,\d*)?$/.test(body)) {
        index = close + 1;
        const isVariable = body.includes(',');
        const isOne = body === '1';
        if ((isVariable || !isOne) && (closed?.hadRepeat || closed?.hadAlternation)) unsafe = true;
        if (isVariable) {
          variableRepeats += 1;
          markRepeat();
        }
        closed = null;
        skipLazySuffix();
        continue;
      }
    }

    closed = null;
    if (char === '[') {
      inCharacterClass = true;
    } else if (char === '(') {
      groups.push({ hasRepeat: false, hasAlternation: false, branches: 1 });
      // Skip the `?:`, `?=`, `?<=`, `?<name>` introducer so its `?` isn't read as optional.
      if (chars[index] === '?') {
        index += 1;
        if (chars[index] === '<' && chars[index + 1] !== '=' && chars[index + 1] !== '!') {
          while (index < chars.length && chars[index] !== '>') index += 1;
        } else if (chars[index] === '<') {
          index += 1;
        }
        index += 1;
      }
    } else if (char === '|') {
      if (groups.length > 0) {
        const group = groups[groups.length - 1];
        group.hasAlternation = true;
        group.branches += 1;
      }
    } else if (char === ')') {
      const group = groups.pop();
      if (group) {
        branchProduct *= group.branches;
        closed = { hadRepeat: group.hasRepeat, hadAlternation: group.hasAlternation };
        if (groups.length > 0) {
          const parent = groups[groups.length - 1];
          parent.hasRepeat = parent.hasRepeat || group.hasRepeat;
          parent.hasAlternation = parent.hasAlternation || group.hasAlternation;
        }
      }
    }
  }

  return { unsafe, variableRepeats, branchProduct };
}

function binomial(n: number, k: number): number {
  let result = 1;
  for (let step = 1; step <= k; step += 1) {
    result = (result * (n - k + step)) / step;
  }
  return result;
}

function textLimitFor(variableRepeats: number): number {
  return variableRepeats <= 1 ? MAX_TEXT_LENGTH : MAX_TEXT_LENGTH_MULTIPLE_REPEATS;
}

/** Why an include pattern can't be used, or null when it is safe to run. */
export function checkIncludePattern(rawPattern: string): StreamRuleProblem | null {
  const pattern = rawPattern.trim();
  if (!pattern) return null;
  if (pattern.length > MAX_PATTERN_LENGTH) return 'tooLong';
  if (hasNestedRepeat(pattern)) return 'unsafe';

  try {
    // Compiling is cheap and does not run the pattern.
    new RegExp(pattern, 'i');
  } catch {
    return 'invalid';
  }

  const shape = inspectPattern(pattern);
  if (shape.unsafe) return 'unsafe';

  // An unanchored search tries every start offset, hence the extra degree.
  const paths = binomial(textLimitFor(shape.variableRepeats), shape.variableRepeats + 1);
  return paths * shape.branchProduct > MAX_ESTIMATED_STEPS ? 'unsafe' : null;
}

export function describeRuleProblem(problem: StreamRuleProblem): string {
  switch (problem) {
    case 'invalid':
      return "This pattern isn't a valid regular expression.";
    case 'tooLong':
      return `This pattern is too long. Keep it under ${MAX_PATTERN_LENGTH} characters.`;
    case 'unsafe':
      return 'This pattern could freeze the app. Avoid repeats inside repeats, repeated alternatives, backreferences, and more than two open-ended repeats.';
  }
}

export class StreamRuleError extends Error {
  constructor(readonly problem: StreamRuleProblem) {
    super(describeRuleProblem(problem));
  }
}

function isWordCode(code: number): boolean {
  if (code < 0x80) {
    return (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
  if (code < 0xc0 || code === 0xd7 || code === 0xf7) return false;
  if (code >= 0x2000 && code <= 0x2bff) return false; // punctuation and symbols
  if (code >= 0x3000 && code <= 0x303f) return false; // CJK punctuation
  if (code >= 0xd800 && code <= 0xdfff) return false; // emoji, common in addon titles
  if (code >= 0xfe00 && code <= 0xfe0f) return false; // variation selectors
  return true;
}

function parseWords(text: string): string[] {
  return text
    .split(/[|,\n]/)
    .map((word) => word.trim().toLowerCase())
    .filter(Boolean);
}

/**
 * First listed word found as a whole word. Letters and digits count as word
 * characters, so "TS" matches "HD-TS" but not "HDTS" or "DTS".
 */
function findWholeWord(lowerText: string, words: string[]): string | null {
  for (const word of words) {
    let from = 0;
    while (from <= lowerText.length - word.length) {
      const at = lowerText.indexOf(word, from);
      if (at < 0) break;
      const before = at > 0 ? lowerText.charCodeAt(at - 1) : -1;
      const after = at + word.length < lowerText.length ? lowerText.charCodeAt(at + word.length) : -1;
      if ((before < 0 || !isWordCode(before)) && (after < 0 || !isWordCode(after))) {
        return word;
      }
      from = at + 1;
    }
  }
  return null;
}

/** What rules are matched against. The URL is left out on purpose: tokens or a `.ts` path would trip words like "TS". */
function searchableText(stream: StremioPlayableStream): string {
  return [
    stream.addonName,
    stream.name,
    stream.title,
    stream.description,
    stream.quality,
    stream.behaviorHints?.filename,
  ]
    .filter(Boolean)
    .join(' ');
}

/** `StremioStreamRules` compiled for matching. Throws StreamRuleError for an unusable pattern. */
export class StreamRuleMatcher {
  private readonly include: RegExp | null = null;
  private readonly includeWords: string[] = [];
  private readonly excludeWords: string[];
  private readonly regexTextLimit: number = MAX_TEXT_LENGTH;
  private remainingMs = MATCHING_BUDGET_MS;
  private exhausted = false;
  private readonly verdicts = new WeakMap<StremioPlayableStream, StreamRuleVerdict>();

  constructor(readonly rules: StremioStreamRules) {
    if (rules.includeIsRegex) {
      const pattern = rules.include.trim();
      if (pattern) {
        const problem = checkIncludePattern(pattern);
        if (problem) throw new StreamRuleError(problem);
        this.include = new RegExp(pattern, 'i');
        this.regexTextLimit = textLimitFor(inspectPattern(pattern).variableRepeats);
      }
    } else {
      this.includeWords = parseWords(rules.include);
    }
    this.excludeWords = parseWords(rules.exclude);
  }

  get timedOut(): boolean {
    return this.exhausted;
  }

  /** An unknown resolution passes the limit; ranking already puts it last. */
  verdict(stream: StremioPlayableStream): StreamRuleVerdict {
    const cached = this.verdicts.get(stream);
    if (cached) return cached;
    const result = this.evaluate(searchableText(stream), resolutionBucket(stream));
    this.verdicts.set(stream, result);
    return result;
  }

  evaluate(fullText: string, resolution: number | null): StreamRuleVerdict {
    const text = fullText.slice(0, MAX_TEXT_LENGTH);
    const lower = text.toLowerCase();

    const excluded = findWholeWord(lower, this.excludeWords);
    if (excluded) {
      return { kind: 'excluded', word: excluded };
    }
    const limit = this.rules.maxResolution;
    if (limit && resolution !== null && resolution > limit) {
      return { kind: 'aboveResolutionLimit' };
    }
    if (this.include) {
      const found = this.runInclude(text.slice(0, this.regexTextLimit));
      if (found === null) return { kind: 'timedOut' };
      if (!found) return { kind: 'missingInclude' };
    } else if (this.includeWords.length > 0 && !findWholeWord(lower, this.includeWords)) {
      return { kind: 'missingInclude' };
    }
    return { kind: 'match' };
  }

  /** Null once the budget is gone. A slow match can only be noticed after it returns. */
  private runInclude(text: string): boolean | null {
    if (this.exhausted || !this.include) return null;
    const startedAt = Date.now();
    const found = this.include.test(text);
    const elapsed = Date.now() - startedAt;
    this.remainingMs -= elapsed;
    if (elapsed > SINGLE_MATCH_LIMIT_MS || this.remainingMs <= 0) {
      this.exhausted = true;
      return elapsed > SINGLE_MATCH_LIMIT_MS ? null : found;
    }
    return found;
  }
}

function isTopTier(stream: StremioPlayableStream): boolean {
  return Boolean(stream.behaviorHints?.cached || stream.isDebrid) && resolutionBucket(stream) === 2160;
}

/** Picks a stream from addon results. Pass rules for "Match my rules", null for "Play best source". */
export class StreamAutoSelector {
  private readonly matcher: StreamRuleMatcher | null;
  /** Installation ids, highest priority first. Set for "Follow addon order". */
  private readonly addonOrder: string[] | undefined;

  constructor(rules: StremioStreamRules | null, addonOrder?: string[]) {
    this.matcher = rules ? new StreamRuleMatcher(rules) : null;
    this.addonOrder = addonOrder;
  }

  /** The include pattern took too long; automatic selection should give up. */
  get rulesTimedOut(): boolean {
    return this.matcher?.timedOut ?? false;
  }

  /** The stream to play given everything that has arrived. */
  pick(results: StremioAddonStreamResult[]): StremioPlayableStream | null {
    if (this.addonOrder) {
      for (const result of results) {
        const first = listedPlayable(result)[0];
        if (first) return first;
      }
      return null;
    }
    const candidates = this.candidates(results);
    return this.preferredCandidate(candidates) ?? candidates[0] ?? null;
  }

  /** True once there is no reason to wait for more addons. */
  shouldStopWaiting(results: StremioAddonStreamResult[], pending: ReadonlySet<string>): boolean {
    return this.earlyPick(results, pending) !== null || this.rulesTimedOut;
  }

  /**
   * A stream good enough to stop waiting on the addons in `pending`, or null to keep
   * waiting. Rules: any match counts, once the preferred addon has answered. Best
   * source: only a cached or debrid 4K stream, which the rest couldn't meaningfully beat.
   * Addon order: the first addon with a playable stream, once every addon ahead has answered.
   */
  earlyPick(
    results: StremioAddonStreamResult[],
    pending: ReadonlySet<string>
  ): StremioPlayableStream | null {
    if (this.addonOrder) {
      for (const addon of this.addonOrder) {
        if (pending.has(addon)) return null;
        const result = results.find((item) => item.installationId === addon);
        const first = result ? listedPlayable(result)[0] : undefined;
        if (first) return first;
      }
      return null;
    }
    const candidates = this.candidates(results);
    if (!this.matcher) {
      const best = candidates[0];
      return best && isTopTier(best) ? best : null;
    }
    const preferred = this.preferredCandidate(candidates);
    if (preferred) return preferred;
    const addon = this.matcher.rules.preferredAddonId;
    if (addon && pending.has(addon)) return null;
    return candidates[0] ?? null;
  }

  private candidates(results: StremioAddonStreamResult[]): StremioPlayableStream[] {
    const ranked = rankedPlayable(results);
    const matcher = this.matcher;
    if (!matcher) return ranked;
    return ranked.filter((stream) => matcher.verdict(stream).kind === 'match');
  }

  private preferredCandidate(candidates: StremioPlayableStream[]): StremioPlayableStream | null {
    const addon = this.matcher?.rules.preferredAddonId;
    if (!addon) return null;
    return candidates.find((stream) => stream.addonInstallationId === addon) ?? null;
  }
}
