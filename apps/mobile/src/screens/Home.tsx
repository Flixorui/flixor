import React, { useEffect, useState, useRef, useCallback, useMemo } from 'react';
import { View, Text, ActivityIndicator, Animated, FlatList, Pressable, Dimensions, InteractionManager, Platform } from 'react-native';
import PullToRefresh, { usePullToRefresh } from '../components/PullToRefresh';
import GlobalTopAppBar from '../components/GlobalTopAppBar';
import FastImage from '@d11/react-native-fast-image';
import { LinearGradient } from 'expo-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import HomeRows from '../components/home/HomeRows';
import { HomeViewport } from '../components/home/homeViewport';
import { preheatArtwork } from '../components/home/preheat';
import { useContinueWatching } from '../components/home/useContinueWatching';
import { useHeroOverride } from '../components/home/useHeroOverride';
import { useHomeBackgroundRefresh } from '../components/home/useHomeBackgroundRefresh';
import { useStremioCatalogs } from '../components/home/useStremioCatalogs';
import {
  arrangeHomeRows,
  buildHomeRowModels,
  HOME_GENRE_ROWS,
  toBrowseItems,
  toRowDescriptors,
  type HomeRowModel,
} from '../components/home/homeRowModels';
import type { ContinueWatchingMenuAction } from '../components/home/continueWatchingMenu';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { TopBarStore } from '../components/TopBarStore';
import { TOP_BAR_EXPANDED_CONTENT_HEIGHT } from '../components/topBarMetrics';
import HeroCard from '../components/HeroCard';
import HeroCarousel from '../components/HeroCarousel';
import AmbientTint from '../components/home/AmbientTint';
import BrowseModal from '../components/BrowseModal';
import type { CategoryPick } from '../components/CategoriesMenu';
import { useFlixor } from '../core/FlixorContext';
import { useAppSettings } from '../hooks/useAppSettings';
import type { PlexMediaItem, BrowseContext } from '@flixor/core';
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
  fetchLocalWatchlistRow,
  matchTraktEpisodeToPlex,
  refreshContinueWatching,
  fetchCollectionRowsForHome,
  fetchRecentlyAddedPerLibrary,
  getPlexImageUrl,
  getTmdbLogo,
  getTmdbTextlessPoster,
  getTmdbTextlessBackdrop,
  isTextlessArtwork,
  getTmdbOverview,
  getUltraBlurColors,
  getUsername,
  convertPlexItemsToHero,
  RowItem,
  GenreItem,
  PlexUltraBlurColors,
  HeroItem,
  CollectionRowData,
  RecentlyAddedSection,
} from '../core/HomeData';
import {
  toggleWatchlist,
  checkWatchlistStatus,
  WatchlistIds,
  extractTmdbIdFromGuids,
  extractImdbIdFromGuids,
} from '../core/DetailsData';
import { stremioStreamCache } from '../stremio/StremioStreamCache';
import { useTheme } from '../hooks/useTheme';
import { useAppMode } from '../core/AppMode';
import { registerHomeRows } from '../core/HomeRowsStore';
import { localLibrary } from '../core/LocalLibrary';
import { seedTraktResumePoint, type ContinueWatchingEntry } from '../core/TraktContinueWatching';
import { addWatchStateListener } from '../core/WatchState';
import { useHomeCollections } from '../core/UserCollectionsStore';

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

const HERO_AUTO_ROTATE_MS = 8000;
const ROW_REGISTRATION_DELAY_MS = 1500;
const NO_PLEX_CONTINUE = { items: [] as PlexMediaItem[], itemsWithMultipleVersions: new Set<string>() };

type HeroPick = { title: string; image?: string; subtitle?: string; tmdbId?: number; mediaType?: 'movie' | 'tv' };

/** The Plex ratingKey of a hero item, if the title is in the library. */
function heroPlexKey(item: { id?: string; plexRatingKey?: string }): string | null {
  if (item.plexRatingKey) return item.plexRatingKey;
  if (item.id?.startsWith('plex:')) return item.id.replace('plex:', '');
  return null;
}

/**
 * Home with its header inside the screen, so the header slides with Home when Details or
 * Shows / Movies are pushed over it, instead of vanishing and popping back in.
 */
