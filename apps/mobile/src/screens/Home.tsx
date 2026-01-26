import React, { useEffect, useState, useRef, useCallback, useMemo } from 'react';
import { View, Text, ActivityIndicator, Animated, FlatList, Pressable, Dimensions, InteractionManager, Platform } from 'react-native';
import PullToRefresh from '../components/PullToRefresh';
import FastImage from '@d11/react-native-fast-image';
import { LinearGradient } from 'expo-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import Row from '../components/Row';
import LazyRow from '../components/LazyRow';
import ContinueWatchingLandscapeRow from '../components/ContinueWatchingLandscapeRow';
import ContinueWatchingPosterRow from '../components/ContinueWatchingPosterRow';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { TopBarStore } from '../components/TopBarStore';
import { TOP_BAR_EXPANDED_CONTENT_HEIGHT } from '../components/topBarMetrics';
import HeroCard from '../components/HeroCard';
import HeroCarousel from '../components/HeroCarousel';
import BrowseModal from '../components/BrowseModal';
import { useFlixor } from '../core/FlixorContext';
import { useAppSettings } from '../hooks/useAppSettings';
import type { PlexMediaItem, BrowseContext, BrowseItem } from '@flixor/core';
import {
  fetchTmdbTrendingTVWeek,
  fetchTmdbTrendingMoviesWeek,
  fetchTmdbTrendingAllWeek,
  fetchContinueWatching,
  fetchOnDeck,
  fetchRecentlyAdded,
  fetchPlexWatchlist,
  fetchPlexGenreRow,
  fetchTraktTrendingMovies,
  fetchTraktTrendingShows,
  fetchTraktPopularShows,
  fetchTraktWatchlist,
  fetchTraktHistory,
  fetchTraktRecommendations,
  fetchCollectionRowsForHome,
  getPlexImageUrl,
  getContinueWatchingImageUrl,
  getTmdbLogo,
  getTmdbTextlessPoster,
  getTmdbTextlessBackdrop,
  getTmdbBackdropWithTitle,
  getShowTmdbId,
  getTmdbOverview,
  getUltraBlurColors,
  getUsername,
  convertPlexItemsToHero,
  RowItem,
  GenreItem,
  PlexUltraBlurColors,
  HeroItem,
  CollectionRowData,
} from '../core/HomeData';
import {
  toggleWatchlist,
  checkWatchlistStatus,
  WatchlistIds,
  extractTmdbIdFromGuids,
} from '../core/DetailsData';

interface HomeProps {
  onLogout: () => Promise<void>;
}

// Persistent store for hero content (like NuvioStreaming)
// Cached at module scope to persist across mounts and reduce re-fetches
const persistentStore = {
  heroCarouselData: null as HeroItem[] | null,
  heroSourceItems: null as PlexMediaItem[] | null, // Raw Plex items for hero (Continue Watching / On Deck / Recent)
  popularOnPlexTmdb: null as RowItem[] | null,
  lastFetchTime: 0,
  CACHE_TTL: 5 * 60 * 1000, // 5 minutes
};

// Platform-aware item limits (like NuvioStreaming)
// Android has more memory constraints, so we limit items more aggressively
const ITEM_LIMITS = {
  ROW: Platform.OS === 'android' ? 18 : 30,
  TRENDING: Platform.OS === 'android' ? 10 : 12,
  HERO: Platform.OS === 'android' ? 6 : 8,
};

type HeroPick = { title: string; image?: string; subtitle?: string; tmdbId?: number; mediaType?: 'movie' | 'tv' };

