import { useEffect, useState } from 'react';
import { fetchSkipSegments, SkipSegment, SkipSegmentRequest } from '@/services/skipSegments';
import { useSettings } from '@/state/settings';

/** Community segments for a request. Null means there is nothing to look up (yet). */
export function useCommunitySegments(request: Omit<SkipSegmentRequest, 'animeSkipClientId'> | null): SkipSegment[] {
  const { communitySkipSegmentsEnabled: enabled, animeSkipClientId } = useSettings();
  const [segments, setSegments] = useState<SkipSegment[]>([]);
  const requestKey = request ? JSON.stringify(request) : null;

  useEffect(() => {
    setSegments([]);
    if (!requestKey || !enabled) return;
    const controller = new AbortController();
    const body = { ...JSON.parse(requestKey), animeSkipClientId: animeSkipClientId.trim() || undefined };
    fetchSkipSegments(body, controller.signal).then((result) => {
      if (!controller.signal.aborted) setSegments(result);
    });
    return () => controller.abort();
  }, [requestKey, enabled, animeSkipClientId]);

  return segments;
}
