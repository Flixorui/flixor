import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { View, Text, TextInput, Pressable, ActivityIndicator, ScrollView, StyleSheet, Animated, Keyboard, InteractionManager } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import FastImage from '@d11/react-native-fast-image';
import Row from '../components/Row';
import { useNavigation } from '@react-navigation/native';
import { TopBarStore } from '../components/TopBarStore';
import { useFlixor } from '../core/FlixorContext';
import {
  searchPlex,
  searchTmdb,
  searchPeople,
  searchAddons,
  getTrendingForSearch,
  fetchPreferredBackdropsForSearch,
  discoverByGenre,
  SearchResult,
  PersonResult,
  RowItem,
  GENRE_MAP,
} from '../core/SearchData';
import { useAppSettings } from '../hooks/useAppSettings';
import { useTheme } from '../hooks/useTheme';
import { useAppMode } from '../core/AppMode';
import { RECENT_SEARCHES_LIMIT } from '../core/SettingsData';
import type { PersonCredit } from '../core/DetailsData';
import RecentSearches from '../components/search/RecentSearches';
import PeopleRow from '../components/search/PeopleRow';
import DiscoverPanel from '../components/search/DiscoverPanel';
import Chip from '../components/collections/Chip';
import PersonModal from '../components/PersonModal';

type GenreRow = {
  title: string;
  items: SearchResult[];
};

// Persistent store for trending data - survives component unmounts
const persistentStore = {
  trending: null as RowItem[] | null,
  lastFetchTime: 0,
  CACHE_TTL: 5 * 60 * 1000, // 5 minutes
};

// Image preload cap - limit concurrent preloads
const IMAGE_PRELOAD_CAP = 6;

// A query still in the field this long is worth remembering
const RECENT_SAVE_DELAY_MS = 2500;

interface SearchProps {
  isTab?: boolean;
  nativeSearchText?: string; // Text from iOS native search bar (older iOS)
  hideCustomSearchBar?: boolean; // Hide custom search bar (iOS with native tabs)
}