export default function Home({ onLogout }: HomeProps) {
  const { flixor, isLoading: flixorLoading, isConnected } = useFlixor();
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings } = useAppSettings();
  // Initialize loading based on cache - if we have cached hero data, skip loading screen
  const [loading, setLoading] = useState(() => !persistentStore.heroSourceItems);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  const [welcome, setWelcome] = useState<string>('');

  // Plex data
  const [continueItems, setContinueItems] = useState<PlexMediaItem[]>([]);
  const [continueVersions, setContinueVersions] = useState<Set<string>>(new Set());
  const [onDeckItems, setOnDeckItems] = useState<PlexMediaItem[]>([]);
  const [recent, setRecent] = useState<PlexMediaItem[]>([]);
  // Cache for TMDB backdrop URLs with titles (ratingKey -> url)
  const [continueBackdrops, setContinueBackdrops] = useState<Record<string, string>>({});
  // Hero source items (Plex items used for hero carousel)
  const [heroSourceItems, setHeroSourceItems] = useState<PlexMediaItem[]>(
    () => persistentStore.heroSourceItems || []
  );

  // TMDB trending (split into multiple rows)
  // Initialize from persistent store for instant render (like NuvioStreaming)
  const [popularOnPlexTmdb, setPopularOnPlexTmdb] = useState<RowItem[]>(
    () => persistentStore.popularOnPlexTmdb || []
  );
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

  // Collection rows
  const [collectionRows, setCollectionRows] = useState<CollectionRowData[]>([]);

  // UI state
  const [tab, setTab] = useState<'all' | 'movies' | 'shows'>('all');
  const [heroLogo, setHeroLogo] = useState<string | undefined>(undefined);
  const [heroPick, setHeroPick] = useState<HeroPick | null>(null);
  const [heroInWatchlist, setHeroInWatchlist] = useState(false);
  const [heroWatchlistLoading, setHeroWatchlistLoading] = useState(false);
  const [heroColors, setHeroColors] = useState<PlexUltraBlurColors | null>(null);
  const [browseModalVisible, setBrowseModalVisible] = useState(false);
  // Hero carousel uses Plex library items: Continue Watching → On Deck → Recently Added
  // This matches macOS behavior
  const heroCarouselItems = useMemo(() => {
    // Priority: Continue Watching → On Deck → Recently Added (like macOS)
    const sourceItems = heroSourceItems.length > 0
      ? heroSourceItems
      : continueItems.length > 0
        ? continueItems
        : onDeckItems.length > 0
          ? onDeckItems
          : recent;

    return sourceItems.slice(0, ITEM_LIMITS.HERO).map((item) => {
      const isEpisode = item.type === 'episode';
      const displayTitle = isEpisode
        ? item.grandparentTitle || item.title
        : item.title;
      const mediaType: 'movie' | 'tv' = item.type === 'movie' ? 'movie' : 'tv';

      return {
        id: `plex:${item.ratingKey}`,
        title: displayTitle || 'Untitled',
        image: undefined, // Will be enriched later
        mediaType,
      };
    });
  }, [heroSourceItems, continueItems, onDeckItems, recent]);
  const [heroCarouselData, setHeroCarouselData] = useState<HeroItem[]>(
    () => persistentStore.heroCarouselData || []
  );
  const [carouselIndex, setCarouselIndex] = useState(0);
  const [carouselInWatchlist, setCarouselInWatchlist] = useState(false);
  const [carouselWatchlistLoading, setCarouselWatchlistLoading] = useState(false);
  const carouselItem = heroCarouselData[carouselIndex] || null;
  const carouselColorCache = useRef<Map<string, PlexUltraBlurColors>>(new Map());
  const [appleTvIndex, setAppleTvIndex] = useState(0);
  const [appleInWatchlist, setAppleInWatchlist] = useState(false);
  const [appleWatchlistLoading, setAppleWatchlistLoading] = useState(false);
  const appleItem = heroCarouselData[appleTvIndex] || heroCarouselItems[appleTvIndex] || null;

  // Pull-to-refresh state
  const [refreshing, setRefreshing] = useState(false);

  // Preload images for hero carousel (capped at 10 images like NuvioStreaming)
  const preloadImages = useCallback((items: Array<{ image?: string; backdrop?: string }>) => {
    const MAX_PRELOAD = 10;
    const images = items
      .slice(0, MAX_PRELOAD)
      .flatMap(item => [item.backdrop, item.image])
      .filter(Boolean) as string[];

    if (images.length > 0) {
      const sources = images.map(uri => ({
        uri,
        priority: FastImage.priority.normal,
        cache: FastImage.cacheControl.immutable,
      }));
      FastImage.preload(sources);
      console.log(`[Home] Preloaded ${sources.length} images (max ${MAX_PRELOAD})`);
    }
  }, []);

  // Pull-to-refresh handler
  const handleRefresh = useCallback(async () => {
    setRefreshing(true);

    // Clear module-level persistent store
    persistentStore.heroCarouselData = null;
    persistentStore.heroSourceItems = null;
    persistentStore.popularOnPlexTmdb = null;
    persistentStore.lastFetchTime = 0;

    // Clear carousel color cache
    carouselColorCache.current.clear();

    // Invalidate API caches
    if (flixor) {
      await Promise.all([
        flixor.clearPlexCache(),
        flixor.clearTraktCache(),
        flixor.clearTmdbCache(),
      ]);
    }

    // Reset all row states
    setContinueItems([]);
    setOnDeckItems([]);
    setRecent([]);
    setHeroSourceItems([]);
    setPopularOnPlexTmdb([]);
    setTrendingNow([]);
    setTrendingMovies([]);
    setTrendingAll([]);
    setWatchlist([]);
    setGenres({});
    setTraktTrendMovies([]);
    setTraktTrendShows([]);
    setTraktPopularShows([]);
    setTraktMyWatchlist([]);
    setTraktHistory([]);
    setTraktRecommendations([]);
    setCollectionRows([]);
    setHeroCarouselData([]);

    // Re-trigger data load by incrementing retryCount
    setLoading(true);
    setRetryCount(c => c + 1);
    setRefreshing(false);
  }, [flixor]);

  // Preload hero carousel images when data changes
  useEffect(() => {
    if (heroCarouselData.length > 0) {
      preloadImages(heroCarouselData);
    }
  }, [heroCarouselData, preloadImages]);

  const y = React.useRef(new Animated.Value(0)).current;
  const contentTopInset = TOP_BAR_EXPANDED_CONTENT_HEIGHT;
  // Use ref instead of useIsFocused() to avoid re-renders on focus change
  const isFocusedRef = useRef(true);
  const perfRef = useRef({ focusAt: 0, loadAt: 0 });
  const lastTraktRefreshRef = useRef(0);
  const lastHeroColorKeyRef = useRef<string | null>(null);
  const lastHeroColorAtRef = useRef(0);
  const lastHeroSourceRef = useRef<string | null>(null);
  const hasLoadedOnceRef = useRef(false);
  // Keep the selected tab stable across focus to avoid heavy re-render on return.

  // Stable handlers to avoid recreating on every render (prevents stale closures)
  const navigateToLibrary = useCallback((t: 'movies' | 'shows') => {
    nav.navigate('Library', { tab: t === 'movies' ? 'movies' : 'tv' });
  }, [nav]);

  const closeHandler = useCallback(() => {
    setTab('all');
  }, []);

  const browseHandler = useCallback(() => {
    setBrowseModalVisible(true);
  }, []);

  // Set baseUsername once when user data loads (not on every focus)
  // This enables instant title display on navigation without jumpy updates
  useEffect(() => {
    if (welcome) {
      const username = welcome.replace('Welcome, ', '');
      TopBarStore.setBaseUsername(username);
    }
  }, [welcome]);

  // Update TopBarStore with Home configuration when focused
  useFocusEffect(
    useCallback(() => {
      isFocusedRef.current = true;

      TopBarStore.setScrollY(y);
      TopBarStore.setState({
        visible: true,
        tabBarVisible: true,
        showFilters: true,
        selected: tab,
        compact: false,
        customFilters: undefined,
        activeGenre: undefined,
        onNavigateLibrary: navigateToLibrary,
        onClose: closeHandler,
        onBrowse: browseHandler,
        onClearGenre: undefined,
      });

      return () => {
        isFocusedRef.current = false;
      };
    }, [tab, navigateToLibrary, closeHandler, browseHandler, y])
  );

  // Also update when tab changes while focused (for pill selection on Home)
  React.useLayoutEffect(() => {
    if (!isFocusedRef.current || !welcome) return;
    TopBarStore.setSelected(tab);
  }, [tab, welcome]);

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

  const getRowWatchlistIds = (item: RowItem): WatchlistIds | null => {
    if (!item.id || !item.mediaType) return null;
    if (item.id.startsWith('tmdb:')) {
      const parts = item.id.split(':');
      const tmdbId = parseInt(parts[2], 10);
      if (!Number.isNaN(tmdbId)) {
        return { tmdbId, mediaType: item.mediaType };
      }
    }
    return null;
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

  // Navigate to Browse for Continue Watching (PlexMediaItem -> BrowseItem conversion)
  const openContinueWatchingBrowse = useCallback(() => {
    const browseItems: BrowseItem[] = continueItems.map((item) => {
      const isEpisode = item.type === 'episode';
      return {
        id: `plex:${item.ratingKey}`,
        title: isEpisode ? (item.grandparentTitle || item.title) : item.title,
        image: getContinueWatchingImageUrl(item, 300), // Use show poster for episodes
        subtitle: isEpisode ? `S${item.parentIndex || 1}, E${item.index || 1}` : undefined,
        year: !isEpisode && item.year ? item.year : undefined,
      };
    });
    nav.navigate('Browse', {
      context: { type: 'plexContinue' } as any,
      title: 'Continue Watching',
      initialItems: browseItems
    });
  }, [nav, continueItems]);

  // Main data loading effect - Progressive loading pattern (like NuvioStreaming)
  // Shows UI as soon as first content is ready instead of waiting for everything
  useEffect(() => {
    if (flixorLoading || !isConnected) return;

    let hasExitedLoading = false;
    const exitLoading = () => {
      if (!hasExitedLoading) {
        hasExitedLoading = true;
        setLoading(false);
        hasLoadedOnceRef.current = true;
      }
    };

    (async () => {
      const loadStart = Date.now();
      perfRef.current.loadAt = loadStart;
      console.log(`[Home][perf] initial load start (progressive)`);
      try {
        setError(null);

        // Get user info first (fast)
        const name = await getUsername();
        setWelcome(`Welcome, ${name}`);

        // Start ALL fetches in parallel but don't wait for all
        const continuePromise = fetchContinueWatching();
        const onDeckPromise = fetchOnDeck();
        const recentPromise = fetchRecentlyAdded();
        const trendingTVPromise = fetchTmdbTrendingTVWeek();
        const watchlistPromise = fetchPlexWatchlist();
        const trendingMoviesPromise = fetchTmdbTrendingMoviesWeek();
        const trendingAllPromise = fetchTmdbTrendingAllWeek();

        // Exit loading as soon as Plex hero content (Continue Watching / On Deck / Recent) is ready
        // Priority: Continue Watching → On Deck → Recently Added (matches macOS behavior)
        continuePromise.then(async (continueResult) => {
          console.log('[Home] continuePromise resolved:', continueResult);
          InteractionManager.runAfterInteractions(async () => {
            const continueData = continueResult?.items || [];
            console.log('[Home] Setting continueItems:', continueData.length);
            setContinueItems(continueData);
            setContinueVersions(continueResult?.itemsWithMultipleVersions || new Set());

            // If we have continue watching items, use them for hero
            if (continueData.length > 0) {
              const heroItems = continueData.slice(0, ITEM_LIMITS.HERO);
              setHeroSourceItems(heroItems);
              persistentStore.heroSourceItems = heroItems;
              persistentStore.lastFetchTime = Date.now();
              exitLoading();
              console.log(`[Home][perf] hero content ready (Continue Watching: ${heroItems.length} items) in ${Date.now() - loadStart}ms`);

              // Enrich hero items with TMDB data in background
              convertPlexItemsToHero(heroItems, ITEM_LIMITS.HERO).then((enriched) => {
                setHeroCarouselData(enriched);
                persistentStore.heroCarouselData = enriched;
              });
            }

            // Fetch TMDB backdrops for Continue Watching row
            continueData.forEach(async (item) => {
              try {
                let tmdbId: string | null = null;
                let mediaType: 'movie' | 'tv' = 'movie';

                if (item.type === 'movie') {
                  tmdbId = extractTmdbIdFromGuids(item.Guid || []);
                  mediaType = 'movie';
                } else if (item.type === 'episode' && item.grandparentRatingKey) {
                  tmdbId = await getShowTmdbId(item.grandparentRatingKey);
                  mediaType = 'tv';
                }

                if (tmdbId) {
                  const backdrop = await getTmdbBackdropWithTitle(Number(tmdbId), mediaType);
                  if (backdrop) {
                    setContinueBackdrops(prev => ({ ...prev, [item.ratingKey]: backdrop }));
                  }
                }
              } catch (e) {
                // Silently handle errors - fallback to Plex images
              }
            });
          });
        }).catch((err) => {
          console.log('[Home] continuePromise error:', err);
          setContinueItems([]);
        });

        // On Deck fallback for hero
        onDeckPromise.then((onDeckData) => {
          InteractionManager.runAfterInteractions(async () => {
            setOnDeckItems(onDeckData);

            // If no continue watching but have on deck, use for hero
            const currentHeroSource = persistentStore.heroSourceItems;
            if ((!currentHeroSource || currentHeroSource.length === 0) && onDeckData.length > 0) {
              const heroItems = onDeckData.slice(0, ITEM_LIMITS.HERO);
              setHeroSourceItems(heroItems);
              persistentStore.heroSourceItems = heroItems;
              persistentStore.lastFetchTime = Date.now();
              exitLoading();
              console.log(`[Home][perf] hero content ready (On Deck: ${heroItems.length} items) in ${Date.now() - loadStart}ms`);

              // Enrich hero items with TMDB data
              convertPlexItemsToHero(heroItems, ITEM_LIMITS.HERO).then((enriched) => {
                setHeroCarouselData(enriched);
                persistentStore.heroCarouselData = enriched;
              });
            }
          });
        }).catch(() => setOnDeckItems([]));

        // TMDB trending rows (not for hero, but for content rows)
        trendingTVPromise.then((tv) => {
          InteractionManager.runAfterInteractions(() => {
            console.log('[Home] TMDB trending TV fetched:', tv.length, 'items');
            setPopularOnPlexTmdb(tv.slice(0, ITEM_LIMITS.TRENDING));
            setTrendingNow(tv.slice(ITEM_LIMITS.TRENDING, ITEM_LIMITS.TRENDING * 2));
            persistentStore.popularOnPlexTmdb = tv.slice(0, ITEM_LIMITS.TRENDING);
          });
        }).catch(() => {});

        // Recently Added - also serves as final hero fallback
        recentPromise.then((recentData) => {
          InteractionManager.runAfterInteractions(async () => {
            setRecent(recentData);

            // If no continue watching or on deck, use recently added for hero
            const currentHeroSource = persistentStore.heroSourceItems;
            if ((!currentHeroSource || currentHeroSource.length === 0) && recentData.length > 0) {
              const heroItems = recentData.slice(0, ITEM_LIMITS.HERO);
              setHeroSourceItems(heroItems);
              persistentStore.heroSourceItems = heroItems;
              persistentStore.lastFetchTime = Date.now();
              exitLoading();
              console.log(`[Home][perf] hero content ready (Recently Added: ${heroItems.length} items) in ${Date.now() - loadStart}ms`);

              // Enrich hero items with TMDB data
              convertPlexItemsToHero(heroItems, ITEM_LIMITS.HERO).then((enriched) => {
                setHeroCarouselData(enriched);
                persistentStore.heroCarouselData = enriched;
              });
            }
          });
        }).catch(() => setRecent([]));
        watchlistPromise.then((items) => {
          InteractionManager.runAfterInteractions(() => setWatchlist(items));
        }).catch(() => setWatchlist([]));
        trendingMoviesPromise.then((items) => {
          InteractionManager.runAfterInteractions(() => setTrendingMovies(items.slice(0, ITEM_LIMITS.TRENDING)));
        }).catch(() => setTrendingMovies([]));
        trendingAllPromise.then((items) => {
          InteractionManager.runAfterInteractions(() => setTrendingAll(items.slice(0, ITEM_LIMITS.TRENDING)));
        }).catch(() => setTrendingAll([]));

        // Wait for all primary rows with a timeout fallback
        await Promise.race([
          Promise.allSettled([
            continuePromise,
            recentPromise,
            trendingTVPromise,
            watchlistPromise,
            trendingMoviesPromise,
            trendingAllPromise,
          ]),
          new Promise(resolve => setTimeout(resolve, 3000)), // 3s timeout
        ]);

        // Exit loading if not already (fallback)
        exitLoading();

        // Genre rows - load in background (don't block UI)
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

        // Load genres progressively - update state as each completes (deferred)
        genreDefs.forEach(async (gd) => {
          try {
            const items = await fetchPlexGenreRow(gd.type, gd.label);
            InteractionManager.runAfterInteractions(() => {
              setGenres(prev => ({ ...prev, [gd.key]: items }));
            });
          } catch {}
        });

        // Trakt rows - load in background (deferred updates)
        fetchTraktTrendingMovies().then((items) => {
          InteractionManager.runAfterInteractions(() => setTraktTrendMovies(items));
        }).catch(() => {});
        fetchTraktTrendingShows().then((items) => {
          InteractionManager.runAfterInteractions(() => setTraktTrendShows(items));
        }).catch(() => {});
        fetchTraktPopularShows().then((items) => {
          InteractionManager.runAfterInteractions(() => setTraktPopularShows(items));
        }).catch(() => {});
        fetchTraktWatchlist().then((items) => {
          InteractionManager.runAfterInteractions(() => setTraktMyWatchlist(items));
        }).catch(() => {});
        fetchTraktHistory().then((items) => {
          InteractionManager.runAfterInteractions(() => setTraktHistory(items));
        }).catch(() => {});
        fetchTraktRecommendations().then((items) => {
          InteractionManager.runAfterInteractions(() => setTraktRecommendations(items));
        }).catch(() => {});

        // Collection rows - load in background (deferred)
        if (settings.showCollectionRows) {
          fetchCollectionRowsForHome(10).then((rows) => {
            InteractionManager.runAfterInteractions(() => {
              // Filter out hidden collections and limit to 5
              const hiddenKeys = new Set(settings.hiddenCollectionKeys || []);
              const visibleRows = rows
                .filter((row) => !hiddenKeys.has(row.ratingKey))
                .slice(0, 5);
              setCollectionRows(visibleRows);
            });
          }).catch(() => setCollectionRows([]));
        }

        const durationMs = Date.now() - loadStart;
        console.log(`[Home][perf] all fetches dispatched in ${durationMs}ms`);
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
      }
    })();
  }, [flixorLoading, isConnected, retryCount]);

  // Memory management: Clear FastImage memory cache when app goes to background
  // Note: Memory cleanup on app background is now handled centrally by MemoryManager

  const scheduleIdleWork = useCallback((work: () => void, delayMs = 0) => {
    let cancelled = false;
    let task: { cancel?: () => void } | null = null;
    const timeout = setTimeout(() => {
      if (cancelled) return;
      task = InteractionManager.runAfterInteractions(() => {
        if (!cancelled) work();
      }) as unknown as { cancel?: () => void };
    }, delayMs);
    return () => {
      cancelled = true;
      clearTimeout(timeout);
      if (task?.cancel) task.cancel();
    };
  }, []);

  // Fetch hero pick from enriched hero carousel data (Plex-based)
  useEffect(() => {
    if (!hasLoadedOnceRef.current) return;
    if (heroCarouselData.length === 0) {
      console.log('[Home] No heroCarouselData yet, skipping hero pick');
      return;
    }

    const sourceKey = heroCarouselData[0]?.id || null;
    if (sourceKey && sourceKey === lastHeroSourceRef.current && heroPick) {
      return;
    }
    lastHeroSourceRef.current = sourceKey;

    console.log('[Home] Setting hero pick from Plex carousel data...');
    const cancel = scheduleIdleWork(async () => {
      try {
        // Pick a random hero from the carousel data (already enriched with TMDB data)
        const randomIndex = Math.floor(Math.random() * Math.min(heroCarouselData.length, 8));
        const pick = heroCarouselData[randomIndex];

        const hero: HeroPick = {
          title: pick.title,
          image: pick.backdrop || pick.image,
          subtitle: pick.year || undefined,
          mediaType: pick.mediaType,
        };

        // Set logo if available
        if (pick.logo) {
          setHeroLogo(pick.logo);
        }

        setHeroPick(hero);
        console.log('[Home] Hero pick set:', hero.title);
      } catch (e) {
        console.log('[Home] Error in hero selection:', e);
      }
    }, 500);
    return cancel;
  }, [heroCarouselData, heroPick, scheduleIdleWork]);

  useEffect(() => {
    if (!isFocusedRef.current) return;
    if (!heroPick?.image) return;
    const colorKey = `hero:${heroPick.image}`;
    if (colorKey === lastHeroColorKeyRef.current && heroColors) return;
    const cached = carouselColorCache.current.get(colorKey);
    if (cached) {
      lastHeroColorKeyRef.current = colorKey;
      setHeroColors(cached);
      return;
    }
    const cancel = scheduleIdleWork(async () => {
      try {
        const now = Date.now();
        if (now - lastHeroColorAtRef.current < 60000) return;
        console.log('[Home] Fetching UltraBlur colors for hero poster');
        const colors = await getUltraBlurColors(heroPick.image as string);
        if (colors) {
          carouselColorCache.current.set(colorKey, colors);
          lastHeroColorKeyRef.current = colorKey;
          setHeroColors(colors);
          lastHeroColorAtRef.current = now;
        }
      } catch {}
    }, 800);
    return cancel;
  }, [heroPick?.image, heroColors, scheduleIdleWork]);

  // Hero enrichment is now handled in the data loading effect via convertPlexItemsToHero
  // This effect only runs if heroCarouselData is empty but heroSourceItems changed
  useEffect(() => {
    if (heroCarouselData.length > 0 || heroSourceItems.length === 0) return;

    let active = true;
    (async () => {
      console.log('[Home] Enriching hero items from Plex source:', heroSourceItems.length);
      const enriched = await convertPlexItemsToHero(heroSourceItems, ITEM_LIMITS.HERO);
      if (active && enriched.length > 0) {
        setHeroCarouselData(enriched);
        setCarouselIndex(0);
        persistentStore.heroCarouselData = enriched;
      }
    })();
    return () => {
      active = false;
    };
  }, [heroSourceItems, heroCarouselData.length]);

  // Precompute ultraBlur colors for all carousel items
  useEffect(() => {
    if (heroCarouselData.length === 0) return;
    if (settings.heroLayout !== 'carousel') return;

    const cleanupFns: (() => void)[] = [];

    heroCarouselData.forEach((item, index) => {
      const cacheKey = `carousel:${item.id}`;
      if (carouselColorCache.current.has(cacheKey)) return;

      const source = item.backdrop || item.image;
      if (!source) return;

      // Stagger fetches to avoid overwhelming the server (200ms apart)
      const cancel = scheduleIdleWork(async () => {
        try {
          const colors = await getUltraBlurColors(source);
          if (colors) {
            carouselColorCache.current.set(cacheKey, colors);
            // If this is the currently active item and colors aren't set, update now
            if (index === carouselIndex && !heroColors) {
              setHeroColors(colors);
            }
          }
        } catch {}
      }, index * 200);
      cleanupFns.push(cancel);
    });

    return () => {
      cleanupFns.forEach(fn => fn());
    };
  }, [heroCarouselData, settings.heroLayout, scheduleIdleWork]);

  useEffect(() => {
    let active = true;
    (async () => {
      if (!carouselItem) return;
      const ids = getRowWatchlistIds(carouselItem as RowItem);
      if (!ids) return;
      try {
        const inWatchlist = await checkWatchlistStatus(ids);
        if (active) setCarouselInWatchlist(inWatchlist);
      } catch {}
    })();
    return () => {
      active = false;
    };
  }, [carouselItem]);

  useEffect(() => {
    if (!isFocusedRef.current) return;
    if (settings.heroLayout !== 'carousel') return;
    if (!carouselItem?.image) return;
    const cacheKey = `carousel:${carouselItem.id}`;
    const cached = carouselColorCache.current.get(cacheKey);
    if (cached) {
      setHeroColors(cached);
      return;
    }
    // Fetch colors for this carousel item (no throttle - cache handles dedup)
    const cancel = scheduleIdleWork(async () => {
      try {
        const source = carouselItem.backdrop || carouselItem.image;
        const colors = await getUltraBlurColors(source as string);
        if (colors) {
          carouselColorCache.current.set(cacheKey, colors);
          setHeroColors(colors);
        }
      } catch {}
    }, 100); // Reduced delay for faster color updates
    return cancel;
  }, [carouselItem, settings.heroLayout, scheduleIdleWork]);

  useEffect(() => {
    let active = true;
    (async () => {
      if (!appleItem || settings.heroLayout !== 'appletv') return;
      const ids = getRowWatchlistIds(appleItem);
      if (!ids) return;
      try {
        const inWatchlist = await checkWatchlistStatus(ids);
        if (active) setAppleInWatchlist(inWatchlist);
      } catch {}
    })();
    return () => {
      active = false;
    };
  }, [appleItem, settings.heroLayout]);

  useEffect(() => {
    if (!isFocusedRef.current) return;
    if (settings.heroLayout !== 'appletv') return;
    const source = appleItem?.backdrop || appleItem?.image;
    if (!appleItem?.id || !source) return;
    const cacheKey = `appletv:${appleItem.id}`;
    const cached = carouselColorCache.current.get(cacheKey);
    if (cached) {
      setHeroColors(cached);
      return;
    }
    const cancel = scheduleIdleWork(async () => {
      try {
        const now = Date.now();
        if (now - lastHeroColorAtRef.current < 60000) return;
        const colors = await getUltraBlurColors(source);
        if (colors) {
          carouselColorCache.current.set(cacheKey, colors);
          setHeroColors(colors);
          lastHeroColorAtRef.current = now;
        }
      } catch {}
    }, 800);
    return cancel;
  }, [appleItem, settings.heroLayout, scheduleIdleWork]);

  useEffect(() => {
    if (appleTvIndex >= heroCarouselItems.length) {
      setAppleTvIndex(0);
    }
  }, [appleTvIndex, heroCarouselItems.length]);

  const isSameRowList = useCallback((prev: RowItem[], next: RowItem[]) => {
    if (prev === next) return true;
    if (prev.length !== next.length) return false;
    if (prev.length === 0) return true;
    return prev[0]?.id === next[0]?.id && prev[prev.length - 1]?.id === next[next.length - 1]?.id;
  }, []);

  // Light refresh of Trakt-dependent rows on focus - using useFocusEffect to avoid re-renders
  useFocusEffect(
    useCallback(() => {
      if (loading || !hasLoadedOnceRef.current) return;
      const focusAt = Date.now();
      perfRef.current.focusAt = focusAt;

      const now = Date.now();
      if (now - lastTraktRefreshRef.current < 120000) {
        return;
      }

      const cancel = scheduleIdleWork(async () => {
        try {
          await new Promise(resolve => setTimeout(resolve, 500));
          const results = await Promise.allSettled([
            fetchTraktTrendingMovies(),
            fetchTraktTrendingShows(),
            fetchTraktPopularShows(),
            fetchTraktWatchlist(),
            fetchTraktHistory(),
            fetchTraktRecommendations(),
          ]);
          const tval = <T,>(i: number): T =>
            results[i].status === 'fulfilled'
              ? (results[i] as PromiseFulfilledResult<T>).value
              : ([] as any);

          const nextTrendMovies = tval<RowItem[]>(0);
          const nextTrendShows = tval<RowItem[]>(1);
          const nextPopularShows = tval<RowItem[]>(2);
          const nextWatchlist = tval<RowItem[]>(3);
          const nextHistory = tval<RowItem[]>(4);
          const nextRecommendations = tval<RowItem[]>(5);

          setTraktTrendMovies(prev => (isSameRowList(prev, nextTrendMovies) ? prev : nextTrendMovies));
          setTraktTrendShows(prev => (isSameRowList(prev, nextTrendShows) ? prev : nextTrendShows));
          setTraktPopularShows(prev => (isSameRowList(prev, nextPopularShows) ? prev : nextPopularShows));
          setTraktMyWatchlist(prev => (isSameRowList(prev, nextWatchlist) ? prev : nextWatchlist));
          setTraktHistory(prev => (isSameRowList(prev, nextHistory) ? prev : nextHistory));
          setTraktRecommendations(prev => (isSameRowList(prev, nextRecommendations) ? prev : nextRecommendations));
          lastTraktRefreshRef.current = Date.now();
        } catch {}
      }, 1200);

      return cancel;
    }, [loading, isSameRowList, scheduleIdleWork])
  );

  const getRowUri = useCallback((it: RowItem) => it.image, []);
  const getRowTitle = useCallback((it: RowItem) => it.title, []);
  const onRowPress = useCallback((it: RowItem) => {
    if (!it?.id) return;
    if (it.id.startsWith('plex:')) {
      const rk = it.id.split(':')[1];
      return nav.navigate('Details', { type: 'plex', ratingKey: rk });
    }
    if (it.id.startsWith('tmdb:')) {
      const [, media, id] = it.id.split(':');
      return nav.navigate('Details', { type: 'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
    }
  }, [nav]);

  const plexImage = useCallback((item: PlexMediaItem) => getPlexImageUrl(item, 300), []);
  const plexContinueImage = useCallback((item: PlexMediaItem) => getContinueWatchingImageUrl(item, 300), []);
  // Landscape image for Continue Watching - prefer TMDB backdrop with title
  const plexContinueLandscapeImage = useCallback((item: PlexMediaItem) => {
    // Check if we have a TMDB backdrop with title cached (for both movies and episodes)
    if (item.ratingKey && continueBackdrops[item.ratingKey]) {
      return continueBackdrops[item.ratingKey];
    }
    // Fallback to Plex art - for episodes use grandparentArt (show backdrop)
    const path = item.type === 'episode'
      ? (item.grandparentArt || item.art || item.thumb)
      : (item.art || item.thumb);
    if (!path) return '';
    return getPlexImageUrl({ ...item, thumb: path } as PlexMediaItem, 600);
  }, [continueBackdrops]);
  const getContinueTitle = useCallback((it: any) => {
    if (it.type === 'episode') {
      return it.grandparentTitle || it.title || 'Episode';
    }
    return it.title || it.name;
  }, []);
  const getContinueSubtitle = useCallback((it: any) => {
    if (it.type === 'episode') {
      const seasonNum = it.parentIndex || 1;
      const episodeNum = it.index || 1;
      return `S${seasonNum}, E${episodeNum}`;
    }
    // For movies, show the year
    if (it.year) {
      return String(it.year);
    }
    return undefined;
  }, []);
  const onContinuePress = useCallback((it: any) => {
    const ratingKey = String(it.ratingKey || it.guid || '');
    if (settings.useCachedStreams) {
      nav.navigate('Player', { type: 'plex', ratingKey });
    } else if (settings.openMetadataScreenWhenCacheDisabled) {
      nav.navigate('Details', { type: 'plex', ratingKey });
    } else {
      nav.navigate('Player', { type: 'plex', ratingKey });
    }
  }, [nav, settings.useCachedStreams, settings.openMetadataScreenWhenCacheDisabled]);

  // Show loading while FlixorCore is initializing or not connected
  if (flixorLoading || !isConnected) {
    return (
      <View style={{ flex: 1, backgroundColor: '#1b0a10', alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator color="#fff" />
        <Text style={{ color: '#999', marginTop: 12 }}>
          {flixorLoading ? 'Initializing...' : 'Connecting to server...'}
        </Text>
      </View>
    );
  }

  // Only show loading screen if we have no cached content to display
  // This prevents blank screen flash when returning to Home with cached data
  const hasContentToShow = heroSourceItems.length > 0 || heroCarouselData.length > 0 || continueItems.length > 0;
  if ((loading && !hasContentToShow) || error) {
    return (
      <View style={{ flex: 1, backgroundColor: '#1b0a10', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
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

  // Convert hex color to rgba with opacity
  const hexToRgba = (hex: string, opacity: number) => {
    const r = parseInt(hex.slice(0, 2), 16);
    const g = parseInt(hex.slice(2, 4), 16);
    const b = parseInt(hex.slice(4, 6), 16);
    return `rgba(${r},${g},${b},${opacity})`;
  };

  const canShowHero = settings.showHeroSection && (heroPick || heroCarouselItems.length > 0);

  // Get gradient colors from heroColors or use defaults
  const bottomLeftColor = heroColors?.bottomLeft || '7a1612';
  const topRightColor = heroColors?.topRight || '144c54';

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#1b0a10' }} edges={['top', 'left', 'right']}>
      <LinearGradient
        colors={['#1a1a1a', '#181818', '#151515']}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 1 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />
      <LinearGradient
        colors={[
          hexToRgba(bottomLeftColor, 0.55),
          hexToRgba(bottomLeftColor, 0.25),
          hexToRgba(bottomLeftColor, 0.0),
        ]}
        start={{ x: 0.0, y: 1.0 }}
        end={{ x: 0.45, y: 0.35 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />
      <LinearGradient
        colors={[
          hexToRgba(topRightColor, 0.50),
          hexToRgba(topRightColor, 0.20),
          hexToRgba(topRightColor, 0.0),
        ]}
        start={{ x: 1.0, y: 0.0 }}
        end={{ x: 0.55, y: 0.45 }}
        style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
      />

      <PullToRefresh scrollY={y} refreshing={refreshing} onRefresh={handleRefresh} />

      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 80 + insets.bottom, paddingTop: contentTopInset }}
        scrollEventThrottle={16}
        onScroll={(e: any) => {
          const currentY = e.nativeEvent.contentOffset.y;
          y.setValue(currentY);
        }}
      >
        {canShowHero ? (
          settings.heroLayout === 'carousel' ? (
            <HeroCarousel
              items={heroCarouselData}
              onSelect={(item) => {
                const ids = getRowWatchlistIds(item);
                if (ids) {
                  // Navigate via TMDB
                  nav.navigate('Details', {
                    type: 'tmdb',
                    id: String(ids.tmdbId),
                    mediaType: ids.mediaType,
                  });
                } else if (item.id?.startsWith('plex:')) {
                  // Fallback: navigate via Plex ratingKey
                  const ratingKey = item.id.replace('plex:', '');
                  nav.navigate('Details', {
                    type: 'plex',
                    ratingKey,
                  });
                }
              }}
              onAdd={async (item) => {
                const ids = getRowWatchlistIds(item);
                if (!ids || carouselWatchlistLoading) return;
                setCarouselWatchlistLoading(true);
                try {
                  const result = await toggleWatchlist(ids, 'both');
                  if (result.success) {
                    setCarouselInWatchlist(result.inWatchlist);
                  }
                } finally {
                  setCarouselWatchlistLoading(false);
                }
              }}
              inWatchlist={carouselInWatchlist}
              watchlistLoading={carouselWatchlistLoading}
              onActiveIndexChange={setCarouselIndex}
            />
          ) : settings.heroLayout === 'appletv' ? (
            <HeroAppleTV
              items={heroCarouselData}
              selectedIndex={appleTvIndex}
              onSelectIndex={setAppleTvIndex}
              onAdd={async () => {
                const ids = appleItem ? getRowWatchlistIds(appleItem) : null;
                if (!ids || appleWatchlistLoading) return;
                setAppleWatchlistLoading(true);
                try {
                  const result = await toggleWatchlist(ids, 'both');
                  if (result.success) {
                    setAppleInWatchlist(result.inWatchlist);
                  }
                } finally {
                  setAppleWatchlistLoading(false);
                }
              }}
              inWatchlist={appleInWatchlist}
              watchlistLoading={appleWatchlistLoading}
            />
          ) : (
            heroPick ? (
              <HeroCard
                hero={{ title: heroPick.title, subtitle: heroPick.subtitle, imageUri: heroPick.image, logoUri: heroLogo }}
                inWatchlist={heroInWatchlist}
                watchlistLoading={heroWatchlistLoading}
                onPress={() => {
                  if (heroPick.tmdbId && heroPick.mediaType) {
                    nav.navigate('Details', {
                      tmdbId: heroPick.tmdbId,
                      mediaType: heroPick.mediaType,
                      title: heroPick.title,
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
            ) : null
          )
        ) : null}

        <View style={{ marginTop: 16 }}>
        {settings.showContinueWatchingRow && continueItems.length > 0 && (
            settings.continueWatchingLayout === 'landscape' ? (
              <ContinueWatchingLandscapeRow
                items={continueItems}
                itemsWithMultipleVersions={continueVersions}
                onItemPress={onContinuePress}
                onBrowsePress={openContinueWatchingBrowse}
                getImageUri={plexContinueLandscapeImage}
                onInfo={(item) => nav.navigate('Details', { type: 'plex', ratingKey: item.ratingKey })}
              />
            ) : (
              <ContinueWatchingPosterRow
                items={continueItems}
                itemsWithMultipleVersions={continueVersions}
                onItemPress={onContinuePress}
                onBrowsePress={openContinueWatchingBrowse}
                getImageUri={plexContinueImage}
                getTitle={getContinueTitle}
                getSubtitle={getContinueSubtitle}
                onInfo={(item) => nav.navigate('Details', { type: 'plex', ratingKey: item.ratingKey })}
              />
            )
          )}

          {/* Collection Rows */}
          {settings.showCollectionRows && collectionRows.map((collection) => (
            collection.items.length > 0 ? (
              <LazyRow
                key={`collection-${collection.ratingKey}`}
                title={collection.title}
                titleIcon="sparkles"
                items={collection.items}
                getImageUri={getRowUri}
                getTitle={getRowTitle}
                onItemPress={onRowPress}
                onBrowsePress={() => openRowBrowse(
                  { type: 'plexCollection', collectionKey: collection.ratingKey } as any,
                  collection.title,
                  collection.items
                )}
                keyPrefix={`collection-${collection.ratingKey}-`}
              />
            ) : null
          ))}

          {settings.showPlexPopularRow && popularOnPlexTmdb.length > 0 && (
            <Row
              title="Popular on Plex"
              items={popularOnPlexTmdb}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'tmdb', kind: 'trending', mediaType: 'tv', title: 'Popular on Plex' }, 'Popular on Plex', popularOnPlexTmdb)}
            />
          )}

          {settings.showTrendingRows && trendingNow.length > 0 && (
            <LazyRow
              title="Trending Now"
              items={trendingNow}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'tmdb', kind: 'trending', mediaType: 'tv', title: 'Trending Now' }, 'Trending Now', trendingNow)}
              keyPrefix="tmdb-trending-now-"
            />
          )}

          {settings.showTrendingRows && trendingMovies.length > 0 && (
            <LazyRow
              title="Trending Movies"
              items={trendingMovies}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'tmdb', kind: 'trending', mediaType: 'movie', title: 'Trending Movies' }, 'Trending Movies', trendingMovies)}
              keyPrefix="tmdb-trending-movies-"
            />
          )}

          {settings.showTrendingRows && trendingAll.length > 0 && (
            <LazyRow
              title="Trending This Week"
              items={trendingAll}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'tmdb', kind: 'trending', mediaType: 'movie', title: 'Trending This Week' }, 'Trending This Week', trendingAll)}
              keyPrefix="tmdb-trending-week-"
            />
          )}

          {watchlist.length > 0 && (
            <LazyRow
              title="Watchlist"
              items={watchlist}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'plexWatchlist' }, 'Watchlist', watchlist)}
              keyPrefix="plex-watchlist-"
            />
          )}

          {genres['TV Shows - Children']?.length ? (
            <LazyRow title="TV Shows - Children" items={genres['TV Shows - Children']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} onBrowsePress={() => openRowBrowse({ type: 'plexGenre', genre: 'Children', mediaType: 'tv' }, 'TV Shows - Children', genres['TV Shows - Children'])} keyPrefix="genre-tv-children-" />
          ) : null}
          {genres['Movie - Music']?.length ? (
            <LazyRow title="Movie - Music" items={genres['Movie - Music']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} onBrowsePress={() => openRowBrowse({ type: 'plexGenre', genre: 'Music', mediaType: 'movie' }, 'Movie - Music', genres['Movie - Music'])} keyPrefix="genre-movie-music-" />
          ) : null}
          {genres['Movies - Documentary']?.length ? (
            <LazyRow title="Movies - Documentary" items={genres['Movies - Documentary']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} onBrowsePress={() => openRowBrowse({ type: 'plexGenre', genre: 'Documentary', mediaType: 'movie' }, 'Movies - Documentary', genres['Movies - Documentary'])} keyPrefix="genre-movie-doc-" />
          ) : null}
          {genres['Movies - History']?.length ? (
            <LazyRow title="Movies - History" items={genres['Movies - History']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} onBrowsePress={() => openRowBrowse({ type: 'plexGenre', genre: 'History', mediaType: 'movie' }, 'Movies - History', genres['Movies - History'])} keyPrefix="genre-movie-history-" />
          ) : null}
          {genres['TV Shows - Reality']?.length ? (
            <LazyRow title="TV Shows - Reality" items={genres['TV Shows - Reality']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} onBrowsePress={() => openRowBrowse({ type: 'plexGenre', genre: 'Reality', mediaType: 'tv' }, 'TV Shows - Reality', genres['TV Shows - Reality'])} keyPrefix="genre-tv-reality-" />
          ) : null}
          {genres['Movies - Drama']?.length ? (
            <LazyRow title="Movies - Drama" items={genres['Movies - Drama']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} onBrowsePress={() => openRowBrowse({ type: 'plexGenre', genre: 'Drama', mediaType: 'movie' }, 'Movies - Drama', genres['Movies - Drama'])} keyPrefix="genre-movie-drama-" />
          ) : null}
          {genres['TV Shows - Suspense']?.length ? (
            <LazyRow title="TV Shows - Suspense" items={genres['TV Shows - Suspense']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} onBrowsePress={() => openRowBrowse({ type: 'plexGenre', genre: 'Suspense', mediaType: 'tv' }, 'TV Shows - Suspense', genres['TV Shows - Suspense'])} keyPrefix="genre-tv-suspense-" />
          ) : null}
          {genres['Movies - Animation']?.length ? (
            <LazyRow title="Movies - Animation" items={genres['Movies - Animation']} getImageUri={getRowUri} getTitle={getRowTitle} onItemPress={onRowPress} onBrowsePress={() => openRowBrowse({ type: 'plexGenre', genre: 'Animation', mediaType: 'movie' }, 'Movies - Animation', genres['Movies - Animation'])} keyPrefix="genre-movie-animation-" />
          ) : null}

          {recent.length > 0 && (
            <LazyRow
              title="Recently Added"
              items={recent}
              getImageUri={plexImage}
              getTitle={(it) => it.title || it.name}
              onItemPress={(it) => nav.navigate('Details', { type: 'plex', ratingKey: String(it.ratingKey || it.guid || '') })}
              onBrowsePress={() => openRowBrowse({ type: 'plexRecent' }, 'Recently Added', recent)}
              keyPrefix="plex-recent-"
            />
          )}

          {settings.showTraktRows && tab !== 'shows' && traktTrendMovies.length > 0 && (
            <LazyRow
              title="Trending Movies on Trakt"
              items={traktTrendMovies}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'trending', mediaType: 'movie', title: 'Trending Movies on Trakt' }, 'Trending Movies on Trakt', traktTrendMovies)}
              keyPrefix="trakt-trend-movies-"
            />
          )}

          {settings.showTraktRows && tab !== 'movies' && traktTrendShows.length > 0 && (
            <LazyRow
              title="Trending TV Shows on Trakt"
              items={traktTrendShows}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'trending', mediaType: 'tv', title: 'Trending TV Shows on Trakt' }, 'Trending TV Shows on Trakt', traktTrendShows)}
              keyPrefix="trakt-trend-shows-"
            />
          )}

          {settings.showTraktRows && traktMyWatchlist.length > 0 && (
            <LazyRow
              title="Your Trakt Watchlist"
              items={traktMyWatchlist}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'watchlist', mediaType: 'movie', title: 'Your Trakt Watchlist' }, 'Your Trakt Watchlist', traktMyWatchlist)}
              keyPrefix="trakt-watchlist-"
            />
          )}

          {settings.showTraktRows && traktHistory.length > 0 && (
            <LazyRow
              title="Recently Watched"
              items={traktHistory}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'history', mediaType: 'movie', title: 'Recently Watched' }, 'Recently Watched', traktHistory)}
              keyPrefix="trakt-history-"
            />
          )}

          {settings.showTraktRows && traktRecommendations.length > 0 && (
            <LazyRow
              title="Recommended for You"
              items={traktRecommendations}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'recommendations', mediaType: 'movie', title: 'Recommended for You' }, 'Recommended for You', traktRecommendations)}
              keyPrefix="trakt-recommendations-"
            />
          )}

          {settings.showTraktRows && traktPopularShows.length > 0 && (
            <LazyRow
              title="Popular TV Shows on Trakt"
              items={traktPopularShows}
              getImageUri={getRowUri}
              getTitle={getRowTitle}
              onItemPress={onRowPress}
              onBrowsePress={() => openRowBrowse({ type: 'trakt', kind: 'trending', mediaType: 'tv', title: 'Popular TV Shows on Trakt' }, 'Popular TV Shows on Trakt', traktPopularShows)}
              keyPrefix="trakt-popular-shows-"
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
            libraryTitle: library.title,
          });
        }}
      />

      {/* Custom refresh indicator above TopAppBar */}
      {refreshing && (
        <View style={{ position: 'absolute', top: expandedPadding + insets.top + 10, left: 0, right: 0, alignItems: 'center', zIndex: 50 }}>
          <View style={{ backgroundColor: 'rgba(0,0,0,0.7)', paddingHorizontal: 16, paddingVertical: 8, borderRadius: 20, flexDirection: 'row', alignItems: 'center' }}>
            <ActivityIndicator color="#fff" size="small" />
            <Text style={{ color: '#fff', marginLeft: 8, fontSize: 13 }}>Refreshing...</Text>
          </View>
        </View>
      )}
    </SafeAreaView>
  );
}

