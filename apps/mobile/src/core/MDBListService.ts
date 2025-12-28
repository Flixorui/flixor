/**
 * MDBList API Service for fetching ratings from multiple sources
 * Requires user to enable and provide API key in settings
 */

import { isMdblistEnabled, getMdblistApiKey } from './SettingsData';

const MDBLIST_BASE_URL = 'https://api.mdblist.com';
const CACHE_TTL = 24 * 60 * 60 * 1000; // 24 hours

export interface MDBListRatings {
  imdb?: number;
  tmdb?: number;
  trakt?: number;
  letterboxd?: number;
  tomatoes?: number; // Rotten Tomatoes critic score
  audience?: number; // Rotten Tomatoes audience score
  metacritic?: number;
}

// In-memory cache for ratings
const ratingsCache = new Map<string, { ratings: MDBListRatings | null; timestamp: number }>();

/**
 * Check if MDBList is enabled and has an API key
 */
export function isMDBListReady(): boolean {
  return isMdblistEnabled() && !!getMdblistApiKey();
}

/**
 * Fetch ratings from MDBList API
 */
export async function fetchMDBListRatings(
  imdbId: string,
  mediaType: 'movie' | 'show'
): Promise<MDBListRatings | null> {
  // Check if MDBList is enabled
  if (!isMdblistEnabled()) {
    console.log('[MDBListService] MDBList is disabled');
    return null;
  }

  const apiKey = getMdblistApiKey();
  if (!apiKey) {
    console.log('[MDBListService] No API key configured');
    return null;
  }

  // Normalize IMDb ID
  const formattedImdbId = imdbId.startsWith('tt') ? imdbId : `tt${imdbId}`;
  if (!/^tt\d+$/.test(formattedImdbId)) {
    console.log('[MDBListService] Invalid IMDb ID format:', formattedImdbId);
    return null;
  }

  // Check cache
  const cacheKey = `${mediaType}:${formattedImdbId}`;
  const cached = ratingsCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    console.log(`[MDBListService] Cache hit for ${cacheKey}:`, cached.ratings ? 'found' : 'null');
    return cached.ratings;
  }

  try {
    console.log(`[MDBListService] Fetching ratings for ${mediaType}: ${formattedImdbId}`);

    const ratings: MDBListRatings = {};
    const ratingTypes = ['imdb', 'tmdb', 'trakt', 'letterboxd', 'tomatoes', 'audience', 'metacritic'];

    // Fetch all rating types in parallel
    const fetchPromises = ratingTypes.map(async (ratingType) => {
      try {
        const url = `${MDBLIST_BASE_URL}/rating/${mediaType}/${ratingType}?apikey=${apiKey}`;

        const response = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            ids: [formattedImdbId],
            provider: 'imdb'
          })
        });

        if (response.ok) {
          const data = await response.json();
          if (data.ratings?.[0]?.rating) {
            return { type: ratingType, rating: data.ratings[0].rating };
          }
        } else if (response.status === 403) {
          console.log('[MDBListService] Invalid API key');
        }
        return null;
      } catch (error) {
        console.log(`[MDBListService] Error fetching ${ratingType}:`, error);
        return null;
      }
    });

    const results = await Promise.all(fetchPromises);

    results.forEach(result => {
      if (result) {
        ratings[result.type as keyof MDBListRatings] = result.rating;
      }
    });

    const ratingCount = Object.keys(ratings).length;
    console.log(`[MDBListService] Fetched ${ratingCount} ratings:`, ratings);

    // Cache the result (even if empty to avoid repeated failed requests)
    const finalResult = ratingCount > 0 ? ratings : null;
    ratingsCache.set(cacheKey, { ratings: finalResult, timestamp: Date.now() });

    return finalResult;
  } catch (error) {
    console.log('[MDBListService] Error fetching ratings:', error);
    return null;
  }
}

/**
 * Clear the ratings cache
 */
export function clearMDBListCache(): void {
  ratingsCache.clear();
  console.log('[MDBListService] Cache cleared');
}

/**
 * Rating provider configuration for UI display
 */
export const RATING_PROVIDERS = {
  imdb: {
    name: 'IMDb',
    color: '#F5C518',
  },
  tmdb: {
    name: 'TMDB',
    color: '#01B4E4',
  },
  trakt: {
    name: 'Trakt',
    color: '#ED1C24',
  },
  letterboxd: {
    name: 'Letterboxd',
    color: '#00E054',
  },
  tomatoes: {
    name: 'Rotten Tomatoes',
    color: '#FA320A',
  },
  audience: {
    name: 'Audience Score',
    color: '#FA320A',
  },
  metacritic: {
    name: 'Metacritic',
    color: '#FFCC33',
  }
} as const;
