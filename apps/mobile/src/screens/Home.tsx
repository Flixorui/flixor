import React, { useEffect, useState, useRef, useCallback } from 'react';
import { View, Text, ActivityIndicator, Animated } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { SafeAreaView } from 'react-native-safe-area-context';
import Row from '../components/Row';
import { useNavigation, useIsFocused } from '@react-navigation/native';
import { TopBarStore, useTopBarStore } from '../components/TopBarStore';
import HeroCard from '../components/HeroCard';
import BrowseModal from '../components/BrowseModal';
import { useFlixor } from '../core/FlixorContext';
import type { PlexMediaItem, BrowseContext, BrowseItem } from '@flixor/core';
import {
  fetchTmdbTrendingTVWeek,
  fetchTmdbTrendingMoviesWeek,
  fetchTmdbTrendingAllWeek,
  fetchContinueWatching,
  fetchRecentlyAdded,
  fetchPlexWatchlist,
  fetchPlexGenreRow,
  fetchTraktTrendingMovies,
  fetchTraktTrendingShows,
  fetchTraktPopularShows,
  fetchTraktWatchlist,
  fetchTraktHistory,
  fetchTraktRecommendations,
  getPlexImageUrl,
  getContinueWatchingImageUrl,
  getTmdbLogo,
  getTmdbTextlessPoster,
  getUltraBlurColors,
  getUsername,
  RowItem,
  GenreItem,
  PlexUltraBlurColors,
} from '../core/HomeData';
import {
  toggleWatchlist,
  checkWatchlistStatus,
  WatchlistIds,
} from '../core/DetailsData';

interface HomeProps {
  onLogout: () => Promise<void>;
}

type HeroPick = { title: string; image?: string; subtitle?: string; tmdbId?: number; mediaType?: 'movie' | 'tv' };

