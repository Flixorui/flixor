import { useEffect, useState, useRef } from 'react';
import { loadSettings } from '@/state/settings';
import { tmdbImage, tmdbDetails } from '@/services/tmdb';
import { plexBackendMetadata } from '@/services/plex_backend';
import SmartImage from './SmartImage';

type Props = {
  id: string;
  title: string;
  image: string;
  progress: number;
  duration?: number;
  viewOffset?: number;
  episodeInfo?: string;
  showTitle?: string;
  onClick?: (id: string) => void;
  onRemove?: (id: string) => void;
  onMarkWatched?: (id: string) => void;
};

export default function ContinueWatchingPosterCard({
  id,
  title,
  image,
  progress,
  duration,
  viewOffset,
  episodeInfo,
  showTitle,
  onClick,
  onRemove,
  onMarkWatched,
}: Props) {
  const pct = Math.max(0, Math.min(100, progress));
  const [altImg, setAltImg] = useState<string | undefined>(undefined);
  const [showMenu, setShowMenu] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  // Calculate time remaining
  const timeRemaining = duration && viewOffset ? Math.max(0, duration - viewOffset) : 0;
  const formatTime = (ms: number) => {
    const totalMinutes = Math.floor(ms / 60000);
    if (totalMinutes < 60) return `${totalMinutes}m`;
    const hours = Math.floor(totalMinutes / 60);
    const mins = totalMinutes % 60;
    return mins > 0 ? `${hours}h ${mins}m` : `${hours}h`;
  };

  // Upgrade to TMDB poster
  useEffect(() => {
    const s = loadSettings();
    async function upgrade() {
      try {
        if (s.tmdbBearer && id.startsWith('tmdb:')) {
          const parts = id.split(':');
          if (parts.length === 3) {
            const media = parts[1] as 'movie' | 'tv';
            const tmdbId = parts[2];
            const details: any = await tmdbDetails(s.tmdbBearer!, media, tmdbId);
            if (details?.poster_path) {
              const u = tmdbImage(details.poster_path, 'w500');
              if (u) setAltImg(u);
            }
          }
          return;
        }
        if (s.tmdbBearer && id.startsWith('plex:')) {
          const rk = id.replace(/^plex:/, '');
          const meta: any = await plexBackendMetadata(rk);
          let m = meta?.MediaContainer?.Metadata?.[0];
          // For episodes, use the show's poster
          if (m?.type === 'episode' && m?.grandparentRatingKey) {
            const showMeta: any = await plexBackendMetadata(String(m.grandparentRatingKey));
            const sm = showMeta?.MediaContainer?.Metadata?.[0];
            if (sm) m = sm;
          }
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
  }, [id]);

  // Close menu when clicking outside
  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setShowMenu(false);
      }
    };
    if (showMenu) {
      document.addEventListener('click', handleClick);
      return () => document.removeEventListener('click', handleClick);
    }
  }, [showMenu]);

  const src = altImg || image;
  const displayTitle = showTitle || title;
  const subtitle = showTitle ? title : undefined;

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    setShowMenu(true);
  };

  return (
    <div
      className="group flex-shrink-0 w-[140px] md:w-[160px] lg:w-[180px] relative"
      onContextMenu={handleContextMenu}
    >
      <button
        onClick={() => onClick?.(id)}
        className="w-full text-left"
      >
        {/* Card with 2:3 poster aspect ratio */}
        <div className="relative aspect-[2/3] card card-hover ring-1 ring-white/15 hover:ring-2 hover:ring-white/90 hover:ring-offset-2 hover:ring-offset-transparent transition-all duration-200 group-hover:z-20 overflow-hidden rounded-lg">
          <SmartImage
            url={src}
            alt={displayTitle}
            width={180}
            className="w-full h-full"
            imgClassName="object-cover opacity-90 group-hover:opacity-100 transition-opacity"
          />

          {/* Gradient overlay */}
          <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-black/30 to-transparent" />

          {/* Episode badge */}
          {episodeInfo && (
            <span className="absolute top-2 left-2 text-[10px] font-semibold bg-black/70 text-white px-1.5 py-0.5 rounded">
              {episodeInfo}
            </span>
          )}

          {/* Progress bar at bottom */}
          <div className="absolute inset-x-0 bottom-0">
            {/* Time remaining */}
            {timeRemaining > 0 && (
              <p className="text-white/80 text-[10px] px-2 pb-1">
                {formatTime(timeRemaining)} left
              </p>
            )}
            <div className="h-1 bg-white/20">
              <div
                className="h-full bg-red-600 transition-all duration-300"
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>

        </div>

        {/* Title below card */}
        <div className="mt-2 px-0.5">
          <h3 className="text-white/90 font-medium text-sm line-clamp-1">
            {displayTitle}
          </h3>
          {subtitle && (
            <p className="text-neutral-400 text-xs line-clamp-1 mt-0.5">
              {subtitle}
            </p>
          )}
        </div>
      </button>

      {/* Context menu */}
      {showMenu && (
        <div
          ref={menuRef}
          className="absolute top-2 right-2 z-50 bg-neutral-900 border border-white/10 rounded-lg shadow-xl overflow-hidden min-w-[140px]"
        >
          <button
            onClick={(e) => {
              e.stopPropagation();
              onRemove?.(id);
              setShowMenu(false);
            }}
            className="w-full px-3 py-2 text-left text-xs text-white hover:bg-white/10 transition-colors flex items-center gap-2"
          >
            <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
            Remove
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onMarkWatched?.(id);
              setShowMenu(false);
            }}
            className="w-full px-3 py-2 text-left text-xs text-white hover:bg-white/10 transition-colors flex items-center gap-2"
          >
            <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
            Mark Watched
          </button>
        </div>
      )}

      {/* Menu toggle button */}
      <button
        onClick={(e) => {
          e.stopPropagation();
          setShowMenu(!showMenu);
        }}
        className="absolute top-2 right-2 w-6 h-6 rounded-full bg-black/60 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity hover:bg-black/80 z-10"
      >
        <svg className="w-4 h-4 text-white" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z" />
        </svg>
      </button>
    </div>
  );
}
