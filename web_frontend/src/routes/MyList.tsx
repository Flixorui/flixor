import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { plexTvWatchlist, plexTvRemoveFromWatchlist } from '@/services/plextv';
import { traktGetWatchlist, traktAddToWatchlist, traktRemoveFromWatchlist, isTraktAuthenticated, getTraktTokens } from '@/services/trakt';
import { tmdbDetails, tmdbImage } from '@/services/tmdb';
import { apiClient } from '@/services/api';
import WatchlistButton from '@/components/WatchlistButton';
import { loadSettings } from '@/state/settings';

type WatchlistItem = {
  id: string;
  title: string;
  year?: string;
  image?: string;
  overview?: string;
  rating?: string;
  mediaType: 'movie' | 'show';
  source: 'plex' | 'trakt' | 'both';
  dateAdded?: Date;
  runtime?: number;
  genres?: string[];
  guid?: string;
  tmdbId?: string;
  tmdbGuid?: string;
};

type SortBy = 'dateAdded' | 'title' | 'year' | 'rating';
type FilterType = 'all' | 'movies' | 'shows';

export default function MyList() {
  const navigate = useNavigate();
  const settings = loadSettings();
  const tmdbKey = settings.tmdbBearer || '';

  const [loading, setLoading] = useState(true);
  const [items, setItems] = useState<WatchlistItem[]>([]);
  const [sortBy, setSortBy] = useState<SortBy>('dateAdded');
  const [filterType, setFilterType] = useState<FilterType>('all');
  const [selectedItems, setSelectedItems] = useState<Set<string>>(new Set());
  const [bulkMode, setBulkMode] = useState(false);

  useEffect(() => {
    loadWatchlist();
  }, []);

  async function loadWatchlist() {
    setLoading(true);

    try {
      // Load from both Plex and Trakt if available
      const [plexList, traktList] = await Promise.all([
        loadPlexWatchlist(),
        isTraktAuthenticated() ? loadTraktWatchlist() : Promise.resolve([])
      ]);

      // Merge and deduplicate
      const mergedMap = new Map<string, WatchlistItem>();

      for (const item of plexList) {
        mergedMap.set(item.id, item);
      }

      for (const item of traktList) {
        const existing = mergedMap.get(item.id);
        if (existing) {
          existing.source = 'both';
        } else {
          mergedMap.set(item.id, item);
        }
      }

      setItems(Array.from(mergedMap.values()));
    } catch (err) {
      console.error('Failed to load watchlist:', err);
    } finally {
      setLoading(false);
    }
  }

  async function loadPlexWatchlist(): Promise<WatchlistItem[]> {
    try {
      const data = await plexTvWatchlist();
      const items = data.MediaContainer?.Metadata || [];

      return items.map((item: any) => {
        let tmdbId: string | undefined;
        try {
          const g = String(item.guid || '');
          const m = g.match(/(?:tmdb|themoviedb):\/\/(\d+)/i);
          if (m) tmdbId = m[1];
        } catch {}
        return ({
          id: item.ratingKey ? `plex:${item.ratingKey}` : (tmdbId ? `tmdb:${item.type==='movie'?'movie':'tv'}:${tmdbId}` : `plex-${item.guid}`),
          title: item.title,
          year: item.year?.toString(),
          image: item.thumb ? apiClient.getPlexImageNoToken(item.thumb) : undefined,
          overview: item.summary,
          rating: item.contentRating || (item.rating ? `⭐ ${item.rating}` : undefined),
          mediaType: item.type === 'movie' ? 'movie' : 'show',
          source: 'plex' as const,
          dateAdded: item.addedAt ? new Date(item.addedAt * 1000) : undefined,
          runtime: item.duration ? Math.round(item.duration / 60000) : undefined,
          genres: item.Genre?.map((g: any) => g.tag),
          guid: item.guid,
          tmdbId,
          tmdbGuid: item.tmdbGuid,
        });
      });
    } catch (err) {
      console.error('Failed to load Plex watchlist:', err);
      return [];
    }
  }

  async function loadTraktWatchlist(): Promise<WatchlistItem[]> {
    try {
      const tokens = getTraktTokens();
      if (!tokens) return [];

      const [movies, shows] = await Promise.all([
        traktGetWatchlist(tokens.access_token, 'movies'),
        traktGetWatchlist(tokens.access_token, 'shows')
      ]);

      const items: WatchlistItem[] = [];

      // Process movies
      for (const entry of movies) {
        const movie = entry.movie;
        let image: string | undefined;

        // Try to get poster from TMDB if we have the ID
        if (movie.ids?.tmdb && tmdbKey) {
          try {
            const details = await tmdbDetails(tmdbKey, 'movie', movie.ids.tmdb);
            image = details.poster_path ? tmdbImage(details.poster_path, 'w342') : undefined;
          } catch {}
        }

        const tmdbId = movie.ids?.tmdb ? String(movie.ids.tmdb) : undefined;
        items.push({
          id: tmdbId ? `tmdb:movie:${tmdbId}` : (movie.ids?.imdb ? `tmdb:movie:${movie.ids.imdb}` : `trakt:movie:${movie.ids?.trakt}`),
          title: movie.title,
          year: movie.year?.toString(),
          image,
          overview: movie.overview,
          rating: movie.rating ? `⭐ ${movie.rating.toFixed(1)}` : undefined,
          mediaType: 'movie',
          source: 'trakt' as const,
          dateAdded: entry.listed_at ? new Date(entry.listed_at) : undefined,
          runtime: movie.runtime,
          genres: movie.genres,
          tmdbId
        });
      }

      // Process shows
      for (const entry of shows) {
        const show = entry.show;
        let image: string | undefined;

        // Try to get poster from TMDB if we have the ID
        if (show.ids?.tmdb && tmdbKey) {
          try {
            const details = await tmdbDetails(tmdbKey, 'tv', show.ids.tmdb);
            image = details.poster_path ? tmdbImage(details.poster_path, 'w342') : undefined;
          } catch {}
        }

        const tmdbIdS = show.ids?.tmdb ? String(show.ids.tmdb) : undefined;
        items.push({
          id: tmdbIdS ? `tmdb:tv:${tmdbIdS}` : (show.ids?.imdb ? `tmdb:tv:${show.ids.imdb}` : `trakt:show:${show.ids?.trakt}`),
          title: show.title,
          year: show.year?.toString(),
          image,
          overview: show.overview,
          rating: show.rating ? `⭐ ${show.rating.toFixed(1)}` : undefined,
          mediaType: 'show',
          source: 'trakt' as const,
          dateAdded: entry.listed_at ? new Date(entry.listed_at) : undefined,
          runtime: show.runtime,
          genres: show.genres,
          tmdbId: tmdbIdS
        });
      }

      return items;
    } catch (err) {
      console.error('Failed to load Trakt watchlist:', err);
      return [];
    }
  }

  async function removeFromWatchlist(itemId: string) {
    const item = items.find(i => i.id === itemId);
    if (!item) return;

    try {
      // Remove from appropriate service(s)
      if (item.source === 'plex' || item.source === 'both') {
        try {
          const guidOrId = item.guid || itemId.replace(/^plex:/, '');
          await plexTvRemoveFromWatchlist(guidOrId);
        } catch (e) { console.error(e); }
      }

      if (item.source === 'trakt' || item.source === 'both') {
        const tokens = getTraktTokens();
        if (tokens) {
          const traktItem = {
            [item.mediaType === 'movie' ? 'movies' : 'shows']: [{
              ids: {
                tmdb: item.tmdbId ? parseInt(item.tmdbId) : undefined
              }
            }]
          };
          await traktRemoveFromWatchlist(tokens.access_token, traktItem);
        }
      }

      // Optimistically remove from UI
      setItems(prev => prev.filter(i => i.id !== itemId));
    } catch (err) {
      console.error('Failed to remove from watchlist:', err);
    }
  }

  async function removeBulkItems() {
    for (const itemId of selectedItems) {
      await removeFromWatchlist(itemId);
    }
    setSelectedItems(new Set());
    setBulkMode(false);
  }

  function toggleItemSelection(itemId: string) {
    setSelectedItems(prev => {
      const newSet = new Set(prev);
      if (newSet.has(itemId)) {
        newSet.delete(itemId);
      } else {
        newSet.add(itemId);
      }
      return newSet;
    });
  }

  // Sort and filter items
  const sortedAndFiltered = items
    .filter(item => {
      if (filterType === 'all') return true;
      if (filterType === 'movies') return item.mediaType === 'movie';
      if (filterType === 'shows') return item.mediaType === 'show';
      return true;
    })
    .sort((a, b) => {
      switch (sortBy) {
        case 'title':
          return a.title.localeCompare(b.title);
        case 'year':
          return (b.year || '0').localeCompare(a.year || '0');
        case 'rating':
          return (b.rating || '').localeCompare(a.rating || '');
        case 'dateAdded':
        default:
          return (b.dateAdded?.getTime() || 0) - (a.dateAdded?.getTime() || 0);
      }
    });

  const handleItemClick = (item: WatchlistItem) => {
    if (bulkMode) {
      toggleItemSelection(item.id);
    } else {
      if (item.id.startsWith('plex')) {
        navigate(`/details/${encodeURIComponent(item.tmdbGuid || item.id)}`);
      } else {
        navigate(`/details/${encodeURIComponent(item.id)}`);
      }
    }
  };

  return (
    <div className="min-h-screen pb-12">
      <div className="px-4 md:px-8 lg:px-12 xl:px-16 py-8">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-3xl md:text-4xl font-bold text-white mb-2">My List</h1>
          <p className="text-white/60">
            {items.length} {items.length === 1 ? 'title' : 'titles'}
            {isTraktAuthenticated() && ' • Synced with Trakt'}
          </p>
        </div>

        {/* API Key Warning */}
        {!tmdbKey && items.some(item => item.source === 'trakt' && !item.image) && (
          <div className="mb-6 p-4 bg-yellow-900/20 border border-yellow-600/30 rounded-lg">
            <div className="flex items-center gap-3">
              <svg className="w-5 h-5 text-yellow-500 flex-shrink-0" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/>
              </svg>
              <div className="text-sm text-yellow-200">
                Some Trakt items are missing images. Configure TMDB API key to load poster images.
                <button
                  onClick={() => navigate('/settings')}
                  className="ml-2 text-yellow-400 hover:text-yellow-300 underline"
                >
                  Configure in Settings
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Controls */}
        <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
          <div className="flex items-center gap-4">
            {/* Filter */}
            <select
              value={filterType}
              onChange={(e) => setFilterType(e.target.value as FilterType)}
              className="bg-black/50 text-white px-3 py-1.5 rounded-md text-sm border border-white/20"
            >
              <option value="all">All</option>
              <option value="movies">Movies</option>
              <option value="shows">TV Shows</option>
            </select>

            {/* Sort */}
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as SortBy)}
              className="bg-black/50 text-white px-3 py-1.5 rounded-md text-sm border border-white/20"
            >
              <option value="dateAdded">Date Added</option>
              <option value="title">Title</option>
              <option value="year">Year</option>
              <option value="rating">Rating</option>
            </select>
          </div>

          {/* Bulk Actions */}
          <div className="flex items-center gap-4">
            {bulkMode && selectedItems.size > 0 && (
              <button
                onClick={removeBulkItems}
                className="px-4 py-1.5 bg-red-600 hover:bg-red-700 text-white text-sm font-medium rounded-md transition-colors"
              >
                Remove {selectedItems.size} {selectedItems.size === 1 ? 'item' : 'items'}
              </button>
            )}
            <button
              onClick={() => {
                setBulkMode(!bulkMode);
                setSelectedItems(new Set());
              }}
              className="px-4 py-1.5 bg-white/10 hover:bg-white/20 text-white text-sm font-medium rounded-md transition-colors"
            >
              {bulkMode ? 'Cancel' : 'Select'}
            </button>
          </div>
        </div>

        {/* Content */}
        {loading ? (
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 gap-4">
            {[...Array(12)].map((_, i) => (
              <div key={i} className="aspect-[2/3] bg-white/10 rounded-lg skeleton" />
            ))}
          </div>
        ) : sortedAndFiltered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20">
            <div className="text-6xl mb-4">📺</div>
            <h2 className="text-xl font-semibold text-white mb-2">Your list is empty</h2>
            <p className="text-white/60 text-center max-w-md mb-6">
              Start building your watchlist by adding movies and TV shows you want to watch later.
            </p>
            <button
              onClick={() => navigate('/browse')}
              className="px-6 py-2.5 bg-white text-black font-semibold rounded-md hover:bg-white/90 transition-colors"
            >
              Browse Content
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6 gap-4">
            {sortedAndFiltered.map(item => (
              <div
                key={item.id}
                onClick={() => handleItemClick(item)}
                className={`relative group cursor-pointer transition-all ${
                  bulkMode && selectedItems.has(item.id) ? 'ring-2 ring-white scale-95' : ''
                }`}
              >
                <div className="relative aspect-[2/3] bg-neutral-800 rounded-lg overflow-hidden ring-1 ring-white/15 group-hover:ring-2 group-hover:ring-white/90 group-hover:ring-offset-2 group-hover:ring-offset-transparent transition-all">
                  {item.image ? (
                    <img
                      src={item.image}
                      alt={item.title}
                      className="w-full h-full object-cover"
                      loading="lazy"
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-white/30">
                      <svg className="w-12 h-12" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M18 3v2h-2V3H8v2H6V3H4v18h2v-2h2v2h8v-2h2v2h2V3h-2zM8 17H6v-2h2v2zm0-4H6v-2h2v2zm0-4H6V7h2v2zm10 8h-2v-2h2v2zm0-4h-2v-2h2v2zm0-4h-2V7h2v2z"/>
                      </svg>
                    </div>
                  )}

                  {/* Overlay */}
                  <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity">
                    <div className="absolute bottom-0 left-0 right-0 p-3 flex items-end justify-between">
                      <div>
                        <div className="text-xs text-white/60 mb-1">
                          {item.year} • {item.mediaType === 'movie' ? 'Movie' : 'TV Show'}
                        </div>
                        {item.rating && (
                          <div className="text-xs text-white/80">{item.rating}</div>
                        )}
                      </div>
                      {item.id.startsWith('plex:') && (
                        <button
                          onClick={(e) => { e.stopPropagation(); navigate(`/player/${encodeURIComponent(item.id)}`); }}
                          className="w-10 h-10 rounded-full bg-white text-black flex items-center justify-center hover:bg-neutral-200"
                          title="Play"
                        >
                          <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
                        </button>
                      )}
                    </div>
                  </div>

                  {/* Bulk selection checkbox */}
                  {bulkMode && (
                    <div className="absolute top-2 left-2 z-10">
                      <div className={`w-6 h-6 rounded border-2 ${
                        selectedItems.has(item.id)
                          ? 'bg-white border-white'
                          : 'bg-black/50 border-white/50'
                      } flex items-center justify-center`}>
                        {selectedItems.has(item.id) && (
                          <svg className="w-4 h-4 text-black" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
                          </svg>
                        )}
                      </div>
                    </div>
                  )}

                  {/* Watchlist toggle (when not in bulk mode) */}
                  {!bulkMode && (
                    <div className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 transition-opacity">
                      <WatchlistButton itemId={item.id} itemType={item.mediaType} tmdbId={item.tmdbId} variant="button" />
                    </div>
                  )}

                  {/* Source badge */}
                  <div className="absolute top-2 left-2">
                    {item.source === 'both' ? (
                      <div className="flex gap-1">
                        <div className="px-1.5 py-0.5 bg-[#E5A00D] text-black text-[10px] font-bold rounded">P</div>
                        <div className="px-1.5 py-0.5 bg-[#ed1c24] text-white text-[10px] font-bold rounded">T</div>
                      </div>
                    ) : item.source === 'plex' ? (
                      <div className="px-1.5 py-0.5 bg-[#E5A00D] text-black text-[10px] font-bold rounded">PLEX</div>
                    ) : (
                      <div className="px-1.5 py-0.5 bg-[#ed1c24] text-white text-[10px] font-bold rounded">TRAKT</div>
                    )}
                  </div>
                </div>

                {/* Title */}
                <div className="mt-2">
                  <div className="text-sm font-medium text-white truncate">{item.title}</div>
                  {item.dateAdded && (
                    <div className="text-xs text-white/50">
                      Added {item.dateAdded.toLocaleDateString()}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
