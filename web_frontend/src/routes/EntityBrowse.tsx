import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import TitleGrid, { tmdbGridItem, type TitleGridItem } from '@/components/details/TitleGrid';
import { tmdbCompany, tmdbDiscoverMovies, tmdbDiscoverTV, tmdbImage, tmdbNetwork } from '@/services/tmdb';

type Sort = 'popular' | 'topRated' | 'newest';

const SORTS: Array<{ value: Sort; label: string }> = [
  { value: 'popular', label: 'Popular' },
  { value: 'topRated', label: 'Top rated' },
  { value: 'newest', label: 'Newest' },
];

function sortParams(sort: Sort, media: 'movie' | 'tv'): Record<string, string | number> {
  switch (sort) {
    case 'popular':
      return { sort_by: 'popularity.desc' };
    case 'topRated':
      return { sort_by: 'vote_average.desc', 'vote_count.gte': 200 };
    case 'newest':
      return {
        sort_by: media === 'tv' ? 'first_air_date.desc' : 'primary_release_date.desc',
        [media === 'tv' ? 'first_air_date.lte' : 'primary_release_date.lte']: new Date().toISOString().slice(0, 10),
      };
  }
}

const Pill = ({ active, onClick, children }: { active: boolean; onClick: () => void; children: string }) => (
  <button
    onClick={onClick}
    aria-pressed={active}
    className={`rounded-full px-4 py-1.5 text-sm font-semibold transition ${active ? 'bg-white text-black' : 'bg-white/10 text-white hover:bg-white/20'}`}
  >
    {children}
  </button>
);

