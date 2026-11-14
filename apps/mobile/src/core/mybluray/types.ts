/**
 * MyBluray v2 API shapes, trimmed to what Flixor uses.
 * See apps/mobile/MYBLURAY_PARITY.md §2 for what each field means.
 */

export interface MBProvenance {
  provider?: string | null;
  sourceUrl?: string | null;
}

export interface MBRating {
  provider: string; // imdb, rotten-tomatoes, letterboxd, tmdb, justwatch
  kind: string; // community, critics-percentage, audience-percentage, critic-average, weighted-community
  value?: number | null;
  scale?: number | null;
  voteCount?: number | null;
  freshness?: string | null;
  certifiedFresh?: boolean | null;
  freshReviews?: number | null;
  rottenReviews?: number | null;
  consensus?: string | null;
  websiteUrl?: string | null;
  provenance?: MBProvenance | null;
}

export interface MBGuidance {
  provider?: string | null;
  recommendedAge?: number | null;
  summary?: string | null;
  categories: { name: string; value?: number | null; scale?: number | null }[];
}

export interface MBCertification {
  system?: string | null;
  value?: string | null;
  explanation?: string | null;
  advisories?: string[] | null;
}

export interface MBVideo {
  providerId?: string | null;
  kind?: string | null; // trailer, teaser, clip, featurette, vertical
  title?: string | null;
  durationSeconds?: number | null;
  host: string; // apple-tv, justwatch, youtube, dailymotion
  url?: string | null;
  playbackUrl?: string | null;
  playback?: string | null; // direct-hls | direct-mp4 | external-host
  thumbnailUrl?: string | null;
}

export interface MBSourceStatus {
  provider: string;
  status: string;
  sourceUrl?: string | null;
}

export interface MBTitle {
  id?: string;
  imdbId?: string | null;
  title?: string | null;
  year?: number | null;
  ratings: MBRating[];
  parentalGuidance: MBGuidance[];
  certifications: MBCertification[];
  videos: MBVideo[];
  sources: MBSourceStatus[];
}

export interface MBParentsGuideCategory {
  category: string;
  label?: string | null;
  severity?: string | null; // none, mild, moderate, severe
  severityLabel?: string | null;
  totalVotes?: number | null;
  votes?: { none?: number; mild?: number; moderate?: number; severe?: number } | null;
  descriptions: { id?: string | null; text: string; isSpoiler?: boolean | null }[];
}

export interface MBParentsGuide {
  titleId?: string | null;
  status?: string | null;
  websiteUrl?: string | null;
  certification?: { rating?: string | null; country?: string | null; reason?: string | null } | null;
  categories: MBParentsGuideCategory[];
}

export interface MBMovie {
  id: string; // movie:18630
  title?: string | null;
  year?: number | null;
  websiteUrl?: string | null;
  imdbId?: string | null;
}

export interface MBCountry {
  code?: string | null;
  name?: string | null;
}

export interface MBEditionSummary {
  id: string; // bluray:187101
  title?: string | null;
  year?: number | null;
  country?: MBCountry | null;
  coverImage?: string | null;
  releaseDate?: string | null; // yyyy-MM-dd
  format?: string | null; // 4k | bluray
  bundle?: boolean | null;
}

export interface MBScoreSet {
  scale?: number | null;
  scores?: Record<string, number> | null; // nulls removed when parsed
  voteCount?: number | null;
  author?: string | null;
  sourceUrl?: string | null;
}

export interface MBEdition extends MBEditionSummary {
  editionTitle?: string | null;
  websiteUrl?: string | null;
  exclusive?: string | null;
  region?: string[] | null;
  video?: { codec?: string | null; resolution?: string | null; hdr?: string | null; aspectRatio?: string | null; originalAspectRatio?: string | null } | null;
  audio?: string[] | null;
  subtitles?: string | null;
  discs?: string[] | null;
  packaging?: string[] | null;
  screenshots: { url: string; thumbnailUrl?: string | null; provenance?: { note?: string | null } | null }[];
  artwork: { type?: string | null; url: string }[];
  reviewScores?: { critic?: MBScoreSet | null; communityReviews?: MBScoreSet | null; communityRatings?: MBScoreSet | null } | null;
  digitalCopy?: { included?: boolean | null; resolution?: string | null; platforms: { value?: string | null; label?: string | null }[] } | null;
  metadata?: {
    studio?: string | null;
    synopsis?: string | null;
    runtime?: number | null;
    amazon?: { purchaseUrl?: string | null; currency?: string | null; price?: string | null; listPrice?: string | null; availability?: string | null } | null;
  } | null;
}

export interface MBListRef {
  id?: string | null;
  alias?: string | null; // owned, wishlist, want-to-buy…
  name?: string | null;
}

export interface MBCollectionEntry extends MBEditionSummary {
  list?: MBListRef | null;
  addedAt?: string | null;
}

export interface MBCollectionList {
  id: string; // bluray:1
  name?: string | null;
  alias?: string | null;
  system?: boolean | null;
  displayOrder?: number | null;
}

export type AccessState = 'yes' | 'no' | 'unknown';

/** What a key can reach (from MyBlurayService.checkKey). */
export interface MyBlurayAccess {
  'apple-tv': AccessState;
  justwatch: AccessState;
  letterboxd: AccessState;
  imdb: AccessState;
  bluray: AccessState;
  collection: AccessState;
}
