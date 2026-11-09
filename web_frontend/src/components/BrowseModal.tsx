import { useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { plexBackendDir, plexBackendLibraryAll } from '@/services/plex_backend';
import { apiClient } from '@/services/api';
import { plexTvWatchlist } from '@/services/plextv';
import { tmdbPopular, tmdbRecommendations, tmdbSimilar, tmdbImage, tmdbTrending } from '@/services/tmdb';
import { traktTrending, traktPopular, traktGetWatchlist, traktGetHistory, traktGetRecommendations, ensureValidToken, isTraktAuthenticated } from '@/services/trakt';
import { getCatalogItems, getCatalogs, type StremioCatalog } from '@/stremio';
import { appToast } from './cards/cardActions';
import { detailsPath, resolveDetailsId, stremioItemToCard, upgradedArtwork } from './cards/cardMedia';
import SmartImage from './SmartImage';

type Item = { id: string; title: string; image?: string; year?: string | number };
type Page = { items: Item[]; next: (() => Promise<Page>) | null };

const STREMIO_PREFIX = 'stremio:';

/** Browse key for an addon catalog. Base64, because catalog ids can hold `:` and `%`. */
export function encodeStremioBrowseKey(catalog: Pick<StremioCatalog, 'installationId' | 'type' | 'id'>) {
  const json = JSON.stringify([catalog.installationId, catalog.type, catalog.id]);
  return STREMIO_PREFIX + btoa(encodeURIComponent(json));
}

function decodeStremioBrowseKey(key: string): { installationId: string; type: string; id: string } | null {
  try {
    const [installationId, type, id] = JSON.parse(decodeURIComponent(atob(key.slice(STREMIO_PREFIX.length))));
    return { installationId, type, id };
  } catch {
    return null;
  }
}

/** One page of an addon catalog. `seen` drops repeats, which addons send across pages. */
async function stremioPage(catalog: StremioCatalog, skip: number, seen: Set<string>): Promise<Page> {
  const entries = await getCatalogItems(catalog, { skip });
  const fresh = entries.map(stremioItemToCard).filter((card) => {
    if (seen.has(card.id)) return false;
    seen.add(card.id);
    return true;
  });
  const nextSkip = skip + entries.length;
  return {
    items: fresh.map(({ id, title, image, backdrop, year }) => ({ id, title, image: backdrop || image, year })),
    next: catalog.supportsSkip && fresh.length > 0 ? () => stremioPage(catalog, nextSkip, seen) : null,
  };
}

function tmdbRows(list: any[], media: 'movie' | 'tv'): Item[] {
  return list.map((r) => ({ id: `tmdb:${media}:${r.id}`, title: r.title || r.name, image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500') }));
}

async function tmdbRelatedPage(kind: 'recs' | 'similar', media: 'movie' | 'tv', id: string, page: number): Promise<Page> {
  const res: any = kind === 'recs' ? await tmdbRecommendations('', media, id, page) : await tmdbSimilar('', media, id, page);
  const total = res?.total_pages;
  return {
    items: tmdbRows(res?.results || [], media),
    next: !total || page < total ? () => tmdbRelatedPage(kind, media, id, page + 1) : null,
  };
}

function plexRows(meta: any[]): Item[] {
  return meta.map((m) => {
    const p = m.thumb || m.parentThumb || m.grandparentThumb || m.art;
    return { id: `plex:${m.ratingKey}`, title: m.title || m.grandparentTitle || 'Title', image: apiClient.getPlexImageNoToken(p || '') };
  });
}

async function traktRows(type: string, mediaType: 'movies' | 'shows'): Promise<Item[]> {
  let data: any[] = [];
  if (type === 'trending') data = await traktTrending(mediaType, 50);
  else if (type === 'popular') data = await traktPopular(mediaType, 50);
  else if (isTraktAuthenticated()) {
    const token = await ensureValidToken();
    if (token) {
      if (type === 'watchlist') {
        const [movies, shows] = await Promise.all([traktGetWatchlist(token, 'movies'), traktGetWatchlist(token, 'shows')]);
        data = [...movies, ...shows];
      } else if (type === 'history') data = await traktGetHistory(token, mediaType, 50);
      else if (type === 'recommendations') data = await traktGetRecommendations(token, mediaType, 50);
    }
  }
  const rows = data.flatMap((entry) => {
    const media = entry.movie || entry.show || entry;
    const tmdbId = media?.ids?.tmdb;
    return tmdbId ? [{ id: `tmdb:${entry.movie ? 'movie' : 'tv'}:${tmdbId}`, title: media?.title || '' }] : [];
  });
  return Promise.all(
    rows.slice(0, 50).map(async (row) => ({ ...row, image: await upgradedArtwork(row.id, 'backdrop') })),
  );
}

const TRAKT_TITLES = (mediaType: string): Record<string, string> => ({
  trending: `Trending ${mediaType === 'movies' ? 'Movies' : 'TV Shows'}`,
  popular: `Popular ${mediaType === 'movies' ? 'Movies' : 'TV Shows'}`,
  watchlist: 'Your Trakt Watchlist',
  history: 'Recently Watched',
  recommendations: 'Recommended for You',
});

async function loadBrowse(bkey: string): Promise<{ title: string; page: Page }> {
  if (bkey.startsWith(STREMIO_PREFIX)) {
    const wanted = decodeStremioBrowseKey(bkey);
    const catalog = wanted && (await getCatalogs()).find((c) => c.installationId === wanted.installationId && c.type === wanted.type && c.id === wanted.id);
    if (!catalog) throw new Error('This addon catalog is no longer available');
    return { title: catalog.name, page: await stremioPage(catalog, 0, new Set()) };
  }

  if (bkey.startsWith('/plextv/watchlist')) {
    const wl: any = await plexTvWatchlist();
    const items = (wl?.MediaContainer?.Metadata || []).map((m: any) => ({
      id: inferIdFromGuid(m) || `guid:${encodeURIComponent(m.guid || '')}`,
      title: m.title || m.grandparentTitle || 'Title',
      image: m.Image?.find((img: any) => img.type === 'coverArt' || img.type === 'background')?.url || m.thumb || m.parentThumb || m.grandparentThumb,
    }));
    return { title: 'Watchlist', page: { items, next: null } };
  }

  // Trakt browse: trakt:<type>:<mediaType>
  if (bkey.startsWith('trakt:')) {
    const [, type, mediaType] = bkey.split(':') as [string, string, 'movies' | 'shows'];
    return { title: TRAKT_TITLES(mediaType)[type] || 'Trakt', page: { items: await traktRows(type, mediaType), next: null } };
  }

  // Plex library recent: plex:library:<key>:recent
  if (bkey.startsWith('plex:library:') && bkey.endsWith(':recent')) {
    const libKey = bkey.split(':')[2];
    const recent: any = await plexBackendLibraryAll(libKey, { sort: 'addedAt:desc', offset: 0, limit: 50 });
    return { title: 'Recently Added', page: { items: plexRows(recent?.MediaContainer?.Metadata || []), next: null } };
  }

  if (bkey.startsWith('tmdb:')) {
    const [, kind, media, id] = bkey.split(':') as [string, string, 'movie' | 'tv', string];
    if (kind === 'trending') {
      const res: any = await tmdbTrending('', media, (id as 'day' | 'week') || 'week');
      return { title: media === 'movie' ? 'Trending Movies' : 'Trending TV Shows', page: { items: tmdbRows(res?.results || [], media), next: null } };
    }
    if (kind === 'popular') {
      const res: any = await tmdbPopular('', media);
      return { title: media === 'movie' ? 'Popular Movies' : 'Popular TV Shows', page: { items: tmdbRows(res?.results || [], media), next: null } };
    }
    const related = kind === 'recs' ? 'recs' : 'similar';
    return { title: related === 'recs' ? 'Recommendations' : 'More Like This', page: await tmdbRelatedPage(related, media, id, 1) };
  }

  const res: any = await plexBackendDir(bkey);
  const mc = res?.MediaContainer;
  return { title: [mc?.title1, mc?.title2].filter(Boolean).join(' - ') || 'Browse', page: { items: plexRows(mc?.Metadata || []), next: null } };
}

export default function BrowseModal() {
  const [params, setParams] = useSearchParams();
  const nav = useNavigate();
  const open = params.has('bkey');
  const bkey = useMemo(() => (open ? decodeURIComponent(params.get('bkey') || '') : ''), [open, params]);
  const [title, setTitle] = useState('');
  const [items, setItems] = useState<Item[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [next, setNext] = useState<Page['next']>(null);

  useEffect(() => {
    if (!open || !bkey) return;
    let alive = true;
    setLoading(true);
    setError('');
    setItems([]);
    setTitle('');
    setNext(null);
    loadBrowse(bkey)
      .then((result) => {
        if (!alive) return;
        setTitle(result.title);
        setItems(result.page.items);
        setNext(() => result.page.next);
      })
      .catch((e: any) => {
        if (alive) setError(e?.message || 'Failed to load');
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [open, bkey]);

  async function loadMore() {
    if (!next) return;
    try {
      setLoading(true);
      const page = await next();
      setItems((prev) => [...prev, ...page.items]);
      setNext(() => page.next);
    } catch (e: any) {
      setError(e?.message || 'Failed to load next page');
    } finally {
      setLoading(false);
    }
  }

  async function openItem(item: Item) {
    const id = await resolveDetailsId(item);
    if (id) nav(detailsPath(id));
    else appToast(`Could not find details for ${item.title}`);
  }

  const close = () => {
    params.delete('bkey');
    setParams(params, { replace: false });
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm overflow-y-auto" onClick={close}>
      <div className="max-w-6xl mx-auto mt-16 mb-24 px-4" onClick={(e) => e.stopPropagation()}>
        <div className="bg-[#181818] rounded-2xl ring-1 ring-white/10 shadow-2xl p-6">
          <div className="flex items-center mb-4">
            <h2 className="text-2xl font-semibold flex-1">{title || 'Browse'}</h2>
            <button onClick={close} className="btn">Close</button>
          </div>
          {error && <div className="text-red-400 mb-4">{error}</div>}
          {!loading && !error && items.length === 0 && <div className="text-neutral-400">Nothing to show here.</div>}
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
            {items.map((i, idx) => (
              <button key={`${i.id}-${idx}`} className="text-left group" onClick={() => openItem(i)}>
                <div className="w-full aspect-video rounded-xl overflow-hidden ring-1 ring-white/10 bg-neutral-800 card-hover">
                  {i.image && <SmartImage url={i.image} alt={i.title} width={320} className="w-full h-full" imgClassName="object-cover" />}
                </div>
                <div className="mt-1 text-sm line-clamp-2 text-neutral-200 group-hover:text-white transition-colors">{i.title}</div>
              </button>
            ))}
          </div>
          {loading && <div className="mt-4 text-neutral-400">Loading…</div>}
          {!loading && next && (
            <div className="mt-4 flex justify-center">
              <button onClick={loadMore} className="btn">Load more</button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function inferIdFromGuid(m: any): string | undefined {
  const g = String(m.guid || m.tmdbGuid || '');
  if (!g) return undefined;
  const num = (g.match(/(\d{3,})/) || [])[1];
  if (g.includes('tmdb://') && num) {
    const type = m.type === 'movie' ? 'movie' : m.type === 'show' ? 'tv' : 'movie';
    return `tmdb:${type}:${num}`;
  }
  return undefined;
}
