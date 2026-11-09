import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import LandscapeCard from '@/components/LandscapeCard';
import SearchDiscover from '@/components/SearchDiscover';
import SearchInput from '@/components/SearchInput';
import SearchRecent from '@/components/SearchRecent';
import SearchResults, { type SearchResult } from '@/components/SearchResults';
import { appToast } from '@/components/cards/cardActions';
import { detailsPath, resolveDetailsId, stremioItemToCard } from '@/components/cards/cardMedia';
import type { CardItem } from '@/components/cards/cardTypes';
import { apiClient } from '@/services/api';
import { plexBackendSearch } from '@/services/plex_backend';
import { filterEnabledLibraries, getAllCollections, getPlexLibraries } from '@/services/plexCollections';
import { tmdbImage, tmdbSearchMulti, tmdbTrending } from '@/services/tmdb';
import { getSettings, saveSettings, useSettings, type SearchIdleTab } from '@/state/settings';
import { searchCatalogs } from '@/stremio';

const RECENT_LIMIT = 15;
const DEBOUNCE_MS = 300;

function normalize(text: string) {
  return text.trim().replace(/\s+/g, ' ');
}

function recordRecentSearch(text: string) {
  const normalized = normalize(text);
  if (!normalized) return;
  const current = getSettings().recentSearches;
  const next = [normalized, ...current.filter((entry) => entry.toLowerCase() !== normalized.toLowerCase())].slice(0, RECENT_LIMIT);
  saveSettings({ recentSearches: next });
}

async function searchPlex(query: string): Promise<SearchResult[]> {
  const [movies, shows]: any[] = await Promise.all([plexBackendSearch(query, 1), plexBackendSearch(query, 2)]);
  const toResult = (type: 'movie' | 'tv') => (item: any): SearchResult => ({
    id: `plex:${item.ratingKey}`,
    title: item.title,
    type,
    image: apiClient.getPlexImageNoToken(item.thumb || item.art || ''),
    year: item.year ? String(item.year) : undefined,
    overview: item.summary,
    available: true,
  });
  return [
    ...(movies?.MediaContainer?.Metadata || []).slice(0, 10).map(toResult('movie')),
    ...(shows?.MediaContainer?.Metadata || []).slice(0, 10).map(toResult('tv')),
  ];
}

async function searchCollections(query: string): Promise<SearchResult[]> {
  const libraries = filterEnabledLibraries(await getPlexLibraries(), getSettings().enabledLibraryKeys);
  const wanted = query.toLowerCase();
  return (await getAllCollections(libraries))
    .filter((collection) => collection.title.toLowerCase().includes(wanted))
    .slice(0, 12)
    .map((collection) => ({ id: collection.ratingKey, title: collection.title, type: 'collection', image: collection.image }));
}

async function searchTmdb(query: string): Promise<SearchResult[]> {
  const res: any = await tmdbSearchMulti('', query);
  return (res?.results || []).slice(0, 30).flatMap((item: any): SearchResult[] => {
    if (item.media_type === 'person') {
      return [{
        id: String(item.id),
        title: item.name,
        type: 'person',
        image: tmdbImage(item.profile_path, 'w500'),
        subtitle: item.known_for_department,
      }];
    }
    if (item.media_type !== 'movie' && item.media_type !== 'tv') return [];
    return [{
      id: `tmdb:${item.media_type}:${item.id}`,
      title: item.title || item.name,
      type: item.media_type,
      image: tmdbImage(item.poster_path, 'w500') || tmdbImage(item.backdrop_path, 'w780'),
      year: String(item.release_date || item.first_air_date || '').slice(0, 4) || undefined,
      overview: item.overview,
      available: false,
    }];
  });
}

async function searchAddons(query: string): Promise<SearchResult[]> {
  const entries = await searchCatalogs(query);
  return entries.map((entry) => {
    const card = stremioItemToCard(entry);
    return {
      id: card.id,
      title: card.title,
      type: entry.type === 'series' ? 'tv' : 'movie',
      image: card.image,
      year: entry.year ? String(entry.year) : undefined,
      addon: 'Addons',
    };
  });
}

