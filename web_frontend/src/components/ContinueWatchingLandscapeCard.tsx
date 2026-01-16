import { useEffect, useState, useRef } from 'react';
import { loadSettings } from '@/state/settings';
import { tmdbBestBackdropUrl } from '@/services/tmdb';
import { plexBackendMetadata } from '@/services/plex_backend';
import SmartImage from './SmartImage';

type Props = {
  id: string;
  title: string;
  image: string;
  progress: number;
  duration?: number; // total duration in ms
  viewOffset?: number; // current position in ms
  episodeInfo?: string; // e.g., "S01E05"
  showTitle?: string; // for episodes, the show name
  onClick?: (id: string) => void;
  onRemove?: (id: string) => void;
  onMarkWatched?: (id: string) => void;
};

export default function ContinueWatchingLandscapeCard({
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

  // Upgrade to TMDB backdrop
  useEffect(() => {
    const s = loadSettings();
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
          // For episodes, use the show's backdrop
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
          const u = await tmdbBestBackdropUrl(s.tmdbBearer!, media as any, tid, 'en');
          if (u) setAltImg(u);
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
  const subtitle = showTitle ? title : undefined; // Episode title when showing show name

  const handleContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    setShowMenu(true);
  };

  return (
    <div
      className="group flex-shrink-0 w-[320px] md:w-[380px] lg:w-[420px] relative"
      onContextMenu={handleContextMenu}
    >
      <button
        onClick={() => onClick?.(id)}
        className="w-full text-left"
      >
        {/* Card with 16:9 aspect ratio */}
        <div className="relative aspect-video rounded-xl overflow-hidden bg-neutral-800">
          <SmartImage
            url={src}
            alt={displayTitle}
            width={420}
            className="w-full h-full"
            imgClassName="object-cover"
          />

          {/* Bottom gradient - subtle like mobile */}
          <div className="absolute bottom-0 left-0 right-0 h-[50px] bg-gradient-to-t from-black/60 to-transparent rounded-b-xl" />

          {/* Controls row at bottom - matching mobile layout */}
          <div className="absolute bottom-0 left-0 right-0 px-3 pb-2.5 flex items-center justify-between">
            {/* Left: Play icon + progress bar + time */}
            <div className="flex items-center gap-1.5">
              {/* Play icon */}
              <svg className="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>

              {/* Short progress bar */}
              <div className="w-7 h-1 bg-white/40 rounded-full overflow-hidden">
                <div
                  className="h-full bg-white rounded-full"
                  style={{ width: `${pct}%` }}
                />
              </div>

              {/* Time remaining */}
              {timeRemaining > 0 && (
                <span className="text-white text-[11px] font-medium">
                  {formatTime(timeRemaining)}
                </span>
              )}
            </div>

            {/* Right: Menu button */}
            <button
              onClick={(e) => {
                e.stopPropagation();
                setShowMenu(!showMenu);
              }}
              className="p-1 text-white/60 hover:text-white transition-colors"
            >
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <path d="M6 10c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm12 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm-6 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z" />
              </svg>
            </button>
          </div>
        </div>
      </button>

      {/* Context menu */}
      {showMenu && (
        <div
          ref={menuRef}
          className="absolute bottom-12 right-2 z-50 bg-neutral-900 border border-white/10 rounded-lg shadow-xl overflow-hidden min-w-[160px]"
        >
          <button
            onClick={(e) => {
              e.stopPropagation();
              onClick?.(id.replace('/player/', '/details/').replace('plex:', 'plex:'));
              setShowMenu(false);
            }}
            className="w-full px-4 py-2.5 text-left text-sm text-white hover:bg-white/10 transition-colors flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            Info
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onMarkWatched?.(id);
              setShowMenu(false);
            }}
            className="w-full px-4 py-2.5 text-left text-sm text-white hover:bg-white/10 transition-colors flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
            Mark as Watched
          </button>
          <button
            onClick={(e) => {
              e.stopPropagation();
              onRemove?.(id);
              setShowMenu(false);
            }}
            className="w-full px-4 py-2.5 text-left text-sm text-red-400 hover:bg-white/10 transition-colors flex items-center gap-2"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            Remove
          </button>
        </div>
      )}
    </div>
  );
}
