/**
 * One list of ratings for Details, built from every source the app has:
 * MyBluray (main), Plex, MDBList (extra, and the only source of Metacritic
 * and Trakt) and TMDB. Each rating comes from the source picked in
 * Settings → Details Screen, or, on Automatic (and when the picked source
 * has nothing), from the first source in `RATING_META[kind].sources` that has
 * it. Port of macOS Services/Ratings/MergedRatings.swift.
 */
import type { AppSettings } from '../SettingsData';
import type { MDBListRatings } from '../MDBListService';
import type { MBRating } from '../mybluray/types';

export type RatingKind = 'imdb' | 'rtCritics' | 'rtAudience' | 'letterboxd' | 'metacritic' | 'tmdb' | 'trakt';
export type RatingSource = 'automatic' | 'mybluray' | 'plex' | 'mdblist' | 'tmdb';

export const RATING_KINDS: RatingKind[] = ['imdb', 'rtCritics', 'rtAudience', 'letterboxd', 'metacritic', 'tmdb', 'trakt'];

export const RATING_META: Record<RatingKind, { title: string; subtitle: string; defaultShown: boolean; sources: RatingSource[] }> = {
  imdb: { title: 'IMDb', subtitle: 'Out of 10, from IMDb users', defaultShown: true, sources: ['mybluray', 'plex', 'mdblist'] },
  rtCritics: { title: 'Rotten Tomatoes (Critics)', subtitle: 'Tomatometer', defaultShown: true, sources: ['mybluray', 'plex', 'mdblist'] },
  rtAudience: { title: 'Rotten Tomatoes (Audience)', subtitle: 'Popcornmeter', defaultShown: true, sources: ['mybluray', 'plex', 'mdblist'] },
  letterboxd: { title: 'Letterboxd', subtitle: 'Out of 5, from Letterboxd members', defaultShown: true, sources: ['mybluray', 'mdblist'] },
  metacritic: { title: 'Metacritic', subtitle: 'Metascore from critics', defaultShown: false, sources: ['mdblist'] },
  tmdb: { title: 'TMDB', subtitle: 'Out of 10, from TMDB users', defaultShown: false, sources: ['mybluray', 'tmdb', 'mdblist'] },
  trakt: { title: 'Trakt', subtitle: 'From Trakt users', defaultShown: false, sources: ['mdblist'] },
};

export const SOURCE_TITLES: Record<RatingSource, string> = {
  automatic: 'Automatic',
  mybluray: 'MyBluray',
  plex: 'Plex',
  mdblist: 'MDBList',
  tmdb: 'TMDB',
};

export interface MergedRating {
  kind: RatingKind;
  /** On the kind's own scale: IMDb, TMDB 0–10; RT, Metacritic, Trakt 0–100; Letterboxd 0–5. */
  value: number;
  source: Exclude<RatingSource, 'automatic'>;
  votes?: number;
  certifiedFresh?: boolean;
  reviews?: { fresh: number; rotten: number };
  consensus?: string;
}

export interface RatingInputs {
  mybluray: MBRating[];
  plexImdb?: number;
  plexCritics?: number;
  plexAudience?: number;
  mdblist?: MDBListRatings | null;
  tmdb?: number;
}

/** IMDb and Rotten Tomatoes keep their original on/off settings, so earlier choices carry over. */
export function isRatingShown(kind: RatingKind, settings: AppSettings): boolean {
  switch (kind) {
    case 'imdb': return settings.showIMDbRating ?? true;
    case 'rtCritics': return settings.showRottenTomatoesCritic ?? true;
    case 'rtAudience': return settings.showRottenTomatoesAudience ?? true;
    default: return settings.ratingShown?.[kind] ?? RATING_META[kind].defaultShown;
  }
}

/** The settings change that shows or hides a rating. */
export function ratingShownPatch(kind: RatingKind, shown: boolean, settings: AppSettings): Partial<AppSettings> {
  switch (kind) {
    case 'imdb': return { showIMDbRating: shown };
    case 'rtCritics': return { showRottenTomatoesCritic: shown };
    case 'rtAudience': return { showRottenTomatoesAudience: shown };
    default: return { ratingShown: { ...(settings.ratingShown ?? {}), [kind]: shown } };
  }
}

export function ratingSource(kind: RatingKind, settings: AppSettings): RatingSource {
  const raw = settings.ratingSource?.[kind] as RatingSource | undefined;
  if (!raw || raw === 'automatic') return 'automatic';
  return RATING_META[kind].sources.includes(raw) ? raw : 'automatic';
}

export function ratingText(r: MergedRating): string {
  switch (r.kind) {
    case 'imdb':
    case 'tmdb':
    case 'letterboxd':
      return r.value.toFixed(1);
    case 'metacritic':
      return String(Math.round(r.value));
    default:
      return `${Math.round(r.value)}%`;
  }
}

