import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom';
import FilterBar, { type FilterOption, type LibraryFilters } from '@/components/FilterBar';
import { CollectionItems, CollectionsGrid } from '@/components/LibraryCollections';
import PosterCard from '@/components/PosterCard';
import SectionBanner from '@/components/SectionBanner';
import SmartImage from '@/components/SmartImage';
import VirtualGrid from '@/components/VirtualGrid';
import { useCardStyle } from '@/components/cards/cardStyle';
import type { CardItem } from '@/components/cards/cardTypes';
import { detailsPath } from '@/components/cards/cardMedia';
import { useCardInteractions } from '@/components/cards/useCardInteractions';
import { plexBackendLibraryAll, plexBackendLibrarySecondary } from '@/services/plex_backend';
import { filterEnabledLibraries, getPlexLibraries, plexItemToCard, type PlexLibrary } from '@/services/plexCollections';
import { saveSettings, useSettings } from '@/state/settings';

const PAGE_SIZE = 100;
const LIST_ROW_HEIGHT = 112;
const TITLE_BLOCK_HEIGHT = 58;
const DEFAULT_FILTERS: LibraryFilters = { query: '', genre: '', year: '', sort: 'addedAt:desc' };

async function directoryOptions(libraryKey: string, directory: 'genre' | 'year'): Promise<FilterOption[]> {
  const res: any = await plexBackendLibrarySecondary(libraryKey, directory).catch(() => null);
  const entries: FilterOption[] = (res?.MediaContainer?.Directory || [])
    .filter((d: any) => d.key && d.title)
    .map((d: any) => ({ label: String(d.title), value: String(d.key) }));
  return directory === 'genre' ? entries.sort((a, b) => a.label.localeCompare(b.label)) : entries.sort((a, b) => b.value.localeCompare(a.value));
}

function collectionKey(param: string | null) {
  return param ? param.replace(/^plex:/, '') : null;
}

