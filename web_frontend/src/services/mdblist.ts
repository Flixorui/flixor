import { loadSettings } from '@/state/settings';

const BASE_URL = 'https://api.mdblist.com';
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

export interface MDBListRatings {
  trakt?: number;
  imdb?: number;
  tmdb?: number;
  letterboxd?: number;
  tomatoes?: number; // RT critic
  audience?: number; // RT audience
  metacritic?: number;
}

type RatingType = 'trakt' | 'imdb' | 'tmdb' | 'letterboxd' | 'tomatoes' | 'audience' | 'metacritic';

interface CacheEntry {
  ratings: MDBListRatings;
  timestamp: number;
}

// In-memory cache
const ratingsCache = new Map<string, CacheEntry>();

function getCacheKey(imdbId: string, mediaType: 'movie' | 'show'): string {
  return `${mediaType}:${imdbId}`;
}

function isValidCache(entry: CacheEntry): boolean {
  return Date.now() - entry.timestamp < CACHE_TTL;
}

async function fetchRating(
  apiKey: string,
  imdbId: string,
  mediaType: 'movie' | 'show',
  ratingType: RatingType
): Promise<number | undefined> {
  try {
    // Ensure IMDb ID is properly formatted
    const formattedId = imdbId.startsWith('tt') ? imdbId : `tt${imdbId}`;

    const response = await fetch(
      `${BASE_URL}/rating/${mediaType}/${ratingType}?apikey=${encodeURIComponent(apiKey)}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          ids: [formattedId],
          provider: 'imdb',
        }),
      }
    );

    if (!response.ok) {
      if (response.status === 403) {
        console.warn('[MDBList] Invalid API key');
      }
      return undefined;
    }

    const data = await response.json();
    const rating = data?.ratings?.[0]?.rating;

    return typeof rating === 'number' ? rating : undefined;
  } catch (error) {
    console.error(`[MDBList] Error fetching ${ratingType} rating:`, error);
    return undefined;
  }
}

export async function getMDBListRatings(
  imdbId: string,
  mediaType: 'movie' | 'show'
): Promise<MDBListRatings | null> {
  const settings = loadSettings();

  if (!settings.mdblistEnabled || !settings.mdblistApiKey) {
    return null;
  }

  // Check cache first
  const cacheKey = getCacheKey(imdbId, mediaType);
  const cached = ratingsCache.get(cacheKey);
  if (cached && isValidCache(cached)) {
    return cached.ratings;
  }

  const apiKey = settings.mdblistApiKey;
  const ratingTypes: RatingType[] = ['trakt', 'imdb', 'tmdb', 'letterboxd', 'tomatoes', 'audience', 'metacritic'];

  // Fetch all ratings in parallel
  const results = await Promise.all(
    ratingTypes.map(async (type) => {
      const rating = await fetchRating(apiKey, imdbId, mediaType, type);
      return { type, rating };
    })
  );

  // Build ratings object
  const ratings: MDBListRatings = {};
  for (const { type, rating } of results) {
    if (rating !== undefined) {
      ratings[type] = rating;
    }
  }

  // Cache the result
  ratingsCache.set(cacheKey, {
    ratings,
    timestamp: Date.now(),
  });

  return ratings;
}

export function clearMDBListCache(): void {
  ratingsCache.clear();
}

export function invalidateMDBListCache(imdbId: string, mediaType: 'movie' | 'show'): void {
  const cacheKey = getCacheKey(imdbId, mediaType);
  ratingsCache.delete(cacheKey);
}

export function isMDBListCached(imdbId: string, mediaType: 'movie' | 'show'): boolean {
  const cacheKey = getCacheKey(imdbId, mediaType);
  const cached = ratingsCache.get(cacheKey);
  return cached !== undefined && isValidCache(cached);
}

// Test connection to MDBList API
export async function testMDBListConnection(apiKey: string): Promise<boolean> {
  try {
    // Test with a known movie (The Shawshank Redemption)
    const response = await fetch(
      `${BASE_URL}/rating/movie/imdb?apikey=${encodeURIComponent(apiKey)}`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          ids: ['tt0111161'],
          provider: 'imdb',
        }),
      }
    );

    return response.ok;
  } catch {
    return false;
  }
}

// Format rating for display
export function formatMDBListRating(rating: number | undefined, source: RatingType): string | null {
  if (rating === undefined) return null;

  switch (source) {
    case 'imdb':
    case 'tmdb':
    case 'trakt':
      return rating.toFixed(1);
    case 'letterboxd':
      return rating.toFixed(1);
    case 'tomatoes':
    case 'audience':
    case 'metacritic':
      return `${Math.round(rating)}%`;
    default:
      return rating.toString();
  }
}

// Get display name for rating source
export function getMDBListSourceName(source: RatingType): string {
  const names: Record<RatingType, string> = {
    trakt: 'Trakt',
    imdb: 'IMDb',
    tmdb: 'TMDB',
    letterboxd: 'Letterboxd',
    tomatoes: 'RT Critics',
    audience: 'RT Audience',
    metacritic: 'Metacritic',
  };
  return names[source];
}
