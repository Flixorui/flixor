/**
 * Leaves out addon results whose file name is for another film or show: an
 * aggregator can return "Dune Part One" for Ramayana, or "Wonder Woman 1984" for
 * Wonder Woman. A result is kept when its file name contains one of the title's
 * names (TMDB title, original title, alternative titles, translations) as whole
 * words, and any year in it is within one of the release year. For an episode, an
 * SxxEyy in the name must be the episode asked for. A result with no file name
 * can't be checked and is kept.
 * macOS reference: Services/Stremio/StremioTitleMatcher.swift
 */

import { getFlixorCore } from '../core';
import type { StremioAddonStreamResult, StremioContentIdentity, StremioPlayableStream } from './types';

export type TitleVerdict = 'match' | 'unverified' | 'mismatch';

// Letters and digits of any script; anything else separates words.
let WORD_CHAR: RegExp;
try {
  WORD_CHAR = new RegExp('[\\p{L}\\p{N}]', 'u');
} catch {
  WORD_CHAR = /[A-Za-z0-9À-ɏͰ-ϿЀ-ӿ֐-ۿऀ-෿぀-ヿ一-鿿가-힯]/;
}

/**
 * Lowercase, accents folded, "&" as "and", anything but letters and digits as one
 * space, padded with spaces so " name " only matches whole words.
 */
export function normaliseTitleText(text: string): string {
  let folded = text;
  try {
    folded = folded.normalize('NFD').replace(/[̀-ͯ]/g, '');
  } catch {
    // No normalize(): accents stay, matching still works for most names.
  }
  folded = folded.toLowerCase().replace(/&/g, ' and ');
  let out = '';
  let lastWasSpace = true;
  for (const ch of folded) {
    if (WORD_CHAR.test(ch)) {
      out += ch;
      lastWasSpace = false;
    } else if (!lastWasSpace) {
      out += ' ';
      lastWasSpace = true;
    }
  }
  return ` ${out.trim()} `;
}

/** Drops "www.site.tld - " in front and [bracketed] / {braced} tags. */
function strippingSiteTags(filename: string): string {
  return filename
    .replace(/^\s*(www\.)?[A-Za-z0-9-]+\.[A-Za-z]{2,10}\s+-\s+/, '')
    .replace(/\[[^\]]*\]|\{[^}]*\}/g, ' ');
}

function yearsIn(normalised: string): number[] {
  return normalised
    .split(' ')
    .filter((word) => word.length === 4 && /^\d{4}$/.test(word))
    .map(Number)
    .filter((value) => value >= 1900 && value <= 2099);
}

/** A line of the stream's text that looks like a file name, for addons that send no hint. */
function filenameLine(stream: StremioPlayableStream): string | undefined {
  return [stream.title, stream.description]
    .filter((part): part is string => !!part)
    .flatMap((part) => part.split('\n'))
    .map((line) => line.trim())
    .find((line) => /\.(mkv|mp4|avi|m4v|ts|m2ts|iso|webm)$/i.test(line));
}

export class StremioTitleMatcher {
  /** Normalised names, each " word word ", longest first. */
  private readonly names: string[];
  private readonly squashedNames: string[];

  constructor(
    names: string[],
    private readonly year: number | null,
    private readonly season: number | null = null,
    private readonly episode: number | null = null
  ) {
    const normalised = Array.from(new Set(names.map(normaliseTitleText).filter((n) => n.length > 2)));
    this.names = normalised.sort((a, b) => b.length - a.length);
    this.squashedNames = this.names.map((n) => n.replace(/ /g, '')).filter((n) => n.length >= 6);
  }

  forEpisode(season: number | null | undefined, episode: number | null | undefined): StremioTitleMatcher {
    const copy = Object.create(StremioTitleMatcher.prototype) as StremioTitleMatcher;
    Object.assign(copy, this, { season: season ?? null, episode: episode ?? null });
    return copy;
  }

  verdict(stream: StremioPlayableStream): TitleVerdict {
    const filename = stream.behaviorHints?.filename || filenameLine(stream);
    if (!filename) return 'unverified';
    return this.verdictForFilename(filename);
  }