export default function Search({ isTab = false, nativeSearchText, hideCustomSearchBar = false }: SearchProps) {
  const useNativeSearchBar = nativeSearchText !== undefined;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { isConnected } = useFlixor();
  const { isStremioOnly } = useAppMode();
  const { settings, updateSetting } = useAppSettings();
  const theme = useTheme();
  // Stremio-only mode has no Plex server to connect to
  const canSearch = isConnected || isStremioOnly;
  const addonSearchEnabled =
    settings.stremioPlaybackEnabled && settings.stremioCatalogSearchEnabled && !settings.discoveryDisabled;
  const [query, setQuery] = useState('');
  const [plexResults, setPlexResults] = useState<SearchResult[]>([]);
  const [tmdbMovies, setTmdbMovies] = useState<SearchResult[]>([]);
  const [tmdbShows, setTmdbShows] = useState<SearchResult[]>([]);
  const [addonResults, setAddonResults] = useState<SearchResult[]>([]);
  const [people, setPeople] = useState<PersonResult[]>([]);
  const [idleMode, setIdleMode] = useState<'recommended' | 'discover'>('recommended');
  const [selectedPerson, setSelectedPerson] = useState<PersonResult | null>(null);
  // Initialize from persistent store for instant render
  const [trending, setTrending] = useState<RowItem[]>(() => persistentStore.trending || []);
  const [genreRows, setGenreRows] = useState<GenreRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchMode, setSearchMode] = useState<'idle' | 'results'>('idle');
  const [trendingLoaded, setTrendingLoaded] = useState(!!persistentStore.trending);
  const searchTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);
  const inputRef = useRef<TextInput>(null);
  const fadeAnim = useRef(new Animated.Value(persistentStore.trending ? 1 : 0)).current;
  const isMounted = useRef(true);
  // Bumped per search so a slow earlier search can't overwrite a newer one
  const searchGeneration = useRef(0);
  const recentSaveTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);
  const recentSearchesRef = useRef(settings.recentSearches);
  recentSearchesRef.current = settings.recentSearches;
  // updateSetting changes with every settings update. Going through a ref keeps the
  // callbacks below stable, so saving a recent can't re-fire the native search bar effect.
  const updateSettingRef = useRef(updateSetting);
  updateSettingRef.current = updateSetting;

  useEffect(() => {
    isMounted.current = true;

    // Hide TopBar when Search is opened as modal (not tab)
    if (!isTab) {
      TopBarStore.setVisible(false);
    }

    const now = Date.now();
    const cacheValid = persistentStore.trending && (now - persistentStore.lastFetchTime < persistentStore.CACHE_TTL);

    // Load recommended/trending for empty state (only if TMDB is enabled)
    if (canSearch && !cacheValid && settings.includeTmdbInSearch) {
      // Defer data fetch to avoid blocking UI
      InteractionManager.runAfterInteractions(() => {
        if (!isMounted.current) return;

        (async () => {
          try {
            const combined = await getTrendingForSearch();
            if (!isMounted.current) return;

            // Update persistent store
            persistentStore.trending = combined;
            persistentStore.lastFetchTime = Date.now();

            setTrending(combined);
            setTrendingLoaded(true);

            // Preload first N images for instant display
            const imagesToPreload = combined
              .slice(0, IMAGE_PRELOAD_CAP)
              .filter(item => item.image)
              .map(item => ({ uri: item.image! }));

            if (imagesToPreload.length > 0) {
              FastImage.preload(imagesToPreload);
            }

            // Fetch preferred backdrops with titles asynchronously (lower priority)
            fetchPreferredBackdropsForSearch(combined).then((backdrops) => {
              if (!isMounted.current) return;
              if (Object.keys(backdrops).length > 0) {
                const updatedTrending = combined.map((item) => ({
                  ...item,
                  image: backdrops[item.id] || item.image,
                }));

                // Update persistent store with new backdrops
                persistentStore.trending = updatedTrending;
                setTrending(updatedTrending);

                // Preload new backdrop images
                const newImagesToPreload = updatedTrending
                  .slice(0, IMAGE_PRELOAD_CAP)
                  .filter(item => item.image && backdrops[item.id])
                  .map(item => ({ uri: item.image! }));

                if (newImagesToPreload.length > 0) {
                  FastImage.preload(newImagesToPreload);
                }
              }
            });
          } catch (e) {
            console.log('[Search] Failed to load trending:', e);
          }
        })();
      });
    } else if (persistentStore.trending) {
      setTrendingLoaded(true);
    }

    // Fade in animation
    if (!persistentStore.trending) {
      Animated.timing(fadeAnim, { toValue: 1, duration: 200, useNativeDriver: true }).start();
    }

    // Auto-focus input (only for custom search bar)
    if (!hideCustomSearchBar) {
      setTimeout(() => inputRef.current?.focus(), 100);
    }

    // Cleanup on unmount
    return () => {
      isMounted.current = false;
      // Restore TopBar only when used as modal
      if (!isTab) {
        TopBarStore.setVisible(true);
      }
      // Clear search timeout
      if (searchTimeout.current) {
        clearTimeout(searchTimeout.current);
      }
      if (recentSaveTimeout.current) {
        clearTimeout(recentSaveTimeout.current);
      }
    };
  }, [canSearch, isTab, settings.includeTmdbInSearch, hideCustomSearchBar]);

  const rememberSearch = useCallback((text: string) => {
    if (recentSaveTimeout.current) clearTimeout(recentSaveTimeout.current);
    const normalized = text.trim();
    if (normalized.length < 2) return;
    const lower = normalized.toLowerCase();
    const rest = recentSearchesRef.current.filter((item) => item.toLowerCase() !== lower);
    const next = [normalized, ...rest].slice(0, RECENT_SEARCHES_LIMIT);
    recentSearchesRef.current = next;
    updateSettingRef.current('recentSearches', next);
  }, []);

  const removeRecentSearch = useCallback((text: string) => {
    const next = recentSearchesRef.current.filter((item) => item !== text);
    recentSearchesRef.current = next;
    updateSettingRef.current('recentSearches', next);
  }, []);

  const clearRecentSearches = useCallback(() => {
    recentSearchesRef.current = [];
    updateSettingRef.current('recentSearches', []);
  }, []);

  const performSearch = useCallback(async (q: string) => {
    if (!canSearch || !q.trim()) return;

    const generation = ++searchGeneration.current;
    const isCurrent = () => generation === searchGeneration.current;

    setLoading(true);
    setSearchMode('results');

    try {
      const [plexRes, tmdbRes, addonRes, peopleRes] = await Promise.all([
        isStremioOnly ? Promise.resolve<SearchResult[]>([]) : searchPlex(q),
        settings.includeTmdbInSearch ? searchTmdb(q) : Promise.resolve({ movies: [] as SearchResult[], shows: [] as SearchResult[] }),
        addonSearchEnabled ? searchAddons(q) : Promise.resolve<SearchResult[]>([]),
        settings.includeTmdbInSearch ? searchPeople(q) : Promise.resolve<PersonResult[]>([]),
      ]);
      if (!isCurrent()) return;

      setPlexResults(plexRes);
      setTmdbMovies(tmdbRes.movies);
      setTmdbShows(tmdbRes.shows);
      setPeople(peopleRes);

      // Titles already shown from TMDB don't repeat under the addon row
      const shown = new Set([...tmdbRes.movies, ...tmdbRes.shows].map((item) => item.id));
      setAddonResults(addonRes.filter((item) => !shown.has(item.id)));

      if (settings.includeTmdbInSearch) {
        // Collect genre IDs from TMDB results
        const allGenreIds = new Set<number>();
        [...tmdbRes.movies, ...tmdbRes.shows].forEach((item) => {
          (item.genreIds || []).forEach((gid: number) => allGenreIds.add(gid));
        });

        // Fetch genre-based recommendations
        const genreRowsData: GenreRow[] = [];
        const topGenres = Array.from(allGenreIds).slice(0, 3);

        for (const genreId of topGenres) {
          const genreName = GENRE_MAP[genreId];
          if (!genreName) continue;

          try {
            const items = await discoverByGenre(genreId);
            if (items.length > 0) {
              genreRowsData.push({
                title: genreName,
                items,
              });
            }
          } catch (e) {
            console.log(`[Search] Failed to fetch genre ${genreName}:`, e);
          }
        }

        if (isCurrent()) setGenreRows(genreRowsData);
      } else {
        setGenreRows([]);
      }
    } finally {
      if (isCurrent()) setLoading(false);
    }
  }, [canSearch, isStremioOnly, addonSearchEnabled, settings.includeTmdbInSearch]);

  const handleQueryChange = useCallback((text: string) => {
    setQuery(text);

    if (searchTimeout.current) clearTimeout(searchTimeout.current);

    if (recentSaveTimeout.current) clearTimeout(recentSaveTimeout.current);

    if (text.trim()) {
      searchTimeout.current = setTimeout(() => performSearch(text), 300);
      recentSaveTimeout.current = setTimeout(() => rememberSearch(text), RECENT_SAVE_DELAY_MS);
    } else {
      searchGeneration.current += 1;
      setLoading(false);
      setSearchMode('idle');
      setPlexResults([]);
      setTmdbMovies([]);
      setTmdbShows([]);
      setAddonResults([]);
      setPeople([]);
      setGenreRows([]);
    }
  }, [performSearch, rememberSearch]);

  const runRecentSearch = useCallback((text: string) => {
    if (searchTimeout.current) clearTimeout(searchTimeout.current);
    setQuery(text);
    rememberSearch(text);
    performSearch(text);
  }, [performSearch, rememberSearch]);

  // Handle native search bar text changes (iOS 26+)
  useEffect(() => {
    if (useNativeSearchBar && nativeSearchText !== undefined) {
      handleQueryChange(nativeSearchText);
    }
  }, [nativeSearchText, useNativeSearchBar, handleQueryChange]);

  const handleResultPress = (result: SearchResult | RowItem) => {
    rememberSearch(query);
    const id = result.id;
    if (id.startsWith('plex:')) {
      const rk = id.split(':')[1];
      nav.navigate('Details', { type: 'plex', ratingKey: rk });
    } else if (id.startsWith('tmdb:')) {
      const [, media, tmdbId] = id.split(':');
      nav.navigate('Details', { type: 'tmdb', mediaType: media, id: tmdbId });
    }
  };

  const handleCreditPress = (credit: PersonCredit) => {
    rememberSearch(query);
    nav.navigate('Details', { type: 'tmdb', mediaType: credit.mediaType, id: String(credit.id) });
  };

  const idleModePicker = settings.includeTmdbInSearch ? (
    <View style={styles.idleModes}>
      <Chip label="Recommended" active={idleMode === 'recommended'} onPress={() => setIdleMode('recommended')} />
      <Chip label="Discover" active={idleMode === 'discover'} onPress={() => setIdleMode('discover')} />
    </View>
  ) : null;

  // Auth headers no longer needed - image URLs include token

  return (
    <View style={{ flex: 1, backgroundColor: theme.background }}>
      {/* Full screen gradients */}
      <LinearGradient
        colors={[ '#0a0a0a', '#0f0f10', '#0b0c0d' ]}
        start={{ x: 0.5, y: 0 }} end={{ x: 0.5, y: 1 }}
        style={StyleSheet.absoluteFillObject}
      />
      <LinearGradient
        colors={[ 'rgba(122,22,18,0.20)', 'rgba(122,22,18,0.08)', 'rgba(122,22,18,0.0)' ]}
        start={{ x: 0.0, y: 1.0 }} end={{ x: 0.45, y: 0.35 }}
        style={StyleSheet.absoluteFillObject}
      />
      <LinearGradient
        colors={[ 'rgba(20,76,84,0.18)', 'rgba(20,76,84,0.08)', 'rgba(20,76,84,0.0)' ]}
        start={{ x: 1.0, y: 0.0 }} end={{ x: 0.55, y: 0.45 }}
        style={StyleSheet.absoluteFillObject}
      />

      <SafeAreaView style={{ flex: 1 }} edges={hideCustomSearchBar ? [] : ['top']}>
        <Animated.View style={{ flex: 1, opacity: fadeAnim }}>
          {/* Custom Search Bar - hidden on iOS with native tabs */}
          {!hideCustomSearchBar && (
            <View style={styles.searchBar}>
              <Ionicons name="search" size={20} color="#888" style={{ marginRight: 12 }} />
              <TextInput
                ref={inputRef}
                value={query}
                onChangeText={handleQueryChange}
                placeholder="Search for movies, shows..."
                placeholderTextColor="#666"
                style={styles.input}
                returnKeyType="search"
                autoCapitalize="none"
                autoCorrect={false}
                onSubmitEditing={() => rememberSearch(query)}
              />
              {query ? (
                <Pressable onPress={() => handleQueryChange('')} style={{ padding: 4 }}>
                  <Ionicons name="close-circle" size={20} color="#888" />
                </Pressable>
              ) : null}
              {!isTab && (
                <Pressable onPress={() => nav.goBack()} style={{ marginLeft: 12 }}>
                  <Text style={{ color: '#fff', fontWeight: '600' }}>Cancel</Text>
                </Pressable>
              )}
            </View>
          )}

          {/* Discover has its own paged grid, so it replaces the scroll view */}
          {searchMode === 'idle' && idleMode === 'discover' && settings.includeTmdbInSearch ? (
            <DiscoverPanel onPressItem={handleResultPress} headerAccessory={idleModePicker} />
          ) : (
          <ScrollView
            style={{ flex: 1 }}
            contentContainerStyle={{ paddingBottom: 80 }}
            contentInsetAdjustmentBehavior="automatic"
            keyboardShouldPersistTaps="handled"
            keyboardDismissMode="on-drag"
          >
            {searchMode === 'idle' ? (
              <RecentSearches
                searches={settings.recentSearches}
                onSelect={runRecentSearch}
                onRemove={removeRecentSearch}
                onClear={clearRecentSearches}
              />
            ) : null}

            {searchMode === 'idle' ? idleModePicker : null}

            {searchMode === 'idle' && settings.includeTmdbInSearch ? (
              <View style={{ paddingTop: 8 }}>
                <Text style={{ color: '#fff', fontSize: 20, fontWeight: '800', marginHorizontal: 16, marginBottom: 16 }}>Recommended TV Shows & Movies</Text>
                {/* Loading skeleton when trending not loaded */}
                {!trendingLoaded && trending.length === 0 ? (
                  <View style={{ alignItems: 'center', paddingTop: 20 }}>
                    <ActivityIndicator color="#fff" size="small" />
                  </View>
                ) : null}
                {/* Vertical list of recommended items - progressive loading */}
                {trending.map((item, i) => (
                  <Pressable key={item.id} onPress={() => handleResultPress(item)} style={styles.recommendCard}>
                    <View style={styles.recommendImage}>
                      {item.image ? (
                        <FastImage
                          source={{
                            uri: item.image,
                            priority: i < 3 ? FastImage.priority.high : FastImage.priority.normal,
                            cache: FastImage.cacheControl.immutable,
                          }}
                          style={{ width: '100%', height: '100%' }}
                          resizeMode={FastImage.resizeMode.cover}
                        />
                      ) : (
                        <View style={{ width: '100%', height: '100%', backgroundColor: '#1a1a1a' }} />
                      )}
                      {/* "Recently added" badge for some items */}
                      {i < 3 ? (
                        <View style={{ position: 'absolute', bottom: 8, left: 8, backgroundColor: theme.accent, paddingHorizontal: 8, paddingVertical: 4, borderRadius: 4 }}>
                          <Text style={{ color: '#fff', fontSize: 11, fontWeight: '700' }}>Recently added</Text>
                        </View>
                      ) : null}
                      {/* TOP 10 badge for top items */}
                      {i < 2 ? (
                        <View style={{ position: 'absolute', top: 8, right: 8, backgroundColor: theme.accent, width: 36, height: 36, borderRadius: 4, alignItems: 'center', justifyContent: 'center' }}>
                          <Text style={{ color: '#fff', fontSize: 10, fontWeight: '700' }}>TOP</Text>
                          <Text style={{ color: '#fff', fontSize: 16, fontWeight: '900' }}>10</Text>
                        </View>
                      ) : null}
                    </View>
                    <View style={{ flex: 1, marginLeft: 16, justifyContent: 'center' }}>
                      <Text style={{ color: '#fff', fontWeight: '700', fontSize: 16 }}>{item.title}</Text>
                      {item.year ? <Text style={{ color: '#aaa', fontSize: 13, marginTop: 4 }}>{item.year}</Text> : null}
                    </View>
                    {/* Play button */}
                    <View style={{ width: 44, height: 44, borderRadius: 22, borderWidth: 2, borderColor: '#fff', alignItems: 'center', justifyContent: 'center' }}>
                      <Ionicons name="play" size={20} color="#fff" style={{ marginLeft: 2 }} />
                    </View>
                  </Pressable>
                ))}
              </View>
            ) : null}

            {searchMode === 'results' ? (
              loading ? (
                <View style={{ alignItems: 'center', paddingTop: 40 }}>
                  <ActivityIndicator color="#fff" size="large" />
                </View>
              ) : (
                <View style={{ paddingTop: 8 }}>
                  {/* A recent search can run with the native search bar still empty */}
                  {useNativeSearchBar && !nativeSearchText ? (
                    <Pressable onPress={() => handleQueryChange('')} style={styles.clearResults}>
                      <Ionicons name="close-circle" size={16} color={theme.textTertiary} />
                      <Text style={{ color: theme.textSecondary, fontWeight: '600', marginLeft: 6 }} numberOfLines={1}>
                        Clear "{query}"
                      </Text>
                    </Pressable>
                  ) : null}

                  {/* Plex Results - Grid (Prominent) */}
                  {plexResults.length > 0 ? (
                    <>
                      <Text style={{ color: '#fff', fontSize: 22, fontWeight: '700', marginHorizontal: 16, marginBottom: 16, marginTop: 8 }}>Results from Your Plex</Text>

                      {/* Plex results grid - show first 4 results */}
                      <View style={styles.topResultsGrid}>
                        {plexResults
                          .slice(0, 4)
                          .map((result, i) => (
                            <Pressable key={result.id} onPress={() => handleResultPress(result)} style={styles.topResultCard}>
                              <View style={styles.topResultImage}>
                                {result.image ? (
                                  <FastImage
                                    source={{
                                      uri: result.image,
                                      priority: FastImage.priority.high,
                                      cache: FastImage.cacheControl.immutable,
                                    }}
                                    style={{ width: '100%', height: '100%' }}
                                    resizeMode={FastImage.resizeMode.cover}
                                  />
                                ) : (
                                  <View style={{ width: '100%', height: '100%', backgroundColor: '#1a1a1a' }} />
                                )}
                              </View>
                              <Text style={{ color: '#fff', fontSize: 13, fontWeight: '600', marginTop: 6 }} numberOfLines={1}>{result.title}</Text>
                              {(result.year || result.editionTitle) && (
                                <Text style={{ color: '#888', fontSize: 11, marginTop: 2 }} numberOfLines={1}>
                                  {result.year}{result.year && result.editionTitle ? ' · ' : ''}{result.editionTitle}
                                </Text>
                              )}
                            </Pressable>
                          ))}
                      </View>

                      {/* Additional Plex results as horizontal row */}
                      {plexResults.length > 4 ? (
                        <View style={{ marginTop: 8 }}>
                          <Row
                            title="More from Your Plex"
                            items={plexResults.slice(4).map(r => ({ id: r.id, title: r.title, image: r.image }))}
                            getImageUri={(it) => it.image}
                            getTitle={(it) => it.title}
                                                        onItemPress={handleResultPress}
                          />
                        </View>
                      ) : null}
                    </>
                  ) : null}

                  {/* Top Results Section - Horizontal Rows */}
                  {tmdbMovies.length > 0 ? (
                    <View style={{ marginTop: plexResults.length > 0 ? 16 : 8 }}>
                      <Row
                        title="Top Results"
                        items={tmdbMovies.slice(0, 10).map(r => ({ id: r.id, title: r.title, image: r.image }))}
                        getImageUri={(it) => it.image}
                        getTitle={(it) => it.title}
                                                onItemPress={handleResultPress}
                      />
                    </View>
                  ) : null}

                  {tmdbShows.length > 0 ? (
                    <Row
                      title="TV Shows"
                      items={tmdbShows.slice(0, 10).map(r => ({ id: r.id, title: r.title, image: r.image }))}
                      getImageUri={(it) => it.image}
                      getTitle={(it) => it.title}
                                            onItemPress={handleResultPress}
                    />
                  ) : null}

                  {addonResults.length > 0 ? (
                    <Row
                      title="From Your Addons"
                      items={addonResults.slice(0, 20).map(r => ({ id: r.id, title: r.title, image: r.image }))}
                      getImageUri={(it) => it.image}
                      getTitle={(it) => it.title}
                      onItemPress={handleResultPress}
                    />
                  ) : null}

                  <PeopleRow people={people} onPress={setSelectedPerson} />

                  {/* Dynamic Genre Rows */}
                  {genreRows.map((genreRow, idx) => (
                    <Row
                      key={idx}
                      title={genreRow.title}
                      items={genreRow.items.map(r => ({ id: r.id, title: r.title, image: r.image }))}
                      getImageUri={(it) => it.image}
                      getTitle={(it) => it.title}
                                            onItemPress={handleResultPress}
                    />
                  ))}

                  {!loading && plexResults.length === 0 && tmdbMovies.length === 0 && tmdbShows.length === 0 && addonResults.length === 0 && people.length === 0 ? (
                    <Text style={{ color: '#888', textAlign: 'center', marginTop: 40 }}>No results found for "{query}"</Text>
                  ) : null}
                </View>
              )
            ) : null}
          </ScrollView>
          )}
        </Animated.View>
      </SafeAreaView>

      <PersonModal
        visible={selectedPerson !== null}
        personId={selectedPerson?.id ?? null}
        personName={selectedPerson?.name}
        onClose={() => setSelectedPerson(null)}
        onSelectCredit={handleCreditPress}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  idleModes: {
    flexDirection: 'row',
    marginHorizontal: 16,
    marginTop: 16,
  },
  clearResults: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginBottom: 8,
    paddingVertical: 6,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(48,48,50,0.98)',
    marginHorizontal: 16,
    marginTop: 12,
    marginBottom: 8,
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderRadius: 10,
  },
  input: {
    flex: 1,
    color: '#fff',
    fontSize: 17,
    padding: 0,
  },
  recommendCard: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: 16,
    marginBottom: 8,
    paddingVertical: 8,
  },
  recommendImage: {
    width: 200,
    height: 112,
    borderRadius: 8,
    backgroundColor: '#1a1a1a',
    overflow: 'hidden',
  },
  topResultsGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 12,
    gap: 8,
  },
  topResultCard: {
    width: '48.5%',
    marginBottom: 8,
  },
  topResultImage: {
    width: '100%',
    aspectRatio: 2/3,
    borderRadius: 6,
    backgroundColor: '#1a1a1a',
    overflow: 'hidden',
  },
});
