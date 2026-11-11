import React, { useEffect, useState, useRef, useCallback, useMemo } from 'react';
import { View, Text, ActivityIndicator, ScrollView, FlatList, Pressable, StyleSheet, Linking, Alert, Image, useWindowDimensions, Platform } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedScrollHandler,
  useAnimatedStyle,
  interpolate,
  Extrapolation,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import TrailersRow from '../components/TrailersRow';
import { Ionicons } from '@expo/vector-icons';
import Feather from '@expo/vector-icons/Feather';
import ConditionalBlurView from '../components/ConditionalBlurView';
import BadgePill from '../components/BadgePill';
import { TechBadge, ContentRatingBadge } from '../components/badges';
import RequestButton from '../components/RequestButton';
import { DownloadButton } from '../components/downloads';
import VersionPicker, { MediaVersion, parseVersionDetails } from '../components/VersionPicker';
import { useNavigation, useFocusEffect, useIsFocused } from '@react-navigation/native';
import { TopBarStore } from '../components/TopBarStore';
import { useFlixor } from '../core/FlixorContext';
import { useAppSettings } from '../hooks/useAppSettings';
import { useMDBListRatings } from '../hooks/useMDBListRatings';
import {
  fetchPlexMetadata,
  fetchPlexSeasons,
  fetchPlexSeasonEpisodes,
  fetchTmdbDetails,
  fetchTmdbLogo,
  fetchTmdbCredits,
  fetchTmdbSeasonsList,
  fetchTmdbSeasonEpisodes,
  fetchTmdbEpisodeStills,
  fetchTmdbMovieCollection,
  TMDBEpisodeData,
  fetchTmdbRecommendations,
  fetchTmdbSimilar,
  fetchTmdbTrailers,
  getYouTubeUrl,
  mapTmdbToPlex,
  getPlexImageUrl,
  getTmdbImageUrl,
  getTmdbProfileUrl,
  extractTmdbIdFromGuids,
  fetchTmdbEpisodeDetails,
  type EpisodeEnrichment,
  extractImdbIdFromGuids,
  toggleWatchlist,
  checkWatchlistStatus,
  getNextUpEpisode,
  isPlexGuid,
  lookupWatchlistByGuid,
  WatchlistIds,
  RowItem,
  TrailerInfo,
  NextUpEpisode,
} from '../core/DetailsData';
import { appLogger } from '../core/AppLogger';

import FastImage from '@d11/react-native-fast-image';
import { FilterImage } from 'react-native-svg/filter-image';
import {
  resolveStremioIdentityFromPlexMetadata,
  resolveStremioIdentityFromTmdb,
} from '../stremio/StremioContentResolver';
import { useAppMode, isStremioOnlyMode } from '../core/AppMode';
import { useTheme } from '../hooks/useTheme';
import { withAlpha } from '../core/theme';
import { orderedEnabledSections } from '../core/DetailsSectionsStore';
import type { DetailsSectionKey } from '../core/SettingsData';
import type { WatchStateTarget } from '../core/WatchState';
import DetailsBackdrop from '../components/details/DetailsBackdrop';
import { useDetailsBackdropTint } from '../components/details/backdropTint';
import DetailsComments from '../components/details/DetailsComments';
import DetailsEpisodesSection from '../components/details/DetailsEpisodesSection';
import Poster from '../components/Poster';
import DetailsCollectionRow from '../components/details/DetailsCollectionRow';
import DetailsSectionHeading, { DetailsSectionStyle } from '../components/details/DetailsSectionHeading';
import DetailsSectionTabs from '../components/details/DetailsSectionTabs';
import AddToListSheet from '../components/lists/AddToListSheet';
import { isTraktAvailable, type TraktListTitle } from '../core/TraktListsData';
import DetailsWatchActions, { DetailsActionLabel, type DetailsSeasonOption } from '../components/details/DetailsWatchActions';
import DetailsActionSheet, { type DetailsAction } from '../components/details/DetailsActionSheet';
import DetailsCastRow, { type DetailsCastMember, type DetailsCrewMember } from '../components/details/DetailsCastRow';

// Optional iOS liquid glass effect with safe fallback
let GlassViewComp: any = null;
let liquidGlassAvailable = false;
if (Platform.OS === 'ios') {
  try {
    const glass = require('expo-glass-effect');
    GlassViewComp = glass.GlassView;
    liquidGlassAvailable = typeof glass.isLiquidGlassAvailable === 'function'
      ? glass.isLiquidGlassAvailable()
      : false;
  } catch {
    GlassViewComp = null;
    liquidGlassAvailable = false;
  }
}

type DetailsParams = {
  type: 'plex' | 'tmdb';
  ratingKey?: string;
  mediaType?: 'movie' | 'tv';
  id?: string;
  initialSeason?: number; // For navigating to a specific season (e.g., from Trakt Continue Watching)
  initialEpisode?: number; // For navigating to a specific episode
};

type RouteParams = {
  route?: { params?: DetailsParams };
};