  verdictForFilename(filename: string): TitleVerdict {
    const text = normaliseTitleText(strippingSiteTags(filename));
    const wrongEpisode = this.isWrongEpisode(filename);
    const name = wrongEpisode ? undefined : this.names.find((n) => text.includes(n));
    if (name) {
      // Years that are part of the title ("Blade Runner 2049") don't count.
      return this.yearFits(text.replace(name, ' ')) ? 'match' : 'mismatch';
    }
    // "emd-wonderwoman.2160p.mkv": the name run together, with no year to check.
    const squashed = text.replace(/ /g, '');
    if (!wrongEpisode && yearsIn(text).length === 0 && this.squashedNames.some((n) => squashed.includes(n))) {
      return 'match';
    }
    return 'mismatch';
  }

  /** Splits addon results into what matches (or can't be checked) and what is for another title. */
  split(results: StremioAddonStreamResult[]): { kept: StremioAddonStreamResult[]; hidden: StremioPlayableStream[] } {
    const hidden: StremioPlayableStream[] = [];
    const kept = results.map((result) => ({
      ...result,
      streams: result.streams.filter((stream) => {
        if (!stream.playable || this.verdict(stream) !== 'mismatch') return true;
        hidden.push(stream);
        return false;
      }),
    }));
    return { kept, hidden };
  }

  private yearFits(text: string): boolean {
    if (this.year == null || this.season != null) return true;
    const found = yearsIn(text);
    return found.length === 0 || found.some((y) => Math.abs(y - (this.year as number)) <= 1);
  }

  private isWrongEpisode(filename: string): boolean {
    if (this.season == null || this.episode == null) return false;
    const match = filename.match(/\bS(\d{1,2})[ ._-]?E(\d{1,3})\b|\b(\d{1,2})x(\d{2,3})\b/i);
    if (!match) return false;
    const s = Number(match[1] ?? match[3]);
    const e = Number(match[2] ?? match[4]);
    if (!Number.isFinite(s) || !Number.isFinite(e)) return false;
    return s !== this.season || e !== this.episode;
  }
}

const cache = new Map<string, StremioTitleMatcher>();
const inFlight = new Map<string, Promise<StremioTitleMatcher | null>>();

async function lookUp(identity: StremioContentIdentity, isSeries: boolean, fallbackTitle?: string): Promise<StremioTitleMatcher | null> {
  try {
    const tmdb = getFlixorCore().tmdb;
    let tmdbId = identity.tmdbId;
    const imdb = identity.imdbId ?? (identity.baseId.startsWith('tt') ? identity.baseId : undefined);
    if (tmdbId == null && imdb) {
      const found = await tmdb.findByImdbId(imdb);
      tmdbId = (isSeries ? found.tv_results?.[0] : found.movie_results?.[0])?.id;
    }
    if (tmdbId != null) {
      const { names, year } = await tmdb.getTitleNames(isSeries ? 'tv' : 'movie', tmdbId);
      // Shows span years; only movies check the year.
      if (names.length > 0) return new StremioTitleMatcher(names, isSeries ? null : year);
    }
  } catch {
    // TMDB unreachable: fall back to the title we were given, or match nothing out.
  }
  return fallbackTitle ? new StremioTitleMatcher([fallbackTitle], null) : null;
}

/**
 * A matcher for the title `identity` asks for, or null when its names can't be
 * found (then nothing is left out). Cached per title for the session.
 */
export async function titleMatcherFor(
  identity: StremioContentIdentity,
  fallbackTitle?: string
): Promise<StremioTitleMatcher | null> {
  const isSeries = identity.requestType === 'series';
  const key = `${identity.requestType}:${identity.baseId}`;
  let base = cache.get(key) ?? null;
  if (!base) {
    let pending = inFlight.get(key);
    if (!pending) {
      pending = lookUp(identity, isSeries, fallbackTitle);
      inFlight.set(key, pending);
    }
    base = await pending;
    inFlight.delete(key);
    if (base) cache.set(key, base);
  }
  if (!base || !isSeries) return base;
  return base.forEpisode(identity.seasonNumber, identity.episodeNumber);
}

/** `results` minus the ones for another title, when the title's names can be found. */
export async function withoutOtherTitles(
  identity: StremioContentIdentity,
  results: StremioAddonStreamResult[],
  fallbackTitle?: string
): Promise<StremioAddonStreamResult[]> {
  const matcher = await titleMatcherFor(identity, fallbackTitle);
  return matcher ? matcher.split(results).kept : results;
}
