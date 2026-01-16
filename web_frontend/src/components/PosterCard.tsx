import { useEffect, useState } from 'react';
import { loadSettings } from '@/state/settings';
import SmartImage from './SmartImage';
import { tmdbImage, tmdbDetails } from '@/services/tmdb';
import { plexBackendMetadata } from '@/services/plex_backend';
import WatchlistButton from '@/components/WatchlistButton';

type PosterCardProps = {
  id: string;
  title: string;
  image?: string;
  subtitle?: string;
  badge?: string;
  onClick?: (id: string) => void;
};

export default function PosterCard({ id, title, image, subtitle, badge, onClick }: PosterCardProps) {
  const [altImg, setAltImg] = useState<string | undefined>(undefined);

  // Infer media type and TMDB id from our canonical id scheme
  const normalizedId = (id || '').replaceAll('%3A', ':');
  const [kind, tmdbId] = (() => {
    if (normalizedId.startsWith('tmdb:movie:')) return ['movie', normalizedId.split(':')[2]] as const;
    if (normalizedId.startsWith('tmdb:tv:')) return ['show', normalizedId.split(':')[2]] as const;
    return ['movie', undefined] as const;
  })();

  // Upgrade to TMDB poster when possible
  useEffect(() => {
    const s = loadSettings();
    async function upgrade() {
      try {
        if (s.tmdbBearer && normalizedId.startsWith('tmdb:')) {
          const parts = normalizedId.split(':');
          if (parts.length === 3) {
            const media = parts[1] as 'movie' | 'tv';
            const tid = parts[2];
            const details: any = await tmdbDetails(s.tmdbBearer!, media, tid);
            if (details?.poster_path) {
              const u = tmdbImage(details.poster_path, 'w500');
              if (u) setAltImg(u);
            }
          }
          return;
        }
        if (s.tmdbBearer && normalizedId.startsWith('plex:')) {
          const rk = normalizedId.replace(/^plex:/, '');
          const meta: any = await plexBackendMetadata(rk);
          const m = meta?.MediaContainer?.Metadata?.[0];
          if (!m) return;
          const guid = (m?.Guid || [])
            .map((g: any) => String(g.id || ''))
            .find((g: string) => g.includes('tmdb://') || g.includes('themoviedb://'));
          if (!guid) return;
          const tid = guid.split('://')[1];
          const media = m?.type === 'movie' ? 'movie' : 'tv';
          const details: any = await tmdbDetails(s.tmdbBearer!, media, tid);
          if (details?.poster_path) {
            const u = tmdbImage(details.poster_path, 'w500');
            if (u) setAltImg(u);
          }
        }
      } catch {}
    }
    upgrade();
  }, [normalizedId]);

  const src = altImg || image;

  return (
    <div
      className="group w-[140px] md:w-[160px] flex-shrink-0 text-left cursor-pointer"
      onClick={() => onClick?.(id)}
    >
      <div className="relative rounded-lg overflow-hidden aspect-[2/3] bg-neutral-800 ring-1 ring-white/15 hover:ring-2 hover:ring-white/90 hover:ring-offset-2 hover:ring-offset-transparent transition-all duration-200 group-hover:z-20">
        {src ? (
          <SmartImage
            url={src}
            alt={title}
            width={180}
            className="w-full h-full"
            imgClassName="transition-transform duration-300 group-hover:scale-[1.03]"
          />
        ) : (
          <div className="w-full h-full skeleton" />
        )}
        {badge && (
          <span className="absolute top-2 left-2 text-[10px] font-semibold bg-black/70 text-white px-1.5 py-0.5 rounded">
            {badge}
          </span>
        )}
        {/* Hover overlay */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity" />
        <div className="absolute inset-x-0 bottom-0 p-2 opacity-0 group-hover:opacity-100 transition-opacity">
          <div className="flex items-center justify-end">
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
      <div className="pt-2 px-0.5">
        <p className="text-sm font-medium text-white/90 line-clamp-2">{title}</p>
        {subtitle && <p className="text-xs text-neutral-400 line-clamp-1 mt-0.5">{subtitle}</p>}
      </div>
    </div>
  );
}
