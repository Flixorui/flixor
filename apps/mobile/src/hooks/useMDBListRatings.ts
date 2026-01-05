import { useState, useEffect } from 'react';
import {
  isMDBListReady,
  fetchMDBListRatings,
  MDBListRatings,
} from '../core/MDBListService';
import { isMdblistEnabled } from '../core/SettingsData';

export interface MDBListRatingResult {
  ratings: MDBListRatings | null;
  loading: boolean;
  error: string | null;
}

/**
 * Hook to fetch MDBList ratings for a movie/show
 * Only fetches if MDBList is enabled and API key is configured
 */
export function useMDBListRatings(
  imdbId?: string,
  type?: 'movie' | 'show'
): MDBListRatingResult {
  const [result, setResult] = useState<MDBListRatingResult>({
    ratings: null,
    loading: false,
    error: null,
  });

  useEffect(() => {
    let cancelled = false;

    async function fetchRatings() {
      // Check if MDBList is enabled
      if (!isMdblistEnabled()) {
        setResult({
          ratings: null,
          loading: false,
          error: null,
        });
        return;
      }

      // Need IMDb ID and type
      if (!imdbId || !type) {
        return;
      }

      // Check if ready (enabled + API key)
      if (!isMDBListReady()) {
        console.log('[useMDBListRatings] MDBList not ready (no API key)');
        return;
      }

      setResult(prev => ({ ...prev, loading: true, error: null }));

      try {
        const ratings = await fetchMDBListRatings(imdbId, type);

        if (cancelled) return;

        setResult({
          ratings,
          loading: false,
          error: null,
        });
      } catch (error) {
        if (cancelled) return;
        console.log('[useMDBListRatings] Error:', error);
        setResult({
          ratings: null,
          loading: false,
          error: 'Failed to fetch MDBList ratings',
        });
      }
    }

    fetchRatings();

    return () => {
      cancelled = true;
    };
  }, [imdbId, type]);

  return result;
}
