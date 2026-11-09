import type { WatchTarget } from '@/services/watchState';

export type CardMediaType = 'movie' | 'show' | 'season' | 'episode';

/** What a card knows about its title. Only `id` and `title` are required. */
export interface CardItem {
  /** Canonical id: `plex:<ratingKey>`, `tmdb:<movie|tv>:<id>` or `stremio:<type>:<id>`. */
  id: string;
  title: string;
  image?: string;
  /** Wide artwork when the source has it. Used by the hero and landscape cards. */
  backdrop?: string;
  subtitle?: string;
  badge?: string;
  mediaType?: CardMediaType;
  year?: string | number;
  /** Out of 10. */
  rating?: number;
  overview?: string;
  /** Set on "N new episodes" cards, which stand for episodes rather than the show. */
  newEpisodeCount?: number;

  // Continue Watching
  /** 0 to 100. */
  progress?: number;
  duration?: number;
  viewOffset?: number;
  episodeInfo?: string;
  showTitle?: string;
  isNextUp?: boolean;
  target?: WatchTarget;
}

/** An extra action a card's owner adds to the bottom of its context menu. */
export interface CardMenuAction {
  label: string;
  danger?: boolean;
  onSelect: () => void;
}

export type CardSurface = 'row' | 'library';

export function parseCardId(rawId: string):
  | { source: 'plex'; ratingKey: string }
  | { source: 'tmdb'; media: 'movie' | 'tv'; tmdbId: string }
  | { source: 'stremio'; type: string; stremioId: string }
  | { source: 'unknown' } {
  const id = (rawId || '').replaceAll('%3A', ':');
  if (id.startsWith('plex:')) return { source: 'plex', ratingKey: id.slice(5) };
  if (id.startsWith('tmdb:')) {
    const [, media, tmdbId] = id.split(':');
    if ((media === 'movie' || media === 'tv') && tmdbId) return { source: 'tmdb', media, tmdbId };
  }
  if (id.startsWith('stremio:')) {
    const [, type, ...rest] = id.split(':');
    if (type && rest.length) return { source: 'stremio', type, stremioId: rest.join(':') };
  }
  return { source: 'unknown' };
}