export default function Details({ route }: RouteParams) {
  const params: Partial<DetailsParams> = route?.params || {};
  const { isLoading: flixorLoading, isConnected } = useFlixor();
  const { settings } = useAppSettings();
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const { isStremioOnly } = useAppMode();
  const canLoad = isConnected || isStremioOnly;
  const isFocused = useIsFocused();

  // Details screen settings with defaults
  const detailsSettings = {
    showIMDbRating: settings.showIMDbRating ?? true,
    showRottenTomatoesCritic: settings.showRottenTomatoesCritic ?? true,
    showRottenTomatoesAudience: settings.showRottenTomatoesAudience ?? true,
    layout: settings.detailsScreenLayout ?? 'tabbed',
  };
  const isUnifiedLayout = detailsSettings.layout === 'unified';
  const [loading, setLoading] = useState(true);
  const [glassKey, setGlassKey] = useState(0); // Force GlassView re-render on focus
  const [meta, setMeta] = useState<any>(null);
  const [episodes, setEpisodes] = useState<any[]>([]);
  const [seasons, setSeasons] = useState<any[]>([]);
  const [seasonKey, setSeasonKey] = useState<string | null>(null);
  const [seasonSource, setSeasonSource] = useState<'plex'|'tmdb'|null>(null);
  const [tab, setTab] = useState<DetailsSectionKey>('suggested');
  const [tmdbCast, setTmdbCast] = useState<DetailsCastMember[]>([]);
  const [tmdbCrew, setTmdbCrew] = useState<DetailsCrewMember[]>([]);
  // Episode pages: guest stars, air date, rating and credits from TMDB
  const [episodeExtra, setEpisodeExtra] = useState<EpisodeEnrichment | null>(null);
  const [matchedPlex, setMatchedPlex] = useState<boolean>(false);
  const [mappedRk, setMappedRk] = useState<string | null>(null);
  const [noLocalSource, setNoLocalSource] = useState<boolean>(false);
  const [episodesLoading, setEpisodesLoading] = useState<boolean>(false);
  const [tmdbEpisodeData, setTmdbEpisodeData] = useState<Map<number, TMDBEpisodeData>>(new Map());
  const [nextUp, setNextUp] = useState<NextUpEpisode | null>(null);
  const [parentShowMeta, setParentShowMeta] = useState<any>(null);
  const [inWatchlist, setInWatchlist] = useState(false);
  const [watchlistLoading, setWatchlistLoading] = useState(false);
  const [watchlistIds, setWatchlistIds] = useState<WatchlistIds | null>(null);
  const [trailers, setTrailers] = useState<TrailerInfo[]>([]);
  const [productionInfo, setProductionInfo] = useState<Array<{id: number; name: string; logo?: string}>>([]);
  const [tmdbExtraInfo, setTmdbExtraInfo] = useState<{
    runtime?: number;
    status?: string;
    tagline?: string;
    budget?: number;
    revenue?: number;
    originalLanguage?: string;
    spokenLanguages?: string[];
    numberOfSeasons?: number;
    numberOfEpisodes?: number;
    creators?: string[];
    releaseDate?: string;
    firstAirDate?: string;
    lastAirDate?: string;
    voteAverage?: number;
    voteCount?: number;
  }>({});
  const [showVersionPicker, setShowVersionPicker] = useState(false);
  const [mediaVersions, setMediaVersions] = useState<MediaVersion[]>([]);
  const [pendingPlayRatingKey, setPendingPlayRatingKey] = useState<string | null>(null);
  const [imdbId, setImdbId] = useState<string | undefined>(undefined);
  const [firstEpisodeMedia, setFirstEpisodeMedia] = useState<any[]>([]); // Technical info from first episode (for TV shows)
  const [addToListTitle, setAddToListTitle] = useState<TraktListTitle | null>(null);
  const [showMoreActions, setShowMoreActions] = useState(false);
  const [collection, setCollection] = useState<{ id: number; name: string; items: RowItem[] } | null>(null);
  const [heroTrailerFinished, setHeroTrailerFinished] = useState(false);
  const [heroTrailerPlaying, setHeroTrailerPlaying] = useState(false);
  const [heroTrailerMuted, setHeroTrailerMuted] = useState(true);
  const scrollRef = useRef<Animated.ScrollView | null>(null);
  const nav: any = useNavigation();
  const { width: screenWidth } = useWindowDimensions();

  // Parallax animation values
  const scrollY = useSharedValue(0);
  const HERO_HEIGHT = useMemo(() => screenWidth * (9 / 16), [screenWidth]); // 16:9 aspect ratio
  const LOGO_PARALLAX_FACTOR = 0.2;
  const HEADER_APPEAR_THRESHOLD = HERO_HEIGHT - 60; // When to start showing sticky header

  // Scroll handler for parallax
  const scrollHandler = useAnimatedScrollHandler({
    onScroll: (event) => {
      scrollY.value = event.contentOffset.y;
    },
  });

  // Animated style for logo parallax (slower for depth effect)
  const logoAnimatedStyle = useAnimatedStyle(() => {
    const translateY = interpolate(
      scrollY.value,
      [0, HERO_HEIGHT],
      [0, HERO_HEIGHT * LOGO_PARALLAX_FACTOR],
      Extrapolation.CLAMP
    );
    const opacity = interpolate(
      scrollY.value,
      [0, HEADER_APPEAR_THRESHOLD * 0.7],
      [1, 0],
      Extrapolation.CLAMP
    );
    return {
      transform: [{ translateY }],
      opacity,
    };
  });

  // Animated style for sticky header
  const stickyHeaderStyle = useAnimatedStyle(() => {
    const opacity = interpolate(
      scrollY.value,
      [HEADER_APPEAR_THRESHOLD - 30, HEADER_APPEAR_THRESHOLD + 20],
      [0, 1],
      Extrapolation.CLAMP
    );
    const translateY = interpolate(
      scrollY.value,
      [HEADER_APPEAR_THRESHOLD - 30, HEADER_APPEAR_THRESHOLD + 20],
      [-20, 0],
      Extrapolation.CLAMP
    );
    return {
      opacity,
      transform: [{ translateY }],
    };
  });

  // MDBList ratings hook - fetches from multiple sources (if enabled)
  const mdblistRating = useMDBListRatings(
    imdbId,
    meta?.type === 'movie' ? 'movie' : 'show'
  );

  const backdropUrl: string | undefined = meta?.backdropUrl
    ? String(meta.backdropUrl)
    : meta?.art || meta?.thumb
      ? getPlexImageUrl(meta.art || meta.thumb, 1080)
      : undefined;
  const { tint, maxTintAlpha } = useDetailsBackdropTint(backdropUrl, theme);

  useEffect(() => {
    setHeroTrailerMuted(settings.detailsHeroTrailerStartsMuted);
  }, [settings.detailsHeroTrailerStartsMuted]);

  // Hide TopBar and TabBar when Details screen is focused (including when returning from Player)
  useFocusEffect(
    useCallback(() => {
      TopBarStore.setVisible(false);
      TopBarStore.setTabBarVisible(false);
      // Force GlassView to re-render on focus (fixes iOS liquid glass not showing after navigation)
      setGlassKey(k => k + 1);
      // No cleanup - let underlying screens (Home/Browse) manage their own TopBar state
    }, [])
  );

  useEffect(() => {
    if (flixorLoading || !canLoad) return;

    (async () => {
      console.log('[Details] useEffect starting...');

      // Handle Plex type (direct ratingKey)
      if (params.type === 'plex' && params.ratingKey) {
        // Check if ratingKey is a GUID (non-numeric) - these are watchlist items not in library
        if (isPlexGuid(params.ratingKey)) {
          console.log('[Details] Detected GUID ratingKey, looking up in watchlist:', params.ratingKey);
          const watchlistInfo = await lookupWatchlistByGuid(params.ratingKey);
          if (watchlistInfo) {
            console.log('[Details] Found watchlist item, redirecting to TMDB:', watchlistInfo.tmdbId);
            // Redirect to TMDB flow by updating params (simulate TMDB navigation)
            params.type = 'tmdb';
            params.id = String(watchlistInfo.tmdbId);
            params.mediaType = watchlistInfo.mediaType;
            // Fall through to TMDB handling below
          } else {
            console.log('[Details] Watchlist item not found or no TMDB ID');
            setLoading(false);
            return;
          }
        } else {
          // Normal numeric ratingKey - fetch from Plex library
          try {
            const m = await fetchPlexMetadata(params.ratingKey);
            if (!m) {
              setLoading(false);
              return;
            }
          const next: any = { ...m };
          setMatchedPlex(true);
          setMappedRk(String(params.ratingKey));

          // Try to fetch TMDB logo and credits for person modal
          const tmdbId = extractTmdbIdFromGuids(m?.Guid || []);
          if (tmdbId) {
            const mediaType = m?.type === 'movie' ? 'movie' : 'tv';
            const logo = await fetchTmdbLogo(mediaType, Number(tmdbId));
            if (logo) next.logoUrl = logo;

            // Fetch TMDB credits for Plex content (cast characters and person ids)
            try {
              const credits = await fetchTmdbCredits(mediaType, Number(tmdbId));
              setTmdbCast(credits.cast.map((c: any) => ({ id: c.id, name: c.name, character: c.character, profile_path: c.profile_path })));
              setTmdbCrew(credits.crew.map((c: any) => ({ id: c.id, name: c.name, job: c.job, department: c.department, profile_path: c.profile_path })));
            } catch (e) {
              console.log('[Details] Error fetching TMDB credits for Plex content:', e);
            }

            // Fetch production companies (movies) or networks (TV) and extra TMDB info
            try {
              const tmdbDet = await fetchTmdbDetails(mediaType, Number(tmdbId));
              const prodData = mediaType === 'movie' ? tmdbDet?.production_companies : tmdbDet?.networks;
              if (Array.isArray(prodData)) {
                setProductionInfo(prodData.map((p: any) => ({
                  id: p.id,
                  name: p.name,
                  logo: p.logo_path ? getTmdbImageUrl(p.logo_path, 'w185') : undefined,
                })).filter((p: any) => p.name));
              }
              // Extract extra TMDB info
              setTmdbExtraInfo({
                runtime: tmdbDet?.runtime || tmdbDet?.episode_run_time?.[0],
                status: tmdbDet?.status,
                tagline: tmdbDet?.tagline,
                budget: tmdbDet?.budget,
                revenue: tmdbDet?.revenue,
                originalLanguage: tmdbDet?.original_language,
                spokenLanguages: tmdbDet?.spoken_languages?.map((l: any) => l.english_name || l.name),
                numberOfSeasons: tmdbDet?.number_of_seasons,
                numberOfEpisodes: tmdbDet?.number_of_episodes,
                creators: tmdbDet?.created_by?.map((c: any) => c.name),
                releaseDate: tmdbDet?.release_date,
                firstAirDate: tmdbDet?.first_air_date,
                lastAirDate: tmdbDet?.last_air_date,
                voteAverage: tmdbDet?.vote_average,
                voteCount: tmdbDet?.vote_count,
              });
            } catch (e) {
              console.log('[Details] Error fetching production info:', e);
            }
          }

          setMeta(next);
          setTab(next?.type === 'show' ? 'episodes' : 'suggested');

          // If this is an episode, fetch the parent show metadata for suggestions
          if (next?.type === 'episode' && next?.grandparentRatingKey) {
            try {
              const showMeta = await fetchPlexMetadata(String(next.grandparentRatingKey));
              if (showMeta) {
                setParentShowMeta(showMeta);
                console.log('[Details] Fetched parent show for episode:', showMeta.title);
              }
            } catch (e) {
              console.log('[Details] Error fetching parent show metadata:', e);
            }
          }

          if (next?.type === 'show') {
            const seas = await fetchPlexSeasons(params.ratingKey);
            setSeasons(seas);
            setSeasonSource('plex');
            if (seas[0]?.ratingKey) {
              setSeasonKey(String(seas[0].ratingKey));
              const eps = await fetchPlexSeasonEpisodes(String(seas[0].ratingKey));
              setEpisodes(eps);
              // Fetch technical details from first episode (like macOS does)
              if (eps[0]?.ratingKey) {
                try {
                  const firstEpMeta = await fetchPlexMetadata(String(eps[0].ratingKey));
                  if (firstEpMeta?.Media) {
                    setFirstEpisodeMedia(firstEpMeta.Media);
                    console.log('[Details] Fetched technical info from first episode');
                  }
                } catch (e) {
                  console.log('[Details] Error fetching first episode technical info:', e);
                }
              }
            }
            // Fetch next up episode for continue watching
            const nextUpEp = await getNextUpEpisode(params.ratingKey, seas);
            setNextUp(nextUpEp);
          }

          // Setup watchlist IDs and check status
          const tmdbIdStr = extractTmdbIdFromGuids(m?.Guid || []);
          const imdbIdStr = extractImdbIdFromGuids(m?.Guid || []);
          if (imdbIdStr) setImdbId(imdbIdStr);
          const ids: WatchlistIds = {
            tmdbId: tmdbIdStr ? Number(tmdbIdStr) : undefined,
            imdbId: imdbIdStr || undefined,
            plexRatingKey: String(params.ratingKey),
            mediaType: m?.type === 'movie' ? 'movie' : 'tv',
          };
          setWatchlistIds(ids);
          checkWatchlistStatus(ids).then(setInWatchlist);
          } catch (e) {
            console.log('[Details] Plex metadata error:', e);
          }
        } // end else (numeric ratingKey)
      } // end if (params.type === 'plex')

      // Handle TMDB type with Plex mapping fallback
      if (params.type === 'tmdb' && params.id && params.mediaType) {
        try {
          // Get TMDB details first
          const det = await fetchTmdbDetails(params.mediaType, Number(params.id));

          // Try to map TMDB to Plex
          const title = det?.title || det?.name;
          const year = (det?.release_date || det?.first_air_date || '').slice(0, 4);
          const mapped = isStremioOnlyMode()
            ? null
            : await mapTmdbToPlex(params.mediaType, String(params.id), title, year);

          if (mapped?.ratingKey) {
            // Found in Plex - use Plex metadata
            const m = await fetchPlexMetadata(String(mapped.ratingKey));
            const next: any = { ...m };
            setMatchedPlex(true);
            setMappedRk(String(mapped.ratingKey));

            // Get TMDB logo, credits, and production info
            const tmdbId = extractTmdbIdFromGuids(m?.Guid || []) || params.id;
            if (tmdbId) {
              const mediaType = m?.type === 'movie' ? 'movie' : 'tv';
              const logo = await fetchTmdbLogo(mediaType, Number(tmdbId));
              if (logo) next.logoUrl = logo;

              // Fetch TMDB credits for mapped Plex content (cast characters and person ids)
              try {
                const credits = await fetchTmdbCredits(mediaType, Number(tmdbId));
                setTmdbCast(credits.cast.map((c: any) => ({ id: c.id, name: c.name, character: c.character, profile_path: c.profile_path })));
                setTmdbCrew(credits.crew.map((c: any) => ({ id: c.id, name: c.name, job: c.job, department: c.department, profile_path: c.profile_path })));
              } catch (e) {
                console.log('[Details] Error fetching TMDB credits for mapped Plex:', e);
              }

              // Fetch production companies (movies) or networks (TV) and extra TMDB info
              try {
                const tmdbDet = await fetchTmdbDetails(mediaType, Number(tmdbId));
                const prodData = mediaType === 'movie' ? tmdbDet?.production_companies : tmdbDet?.networks;
                if (Array.isArray(prodData)) {
                  setProductionInfo(prodData.map((p: any) => ({
                    id: p.id,
                    name: p.name,
                    logo: p.logo_path ? getTmdbImageUrl(p.logo_path, 'w185') : undefined,
                  })).filter((p: any) => p.name));
                }
                // Extract extra TMDB info
                setTmdbExtraInfo({
                  runtime: tmdbDet?.runtime || tmdbDet?.episode_run_time?.[0],
                  status: tmdbDet?.status,
                  tagline: tmdbDet?.tagline,
                  budget: tmdbDet?.budget,
                  revenue: tmdbDet?.revenue,
                  originalLanguage: tmdbDet?.original_language,
                  spokenLanguages: tmdbDet?.spoken_languages?.map((l: any) => l.english_name || l.name),
                  numberOfSeasons: tmdbDet?.number_of_seasons,
                  numberOfEpisodes: tmdbDet?.number_of_episodes,
                  creators: tmdbDet?.created_by?.map((c: any) => c.name),
                  releaseDate: tmdbDet?.release_date,
                  firstAirDate: tmdbDet?.first_air_date,
                  lastAirDate: tmdbDet?.last_air_date,
                  voteAverage: tmdbDet?.vote_average,
                  voteCount: tmdbDet?.vote_count,
                });
              } catch (e) {
                console.log('[Details] Error fetching production info:', e);
              }
            }

            setMeta(next);
            setTab(next?.type === 'show' ? 'episodes' : 'suggested');

            if (next?.type === 'show') {
              const seas = await fetchPlexSeasons(String(mapped.ratingKey));
              setSeasons(seas);
              setSeasonSource('plex');
              if (seas[0]?.ratingKey) {
                setSeasonKey(String(seas[0].ratingKey));
                const eps = await fetchPlexSeasonEpisodes(String(seas[0].ratingKey));
                setEpisodes(eps);
                // Fetch technical details from first episode (like macOS does)
                if (eps[0]?.ratingKey) {
                  try {
                    const firstEpMeta = await fetchPlexMetadata(String(eps[0].ratingKey));
                    if (firstEpMeta?.Media) {
                      setFirstEpisodeMedia(firstEpMeta.Media);
                      console.log('[Details] Fetched technical info from first episode (TMDB-mapped)');
                    }
                  } catch (e) {
                    console.log('[Details] Error fetching first episode technical info:', e);
                  }
                }
              }
              // Fetch next up episode for continue watching
              const nextUpEp = await getNextUpEpisode(String(mapped.ratingKey), seas);
              setNextUp(nextUpEp);
            }

            // Setup watchlist IDs and check status for Plex-mapped content
            const tmdbIdPlex = extractTmdbIdFromGuids(m?.Guid || []) || params.id;
            const imdbIdPlex = extractImdbIdFromGuids(m?.Guid || []);
            if (imdbIdPlex) setImdbId(imdbIdPlex);
            const idsMapped: WatchlistIds = {
              tmdbId: tmdbIdPlex ? Number(tmdbIdPlex) : undefined,
              imdbId: imdbIdPlex || undefined,
              plexRatingKey: String(mapped.ratingKey),
              mediaType: params.mediaType,
            };
            setWatchlistIds(idsMapped);
            checkWatchlistStatus(idsMapped).then(setInWatchlist);
          } else {
            // Not in Plex - show TMDB details
            const back = det?.backdrop_path
              ? getTmdbImageUrl(det.backdrop_path, 'w1280')
              : det?.poster_path
                ? getTmdbImageUrl(det.poster_path, 'w780')
                : undefined;
            const genres = Array.isArray(det?.genres)
              ? det.genres.map((g: any) => ({ tag: g.name }))
              : [];

            // Fetch logo for TMDB items not in Plex
            const logo = await fetchTmdbLogo(params.mediaType, Number(params.id));

            setMeta({
              id: Number(params.id),
              tmdbId: Number(params.id),
              title: det?.title || det?.name || 'Title',
              name: det?.name,
              summary: det?.overview,
              year: year,
              type: params.mediaType === 'movie' ? 'movie' : 'show',
              imdb_id: det?.external_ids?.imdb_id || det?.imdb_id,
              external_ids: det?.external_ids,
              release_date: det?.release_date,
              first_air_date: det?.first_air_date,
              poster_path: det?.poster_path,
              backdrop_path: det?.backdrop_path,
              backdropUrl: back,
              Genre: genres,
              logoUrl: logo,
            });
            setNoLocalSource(true);
            setMatchedPlex(false);
            setMappedRk(null);

            // Fetch TMDB credits
            const credits = await fetchTmdbCredits(params.mediaType, Number(params.id));
            setTmdbCast(credits.cast.map((c: any) => ({ id: c.id, name: c.name, character: c.character, profile_path: c.profile_path })));
            setTmdbCrew(credits.crew.map((c: any) => ({ id: c.id, name: c.name, job: c.job, department: c.department, profile_path: c.profile_path })));

            // Extract production companies (movies) or networks (TV) from already-fetched det
            const prodData = params.mediaType === 'movie' ? det?.production_companies : det?.networks;
            if (Array.isArray(prodData)) {
              setProductionInfo(prodData.map((p: any) => ({
                id: p.id,
                name: p.name,
                logo: p.logo_path ? getTmdbImageUrl(p.logo_path, 'w185') : undefined,
              })).filter((p: any) => p.name));
            }

            // Extract extra TMDB info from already-fetched det
            setTmdbExtraInfo({
              runtime: det?.runtime || det?.episode_run_time?.[0],
              status: det?.status,
              tagline: det?.tagline,
              budget: det?.budget,
              revenue: det?.revenue,
              originalLanguage: det?.original_language,
              spokenLanguages: det?.spoken_languages?.map((l: any) => l.english_name || l.name),
              numberOfSeasons: det?.number_of_seasons,
              numberOfEpisodes: det?.number_of_episodes,
              creators: det?.created_by?.map((c: any) => c.name),
              releaseDate: det?.release_date,
              firstAirDate: det?.first_air_date,
              lastAirDate: det?.last_air_date,
              voteAverage: det?.vote_average,
              voteCount: det?.vote_count,
            });

            // For TV shows, populate seasons + episodes
            if (params.mediaType === 'tv') {
              const ss = await fetchTmdbSeasonsList(Number(params.id));
              if (ss.length) {
                setSeasons(
                  ss.map((s) => ({
                    key: s.key,
                    title: s.title,
                    index: s.season_number,
                    posterPath: s.poster_path,
                    episodeCount: s.episode_count,
                  })) as any
                );
                // Use initialSeason if provided (e.g., from Trakt Continue Watching), otherwise default to first season
                const targetSeasonKey = params.initialSeason
                  ? ss.find((s) => Number(s.key) === params.initialSeason)?.key || ss[0].key
                  : ss[0].key;
                setSeasonKey(targetSeasonKey);
                const eps = await fetchTmdbSeasonEpisodes(Number(params.id), Number(targetSeasonKey));
                setEpisodes(eps);
                setSeasonSource('tmdb');
              }
            }
            setTab('suggested');

            // Setup watchlist IDs for TMDB-only content (no Plex ratingKey)
            // Get external IDs from TMDB for better watchlist matching
            let imdbIdTmdb: string | undefined;
            try {
              const details = params.mediaType === 'movie'
                ? await (await import('../core/DetailsData')).fetchTmdbDetails('movie', Number(params.id))
                : await (await import('../core/DetailsData')).fetchTmdbDetails('tv', Number(params.id));
              imdbIdTmdb = details?.external_ids?.imdb_id || details?.imdb_id;
              if (imdbIdTmdb) setImdbId(imdbIdTmdb);
            } catch {}

            const idsTmdb: WatchlistIds = {
              tmdbId: Number(params.id),
              imdbId: imdbIdTmdb,
              plexRatingKey: undefined,
              mediaType: params.mediaType,
              title: det?.title || det?.name,
              posterUrl: det?.poster_path ? getTmdbImageUrl(det.poster_path, 'w342') : undefined,
              backdropUrl: back,
              year: Number(year) || undefined,
            };
            setWatchlistIds(idsTmdb);
            checkWatchlistStatus(idsTmdb).then(setInWatchlist);
          }
        } catch {}
      }
      setLoading(false);
    })();
  }, []);

  // Fetch trailers when we have metadata with TMDB ID
  useEffect(() => {
    if (!meta) return;

    const fetchTrailers = async () => {
      try {
        // Determine TMDB ID and media type
        let tmdbId: number | undefined;
        let mediaType: 'movie' | 'tv' = 'movie';

        // Try to get TMDB ID from Plex GUIDs first
        if (meta?.Guid) {
          const id = extractTmdbIdFromGuids(meta.Guid);
          if (id) tmdbId = Number(id);
        }

        // If from TMDB route params
        if (!tmdbId && params.type === 'tmdb' && params.id) {
          tmdbId = Number(params.id);
        }

        // Determine media type
        if (meta?.type === 'show' || params.mediaType === 'tv') {
          mediaType = 'tv';
        }

        if (tmdbId) {
          console.log('[Details] Fetching trailers for TMDB ID:', tmdbId, 'type:', mediaType);
          const trailersResult = await fetchTmdbTrailers(mediaType, tmdbId);
          setTrailers(trailersResult);
          console.log('[Details] Found', trailersResult.length, 'trailers');
        }
      } catch (e) {
        console.log('[Details] Error fetching trailers:', e);
      }
    };

    fetchTrailers();
  }, [meta, params.type, params.id, params.mediaType]);

  // Fetch TMDB episode data for Plex mode (stills, air_date, vote_average)
  useEffect(() => {
    if (seasonSource !== 'plex' || !seasonKey || !meta?.type || meta.type !== 'show') {
      setTmdbEpisodeData(new Map());
      return;
    }

    const fetchEpisodeData = async () => {
      try {
        // Get TMDB ID from Plex GUIDs
        let tmdbId: number | undefined;
        if (meta?.Guid) {
          const id = extractTmdbIdFromGuids(meta.Guid);
          if (id) tmdbId = Number(id);
        }

        if (!tmdbId) {
          setTmdbEpisodeData(new Map());
          return;
        }

        // Find the season number from the seasonKey (which is the ratingKey for Plex)
        const currentSeason = seasons.find((s: any) => String(s.ratingKey || s.key) === seasonKey);
        const seasonNumber = currentSeason?.index || 1;

        console.log('[Details] Fetching TMDB episode data for season', seasonNumber, 'TMDB ID:', tmdbId);
        const epData = await fetchTmdbEpisodeStills(tmdbId, seasonNumber);
        console.log('[Details] Fetched', epData.size, 'TMDB episode entries');
        setTmdbEpisodeData(epData);
      } catch (e) {
        console.log('[Details] Error fetching TMDB episode data:', e);
        setTmdbEpisodeData(new Map());
      }
    };

    fetchEpisodeData();
  }, [seasonSource, seasonKey, meta, seasons]);

  // Helper to handle playback with version checking
  const handlePlayWithVersionCheck = async (ratingKey: string) => {
    try {
      // Fetch metadata for this item to check for multiple versions
      const itemMeta = await fetchPlexMetadata(ratingKey);
      const mediaArray = itemMeta?.Media || [];

      if (mediaArray.length > 1) {
        // Multiple versions - show picker
        const versions = mediaArray.map((m: any, idx: number) => parseVersionDetails(m, idx));
        setMediaVersions(versions);
        setPendingPlayRatingKey(ratingKey);
        setShowVersionPicker(true);
        console.log('[Details] Multiple versions detected for episode:', versions.length);
      } else {
        // Single version - play directly
        console.log('[Details] Playing ratingKey:', ratingKey);
        nav.navigate('Player', { type: 'plex', ratingKey });
      }
    } catch (e) {
      // On error, just play directly
      console.log('[Details] Error checking versions, playing directly:', e);
      nav.navigate('Player', { type: 'plex', ratingKey });
    }
  };

  // Handler for episode playback from EpisodeList
  const handlePlayEpisode = (episode: any) => {
    if (episode.ratingKey) {
      handlePlayWithVersionCheck(String(episode.ratingKey));
    }
  };

  const openStremioSources = useCallback(
    async (input: {
      mode: 'plex' | 'tmdb';
      metadata?: any;
      tmdbMediaType?: 'movie' | 'tv';
      tmdbId?: number;
      seasonNumber?: number;
      episodeNumber?: number;
      episodeTitle?: string;
      titleOverride?: string;
      backdropOverride?: string;
    }) => {
      try {
        appLogger.info('[Stremio] CTA tapped', {
          mode: input.mode,
          tmdbId: input.tmdbId,
          plexRatingKey: input.metadata?.ratingKey,
          seasonNumber: input.seasonNumber,
          episodeNumber: input.episodeNumber,
        });
        let result;
        if (input.mode === 'plex' && input.metadata) {
          result = await resolveStremioIdentityFromPlexMetadata(input.metadata, {
            seasonNumber: input.seasonNumber,
            episodeNumber: input.episodeNumber,
          });
        } else if (input.mode === 'tmdb' && input.tmdbMediaType && input.tmdbId) {
          result = await resolveStremioIdentityFromTmdb(input.tmdbMediaType, input.tmdbId, {
            seasonNumber: input.seasonNumber,
            episodeNumber: input.episodeNumber,
            tmdbDetails: meta,
          });
        } else {
          result = { error: 'unresolved' as const };
        }

        if (!result.identity) {
          appLogger.warn('[Stremio] ID resolution failed', {
            mode: input.mode,
            error: result.error,
            tmdbId: input.tmdbId,
            plexRatingKey: input.metadata?.ratingKey,
          });
          if (result.error === 'no_stream_addons') {
            Alert.alert(
              'No Stremio Addons',
              'No stream-capable Stremio addons are installed for this profile.',
              [
                { text: 'Cancel', style: 'cancel' },
                {
                  text: 'Open Settings',
                  onPress: () => {
                    const parentNav = nav.getParent?.();
                    if (parentNav) {
                      parentNav.navigate('SettingsTab', { screen: 'StremioSettings' });
                    }
                  },
                },
              ]
            );
            return;
          }

          Alert.alert('Stremio Unavailable', 'No compatible Stremio ID could be resolved for this title.');
          return;
        }

        appLogger.info('[Stremio] ID resolved', {
          requestId: result.identity.requestId,
          baseId: result.identity.baseId,
          source: result.identity.source,
        });
        nav.navigate('StremioSources', {
          identity: result.identity,
          title: input.titleOverride || meta?.title || meta?.grandparentTitle || 'Title',
          backdrop:
            input.backdropOverride ||
            meta?.backdropUrl ||
            ((meta?.art || meta?.thumb) ? getPlexImageUrl(meta?.art || meta?.thumb, 1080) : undefined),
          mediaType: input.episodeNumber ? 'episode' : 'movie',
          imdbId: result.identity.imdbId,
          tmdbId: result.identity.tmdbId,
          seasonNumber: input.seasonNumber || result.identity.seasonNumber,
          episodeNumber: input.episodeNumber || result.identity.episodeNumber,
          episodeTitle: input.episodeTitle,
        });
      } catch (e: any) {
        appLogger.warn('[Stremio] Failed to prepare sources', {
          error: e?.message || String(e),
        });
        Alert.alert('Stremio Unavailable', 'Failed to prepare Stremio sources for this title.');
      }
    },
    [meta, nav]
  );

  const handleStremioFromHero = useCallback(async () => {
    if (!settings.stremioPlaybackEnabled) {
      return;
    }

    if (params.type === 'plex') {
      if (meta?.type === 'movie') {
        await openStremioSources({ mode: 'plex', metadata: meta, titleOverride: meta?.title });
        return;
      }

      if (meta?.type === 'show') {
        if (nextUp?.ratingKey) {
          const nextEpisodeMeta = await fetchPlexMetadata(nextUp.ratingKey);
          if (nextEpisodeMeta) {
            await openStremioSources({
              mode: 'plex',
              metadata: nextEpisodeMeta,
              seasonNumber: nextUp.seasonNumber,
              episodeNumber: nextUp.episodeNumber,
              episodeTitle: nextEpisodeMeta.title,
              titleOverride: meta?.title,
            });
            return;
          }
        }

        const firstEpisode = episodes.find((episode) => episode.ratingKey);
        if (firstEpisode) {
          const episodeMeta = await fetchPlexMetadata(String(firstEpisode.ratingKey));
          if (episodeMeta) {
            await openStremioSources({
              mode: 'plex',
              metadata: episodeMeta,
              seasonNumber: firstEpisode.parentIndex,
              episodeNumber: firstEpisode.index,
              episodeTitle: firstEpisode.title,
              titleOverride: meta?.title,
            });
            return;
          }
        }

        Alert.alert('Choose an Episode', 'Open a specific episode to fetch Stremio sources for this show.');
        return;
      }
    }

    if (params.type === 'tmdb' && (settings.stremioShowOnTmdbDetails || isStremioOnly) && params.id) {
      if (params.mediaType === 'movie') {
        await openStremioSources({
          mode: 'tmdb',
          tmdbMediaType: 'movie',
          tmdbId: Number(params.id),
          titleOverride: meta?.title,
        });
        return;
      }

      const firstEpisode = episodes[0];
      if (firstEpisode) {
        await openStremioSources({
          mode: 'tmdb',
          tmdbMediaType: 'tv',
          tmdbId: Number(params.id),
          seasonNumber: firstEpisode.season_number,
          episodeNumber: firstEpisode.episode_number,
          episodeTitle: firstEpisode.name,
          titleOverride: meta?.name || meta?.title,
        });
        return;
      }

      Alert.alert('Choose an Episode', 'Open a specific episode to fetch Stremio sources for this show.');
    }
  }, [episodes, isStremioOnly, meta, nextUp, openStremioSources, params.id, params.mediaType, params.type, settings.stremioPlaybackEnabled, settings.stremioShowOnTmdbDetails]);

  const handleStremioEpisode = useCallback(
    async (episode: any) => {
      if (!settings.stremioPlaybackEnabled) {
        return;
      }

      if (seasonSource === 'tmdb' && params.id) {
        await openStremioSources({
          mode: 'tmdb',
          tmdbMediaType: 'tv',
          tmdbId: Number(params.id),
          seasonNumber: episode.season_number || Number(seasonKey || 1),
          episodeNumber: episode.episode_number,
          episodeTitle: episode.name || episode.title,
          titleOverride: meta?.name || meta?.title,
        });
        return;
      }

      if (episode.ratingKey) {
        const episodeMeta = await fetchPlexMetadata(String(episode.ratingKey));
        if (episodeMeta) {
          await openStremioSources({
            mode: 'plex',
            metadata: episodeMeta,
            seasonNumber: episode.parentIndex,
            episodeNumber: episode.index,
            episodeTitle: episode.title,
            titleOverride: meta?.title || meta?.grandparentTitle,
          });
        }
      }
    },
    [meta, openStremioSources, params.id, seasonKey, seasonSource, settings.stremioPlaybackEnabled]
  );

  const loadSeasonEpisodes = useCallback(
    async (key: string) => {
      if (seasonSource === 'plex') {
        setEpisodes(await fetchPlexSeasonEpisodes(key));
      } else if (seasonSource === 'tmdb' && params.id) {
        setEpisodes(await fetchTmdbSeasonEpisodes(Number(params.id), Number(key)));
      }
    },
    [seasonSource, params.id]
  );

  const handleSeasonChange = useCallback(
    async (key: string) => {
      setSeasonKey(key);
      setEpisodesLoading(true);
      try {
        await loadSeasonEpisodes(key);
      } finally {
        setEpisodesLoading(false);
      }
    },
    [loadSeasonEpisodes]
  );

  const reloadEpisodes = useCallback(async () => {
    if (seasonKey) await loadSeasonEpisodes(seasonKey);
  }, [seasonKey, loadSeasonEpisodes]);

  const titleName: string = meta?.title || meta?.grandparentTitle || 'Title';
  const showTmdbId = meta?.type === 'episode' ? undefined : watchlistIds?.tmdbId;
  const showImdbId = meta?.type === 'episode' ? undefined : imdbId;

  // Without Plex the key must be absent so changes go to Trakt and this device
  const plexKey = isStremioOnly ? undefined : mappedRk || (params.type === 'plex' ? params.ratingKey : undefined);

  const titleTarget = useMemo<WatchStateTarget | null>(() => {
    if (!meta) return null;
    if (meta.type === 'episode') {
      return plexKey
        ? { kind: 'episode', plexRatingKey: plexKey, seasonNumber: meta.parentIndex, episodeNumber: meta.index, title: titleName }
        : null;
    }
    if (!plexKey && showTmdbId == null && !showImdbId) return null;
    return {
      kind: meta.type === 'movie' ? 'movie' : 'show',
      plexRatingKey: plexKey,
      tmdbId: showTmdbId,
      imdbId: showImdbId,
      title: titleName,
    };
  }, [meta, plexKey, showTmdbId, showImdbId, titleName]);

  const seasonNumber = useMemo<number | null>(() => {
    const current = seasons.find((s: any, i: number) => String(s.ratingKey || s.key || i) === seasonKey);
    if (current?.index != null) return Number(current.index);
    return seasonSource === 'tmdb' && seasonKey ? Number(seasonKey) : null;
  }, [seasons, seasonKey, seasonSource]);

  const seasonOptions = useMemo<DetailsSeasonOption[]>(
    () =>
      meta?.type !== 'show'
        ? []
        : seasons.map((s: any, i: number) => ({
            id: String(s.ratingKey || s.key || i),
            title: s.title || `Season ${s.index || i + 1}`,
            target: {
              kind: 'season',
              plexRatingKey: seasonSource === 'plex' && !isStremioOnly ? String(s.ratingKey) : undefined,
              seasonNumber: s.index ?? Number(s.key),
              tmdbId: showTmdbId,
              imdbId: showImdbId,
              title: titleName,
            },
          })),
    [meta?.type, seasons, seasonSource, isStremioOnly, showTmdbId, showImdbId, titleName]
  );

  // Episode pages: TMDB episode details for guest stars and the Information rows
  const episodeShowTmdbId =
    meta?.type === 'episode' ? extractTmdbIdFromGuids(parentShowMeta?.Guid || []) : undefined;
  useEffect(() => {
    let cancelled = false;
    setEpisodeExtra(null);
    const season = Number(meta?.parentIndex);
    const episode = Number(meta?.index);
    if (!episodeShowTmdbId || !Number.isFinite(season) || !Number.isFinite(episode)) return;
    fetchTmdbEpisodeDetails(Number(episodeShowTmdbId), season, episode).then((result) => {
      if (!cancelled) setEpisodeExtra(result);
    });
    return () => {
      cancelled = true;
    };
  }, [episodeShowTmdbId, meta?.parentIndex, meta?.index]);

  // TMDB franchise row for movies
  const collectionMovieId = meta?.type === 'movie' ? watchlistIds?.tmdbId : undefined;
  useEffect(() => {
    let cancelled = false;
    setCollection(null);
    if (collectionMovieId == null) return;
    fetchTmdbMovieCollection(collectionMovieId).then((result) => {
      if (!cancelled) setCollection(result);
    });
    return () => {
      cancelled = true;
    };
  }, [collectionMovieId]);

  const hasCastOrCrew =
    tmdbCast.length > 0 ||
    (episodeExtra?.guest_stars?.length ?? 0) > 0 ||
    tmdbCrew.length > 0 ||
    !!meta?.Role?.length ||
    !!meta?.Director?.length ||
    !!meta?.Writer?.length ||
    !!tmdbExtraInfo.creators?.length;

  const availableSections = useMemo<DetailsSectionKey[]>(
    () =>
      orderedEnabledSections(settings.detailsSectionPreferences).filter((key) => {
        switch (key) {
          case 'episodes':
            return meta?.type === 'show' && seasons.length > 0;
          case 'collection':
            return collection !== null;
          case 'cast':
            return hasCastOrCrew;
          case 'trailers':
            return trailers.length > 0;
          case 'comments':
            return titleTarget !== null;
          case 'suggested':
            // As on macOS: a show's suggestions don't belong on an episode page
            return meta?.type !== 'episode';
          case 'about':
            return true;
        }
      }),
    [settings.detailsSectionPreferences, meta?.type, seasons.length, collection, hasCastOrCrew, trailers.length, titleTarget]
  );

  const heroTrailerKey = useMemo(() => {
    if (!settings.detailsHeroInlineTrailerEnabled || heroTrailerFinished) return undefined;
    const youtube = trailers.filter((t) => t.site?.toLowerCase() === 'youtube');
    return (youtube.find((t) => t.type === 'Trailer' && t.official) ?? youtube.find((t) => t.type === 'Trailer') ?? youtube[0])?.key;
  }, [settings.detailsHeroInlineTrailerEnabled, heroTrailerFinished, trailers]);

  console.log('[Details] Render - loading:', loading, 'isConnected:', isConnected, 'meta:', !!meta);

  if (flixorLoading || !canLoad || loading) {
    return (
      <View style={{ flex:1, backgroundColor: theme.background, alignItems:'center', justifyContent:'center' }}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  if (!meta) {
    return (
      <View style={{ flex:1, backgroundColor: theme.background, alignItems:'center', justifyContent:'center' }}>
        <Text style={{ color:'#fff' }}>No metadata available</Text>
      </View>
    );
  }

  console.log('[Details] Rendering full UI for:', meta?.title);

  const title = meta?.title || meta?.grandparentTitle || 'Title';
  const stremioOnTmdb = settings.stremioShowOnTmdbDetails || isStremioOnly;
  const showStremioButton =
    settings.stremioPlaybackEnabled &&
    (params.type === 'plex' || (params.type === 'tmdb' && stremioOnTmdb)) &&
    (meta?.type === 'movie' || meta?.type === 'show');
  // Addons are the only playback path with no Plex, so they take the main button
  const stremioIsPrimary = isStremioOnly && showStremioButton;
  const headerOverlayColor = withAlpha(tint, 0.85);
  const listTitle: TraktListTitle | null =
    (meta?.type === 'movie' || meta?.type === 'show') && (showTmdbId != null || !!showImdbId)
      ? { type: meta.type, tmdbId: showTmdbId, imdbId: showImdbId, title }
      : null;
  // Hero play button: sentence case, "Resume" with progress for a part-watched movie
  const movieOffset = meta?.type !== 'show' ? Number(meta?.viewOffset || 0) : 0;
  const movieDuration = Number(meta?.duration || 0);
  const movieProgress =
    matchedPlex && !stremioIsPrimary && movieOffset > 0 && movieDuration > 0 && movieOffset < movieDuration * 0.97
      ? {
          percent: Math.max(2, Math.min(100, Math.round((movieOffset / movieDuration) * 100))),
          left: formatRuntime(Math.max(1, Math.round((movieDuration - movieOffset) / 60000))) || '',
        }
      : null;
  const playLabel = (() => {
    if (stremioIsPrimary) return 'Play';
    if (meta?.type === 'show' && nextUp) {
      const verb = nextUp.status === 'in-progress' ? 'Continue' : nextUp.status === 'all-watched' ? 'Rewatch' : 'Play';
      return `${verb} S${nextUp.seasonNumber} E${nextUp.episodeNumber}`;
    }
    return movieProgress ? 'Resume' : 'Play';
  })();
  const openTrailer = () => {
    const trailer = trailers[0];
    if (!trailer) return;
    const url = getYouTubeUrl(trailer.key);
    Linking.openURL(url).catch((err) => {
      Alert.alert('Error', 'Could not open trailer');
      console.log('[Details] Failed to open URL:', err);
    });
  };
  const moreActions: DetailsAction[] = [
    {
      key: 'trailer',
      title: trailers.length > 0 ? 'Play Trailer' : 'No Trailer Available',
      icon: 'play-circle-outline',
      disabled: trailers.length === 0,
      onPress: openTrailer,
    },
  ];
  if (listTitle && isTraktAvailable()) {
    moreActions.push({
      key: 'add-to-list',
      title: 'Add to List…',
      icon: 'list-outline',
      // Let the action sheet finish closing before the list sheet opens (two modals at once fail on iOS)
      onPress: () => setTimeout(() => setAddToListTitle(listTitle), 350),
    });
  }
  const contentRating = meta?.contentRating || 'PG';
  // Badges parsing from Plex streams (matching macOS logic)
  const media = (meta?.Media || [])[0] || {};
  const streams = ((media?.Part || [])[0]?.Stream || []) as any[];
  const videoStreams = streams.filter(s => s.streamType === 1);
  const audioStreams = streams.filter(s => s.streamType === 2);
  const subtitleStreams = streams.filter(s => s.streamType === 3);

  // Resolution detection from width/height (like macOS)
  const width = media?.width || 0;
  const height = media?.height || 0;
  const videoRes = media?.videoResolution;
  const is4K = width >= 3800 || height >= 2100 || String(videoRes).toLowerCase() === '4k' || Number(videoRes) >= 2160;
  const isHD = !is4K && (width >= 1260 || height >= 700 || (Number(videoRes) >= 720 && Number(videoRes) < 2160));

  // Dolby Vision detection from video stream profile (like macOS)
  const hasDV = videoStreams.some(s => {
    const profile = String(s?.displayTitle || '').toLowerCase();
    const colorTrc = String(s?.colorTrc || '').toLowerCase();
    return /dolby.?vision|dovi/i.test(profile) ||
           profile.includes('dv') ||
           /smpte2084|pq/i.test(colorTrc);
  });

  // Dolby Atmos detection from audio streams (like macOS)
  const hasAtmos = audioStreams.some(s => {
    const displayTitle = String(s?.displayTitle || '').toLowerCase();
    const codec = String(s?.codec || '').toLowerCase();
    const profile = String(s?.audioProfile || '').toLowerCase();
    return displayTitle.includes('atmos') ||
           displayTitle.includes('truehd') ||
           codec.includes('atmos') ||
           codec.includes('truehd') ||
           profile.includes('atmos');
  });

  // CC badge - show if any subtitles exist (like macOS)
  const hasCC = subtitleStreams.length > 0;

  // SDH badge - show if any subtitle contains "SDH" in name (like macOS)
  const hasSDH = subtitleStreams.some(s =>
    String(s?.displayTitle || '').toUpperCase().includes('SDH') ||
    String(s?.title || '').toUpperCase().includes('SDH')
  );

  // AD (Audio Description) badge
  const hasAD = audioStreams.some(s =>
    String(s?.displayTitle || '').toLowerCase().includes('description') ||
    String(s?.title || '').toLowerCase().includes('description')
  );

  // Parse ratings for inline display
  const plexRatings: any[] = Array.isArray(meta?.Rating) ? meta.Rating : [];
  let imdbRating: number | undefined;
  let rtCriticRating: number | undefined;
  let rtAudienceRating: number | undefined;
  try {
    plexRatings.forEach((r: any) => {
      const img = String(r?.image || '').toLowerCase();
      const val = typeof r?.value === 'number' ? r.value : Number(r?.value);
      if (img.includes('imdb://image.rating')) imdbRating = val;
      if (img.includes('rottentomatoes://image.rating.ripe') || img.includes('rottentomatoes://image.rating.rotten')) rtCriticRating = val ? Math.round(val * 10) : undefined;
      if (img.includes('rottentomatoes://image.rating.upright') || img.includes('rottentomatoes://image.rating.spilled')) rtAudienceRating = val ? Math.round(val * 10) : undefined;
    });
  } catch {}
  // Fallbacks from top-level fields
  if (!imdbRating && typeof meta?.rating === 'number') imdbRating = meta.rating;
  if (!rtAudienceRating && typeof meta?.audienceRating === 'number') rtAudienceRating = Math.round(meta.audienceRating * 10);
  // Then MDBList, then TMDB, as on macOS (the hero is the only place ratings appear)
  const mdb = mdblistRating.ratings;
  if (!imdbRating && mdb?.imdb) imdbRating = mdb.imdb;
  if (!imdbRating && tmdbExtraInfo?.voteAverage) imdbRating = tmdbExtraInfo.voteAverage;
  if (!rtCriticRating && mdb?.tomatoes) rtCriticRating = Math.round(mdb.tomatoes);
  if (!rtAudienceRating && mdb?.audience) rtAudienceRating = Math.round(mdb.audience);

  // Handler for sticky header watchlist toggle
  const handleStickyWatchlistToggle = async () => {
    if (!watchlistIds || watchlistLoading) return;
    setWatchlistLoading(true);
    try {
      const result = await toggleWatchlist(watchlistIds, 'both');
      if (result.success) {
        setInWatchlist(result.inWatchlist);
      }
    } finally {
      setWatchlistLoading(false);
    }
  };

  const activeSection: DetailsSectionKey = availableSections.includes(tab) ? tab : availableSections[0] ?? 'about';

  // Full Person page on this tab's stack, as on macOS; Back returns here
  const openPerson = (id: number, name: string) => {
    nav.push('Person', { id, name });
  };

  const renderSection = (key: DetailsSectionKey): React.ReactNode => {
    switch (key) {
      case 'episodes':
        return (
          <DetailsEpisodesSection
            seasons={seasons}
            seasonKey={seasonKey}
            seasonNumber={seasonNumber}
            seasonPickerStyle={settings.detailsSeasonPickerStyle}
            onSeasonChange={handleSeasonChange}
            episodes={episodes}
            loading={episodesLoading}
            tmdbMode={seasonSource === 'tmdb'}
            tmdbId={showTmdbId}
            imdbId={showImdbId}
            showTitle={title}
            tmdbEpisodeData={tmdbEpisodeData}
            horizontalLayout={settings.episodeLayoutStyle === 'horizontal'}
            hideSpoilers={settings.detailsHideEpisodeSpoilers}
            showRatings={settings.detailsShowEpisodeRatings}
            stremioEnabled={settings.stremioPlaybackEnabled && (seasonSource !== 'tmdb' || stremioOnTmdb)}
            onPlayEpisode={handlePlayEpisode}
            onOpenStremioEpisode={handleStremioEpisode}
            onChanged={reloadEpisodes}
          />
        );
      case 'suggested':
        return <SuggestedRows meta={meta} routeParams={route?.params} parentShowMeta={parentShowMeta} keyPrefix={isUnifiedLayout ? 'unified-' : ''} />;
      case 'collection':
        return collection ? (
          <DetailsCollectionRow
            name={collection.name}
            items={collection.items}
            currentId={collectionMovieId != null ? `tmdb:movie:${collectionMovieId}` : undefined}
            onTitlePress={() => nav.push('EntityBrowse', { kind: 'collection', id: collection.id, name: collection.name })}
            onItemPress={(item) => {
              const [, media, id] = item.id.split(':');
              nav.push('Details', { type: 'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
            }}
          />
        ) : null;
      case 'cast':
        return (
          <DetailsCastRow
            meta={meta}
            tmdbCast={tmdbCast}
            tmdbCrew={tmdbCrew}
            creators={tmdbExtraInfo?.creators}
            guestStars={episodeExtra?.guest_stars ?? []}
            onPersonPress={openPerson}
          />
        );
      case 'trailers':
        return <TrailersRow trailers={trailers} contentTitle={meta?.title} />;
      case 'comments':
        return <DetailsComments target={titleTarget} />;
      case 'about':
        return (
          <DetailsTab
            meta={meta}
            productionInfo={productionInfo}
            tmdbExtraInfo={tmdbExtraInfo}
            tmdbCrew={tmdbCrew}
            episodeExtra={episodeExtra}
            firstEpisodeMedia={firstEpisodeMedia}
            onOpenEntity={(kind, id, name) => nav.push('EntityBrowse', { kind, id, name })}
          />
        );
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: tint }}>
      <DetailsBackdrop
        imageUrl={backdropUrl}
        tint={tint}
        maxTintAlpha={maxTintAlpha}
        heroHeight={HERO_HEIGHT}
        scrollY={scrollY}
        trailerKey={heroTrailerKey}
        trailerMuted={heroTrailerMuted}
        trailerAllowed={isFocused}
        onTrailerPlayingChange={setHeroTrailerPlaying}
        onTrailerFinished={() => {
          setHeroTrailerPlaying(false);
          setHeroTrailerFinished(true);
        }}
      />
      {/* Sticky Header with Logo - appears when scrolled past hero */}
      <Animated.View
        style={[
          {
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            zIndex: 100,
            overflow: 'hidden',
          },
          stickyHeaderStyle,
        ]}
        pointerEvents="box-none"
      >
        {/* Blur background */}
        <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}>
          <ConditionalBlurView intensity={50} tint="dark" style={StyleSheet.absoluteFillObject} />
          <View style={[StyleSheet.absoluteFillObject, { backgroundColor: headerOverlayColor }]} />
          {/* Bottom separator */}
          <View
            style={{
              position: 'absolute',
              left: 0,
              right: 0,
              bottom: 0,
              height: StyleSheet.hairlineWidth,
              backgroundColor: 'rgba(255,255,255,0.1)',
            }}
          />
        </View>
        {/* Header content */}
        <View style={{ paddingTop: insets.top, paddingBottom: 12 }}>
          <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12 }}>
            {/* Back button in sticky header - uses simple styling since header already has blur */}
            <Pressable onPress={() => nav.goBack()} style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: 'rgba(0,0,0,0.3)', alignItems: 'center', justifyContent: 'center' }}>
              <Ionicons name="chevron-back" color="#fff" size={22} />
            </Pressable>
            {/* Centered logo or title */}
            <View style={{ flex: 1, alignItems: 'center', marginHorizontal: 8 }}>
              {meta?.logoUrl && FastImage ? (
                <FastImage source={{ uri: meta.logoUrl }} style={{ width: 120, height: 32 }} resizeMode="contain" />
              ) : (
                <Text style={{ color: '#fff', fontSize: 16, fontWeight: '700' }} numberOfLines={1}>
                  {title}
                </Text>
              )}
            </View>
            {/* Watchlist button - uses simple styling since header already has blur */}
            <Pressable
              onPress={handleStickyWatchlistToggle}
              disabled={watchlistLoading}
              style={{ width: 36, height: 36, borderRadius: 18, backgroundColor: 'rgba(0,0,0,0.3)', alignItems: 'center', justifyContent: 'center', opacity: watchlistLoading ? 0.5 : 1 }}
            >
              {watchlistLoading ? (
                <ActivityIndicator size="small" color="#fff" />
              ) : (
                <Ionicons name={inWatchlist ? 'bookmark' : 'bookmark-outline'} size={18} color="#fff" />
              )}
            </Pressable>
          </View>
        </View>
      </Animated.View>

      <Animated.ScrollView
        ref={scrollRef}
        scrollEventThrottle={16}
        onScroll={scrollHandler}
        bounces={true}
        contentContainerStyle={{ paddingBottom: 32 + insets.bottom }}
      >
        {/* Hero: the artwork itself is fixed behind the page in DetailsBackdrop */}
        <View pointerEvents="box-none">
          <View style={{ width: '100%', aspectRatio: 16/9 }} pointerEvents="box-none">
            {/* Top-left back button */}
            <View style={{ position: 'absolute', left: 12, top: insets.top + 8, flexDirection: 'row' }}>
              <Pressable onPress={() => nav.goBack()} style={{ width: 36, height: 36 }}>
                {Platform.OS === 'ios' && GlassViewComp && liquidGlassAvailable ? (
                  <>
                    <GlassViewComp key={`glass-${glassKey}`} style={{ position: 'absolute', width: 36, height: 36, borderRadius: 18, overflow: 'hidden' }} isInteractive glassEffectStyle="clear" tintColor="rgba(59, 55, 55, 0.15)" />
                    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }} pointerEvents="none">
                      <Ionicons name="chevron-back" color="#fff" size={22} />
                    </View>
                  </>
                ) : (
                  <>
                    <ConditionalBlurView intensity={60} tint="dark" style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
                      <Ionicons name="chevron-back" color="#fff" size={22} />
                    </ConditionalBlurView>
                    <View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, borderRadius: 18, borderWidth: 1, borderColor: 'rgba(255,255,255,0.15)' }} pointerEvents="none" />
                  </>
                )}
              </Pressable>
            </View>
            {heroTrailerPlaying ? (
              <Pressable
                onPress={() => setHeroTrailerMuted((muted) => !muted)}
                hitSlop={8}
                accessibilityRole="button"
                accessibilityLabel={heroTrailerMuted ? 'Unmute trailer' : 'Mute trailer'}
                style={{ position: 'absolute', right: 12, top: insets.top + 8, width: 36, height: 36, borderRadius: 18, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center' }}
              >
                <Ionicons name={heroTrailerMuted ? 'volume-mute' : 'volume-high'} size={18} color="#fff" />
              </Pressable>
            ) : null}
            {/* TMDB logo overlay with parallax */}
            {meta?.logoUrl && FastImage ? (
              <Animated.View style={[{ position: 'absolute', bottom: 24, left: '10%', right: '10%', height: 48 }, logoAnimatedStyle]} pointerEvents="none">
                <FastImage source={{ uri: meta.logoUrl }} style={{ width: '100%', height: '100%' }} resizeMode="contain" />
              </Animated.View>
            ) : null}
          </View>
        </View>

        {/* Title - hide when logo is displayed */}
        {!meta?.logoUrl && (
          <Text style={{ color:'#fff', fontSize:28, fontWeight:'800', marginHorizontal:16 }}>{title}</Text>
        )}

        {/* Meta line */}
        <Text numberOfLines={1} style={{ color: theme.textSecondary, fontSize: 13, marginHorizontal: 16, marginTop: 12, textAlign: 'center' }}>
          {[
            meta?.type === 'episode' && meta?.parentIndex && meta?.index ? `S${meta.parentIndex} E${meta.index}` : null,
            meta?.year ? String(meta.year) : null,
            extractEditionTitle(meta?.Media) || null,
            meta?.type === 'show'
              ? `${meta?.leafCount || tmdbExtraInfo.numberOfEpisodes || 0} Episodes`
              : (meta?.duration ? formatRuntime(Math.round(meta.duration / 60000)) : null),
            meta?.Genre?.length ? meta.Genre.map((g: any) => g.tag).slice(0, 2).join(', ') : null,
          ].filter(Boolean).join(' · ')}
        </Text>

        {/* Badges and ratings: one line that never wraps. A title with many badges scrolls sideways. */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          style={{ flexGrow: 0, marginTop: 8 }}
          contentContainerStyle={{ flexGrow: 1, justifyContent: 'center', alignItems: 'center', gap: 6, paddingHorizontal: 16 }}
        >
          <ContentRatingBadge rating={contentRating} size={10} />
          {is4K ? <TechBadge type="4k" size={10} /> : null}
          {isHD ? <TechBadge type="hd" size={10} /> : null}
          {hasDV ? <TechBadge type="dolby-vision" size={10} /> : null}
          {hasAtmos ? <TechBadge type="dolby-atmos" size={10} /> : null}
          {hasCC ? <TechBadge type="cc" size={10} /> : null}
          {hasSDH && !hasCC ? <TechBadge type="sdh" size={10} /> : null}
          {hasAD ? <TechBadge type="ad" size={10} /> : null}
          {!matchedPlex && params.type === 'tmdb' && !isStremioOnly ? <BadgePill label="No local source" /> : null}
          {(() => {
            const ratings: React.ReactNode[] = [];
            if (detailsSettings.showIMDbRating && typeof imdbRating === 'number') {
              ratings.push(
                <View key="imdb" style={styles.heroRating}>
                  <Image source={RATING_IMAGES.imdb} style={{ width: 22, height: 11 }} resizeMode="contain" />
                  <Text style={styles.heroRatingText}>{imdbRating.toFixed(1)}</Text>
                </View>
              );
            }
            if (detailsSettings.showRottenTomatoesCritic && typeof rtCriticRating === 'number') {
              ratings.push(
                <View key="rt" style={styles.heroRating}>
                  <Image source={rtCriticRating >= 60 ? RATING_IMAGES.tomatoFresh : RATING_IMAGES.tomatoRotten} style={{ width: 11, height: 11 }} resizeMode="contain" />
                  <Text style={styles.heroRatingText}>{rtCriticRating}%</Text>
                </View>
              );
            }
            if (detailsSettings.showRottenTomatoesAudience && typeof rtAudienceRating === 'number') {
              ratings.push(
                <View key="rta" style={styles.heroRating}>
                  <Image source={rtAudienceRating >= 60 ? RATING_IMAGES.popcornFull : RATING_IMAGES.popcornFallen} style={{ width: 11, height: 11 }} resizeMode="contain" />
                  <Text style={styles.heroRatingText}>{rtAudienceRating}%</Text>
                </View>
              );
            }
            return ratings.flatMap((node, i) => [
              <Text key={`dot-${i}`} style={styles.heroDot}>·</Text>,
              node,
            ]);
          })()}
        </ScrollView>

        {/* View Show button for episodes */}
        {meta?.type === 'episode' && meta?.grandparentRatingKey && (
          <Pressable
            onPress={() => {
              console.log('[Details] Navigating to parent show:', meta.grandparentRatingKey);
              nav.push('Details', { type: 'plex', ratingKey: String(meta.grandparentRatingKey) });
            }}
            style={{
              marginHorizontal: 16,
              marginTop: 12,
              backgroundColor: 'rgba(255,255,255,0.1)',
              paddingVertical: 10,
              borderRadius: 10,
              alignItems: 'center',
              flexDirection: 'row',
              justifyContent: 'center',
              gap: 8,
            }}
          >
            <Ionicons name="tv-outline" size={18} color="#fff" />
            <Text style={{ color: '#fff', fontWeight: '700', fontSize: 14 }}>
              View Show
            </Text>
          </Pressable>
        )}

        {/* Play / Continue */}
        <View style={{ marginHorizontal: 16, marginTop: 12, gap: 10 }}>
          <Pressable
            disabled={!matchedPlex && !stremioIsPrimary}
            onPress={() => {
              if (stremioIsPrimary) {
                handleStremioFromHero();
              } else if (matchedPlex || params.type === 'plex') {
                // For TV shows with nextUp, play that episode (with version check)
                if (meta?.type === 'show' && nextUp) {
                  console.log('[Details] Playing next up episode:', nextUp.ratingKey, `S${nextUp.seasonNumber}E${nextUp.episodeNumber}`);
                  handlePlayWithVersionCheck(nextUp.ratingKey);
                } else {
                  // For movies or shows without nextUp data, play the main content
                  const rk = mappedRk || params.ratingKey;
                  if (rk) {
                    // Check for multiple versions (multi-version support)
                    const mediaArray = meta?.Media || [];
                    if (mediaArray.length > 1) {
                      // Parse versions and show picker
                      const versions = mediaArray.map((m: any, idx: number) => parseVersionDetails(m, idx));
                      setMediaVersions(versions);
                      setPendingPlayRatingKey(rk);
                      setShowVersionPicker(true);
                      console.log('[Details] Multiple versions detected:', versions.length);
                    } else {
                      console.log('[Details] Playing ratingKey:', rk);
                      nav.navigate('Player', { type: 'plex', ratingKey: rk });
                    }
                  }
                }
              }
            }}
            accessibilityRole="button"
            accessibilityLabel={playLabel}
            style={matchedPlex || stremioIsPrimary ? styles.playButton : styles.playButtonDisabled}
          >
            {matchedPlex || stremioIsPrimary ? (
              <>
                <Ionicons name="play" size={18} color="#000" />
                <Text style={styles.playButtonText}>{playLabel}</Text>
              </>
            ) : (
              <Text style={{ color: theme.textSecondary, fontWeight: '600', fontSize: 13, textAlign: 'center' }}>
                You don't own this content{'\n'}No local source found
              </Text>
            )}
          </Pressable>

          {movieProgress ? (
            <View style={styles.resumeRow} accessibilityLabel={`${movieProgress.left} left`}>
              <View style={styles.resumeTrack}>
                <View style={[styles.resumeFill, { width: `${movieProgress.percent}%`, backgroundColor: theme.accent }]} />
              </View>
              <Text style={[styles.resumeText, { color: theme.textSecondary }]}>{movieProgress.left} left</Text>
            </View>
          ) : null}

          {showStremioButton && !stremioIsPrimary ? (
            <Pressable
              onPress={handleStremioFromHero}
              accessibilityRole="button"
              style={styles.secondaryButton}
            >
              <Text style={styles.secondaryButtonText}>Stremio sources</Text>
            </Pressable>
          ) : null}
        </View>

        {/* Actions: round neutral buttons, as on macOS. Trailer and Add to List live under More. */}
        <View style={{ flexDirection: 'row', justifyContent: 'space-evenly', marginTop: 18, marginHorizontal: 8 }}>
          <WatchlistButton
            inWatchlist={inWatchlist}
            loading={watchlistLoading}
            onPress={async () => {
              if (!watchlistIds || watchlistLoading) return;
              setWatchlistLoading(true);
              try {
                const result = await toggleWatchlist(watchlistIds, 'both');
                if (result.success) {
                  setInWatchlist(result.inWatchlist);
                }
              } finally {
                setWatchlistLoading(false);
              }
            }}
          />
          <DetailsWatchActions
            target={titleTarget}
            title={title}
            episodeTotal={tmdbExtraInfo.numberOfEpisodes}
            seasonOptions={seasonOptions}
          />
          {noLocalSource && !isStremioOnly && (
            <RequestButton
              tmdbId={watchlistIds?.tmdbId}
              mediaType={meta?.type === 'movie' ? 'movie' : 'tv'}
              title={meta?.title || 'this title'}
              compact
            />
          )}
          {/* Download: movies with a local source */}
          {!noLocalSource && meta?.type === 'movie' && meta && (
            <DownloadButton metadata={meta} variant="round" />
          )}
          <Pressable onPress={() => setShowMoreActions(true)} accessibilityRole="button" accessibilityLabel="More actions">
            <DetailsActionLabel icon="ellipsis-horizontal" label="More" />
          </Pressable>
        </View>

        <DetailsActionSheet
          visible={showMoreActions}
          title={title}
          actions={moreActions}
          onClose={() => setShowMoreActions(false)}
        />

        {/* Synopsis */}
        {meta?.summary ? (
          <Text style={{ color:'rgba(255,255,255,0.86)', fontSize: 15, marginHorizontal:16, marginTop:18, lineHeight:21 }}>{meta.summary}</Text>
        ) : null}

        {/* Tabs - only show in tabbed layout */}
        {!isUnifiedLayout && availableSections.length > 0 ? (
          <DetailsSectionTabs sections={availableSections} active={activeSection} onSelect={setTab} />
        ) : null}

        {/* Sections in the user's order */}
        <View style={{ marginTop: 20 }}>
          {isUnifiedLayout
            ? availableSections.map((key) => (
                <View key={key} style={{ marginBottom: DetailsSectionStyle.sectionGap }}>
                  {renderSection(key)}
                </View>
              ))
            : renderSection(activeSection)}
        </View>
      </Animated.ScrollView>

      <AddToListSheet title={addToListTitle} onClose={() => setAddToListTitle(null)} />

      {/* Version Picker Modal (for multi-version support) */}
      <VersionPicker
        visible={showVersionPicker}
        onClose={() => {
          setShowVersionPicker(false);
          setPendingPlayRatingKey(null);
        }}
        onSelect={(mediaIndex) => {
          setShowVersionPicker(false);
          const rk = pendingPlayRatingKey || mappedRk || params.ratingKey;
          setPendingPlayRatingKey(null);
          if (rk) {
            console.log('[Details] Playing version:', mediaIndex, 'ratingKey:', rk);
            nav.navigate('Player', { type: 'plex', ratingKey: rk, mediaIndex });
          }
        }}
        versions={mediaVersions}
        title={meta?.title || meta?.name || 'Select Version'}
      />
    </View>
  );
}

function WatchlistButton({ inWatchlist, loading, onPress }: { inWatchlist: boolean; loading: boolean; onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      disabled={loading}
      accessibilityRole="button"
      accessibilityLabel={inWatchlist ? 'Remove from My List' : 'Add to My List'}
      style={{ alignItems:'center', opacity: loading ? 0.5 : 1 }}
    >
      {loading ? (
        <DetailsActionLabel icon="add" label="My List" busy />
      ) : (
        <DetailsActionLabel icon={inWatchlist ? 'checkmark' : 'add'} label="My List" />
      )}
    </Pressable>
  );
}

function SuggestedRows({ meta, routeParams, parentShowMeta, keyPrefix = '' }: { meta: any; routeParams?: any; parentShowMeta?: any; keyPrefix?: string }) {
  const [recs, setRecs] = React.useState<RowItem[]>([]);
  const [similar, setSimilar] = React.useState<RowItem[]>([]);
  const [loading, setLoading] = React.useState(true);

  // For episodes, use parent show's TMDB ID for suggestions
  const isEpisode = meta?.type === 'episode';
  const effectiveMeta = isEpisode && parentShowMeta ? parentShowMeta : meta;

  const tmdbId = React.useMemo(() => {
    try {
      // Prefer Plex GUID (meta) if available
      const guids: string[] = Array.isArray(effectiveMeta?.Guid) ? effectiveMeta.Guid.map((g:any)=> String(g.id||'')) : [];
      const tmdbGuid = guids.find(g=> g.includes('tmdb://') || g.includes('themoviedb://'));
      if (tmdbGuid) return tmdbGuid.split('://')[1];
      // Fallback to route param for TMDB-only details
      const pid = routeParams?.id; return pid ? String(pid) : null;
    } catch { return null; }
  }, [effectiveMeta, routeParams]);

  const mediaType: 'movie'|'tv' = React.useMemo(() => {
    // Episodes are always TV
    if (isEpisode) return 'tv';
    if (effectiveMeta?.type === 'movie' || effectiveMeta?.type === 'show') return (effectiveMeta.type === 'movie') ? 'movie' : 'tv';
    const rt = routeParams?.mediaType; return rt === 'movie' ? 'movie' : 'tv';
  }, [effectiveMeta, routeParams, isEpisode]);

  React.useEffect(() => {
    (async () => {
      try {
        if (!tmdbId) return setLoading(false);
        const [r, s] = await Promise.all([
          fetchTmdbRecommendations(mediaType, Number(tmdbId)),
          fetchTmdbSimilar(mediaType, Number(tmdbId))
        ]);
        setRecs(r);
        setSimilar(s);
      } finally {
        setLoading(false);
      }
    })();
  }, [tmdbId, mediaType]);

  const nav: any = useNavigation();
  const onPress = (it: RowItem) => {
    if (!it?.id) return;
    if (it.id.startsWith('plex:')) {
      const rk = it.id.split(':')[1];
      nav.push('Details', { type:'plex', ratingKey: rk });
    } else if (it.id.startsWith('tmdb:')) {
      const [, media, id] = it.id.split(':');
      nav.push('Details', { type:'tmdb', mediaType: media === 'movie' ? 'movie' : 'tv', id });
    }
  };

  // Push Browse screen on top of Details modal with all items
  const openBrowse = (title: string, items: RowItem[]) => {
    const browseItems = items.map((item) => ({
      id: item.id,
      title: item.title,
      image: item.image,
    }));
    nav.push('Browse', {
      context: { type: 'static' },
      title,
      initialItems: browseItems,
    });
  };

  // One "More Like This" row, as on macOS: Recommended first, then Similar titles not
  // already in it. Nothing is drawn while loading or when both lists are empty.
  const moreLikeThis = React.useMemo(() => {
    const seen = new Set<string>();
    return [...recs, ...similar].filter((item) => !seen.has(item.id) && seen.add(item.id) !== undefined);
  }, [recs, similar]);
  if (loading || moreLikeThis.length === 0) return null;
  return (
    <View>
      <DetailsSectionHeading title="More Like This" onPress={() => openBrowse('More Like This', moreLikeThis)} />
      <FlatList
        horizontal
        data={moreLikeThis}
        keyExtractor={(item) => `${keyPrefix}${item.id}`}
        renderItem={({ item }) => (
          <Poster uri={item.image} title={item.title} onPress={() => onPress(item)} />
        )}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingHorizontal: DetailsSectionStyle.inset }}
        initialNumToRender={4}
        windowSize={5}
      />
    </View>
  );
}

