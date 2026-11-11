/**
 * FlixPatrol JSON API (v2) and Streaming Availability (Movie of the Night) v4: the parts the
 * Top 10 rows read. Both send the same show shape.
 * macOS reference: Models/StreamingAvailabilityModels.swift
 */

export type StreamingServiceId =
  | 'netflix' | 'prime' | 'disney' | 'apple' | 'hbo' | 'paramount' | 'hulu' | 'starz' | 'hotstar';

export const ALL_SERVICES: StreamingServiceId[] = ['netflix', 'prime', 'disney', 'apple', 'hbo', 'paramount', 'hulu', 'starz', 'hotstar'];

/** On before FlixPatrol added more; also the five Streaming Availability has charts for. */
export const DEFAULT_TOP_SERVICES: StreamingServiceId[] = ['netflix', 'prime', 'disney', 'apple', 'hbo'];

export function hasStreamingAvailability(service: StreamingServiceId): boolean {
  return DEFAULT_TOP_SERVICES.includes(service);
}

export const SERVICE_NAMES: Record<StreamingServiceId, string> = {
  netflix: 'Netflix',
  prime: 'Prime Video',
  disney: 'Disney+',
  apple: 'Apple TV+',
  hbo: 'Max',
  paramount: 'Paramount+',
  hulu: 'Hulu',
  starz: 'Starz',
  hotstar: 'JioHotstar',
};

/** Brand colours for the settings icons. */
export const SERVICE_COLORS: Record<StreamingServiceId, string> = {
  netflix: '#E50914',
  prime: '#00A8E1',
  disney: '#113CCF',
  apple: '#3A3A3C',
  hbo: '#002BE7',
  paramount: '#0064FF',
  hulu: '#1CE783',
  starz: '#2C2C2E',
  hotstar: '#1F2A44',
};

type ImageSizes = Partial<Record<'w240' | 'w342' | 'w360' | 'w480' | 'w500' | 'w600' | 'w720' | 'w780' | 'w1280' | 'original', string>>;

export type SAShow = {
  id: string;
  showType: 'movie' | 'series' | string;
  title: string;
  overview?: string;
  releaseYear?: number;
  firstAirYear?: number;
  imdbId?: string;
  /** "movie/123" or "tv/456". */
  tmdbId?: string;
  rating?: number;
  imageSet?: { verticalPoster?: ImageSizes; horizontalBackdrop?: ImageSizes };
  /** FlixPatrol only: chart positions. */
  rankings?: Array<{ category: string; rank: number }>;
};

export type SAChangesResult = {
  changes: Array<{ showId: string; streamingOptionType?: string | null }>;
  shows: Record<string, SAShow>;
};

export type SACountry = { countryCode: string; name: string; services: Array<{ id: string; name?: string }> };

export type SAQuota = { used: number; granted: number; resetsAt?: number; observedAt: number };

export const quotaRemaining = (q: SAQuota) => Math.max(0, q.granted - q.used);

export const isSeries = (show: SAShow) => show.showType === 'series';

export function posterUrl(show: SAShow): string | undefined {
  const p = show.imageSet?.verticalPoster;
  return p ? p.w480 ?? p.w500 ?? p.w360 ?? p.w342 ?? p.w600 ?? p.w780 ?? p.w240 : undefined;
}

export function backdropUrl(show: SAShow): string | undefined {
  const b = show.imageSet?.horizontalBackdrop;
  return b ? b.w720 ?? b.w780 ?? b.w600 ?? b.w1280 ?? b.w480 : undefined;
}

/** The TMDB id and type for Details, or null without a TMDB id. */
export function tmdbRef(show: SAShow): { tmdbId: number; mediaType: 'movie' | 'tv' } | null {
  const [kind, id] = (show.tmdbId ?? '').split('/');
  const tmdbId = Number(id);
  if (!kind || !id || Number.isNaN(tmdbId)) return null;
  return { tmdbId, mediaType: kind === 'tv' ? 'tv' : 'movie' };
}

/** Countries offered in Settings (both APIs cover these). */
export const REGIONS: Array<{ code: string; name: string }> = [
  { code: 'us', name: 'United States' }, { code: 'in', name: 'India' }, { code: 'gb', name: 'United Kingdom' },
  { code: 'ca', name: 'Canada' }, { code: 'au', name: 'Australia' }, { code: 'de', name: 'Germany' },
  { code: 'fr', name: 'France' }, { code: 'es', name: 'Spain' }, { code: 'it', name: 'Italy' },
  { code: 'br', name: 'Brazil' }, { code: 'mx', name: 'Mexico' }, { code: 'jp', name: 'Japan' },
  { code: 'kr', name: 'South Korea' }, { code: 'nl', name: 'Netherlands' }, { code: 'se', name: 'Sweden' },
  { code: 'ie', name: 'Ireland' }, { code: 'nz', name: 'New Zealand' }, { code: 'sg', name: 'Singapore' },
  { code: 'ae', name: 'United Arab Emirates' }, { code: 'za', name: 'South Africa' },
];

export function deviceRegion(): string {
  try {
    const locale = Intl.DateTimeFormat().resolvedOptions().locale || '';
    const region = locale.split(/[-_]/)[1]?.toLowerCase();
    if (region && region.length === 2) return region;
  } catch {
    // fall through
  }
  return 'us';
}