/** Long-press text: what the score is and where it came from. */
export function ratingHelp(r: MergedRating): string {
  const parts = [`${RATING_META[r.kind].title} ${ratingText(r)}`];
  if (r.certifiedFresh) parts.push('Certified Fresh');
  if (r.votes) parts.push(`${r.votes.toLocaleString('en-US')} votes`);
  if (r.reviews) parts.push(`${(r.reviews.fresh + r.reviews.rotten).toLocaleString('en-US')} reviews`);
  parts.push(`via ${SOURCE_TITLES[r.source]}`);
  const line = parts.join(' · ');
  return r.consensus ? `${line}\n\n${r.consensus}` : line;
}

export function mergeRatings(inputs: RatingInputs, settings: AppSettings): MergedRating[] {
  const out: MergedRating[] = [];
  for (const kind of RATING_KINDS) {
    if (!isRatingShown(kind, settings)) continue;
    const picked = ratingSource(kind, settings);
    let rating = picked !== 'automatic' ? ratingFrom(kind, picked, inputs) : null;
    if (!rating) {
      for (const candidate of RATING_META[kind].sources) {
        rating = ratingFrom(kind, candidate, inputs);
        if (rating) break;
      }
    }
    if (rating) out.push(rating);
  }
  return out;
}

/** Which sources have this rating for the title on screen (for the settings picker). */
export function ratingFrom(kind: RatingKind, source: RatingSource, inputs: RatingInputs): MergedRating | null {
  const make = (value: number | undefined | null, extra: Partial<MergedRating> = {}): MergedRating | null => {
    if (value == null || !Number.isFinite(value) || value <= 0) return null;
    return { kind, value, source: source as MergedRating['source'], ...extra };
  };
  switch (source) {
    case 'automatic':
      return null;
    case 'mybluray': {
      const match = myblurayRating(kind, inputs.mybluray);
      if (!match) return null;
      const r = make(normalized(match.value, match.scale, kind), {
        votes: match.voteCount ?? undefined,
        certifiedFresh: match.certifiedFresh === true || match.freshness === 'CertifiedFresh',
        consensus: match.consensus ?? undefined,
      });
      if (r && match.freshReviews != null && match.rottenReviews != null) {
        r.reviews = { fresh: match.freshReviews, rotten: match.rottenReviews };
      }
      return r;
    }
    case 'plex':
      if (kind === 'imdb') return make(inputs.plexImdb);
      if (kind === 'rtCritics') return make(inputs.plexCritics);
      if (kind === 'rtAudience') return make(inputs.plexAudience);
      return null;
    case 'mdblist': {
      const m = inputs.mdblist;
      if (!m) return null;
      switch (kind) {
        case 'imdb': return make(m.imdb);
        case 'rtCritics': return make(m.tomatoes);
        case 'rtAudience': return make(m.audience);
        case 'letterboxd': return make(m.letterboxd);
        case 'metacritic': return make(m.metacritic);
        // MDBList gives TMDB out of 100 for some titles and 10 for others
        case 'tmdb': return make(m.tmdb != null ? (m.tmdb > 10 ? m.tmdb / 10 : m.tmdb) : undefined);
        case 'trakt': return make(m.trakt != null ? (m.trakt <= 10 ? m.trakt * 10 : m.trakt) : undefined);
      }
      return null;
    }
    case 'tmdb':
      return kind === 'tmdb' ? make(inputs.tmdb) : null;
  }
}

/** MyBluray can list Rotten Tomatoes twice (Apple and JustWatch); Apple's copy is preferred. */
function myblurayRating(kind: RatingKind, ratings: MBRating[]): MBRating | undefined {
  const matches = ratings.filter((r) => {
    switch (kind) {
      case 'imdb': return r.provider === 'imdb';
      case 'rtCritics': return r.provider === 'rotten-tomatoes' && r.kind === 'critics-percentage';
      case 'rtAudience': return r.provider === 'rotten-tomatoes' && r.kind === 'audience-percentage';
      case 'letterboxd': return r.provider === 'letterboxd';
      case 'tmdb': return r.provider === 'tmdb';
      case 'metacritic': return r.provider === 'metacritic';
      case 'trakt': return r.provider === 'trakt';
    }
  });
  return matches.find((r) => r.provenance?.provider === 'apple-tv') ?? matches[0];
}

function normalized(value: number | null | undefined, scale: number | null | undefined, kind: RatingKind): number | undefined {
  if (value == null) return undefined;
  const target = kind === 'imdb' || kind === 'tmdb' ? 10 : kind === 'letterboxd' ? 5 : 100;
  if (!scale || scale <= 0 || scale === target) return value;
  return (value / scale) * target;
}