export default function Library() {
  const nav = useNavigate();
  const location = useLocation();
  const [params, setParams] = useSearchParams();
  const settings = useSettings();
  const style = useCardStyle('library');
  const connected = !!settings.plexBaseUrl && !!settings.plexToken;

  const [allSections, setAllSections] = useState<PlexLibrary[]>([]);
  const [sectionsState, setSectionsState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [active, setActive] = useState('');
  const [typeFilter, setTypeFilter] = useState<'all' | 'movies' | 'shows'>('all');
  const [contentTab, setContentTab] = useState<'library' | 'collections'>('library');
  const [filters, setFilters] = useState<LibraryFilters>(DEFAULT_FILTERS);
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [genres, setGenres] = useState<FilterOption[]>([]);
  const [years, setYears] = useState<FilterOption[]>([]);
  const [items, setItems] = useState<CardItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [hasMore, setHasMore] = useState(false);
  const [refreshToken, setRefreshToken] = useState(0);
  const [collectionTitle, setCollectionTitle] = useState<string | undefined>(undefined);

  const openCollection = collectionKey(params.get('collection'));
  const offset = useRef(0);
  const requestId = useRef(0);
  const loadingMore = useRef(false);

  const enabledKeys = settings.enabledLibraryKeys.join(',');
  const sections = useMemo(
    () => filterEnabledLibraries(allSections, settings.enabledLibraryKeys),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [allSections, enabledKeys],
  );
  const visibleSections = useMemo(
    () => sections.filter((s) => typeFilter === 'all' || s.type === (typeFilter === 'movies' ? 'movie' : 'show')),
    [sections, typeFilter],
  );

  useEffect(() => {
    if (!connected) return;
    let alive = true;
    setSectionsState('loading');
    getPlexLibraries()
      .then((libraries) => {
        if (!alive) return;
        setAllSections(libraries);
        setSectionsState('ready');
      })
      .catch((e) => {
        console.error(e);
        if (alive) setSectionsState('error');
      });
    return () => {
      alive = false;
    };
  }, [connected, refreshToken]);

  const wantedType = (search: string) => {
    const tab = new URLSearchParams(search).get('tab');
    return tab === 'tv' ? 'show' : tab === 'movies' ? 'movie' : null;
  };

  // Follow links to /library?tab=tv and /library?tab=movies.
  useEffect(() => {
    const wanted = wantedType(location.search);
    if (!wanted || sections.length === 0) return;
    setTypeFilter('all');
    const current = sections.find((s) => s.key === active);
    const preferred = sections.find((s) => s.type === wanted);
    if (preferred && current?.type !== wanted) setActive(preferred.key);
    // Only a new link should move the selection, not picking another library.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.search, sections]);

  // Keep the selection on a library the type filter and Catalog settings allow.
  useEffect(() => {
    if (visibleSections.length === 0 || visibleSections.some((s) => s.key === active)) return;
    const wanted = wantedType(location.search);
    setActive((visibleSections.find((s) => !wanted || s.type === wanted) ?? visibleSections[0]).key);
  }, [visibleSections, active, location.search]);

  useEffect(() => {
    const handler = () => window.location.reload();
    window.addEventListener('plex-server-changed', handler);
    return () => window.removeEventListener('plex-server-changed', handler);
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedQuery(filters.query.trim()), 300);
    return () => window.clearTimeout(timer);
  }, [filters.query]);

  // Genre and year options belong to the selected library.
  useEffect(() => {
    if (!active) return;
    let alive = true;
    setFilters((current) => ({ ...current, genre: '', year: '' }));
    Promise.all([directoryOptions(active, 'genre'), directoryOptions(active, 'year')]).then(([g, y]) => {
      if (!alive) return;
      setGenres(g);
      setYears(y);
    });
    return () => {
      alive = false;
    };
  }, [active]);

  const fetchPage = useCallback(
    async (reset: boolean) => {
      if (!active) return;
      const id = reset ? ++requestId.current : requestId.current;
      const start = reset ? 0 : offset.current;
      const query: Record<string, string | number> = { sort: filters.sort, offset: start, limit: PAGE_SIZE };
      if (filters.genre) query.genre = filters.genre;
      if (filters.year) query.year = filters.year;
      if (debouncedQuery) query.title = debouncedQuery;
      try {
        if (reset) {
          setLoading(true);
          setError('');
        }
        const res: any = await plexBackendLibraryAll(active, query);
        if (id !== requestId.current) return;
        const metadata: any[] = res?.MediaContainer?.Metadata || [];
        const page = metadata.map((m) => ({ ...plexItemToCard(m), subtitle: m.year ? String(m.year) : undefined }));
        setItems((current) => (reset ? page : [...current, ...page]));
        offset.current = start + page.length;
        const total = res?.MediaContainer?.totalSize ?? offset.current;
        setHasMore(page.length > 0 && offset.current < total);
      } catch (e: any) {
        if (id !== requestId.current) return;
        if (reset) setItems([]);
        setHasMore(false);
        setError(e?.message || 'Could not load this library');
      } finally {
        if (id === requestId.current) setLoading(false);
      }
    },
    [active, filters.sort, filters.genre, filters.year, debouncedQuery],
  );

  useEffect(() => {
    if (contentTab === 'library') fetchPage(true);
  }, [fetchPage, contentTab, refreshToken]);

  const loadMore = useCallback(() => {
    if (loadingMore.current || !hasMore) return;
    loadingMore.current = true;
    fetchPage(false).finally(() => {
      loadingMore.current = false;
    });
  }, [fetchPage, hasMore]);

  const open = (item: CardItem) => nav(detailsPath(item.id));
  const hasFilters = !!(filters.genre || filters.year || debouncedQuery);
  const isList = settings.libraryViewMode === 'list';
  const rowHeight = isList ? LIST_ROW_HEIGHT : Math.round(style.posterWidth * 1.5) + (style.titleMode === 'always' ? TITLE_BLOCK_HEIGHT : 0);
  const showBanner = !connected || (sectionsState === 'ready' && allSections.length === 0);

  const closeCollection = () => {
    params.delete('collection');
    setParams(params, { replace: false });
    setCollectionTitle(undefined);
    setContentTab('collections');
  };

  return (
    <div className="pb-8 relative">
      <button
        onClick={() => setRefreshToken((token) => token + 1)}
        disabled={loading || showBanner}
        className="fixed top-20 right-4 z-40 p-3 rounded-full bg-white/10 backdrop-blur-md hover:bg-white/20 transition-all disabled:opacity-50"
        title="Refresh library"
        aria-label="Refresh library"
      >
        <svg className={`w-5 h-5 text-white ${loading ? 'animate-spin' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
      </button>

      {showBanner ? (
        <SectionBanner title="Libraries" message="Connect Plex to browse your Movies and TV Show libraries here." cta="Open Settings" to="/settings" />
      ) : sectionsState === 'error' ? (
        <div className="page-gutter pt-12 text-center">
          <p className="text-neutral-400 mb-3">Could not load your libraries.</p>
          <button onClick={() => setRefreshToken((token) => token + 1)} className="btn">Retry</button>
        </div>
      ) : openCollection ? (
        <div className="page-gutter pt-6">
          <CollectionItems ratingKey={openCollection} title={collectionTitle} onBack={closeCollection} onOpen={open} />
        </div>
      ) : (
        <>
          <div className="page-gutter pt-6 space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              {(['library', 'collections'] as const).map((tab) => (
                <button
                  key={tab}
                  onClick={() => setContentTab(tab)}
                  className={`h-8 px-3 text-sm font-semibold border-b-2 ${contentTab === tab ? 'text-white border-white' : 'text-neutral-400 border-transparent hover:text-white'}`}
                >
                  {tab === 'library' ? 'Library' : 'Collections'}
                </button>
              ))}
            </div>
            {contentTab === 'library' && (
              <>
                <div className="flex flex-wrap gap-2">
                  {visibleSections.map((s) => (
                    <button
                      key={s.key}
                      onClick={() => setActive(s.key)}
                      className={`h-8 px-3 rounded-full text-sm ring-1 ${active === s.key ? 'bg-white text-black ring-white/0' : 'bg-white/5 text-neutral-200 hover:bg-white/10 ring-white/10'}`}
                    >
                      {s.title}
                    </button>
                  ))}
                </div>
                <FilterBar
                  filters={filters}
                  onChange={setFilters}
                  type={typeFilter}
                  setType={setTypeFilter}
                  genres={genres}
                  years={years}
                  viewMode={settings.libraryViewMode}
                  setViewMode={(libraryViewMode) => saveSettings({ libraryViewMode })}
                />
              </>
            )}
          </div>

          {contentTab === 'collections' ? (
            <div className="page-gutter mt-4">
              <CollectionsGrid
                libraries={sections}
                onSelect={(collection) => {
                  setCollectionTitle(collection.title);
                  params.set('collection', collection.ratingKey);
                  setParams(params, { replace: false });
                }}
              />
            </div>
          ) : error ? (
            <div className="page-gutter pt-12 text-center">
              <p className="text-neutral-400 mb-3">{error}</p>
              <button onClick={() => fetchPage(true)} className="btn">Retry</button>
            </div>
          ) : !loading && items.length === 0 && active ? (
            <p className="page-gutter pt-12 text-center text-neutral-400">
              {hasFilters ? 'No titles match these filters.' : 'This library is empty.'}
            </p>
          ) : (
            active && (
              <div className="page-gutter mt-4">
                <div className="row-band">
                  <VirtualGrid
                    items={items}
                    columnWidth={style.posterWidth}
                    rowHeight={rowHeight}
                    gap={12}
                    overscan={3}
                    hasMore={hasMore}
                    loadMore={loadMore}
                    singleColumn={isList}
                    render={(item) =>
                      isList ? (
                        <LibraryListRow item={item} onOpen={() => open(item)} />
                      ) : (
                        <PosterCard id={item.id} title={item.title} image={item.image} subtitle={item.subtitle} item={item} surface="library" fill onClick={() => open(item)} />
                      )
                    }
                  />
                </div>
              </div>
            )
          )}
        </>
      )}
    </div>
  );
}

function LibraryListRow({ item, onOpen }: { item: CardItem; onOpen: () => void }) {
  const { cardProps, overlay } = useCardInteractions<HTMLDivElement>({ item, onOpen });
  return (
    <div {...cardProps} className="group flex items-center gap-4 h-full px-2 rounded-lg cursor-pointer outline-none hover:bg-white/5 focus-visible:ring-2 focus-visible:ring-white">
      <div className="h-[100px] aspect-[2/3] flex-shrink-0 rounded-md overflow-hidden bg-neutral-800">
        {item.image && <SmartImage url={item.image} alt={item.title} width={80} className="w-full h-full" />}
      </div>
      <div className="min-w-0">
        <p className="text-white font-semibold line-clamp-1">{item.title}</p>
        <p className="text-xs text-neutral-400 mt-0.5">
          {[item.year, item.rating ? `★ ${Number(item.rating).toFixed(1)}` : undefined].filter(Boolean).join(' • ')}
        </p>
        {item.overview && <p className="text-sm text-neutral-400 mt-1 line-clamp-2">{item.overview}</p>}
      </div>
      {overlay}
    </div>
  );
}