function HeroAppleTV({
  items,
  selectedIndex,
  onSelectIndex,
  onAdd,
  inWatchlist,
  watchlistLoading,
}: {
  items: Array<{ id: string; title: string; image?: string; mediaType?: 'movie' | 'tv'; logo?: string; backdrop?: string }>;
  selectedIndex: number;
  onSelectIndex: (index: number) => void;
  onAdd: () => void;
  inWatchlist: boolean;
  watchlistLoading: boolean;
}) {
  const current = items[selectedIndex];
  const screenW = Dimensions.get('window').width;
  const thumbWidth = Math.min(screenW * 0.28, 140);
  const thumbHeight = Math.round(thumbWidth * 0.56);

  if (!current) return null;

  return (
    <View style={{ paddingHorizontal: 16, marginTop: 8 }}>
      <View
        style={{
          borderRadius: 18,
          overflow: 'hidden',
          backgroundColor: '#111',
          borderWidth: 1,
          borderColor: 'rgba(255,255,255,0.08)',
        }}
      >
        <View style={{ width: '100%', aspectRatio: 16 / 9 }}>
          {(current.backdrop || current.image) ? (
            <FastImage
              source={{
                uri: current.backdrop || current.image,
                priority: FastImage.priority.high,
                cache: FastImage.cacheControl.immutable,
              }}
              style={{ width: '100%', height: '100%' }}
              resizeMode={FastImage.resizeMode.cover}
            />
          ) : null}
        </View>
        <LinearGradient
          colors={['rgba(0,0,0,0.0)', 'rgba(0,0,0,0.65)', 'rgba(0,0,0,0.95)']}
          style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
        />
        <View style={{ position: 'absolute', left: 18, right: 18, bottom: 18 }}>
          {current.logo ? (
            <FastImage
              source={{
                uri: current.logo,
                priority: FastImage.priority.high,
                cache: FastImage.cacheControl.immutable,
              }}
              style={{ width: 200, height: 70, marginBottom: 8 }}
              resizeMode={FastImage.resizeMode.contain}
            />
          ) : (
            <Text style={{ color: '#fff', fontSize: 26, fontWeight: '900', marginBottom: 6 }}>
              {current.title}
            </Text>
          )}
          {current.mediaType ? (
            <Text style={{ color: '#d1d5db', fontSize: 13 }}>
              {current.mediaType === 'movie' ? 'Movie' : 'Series'}
            </Text>
          ) : null}
        </View>
        {/* List button - top right corner */}
        <Pressable
          onPress={onAdd}
          disabled={watchlistLoading}
          style={{
            position: 'absolute',
            top: 12,
            right: 12,
            width: 36,
            height: 36,
            borderRadius: 18,
            backgroundColor: 'rgba(0,0,0,0.5)',
            alignItems: 'center',
            justifyContent: 'center',
            borderWidth: 1,
            borderColor: 'rgba(255,255,255,0.2)',
            opacity: watchlistLoading ? 0.6 : 1,
          }}
        >
          <Ionicons name={inWatchlist ? 'checkmark' : 'add'} size={20} color="#fff" />
        </Pressable>
      </View>
      <View style={{ marginTop: 14 }}>
        <FlatList
          data={items}
          horizontal
          keyExtractor={(item) => item.id}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={{ paddingHorizontal: 2 }}
          renderItem={({ item, index }) => (
            <Pressable
              onPress={() => onSelectIndex(index)}
              style={{
                width: thumbWidth,
                height: thumbHeight,
                borderRadius: 12,
                overflow: 'hidden',
                marginRight: 10,
                borderWidth: index === selectedIndex ? 2 : 1,
                borderColor: index === selectedIndex ? '#fff' : 'rgba(255,255,255,0.2)',
              }}
            >
              {(item.backdrop || item.image) ? (
                <FastImage
                  source={{
                    uri: item.backdrop || item.image,
                    priority: FastImage.priority.normal,
                    cache: FastImage.cacheControl.immutable,
                  }}
                  style={{ width: '100%', height: '100%' }}
                  resizeMode={FastImage.resizeMode.cover}
                />
              ) : null}
            </Pressable>
          )}
        />
      </View>
    </View>
  );
}