function SectionHeader({ title }: { title: string }) {
  return (
    <View style={{ marginTop: 18 }}>
      <DetailsSectionHeading title={title} />
    </View>
  );
}

function KeyValue({ k, v }: { k: string; v?: string }) {
  if (!v) return null;
  return (
    <View style={{ flexDirection:'row', justifyContent:'space-between', paddingHorizontal:16, paddingVertical:8 }}>
      <Text style={{ color:'rgba(255,255,255,0.6)', fontSize:15 }}>{k}</Text>
      <Text style={{ color:'#fff', fontSize:15, marginLeft:16, flexShrink:1, textAlign:'right' }}>{v}</Text>
    </View>
  );
}

// Rating images - Metro bundler picks the right @2x/@3x variant automatically
const RATING_IMAGES = {
  imdb: require('../../assets/ratings/imdb.png'),
  tomatoFresh: require('../../assets/ratings/tomato-fresh.png'),
  tomatoRotten: require('../../assets/ratings/tomato-rotten.png'),
  popcornFull: require('../../assets/ratings/popcorn-full.png'),
  popcornFallen: require('../../assets/ratings/popcorn-fallen.png'),
  metacritic: require('../../assets/ratings/metacritic.png'),
  audienceScore: require('../../assets/ratings/audienscore.png'),
};

