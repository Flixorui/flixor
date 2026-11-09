/** Resolves Plex and TMDB items to the ids addons understand. */
import { plexBackendMetadata } from '@/services/plex_backend';
import { tmdbExternalIds } from '@/services/tmdb';
import { getSettings } from '@/state/settings';
import { canResolveId, hasStreamProviders } from './addons';
import type {
  StremioContentIdentity,
  StremioContentRef,
  StremioRequestOptions,
  StremioRequestType,
} from './types';

interface ResolvedIds {
  imdbId?: string;
  tmdbId?: number;
  seasonNumber?: number;
  episodeNumber?: number;
}

function buildIdentity(
  requestType: StremioRequestType,
  baseId: string,
  ids: ResolvedIds,
): StremioContentIdentity {
  const { seasonNumber, episodeNumber } = ids;
  const isEpisode = requestType === 'series' && seasonNumber != null && episodeNumber != null;
  return {
    requestType,
    baseId,
    requestId: isEpisode ? `${baseId}:${seasonNumber}:${episodeNumber}` : baseId,
    imdbId: ids.imdbId,
    tmdbId: ids.tmdbId,
    seasonNumber,
    episodeNumber,
  };
}

/** `movie:<baseId>` or `series:<baseId>:<season>:<episode>`, matching the macOS app. */
export function buildContentKey(identity: StremioContentIdentity): string {
  if (identity.requestType === 'movie') return `movie:${identity.baseId}`;
  return `series:${identity.baseId}:${identity.seasonNumber ?? 1}:${identity.episodeNumber ?? 1}`;
}

function idsFromGuids(guids: unknown): Pick<ResolvedIds, 'imdbId' | 'tmdbId'> {
  const ids: Pick<ResolvedIds, 'imdbId' | 'tmdbId'> = {};
  for (const entry of Array.isArray(guids) ? guids : []) {
    const value = String((entry as any)?.id ?? '');
    if (value.startsWith('imdb://')) ids.imdbId = value.slice('imdb://'.length);
    else if (value.startsWith('tmdb://')) ids.tmdbId = Number(value.slice('tmdb://'.length)) || undefined;
  }
  return ids;
}

async function metadataFor(ratingKey: string): Promise<any> {
  const response: any = await plexBackendMetadata(ratingKey);
  return response?.MediaContainer?.Metadata?.[0];
}

/** Fills in ids from Plex. An episode's own GUIDs identify the episode, so the show's are used. */
async function idsFromPlex(ref: StremioContentRef): Promise<ResolvedIds | null> {
  const metadata = await metadataFor(ref.plexRatingKey!);
  if (!metadata) return null;
  if (metadata.type === 'episode' || ref.mediaType === 'episode') {
    const showKey = metadata.grandparentRatingKey;
    const show = showKey ? await metadataFor(String(showKey)) : null;
    if (!show) return null;
    return {
      ...idsFromGuids(show.Guid),
      seasonNumber: metadata.parentIndex,
      episodeNumber: metadata.index,
    };
  }
  return idsFromGuids(metadata.Guid);
}

function throwIfAborted(signal: AbortSignal | undefined): void {
  if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');
}

export async function resolveContentIdentity(
  ref: StremioContentRef,
  options: StremioRequestOptions = {},
): Promise<StremioContentIdentity | null> {
  const requestType: StremioRequestType = ref.mediaType === 'movie' ? 'movie' : 'series';
  if (!hasStreamProviders(requestType)) return null;

  let ids: ResolvedIds = {
    imdbId: ref.imdbId,
    tmdbId: ref.tmdbId,
    seasonNumber: ref.seasonNumber,
    episodeNumber: ref.episodeNumber,
  };

  if (ref.plexRatingKey && !(ids.imdbId || ids.tmdbId)) {
    const fromPlex = await idsFromPlex(ref).catch(() => null);
    throwIfAborted(options.signal);
    if (!fromPlex) return null;
    ids = {
      imdbId: ids.imdbId ?? fromPlex.imdbId,
      tmdbId: ids.tmdbId ?? fromPlex.tmdbId,
      seasonNumber: ids.seasonNumber ?? fromPlex.seasonNumber,
      episodeNumber: ids.episodeNumber ?? fromPlex.episodeNumber,
    };
  }

  if (!ids.imdbId && ids.tmdbId) {
    const media = requestType === 'movie' ? 'movie' : 'tv';
    const external: any = await tmdbExternalIds(getSettings().tmdbBearer ?? '', media, ids.tmdbId).catch(() => null);
    throwIfAborted(options.signal);
    ids.imdbId = external?.imdb_id || undefined;
  }

  const candidates = [ids.imdbId, ids.tmdbId ? `tmdb:${ids.tmdbId}` : undefined];
  for (const baseId of candidates) {
    if (baseId && canResolveId(requestType, baseId)) return buildIdentity(requestType, baseId, ids);
  }
  return null;
}
