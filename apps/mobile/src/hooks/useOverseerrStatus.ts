import { useCallback, useEffect, useState } from 'react';
import {
  isOverseerrReady,
  getMediaStatus,
  requestMedia,
  clearOverseerrCacheItem,
  OverseerrMediaStatus,
  OverseerrRequestResult,
  OverseerrStatus,
} from '../core/OverseerrService';

interface UseOverseerrStatusResult {
  status: OverseerrStatus;
  canRequest: boolean;
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  submitRequest: (is4k?: boolean) => Promise<OverseerrRequestResult>;
  isRequesting: boolean;
}

/**
 * Hook to fetch and manage Overseerr request status for a media item
 * Only fetches if Overseerr is enabled and tmdbId is provided
 */
export function useOverseerrStatus(
  tmdbId: number | string | undefined,
  mediaType: 'movie' | 'tv'
): UseOverseerrStatusResult {
  const [statusData, setStatusData] = useState<OverseerrMediaStatus>({
    status: 'unknown',
    canRequest: false,
  });
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isRequesting, setIsRequesting] = useState(false);

  const numericTmdbId = tmdbId ? Number(tmdbId) : undefined;

  const fetchStatus = useCallback(async () => {
    if (!numericTmdbId || !isOverseerrReady()) {
      setStatusData({ status: 'unknown', canRequest: false });
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const result = await getMediaStatus(numericTmdbId, mediaType);
      setStatusData(result);
    } catch (err) {
      console.log('[useOverseerrStatus] Error fetching status:', err);
      setError('Failed to check request status');
      setStatusData({ status: 'unknown', canRequest: true });
    } finally {
      setIsLoading(false);
    }
  }, [numericTmdbId, mediaType]);

  const submitRequest = useCallback(
    async (is4k: boolean = false): Promise<OverseerrRequestResult> => {
      if (!numericTmdbId || !isOverseerrReady()) {
        return { success: false, error: 'Overseerr not configured' };
      }

      setIsRequesting(true);

      try {
        const result = await requestMedia(numericTmdbId, mediaType, is4k);

        if (result.success) {
          // Clear cache and refetch status
          clearOverseerrCacheItem(numericTmdbId, mediaType);
          await fetchStatus();
        }

        return result;
      } catch (err) {
        console.log('[useOverseerrStatus] Error submitting request:', err);
        return { success: false, error: 'Request failed' };
      } finally {
        setIsRequesting(false);
      }
    },
    [numericTmdbId, mediaType, fetchStatus]
  );

  useEffect(() => {
    fetchStatus();
  }, [fetchStatus]);

  return {
    status: statusData.status,
    canRequest: statusData.canRequest,
    isLoading,
    error,
    refetch: fetchStatus,
    submitRequest,
    isRequesting,
  };
}