/** Paged TMDB discover for a production company (movies or TV) or a TV network. */
export default function EntityBrowse() {
  const { kind = '', id = '' } = useParams();
  const validKind = kind === 'company' || kind === 'network';
  const isNetwork = kind === 'network';

  const [details, setDetails] = useState<any | null>(null);
  const [media, setMedia] = useState<'movie' | 'tv'>(isNetwork ? 'tv' : 'movie');
  const [sort, setSort] = useState<Sort>('popular');
  const [items, setItems] = useState<TitleGridItem[]>([]);
  const [total, setTotal] = useState<number | null>(null);
  const [phase, setPhase] = useState<'loading' | 'loaded' | 'failed'>('loading');
  const [loadingMore, setLoadingMore] = useState(false);
  const [pagingFailed, setPagingFailed] = useState(false);

  const pageRef = useRef(0);
  const totalPagesRef = useRef(1);
  const generation = useRef(0);
  const autoSwitched = useRef(false);
  const sentinel = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!validKind || !/^\d+$/.test(id)) return;
    let alive = true;
    (isNetwork ? tmdbNetwork(id) : tmdbCompany(id))
      .then((data) => { if (alive) setDetails(data); })
      .catch(() => undefined);
    return () => { alive = false; };
  }, [id, isNetwork, validKind]);

  const fetchPage = useCallback(async (page: number) => {
    const filter = isNetwork ? { with_networks: id } : { with_companies: id };
    const params = { ...filter, ...sortParams(sort, media), page };
    return (media === 'tv' ? tmdbDiscoverTV('', params) : tmdbDiscoverMovies('', params)) as Promise<any>;
  }, [id, isNetwork, sort, media]);

  useEffect(() => {
    if (!validKind || !/^\d+$/.test(id)) {
      setPhase('failed');
      return;
    }
    const gen = ++generation.current;
    setPhase('loading');
    setItems([]);
    setTotal(null);
    setPagingFailed(false);
    pageRef.current = 0;

    fetchPage(1)
      .then((data) => {
        if (gen !== generation.current) return;
        // Companies that mostly make TV switch to TV once if there are no movies.
        if (!data.results?.length && media === 'movie' && !isNetwork && !autoSwitched.current) {
          autoSwitched.current = true;
          setMedia('tv');
          return;
        }
        setItems(dedupe([], (data.results || []).map((r: any) => tmdbGridItem(r, media, (p) => tmdbImage(p, 'w500')))));
        setTotal(data.total_results ?? null);
        pageRef.current = 1;
        totalPagesRef.current = data.total_pages || 1;
        setPhase('loaded');
      })
      .catch(() => { if (gen === generation.current) setPhase('failed'); });
  }, [fetchPage, id, isNetwork, media, validKind]);

  const canLoadMore = pageRef.current > 0 && pageRef.current < totalPagesRef.current && pageRef.current < 500;

  const loadMore = useCallback(async () => {
    if (loadingMore || pageRef.current === 0 || pageRef.current >= Math.min(totalPagesRef.current, 500)) return;
    const gen = generation.current;
    setLoadingMore(true);
    setPagingFailed(false);
    try {
      const data = await fetchPage(pageRef.current + 1);
      if (gen !== generation.current) return;
      pageRef.current += 1;
      setItems((current) => dedupe(current, (data.results || []).map((r: any) => tmdbGridItem(r, media, (p) => tmdbImage(p, 'w500')))));
    } catch {
      if (gen === generation.current) setPagingFailed(true);
    } finally {
      if (gen === generation.current) setLoadingMore(false);
    }
  }, [fetchPage, loadingMore, media]);

  useEffect(() => {
    const element = sentinel.current;
    if (!element) return;
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting && !pagingFailed) loadMore();
    }, { rootMargin: '600px' });
    observer.observe(element);
    return () => observer.disconnect();
  }, [loadMore, pagingFailed, items.length]);

  const subtitle = useMemo(() => {
    const parts = [isNetwork ? 'TV network' : 'Production company'];
    if (details?.headquarters) parts.push(details.headquarters);
    else if (details?.origin_country) parts.push(details.origin_country);
    return parts.join(' · ');
  }, [details, isNetwork]);

  if (!validKind) {
    return <div className="page-gutter py-24 text-center text-white/60">There are no titles to show here.</div>;
  }

  const logo = tmdbImage(details?.logo_path, 'w500');
  const noun = media === 'tv' ? 'show' : 'movie';

  return (
    <div className="page-gutter pb-16 pt-8">
      <header className="mb-8 flex items-center gap-5">
        {logo && (
          <div className="flex h-16 items-center rounded-xl bg-white px-4">
            <img src={logo} alt="" className="max-h-10 w-auto max-w-[160px] object-contain" />
          </div>
        )}
        <div className="min-w-0">
          <h1 className="truncate text-3xl font-bold text-white">{details?.name || (isNetwork ? 'Network' : 'Studio')}</h1>
          <p className="mt-1 text-sm text-white/60">{subtitle}</p>
          {total != null && total > 0 && <p className="text-sm text-white/40">{total.toLocaleString()} {noun}{total === 1 ? '' : 's'}</p>}
        </div>
      </header>

      <div className="mb-6 flex flex-wrap gap-2">
        {!isNetwork && (
          <>
            <Pill active={media === 'movie'} onClick={() => setMedia('movie')}>Movies</Pill>
            <Pill active={media === 'tv'} onClick={() => setMedia('tv')}>TV</Pill>
            <span className="mx-1 w-px bg-white/15" />
          </>
        )}
        {SORTS.map((option) => (
          <Pill key={option.value} active={sort === option.value} onClick={() => setSort(option.value)}>{option.label}</Pill>
        ))}
      </div>

      {phase === 'loading' && (
        <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-4 md:grid-cols-[repeat(auto-fill,minmax(160px,1fr))]">
          {Array.from({ length: 12 }).map((_, index) => <div key={index} className="aspect-[2/3] animate-pulse rounded-xl bg-white/10" />)}
        </div>
      )}
      {phase === 'failed' && <p className="py-16 text-center text-white/60">Couldn't load these titles. Check your connection and try again.</p>}
      {phase === 'loaded' && items.length === 0 && <p className="py-16 text-center text-white/60">There are no titles to show here.</p>}
      {phase === 'loaded' && items.length > 0 && <TitleGrid items={items} />}

      {canLoadMore && <div ref={sentinel} className="h-10" />}
      {loadingMore && <p className="py-6 text-center text-sm text-white/50">Loading more...</p>}
      {pagingFailed && (
        <div className="py-6 text-center">
          <button onClick={() => loadMore()} className="rounded-full bg-white/15 px-4 py-1.5 text-sm font-semibold text-white hover:bg-white/25">Try Again</button>
        </div>
      )}
    </div>
  );
}

function dedupe(current: TitleGridItem[], incoming: TitleGridItem[]): TitleGridItem[] {
  const seen = new Set(current.map((item) => item.id));
  const merged = [...current];
  for (const item of incoming) {
    if (!seen.has(item.id)) {
      seen.add(item.id);
      merged.push(item);
    }
  }
  return merged;
}
