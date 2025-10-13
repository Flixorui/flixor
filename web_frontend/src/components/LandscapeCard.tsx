import { useEffect, useState } from 'react';
import { loadSettings } from '@/state/settings';
import SmartImage from './SmartImage';
import { tmdbBestBackdropUrl } from '@/services/tmdb';
import { plexMetadata, plexFindByGuid } from '@/services/plex';
import { plexBackendMetadata } from '@/services/plex_backend';
import { cached } from '@/services/cache';
import WatchlistButton from '@/components/WatchlistButton';

type CardProps = { id: string; title: string; image: string; badge?: string; onClick?: (id: string) => void; layout?: 'row' | 'grid' };

export default function LandscapeCard({ id, title, image, badge, onClick, layout = 'row' }: CardProps) {
  const [altImg, setAltImg] = useState<string | undefined>(undefined);
  const [mappedPlexId, setMappedPlexId] = useState<string | undefined>(undefined);
  const [availabilityChecked, setAvailabilityChecked] = useState(false);
  const playable = id.startsWith('plex:') || (!!mappedPlexId);
  // Infer media type and TMDB id from our canonical id scheme
  id = id.replaceAll('%3A', ':');
  const [kind, tmdbId] = (() => {
    if (id.startsWith('tmdb:movie:')) return ['movie', id.split(':')[2]] as const;
    if (id.startsWith('tmdb:tv:')) return ['show', id.split(':')[2]] as const;
    return ['movie', undefined] as const;
  })();
  useEffect(() => {
    const s = loadSettings();
    // If this is a TMDB item, try to fetch a language-specific backdrop (with title text)
    if (s.tmdbBearer && id.startsWith('tmdb:')) {
      const parts = id.split(':'); // tmdb:<media>:<id>
      if (parts.length === 3) {
        const media = parts[1] as 'movie' | 'tv';
        const tmdbId = parts[2];
        tmdbBestBackdropUrl(s.tmdbBearer!, media, tmdbId, 'en').then((u) => { if (u) setAltImg(u); }).catch(()=>{});
      }
    }
    // Attempt Plex -> TMDB mapping for backdrop upgrade if possible (best-effort, cached)
    else if (s.tmdbBearer && id.startsWith('plex:')) {
      const rk = id.replace(/^plex:/,'');
      plexBackendMetadata(rk).then(async (meta: any) => {
        try {
          const m = meta?.MediaContainer?.Metadata?.[0];
          const guid = (m?.Guid || []).map((g:any)=>String(g.id||''))
            .find((g:string)=>g.includes('tmdb://')||g.includes('themoviedb://'));
          if (!guid) return;
          const tid = guid.split('://')[1];
          const media = (m?.type === 'movie') ? 'movie' : 'tv';
          const u = await tmdbBestBackdropUrl(s.tmdbBearer!, media as any, tid, 'en');
          if (u) setAltImg(u);
        } catch {}
      }).catch(()=>{});
    }
    // If TMDB item, try to map to Plex to determine availability badge and enable play
    setAvailabilityChecked(false);
    (async () => {
      try {
        const s2 = loadSettings();
        if (!s2.plexBaseUrl || !s2.plexToken) return;
        if (!id.startsWith('tmdb:')) return;
        const parts = id.split(':');
        if (parts.length !== 3) return;
        const media = parts[1] as 'movie' | 'tv';
        const tmdb = parts[2];
        const typeNum = media === 'movie' ? 1 : 2;
        const key = `plex:map:${typeNum}:${tmdb}`;
        const mapped = await cached(key, 30 * 60 * 1000, async () => {
          try {
            const byGuid: any = await plexFindByGuid({ baseUrl: s2.plexBaseUrl!, token: s2.plexToken! }, `tmdb://${tmdb}`, typeNum);
            const hit = byGuid?.MediaContainer?.Metadata?.[0];
            if (hit?.ratingKey) return String(hit.ratingKey);
          } catch {}
          try {
            const byGuid2: any = await plexFindByGuid({ baseUrl: s2.plexBaseUrl!, token: s2.plexToken! }, `themoviedb://${tmdb}`, typeNum);
            const hit2 = byGuid2?.MediaContainer?.Metadata?.[0];
            if (hit2?.ratingKey) return String(hit2.ratingKey);
          } catch {}
          return '';
        });
        if (mapped) setMappedPlexId(`plex:${mapped}`); else setMappedPlexId(undefined);
      } catch {}
      finally { setAvailabilityChecked(true); }
    })();
  }, [id]);
  const src = altImg || image;
  const wrapperClass = layout === 'grid' ? 'group relative z-0 w-full cursor-pointer' : 'group relative z-0 flex-shrink-0 w-[360px] md:w-[420px] cursor-pointer';
  const aspectClass = layout === 'grid' ? 'aspect-video' : 'aspect-[2/1]';
  return (
    <div className={wrapperClass} onClick={() => onClick?.(id)}>
      <div className={`relative ${aspectClass} card card-hover ring-1 ring-white/15 hover:ring-2 hover:ring-white/90 hover:ring-offset-2 hover:ring-offset-transparent transition-all duration-200 group-hover:z-20`}>
                <div className="w-full h-full">
                  <SmartImage url={src} alt={title} width={360} className="w-full h-full" imgClassName="transition-transform duration-300 group-hover:scale-[1.03]" />
                </div>
        {/* Top-left badge */}
        {badge && <span className="absolute top-2 left-2 text-xs bg-black/70 text-white px-2 py-0.5 rounded">{badge}</span>}
        {/* Hover overlay actions */}
        <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-black/75 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
        <div className="absolute inset-0 p-3 flex items-end justify-between opacity-0 group-hover:opacity-100 transition-opacity">
          {/* Title */}
          <div className="pointer-events-none max-w-[70%]">
            <div className="text-white font-semibold text-sm line-clamp-2 drop-shadow-lg">{title}</div>
          </div>
          <div className="flex items-center gap-2">
            {/* Watchlist */}
            <WatchlistButton
              itemId={id}
              itemType={kind}
              tmdbId={tmdbId}
              variant="button"
              className="pointer-events-auto"
            />
          </div>
        </div>
      </div>
    </div>
  );
}
