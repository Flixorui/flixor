import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import SmartImage from '@/components/SmartImage';
import { tmdbDetails, tmdbImage, tmdbImages, tmdbVideos } from '@/services/tmdb';
import { useSettings } from '@/state/settings';
import { detailsPath, resolvePlayerRoute } from './cardMedia';
import { isInMyList, resolveCardMedia, setInMyList, supportsMyList } from './cardActions';
import type { CardMedia } from './cardMedia';
import type { CardItem } from './cardTypes';

const PREVIEW_WIDTH = 320;
const EDGE_MARGIN = 12;
const MAX_PREVIEW_WIDTH = 460;
/** Wait after the preview appears before a trailer is looked up and started. */
const TRAILER_SETTLE_MS = 900;

interface PreviewData {
  title: string;
  overview?: string;
  year?: string;
  runtime?: string;
  rating?: number;
  genres: string[];
  backdrop?: string;
  logo?: string;
}

function formatRuntime(minutes?: number) {
  if (!minutes) return undefined;
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return hours ? `${hours}h${mins ? ` ${mins}m` : ''}` : `${mins}m`;
}

/** Preview shown over a card after the pointer rests on it. At most one at a time. */
export default function HoverPreview({
  item,
  anchor,
  onOpen,
  navigate,
  onPointerEnter,
  onPointerLeave,
}: {
  item: CardItem;
  anchor: DOMRect;
  onOpen?: () => void;
  navigate: (path: string) => void;
  onPointerEnter: () => void;
  onPointerLeave: () => void;
}) {
  const settings = useSettings();
  const ref = useRef<HTMLDivElement>(null);
  const [top, setTop] = useState(anchor.top);
  const [media, setMedia] = useState<CardMedia | null>(null);
  const [playRoute, setPlayRoute] = useState<string | null>(null);
  const [inList, setInList] = useState<boolean | null>(null);
  const [trailerKey, setTrailerKey] = useState<string | null>(null);
  const [data, setData] = useState<PreviewData>({
    title: item.showTitle || item.title,
    overview: item.overview,
    year: item.year ? String(item.year) : undefined,
    rating: item.rating,
    genres: [],
    backdrop: item.backdrop || item.image,
  });

  // Not in Plex: Play goes through the addons, via the details page's source picker.
  const canPlayFromAddons = !playRoute && settings.stremioPlaybackEnabled && !!(media?.tmdbId || (media as any)?.imdbId);

  // Always wider than the card it grows out of, so nothing of the card shows around it.
  const width = Math.round(Math.min(
    Math.max(PREVIEW_WIDTH, anchor.width * 1.06),
    MAX_PREVIEW_WIDTH,
    window.innerWidth - EDGE_MARGIN * 2,
  ));
  const left = Math.max(
    EDGE_MARGIN,
    Math.min(anchor.left + anchor.width / 2 - width / 2, window.innerWidth - width - EDGE_MARGIN),
  );

  // Grows from the card's exact box: starts transformed onto the card, then eases to its own box.
  const [grown, setGrown] = useState(false);
  const [height, setHeight] = useState(0);

  useLayoutEffect(() => {
    const measured = ref.current?.offsetHeight ?? 0;
    setHeight(measured);
    const centered = anchor.top + anchor.height / 2 - measured / 2;
    setTop(Math.max(EDGE_MARGIN, Math.min(centered, window.innerHeight - measured - EDGE_MARGIN)));
  }, [anchor.top, anchor.height, data, playRoute, inList, width]);

  useEffect(() => {
    if (!height || grown) return;
    const frame = requestAnimationFrame(() => requestAnimationFrame(() => setGrown(true)));
    return () => cancelAnimationFrame(frame);
  }, [height, grown]);

  const reduceMotion = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  const fromCard = !grown && height > 0 && !reduceMotion
    ? `translate(${anchor.left - left}px, ${anchor.top - top}px) scale(${anchor.width / width}, ${anchor.height / height})`
    : undefined;

  useEffect(() => {
    let alive = true;
    (async () => {
      const resolved = await resolveCardMedia(item.id, item.mediaType).catch(() => null);
      if (!alive || !resolved) return;
      setMedia(resolved);
      resolvePlayerRoute(item.id, item.mediaType)
        .then((route) => alive && setPlayRoute(route))
        .catch(() => {});
      if (supportsMyList(resolved.mediaType || item.mediaType)) {
        isInMyList(resolved)
          .then((listed) => alive && setInList(listed))
          .catch(() => {});
      }
      const reference = await referenceFor(resolved);
      if (!alive || !reference) return;
      const [details, images]: any[] = await Promise.all([
        tmdbDetails('', reference.media, reference.tmdbId).catch(() => null),
        tmdbImages('', reference.media, reference.tmdbId, 'en,null').catch(() => null),
      ]);
      if (!alive) return;
      const logo = (images?.logos || []).find((l: any) => l.iso_639_1 === 'en') || images?.logos?.[0];
      const textless = (images?.backdrops || []).filter((b: any) => b.iso_639_1 == null);
      const backdrop = textless[0] || images?.backdrops?.[0];
      setData((current) => ({
        ...current,
        overview: current.overview || details?.overview,
        year: current.year || String(details?.release_date || details?.first_air_date || '').slice(0, 4) || undefined,
        runtime: formatRuntime(details?.runtime || details?.episode_run_time?.[0]),
        rating: current.rating || details?.vote_average || undefined,
        genres: (details?.genres || []).slice(0, 3).map((g: any) => g.name),
        backdrop: backdrop?.file_path ? tmdbImage(backdrop.file_path, 'w780') : current.backdrop,
        logo: logo?.file_path ? tmdbImage(logo.file_path, 'w500') : undefined,
      }));
      if (settings.cardHoverTrailerMode === 'off') return;
      await new Promise((resolve) => setTimeout(resolve, TRAILER_SETTLE_MS));
      if (!alive) return;
      const videos: any = await tmdbVideos('', reference.media, reference.tmdbId).catch(() => null);
      const list: any[] = videos?.results || [];
      const trailer = list.find((v) => v.site === 'YouTube' && v.type === 'Trailer') || list.find((v) => v.site === 'YouTube');
      if (alive && trailer?.key) setTrailerKey(trailer.key);
    })();
    return () => {
      alive = false;
    };
  }, [item.id, item.mediaType, settings.cardHoverTrailerMode]);

  const open = () => (onOpen ? onOpen() : navigate(detailsPath(item.id)));
  const muted = settings.cardHoverTrailerMode !== 'sound';
  const meta = [data.year, data.runtime, data.rating ? `★ ${Number(data.rating).toFixed(1)}` : undefined].filter(Boolean);

  return createPortal(
    <div
      ref={ref}
      className="fixed z-[150] rounded-2xl overflow-hidden bg-neutral-900 ring-1 ring-white/15 shadow-2xl"
      style={{
        top,
        left,
        width,
        transformOrigin: '0 0',
        transform: fromCard,
        // Hidden until measured, so the first frame is never at the wrong size.
        visibility: height ? 'visible' : 'hidden',
        transition: grown && !reduceMotion ? 'transform 260ms cubic-bezier(0.2, 0.8, 0.2, 1)' : undefined,
      }}
      onMouseEnter={onPointerEnter}
      onMouseLeave={onPointerLeave}
      // React events bubble through portals; keep these away from the card underneath.
      onClick={(event) => event.stopPropagation()}
      onKeyDown={(event) => event.stopPropagation()}
      onContextMenu={(event) => event.stopPropagation()}
    >
      <button className="relative block w-full aspect-video bg-neutral-800" onClick={open} aria-label={`Open ${data.title}`}>
        {data.backdrop && <SmartImage url={data.backdrop} alt="" width={width} className="absolute inset-0 w-full h-full" />}
        {trailerKey && (
          <iframe
            className="absolute inset-0 w-full h-full pointer-events-none"
            title="Trailer"
            src={`https://www.youtube-nocookie.com/embed/${encodeURIComponent(trailerKey)}?autoplay=1&mute=${muted ? 1 : 0}&controls=0&rel=0&playsinline=1&modestbranding=1`}
            allow="autoplay; encrypted-media"
            referrerPolicy="strict-origin-when-cross-origin"
          />
        )}
        <div className="absolute inset-x-0 bottom-0 h-24 bg-gradient-to-t from-neutral-900 to-transparent" />
        <div className="absolute left-3 bottom-2 right-3 text-left">
          {data.logo ? (
            <img src={data.logo} alt={data.title} className="max-h-12 max-w-[60%] object-contain" />
          ) : (
            <span className="text-white font-bold text-lg line-clamp-1">{data.title}</span>
          )}
        </div>
      </button>
      <div className="p-3">
        <div className="flex items-center gap-2">
          {(playRoute || canPlayFromAddons) && (
            <button
              onClick={() => navigate(playRoute ?? `${detailsPath(item.id)}?play=1`)}
              className="inline-flex items-center px-4 py-1.5 text-sm font-semibold rounded-md bg-white text-black hover:bg-white/90"
            >
              <svg className="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
              Play
            </button>
          )}
          <button onClick={open} className="px-4 py-1.5 text-sm font-medium rounded-md bg-white/15 text-white hover:bg-white/25">
            Details
          </button>
          {media && inList !== null && (
            <button
              onClick={async () => {
                const next = !inList;
                setInList(next);
                if (!(await setInMyList(media, next, data.title))) setInList(!next);
              }}
              className="px-3 py-1.5 text-sm font-medium rounded-md bg-white/15 text-white hover:bg-white/25"
            >
              {inList ? 'In My List' : 'My List'}
            </button>
          )}
        </div>
        {meta.length > 0 && <p className="mt-2 text-xs text-white/80">{meta.join(' • ')}</p>}
        {item.subtitle && <p className="mt-1 text-xs text-white/60 line-clamp-1">{item.subtitle}</p>}
        {data.genres.length > 0 && <p className="mt-1 text-xs text-white/60">{data.genres.join(' • ')}</p>}
        {data.overview && !item.newEpisodeCount && <p className="mt-2 text-xs leading-relaxed text-white/70 line-clamp-2">{data.overview}</p>}
      </div>
    </div>,
    document.body,
  );
}

async function referenceFor(media: CardMedia): Promise<{ media: 'movie' | 'tv'; tmdbId: string } | null> {
  if (media.tmdbId && media.tmdbMedia) return { media: media.tmdbMedia, tmdbId: media.tmdbId };
  if (media.showRatingKey) {
    const show = await resolveCardMedia(`plex:${media.showRatingKey}`, 'show').catch(() => null);
    if (show?.tmdbId) return { media: 'tv', tmdbId: show.tmdbId };
  }
  return null;
}
