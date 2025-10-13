import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { loadSettings } from '@/state/settings';
import { plexImage } from '@/services/plex';
import { plexBackendDir } from '@/services/plex_backend';
import { apiClient } from '@/services/api';
import { plexTvWatchlist } from '@/services/plextv';
import { tmdbRecommendations, tmdbSimilar, tmdbImage } from '@/services/tmdb';
import SmartImage from './SmartImage';

type Item = { id: string; title: string; image?: string };

export default function BrowseModal() {
  const [params, setParams] = useSearchParams();
  const nav = useNavigate();
  const open = params.has('bkey');
  const bkey = useMemo(() => (open ? decodeURIComponent(params.get('bkey') || '') : ''), [open, params]);
  const [title, setTitle] = useState<string>('');
  const [items, setItems] = useState<Item[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | ''>('');
  const [tmdbCtx, setTmdbCtx] = useState<{ kind: 'recs'|'similar'; media: 'movie'|'tv'; id: string; page: number; total?: number } | null>(null);

  useEffect(() => {
    if (!open || !bkey) return;
    const s = loadSettings();
    async function run() {
      setLoading(true); setError(''); setItems([]); setTitle('');
      setTmdbCtx(null);
      try {
        if (bkey.startsWith('/plextv/watchlist')) {
          if (!s.plexTvToken) throw new Error('Plex Account Token missing. Add it in Settings.');
          const wl: any = await plexTvWatchlist(s.plexTvToken);
          const meta = wl?.MediaContainer?.Metadata || [];
          setTitle('Watchlist');
          const rows: Item[] = meta.map((m: any) => ({
            id: inferIdFromGuid(m) || `guid:${encodeURIComponent(m.guid||'')}`,
            title: m.title || m.grandparentTitle || 'Title',
            image: m.thumb || m.parentThumb || m.grandparentThumb,
          }));
          setItems(rows);
          return;
        }
        // TMDB browse: recommendations/similar
        if (bkey.startsWith('tmdb:')) {
          const parts = bkey.split(':'); // tmdb:<kind>:<media>:<id>
          const kind = parts[1];
          const media = parts[2] as 'movie'|'tv';
          const tmdbId = parts[3];
          if (!s.tmdbBearer) throw new Error('TMDB key not configured');
          setTitle(kind === 'recs' ? 'Recommendations' : 'More Like This');
          // Load page 1 and set context for pagination
          const res: any = kind === 'recs'
            ? await tmdbRecommendations(s.tmdbBearer!, media, tmdbId, 1)
            : await tmdbSimilar(s.tmdbBearer!, media, tmdbId, 1);
          const list = (res?.results || []) as any[];
          const rows: Item[] = list.map((r: any) => ({ id: `tmdb:${media}:${r.id}`, title: r.title || r.name, image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500') }));
          setItems(rows);
          setTmdbCtx({ kind: kind === 'recs' ? 'recs' : 'similar', media, id: tmdbId, page: 1, total: res?.total_pages || undefined });
          return;
        }
        const res: any = await plexBackendDir(bkey);
        const mc = res?.MediaContainer;
        setTitle([mc?.title1, mc?.title2].filter(Boolean).join(' - ') || 'Browse');
        const meta = mc?.Metadata || [];
        const rows: Item[] = meta.map((m: any) => {
          const p = m.thumb || m.parentThumb || m.grandparentThumb || m.art;
          return {
            id: `plex:${m.ratingKey}`,
            title: m.title || m.grandparentTitle || 'Title',
            image: apiClient.getPlexImageNoToken(p || ''),
          };
        });
        setItems(rows);
      } catch (e: any) {
        setError(e?.message || 'Failed to load');
      } finally { setLoading(false); }
    }
    run();
  }, [open, bkey]);

  async function loadMore() {
    const s = loadSettings();
    if (!tmdbCtx || !s.tmdbBearer) return;
    if (tmdbCtx.total && tmdbCtx.page >= tmdbCtx.total) return;
    const next = tmdbCtx.page + 1;
    try {
      setLoading(true);
      const res: any = tmdbCtx.kind === 'recs'
        ? await tmdbRecommendations(s.tmdbBearer!, tmdbCtx.media, tmdbCtx.id, next)
        : await tmdbSimilar(s.tmdbBearer!, tmdbCtx.media, tmdbCtx.id, next);
      const list = (res?.results || []) as any[];
      const rows: Item[] = list.map((r: any) => ({ id: `tmdb:${tmdbCtx.media}:${r.id}`, title: r.title || r.name, image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500') }));
      setItems((prev) => [...prev, ...rows]);
      setTmdbCtx((c) => c ? { ...c, page: next, total: res?.total_pages || c.total } : c);
    } catch (e: any) {
      setError(e?.message || 'Failed to load next page');
    } finally {
      setLoading(false);
    }
  }

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm overflow-y-auto" onClick={() => { params.delete('bkey'); setParams(params, { replace: false }); }}>
      <div className="max-w-6xl mx-auto mt-16 mb-24 px-4" onClick={(e) => e.stopPropagation()}>
        <div className="bg-[#181818] rounded-2xl ring-1 ring-white/10 shadow-2xl p-6">
          <div className="flex items-center mb-4">
            <h2 className="text-2xl font-semibold flex-1">{title || 'Browse'}</h2>
            <button onClick={() => { params.delete('bkey'); setParams(params, { replace: false }); }} className="btn">Close</button>
          </div>
          {error && <div className="text-red-400 mb-4">{error}</div>}
          {loading ? (
            <div className="text-neutral-400">Loading…</div>
          ) : (
            <>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
                {items.map((i, idx) => (
                  <button key={idx} className="text-left group" onClick={() => nav(`/details/${encodeURIComponent(i.id)}`)}>
                    <div className="w-full aspect-video rounded-xl overflow-hidden ring-1 ring-white/10 bg-neutral-800 card-hover">
                      {i.image && <SmartImage url={i.image} alt={i.title} width={320} className="w-full h-full" imgClassName="object-cover" />}
                    </div>
                    <div className="mt-1 text-sm line-clamp-2 text-neutral-200 group-hover:text-white transition-colors">{i.title}</div>
                  </button>
                ))}
              </div>
              {tmdbCtx && (!tmdbCtx.total || tmdbCtx.page < (tmdbCtx.total || 1)) && (
                <div className="mt-4 flex justify-center">
                  <button onClick={loadMore} className="btn">Load more</button>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function inferIdFromGuid(m: any): string | undefined {
  const g = String(m.guid || '');
  if (!g) return undefined;
  const num = (g.match(/(\d{3,})/) || [])[1];
  if (g.includes('tmdb://') && num) {
    const type = (m.type === 'movie') ? 'movie' : (m.type === 'show' ? 'tv' : 'movie');
    return `tmdb:${type}:${num}`;
  }
  return undefined;
}
