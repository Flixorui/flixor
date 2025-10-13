import Billboard from '@/components/Billboard';
import HomeHero from '@/components/HomeHero';
import Row from '@/components/Row';
import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { loadSettings, saveSettings } from '@/state/settings';
import { apiClient, checkAuth } from '@/services/api';
import { tmdbTrending, tmdbImage, tmdbVideos, tmdbImages, tmdbDetails } from '@/services/tmdb';
import { traktTrending, isTraktAuthenticated } from '@/services/trakt';
import { plexPartUrl } from '@/services/plex';
import { plexBackendOnDeckGlobal, plexBackendContinue, plexBackendLibraries, plexBackendLibrarySecondary, plexBackendDir, plexBackendLibraryAll, plexBackendMetadataWithExtras } from '@/services/plex_backend';
import BrowseModal from '@/components/BrowseModal';
import { plexTvWatchlist } from '@/services/plextv';
import SectionBanner from '@/components/SectionBanner';
import { TraktSection } from '@/components/TraktSection';

type Item = { id: string; title: string; image?: string; subtitle?: string; badge?: string };

export default function Home() {
  const nav = useNavigate();
  const [loading, setLoading] = useState(true);
  const [rows, setRows] = useState<Array<{ title: string; items: Item[]; variant?: 'default'|'continue' }>>([]);
  const [needsPlex, setNeedsPlex] = useState(false);
  const [hero, setHero] = useState<{ title: string; overview?: string; poster?: string; backdrop?: string; rating?: string; videoUrl?: string; ytKey?: string; id?: string; year?: string; runtime?: number; genres?: string[]; logoUrl?: string } | null>(null);
  const genreRows: Array<{label: string; type: 'movie'|'show'; genre: string}> = [
    { label: 'TV Shows - Children', type: 'show', genre: 'Children' },
    { label: 'Movie - Music', type: 'movie', genre: 'Music' },
    { label: 'Movies - Documentary', type: 'movie', genre: 'Documentary' },
    { label: 'Movies - History', type: 'movie', genre: 'History' },
    { label: 'TV Shows - Reality', type: 'show', genre: 'Reality' },
    { label: 'Movies - Drama', type: 'movie', genre: 'Drama' },
    { label: 'TV Shows - Suspense', type: 'show', genre: 'Suspense' },
    { label: 'Movies - Animation', type: 'movie', genre: 'Animation' },
  ];

  const didInit = useRef(false);
  useEffect(() => {
    if (didInit.current) return; // prevent StrictMode double-run flicker
    didInit.current = true;

    // Check backend authentication first
    (async () => {
      const isAuthenticated = await checkAuth();
      if (!isAuthenticated) {
        nav('/login');
        return;
      }

      // Get servers from backend
      try {
        const servers = await apiClient.getServers();
        if (servers.length > 0) {
          const server = servers[0];
          saveSettings({
            plexBaseUrl: server.baseUrl,
            plexToken: server.token,
            plexServer: {
              name: server.name,
              clientIdentifier: server.clientIdentifier,
              baseUrl: server.baseUrl,
              token: server.token
            }
          });
        }
      } catch (err) {
        console.error('Failed to get servers:', err);
      }

      // Continue with loading content
      run();
    })();

    // run() function is called from the auth check above
    async function run() {
      try {
        let s = loadSettings(); // Load settings here

        // Use default TMDB API key if not configured
        if (!s.tmdbBearer) {
          const DEFAULT_TMDB_KEY = 'db55323b8d3e4154498498a75642b381';
          saveSettings({ tmdbBearer: DEFAULT_TMDB_KEY });
          s = loadSettings();
        }
        const rowsData: Array<{ title: string; items: Item[]; variant?: 'default'|'continue' }> = [];
        let tmdbHero: any | null = null;
        let plexHero: any | null = null;
        let heroLogoUrl: string | undefined = undefined;
        if (s.tmdbBearer) {
          const tmdb = await tmdbTrending(s.tmdbBearer, 'tv', 'week');
          const items: Item[] = (tmdb as any).results?.slice(0, 16).map((r: any) => ({
            id: `tmdb:tv:${String(r.id)}`,
            title: r.name || r.title,
            image: tmdbImage(r.backdrop_path, 'w780') || tmdbImage(r.poster_path, 'w500'),
          })) || [];
          rowsData.push({ title: 'Popular on Plex', items: items.slice(0, 8) });
          rowsData.push({ title: 'Trending Now', items: items.slice(8, 16) });
          // Prepare TMDB fallback hero (do not set yet)
          try {
            if ((tmdb as any).results?.length) {
              const f = (tmdb as any).results[0];
              let ytKey: string | undefined;
              try { const vids: any = await tmdbVideos(s.tmdbBearer!, 'tv', String(f.id)); ytKey = (vids.results||[]).find((v:any)=>v.site==='YouTube')?.key; } catch {}

              // Get additional details for the hero
              let genres: string[] = [];
              let year: string | undefined;
              let runtime: number | undefined;
              try {
                const details: any = await tmdbDetails(s.tmdbBearer!, 'tv', String(f.id));
                genres = (details.genres || []).map((g: any) => g.name);
                year = (details.first_air_date || '').slice(0, 4);
                runtime = details.episode_run_time?.[0];
              } catch {}

              tmdbHero = {
                title: f.name||f.title,
                overview: f.overview,
                poster: tmdbImage(f.poster_path,'w500')||undefined,
                backdrop: tmdbImage(f.backdrop_path,'w1280')||undefined,
                rating: undefined,
                ytKey,
                id: `tmdb:tv:${String(f.id)}`,
                genres,
                year,
                runtime
              };
              try {
                const imgs: any = await tmdbImages(s.tmdbBearer!, 'tv', String(f.id), 'en,null');
                const logo = (imgs?.logos||[]).find((l:any)=>l.iso_639_1==='en') || (imgs?.logos||[])[0];
                if (logo?.file_path) heroLogoUrl = tmdbImage(logo.file_path, 'w500') || tmdbImage(logo.file_path, 'original');
              } catch {}
            }
          } catch {}
        } else {
          // Fallback placeholders (no TMDB key)
          const landscape = Array.from({ length: 16 }).map((_, i) => ({ id: 'ph'+i, title: `Sample ${i+1}`, image: `https://picsum.photos/seed/land${i}/800/400` }));
          rowsData.push({ title: 'Popular on Plex', items: landscape.slice(0, 8) });
          rowsData.push({ title: 'Trending Now', items: landscape.slice(8, 16) });
        }
        // Trakt content will be handled by TraktSection components below
        // Continue Watching via Plex if configured
        // eslint-disable-next-line no-console
        console.info('[Home] Using backend for Plex reads');
        if (s.plexBaseUrl && s.plexToken) {
          try {
            const deck: any = await plexBackendContinue();
            const meta = deck?.MediaContainer?.Metadata || [];
            const items: any[] = meta.slice(0, 10).map((m: any, i: number) => {
              const p = m.thumb || m.parentThumb || m.grandparentThumb || m.art;
              const img = apiClient.getPlexImageNoToken(p || '');
              const duration = (m.duration || 0) / 1000;
              const vo = (m.viewOffset || 0) / 1000;
              const progress = duration > 0 ? Math.min(100, Math.max(1, Math.round((vo / duration) * 100))) : 0;
              return { id: `plex:${String(m.ratingKey || i)}`, title: m.title || m.grandparentTitle || 'Continue', image: img, progress };
            });
            rowsData.splice(1, 0, { title: 'Continue Watching', items: items as any, variant: 'continue' });
          } catch (e) {
            setNeedsPlex(true);
          }
          // Watchlist via Plex.tv if configured
          if (true) {
            try {
              const wl: any = await plexTvWatchlist();
              const meta = wl?.MediaContainer?.Metadata || [];
              const wlItems: Item[] = meta.slice(0, 12).map((m: any, i: number) => ({
                id: inferIdFromGuid(m) || `${encodeURIComponent(m.tmdbGuid||'')}`,
                title: m.title || m.grandparentTitle || 'Title',
                image: m.Image?.find((img: any) => img.type === 'coverArt' || img.type === 'background')?.url,
              }));
              const row: any = { title: 'Watchlist', items: wlItems };
              row.browseKey = '/plextv/watchlist';
              rowsData.push(row);
            } catch {}
          }
          // Genre-based rows from first matching library containing that genre
          try {
            const libs: any = await plexBackendLibraries();
            const dirs = libs?.MediaContainer?.Directory || [];
            for (const gr of genreRows) {
              const lib = dirs.find((d: any) => d.type === (gr.type === 'movie' ? 'movie' : 'show'));
              if (!lib) continue;
              try {
                const gens: any = await plexBackendLibrarySecondary(String(lib.key), 'genre');
                const gx = (gens?.MediaContainer?.Directory || []).find((g: any) => String(g.title).toLowerCase() === gr.genre.toLowerCase());
                if (!gx) continue;
                const path = `/library/sections/${lib.key}/genre/${gx.key}`;
                const data: any = await plexBackendDir(path);
                const meta = data?.MediaContainer?.Metadata || [];
                const items: Item[] = meta.slice(0, 12).map((m: any) => {
                  const p = m.thumb || m.parentThumb || m.grandparentThumb || m.art;
                  const img = apiClient.getPlexImageNoToken(p || '');
                  return { id: `plex:${m.ratingKey}`, title: m.title || m.grandparentTitle || 'Title', image: img };
                });
                const row: any = { title: gr.label, items };
                row.browseKey = path;
                rowsData.push(row);
              } catch {}
            }
          } catch {}
          // Try to build a Plex-based hero like Nevu
          try {
              const libs: any = await plexBackendLibraries();
            const dirs = libs?.MediaContainer?.Directory || [];
            const elig = dirs.filter((d: any) => d.type === 'movie' || d.type === 'show');
            for (let attempts = 0; attempts < 8; attempts++) {
              const lib = elig[Math.floor(Math.random() * Math.max(1, elig.length))];
              if (!lib) break;
              const t = lib.type === 'movie' ? 1 : 2;
              const q = `?type=${t}&sort=random:desc&X-Plex-Container-Start=0&X-Plex-Container-Size=1`;
              const res: any = await plexBackendLibraryAll(String(lib.key), { type: t, sort: 'random:desc', offset: 0, limit: 1 });
              const m = res?.MediaContainer?.Metadata?.[0];
              if (!m) continue;
              const meta: any = await plexBackendMetadataWithExtras(String(m.ratingKey));
              const mm = meta?.MediaContainer?.Metadata?.[0];
              if (!mm) continue;
              const pPoster = mm.thumb || mm.parentThumb || mm.grandparentThumb;
              const pBackdrop = mm.art || mm.parentThumb || mm.grandparentThumb || mm.thumb;
              const poster = apiClient.getPlexImageNoToken(pPoster || '');
              const backdrop = apiClient.getPlexImageNoToken(pBackdrop || '');
              const extra = mm?.Extras?.Metadata?.[0]?.Media?.[0]?.Part?.[0]?.key as string | undefined;
              const videoUrl = extra ? plexPartUrl(s.plexBaseUrl!, s.plexToken!, extra) : undefined;

              // Extract metadata for hero
              const genres = (mm.Genre || []).map((g: any) => g.tag);
              const year = mm.year ? String(mm.year) : undefined;
              const runtime = mm.duration ? Math.round(mm.duration / 60000) : undefined;

              plexHero = {
                title: mm.title || mm.grandparentTitle || 'Title',
                overview: mm.summary,
                poster,
                backdrop,
                rating: mm.contentRating || undefined,
                videoUrl,
                id: `plex:${String(mm.ratingKey)}`,
                genres,
                year,
                runtime
              };
              // If this item has a TMDB GUID, try TMDB logo and dispatch
              try {
                const tmdbGuid = (mm.Guid || []).map((g:any)=>String(g.id||''))
                  .find((g:string)=>g.includes('tmdb://')||g.includes('themoviedb://'));
                if (tmdbGuid && s.tmdbBearer) {
                  const tid = tmdbGuid.split('://')[1];
                  const mediaType = (mm.type === 'movie') ? 'movie' : 'tv';
                  const imgs: any = await tmdbImages(s.tmdbBearer!, mediaType as any, tid, 'en,null');
                  const logo = (imgs?.logos||[]).find((l:any)=>l.iso_639_1==='en') || (imgs?.logos||[])[0];
                  if (logo?.file_path) heroLogoUrl = tmdbImage(logo.file_path, 'w500') || tmdbImage(logo.file_path, 'original');
                }
              } catch {}
              break;
            }
          } catch (e) { /* ignore */ }
        } else {
          setNeedsPlex(true);
        }
        setRows(rowsData);
        // Commit hero once with final choice (prefer Plex)
        const finalHero = plexHero || tmdbHero;
        if (!hero && finalHero) {
          // Add logo URL to hero data
          if (heroLogoUrl) {
            finalHero.logoUrl = heroLogoUrl;
          }
          setHero(finalHero);
          if (heroLogoUrl) window.dispatchEvent(new CustomEvent('home-hero-logo', { detail: { logoUrl: heroLogoUrl } }));
        }
      } catch (e) {
        console.error(e);
      } finally {
        setLoading(false);
      }
    }
  }, []);

  // Refresh entire app when server changes
  useEffect(() => {
    const handler = () => window.location.reload();
    // @ts-ignore - CustomEvent typing
    window.addEventListener('plex-server-changed', handler as any);
    return () => {
      // @ts-ignore - CustomEvent typing
      window.removeEventListener('plex-server-changed', handler as any);
    };
  }, []);

  return (
    <div className="pb-10">
      {/* Spacer to separate hero from transparent nav */}
      <div className="pt-24" />
      {hero ? (
        <HomeHero
          title={hero.title}
          overview={hero.overview}
          posterUrl={hero.poster}
          backdropUrl={hero.backdrop}
          rating={hero.rating}
          year={hero.year}
          runtime={hero.runtime}
          genres={hero.genres}
          logoUrl={hero.logoUrl}
          videoUrl={hero.videoUrl}
          ytKey={hero.ytKey}
          onPlay={() => { if (hero.id) nav(`/player/${encodeURIComponent(hero.id)}`); }}
          onMoreInfo={() => { if (hero.id) nav(`/details/${encodeURIComponent(hero.id)}`); }}
        />
      ) : (
        <div className="bleed" style={{ padding: '20px' }}>
          <div className="rounded-2xl overflow-hidden ring-1 ring-white/10 bg-neutral-900/40 h-[56vh] md:h-[64vh] xl:h-[68vh] skeleton" />
        </div>
      )}
      <div className="mt-6" />
      {needsPlex && (
        <SectionBanner title="Continue Watching" message="Connect your Plex account to see your in‑progress shows and movies here." cta="Open Settings" to="/settings" />
      )}
      {!loading && rows.map((r: any) => (
        <Row key={r.title} title={r.title} items={r.items as any} variant={r.variant} browseKey={r.browseKey} onItemClick={(id) => nav(`/details/${encodeURIComponent(id)}`)} />
      ))}

      {/* Trakt Sections */}
      <div className="mt-8 space-y-8">
        <TraktSection type="trending" mediaType="movies" />
        <TraktSection type="trending" mediaType="shows" />
        {isTraktAuthenticated() && (
          <>
            <TraktSection type="watchlist" mediaType="movies" />
            <TraktSection type="history" mediaType="shows" />
            <TraktSection type="recommendations" mediaType="movies" />
          </>
        )}
        <TraktSection type="popular" mediaType="shows" />
      </div>

      <BrowseModal />
    </div>
  );
}

function inferIdFromGuid(m: any): string | undefined {
  const g = String(m.tmdbGuid || '');
  if (!g) return undefined;
  const num = (g.match(/(\d{3,})/) || [])[1];
  if (g.includes('tmdb://') && num) {
    const type = (m.type === 'movie') ? 'movie' : (m.type === 'show' ? 'tv' : 'movie');
    return `tmdb:${type}:${num}`;
  }
  return undefined;
}
