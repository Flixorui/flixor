/**
 * Community skip segments for addon streams and Plex items without markers, merged
 * into the marker list so the skip button, auto-skip and credits trigger just work.
 * macOS reference: ViewModels/PlayerViewModel+SkipSegments.swift
 */

import { useEffect, useMemo, useState } from 'react';
import {
  extractImdbIdFromGuids,
  extractTmdbIdFromGuids,
  fetchPlexMetadata,
  fetchTmdbDetails,
} from '../../../core/DetailsData';
import { skipSegmentService } from '../../../services/skipSegments/SkipSegmentService';
import type { SkipSegment, SkipSegmentRequest } from '../../../services/skipSegments/types';
import { parseStreamSeriesRef } from '../../../stremio/StreamEpisodeNavigator';
import type { GenericStreamParams } from '../../../stremio/types';

export type PlayerMarker = {
  id?: number | string;
  type: string;
  startTimeOffset: number;
  endTimeOffset: number;
};

type Options = {
  enabled: boolean;
  animeSkipClientId: string;
  streamParams: GenericStreamParams | null;
  /** Plex metadata; null for addon streams and offline playback. */
  plexMetadata: any | null;
  plexMarkers: PlayerMarker[];
  /** True once the Plex marker request has finished. */
  plexMarkersReady: boolean;
  durationMs: number;
};

async function imdbIdFromTmdb(mediaType: 'movie' | 'tv', tmdbId: number | undefined): Promise<string | undefined> {
  if (!tmdbId) return undefined;
  const details = await fetchTmdbDetails(mediaType, tmdbId).catch(() => null);
  return details?.external_ids?.imdb_id || details?.imdb_id || undefined;
}

async function requestForStream(
  params: GenericStreamParams,
  animeSkipClientId: string
): Promise<SkipSegmentRequest | null> {
  const series = parseStreamSeriesRef(params);
  if (series) {
    const needsImdb = !series.imdbId && !series.kitsuId && !series.malId;
    return {
      imdbId: needsImdb ? await imdbIdFromTmdb('tv', series.tmdbId) : series.imdbId,
      tmdbId: series.tmdbId,
      isMovie: false,
      season: series.season,
      episode: series.episode,
      kitsuId: series.kitsuId,
      malId: series.malId,
      animeSkipClientId,
    };
  }

  if (params.mediaType !== 'movie') {
    return null;
  }
  const baseId = params.contentKey.startsWith('movie:') ? params.contentKey.slice(6) : '';
  const tmdbId = params.tmdbId || (baseId.startsWith('tmdb:') ? Number(baseId.slice(5)) || undefined : undefined);
  const imdbId =
    params.imdbId || (baseId.startsWith('tt') ? baseId : undefined) || (await imdbIdFromTmdb('movie', tmdbId));
  return imdbId ? { imdbId, tmdbId, isMovie: true, animeSkipClientId } : null;
}

async function requestForPlex(metadata: any, animeSkipClientId: string): Promise<SkipSegmentRequest | null> {
  if (metadata.type === 'episode') {
    if (!metadata.parentIndex || !metadata.index || !metadata.grandparentRatingKey) {
      return null;
    }
    const show = await fetchPlexMetadata(String(metadata.grandparentRatingKey));
    const guids = show?.Guid || [];
    const tmdbId = Number(extractTmdbIdFromGuids(guids) || '') || undefined;
    return {
      imdbId: extractImdbIdFromGuids(guids) || (await imdbIdFromTmdb('tv', tmdbId)),
      tmdbId,
      isMovie: false,
      season: metadata.parentIndex,
      episode: metadata.index,
      animeSkipClientId,
    };
  }
  if (metadata.type === 'movie') {
    const guids = metadata.Guid || [];
    const tmdbId = Number(extractTmdbIdFromGuids(guids) || '') || undefined;
    const imdbId = extractImdbIdFromGuids(guids) || (await imdbIdFromTmdb('movie', tmdbId));
    return imdbId ? { imdbId, tmdbId, isMovie: true, animeSkipClientId } : null;
  }
  return null;
}

function toMarker(segment: SkipSegment, durationMs: number): PlayerMarker | null {
  let endMs: number;
  if (segment.end !== null) {
    endMs = segment.end * 1000;
    if (durationMs > 0) endMs = Math.min(endMs, durationMs);
  } else if (durationMs > 0) {
    endMs = durationMs;
  } else {
    // Open-ended segments are rebuilt once the duration is known.
    return null;
  }
  const startMs = Math.round(segment.start * 1000);
  endMs = Math.round(endMs);
  if (endMs <= startMs) return null;
  return {
    id: `community-${segment.provider}-${segment.type}-${startMs}`,
    type: segment.type,
    startTimeOffset: startMs,
    endTimeOffset: endMs,
  };
}

export function useCommunitySkipMarkers({
  enabled,
  animeSkipClientId,
  streamParams,
  plexMetadata,
  plexMarkers,
  plexMarkersReady,
  durationMs,
}: Options): PlayerMarker[] {
  const [segments, setSegments] = useState<SkipSegment[]>([]);

  const plexHasBoth =
    plexMarkers.some((marker) => marker.type === 'intro') && plexMarkers.some((marker) => marker.type === 'credits');
  const plexKey = plexMetadata?.ratingKey ? String(plexMetadata.ratingKey) : null;
  const lookupKey = !enabled
    ? null
    : streamParams
      ? streamParams.contentKey
      : plexKey && plexMarkersReady && !plexHasBoth
        ? plexKey
        : null;

  useEffect(() => {
    if (!lookupKey) {
      setSegments([]);
      return;
    }
    let cancelled = false;
    (async () => {
      const clientId = animeSkipClientId;
      const request = streamParams
        ? await requestForStream(streamParams, clientId)
        : await requestForPlex(plexMetadata, clientId);
      const found = request ? await skipSegmentService.segments(request) : [];
      if (!cancelled) {
        setSegments(found);
      }
    })().catch(() => {
      // Community data is optional; playback carries on without it.
    });
    return () => {
      cancelled = true;
    };
    // The lookup is identified by lookupKey; the objects behind it don't need to re-trigger it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [animeSkipClientId, lookupKey]);

  return useMemo(() => {
    // Community segments only fill in the types Plex didn't provide.
    const plexTypes = new Set(plexMarkers.map((marker) => marker.type));
    const community = segments
      .filter((segment) => !plexTypes.has(segment.type))
      .map((segment) => toMarker(segment, durationMs))
      .filter(Boolean) as PlayerMarker[];
    return community.length === 0
      ? plexMarkers
      : [...plexMarkers, ...community].sort((left, right) => left.startTimeOffset - right.startTimeOffset);
  }, [durationMs, plexMarkers, segments]);
}
