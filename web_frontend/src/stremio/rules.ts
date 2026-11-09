/**
 * "Match my rules" evaluation, ported from StreamAutoSelector.swift. It keeps the macOS
 * safeguards against bad patterns: nested repeats are rejected, text is capped, and
 * regexes run under a time budget. JavaScript cannot interrupt a regex, so the budget
 * is enforced by running patterns in a worker that gets terminated.
 */
import { getSettings } from '@/state/settings';
import { resolutionBucket } from './ranking';
import type { StremioStream } from './types';

export interface StreamRules {
  include: string;
  includeIsRegex: boolean;
  exclude: string;
  preferredAddonId?: string;
  maxResolution?: number;
}

export type RuleError = 'invalidInclude' | 'unsafeInclude' | 'invalidExclude';
export type RuleVerdict = 'match' | 'missingInclude' | 'excluded' | 'aboveResolutionLimit' | 'timedOut';

export interface RuleSubject {
  text: string;
  resolution?: number;
}

const MAX_TEXT_LENGTH = 1_000;
const MAX_PATTERN_LENGTH = 300;

export class StreamRulesError extends Error {
  constructor(readonly code: RuleError) {
    super(code);
  }
}

export function getStreamRules(): StreamRules {
  const settings = getSettings();
  return {
    include: settings.stremioRulesInclude,
    includeIsRegex: settings.stremioRulesIncludeRegex,
    exclude: settings.stremioRulesExclude,
    preferredAddonId: settings.stremioRulesPreferredAddon || undefined,
    maxResolution: settings.stremioRulesMaxResolution || undefined,
  };
}

const escapeRegex = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Whole-word, case-insensitive match for `|`, `,` or newline separated words. */
function wordsRegex(text: string): RegExp | undefined {
  const words = text.split(/[|,\n]/).map((word) => word.trim()).filter(Boolean);
  if (words.length === 0) return undefined;
  return new RegExp(`(?<![\\p{L}\\p{N}])(?:${words.map(escapeRegex).join('|')})(?![\\p{L}\\p{N}])`, 'iu');
}

/** True when a group containing an open-ended repeat is itself repeated, like `(a+)+`. */
export function hasNestedRepeat(pattern: string): boolean {
  const chars = [...pattern];
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
      if (hadRepeat && groupHasRepeat.length > 0) groupHasRepeat[groupHasRepeat.length - 1] = true;
    }
  }
  return false;
}

/** Runs the pattern in a worker. Resolves null if it ran out of time or failed to start. */
function matchInWorker(pattern: string, texts: string[], budgetMs: number): Promise<boolean[] | null> {
  if (typeof Worker === 'undefined') return Promise.resolve(null);
  return new Promise((resolve) => {
    let worker: Worker;
    try {
      worker = new Worker(new URL('./ruleWorker.ts', import.meta.url), { type: 'module' });
    } catch {
      resolve(null);
      return;
    }
    const finish = (result: boolean[] | null) => {
      clearTimeout(timer);
      worker.terminate();
      resolve(result);
    };
    const timer = setTimeout(() => finish(null), budgetMs);
    worker.onmessage = (event: MessageEvent<boolean[]>) => finish(event.data);
    worker.onerror = () => finish(null);
    worker.postMessage({ pattern, texts });
  });
}

export function searchableText(stream: StremioStream): string {
  // The URL is left out on purpose: tokens in it, or a .ts path, would trip words like "TS".
  return [stream.addonName, stream.name, stream.title, stream.description, stream.quality, stream.behaviorHints?.filename]
    .filter(Boolean)
    .join(' ');
}

export function subjectFor(stream: StremioStream): RuleSubject {
  return { text: searchableText(stream), resolution: resolutionBucket(stream) };
}

export class StreamRuleMatcher {
  private readonly includeWords?: RegExp;
  private readonly includePattern?: string;
  private readonly exclude?: RegExp;
  private remainingBudgetMs: number;
  private exhausted = false;

  /** Throws StreamRulesError when a pattern is invalid or unsafe. */
  constructor(readonly rules: StreamRules, budgetMs = 1_000) {
    this.remainingBudgetMs = budgetMs;
    if (rules.includeIsRegex) {
      const pattern = rules.include.trim();
      if (pattern) {
        if (pattern.length > MAX_PATTERN_LENGTH || hasNestedRepeat(pattern)) {
          throw new StreamRulesError('unsafeInclude');
        }
        try {
          new RegExp(pattern, 'i');
        } catch {
          throw new StreamRulesError('invalidInclude');
        }
        this.includePattern = pattern;
      }
    } else {
      try {
        this.includeWords = wordsRegex(rules.include);
      } catch {
        throw new StreamRulesError('invalidInclude');
      }
    }
    try {
      this.exclude = wordsRegex(rules.exclude);
    } catch {
      throw new StreamRulesError('invalidExclude');
    }
  }

  /** The include pattern took too long, so automatic selection should give up. */
  get timedOut(): boolean {
    return this.exhausted;
  }

  async verdicts(subjects: RuleSubject[]): Promise<RuleVerdict[]> {
    const texts = subjects.map((subject) => subject.text.slice(0, MAX_TEXT_LENGTH));
    const verdicts: RuleVerdict[] = subjects.map((subject, index) => {
      if (this.exclude?.test(texts[index])) return 'excluded';
      const { maxResolution } = this.rules;
      // An unknown resolution passes the limit; ranking already puts it last.
      if (maxResolution && subject.resolution && subject.resolution > maxResolution) return 'aboveResolutionLimit';
      if (this.includeWords && !this.includeWords.test(texts[index])) return 'missingInclude';
      return 'match';
    });
    if (!this.includePattern) return verdicts;

    const pending = verdicts.flatMap((verdict, index) => (verdict === 'match' ? [index] : []));
    if (pending.length === 0) return verdicts;
    const started = Date.now();
    const found = this.exhausted
      ? null
      : await matchInWorker(this.includePattern, pending.map((index) => texts[index]), Math.max(this.remainingBudgetMs, 0));
    this.remainingBudgetMs -= Date.now() - started;
    if (!found || this.remainingBudgetMs <= 0) this.exhausted = true;
    pending.forEach((index, position) => {
      verdicts[index] = found ? (found[position] ? 'match' : 'missingInclude') : 'timedOut';
    });
    return verdicts;
  }
}
