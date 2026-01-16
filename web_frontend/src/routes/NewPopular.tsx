import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { tmdbTrending, tmdbImage, tmdbUpcoming, tmdbDetails, tmdbVideos, tmdbImages } from '@/services/tmdb';
import { traktAnticipated, traktMostWatched } from '@/services/trakt';
import { plexRecentlyAdded, plexImage, plexFindByGuid, plexPopular } from '@/services/plex';
import { apiClient } from '@/services/api';
import { loadSettings } from '@/state/settings';
import { cached } from '@/services/cache';
import HomeHero from '@/components/HomeHero';
import WatchlistButton from '@/components/WatchlistButton';
import Row from '@/components/Row';
import UltraBlurBackground from '@/components/UltraBlurBackground';

type TabType = 'trending' | 'top10' | 'coming-soon' | 'worth-wait';

type MediaItem = {
  id: string;
  title: string;
  image?: string;
  subtitle?: string;
  badge?: string;
  rank?: number;
  mediaType?: 'movie' | 'show';
};

export default function NewPopular() {
  const navigate = useNavigate();
  const settings = loadSettings();
  const tmdbKey = settings.tmdbBearer || '';
  const plexToken = settings.plexToken || '';
  const plexBaseUrl = settings.plexBaseUrl || '';

  const [activeTab, setActiveTab] = useState<TabType>('trending');
  const [contentType, setContentType] = useState<'all' | 'movies' | 'shows'>('all');
  const [period, setPeriod] = useState<'daily' | 'weekly' | 'monthly'>('weekly');
  const [loading, setLoading] = useState(true);

  const [hero, setHero] = useState<any>(null);
  const [trendingMovies, setTrendingMovies] = useState<MediaItem[]>([]);
  const [trendingShows, setTrendingShows] = useState<MediaItem[]>([]);
  const [top10, setTop10] = useState<MediaItem[]>([]);
  const [recentlyAdded, setRecentlyAdded] = useState<MediaItem[]>([]);
  const [popularPlex, setPopularPlex] = useState<MediaItem[]>([]);
  const [anticipated, setAnticipated] = useState<MediaItem[]>([]);
  const [popular, setPopular] = useState<MediaItem[]>([]);
  const [upcoming, setUpcoming] = useState<MediaItem[]>([]);

  useEffect(() => {
    loadContent();
  }, [activeTab, contentType, period]);

  async function loadContent() {
    setLoading(true);

    try {
      // Load different content based on active tab
      if (activeTab === 'trending') {
        await loadTrendingContent();
      } else if (activeTab === 'top10') {
        await loadTop10Content();
      } else if (activeTab === 'coming-soon') {
        await loadComingSoonContent();
      } else if (activeTab === 'worth-wait') {
        await loadWorthWaitContent();
      }
    } catch (err) {
      console.error('Error loading content:', err);
    } finally {
      setLoading(false);
    }
  }

  async function loadTrendingContent() {
    const mappedPeriod = period === 'daily' ? 'day' : 'week';
    const [moviesRes, showsRes, plexRecent, plexPop] = await Promise.all([
      tmdbKey ? tmdbTrending(tmdbKey, 'movie', mappedPeriod as any).catch(() => ({ results: [] })) : Promise.resolve({ results: [] }),
      tmdbKey ? tmdbTrending(tmdbKey, 'tv', mappedPeriod as any).catch(() => ({ results: [] })) : Promise.resolve({ results: [] }),
      plexRecentlyAdded(7).catch(() => []),
      plexPopular().catch(() => [])
    ]);

    // Set trending movies
    const movies = moviesRes.results?.slice(0, 20).map((m: any) => ({
      id: `tmdb:movie:${m.id}`,
      title: m.title,
      image: m.poster_path ? tmdbImage(m.poster_path, 'w342') : undefined,
      subtitle: m.release_date?.split('-')[0],
      badge: m.vote_average ? `⭐ ${m.vote_average.toFixed(1)}` : undefined,
      mediaType: 'movie' as const
    })) || [];
    setTrendingMovies(movies);

    // Set trending shows
    const shows = showsRes.results?.slice(0, 20).map((s: any) => ({
      id: `tmdb:tv:${s.id}`,
      title: s.name,
      image: s.poster_path ? tmdbImage(s.poster_path, 'w342') : undefined,
      subtitle: s.first_air_date?.split('-')[0],
      badge: s.vote_average ? `⭐ ${s.vote_average.toFixed(1)}` : undefined,
      mediaType: 'show' as const
    })) || [];
    setTrendingShows(shows);

    // Set recently added from Plex
    const recent = plexRecent.slice(0, 20).map((item: any) => ({
      id: `plex:${item.ratingKey}`,
      title: item.title,
      image: item.thumb ? apiClient.getPlexImageNoToken(item.thumb) : undefined,
      subtitle: item.year?.toString(),
      badge: 'New',
      mediaType: item.type === 'movie' ? 'movie' : 'show' as const
    }));
    setRecentlyAdded(recent);

    // Popular on Plex
    const pop = (plexPop || []).slice(0, 20).map((item: any) => ({
      id: `plex:${item.ratingKey}`,
      title: item.title || item.grandparentTitle,
      image: item.thumb ? apiClient.getPlexImageNoToken((item.thumb || item.parentThumb || item.grandparentThumb) || '') : undefined,
      subtitle: item.year?.toString(),
      badge: 'Popular',
      mediaType: item.type === 'movie' ? 'movie' : 'show' as const
    }));
    setPopularPlex(pop);

    // Set hero from top trending
    if (moviesRes.results?.[0] && tmdbKey) {
      const topItem = moviesRes.results[0];
      const [details, videos, images] = await Promise.all([
        tmdbDetails(tmdbKey, 'movie', topItem.id).catch(() => null),
        tmdbVideos(tmdbKey, 'movie', topItem.id).catch(() => ({ results: [] })),
        tmdbImages(tmdbKey, 'movie', topItem.id).catch(() => ({ logos: [] }))
      ]);

      const trailer = videos.results?.find((v: any) => v.type === 'Trailer' && v.site === 'YouTube');
      const logo = images.logos?.find((l: any) => l.iso_639_1 === 'en' || !l.iso_639_1);

      // Try to map to Plex to decide Play availability
      let heroId = `tmdb:movie:${topItem.id}`;
      if (plexBaseUrl && plexToken) {
        try {
          const byGuid: any = await plexFindByGuid({ baseUrl: plexBaseUrl, token: plexToken }, `tmdb://${topItem.id}`, 1);
          const hit = byGuid?.MediaContainer?.Metadata?.[0];
          if (hit?.ratingKey) heroId = `plex:${hit.ratingKey}`;
          if (!hit) {
            const byGuid2: any = await plexFindByGuid({ baseUrl: plexBaseUrl, token: plexToken }, `themoviedb://${topItem.id}`, 1);
            const hit2 = byGuid2?.MediaContainer?.Metadata?.[0];
            if (hit2?.ratingKey) heroId = `plex:${hit2.ratingKey}`;
          }
        } catch {}
      }

      setHero({
        id: heroId,
        title: topItem.title,
        overview: topItem.overview,
        backdrop: topItem.backdrop_path ? tmdbImage(topItem.backdrop_path, 'original') : undefined,
        poster: topItem.poster_path ? tmdbImage(topItem.poster_path, 'w500') : undefined,
        rating: topItem.vote_average ? `⭐ ${topItem.vote_average.toFixed(1)}` : undefined,
        year: topItem.release_date?.split('-')[0],
        runtime: details?.runtime,
        genres: details?.genres?.map((g: any) => g.name),
        ytKey: trailer?.key,
        logoUrl: logo ? tmdbImage(logo.file_path, 'w500') : undefined
      });
    }
  }

  async function loadTop10Content() {
    try {
      // Try Trakt first for more accurate charts
      const [traktMovies, traktShows] = await Promise.all([
        traktMostWatched('movies', period as any).catch(() => []),
        traktMostWatched('shows', period as any).catch(() => [])
      ]);

      // Fetch images from TMDB for Trakt items
      const moviesWithImages = await Promise.all(
        traktMovies.slice(0, 10).map(async (m: any, i: number) => {
          let image: string | undefined;
          if (tmdbKey && m.movie.ids?.tmdb) {
            try {
              const details = await tmdbDetails(tmdbKey, 'movie', m.movie.ids.tmdb);
              image = details.poster_path ? tmdbImage(details.poster_path, 'w342') : undefined;
            } catch {}
          }
          return {
            id: m.movie.ids?.tmdb ? `tmdb:movie:${m.movie.ids.tmdb}` : (m.movie.ids?.imdb ? `tmdb:movie:${m.movie.ids.imdb}` : `trakt:movie:${m.movie.ids?.trakt ?? i}`),
            title: m.movie.title,
            image,
            subtitle: m.movie.year?.toString(),
            badge: `#${i + 1}`,
            rank: i + 1,
            mediaType: 'movie' as const
          };
        })
      );

      const showsWithImages = await Promise.all(
        traktShows.slice(0, 10).map(async (s: any, i: number) => {
          let image: string | undefined;
          if (tmdbKey && s.show.ids?.tmdb) {
            try {
              const details = await tmdbDetails(tmdbKey, 'tv', s.show.ids.tmdb);
              image = details.poster_path ? tmdbImage(details.poster_path, 'w342') : undefined;
            } catch {}
          }
          return {
            id: s.show.ids?.tmdb ? `tmdb:tv:${s.show.ids.tmdb}` : (s.show.ids?.imdb ? `tmdb:tv:${s.show.ids.imdb}` : `trakt:show:${s.show.ids?.trakt ?? i}`),
            title: s.show.title,
            image,
            subtitle: s.show.year?.toString(),
            badge: `#${i + 1}`,
            rank: i + 1,
            mediaType: 'show' as const
          };
        })
      );

      // Combine and rank
      const combined = [...moviesWithImages, ...showsWithImages].slice(0, 10);
      setTop10(combined);
    } catch {
      // Fallback to TMDB if we have a key
      if (tmdbKey) {
        const trending = await tmdbTrending(tmdbKey, 'movie', 'day');
        const items = trending.results?.slice(0, 10).map((item: any, i: number) => ({
        id: item.media_type === 'movie' ? `tmdb:movie:${item.id}` : `tmdb:tv:${item.id}`,
        title: item.title || item.name,
        image: item.poster_path ? tmdbImage(item.poster_path, 'w342') : undefined,
        subtitle: (item.release_date || item.first_air_date)?.split('-')[0],
        badge: `#${i + 1}`,
        rank: i + 1,
        mediaType: item.media_type as 'movie' | 'show'
        })) || [];
        setTop10(items);
      } else {
        setTop10([]);
      }
    }
  }

  async function loadComingSoonContent() {
    if (!tmdbKey) {
      setUpcoming([]);
      return;
    }
    // Region inference (best-effort), cached 24h
    const region = await cached('geo:country', 24 * 60 * 60 * 1000, async () => {
      try {
        const res = await fetch('https://ipapi.co/country/');
        if (res.ok) return (await res.text()).trim();
      } catch {}
      return 'US';
    });
    const upcoming = await tmdbUpcoming(tmdbKey, region || 'US');
    const items = upcoming.results?.map((m: any) => ({
      id: `tmdb:movie:${m.id}`,
      title: m.title,
      image: m.poster_path ? tmdbImage(m.poster_path, 'w342') : undefined,
      subtitle: m.release_date ? new Date(m.release_date).toLocaleDateString() : undefined,
      badge: 'Coming Soon',
      mediaType: 'movie' as const
    })) || [];
    setUpcoming(items);
  }

  async function loadWorthWaitContent() {
    try {
      const anticipated = await traktAnticipated('movies');

      // Fetch images from TMDB
      const items = await Promise.all(
        anticipated.slice(0, 20).map(async (item: any) => {
          let image: string | undefined;
          if (tmdbKey && item.movie.ids?.tmdb) {
            try {
              const details = await tmdbDetails(tmdbKey, 'movie', item.movie.ids.tmdb);
              image = details.poster_path ? tmdbImage(details.poster_path, 'w342') : undefined;
            } catch {}
          }
          return {
            id: item.movie.ids?.tmdb ? `tmdb:movie:${item.movie.ids.tmdb}` : (item.movie.ids?.imdb ? `tmdb:movie:${item.movie.ids.imdb}` : `trakt:movie:${item.movie.ids?.trakt ?? 0}`),
            title: item.movie.title,
            image,
            subtitle: item.movie.year?.toString(),
            badge: `${item.list_count} lists`,
            mediaType: 'movie' as const
          };
        })
      );

      setAnticipated(items);
    } catch {
      // Fallback to upcoming
      await loadComingSoonContent();
    }
  }

  const handleItemClick = (id: string) => {
    navigate(`/details/${encodeURIComponent(id)}`);
  };

  return (
    <UltraBlurBackground imageUrl={hero?.backdrop} className="min-h-screen pb-12">
      {/* Hero Section */}
      {hero && !loading && (
        <HomeHero
          title={hero.title}
          overview={hero.overview}
          backdropUrl={hero.backdrop}
          posterUrl={hero.poster}
          rating={hero.rating}
          year={hero.year}
          runtime={hero.runtime}
          genres={hero.genres}
          ytKey={hero.ytKey}
          logoUrl={hero.logoUrl}
          onPlay={hero.id.startsWith('plex:') ? (() => navigate(`/player/${encodeURIComponent(hero.id)}`)) : undefined}
          onMoreInfo={() => navigate(`/details/${encodeURIComponent(hero.id)}`)}
          extraActions={(
            <WatchlistButton
              itemId={hero.id}
              itemType={hero.id.includes(':tv:') ? 'show' : 'movie'}
              tmdbId={hero.id.startsWith('tmdb:') ? hero.id.split(':')[2] : undefined}
              variant="button"
              />
          )}
        />
      )}

      <div className="page-gutter-left mt-8">
        {/* API Key Warning */}
        {!tmdbKey && (
          <div className="mb-6 p-4 bg-yellow-900/20 border border-yellow-600/30 rounded-lg">
            <div className="flex items-center gap-3">
              <svg className="w-5 h-5 text-yellow-500 flex-shrink-0" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z"/>
              </svg>
              <div className="text-sm text-yellow-200">
                TMDB API key not configured. Some content and images may not be available.
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
        {/* Tabs */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-6">
            {[
              { id: 'trending' as const, label: 'Trending Now' },
              { id: 'top10' as const, label: 'Top 10' },
              { id: 'coming-soon' as const, label: 'Coming Soon' },
              { id: 'worth-wait' as const, label: 'Worth the Wait' }
            ].map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`pb-2 text-sm font-medium transition-colors border-b-2 ${
                  activeTab === tab.id
                    ? 'text-white border-white'
                    : 'text-white/50 border-transparent hover:text-white/80'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {/* Filters */}
          <div className="flex items-center gap-4">
            {/* Content Type Filter */}
            <select
              value={contentType}
              onChange={(e) => setContentType(e.target.value as any)}
              className="bg-black/50 text-white px-3 py-1.5 rounded-md text-sm border border-white/20"
            >
              <option value="all">All</option>
              <option value="movies">Movies</option>
              <option value="shows">TV Shows</option>
            </select>

            {/* Period Filter */}
            {(activeTab === 'trending' || activeTab === 'top10') && (
              <select
                value={period}
                onChange={(e) => setPeriod(e.target.value as any)}
                className="bg-black/50 text-white px-3 py-1.5 rounded-md text-sm border border-white/20"
              >
                <option value="daily">Today</option>
                <option value="weekly">This Week</option>
                <option value="monthly">This Month</option>
              </select>
            )}
          </div>
        </div>

        {/* Content Rows */}
        {loading ? (
          <div className="space-y-8">
            {[1, 2, 3].map(i => (
              <div key={i}>
                <div className="h-6 w-32 bg-white/10 rounded mb-4 skeleton" />
                <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 xl:grid-cols-8 gap-4">
                  {[1, 2, 3, 4, 5, 6, 7, 8].map(j => (
                    <div key={j} className="aspect-[2/3] bg-white/10 rounded skeleton" />
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="space-y-8">
            {activeTab === 'trending' && (
              <>
                {recentlyAdded.length > 0 && (
                  <Row
                    title="New on Plex"
                    items={recentlyAdded}
                    gutter="edge"
                    onItemClick={handleItemClick}
                  />
                )}
                {popularPlex.length > 0 && (
                  <Row
                    title="Popular on Plex"
                    items={popularPlex}
                    gutter="edge"
                    onItemClick={handleItemClick}
                  />
                )}
                {(contentType === 'all' || contentType === 'movies') && trendingMovies.length > 0 && (
                  <Row
                    title="Trending Movies"
                    items={trendingMovies}
                    gutter="edge"
                    onItemClick={handleItemClick}
                  />
                )}
                {(contentType === 'all' || contentType === 'shows') && trendingShows.length > 0 && (
                  <Row
                    title="Trending TV Shows"
                    items={trendingShows}
                    gutter="edge"
                    onItemClick={handleItemClick}
                  />
                )}
              </>
            )}

            {activeTab === 'top10' && top10.length > 0 && (
              <div>
                <h2 className="text-xl font-semibold text-white mb-4">
                  Top 10 {period === 'daily' ? 'Today' : period === 'weekly' ? 'This Week' : 'This Month'}
                </h2>
                <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
                  {top10.map((item, index) => (
                    <div
                      key={item.id}
                      onClick={() => handleItemClick(item.id)}
                      className="relative cursor-pointer group"
                    >
                      <div className="relative aspect-[2/3] bg-neutral-800 rounded-lg overflow-hidden">
                        {item.image ? (
                          <img
                            src={item.image}
                            alt={item.title}
                            className="w-full h-full object-cover"
                          />
                        ) : (
                          <div className="w-full h-full flex items-center justify-center text-white/30">
                            No Image
                          </div>
                        )}
                        <div className="absolute top-0 left-0 text-6xl font-black text-white px-2 py-1
                                      drop-shadow-[2px_2px_4px_rgba(0,0,0,0.9)]"
                             style={{ WebkitTextStroke: '2px black' }}>
                          {index + 1}
                        </div>
                        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
                      </div>
                      <div className="mt-2">
                        <div className="text-sm font-medium text-white truncate">{item.title}</div>
                        <div className="text-xs text-white/60">{item.subtitle}</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {activeTab === 'coming-soon' && upcoming.length > 0 && (
              <Row
                title="Coming Soon"
                items={upcoming}
                gutter="edge"
                onItemClick={handleItemClick}
              />
            )}

            {activeTab === 'worth-wait' && anticipated.length > 0 && (
              <Row
                title="Most Anticipated"
                items={anticipated}
                gutter="edge"
                onItemClick={handleItemClick}
              />
            )}
          </div>
        )}
      </div>
    </UltraBlurBackground>
  );
}
