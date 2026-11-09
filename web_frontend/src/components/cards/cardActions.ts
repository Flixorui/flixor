/** My List and watch-state actions behind the card menu and hover preview. */
import { getSettings } from '@/state/settings';
import { getTraktTokens, traktAddToWatchlist, traktGetWatchlist, traktRemoveFromWatchlist } from '@/services/trakt';
import { plexTvAddToWatchlist, plexTvRemoveFromWatchlist, plexTvWatchlist } from '@/services/plextv';
import { markUnwatched, markWatched, type WatchTarget } from '@/services/watchState';
import { resolveCardMedia, type CardMedia } from './cardMedia';
import type { CardItem, CardMediaType } from './cardTypes';

export function appToast(message: string) {
  window.dispatchEvent(new CustomEvent('app-toast', { detail: message }));
}

export function supportsMyList(type?: CardMediaType) {
  return type === 'movie' || type === 'show';
}

function useTrakt(media: CardMedia) {
  return (getSettings().watchlistProvider || 'trakt') === 'trakt' && !!getTraktTokens() && !!media.tmdbId;
}

function plexGuidFor(media: CardMedia): string | undefined {
  if (media.tmdbId) return `tmdb://${media.tmdbId}`;
  if (media.imdbId) return `imdb://${media.imdbId}`;
  return media.plexRatingKey;
}

function myListProviderName(media: CardMedia) {
  return useTrakt(media) ? 'Trakt' : 'Plex';
}

export async function isInMyList(media: CardMedia): Promise<boolean> {
  if (useTrakt(media)) {
    const list: any[] = await traktGetWatchlist(getTraktTokens()!.access_token, media.mediaType === 'movie' ? 'movies' : 'shows');
    const wanted = Number(media.tmdbId);
    return (list || []).some((entry) => (entry.movie || entry.show || {}).ids?.tmdb === wanted);
  }
  const res: any = await plexTvWatchlist();
  const items: any[] = res?.MediaContainer?.Metadata || [];
  return items.some(
    (item) =>
      (media.plexRatingKey && String(item.ratingKey) === media.plexRatingKey) ||
      (media.tmdbId && String(item.guid || item.tmdbGuid || '').includes(`tmdb://${media.tmdbId}`)) ||
      (media.imdbId && String(item.guid || '').includes(`imdb://${media.imdbId}`)),
  );
}

/** Adds or removes a title. Reports the result with a toast and never throws. */
export async function setInMyList(media: CardMedia, inList: boolean, title: string): Promise<boolean> {
  try {
    if (useTrakt(media)) {
      const token = getTraktTokens()!.access_token;
      const payload = {
        [media.mediaType === 'movie' ? 'movies' : 'shows']: [{ ids: { tmdb: Number(media.tmdbId) } }],
      };
      if (inList) await traktAddToWatchlist(token, payload as any);
      else await traktRemoveFromWatchlist(token, payload as any);
    } else {
      const guid = plexGuidFor(media);
      if (!guid) throw new Error('This title cannot be added to My List');
      if (inList) await plexTvAddToWatchlist(guid);
      else await plexTvRemoveFromWatchlist(guid);
    }
    appToast(`${inList ? 'Added to' : 'Removed from'} ${myListProviderName(media)} Watchlist`);
    return true;
  } catch {
    appToast(`Could not update My List for ${title}`);
    return false;
  }
}

export function watchTargetFor(item: CardItem, media: CardMedia): WatchTarget | null {
  if (item.target) return item.target;
  if (item.newEpisodeCount) return null;
  const kind = media.mediaType || item.mediaType;
  if (!kind) return null;
  return {
    kind,
    plexRatingKey: media.plexRatingKey,
    tmdbId: media.tmdbId ? Number(media.tmdbId) : undefined,
    imdbId: media.imdbId,
    title: item.title,
  };
}

/** Applies a watched change. Reports the result with a toast and never throws. */
export async function setWatched(target: WatchTarget, watched: boolean, title: string) {
  try {
    const result = await (watched ? markWatched(target) : markUnwatched(target));
    appToast(result.message);
  } catch (error: any) {
    appToast(error?.message || `Could not mark ${title} as ${watched ? 'watched' : 'unwatched'}`);
  }
}

export { resolveCardMedia };
