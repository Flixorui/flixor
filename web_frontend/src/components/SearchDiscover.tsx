import { useEffect, useMemo, useRef, useState } from 'react';
import PosterCard from './PosterCard';
import { useCardStyle } from './cards/cardStyle';
import type { CardItem } from './cards/cardTypes';
import {
  DEFAULT_DISCOVER_FILTERS,
  DISCOVER_GENRES,
  DISCOVER_SORTS,
  fetchDiscoverPage,
  hasActiveDiscoverFilters,
  normalizeDiscoverFilters,
} from '@/services/discover';
import { saveSettings, useSettings, type SearchDiscoverFilters } from '@/state/settings';

const YEARS = Array.from({ length: new Date().getFullYear() - 1949 }, (_, i) => new Date().getFullYear() - i);
const RATINGS = [5, 6, 7, 8, 9];

/** Discover mode of the Search screen: filters plus an endless poster grid. */
export default function SearchDiscover({ onOpen }: { onOpen: (item: CardItem) => void }) {
  const settings = useSettings();
  const style = useCardStyle();
  const filters = useMemo(() => normalizeDiscoverFilters(settings.searchDiscoverFilters), [settings.searchDiscoverFilters]);
  const filterKey = JSON.stringify(filters);
  const [items, setItems] = useState<CardItem[]>([]);
  const [page, setPage] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const requestId = useRef(0);
  const sentinel = useRef<HTMLDivElement>(null);

  const update = (patch: Partial<SearchDiscoverFilters>) => saveSettings({ searchDiscoverFilters: normalizeDiscoverFilters({ ...filters, ...patch }) });

  const load = async (target: number) => {
    const id = ++requestId.current;
    setLoading(true);
    setError('');
    try {
      const result = await fetchDiscoverPage(filters, target);
      if (id !== requestId.current) return;
      setItems((current) => {
        if (target === 1) return result.items;
        const seen = new Set(current.map((item) => item.id));
        return [...current, ...result.items.filter((item) => !seen.has(item.id))];
      });
      setPage(target);
      setTotalPages(result.totalPages);
    } catch (e: any) {
      if (id === requestId.current) setError(e?.message || 'Could not load results');
    } finally {
      if (id === requestId.current) setLoading(false);
    }
  };

  useEffect(() => {
    setItems([]);
    load(1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filterKey]);

  const canLoadMore = !loading && !error && page > 0 && page < totalPages;
  useEffect(() => {
    const el = sentinel.current;
    if (!el || !canLoadMore) return;
    const observer = new IntersectionObserver(([entry]) => entry.isIntersecting && load(page + 1), { rootMargin: '600px' });
    observer.observe(el);
    return () => observer.disconnect();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canLoadMore, page, filterKey]);

  const genres = DISCOVER_GENRES[filters.mediaType];

  return (
    <div>
      <div className="flex flex-wrap items-center gap-3 mb-6">
        <div className="flex rounded-full bg-white/10 p-0.5" role="group" aria-label="Media type">
          {(['movie', 'tv'] as const).map((type) => (
            <button
              key={type}
              onClick={() => update({ mediaType: type, genreId: undefined, genreName: undefined })}
              className={`px-4 py-1.5 rounded-full text-sm font-semibold ${filters.mediaType === type ? 'bg-white text-black' : 'text-white/80 hover:text-white'}`}
            >
              {type === 'movie' ? 'Movies' : 'TV Shows'}
            </button>
          ))}
        </div>
        <select
          className="input"
          aria-label="Genre"
          value={filters.genreId ?? ''}
          onChange={(e) => {
            const id = Number(e.target.value) || undefined;
            update({ genreId: id, genreName: genres.find((g) => g.id === id)?.name });
          }}
        >
          <option value="">Any Genre</option>
          {genres.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}
        </select>
        <select className="input" aria-label="Sort" value={filters.sort} onChange={(e) => update({ sort: e.target.value as SearchDiscoverFilters['sort'] })}>
          {DISCOVER_SORTS.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
        </select>
        <select className="input" aria-label="From year" value={filters.yearFrom ?? ''} onChange={(e) => update({ yearFrom: Number(e.target.value) || undefined })}>
          <option value="">From Any Year</option>
          {YEARS.map((y) => <option key={y} value={y}>From {y}</option>)}
        </select>
        <select className="input" aria-label="To year" value={filters.yearTo ?? ''} onChange={(e) => update({ yearTo: Number(e.target.value) || undefined })}>
          <option value="">To Any Year</option>
          {YEARS.map((y) => <option key={y} value={y}>To {y}</option>)}
        </select>
        <select className="input" aria-label="Minimum rating" value={filters.minimumRating ?? ''} onChange={(e) => update({ minimumRating: Number(e.target.value) || undefined })}>
          <option value="">Any Rating</option>
          {RATINGS.map((r) => <option key={r} value={r}>{r}+</option>)}
        </select>
        {hasActiveDiscoverFilters(filters) && (
          <button className="text-sm text-white/70 hover:text-white" onClick={() => saveSettings({ searchDiscoverFilters: { ...DEFAULT_DISCOVER_FILTERS, mediaType: filters.mediaType } })}>
            Reset
          </button>
        )}
      </div>

      {error && items.length === 0 ? (
        <div className="py-16 text-center">
          <p className="text-neutral-400 mb-3">{error}</p>
          <button className="btn" onClick={() => load(1)}>Retry</button>
        </div>
      ) : !loading && items.length === 0 ? (
        <p className="py-16 text-center text-neutral-400">Nothing matches these filters.</p>
      ) : (
        <div className="grid gap-4" style={{ gridTemplateColumns: `repeat(auto-fill, minmax(${style.posterWidth}px, 1fr))` }}>
          {items.map((item) => (
            <PosterCard key={item.id} id={item.id} title={item.title} image={item.image} subtitle={item.year ? String(item.year) : undefined} item={item} fill onClick={() => onOpen(item)} />
          ))}
          {loading && Array.from({ length: 12 }).map((_, i) => <div key={`s${i}`} className="aspect-[2/3] skeleton" style={{ borderRadius: style.radius }} />)}
        </div>
      )}
      {error && items.length > 0 && (
        <div className="py-6 text-center">
          <button className="btn" onClick={() => load(page + 1)}>Retry</button>
        </div>
      )}
      <div ref={sentinel} className="h-px" />
    </div>
  );
}