export default function Home({ onLogout }: HomeProps) {
  const { flixor, isLoading: flixorLoading, isConnected } = useFlixor();
  const nav: any = useNavigation();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  const [welcome, setWelcome] = useState<string>('');

  // Plex data
  const [continueItems, setContinueItems] = useState<PlexMediaItem[]>([]);
  const [recent, setRecent] = useState<PlexMediaItem[]>([]);

  // TMDB trending (split into multiple rows)
  const [popularOnPlexTmdb, setPopularOnPlexTmdb] = useState<RowItem[]>([]);
  const [trendingNow, setTrendingNow] = useState<RowItem[]>([]);
  const [trendingMovies, setTrendingMovies] = useState<RowItem[]>([]);
  const [trendingAll, setTrendingAll] = useState<RowItem[]>([]);

  // Plex watchlist and genres
  const [watchlist, setWatchlist] = useState<RowItem[]>([]);
  const [genres, setGenres] = useState<Record<string, RowItem[]>>({});

  // Trakt data
  const [traktTrendMovies, setTraktTrendMovies] = useState<RowItem[]>([]);
  const [traktTrendShows, setTraktTrendShows] = useState<RowItem[]>([]);
  const [traktPopularShows, setTraktPopularShows] = useState<RowItem[]>([]);
  const [traktMyWatchlist, setTraktMyWatchlist] = useState<RowItem[]>([]);
  const [traktHistory, setTraktHistory] = useState<RowItem[]>([]);
  const [traktRecommendations, setTraktRecommendations] = useState<RowItem[]>([]);

  // UI state
  const [tab, setTab] = useState<'all' | 'movies' | 'shows'>('all');
  const [heroLogo, setHeroLogo] = useState<string | undefined>(undefined);
  const [heroPick, setHeroPick] = useState<HeroPick | null>(null);
  const [heroInWatchlist, setHeroInWatchlist] = useState(false);
  const [heroWatchlistLoading, setHeroWatchlistLoading] = useState(false);
  const [heroColors, setHeroColors] = useState<PlexUltraBlurColors | null>(null);
  const [browseModalVisible, setBrowseModalVisible] = useState(false);

  const y = React.useRef(new Animated.Value(0)).current;
  const showPillsAnim = React.useRef(new Animated.Value(1)).current;
  const barHeight = useTopBarStore((s) => s.height || 90);
  const isFocused = useIsFocused();
  const lastScrollY = useRef(0);
  const scrollDirection = useRef<'up' | 'down'>('down');

  // Set scrollY and showPills immediately on mount and when regaining focus
  React.useLayoutEffect(() => {
    if (isFocused) {
      console.log('[Home] Setting scrollY and showPills for Home screen');
      TopBarStore.setScrollY(y);
      TopBarStore.setShowPills(showPillsAnim);
    }
  }, [isFocused, y]);

  // Reset tab to 'all' when returning to Home (on focus), but not on first mount
  const isFirstMount = useRef(true);
  useEffect(() => {
    if (isFocused) {
      if (isFirstMount.current) {
        isFirstMount.current = false;
      } else {
        console.log('[Home] Returning to Home, resetting tab to all');
        setTab('all');
      }
    }
  }, [isFocused]);

  // Push top bar updates via effects
  useEffect(() => {
    if (!isFocused) return;

    console.log('[Home] Updating TopBar handlers, tab:', tab);
    TopBarStore.setVisible(true);
    TopBarStore.setShowFilters(true);
    TopBarStore.setUsername(welcome.replace('Welcome, ', ''));
    TopBarStore.setSelected(tab);
    TopBarStore.setCompact(false);
    TopBarStore.setHandlers({
      onNavigateLibrary: (t) => {
        console.log('[Home] Navigating to Library with tab:', t);
        nav.navigate('Library', { tab: t === 'movies' ? 'movies' : 'tv' });
      },
      onClose: () => {
        console.log('[Home] Close button clicked, resetting to all');
        setTab('all');
      },
      onSearch: () => {
        console.log('[Home] Opening search');
        nav.navigate('Search');
      },
      onBrowse: () => {
        console.log('[Home] Opening browse modal');
        setBrowseModalVisible(true);
      },
    });
  }, [welcome, tab, nav, isFocused]);

  // Helper function to pick hero
  const pickHero = (items: RowItem[]): HeroPick => {
    if (items.length > 0) {
      const randomIndex = Math.floor(Math.random() * Math.min(items.length, 8));
      const pick = items[randomIndex];

      let tmdbId: number | undefined;
      let mediaType: 'movie' | 'tv' | undefined;
      if (pick.id && pick.id.startsWith('tmdb:')) {
        const parts = pick.id.split(':');
        mediaType = parts[1] as 'movie' | 'tv';
        tmdbId = parseInt(parts[2], 10);
      }

      return {
        title: pick.title,
        image: pick.image,
        subtitle: '',
        tmdbId,
        mediaType,
      };
    }

    return { title: 'Featured', image: undefined, subtitle: undefined };
  };

  // Navigate to Browse screen with context and initial items
  const openRowBrowse = useCallback((context: BrowseContext, title: string, items: RowItem[]) => {
    // Convert RowItem to BrowseItem format
    const browseItems: BrowseItem[] = items.map((item) => ({
      id: item.id,
      title: item.title,
      image: item.image,
    }));
    nav.navigate('Browse', { context, title, initialItems: browseItems });
  }, [nav]);

  // Main data loading effect
  useEffect(() => {
    if (flixorLoading || !isConnected) return;

    (async () => {
      try {
        setError(null);
        console.log('[Home] Loading data...');

        // Get user info
        const name = await getUsername();
        setWelcome(`Welcome, ${name}`);

        // Fetch primary rows in parallel
        const results = await Promise.allSettled([
          fetchContinueWatching(),
          fetchRecentlyAdded(),
          fetchTmdbTrendingTVWeek(),
          fetchPlexWatchlist(),
          fetchTmdbTrendingMoviesWeek(),
          fetchTmdbTrendingAllWeek(),
        ]);

        const val = <T,>(i: number, def: T): T =>
          results[i].status === 'fulfilled'
            ? (results[i] as PromiseFulfilledResult<T>).value
            : def;

        setContinueItems(val(0, []));
        setRecent(val(1, []));

        const tv = val<RowItem[]>(2, []);
        console.log('[Home] TMDB trending TV fetched:', tv.length, 'items');
        setPopularOnPlexTmdb(tv.slice(0, 8));
        setTrendingNow(tv.slice(8, 16));

        setWatchlist(val(3, []));
        setTrendingMovies(val<RowItem[]>(4, []).slice(0, 12));
        setTrendingAll(val<RowItem[]>(5, []).slice(0, 12));

        // Genre rows - best-effort per row
        const genreDefs: Array<{ key: string; type: 'movie' | 'show'; label: string }> = [
          { key: 'TV Shows - Children', type: 'show', label: 'Children' },
          { key: 'Movie - Music', type: 'movie', label: 'Music' },
          { key: 'Movies - Documentary', type: 'movie', label: 'Documentary' },
          { key: 'Movies - History', type: 'movie', label: 'History' },
          { key: 'TV Shows - Reality', type: 'show', label: 'Reality' },
          { key: 'Movies - Drama', type: 'movie', label: 'Drama' },
          { key: 'TV Shows - Suspense', type: 'show', label: 'Suspense' },
          { key: 'Movies - Animation', type: 'movie', label: 'Animation' },
        ];

        const gEntries: [string, RowItem[]][] = [];
        await Promise.allSettled(
          genreDefs.map(async (gd) => {
            try {
              gEntries.push([gd.key, await fetchPlexGenreRow(gd.type, gd.label)]);
            } catch {}
          })
        );
        setGenres(Object.fromEntries(gEntries));

        // Trakt rows in parallel
        const traktRes = await Promise.allSettled([
          fetchTraktTrendingMovies(),
          fetchTraktTrendingShows(),
          fetchTraktPopularShows(),
          fetchTraktWatchlist(),
          fetchTraktHistory(),
          fetchTraktRecommendations(),
        ]);

        const tval = <T,>(i: number): T =>
          traktRes[i].status === 'fulfilled'
            ? (traktRes[i] as PromiseFulfilledResult<T>).value
            : ([] as any);

        setTraktTrendMovies(tval(0));
        setTraktTrendShows(tval(1));
        setTraktPopularShows(tval(2));
        setTraktMyWatchlist(tval(3));
        setTraktHistory(tval(4));
        setTraktRecommendations(tval(5));
      } catch (err: any) {
        console.error('[Home] Fatal error loading data:', err);
        const errorMsg = err?.message || 'Failed to load';
        setError(errorMsg);

        const currentRetry = retryCount + 1;
        setRetryCount(currentRetry);

        if (currentRetry >= 3) {
          console.log('[Home] Max retries exceeded, logging out user');
          setTimeout(async () => {
            await onLogout();
          }, 2000);
        } else {
          console.log('[Home] Retry count:', currentRetry);
        }
      } finally {
        setLoading(false);
      }
    })();
  }, [flixorLoading, isConnected, retryCount]);

  // Fetch logo and textless backdrop for hero once popularOnPlexTmdb is loaded
  useEffect(() => {
    console.log('[Home] Hero effect triggered, popularOnPlexTmdb length:', popularOnPlexTmdb.length);
    if (popularOnPlexTmdb.length === 0) {
      console.log('[Home] No popularOnPlexTmdb items yet, skipping hero');
      return;
    }

    console.log('[Home] Starting hero selection async...');
    (async () => {
      try {
        const hero = pickHero(popularOnPlexTmdb);
        console.log('[Home] Picked hero:', hero.title, 'tmdbId:', hero.tmdbId, 'has image:', !!hero.image);

        if (hero.tmdbId && hero.mediaType) {
          // Fetch textless poster from TMDB
          console.log('[Home] Fetching textless poster for:', hero.mediaType, hero.tmdbId);
          const poster = await getTmdbTextlessPoster(hero.tmdbId, hero.mediaType);
          if (poster) {
            console.log('[Home] Setting hero poster from TMDB (textless)');
            hero.image = poster;

            // Fetch UltraBlur colors from the poster
            console.log('[Home] Fetching UltraBlur colors for hero poster');
            const colors = await getUltraBlurColors(poster);
            if (colors) {
              console.log('[Home] Setting hero colors:', colors);
              setHeroColors(colors);
            }
          }

          // Fetch logo
          console.log('[Home] Fetching logo for:', hero.mediaType, hero.tmdbId);
          const logo = await getTmdbLogo(hero.tmdbId, hero.mediaType);
          if (logo) {
            console.log('[Home] Setting hero logo:', logo);
            setHeroLogo(logo);
          } else {
            console.log('[Home] No logo found for hero');
          }

          // Check watchlist status for hero
          const heroIds: WatchlistIds = {
            tmdbId: hero.tmdbId,
            mediaType: hero.mediaType,
          };
          const inWatchlist = await checkWatchlistStatus(heroIds);
          setHeroInWatchlist(inWatchlist);
        } else {
          console.log('[Home] No TMDB ID for hero, logo unavailable');
        }

        setHeroPick(hero);
      } catch (e) {
        console.log('[Home] Error in hero selection:', e);
      }
    })();
  }, [popularOnPlexTmdb]);

  // Light refresh of Trakt-dependent rows on focus
  useEffect(() => {
    (async () => {
      if (!isFocused || loading) return;
      try {
        setTraktTrendMovies(await fetchTraktTrendingMovies());
        setTraktTrendShows(await fetchTraktTrendingShows());
        setTraktPopularShows(await fetchTraktPopularShows());
        setTraktMyWatchlist(await fetchTraktWatchlist());
        setTraktHistory(await fetchTraktHistory());
        setTraktRecommendations(await fetchTraktRecommendations());
      } catch {}
    })();
  }, [isFocused]);

  // Show loading while FlixorCore is initializing or not connected
  if (flixorLoading || !isConnected) {
    return (
      <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator color="#fff" />
        <Text style={{ color: '#999', marginTop: 12 }}>
          {flixorLoading ? 'Initializing...' : 'Connecting to server...'}
        </Text>
      </View>
    );
  }

  if (loading || error) {
    return (
      <View style={{ flex: 1, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
        {error ? (
          <>
            <Text style={{ color: '#fff', fontSize: 18, marginBottom: 10, textAlign: 'center' }}>
              Unable to load data
            </Text>
            <Text style={{ color: '#999', fontSize: 14, marginBottom: 20, textAlign: 'center' }}>{error}</Text>
            <Text style={{ color: '#999', fontSize: 14, marginBottom: 20, textAlign: 'center' }}>Retry {retryCount}/3</Text>
            {retryCount >= 3 ? (
              <Text style={{ color: '#e50914', fontSize: 14, textAlign: 'center' }}>
                Logging out... Please check your connection and try again.
              </Text>
            ) : (
              <ActivityIndicator color="#fff" />
            )}
          </>
        ) : (
          <ActivityIndicator color="#fff" />
        )}
      </View>
    );
  }

  const getRowUri = (it: RowItem) => it.image;
  const getRowTitle = (it: RowItem) => it.title;
  const onRowPress = (it: RowItem) => {
    if (!it?.id) return;
    if (it.id.startsWith('plex:')) {
      const rk = it.id.split(':')[1];
      return nav.navigate('Details', { type: 'plex', ratingKey: rk });
    }
    if (it.id.startsWith('tmdb:')) {
      const [, media, id] = it.id.split(':');
      return nav.navigate('Details', { type: 'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
    }
  };

  const plexImage = (item: PlexMediaItem) => getPlexImageUrl(item, 300);
  const plexContinueImage = (item: PlexMediaItem) => getContinueWatchingImageUrl(item, 300);

  // Convert hex color to rgba with opacity
  const hexToRgba = (hex: string, opacity: number) => {
    const r = parseInt(hex.slice(0, 2), 16);
    const g = parseInt(hex.slice(2, 4), 16);
    const b = parseInt(hex.slice(4, 6), 16);
    return `rgba(${r},${g},${b},${opacity})`;
  };

  // Get gradient colors from heroColors or use defaults
  const bottomLeftColor = heroColors?.bottomLeft || '7a1612';
  const topRightColor = heroColors?.topRight || '144c54';

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#1b0a10' }}>
      <LinearGradient
        colors={['#0a0a0a', '#0f0f10', '#0b0c0d']}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 1 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />
      <LinearGradient
        colors={[
          hexToRgba(bottomLeftColor, 0.28),
          hexToRgba(bottomLeftColor, 0.08),
          hexToRgba(bottomLeftColor, 0.0),
        ]}
        start={{ x: 0.0, y: 1.0 }}
        end={{ x: 0.45, y: 0.35 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />
      <LinearGradient
        colors={[
          hexToRgba(topRightColor, 0.26),
          hexToRgba(topRightColor, 0.08),
          hexToRgba(topRightColor, 0.0),
        ]}
        start={{ x: 1.0, y: 0.0 }}
        end={{ x: 0.55, y: 0.45 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />

      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 24, paddingTop: barHeight }}
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y } } }], {
          useNativeDriver: false,
          listener: (e: any) => {
            const currentY = e.nativeEvent.contentOffset.y;
            const delta = currentY - lastScrollY.current;

            if (delta > 5) {
              if (scrollDirection.current !== 'down') {
                scrollDirection.current = 'down';
                Animated.spring(showPillsAnim, {
                  toValue: 0,
                  useNativeDriver: true,
                  tension: 60,
                  friction: 10,
                }).start();
              }
            } else if (delta < -5) {
              if (scrollDirection.current !== 'up') {
                scrollDirection.current = 'up';
                Animated.spring(showPillsAnim, {
                  toValue: 1,
                  useNativeDriver: true,
                  tension: 60,
                  friction: 10,
                }).start();
              }
            }

            lastScrollY.current = currentY;
          },
        })}
      >
        {heroPick ? (
          <HeroCard
            hero={{ title: heroPick.title, subtitle: heroPick.subtitle, imageUri: heroPick.image, logoUri: heroLogo }}
            inWatchlist={heroInWatchlist}
            watchlistLoading={heroWatchlistLoading}
            onPlay={() => {
              if (heroPick.tmdbId && heroPick.mediaType) {
                nav.navigate('Details', {
                  type: 'tmdb',
                  id: String(heroPick.tmdbId),
                  mediaType: heroPick.mediaType,
                });
              }
            }}
            onAdd={async () => {
              if (!heroPick.tmdbId || !heroPick.mediaType || heroWatchlistLoading) return;
              setHeroWatchlistLoading(true);
              try {
                const ids: WatchlistIds = {
                  tmdbId: heroPick.tmdbId,
                  mediaType: heroPick.mediaType,
                };
                const result = await toggleWatchlist(ids, 'both');
                if (result.success) {
                  setHeroInWatchlist(result.inWatchlist);
                }
              } finally {
                setHeroWatchlistLoading(false);
              }
            }}
          />
        ) : null}

        <View style={{ paddingHorizontal: 16, marginTop: 16 }}>
        {continueItems.length > 0 && (
            <Row
              title="Continue Watching"
              items={continueItems}
              getImageUri={plexContinueImage}
              getTitle={(it) => (it.type === 'episode' ? it.grandparentTitle || it.title || it.name : it.title || it.name)}
              onItemPress={(it) => nav.navigate('Details', { type: 'plex', ratingKey: String(it.ratingKey || it.guid || '') })}
            />
          )}
          
          {popularOnPlexTmdb.length > 0 && (
            <Row
              title="Popular on Plex"
              items={popularOnPlexTmdb}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'tmdb', kind: 'trending', mediaType: 'tv', title: 'Popular on Plex' }, 'Popular on Plex', popularOnPlexTmdb)}
            />
          )}

          {trendingNow.length > 0 && (
            <Row
              title="Trending Now"
              items={trendingNow}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'tmdb', kind: 'trending', mediaType: 'tv', title: 'Trending Now' }, 'Trending Now', trendingNow)}
            />
          )}

          {trendingMovies.length > 0 && (
            <Row
              title="Trending Movies"
              items={trendingMovies}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'tmdb', kind: 'trending', mediaType: 'movie', title: 'Trending Movies' }, 'Trending Movies', trendingMovies)}
            />
          )}

          {trendingAll.length > 0 && (
            <Row
              title="Trending This Week"
              items={trendingAll}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'tmdb', kind: 'trending', mediaType: 'movie', title: 'Trending This Week' }, 'Trending This Week', trendingAll)}
            />
          )}

          {watchlist.length > 0 && (
            <Row
              title="Watchlist"
              items={watchlist}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'plexWatchlist' }, 'Watchlist', watchlist)}
            />
          )}

          {genres['TV Shows - Children']?.length ? (
            <Row title="TV Shows - Children" items={genres['TV Shows - Children']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} />
          ) : null}
          {genres['Movie - Music']?.length ? (
            <Row title="Movie - Music" items={genres['Movie - Music']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} />
          ) : null}
          {genres['Movies - Documentary']?.length ? (
            <Row title="Movies - Documentary" items={genres['Movies - Documentary']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} />
          ) : null}
          {genres['Movies - History']?.length ? (
            <Row title="Movies - History" items={genres['Movies - History']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} />
          ) : null}
          {genres['TV Shows - Reality']?.length ? (
            <Row title="TV Shows - Reality" items={genres['TV Shows - Reality']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} />
          ) : null}
          {genres['Movies - Drama']?.length ? (
            <Row title="Movies - Drama" items={genres['Movies - Drama']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} />
          ) : null}
          {genres['TV Shows - Suspense']?.length ? (
            <Row title="TV Shows - Suspense" items={genres['TV Shows - Suspense']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} />
          ) : null}
          {genres['Movies - Animation']?.length ? (
            <Row title="Movies - Animation" items={genres['Movies - Animation']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} />
          ) : null}

          {recent.length > 0 && (
            <Row
              title="Recently Added"
              items={recent}
              getImageUri={plexImage}
              getTitle={(it) => it.title || it.name}
              onItemPress={(it) => nav.navigate('Details', { type: 'plex', ratingKey: String(it.ratingKey || it.guid || '') })}
            />
          )}

          {tab !== 'shows' && traktTrendMovies.length > 0 && (
            <Row
              title="Trending Movies on Trakt"
              items={traktTrendMovies}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'trending', mediaType: 'movie', title: 'Trending Movies on Trakt' }, 'Trending Movies on Trakt', traktTrendMovies)}
            />
          )}

          {tab !== 'movies' && traktTrendShows.length > 0 && (
            <Row
              title="Trending TV Shows on Trakt"
              items={traktTrendShows}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'trending', mediaType: 'tv', title: 'Trending TV Shows on Trakt' }, 'Trending TV Shows on Trakt', traktTrendShows)}
            />
          )}

          {traktMyWatchlist.length > 0 && (
            <Row
              title="Your Trakt Watchlist"
              items={traktMyWatchlist}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'watchlist', mediaType: 'movie', title: 'Your Trakt Watchlist' }, 'Your Trakt Watchlist', traktMyWatchlist)}
            />
          )}

          {traktHistory.length > 0 && (
            <Row
              title="Recently Watched"
              items={traktHistory}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'history', mediaType: 'movie', title: 'Recently Watched' }, 'Recently Watched', traktHistory)}
            />
          )}

          {traktRecommendations.length > 0 && (
            <Row
              title="Recommended for You"
              items={traktRecommendations}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'recommendations', mediaType: 'movie', title: 'Recommended for You' }, 'Recommended for You', traktRecommendations)}
            />
          )}

          {traktPopularShows.length > 0 && (
            <Row
              title="Popular TV Shows on Trakt"
              items={traktPopularShows}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'trending', mediaType: 'tv', title: 'Popular TV Shows on Trakt' }, 'Popular TV Shows on Trakt', traktPopularShows)}
            />
          )}
        </View>
      </Animated.ScrollView>

      {/* Browse Modal for Categories */}
      <BrowseModal
        visible={browseModalVisible}
        onClose={() => setBrowseModalVisible(false)}
        onSelectGenre={(genre: GenreItem, type: 'movie' | 'tv') => {
          nav.navigate('Library', {
            tab: type === 'movie' ? 'movies' : 'tv',
            genre: genre.title,
            genreKey: genre.key,
          });
        }}
        onSelectLibrary={(library) => {
          nav.navigate('Library', {
            tab: library.type === 'movie' ? 'movies' : 'tv',
            libraryKey: library.key,
          });
        }}
        onSelectCollections={() => {
          nav.navigate('Collections');
        }}
      />
    </SafeAreaView>
  );
}