export default function Home(props: HomeProps) {
  return (
    <View style={{ flex: 1 }}>
      <HomeContent {...props} />
      <GlobalTopAppBar screenContext="HomeStack" embedded />
    </View>
  );
}

function HomeContent({ onLogout }: HomeProps) {
  const { flixor, isLoading: flixorLoading, isConnected } = useFlixor();
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, isLoaded: settingsLoaded } = useAppSettings();
  const theme = useTheme();
  const { isStremioOnly } = useAppMode();
  const hasPlex = isConnected && !isStremioOnly;
  const canLoad = isConnected || isStremioOnly;
  const continueWatching = useContinueWatching(settings, isStremioOnly);
  const continueItems = continueWatching.plexItems;
  const applyPlexContinue = continueWatching.applyPlexResult;
  const refreshContinueEntries = continueWatching.refresh;
  const homeCollections = useHomeCollections();
  const catalogs = useStremioCatalogs(settings.stremioPlaybackEnabled && settings.showStremioCatalogRows);
  const viewportRef = useRef<HomeViewport | null>(null);
  viewportRef.current ??= new HomeViewport();
  const viewport = viewportRef.current;
  const [reloadToken, setReloadToken] = useState(0);
  // Initialize loading based on cache - if we have cached hero data, skip loading screen
  const [loading, setLoading] = useState(() => !persistentStore.heroSourceItems);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  const [welcome, setWelcome] = useState<string>('');

  // Plex data
  const [onDeckItems, setOnDeckItems] = useState<PlexMediaItem[]>([]);
  const [recent, setRecent] = useState<PlexMediaItem[]>([]);
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

  // Recently Added per library rows
  const [recentlyAddedSections, setRecentlyAddedSections] = useState<RecentlyAddedSection[]>([]);

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
  const [plexHeroData, setHeroCarouselData] = useState<HeroItem[]>(
    () => persistentStore.heroCarouselData || []
  );
  const recentRowItems = useMemo<RowItem[]>(
    () =>
      recent.map((item) => ({
        id: `plex:${item.ratingKey}`,
        title: item.title || 'Untitled',
        image: getPlexImageUrl(item, 300) || undefined,
        backdrop: item.art ? getPlexImageUrl({ ...item, thumb: item.art } as PlexMediaItem, 600) : undefined,
        rating: item.rating || undefined,
        mediaType: item.type === 'movie' ? ('movie' as const) : ('tv' as const),
      })),
    [recent]
  );
  const rowModels = useMemo(
    () =>
      buildHomeRowModels({
        showCollectionRows: settings.showCollectionRows,
        showRecentlyAddedRows: settings.showRecentlyAddedRows,
        showPlexPopularRow: settings.showPlexPopularRow,
        showTrendingRows: settings.showTrendingRows,
        showPlexGenreRows: settings.showPlexGenreRows,
        showTraktRows: settings.showTraktRows,
        collectionRows,
        recentlyAddedSections,
        userCollections: homeCollections,
        catalogs,
        popularOnPlex: popularOnPlexTmdb,
        trendingNow,
        trendingMovies,
        trendingAll,
        watchlist,
        genres,
        recent: recentRowItems,
        traktTrendMovies,
        traktTrendShows,
        traktWatchlist: traktMyWatchlist,
        traktHistory,
        traktRecommendations,
        traktPopularShows,
      }),
    [
      settings.showCollectionRows,
      settings.showRecentlyAddedRows,
      settings.showPlexPopularRow,
      settings.showTrendingRows,
      settings.showPlexGenreRows,
      settings.showTraktRows,
      collectionRows,
      recentlyAddedSections,
      homeCollections,
      catalogs,
      popularOnPlexTmdb,
      trendingNow,
      trendingMovies,
      trendingAll,
      watchlist,
      genres,
      recentRowItems,
      traktTrendMovies,
      traktTrendShows,
      traktMyWatchlist,
      traktHistory,
      traktRecommendations,
      traktPopularShows,
    ]
  );
  const displayRows = useMemo(
    () =>
      arrangeHomeRows(
        rowModels,
        {
          homeRowHidden: settings.homeRowHidden,
          homeRowTitles: settings.homeRowTitles,
          homeRowOrder: settings.homeRowOrder,
        },
        tab
      ),
    [rowModels, settings.homeRowHidden, settings.homeRowTitles, settings.homeRowOrder, tab]
  );
  const rowModelsRef = useRef<HomeRowModel[]>(rowModels);
  rowModelsRef.current = rowModels;
  const displayRowsRef = useRef(displayRows);
  displayRowsRef.current = displayRows;

  const heroOverride = useHeroOverride(
    settings.homeHeroSource,
    continueWatching.entries,
    rowModels,
    plexHeroData.length > 0 || heroSourceItems.length > 0,
    ITEM_LIMITS.HERO
  );
  const heroCarouselData = heroOverride ?? plexHeroData;
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
      ]).catch((e) => console.log('[Home] Cache clear failed:', e));
    }

    // Reset all row states
    applyPlexContinue(NO_PLEX_CONTINUE);
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
    setRecentlyAddedSections([]);
    setHeroCarouselData([]);

    // Re-trigger data load by incrementing retryCount
    setLoading(true);
    setRetryCount(c => c + 1);
    setReloadToken(c => c + 1);
    refreshContinueEntries({ force: true });
    // `refreshing` stays on until the reload has finished (see the effect below), so the
    // pull-to-refresh spinner shows for the whole reload
  }, [flixor, applyPlexContinue, refreshContinueEntries]);

  const refreshSawLoading = useRef(false);
  useEffect(() => {
    if (!refreshing) return;
    if (loading) {
      refreshSawLoading.current = true;
      return;
    }
    if (refreshSawLoading.current) {
      refreshSawLoading.current = false;
      setRefreshing(false);
    }
  }, [refreshing, loading]);
  // Safety: never spin forever if a reload doesn't report back
  useEffect(() => {
    if (!refreshing) return;
    const t = setTimeout(() => {
      refreshSawLoading.current = false;
      setRefreshing(false);
    }, 20000);
    return () => clearTimeout(t);
  }, [refreshing]);

  // Warm artwork that is about to be on screen
  useEffect(() => {
    preheatArtwork(heroCarouselData.flatMap((item) => [item.backdrop, item.image]));
  }, [heroCarouselData]);

  useEffect(() => {
    preheatArtwork(
      continueWatching.entries.map((entry) =>
        settings.continueWatchingLayout === 'landscape' ? entry.backdrop || entry.image : entry.image || entry.backdrop
      )
    );
  }, [continueWatching.entries, settings.continueWatchingLayout]);

  const y = React.useRef(new Animated.Value(0)).current;
  // Refreshes only when the finger is lifted past the line (never from momentum)
  const pull = usePullToRefresh(y, refreshing, handleRefresh);
  const contentTopInset = insets.top + TOP_BAR_EXPANDED_CONTENT_HEIGHT;
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
    // Netflix-style page with its own billboard and rows; the poster grid is one tap from there
    nav.navigate('LibraryHome', { type: t === 'movies' ? 'movie' : 'show' });
  }, [nav]);

  const closeHandler = useCallback(() => {
    setTab('all');
  }, []);

  const browseHandler = useCallback(() => {
    setBrowseModalVisible(true);
  }, []);

  // Native Categories menu on the Explore pill; "All Categories…" opens the full sheet
  const selectCategory = useCallback((pick: CategoryPick) => {
    if (pick.kind === 'all') {
      setBrowseModalVisible(true);
    } else if (pick.kind === 'physical') {
      nav.navigate('PhysicalCollection');
    } else if (pick.kind === 'genre') {
      nav.navigate('LibraryHome', { type: pick.type === 'movie' ? 'movie' : 'show', genre: pick.genre.title });
    } else {
      nav.navigate('LibraryHome', { type: pick.library.type === 'movie' ? 'movie' : 'show', libraryKey: pick.library.key });
    }
  }, [nav]);

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
        onSelectCategory: selectCategory,
      });

      return () => {
        isFocusedRef.current = false;
      };
    }, [tab, navigateToLibrary, closeHandler, browseHandler, selectCategory, y])
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

  // Navigate to Browse for a row
  const openTop10Item = useCallback((item: { tmdbId?: number; mediaType?: 'movie' | 'tv' }) => {
    if (item.tmdbId && item.mediaType) nav.navigate('Details', { type: 'tmdb', id: String(item.tmdbId), mediaType: item.mediaType });
  }, [nav]);

  const openRowBrowse = useCallback((rowId: string) => {
    const row = displayRowsRef.current.find((candidate) => candidate.model.id === rowId);
    if (!row) return;
    const { model, title } = row;
    if (model.type === 'catalog') {
      nav.navigate('Browse', { context: { type: 'stremioCatalog', catalog: model.catalog }, title });
    } else if (model.type === 'userCollection') {
      nav.navigate('UserCollection', { collectionId: model.collection.id, title });
    } else if (model.type === 'items') {
      nav.navigate('Browse', { context: model.browseContext, title, initialItems: toBrowseItems(model.items) });
    }
  }, [nav]);

  const continueEntriesRef = useRef(continueWatching.entries);
  continueEntriesRef.current = continueWatching.entries;
  const openContinueWatchingBrowse = useCallback(() => {
    const items = continueEntriesRef.current.map((entry) => ({
      id: entry.plexRatingKey
        ? `plex:${entry.plexRatingKey}`
        : `tmdb:${entry.mediaType === 'movie' ? 'movie' : 'tv'}:${entry.tmdbId}`,
      title: entry.title,
      image: entry.image,
      subtitle: entry.mediaType === 'episode' ? `S${entry.seasonNumber || 1}, E${entry.episodeNumber || 1}` : undefined,
      year: entry.mediaType === 'movie' ? entry.year : undefined,
    }));
    nav.navigate('Browse', { context: { type: 'static' } as BrowseContext, title: 'Continue Watching', initialItems: items });
  }, [nav]);

  // Main data loading effect - Progressive loading pattern (like NuvioStreaming)
  // Shows UI as soon as first content is ready instead of waiting for everything
  useEffect(() => {
    if (flixorLoading || !canLoad) return;

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
        const continuePromise = hasPlex ? fetchContinueWatching() : Promise.resolve(NO_PLEX_CONTINUE);
        const onDeckPromise = hasPlex ? fetchOnDeck() : Promise.resolve<PlexMediaItem[]>([]);
        const recentPromise = hasPlex ? fetchRecentlyAdded() : Promise.resolve<PlexMediaItem[]>([]);
        const trendingTVPromise = fetchTmdbTrendingTVWeek();
        const watchlistPromise = hasPlex ? fetchPlexWatchlist() : fetchLocalWatchlistRow();
        const trendingMoviesPromise = fetchTmdbTrendingMoviesWeek();
        const trendingAllPromise = fetchTmdbTrendingAllWeek();

        // Exit loading as soon as Plex hero content (Continue Watching / On Deck / Recent) is ready
        // Priority: Continue Watching → On Deck → Recently Added (matches macOS behavior)
        continuePromise.then(async (continueResult) => {
          InteractionManager.runAfterInteractions(async () => {
            const continueData = continueResult?.items || [];
            console.log('[Home] Setting continueItems:', continueData.length);
            applyPlexContinue(continueResult || NO_PLEX_CONTINUE);

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
          });
        }).catch((err) => {
          console.log('[Home] continuePromise error:', err);
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
        // Load genres progressively - update state as each completes (deferred)
        // Only fetch if genre rows are enabled in settings
        if (hasPlex && settings.showPlexGenreRows) {
          HOME_GENRE_ROWS.forEach(async (gd) => {
            try {
              const items = await fetchPlexGenreRow(gd.type, gd.label);
              InteractionManager.runAfterInteractions(() => {
                setGenres(prev => ({ ...prev, [gd.key]: items }));
              });
            } catch {}
          });
        }

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
        if (hasPlex && settings.showCollectionRows) {
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

        // Recently Added per library rows - load in background (deferred)
        if (hasPlex && settings.showRecentlyAddedRows) {
          fetchRecentlyAddedPerLibrary(
            settings.groupRecentlyAddedEpisodes,
            settings.enabledLibraryKeys
          ).then((sections) => {
            InteractionManager.runAfterInteractions(() => {
              setRecentlyAddedSections(sections);
            });
          }).catch(() => setRecentlyAddedSections([]));
        }

        const durationMs = Date.now() - loadStart;
        console.log(`[Home][perf] all fetches dispatched in ${durationMs}ms`);
      } catch (err: any) {
        console.error('[Home] Fatal error loading data:', err);
        const errorMsg = err?.message || 'Failed to load';
        setError(errorMsg);

        const currentRetry = retryCount + 1;
        setRetryCount(currentRetry);

        // Stremio-only has no account to sign out of, and a retry can't fix that.
        if (currentRetry >= 3 && !isStremioOnly) {
          console.log('[Home] Max retries exceeded, logging out user');
          setTimeout(async () => {
            await onLogout();
          }, 2000);
        } else {
          console.log('[Home] Retry count:', currentRetry);
        }
      }
    })();
  }, [flixorLoading, canLoad, hasPlex, isStremioOnly, retryCount]);

  // Keeps Continue Watching and Recently Added fresh without a full reload
  const settingsRef = useRef(settings);
  settingsRef.current = settings;
  const refreshDynamicRows = useCallback(async () => {
    const current = settingsRef.current;
    const tasks: Promise<unknown>[] = [];
    if (current.showContinueWatchingRow) {
      tasks.push(refreshContinueEntries());
      if (hasPlex) tasks.push(refreshContinueWatching().then(applyPlexContinue));
    }
    if (hasPlex && current.showRecentlyAddedRows) {
      tasks.push(
        fetchRecentlyAddedPerLibrary(current.groupRecentlyAddedEpisodes, current.enabledLibraryKeys).then((sections) => {
          // The fetcher returns nothing on failure, which shouldn't empty the rows.
          if (sections.length === 0) return;
          const idsOf = (list: RecentlyAddedSection[]) =>
            list.map((section) => `${section.id}:${section.items.map((item) => item.id).join(',')}`).join('|');
          setRecentlyAddedSections((prev) => (idsOf(prev) === idsOf(sections) ? prev : sections));
        })
      );
    }
    await Promise.allSettled(tasks);
  }, [hasPlex, applyPlexContinue, refreshContinueEntries]);

  const invalidateDynamicRows = useHomeBackgroundRefresh(!loading && canLoad, refreshDynamicRows);

  // Watched state or local progress changed somewhere else in the app
  useEffect(() => {
    const removeWatchState = addWatchStateListener(invalidateDynamicRows);
    const removeLocal = localLibrary.addListener((change) => {
      if (change === 'history') invalidateDynamicRows();
    });
    return () => {
      removeWatchState();
      removeLocal();
    };
  }, [invalidateDynamicRows]);

  // Records the rows for Rows Settings once loading has settled
  useEffect(() => {
    if (!settingsLoaded || loading) return;
    const timer = setTimeout(() => {
      registerHomeRows(toRowDescriptors(rowModelsRef.current));
    }, ROW_REGISTRATION_DELAY_MS);
    return () => clearTimeout(timer);
  }, [rowModels, settingsLoaded, loading]);

  // The Carousel layout rotates itself; Apple TV is driven by its selected index
  useEffect(() => {
    if (!settings.heroAutoRotate || settings.heroLayout !== 'appletv' || heroCarouselData.length < 2) return;
    const timer = setInterval(() => {
      if (isFocusedRef.current) setAppleTvIndex((index) => (index + 1) % heroCarouselData.length);
    }, HERO_AUTO_ROTATE_MS);
    return () => clearInterval(timer);
  }, [settings.heroAutoRotate, settings.heroLayout, heroCarouselData.length]);

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
    if (plexHeroData.length > 0 || heroSourceItems.length === 0) return;

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
  }, [heroSourceItems, plexHeroData.length]);

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

  const onContinuePress = useCallback(async (it: any) => {
    const ratingKey = String(it.ratingKey || it.guid || '');
    if (settings.useCachedStreams) {
      const guids = it.Guid || [];
      const imdbId = extractImdbIdFromGuids(guids) || undefined;
      const tmdbId = extractTmdbIdFromGuids(guids) || undefined;
      const baseId = imdbId || (tmdbId ? `tmdb:${tmdbId}` : undefined);

      if (baseId) {
        const contentKey =
          it.type === 'episode'
            ? `series:${baseId}:${it.parentIndex || 1}:${it.index || 1}`
            : `movie:${baseId}`;
        const cachedSource = await stremioStreamCache.get(contentKey);
        if (cachedSource) {
          nav.navigate('Player', {
            type: 'stream',
            provider: 'stremio',
            uri: cachedSource.uri,
            headers: cachedSource.headers,
            title: cachedSource.title,
            mediaType: cachedSource.mediaType,
            contentKey: cachedSource.contentKey,
            imdbId: cachedSource.imdbId,
            tmdbId: cachedSource.tmdbId,
            seasonNumber: cachedSource.seasonNumber,
            episodeNumber: cachedSource.episodeNumber,
            episodeTitle: cachedSource.episodeTitle,
            backdrop: cachedSource.backdrop,
            streamLabel: cachedSource.streamLabel,
            streamAddonId: cachedSource.addonId,
            streamAddonName: cachedSource.addonName,
            availableStreams: cachedSource.availableStreams,
            externalSubtitles: cachedSource.externalSubtitles,
            stremioIdentity: cachedSource.stremioIdentity,
          });
          return;
        }
      }

      nav.navigate('Player', { type: 'plex', ratingKey });
    } else if (settings.openMetadataScreenWhenCacheDisabled) {
      nav.navigate('Details', { type: 'plex', ratingKey });
    } else {
      nav.navigate('Player', { type: 'plex', ratingKey });
    }
  }, [nav, settings.useCachedStreams, settings.openMetadataScreenWhenCacheDisabled]);

  /** Opens an addon stream saved for this entry, if caching is on and one is still valid. */
  const playCachedStream = useCallback(async (entry: ContinueWatchingEntry): Promise<boolean> => {
    if (!settings.useCachedStreams) return false;
    const baseId = entry.imdbId || (entry.tmdbId ? `tmdb:${entry.tmdbId}` : undefined);
    const contentKey =
      entry.contentKey ||
      (baseId &&
        (entry.mediaType === 'episode'
          ? `series:${baseId}:${entry.seasonNumber || 1}:${entry.episodeNumber || 1}`
          : `movie:${baseId}`));
    if (!contentKey) return false;
    const cached = await stremioStreamCache.get(contentKey);
    if (!cached) return false;
    nav.navigate('Player', {
      type: 'stream',
      provider: 'stremio',
      uri: cached.uri,
      headers: cached.headers,
      title: cached.title,
      mediaType: cached.mediaType,
      contentKey: cached.contentKey,
      imdbId: cached.imdbId,
      tmdbId: cached.tmdbId,
      seasonNumber: cached.seasonNumber,
      episodeNumber: cached.episodeNumber,
      episodeTitle: cached.episodeTitle,
      backdrop: cached.backdrop,
      streamLabel: cached.streamLabel,
      streamAddonId: cached.addonId,
      streamAddonName: cached.addonName,
      availableStreams: cached.availableStreams,
      externalSubtitles: cached.externalSubtitles,
      stremioIdentity: cached.stremioIdentity,
    });
    return true;
  }, [nav, settings.useCachedStreams]);

  const openContinueDetails = useCallback(async (entry: ContinueWatchingEntry) => {
    if (entry.plexRatingKey) {
      return nav.navigate('Details', { type: 'plex', ratingKey: entry.plexRatingKey });
    }
    if (entry.tmdbId == null) return;
    const isEpisode = entry.mediaType === 'episode' && !!entry.seasonNumber;
    if (hasPlex && isEpisode) {
      // Prefer the library copy so Plex playback and metadata are available.
      const ratingKey = await matchTraktEpisodeToPlex(entry.tmdbId, entry.title, entry.seasonNumber!, entry.episodeNumber || 1).catch(() => null);
      if (ratingKey) return nav.navigate('Details', { type: 'plex', ratingKey });
    }
    nav.navigate('Details', {
      type: 'tmdb',
      mediaType: entry.mediaType === 'movie' ? 'movie' : 'tv',
      id: String(entry.tmdbId),
      ...(isEpisode ? { initialSeason: entry.seasonNumber, initialEpisode: entry.episodeNumber } : null),
    });
  }, [nav, hasPlex]);

  const onContinueEntryPress = useCallback(async (entry: ContinueWatchingEntry) => {
    if (entry.plex) return onContinuePress(entry.plex);
    await seedTraktResumePoint(entry).catch((e) => console.log('[Home] Could not save Trakt resume point:', e));
    if (await playCachedStream(entry)) return;
    await openContinueDetails(entry);
  }, [onContinuePress, playCachedStream, openContinueDetails]);

  const performContinueAction = continueWatching.performAction;
  const onContinueAction = useCallback(async (action: ContinueWatchingMenuAction, entry: ContinueWatchingEntry) => {
    if (action === 'info') {
      openContinueDetails(entry);
      return;
    }
    const result = await performContinueAction(action, entry);
    if (action === 'startOver' && result && (result.isSuccess || result.isPartialSuccess)) {
      onContinueEntryPress({ ...entry, positionMs: undefined, progress: 0 });
    }
  }, [openContinueDetails, performContinueAction, onContinueEntryPress]);

  // Show loading while FlixorCore is initializing or not connected
  if (flixorLoading || !canLoad) {
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
  // A pull refresh stays on the page (skeleton rows and the glass spinner), not the loading screen
  if ((loading && !hasContentToShow && !refreshing) || error) {
    return (
      <View style={{ flex: 1, backgroundColor: '#1b0a10', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
        {error ? (
          <>
            <Text style={{ color: '#fff', fontSize: 18, marginBottom: 10, textAlign: 'center' }}>
              Unable to load data
            </Text>
            <Text style={{ color: '#999', fontSize: 14, marginBottom: 20, textAlign: 'center' }}>{error}</Text>
            <Text style={{ color: '#999', fontSize: 14, marginBottom: 20, textAlign: 'center' }}>Retry {retryCount}/3</Text>
            {retryCount >= 3 && !isStremioOnly ? (
              <Text style={{ color: theme.accent, fontSize: 14, textAlign: 'center' }}>
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

  const canShowHero = settings.showHeroSection && (heroPick || heroCarouselItems.length > 0);


  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: '#0e0e10' }} edges={['left', 'right']}>
      {/* Background takes the hero's colour and cross-fades as the hero changes */}
      <AmbientTint color={heroColors?.topLeft || heroColors?.topRight || '2b3a3f'} />

      <PullToRefresh {...pull.indicatorProps} top={contentTopInset + 6} />

      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 80 + insets.bottom, paddingTop: contentTopInset }}
        {...pull.dragHandlers}
        scrollEventThrottle={16}
        onScroll={(e: any) => {
          const currentY = e.nativeEvent.contentOffset.y;
          y.setValue(currentY);
          viewport.setOffset(currentY);
        }}
      >
        {canShowHero ? (
          settings.heroLayout === 'carousel' ? (
            <HeroCarousel
              items={heroCarouselData}
              // Plex movies play straight away; shows and titles outside the library open
              // Details (which knows the next episode or the sources)
              isPlayable={(item) => heroPlexKey(item) !== null && item.mediaType === 'movie'}
              onPlay={(item) => {
                const ratingKey = heroPlexKey(item);
                if (ratingKey && item.mediaType === 'movie') {
                  nav.navigate('Player', { type: 'plex', ratingKey });
                } else if (ratingKey) {
                  nav.navigate('Details', { type: 'plex', ratingKey });
                } else {
                  const ids = getRowWatchlistIds(item);
                  if (ids) nav.navigate('Details', { type: 'tmdb', id: String(ids.tmdbId), mediaType: ids.mediaType });
                }
              }}
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
              autoRotate={settings.heroAutoRotate}
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

        <HomeRows
          rows={displayRows}
          layout={settings.rowLayout}
          viewport={viewport}
          reloadToken={reloadToken}
          showContinueWatching={settings.showContinueWatchingRow}
          continueLayout={settings.continueWatchingLayout}
          continueEntries={continueWatching.entries}
          blurNextUp={settings.continueWatchingBlurNextUp}
          onContinuePress={onContinueEntryPress}
          onContinueAction={onContinueAction}
          onContinueBrowse={openContinueWatchingBrowse}
          onItemPress={onRowPress}
          onBrowseRow={openRowBrowse}
          onTop10Press={openTop10Item}
        />
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
          {/* The logo only over artwork without its own title (else the title shows twice) */}
          {current.logo && (!(current.backdrop || current.image) || isTextlessArtwork(current.backdrop || current.image)) ? (
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