/** The media of the title on screen, or of a show's first episode. */
function primaryMedia(meta: any, firstEpisodeMedia?: any[]): any {
  const mediaArray = meta?.Media?.length ? meta.Media : (firstEpisodeMedia || []);
  return mediaArray[0] || {};
}

function TechSpecs({ meta, firstEpisodeMedia }: { meta:any; firstEpisodeMedia?: any[] }) {
  const m = primaryMedia(meta, firstEpisodeMedia);
  const streams: any[] = (Array.isArray(m?.Part) ? m.Part[0]?.Stream : undefined) || [];
  const audio = streams.find((x) => x.streamType === 2 && x.selected) || streams.find((x) => x.streamType === 2);
  const resolution = (() => {
    const r = String(m?.videoResolution || '').toLowerCase();
    if (r === '4k') return '4K';
    if (/^\d+$/.test(r)) return `${r}p`;
    return m?.width && m?.height ? `${m.width}×${m.height}` : undefined;
  })();
  const vCodec = (m?.videoCodec || m?.videoCodecTag)?.toUpperCase();
  const channels = audio?.channels || m?.audioChannels;
  const aCodec = m?.audioCodec ? `${String(m.audioCodec).toUpperCase()}${channels ? ` ${channels}ch` : ''}` : undefined;
  const container = m?.container ? String(m.container).toUpperCase() : undefined;
  const bitrate = m?.bitrate ? `${(m.bitrate / 1000).toFixed(m.bitrate >= 10000 ? 0 : 1)} Mbps` : undefined;
  const size = Number(m?.Part?.[0]?.size || 0);
  const fileSize = size > 0 ? (size >= 1e9 ? `${(size / 1e9).toFixed(1)} GB` : `${Math.round(size / 1e6)} MB`) : undefined;
  const hdr = (() => {
    const s = streams.find((x) => /dolby.?vision|dovi/i.test(String(x?.displayTitle||'')) || /smpte2084|pq|hdr10|arib-std-b67/i.test(String(x?.colorTrc||'')));
    if (!s) return undefined;
    if (/dolby.?vision|dovi/i.test(String(s?.displayTitle||''))) return 'Dolby Vision';
    return /arib-std-b67/i.test(String(s?.colorTrc||'')) ? 'HLG' : 'HDR10';
  })();

  if (!resolution && !vCodec && !aCodec && !container && !bitrate && !hdr && !fileSize) return null;

  return (
    <View>
      <SectionHeader title="Technical" />
      <KeyValue k="Resolution" v={resolution} />
      <KeyValue k="Video" v={vCodec} />
      <KeyValue k="Audio" v={aCodec} />
      <KeyValue k="HDR" v={hdr} />
      <KeyValue k="Container" v={container} />
      <KeyValue k="Bitrate" v={bitrate} />
      <KeyValue k="File Size" v={fileSize} />
    </View>
  );
}

