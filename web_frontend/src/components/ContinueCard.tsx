import { useEffect, useState } from 'react';
import { loadSettings } from '@/state/settings';
import { tmdbBestBackdropUrl } from '@/services/tmdb';
import { plexMetadata } from '@/services/plex';
import { plexBackendMetadata } from '@/services/plex_backend';
import SmartImage from './SmartImage';

type Props = { id: string; title: string; image: string; progress: number; onClick?: (id: string) => void };

export default function ContinueCard({ id, title, image, progress, onClick }: Props) {
  const pct = Math.max(0, Math.min(100, progress));
  const [altImg, setAltImg] = useState<string | undefined>(undefined);

  useEffect(() => {
    const s = loadSettings();
    // Upgrade to language-specific TMDB backdrop when possible
    async function upgrade() {
      try {
        if (s.tmdbBearer && id.startsWith('tmdb:')) {
          const parts = id.split(':');
          if (parts.length === 3) {
            const media = parts[1] as 'movie' | 'tv';
            const tmdbId = parts[2];
            const u = await tmdbBestBackdropUrl(s.tmdbBearer!, media, tmdbId, 'en');
            if (u) setAltImg(u);
          }
          return;
        }
        if (s.tmdbBearer && id.startsWith('plex:')) {
          const rk = id.replace(/^plex:/, '');
          const meta: any = await plexBackendMetadata(rk);
          let m = meta?.MediaContainer?.Metadata?.[0];
          // If this is an episode, prefer the show (grandparent) for TMDB mapping/backdrop
          if (m?.type === 'episode' && m?.grandparentRatingKey) {
            const showMeta: any = await plexBackendMetadata(String(m.grandparentRatingKey));
            const sm = showMeta?.MediaContainer?.Metadata?.[0];
            if (sm) m = sm;
          }
          const guid = (m?.Guid || []).map((g:any)=>String(g.id||''))
            .find((g:string)=>g.includes('tmdb://')||g.includes('themoviedb://'));
          if (!guid) return;
          const tid = guid.split('://')[1];
          const media = (m?.type === 'movie') ? 'movie' : 'tv';
          const u = await tmdbBestBackdropUrl(s.tmdbBearer!, media as any, tid, 'en');
          if (u) setAltImg(u);
        }
      } catch {}
    }
    upgrade();
  }, [id]);

  const src = altImg || image;

  return (
    <button onClick={() => onClick?.(id)} className="group flex-shrink-0 w-[360px] md:w-[420px]">
      <div className="relative aspect-[2/1] card card-hover ring-1 ring-white/15 hover:ring-2 hover:ring-white/90 hover:ring-offset-2 hover:ring-offset-transparent transition-all duration-200 group-hover:z-20">
        <SmartImage url={src} alt={title} width={420} className="w-full h-full" imgClassName="object-cover opacity-90 group-hover:opacity-100 transition-opacity" />
        <div className="absolute inset-x-0 bottom-0 h-1.5 bg-black/50">
          <div className="h-full bg-brand" style={{ width: pct + '%' }} />
        </div>
      </div>
    </button>
  );
}
