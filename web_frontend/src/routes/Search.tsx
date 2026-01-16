import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { loadSettings } from '@/state/settings';
import { apiClient } from '@/services/api';
import { plexBackendSearch } from '@/services/plex_backend';
import { tmdbSearchMulti, tmdbTrending, tmdbImage } from '@/services/tmdb';
import SearchInput from '@/components/SearchInput';
import SearchResults from '@/components/SearchResults';
import SmartImage from '@/components/SmartImage';

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
  const [trendingItems, setTrendingItems] = useState<SearchResult[]>([]);
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

    // Load trending items from TMDB
    if (s.tmdbBearer) {
      try {
        const [trendingMovies, trendingShows] = await Promise.all([
          tmdbTrending(s.tmdbBearer, 'movie', 'week'),
          tmdbTrending(s.tmdbBearer, 'tv', 'week')
        ]);

        const trending: SearchResult[] = [];

        // Interleave movies and shows for variety
        const movies = (trendingMovies as any).results?.slice(0, 6) || [];
        const shows = (trendingShows as any).results?.slice(0, 6) || [];

        for (let i = 0; i < Math.max(movies.length, shows.length); i++) {
          if (movies[i]) {
            trending.push({
              id: `tmdb:movie:${movies[i].id}`,
              title: movies[i].title,
              type: 'movie',
              image: tmdbImage(movies[i].backdrop_path, 'w780') || tmdbImage(movies[i].poster_path, 'w500'),
              year: movies[i].release_date?.slice(0, 4)
            });
          }
          if (shows[i]) {
            trending.push({
              id: `tmdb:tv:${shows[i].id}`,
              title: shows[i].name,
              type: 'tv',
              image: tmdbImage(shows[i].backdrop_path, 'w780') || tmdbImage(shows[i].poster_path, 'w500'),
              year: shows[i].first_air_date?.slice(0, 4)
            });
          }
        }

        setTrendingItems(trending.slice(0, 12));
      } catch (err) {
        console.error('Failed to load trending content:', err);
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
          // Search movies and TV shows in parallel
          const [plexMovies, plexShows] = await Promise.all([
            plexBackendSearch(searchQuery, 1),
            plexBackendSearch(searchQuery, 2)
          ]);

          const movieResults = (plexMovies as any)?.MediaContainer?.Metadata || [];
          const showResults = (plexShows as any)?.MediaContainer?.Metadata || [];

          movieResults.slice(0, 10).forEach((item: any) => {
            searchResults.push({
              id: `plex:${item.ratingKey}`,
              title: item.title,
              type: 'movie',
              image: apiClient.getPlexImageNoToken((item.thumb || item.art) || ''),
              year: item.year ? String(item.year) : undefined,
              overview: item.summary,
              available: true
            });
          });

          showResults.slice(0, 10).forEach((item: any) => {
            searchResults.push({
              id: `plex:${item.ratingKey}`,
              title: item.title,
              type: 'tv',
              image: apiClient.getPlexImageNoToken((item.thumb || item.art) || ''),
              year: item.year ? String(item.year) : undefined,
              overview: item.summary,
              available: true
            });
          });
        } catch (err) {
          console.error('Plex search failed:', err);
        }
      }

      // Search TMDB
      if (s.tmdbBearer) {
        try {
          const tmdbResults: any = await tmdbSearchMulti(s.tmdbBearer, searchQuery);
          const tmdbItems = tmdbResults?.results || [];

          tmdbItems.slice(0, 20).forEach((item: any) => {
            // Skip if already in Plex results or if it's a person
            if (item.media_type === 'person') return;

            const plexMatch = searchResults.find(r =>
              r.title.toLowerCase() === (item.title || item.name || '').toLowerCase()
            );

            if (!plexMatch) {
              searchResults.push({
                id: `tmdb:${item.media_type}:${item.id}`,
                title: item.title || item.name,
                type: item.media_type as 'movie' | 'tv',
                image: tmdbImage(item.poster_path, 'w500') || tmdbImage(item.backdrop_path, 'w780'),
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
    if (searchTimeoutRef.current) {
      clearTimeout(searchTimeoutRef.current);
    }

    setQuery(value);

    if (value) {
      searchTimeoutRef.current = setTimeout(() => {
        performSearch(value);
      }, 300);
    }
  }, [performSearch]);

  const handleItemClick = (item: SearchResult) => {
    if (item.type === 'collection') {
      nav(`/library?collection=${encodeURIComponent(item.id)}`);
    } else {
      nav(`/details/${encodeURIComponent(item.id)}`);
    }
  };

  return (
    <div className="min-h-screen relative">
      {/* Background with accent gradients - matching MacOS */}
      <div className="fixed inset-0 pointer-events-none">
        {/* Base dark gradient */}
        <div
          className="absolute inset-0"
          style={{
            background: 'linear-gradient(to bottom, #0a0a0a 0%, #0f0f10 50%, #0b0c0d 100%)'
          }}
        />
        {/* Teal accent (top-right) */}
        <div
          className="absolute inset-0"
          style={{
            background: 'radial-gradient(circle at 88% 10%, rgba(20, 76, 84, 0.28) 0%, transparent 50%)'
          }}
        />
        {/* Red accent (bottom-left) */}
        <div
          className="absolute inset-0"
          style={{
            background: 'radial-gradient(circle at 12% 88%, rgba(122, 22, 18, 0.30) 0%, transparent 50%)'
          }}
        />
      </div>

      {/* Content */}
      <div className="relative z-10 pt-20 pb-10">
        <div className="page-gutter">
          {/* Search Input */}
          <div className="max-w-2xl mb-10">
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
                  <p className="mt-4 text-neutral-400">Searching...</p>
                </div>
              ) : results.length > 0 ? (
                <SearchResults
                  results={results}
                  onItemClick={handleItemClick}
                />
              ) : (
                <div className="text-center py-20">
                  <p className="text-xl text-neutral-400">No results found for "{query}"</p>
                  <p className="mt-2 text-sm text-neutral-500">Try searching with different keywords</p>
                </div>
              )}
            </div>
          )}

          {/* Idle State - Show Trending */}
          {searchMode === 'idle' && trendingItems.length > 0 && (
            <div>
              <h2 className="text-lg font-semibold mb-4 text-white">Recommended TV Shows & Movies</h2>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                {trendingItems.map(item => (
                  <TrendingCard key={item.id} item={item} onClick={() => handleItemClick(item)} />
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function TrendingCard({ item, onClick }: { item: SearchResult; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="group text-left focus:outline-none"
    >
      <div className="relative aspect-video rounded-lg overflow-hidden bg-neutral-800 ring-1 ring-white/10 group-hover:ring-white/30 transition-all">
        {item.image ? (
          <SmartImage
            url={item.image}
            alt={item.title}
            width={320}
            className="w-full h-full"
            imgClassName="object-cover"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-neutral-600">
            <svg className="w-10 h-10" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15.75 10.5l4.72-4.72a.75.75 0 011.28.53v11.38a.75.75 0 01-1.28.53l-4.72-4.72M4.5 18.75h9a2.25 2.25 0 002.25-2.25v-9a2.25 2.25 0 00-2.25-2.25h-9A2.25 2.25 0 002.25 7.5v9a2.25 2.25 0 002.25 2.25z" />
            </svg>
          </div>
        )}

        {/* Gradient overlay */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />

        {/* Title on hover */}
        <div className="absolute bottom-0 left-0 right-0 p-3 translate-y-full group-hover:translate-y-0 transition-transform">
          <p className="text-sm font-medium text-white truncate">{item.title}</p>
          <p className="text-xs text-neutral-400">{item.year} • {item.type === 'movie' ? 'Movie' : 'TV Show'}</p>
        </div>
      </div>
    </button>
  );
}