/** Keeps the first result per title, in source order: Plex, TMDB, then addons. */
function mergeResults(sections: SearchResult[][]) {
  const titles = new Set<string>();
  const ids = new Set<string>();
  const merged: SearchResult[] = [];
  for (const result of sections.flat()) {
    if (ids.has(`${result.type}:${result.id}`)) continue;
    if (result.type === 'movie' || result.type === 'tv') {
      const key = result.title.toLowerCase();
      if (titles.has(key)) continue;
      titles.add(key);
    }
    ids.add(`${result.type}:${result.id}`);
    merged.push(result);
  }
  return merged;
}

export default function Search() {
  const nav = useNavigate();
  const settings = useSettings();
  const [searchParams, setSearchParams] = useSearchParams();
  const [query, setQuery] = useState(searchParams.get('q') || '');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [activeQuery, setActiveQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const [trending, setTrending] = useState<CardItem[]>([]);
  const requestId = useRef(0);

  const tmdbAllowed = settings.discoveryDisabled !== true && settings.includeTmdbInSearch !== false;
  const addonsAllowed = settings.discoveryDisabled !== true && settings.stremioCatalogSearchEnabled;
  const idleTab: SearchIdleTab = tmdbAllowed ? settings.searchIdleTab : 'explore';

  useEffect(() => {
    if (!tmdbAllowed) {
      setTrending([]);
      return;
    }
    let alive = true;
    Promise.all([tmdbTrending('', 'movie', 'week'), tmdbTrending('', 'tv', 'week')])
      .then(([movies, shows]: any[]) => {
        if (!alive) return;
        const toCard = (media: 'movie' | 'tv') => (r: any): CardItem => ({
          id: `tmdb:${media}:${r.id}`,
          title: r.title || r.name,
          image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500'),
          backdrop: tmdbImage(r.backdrop_path, 'w780'),
          mediaType: media === 'movie' ? 'movie' : 'show',
          year: String(r.release_date || r.first_air_date || '').slice(0, 4) || undefined,
        });
        const movieCards: CardItem[] = (movies?.results || []).slice(0, 6).map(toCard('movie'));
        const showCards: CardItem[] = (shows?.results || []).slice(0, 6).map(toCard('tv'));
        const interleaved = Array.from({ length: Math.max(movieCards.length, showCards.length) }).flatMap((_, i) => [movieCards[i], showCards[i]].filter(Boolean));
        setTrending(interleaved.slice(0, 12));
      })
      .catch((err) => console.error('Failed to load trending content:', err));
    return () => {
      alive = false;
    };
  }, [tmdbAllowed]);

  const runSearch = useCallback(
    async (text: string) => {
      const id = ++requestId.current;
      const s = getSettings();
      const plexReady = !!s.plexBaseUrl && !!s.plexToken;
      setLoading(true);
      setFailed(false);
      setActiveQuery(text);

      const sources: Array<Promise<SearchResult[]>> = [];
      if (plexReady) sources.push(searchPlex(text), searchCollections(text));
      if (tmdbAllowed) sources.push(searchTmdb(text));
      if (addonsAllowed) sources.push(searchAddons(text));

      const sections: SearchResult[][] = sources.map(() => []);
      let settled = 0;
      let failures = 0;
      await Promise.all(
        sources.map((source, index) =>
          source
            .then((found) => {
              sections[index] = found;
            })
            .catch(() => {
              failures += 1;
            })
            .finally(() => {
              settled += 1;
              if (id !== requestId.current) return;
              setResults(mergeResults(sections));
              if (settled === sources.length) {
                setLoading(false);
                setFailed(failures === sources.length && sources.length > 0);
              }
            }),
        ),
      );
      if (sources.length === 0 && id === requestId.current) {
        setResults([]);
        setLoading(false);
      }
    },
    [tmdbAllowed, addonsAllowed],
  );

  useEffect(() => {
    const normalized = normalize(query);
    setSearchParams(normalized ? { q: normalized } : {}, { replace: true });
    if (!normalized) {
      requestId.current += 1;
      setActiveQuery('');
      setResults([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    const timer = window.setTimeout(() => runSearch(normalized), DEBOUNCE_MS);
    return () => window.clearTimeout(timer);
    // setSearchParams changes identity on every navigation.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, runSearch]);

  const openCard = async (item: CardItem) => {
    if (normalize(query)) recordRecentSearch(query);
    const id = await resolveDetailsId(item);
    if (id) nav(detailsPath(id));
    else appToast(`Could not find details for ${item.title}`);
  };

  const handleResult = (item: SearchResult) => {
    if (item.type === 'person') {
      recordRecentSearch(query);
      nav(`/person/${encodeURIComponent(item.id)}`);
    } else if (item.type === 'collection') {
      recordRecentSearch(query);
      nav(`/library?collection=${encodeURIComponent(item.id)}`);
    } else {
      openCard({ id: item.id, title: item.title, year: item.year });
    }
  };

  const searching = !!normalize(query);
  const recent = settings.recentSearches;

  return (
    <div className="min-h-screen relative">
      <div className="fixed inset-0 pointer-events-none">
        <div className="absolute inset-0" style={{ background: 'linear-gradient(to bottom, #0a0a0a 0%, #0f0f10 50%, #0b0c0d 100%)' }} />
        <div className="absolute inset-0" style={{ background: 'radial-gradient(circle at 88% 10%, rgba(20, 76, 84, 0.28) 0%, transparent 50%)' }} />
        <div className="absolute inset-0" style={{ background: 'radial-gradient(circle at 12% 88%, rgba(122, 22, 18, 0.30) 0%, transparent 50%)' }} />
      </div>

      <div className="relative z-10 pt-20 pb-10">
        <div className="page-gutter">
          <div className="max-w-2xl mb-10">
            <SearchInput value={query} onChange={setQuery} onSubmit={() => recordRecentSearch(query)} autoFocus />
          </div>

          {searching ? (
            <div className="mb-12">
              {results.length > 0 && <SearchResults results={results} onItemClick={handleResult} />}
              {loading && results.length === 0 && (
                <div className="text-center py-20">
                  <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-white" />
                  <p className="mt-4 text-neutral-400">Searching...</p>
                </div>
              )}
              {!loading && results.length === 0 && (
                <div className="text-center py-20">
                  {failed ? (
                    <>
                      <p className="text-xl text-neutral-400">Search failed</p>
                      <button className="btn mt-4" onClick={() => runSearch(activeQuery || normalize(query))}>Retry</button>
                    </>
                  ) : (
                    <>
                      <p className="text-xl text-neutral-400">No results found for "{activeQuery || normalize(query)}"</p>
                      <p className="mt-2 text-sm text-neutral-500">Try searching with different keywords</p>
                    </>
                  )}
                </div>
              )}
            </div>
          ) : (
            <>
              {recent.length > 0 && (
                <SearchRecent
                  searches={recent}
                  onSelect={(text) => {
                    setQuery(text);
                    recordRecentSearch(text);
                  }}
                  onRemove={(text) => saveSettings({ recentSearches: getSettings().recentSearches.filter((entry) => entry !== text) })}
                  onClear={() => saveSettings({ recentSearches: [] })}
                />
              )}
              {tmdbAllowed && (
                <div className="flex gap-1 mb-6" role="tablist" aria-label="Search mode">
                  {(['explore', 'discover'] as const).map((tab) => (
                    <button
                      key={tab}
                      role="tab"
                      aria-selected={idleTab === tab}
                      onClick={() => saveSettings({ searchIdleTab: tab })}
                      className={`px-4 py-1.5 rounded-full text-sm font-semibold ${idleTab === tab ? 'bg-white text-black' : 'bg-white/10 text-white/80 hover:text-white'}`}
                    >
                      {tab === 'explore' ? 'Explore' : 'Discover'}
                    </button>
                  ))}
                </div>
              )}
              {idleTab === 'discover' ? (
                <SearchDiscover onOpen={openCard} />
              ) : (
                trending.length > 0 && (
                  <div>
                    <h2 className="text-lg font-semibold mb-4 text-white">Recommended TV Shows & Movies</h2>
                    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
                      {trending.map((item) => (
                        <LandscapeCard key={item.id} id={item.id} title={item.title} image={item.image} item={item} layout="grid" onClick={() => openCard(item)} />
                      ))}
                    </div>
                  </div>
                )
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
