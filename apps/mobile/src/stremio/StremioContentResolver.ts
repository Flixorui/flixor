import {
  extractImdbIdFromGuids,
  extractTmdbIdFromGuids,
  fetchPlexMetadata,
  fetchTmdbDetails,
} from '../core/DetailsData';
import { stremioService } from './StremioService';
import type { StremioContentIdentity } from './types';

export type StremioResolverResult = {
  identity?: StremioContentIdentity;
  error?: 'no_stream_addons' | 'unsupported_id' | 'unresolved';
};

function buildIdentity(
  requestType: 'movie' | 'series',
  baseId: string,
  source: StremioContentIdentity['source'],
  extras?: {
    imdbId?: string;
    tmdbId?: number;
    seasonNumber?: number;
    episodeNumber?: number;
  }
): StremioContentIdentity {
  const requestId =
    requestType === 'series' && extras?.seasonNumber && extras?.episodeNumber
      ? `${baseId}:${extras.seasonNumber}:${extras.episodeNumber}`
      : baseId;

  return {
    requestType,
    baseId,
    requestId,
    imdbId: extras?.imdbId,
    tmdbId: extras?.tmdbId,
    seasonNumber: extras?.seasonNumber,
    episodeNumber: extras?.episodeNumber,
    source,
  };
}

async function chooseSupportedIdentity(
  requestType: 'movie' | 'series',
  candidates: Array<{
    baseId: string;
    source: StremioContentIdentity['source'];
    imdbId?: string;
    tmdbId?: number;
    seasonNumber?: number;
    episodeNumber?: number;
  }>
): Promise<StremioContentIdentity | undefined> {
  for (const candidate of candidates) {
    const supported = await stremioService.canResolveId(requestType, candidate.baseId);
    if (supported) {
      return buildIdentity(requestType, candidate.baseId, candidate.source, candidate);
    }
  }
  return undefined;
}

export function buildStremioContentKey(identity: StremioContentIdentity): string {
  if (identity.requestType === 'movie') {
    return `movie:${identity.baseId}`;
  }
  return `series:${identity.baseId}:${identity.seasonNumber || 1}:${identity.episodeNumber || 1}`;
}

export async function resolveStremioIdentityFromPlexMetadata(
  metadata: any,
  options?: {
    seasonNumber?: number;
    episodeNumber?: number;
  }
): Promise<StremioResolverResult> {
  const hasStreamAddons = await stremioService.hasStreamProviders();
  if (!hasStreamAddons) {
    return { error: 'no_stream_addons' };
  }

  if (!metadata) {
    return { error: 'unresolved' };
  }

  const mediaType = metadata.type;
  const requestType: 'movie' | 'series' = mediaType === 'movie' ? 'movie' : 'series';

  let guidSource = metadata;
  if (mediaType === 'episode' && metadata.grandparentRatingKey) {
    try {
      const showMetadata = await fetchPlexMetadata(String(metadata.grandparentRatingKey));
      if (showMetadata) {
        guidSource = showMetadata;
      }
    } catch {
      // Ignore and fall back to episode GUIDs if present.
    }
  }

  const guids = guidSource?.Guid || metadata?.Guid || [];
  const imdbId = extractImdbIdFromGuids(guids) || undefined;
  const tmdbId = Number(extractTmdbIdFromGuids(guids) || '') || undefined;
  const seasonNumber = options?.seasonNumber ?? metadata?.parentIndex;
  const episodeNumber = options?.episodeNumber ?? metadata?.index;

  const candidates = [
    imdbId
      ? {
          baseId: imdbId,
          source: 'plex-guid' as const,
          imdbId,
          tmdbId,
          seasonNumber,
          episodeNumber,
        }
      : null,
    tmdbId
      ? {
          baseId: `tmdb:${tmdbId}`,
          source: 'plex-guid' as const,
          imdbId,
          tmdbId,
          seasonNumber,
          episodeNumber,
        }
      : null,
  ].filter(Boolean) as Array<{
    baseId: string;
    source: StremioContentIdentity['source'];
    imdbId?: string;
    tmdbId?: number;
    seasonNumber?: number;
    episodeNumber?: number;
  }>;

  const identity = await chooseSupportedIdentity(requestType, candidates);
  return identity ? { identity } : { error: 'unsupported_id' };
}

export async function resolveStremioIdentityFromTmdb(
  mediaType: 'movie' | 'tv',
  tmdbId: number,
  options?: {
    seasonNumber?: number;
    episodeNumber?: number;
    tmdbDetails?: any;
  }
): Promise<StremioResolverResult> {
  const hasStreamAddons = await stremioService.hasStreamProviders();
  if (!hasStreamAddons) {
    return { error: 'no_stream_addons' };
  }

  if (!tmdbId) {
    return { error: 'unresolved' };
  }

  let details = options?.tmdbDetails;
  const missingExternalIds =
    !details ||
    ((details?.id || details?.tmdbId) !== tmdbId) ||
    (!details?.external_ids?.imdb_id && !details?.imdb_id);

  if (missingExternalIds) {
    details = await fetchTmdbDetails(mediaType, tmdbId);
  }

  const imdbId = details?.external_ids?.imdb_id || details?.imdb_id || undefined;
  const requestType = mediaType === 'movie' ? 'movie' : 'series';
  const seasonNumber = options?.seasonNumber;
  const episodeNumber = options?.episodeNumber;

  const candidates = [
    imdbId
      ? {
          baseId: imdbId,
          source: 'tmdb-external-ids' as const,
          imdbId,
          tmdbId,
          seasonNumber,
          episodeNumber,
        }
      : null,
    {
      baseId: `tmdb:${tmdbId}`,
      source: 'tmdb' as const,
      imdbId,
      tmdbId,
      seasonNumber,
      episodeNumber,
    },
  ].filter(Boolean) as Array<{
    baseId: string;
    source: StremioContentIdentity['source'];
    imdbId?: string;
    tmdbId?: number;
    seasonNumber?: number;
    episodeNumber?: number;
  }>;

  const identity = await chooseSupportedIdentity(requestType, candidates);
  return identity ? { identity } : { error: 'unsupported_id' };
}