function Collections({ meta }: { meta:any }) {
  const cols: any[] = Array.isArray(meta?.Collection) ? meta.Collection : [];
  if (!cols.length) return null;
  return (
    <View>
      <SectionHeader title="Collections" />
      <View style={{ flexDirection:'row', flexWrap:'wrap', gap:8, paddingHorizontal:16 }}>
        {cols.map((c:any, idx:number) => (
          <View key={idx} style={{ paddingHorizontal:12, paddingVertical:8, borderRadius:10, backgroundColor:'rgba(255,255,255,0.08)' }}>
            <Text style={{ color:'#fff', fontWeight:'600', fontSize:14 }}>{c.tag || c.title}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}

// Luminance grey, then inverted: dark marks become light and white backgrounds go black
const LOGO_INVERT_MATRIX = [
  -0.2126, -0.7152, -0.0722, 0, 1,
  -0.2126, -0.7152, -0.0722, 0, 1,
  -0.2126, -0.7152, -0.0722, 0, 1,
  0, 0, 0, 1, 0,
];

function ProductionRow({ items, isMovie, onOpenEntity }: {
  items: Array<{id: number; name: string; logo?: string}>;
  isMovie: boolean;
  onOpenEntity: (kind: 'company' | 'network', id: number, name: string) => void;
}) {
  if (!items?.length) return null;

  return (
    <View>
      <SectionHeader title={isMovie ? "Production" : "Networks"} />
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingHorizontal: 12, gap: 10, paddingTop: 8 }}
      >
        {items.slice(0, 6).map((item) => (
          <Pressable
            key={String(item.id || item.name)}
            disabled={!item.id}
            onPress={() => onOpenEntity(isMovie ? 'company' : 'network', item.id, item.name)}
            accessibilityRole="button"
            accessibilityLabel={item.name}
            style={{
              paddingVertical: 10,
              paddingHorizontal: 14,
              // Dark tiles with light marks, as on macOS
              backgroundColor: 'rgba(255,255,255,0.07)',
              borderRadius: 12,
              alignItems: 'center',
              justifyContent: 'center',
              minHeight: 44,
            }}
          >
            {item.logo && FastImage ? (
              // TMDB logos are made for white backgrounds. Greyed and inverted (as on macOS)
              // they read as light marks on the dark tile, opaque logos included.
              <FilterImage
                source={{ uri: item.logo }}
                style={{ width: 72, height: 26, opacity: 0.9 }}
                resizeMode="contain"
                filters={[{ name: 'feColorMatrix', type: 'matrix', values: LOGO_INVERT_MATRIX }]}
              />
            ) : (
              <Text style={{ color: 'rgba(255,255,255,0.9)', fontSize: 13, fontWeight: '600' }}>{item.name}</Text>
            )}
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}

// Helper functions for formatting
function formatRuntime(minutes?: number): string | undefined {
  if (!minutes) return undefined;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h > 0 && m > 0) return `${h}h ${m}m`;
  if (h > 0) return `${h}h`;
  return `${m}m`;
}

/** Whole US dollars with thousands separators, as on macOS ("$180,000,000"). */
function formatCurrency(amount?: number): string | undefined {
  if (!amount || amount === 0) return undefined;
  return `$${Math.round(amount).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
}

/** "2 hr 11 min", as on macOS. */
function formatLongRuntime(minutes?: number): string | undefined {
  if (!minutes) return undefined;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h && m) return `${h} hr ${m} min`;
  return h ? `${h} hr` : `${m} min`;
}

/** Unique, non-empty language names for one stream type (2 audio, 3 subtitles). */
function streamLanguages(media: any, streamType: number): string[] {
  const streams: any[] = (Array.isArray(media?.Part) ? media.Part[0]?.Stream : undefined) || [];
  const seen = new Set<string>();
  const names: string[] = [];
  for (const st of streams) {
    if (st.streamType !== streamType) continue;
    const name = String(st.language || st.languageTag || st.displayTitle || '').trim();
    if (!name || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    names.push(name);
  }
  return names;
}

function formatLanguage(code?: string): string | undefined {
  if (!code) return undefined;
  const languages: Record<string, string> = {
    en: 'English', es: 'Spanish', fr: 'French', de: 'German', it: 'Italian',
    pt: 'Portuguese', ja: 'Japanese', ko: 'Korean', zh: 'Chinese', hi: 'Hindi',
    ar: 'Arabic', ru: 'Russian', nl: 'Dutch', sv: 'Swedish', pl: 'Polish',
    tr: 'Turkish', th: 'Thai', vi: 'Vietnamese', id: 'Indonesian', no: 'Norwegian',
    da: 'Danish', fi: 'Finnish', cs: 'Czech', el: 'Greek', he: 'Hebrew',
  };
  return languages[code] || code.toUpperCase();
}

function formatDate(dateStr?: string): string | undefined {
  if (!dateStr) return undefined;
  const date = new Date(dateStr);
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

function extractEditionTitle(media?: any[]): string | undefined {
  if (!media || media.length === 0) return undefined;
  // Priority 1: Use explicit editionTitle from API
  if (media[0]?.editionTitle) return media[0].editionTitle;
  // Priority 2: Parse from filename {edition-XXX} pattern
  const filePath = media[0]?.Part?.[0]?.file;
  if (filePath) {
    const match = filePath.match(/\{edition-([^}]+)\}/i);
    if (match) return match[1];
  }
  return undefined;
}

function DetailsTab({ meta, productionInfo, tmdbExtraInfo, tmdbCrew, episodeExtra, firstEpisodeMedia, onOpenEntity }: {
  meta: any;
  productionInfo?: Array<{id: number; name: string; logo?: string}>;
  tmdbExtraInfo?: {
    runtime?: number;
    status?: string;
    tagline?: string;
    budget?: number;
    revenue?: number;
    originalLanguage?: string;
    spokenLanguages?: string[];
    numberOfSeasons?: number;
    numberOfEpisodes?: number;
    creators?: string[];
    releaseDate?: string;
    firstAirDate?: string;
    lastAirDate?: string;
    voteAverage?: number;
    voteCount?: number;
  };
  tmdbCrew: DetailsCrewMember[];
  episodeExtra: EpisodeEnrichment | null;
  firstEpisodeMedia?: any[];
  onOpenEntity: (kind: 'company' | 'network', id: number, name: string) => void;
}) {
  const guids: string[] = Array.isArray(meta?.Guid) ? meta.Guid.map((g:any)=> String(g.id||'')) : [];
  const imdbId = guids.find(x=> x.startsWith('imdb://'))?.split('://')[1];
  const tmdbId = guids.find(x=> x.includes('tmdb://') || x.includes('themoviedb://'))?.split('://')[1];
  const isMovie = meta?.type === 'movie';
  const isShow = meta?.type === 'show';
  const isEpisode = meta?.type === 'episode';

  const plexNames = (list: any) => (Array.isArray(list) ? list.map((d: any) => String(d.tag || d.title || '')).filter(Boolean) : []);
  const unique = (names: string[]) => Array.from(new Set(names));
  const directors = plexNames(meta?.Director).length
    ? plexNames(meta?.Director)
    : unique(tmdbCrew.filter((c) => c.job === 'Director').map((c) => c.name));
  const writers = plexNames(meta?.Writer).length
    ? plexNames(meta?.Writer)
    : unique(tmdbCrew.filter((c) => /^(screenplay|writer|story|teleplay)$/i.test(String(c.job || ''))).map((c) => c.name));

  const genres: string[] = Array.isArray(meta?.Genre) ? meta.Genre.map((g: any) => g.tag).filter(Boolean) : [];
  const media = primaryMedia(meta, firstEpisodeMedia);
  const audioLanguages = streamLanguages(media, 2);
  const subtitleLanguages = streamLanguages(media, 3);
  const runtimeMinutes = tmdbExtraInfo?.runtime || (meta?.duration ? Math.floor(meta.duration / 60000) : undefined);
  const released = formatDate(isShow ? tmdbExtraInfo?.firstAirDate : tmdbExtraInfo?.releaseDate) || (meta?.year ? String(meta.year) : undefined);
  const imdbUrl = imdbId ? `https://www.imdb.com/title/${imdbId}` : undefined;
  const tmdbUrl = tmdbId ? `https://www.themoviedb.org/${isMovie ? 'movie' : 'tv'}/${tmdbId}` : undefined;
  const episodeAirDate = episodeExtra?.air_date || meta?.originallyAvailableAt;

  return (
    <View>
      {/* About: tagline, then a card with title, genres and overview, then the content rating */}
      <DetailsSectionHeading title="About" />
      {tmdbExtraInfo?.tagline ? (
        <Text style={styles.aboutTagline}>"{tmdbExtraInfo.tagline}"</Text>
      ) : null}
      <View style={styles.aboutCard}>
        <Text style={styles.aboutTitle}>{meta?.title || meta?.grandparentTitle}</Text>
        {genres.length ? <Text style={styles.aboutGenres}>{genres.join(', ').toUpperCase()}</Text> : null}
        {meta?.summary ? <Text style={styles.aboutOverview}>{meta.summary}</Text> : null}
      </View>
      {meta?.contentRating ? (
        <View style={styles.ratingTile}>
          <Ionicons name="checkmark-circle" size={22} color="#30D158" />
          <Text style={styles.ratingTileValue}>{meta.contentRating}</Text>
          <Text style={styles.ratingTileLabel}>Content rating</Text>
        </View>
      ) : null}

      {productionInfo && productionInfo.length > 0 && (
        <View style={{ marginTop: 12 }}>
          <ProductionRow items={productionInfo} isMovie={isMovie} onOpenEntity={onOpenEntity} />
        </View>
      )}

      <SectionHeader title="Information" />
      {isEpisode ? (
        <>
          <KeyValue k="Show" v={meta?.grandparentTitle} />
          <KeyValue k="Episode" v={meta?.parentIndex != null && meta?.index != null ? `Season ${meta.parentIndex}, Episode ${meta.index}` : undefined} />
          <KeyValue k="Air Date" v={formatDate(episodeAirDate)} />
          <KeyValue k="TMDB Rating" v={episodeExtra?.vote_average ? `${episodeExtra.vote_average.toFixed(1)}/10` : undefined} />
        </>
      ) : (
        <KeyValue k="Released" v={released} />
      )}
      <KeyValue k="Run Time" v={formatLongRuntime(isEpisode ? (episodeExtra?.runtime || runtimeMinutes) : runtimeMinutes)} />
      <KeyValue k="Rated" v={meta?.contentRating} />
      {!isEpisode && <KeyValue k="Status" v={tmdbExtraInfo?.status} />}
      {isShow && tmdbExtraInfo?.lastAirDate && tmdbExtraInfo?.status === 'Ended' && <KeyValue k="Last Aired" v={formatDate(tmdbExtraInfo?.lastAirDate)} />}
      {isShow && <KeyValue k="Seasons" v={tmdbExtraInfo?.numberOfSeasons ? String(tmdbExtraInfo.numberOfSeasons) : undefined} />}
      {isShow && <KeyValue k="Episodes" v={tmdbExtraInfo?.numberOfEpisodes ? String(tmdbExtraInfo.numberOfEpisodes) : undefined} />}
      {isMovie && <KeyValue k="Budget" v={formatCurrency(tmdbExtraInfo?.budget)} />}
      {isMovie && <KeyValue k="Box Office" v={formatCurrency(tmdbExtraInfo?.revenue)} />}
      {!isEpisode && <KeyValue k="Original Language" v={formatLanguage(tmdbExtraInfo?.originalLanguage)} />}
      <KeyValue k="Studio" v={meta?.studio} />
      {isShow && <KeyValue k="Created By" v={tmdbExtraInfo?.creators?.join(', ') || undefined} />}
      <KeyValue k="Directed By" v={(isEpisode && episodeExtra?.director) || directors.join(', ') || undefined} />
      <KeyValue k="Written By" v={(isEpisode && episodeExtra?.writer) || writers.join(', ') || undefined} />

      {tmdbExtraInfo?.originalLanguage || audioLanguages.length || subtitleLanguages.length ? (
        <>
          <SectionHeader title="Languages" />
          <KeyValue k="Original Audio" v={formatLanguage(tmdbExtraInfo?.originalLanguage)} />
          <KeyValue k="Audio" v={audioLanguages.join(', ') || undefined} />
          <KeyValue k="Subtitles" v={subtitleLanguages.join(', ') || undefined} />
        </>
      ) : null}

      <TechSpecs meta={meta} firstEpisodeMedia={firstEpisodeMedia} />

      <Collections meta={meta} />

      {imdbUrl || tmdbUrl ? (
        <>
          <SectionHeader title="External Links" />
          <View style={styles.linkRow}>
            {imdbUrl ? (
              <Pressable onPress={() => Linking.openURL(imdbUrl)} style={styles.linkButton} accessibilityRole="link">
                <Image source={RATING_IMAGES.imdb} style={{ width: 30, height: 15 }} resizeMode="contain" />
                <Text style={styles.linkText}>View on IMDb</Text>
              </Pressable>
            ) : null}
            {tmdbUrl ? (
              <Pressable onPress={() => Linking.openURL(tmdbUrl)} style={styles.linkButton} accessibilityRole="link">
                <Ionicons name="open-outline" size={16} color="#fff" />
                <Text style={styles.linkText}>View on TMDB</Text>
              </Pressable>
            ) : null}
          </View>
        </>
      ) : null}
      <View style={{ height:12 }} />
    </View>
  );
}

const styles = StyleSheet.create({
  heroRating: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  aboutTagline: { color: 'rgba(255,255,255,0.7)', fontSize: 16, fontStyle: 'italic', marginHorizontal: 16, marginBottom: 12 },
  aboutCard: { marginHorizontal: 16, padding: 16, borderRadius: 12, backgroundColor: 'rgba(255,255,255,0.08)', gap: 10 },
  aboutTitle: { color: '#fff', fontSize: 18, fontWeight: '600' },
  aboutGenres: { color: 'rgba(255,255,255,0.6)', fontSize: 12, fontWeight: '500', letterSpacing: 0.3 },
  aboutOverview: { color: 'rgba(255,255,255,0.85)', fontSize: 15, lineHeight: 21 },
  ratingTile: {
    marginHorizontal: 16,
    marginTop: 10,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.08)',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  ratingTileValue: { color: '#fff', fontSize: 20, fontWeight: '700' },
  ratingTileLabel: { color: 'rgba(255,255,255,0.5)', fontSize: 13, marginLeft: 'auto' },
  linkRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, paddingHorizontal: 16 },
  linkButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    height: 44,
    paddingHorizontal: 14,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  linkText: { color: '#fff', fontSize: 15, fontWeight: '600' },
  heroRatingText: { color: 'rgba(255,255,255,0.86)', fontSize: 12, fontWeight: '600' },
  heroDot: { color: 'rgba(255,255,255,0.4)', fontSize: 12 },
  // One white primary button per screen (macOS rule); secondary buttons are translucent grey
  playButton: {
    height: 50,
    borderRadius: 12,
    backgroundColor: '#fff',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  playButtonDisabled: {
    minHeight: 50,
    paddingVertical: 8,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.08)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  playButtonText: { color: '#000', fontSize: 17, fontWeight: '600' },
  secondaryButton: {
    height: 50,
    borderRadius: 12,
    backgroundColor: 'rgba(255,255,255,0.12)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  secondaryButtonText: { color: '#fff', fontSize: 17, fontWeight: '600' },
  resumeRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: -2 },
  resumeTrack: { flex: 1, height: 3, borderRadius: 2, backgroundColor: 'rgba(255,255,255,0.18)', overflow: 'hidden' },
  resumeFill: { height: '100%', borderRadius: 2 },
  resumeText: { fontSize: 12 },
});
