import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { loadSettings } from '@/state/settings';
import { plexSearch } from '@/services/plex';
import { apiClient } from '@/services/api';
import { plexBackendLibraries, plexBackendSearch } from '@/services/plex_backend';
import { tmdbSearchMulti, tmdbTrending, tmdbImage, tmdbPopular } from '@/services/tmdb';
import SearchInput from '@/components/SearchInput';
import SearchResults from '@/components/SearchResults';
import PopularSearches from '@/components/PopularSearches';
import TrendingSearches from '@/components/TrendingSearches';
import SearchCollections from '@/components/SearchCollections';

type SearchResult = {
  id: string;
  title: string;
  type: 'movie' | 'tv' | 'person' | 'collection';
  image?: string;
  year?: string;
  overview?: string;
  available?: boolean;
};

export default function Search() {
  const nav = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const [query, setQuery] = useState(searchParams.get('q') || '');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [popularItems, setPopularItems] = useState<SearchResult[]>([]);
  const [trendingItems, setTrendingItems] = useState<SearchResult[]>([]);
  const [collections, setCollections] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchMode, setSearchMode] = useState<'idle' | 'searching' | 'results'>('idle');
  const searchTimeoutRef = useRef<NodeJS.Timeout>();

  // Load initial content on mount
  useEffect(() => {
    loadInitialContent();
  }, []);

  // Handle query changes
  useEffect(() => {
    if (query) {
      setSearchParams({ q: query });
      setSearchMode('searching');
      performSearch(query);
    } else {
      setSearchParams({});
      setSearchMode('idle');
      setResults([]);
    }
  }, [query]);

  async function loadInitialContent() {
    const s = loadSettings();

    // Load popular items from TMDB
    if (s.tmdbBearer) {
      try {
        const [popularMovies, popularShows] = await Promise.all([
          tmdbPopular(s.tmdbBearer, 'movie'),
          tmdbPopular(s.tmdbBearer, 'tv')
        ]);

        const popular: SearchResult[] = [];

        // Add popular movies (prefer backdrops for landscape rails)
        (popularMovies as any).results?.slice(0, 6).forEach((item: any) => {
          popular.push({
            id: `tmdb:movie:${item.id}`,
            title: item.title,
            type: 'movie',
            image: tmdbImage(item.backdrop_path, 'w780') || tmdbImage(item.poster_path, 'w500'),
            year: item.release_date?.slice(0, 4)
          });
        });

        // Add popular TV shows
        (popularShows as any).results?.slice(0, 6).forEach((item: any) => {
          popular.push({
            id: `tmdb:tv:${item.id}`,
            title: item.name,
            type: 'tv',
            image: tmdbImage(item.backdrop_path, 'w780') || tmdbImage(item.poster_path, 'w500'),
            year: item.first_air_date?.slice(0, 4)
          });
        });

        setPopularItems(popular.slice(0, 10));

        // Load trending items
        const trending = await tmdbTrending(s.tmdbBearer, 'all', 'week');
        const trendingList: SearchResult[] = (trending as any).results?.slice(0, 12).map((item: any) => ({
          id: `tmdb:${item.media_type}:${item.id}`,
          title: item.title || item.name,
          type: item.media_type as 'movie' | 'tv',
          image: tmdbImage(item.backdrop_path, 'w780') || tmdbImage(item.poster_path, 'w500'),
          year: (item.release_date || item.first_air_date)?.slice(0, 4)
        })) || [];

        setTrendingItems(trendingList);
      } catch (err) {
        console.error('Failed to load popular/trending content:', err);
      }
    }

    // Load Plex collections
    if (s.plexBaseUrl && s.plexToken) {
      try {
        const libs: any = await plexBackendLibraries();
        const directories = libs?.MediaContainer?.Directory || [];
        const collectionsList: SearchResult[] = [];

        // Get collections from each library
        for (const lib of directories.slice(0, 2)) {
          try {
            const cols: any = await plexBackendCollections(lib.key);
            const items = cols?.MediaContainer?.Metadata || [];

            items.slice(0, 3).forEach((col: any) => {
              const p = col.thumb || col.art;
              collectionsList.push({
                id: `plex:collection:${col.ratingKey}`,
                title: col.title,
                type: 'collection',
                image: apiClient.getPlexImageNoToken(p || ''),
                overview: col.summary
              });
            });
          } catch {}
        }

        setCollections(collectionsList);
      } catch (err) {
        console.error('Failed to load Plex collections:', err);
      }
    }
  }

  const performSearch = useCallback(async (searchQuery: string) => {
    if (!searchQuery.trim()) {
      setResults([]);
      setSearchMode('idle');
      return;
    }

    setLoading(true);
    const s = loadSettings();
    const searchResults: SearchResult[] = [];

    try {
      // Search Plex first
      if (s.plexBaseUrl && s.plexToken) {
        try {
          // Search movies
          const plexMovies: any = await plexBackendSearch(searchQuery, 1);
          const movieResults = plexMovies?.MediaContainer?.Metadata || [];

          movieResults.slice(0, 10).forEach((item: any) => {
            searchResults.push({
              id: `plex:${item.ratingKey}`,
              title: item.title,
              type: 'movie',
              image: apiClient.getPlexImageNoToken((item.art || item.thumb || item.parentThumb || item.grandparentThumb) || ''),
              year: item.year ? String(item.year) : undefined,
              overview: item.summary,
              available: true
            });
          });

          // Search TV shows
          const plexShows: any = await plexBackendSearch(searchQuery, 2);
          const showResults = plexShows?.MediaContainer?.Metadata || [];

          showResults.slice(0, 10).forEach((item: any) => {
            searchResults.push({
              id: `plex:${item.ratingKey}`,
              title: item.title,
              type: 'tv',
              image: apiClient.getPlexImageNoToken((item.art || item.thumb || item.parentThumb || item.grandparentThumb) || ''),
              year: item.year ? String(item.year) : undefined,
              overview: item.summary,
              available: true
            });
          });
        } catch (err) {
          console.error('Plex search failed:', err);
        }
      }

      // Search TMDB as fallback
      if (s.tmdbBearer) {
        try {
          const tmdbResults: any = await tmdbSearchMulti(s.tmdbBearer, searchQuery);
          const tmdbItems = tmdbResults?.results || [];

          tmdbItems.slice(0, 20).forEach((item: any) => {
            // Skip if already in Plex results
            const plexMatch = searchResults.find(r =>
              r.title.toLowerCase() === (item.title || item.name || '').toLowerCase()
            );

            if (!plexMatch && item.media_type !== 'person') {
              searchResults.push({
                id: `tmdb:${item.media_type}:${item.id}`,
                title: item.title || item.name,
                type: item.media_type as 'movie' | 'tv',
                image: tmdbImage(item.backdrop_path, 'w780') || tmdbImage(item.poster_path, 'w500'),
                year: (item.release_date || item.first_air_date)?.slice(0, 4),
                overview: item.overview,
                available: false
              });
            }
          });
        } catch (err) {
          console.error('TMDB search failed:', err);
        }
      }

      setResults(searchResults);
      setSearchMode('results');
    } finally {
      setLoading(false);
    }
  }, []);

  const handleSearch = useCallback((value: string) => {
    // Clear existing timeout
    if (searchTimeoutRef.current) {
      clearTimeout(searchTimeoutRef.current);
    }

    setQuery(value);

    // Debounce search
    if (value) {
      searchTimeoutRef.current = setTimeout(() => {
        performSearch(value);
      }, 300);
    }
  }, [performSearch]);

  const handleItemClick = (item: SearchResult) => {
    if (item.type === 'collection') {
      // Handle collection click - maybe show collection contents
      nav(`/library?collection=${encodeURIComponent(item.id)}`);
    } else {
      nav(`/details/${encodeURIComponent(item.id)}`);
    }
  };

  return (
    <div className="min-h-screen pt-20 pb-10">
      <div className="page-gutter-left">
        {/* Search Input */}
        <div className="mb-8">
          <SearchInput
            value={query}
            onChange={handleSearch}
            autoFocus
          />
        </div>

        {/* Search Results */}
        {searchMode === 'results' && (
          <div className="mb-12">
            {loading ? (
              <div className="text-center py-20">
                <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-white"></div>
                <p className="mt-4 text-gray-400">Searching...</p>
              </div>
            ) : results.length > 0 ? (
              <SearchResults
                results={results}
                onItemClick={handleItemClick}
              />
            ) : (
              <div className="text-center py-20">
                <p className="text-xl text-gray-400">No results found for "{query}"</p>
                <p className="mt-2 text-sm text-gray-500">Try searching with different keywords</p>
              </div>
            )}
          </div>
        )}

        {/* Idle State - Show Popular, Trending, Collections */}
        {searchMode === 'idle' && (
          <>
            {/* Popular Searches rail */}
            {popularItems.length > 0 && (
              <div className="mb-4">
                <PopularSearches
                  items={popularItems}
                  onItemClick={handleItemClick}
                />
              </div>
            )}

            {/* Trending Searches rail */}
            {trendingItems.length > 0 && (
              <div className="mb-4">
                <TrendingSearches
                  items={trendingItems}
                  onItemClick={handleItemClick}
                />
              </div>
            )}

            {/* Collections */}
            {collections.length > 0 && (
              <div className="mt-6 mb-12">
                <SearchCollections
                  collections={collections}
                  onItemClick={handleItemClick}
                />
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
