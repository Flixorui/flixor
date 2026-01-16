import VirtualGrid from '@/components/VirtualGrid';
import PosterCard from '@/components/PosterCard';
import FilterBar from '@/components/FilterBar';
import { loadSettings } from '@/state/settings';
import { plexLibs, plexSectionAll, plexImage, withContainer } from '@/services/plex';
import { plexBackendLibraries, plexBackendLibraryAll } from '@/services/plex_backend';
import SectionBanner from '@/components/SectionBanner';
import { useLocation, useNavigate } from 'react-router-dom';
import { useEffect, useMemo, useState } from 'react';
import { apiClient } from '@/services/api';

type Item = { id: string; title: string; image?: string; subtitle?: string; badge?: string };

export default function Library() {
  const nav = useNavigate();
  const location = useLocation();
  const [items, setItems] = useState<Item[]>([]);
  const [start, setStart] = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const [sections, setSections] = useState<Array<{ key: string; title: string; type: 'movie'|'show' }>>([]);
  const [active, setActive] = useState<string>('');
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<'all' | 'movies' | 'shows'>('all');
  const [needsPlex, setNeedsPlex] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = () => {
    setIsRefreshing(true);
    setItems([]);
    setStart(0);
    setHasMore(true);
    // Trigger re-fetch by updating active
    const currentActive = active;
    setActive('');
    setTimeout(() => {
      setActive(currentActive);
      setIsRefreshing(false);
    }, 100);
  };

  useEffect(() => {
    const s = loadSettings();
    if (!s.plexBaseUrl || !s.plexToken) { setNeedsPlex(true); return; }
    async function load() {
      try {
        const libs: any = await plexBackendLibraries();
        const dir = libs?.MediaContainer?.Directory || [];
        const secs = dir
          .filter((d: any) => d.type === 'movie' || d.type === 'show')
          .map((d: any) => ({ key: String(d.key), title: d.title, type: d.type }));
        setSections(secs);
        // Choose default section based on URL tab parameter
        const params = new URLSearchParams(location.search);
        const tab = params.get('tab'); // 'tv' | 'movies'
        const wantType: 'show'|'movie' | null = tab === 'tv' ? 'show' : tab === 'movies' ? 'movie' : null;
        const preferred = wantType ? secs.find((x: any) => x.type === wantType) : (secs[0] || null);
        if (preferred) setActive(preferred.key);
        else setNeedsPlex(true);
      } catch (e) {
        console.error(e); setNeedsPlex(true);
      }
    }
    load();
  }, [location.search]);

  // If user switches between /library?tab=tv and /library?tab=movies while already loaded,
  // update the active section accordingly.
  useEffect(() => {
    if (sections.length === 0) return;
    const params = new URLSearchParams(location.search);
    const tab = params.get('tab');
    const wantType: 'show'|'movie' | null = tab === 'tv' ? 'show' : tab === 'movies' ? 'movie' : null;
    if (!wantType) return;
    const preferred = sections.find((s) => s.type === wantType);
    if (preferred && preferred.key !== active) setActive(preferred.key);
  }, [location.search, sections]);

  // Reload app when server changes so sections/items refresh
  useEffect(() => {
    const handler = () => window.location.reload();
    // @ts-ignore
    window.addEventListener('plex-server-changed', handler as any);
    return () => {
      // @ts-ignore
      window.removeEventListener('plex-server-changed', handler as any);
    };
  }, []);

  useEffect(() => {
    const s = loadSettings();
    if (!active || !s.plexBaseUrl || !s.plexToken) return;
    async function loadItems(reset = true) {
      const base = '?sort=addedAt:desc';
      const size = 100;
      const nextOffset = reset ? 0 : start;
      const all: any = await plexBackendLibraryAll(active, { sort: 'addedAt:desc', offset: nextOffset, limit: size });
      const mc = all?.MediaContainer?.Metadata || [];
      const mapped: Item[] = mc.map((m: any, i: number) => {
        const p = m.thumb || m.parentThumb || m.grandparentThumb;
        const img = apiClient.getPlexImageNoToken(p || '');
        return {
          id: String(m.ratingKey || i),
          title: m.title || m.grandparentTitle,
          image: img,
          subtitle: m.year ? String(m.year) : undefined,
          badge: 'Plex',
        };
      });
      if (reset) setItems(mapped); else setItems((prev) => [...prev, ...mapped]);
      const total = all?.MediaContainer?.totalSize ?? (reset ? mapped.length : items.length + mapped.length);
      const newStart = (reset ? 0 : start) + mapped.length;
      setStart(newStart);
      setHasMore(newStart < total);
    }
    setStart(0); setHasMore(true); loadItems(true);
  }, [active]);

  const filtered = useMemo(() => items.filter((it) => it.title.toLowerCase().includes(query.toLowerCase())), [items, query]);

  return (
    <div className="pb-8 relative">
      {/* Floating Refresh Button */}
      <button
        onClick={handleRefresh}
        disabled={isRefreshing || needsPlex}
        className="fixed top-20 right-4 z-40 p-3 rounded-full bg-white/10 backdrop-blur-md hover:bg-white/20 transition-all disabled:opacity-50"
        title="Refresh library"
      >
        <svg
          className={`w-5 h-5 text-white ${isRefreshing ? 'animate-spin' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
          />
        </svg>
      </button>
      {!needsPlex && sections.length>0 ? (
        <div className="page-gutter pt-6 space-y-3">
          <div className="flex flex-wrap gap-2">
            {sections.map(s => (
              <button key={s.key} onClick={() => setActive(s.key)} className={`h-8 px-3 rounded-full text-sm ring-1 ${active===s.key? 'bg-white text-black ring-white/0':'bg-white/5 text-neutral-200 hover:bg-white/10 ring-white/10'}`}>{s.title}</button>
            ))}
          </div>
        <FilterBar
          query={query}
          setQuery={setQuery}
          type={filter}
          setType={(v) => setFilter(v as any)}
          genres={[{label:'Action', value:'action'},{label:'Drama',value:'drama'}]}
          years={Array.from({length: 10}).map((_,i)=>({label:String(2024-i), value:String(2024-i)}))}
        />
        </div>
      ) : (
        <SectionBanner title="Libraries" message="Connect Plex to browse your Movies and TV Show libraries here." cta="Open Settings" to="/settings" />
      )}
      {!needsPlex && active && (
        <div className="page-gutter mt-4">
          <div className="row-band">
            <VirtualGrid
              items={filtered}
              columnWidth={160}
              rowHeight={240}
              gap={12}
              overscan={3}
              hasMore={hasMore}
              loadMore={() => {
                if (!hasMore) return;
                const s = loadSettings();
                if (!s.plexBaseUrl || !s.plexToken || !active) return;
              // load next page
              (async () => {
                  const base = '?sort=addedAt:desc';
                  const size = 100;
                  const all: any = await plexBackendLibraryAll(active, { sort: 'addedAt:desc', offset: start, limit: size });
                  const mc = all?.MediaContainer?.Metadata || [];
                  const mapped: Item[] = mc.map((m: any, i: number) => {
                    const p = m.thumb || m.parentThumb || m.grandparentThumb;
                    const img = apiClient.getPlexImageNoToken(p || '');
                    return {
                      id: String(m.ratingKey || i),
                      title: m.title || m.grandparentTitle,
                      image: img,
                      subtitle: m.year ? String(m.year) : undefined,
                    };
                  });
                  setItems((prev) => [...prev, ...mapped]);
                  const total = all?.MediaContainer?.totalSize ?? (start + mapped.length);
                  const newStart = start + mapped.length;
                  setStart(newStart);
                  setHasMore(newStart < total);
                })();
              }}
              render={(it) => <PosterCard id={`plex:${it.id}`} title={it.title} image={it.image} onClick={() => nav(`/details/plex:${it.id}`)} />}
            />
          </div>
        </div>
      )}
    </div>
  );
}
