import { useCallback, useEffect, useRef, useState, type PointerEvent } from 'react';
import SmartImage from './SmartImage';
import type { CardItem } from './cards/cardTypes';
import { heroMetadata, type HeroMetadata } from './home/heroData';
import { preheatImages } from './home/preheat';

const ROTATE_INTERVAL_MS = 8000;
const PAGE_MS = 500;
const BACKGROUND_PARALLAX = 0.055;
const CONTENT_PARALLAX = 0.18;
const SCROLL_PARALLAX = 0.38;
const SCROLL_DOWN_SCALE = 0.0001;
const SCROLL_UP_SCALE = 0.002;
const MAX_SCROLL_SCALE = 1.3;
const SWIPE_THRESHOLD = 0.16;
const BACKDROP_WIDTH = 1920;

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

function useHeroMetadata(item?: CardItem) {
  const [metadata, setMetadata] = useState<HeroMetadata | null>(null);
  useEffect(() => {
    setMetadata(null);
    if (!item) return;
    let alive = true;
    heroMetadata(item).then((value) => {
      if (alive) setMetadata(value);
    });
    return () => {
      alive = false;
    };
  }, [item]);
  return metadata;
}

/** Full-bleed Home hero: artwork to the window edges, logo, genres, summary and View Details. */
export default function HeroCarousel({
  items,
  autoRotate = false,
  onInfo,
  onActiveChange,
}: {
  items: CardItem[];
  autoRotate?: boolean;
  onInfo: (item: CardItem) => void;
  onActiveChange?: (backdropUrl: string | undefined) => void;
}) {
  const [index, setIndex] = useState(0);
  const [outgoing, setOutgoing] = useState<number | null>(null);
  const [forward, setForward] = useState(true);
  const [paused, setPaused] = useState(false);
  const [width, setWidth] = useState(() => window.innerWidth);
  const [rotationEpoch, setRotationEpoch] = useState(0);
  const rootRef = useRef<HTMLDivElement>(null);
  const artworkRef = useRef<HTMLDivElement>(null);
  const dragStart = useRef<{ x: number; y: number } | null>(null);
  const reduceMotion = prefersReducedMotion();
  const safeIndex = index < items.length ? index : 0;
  const current = items[safeIndex];
  const metadata = useHeroMetadata(current);

  const changePage = useCallback(
    (next: number, isForward: boolean, userInitiated: boolean) => {
      if (next === safeIndex) return;
      setForward(isForward);
      setOutgoing(reduceMotion ? null : safeIndex);
      setIndex(next);
      if (userInitiated) setRotationEpoch((epoch) => epoch + 1);
    },
    [safeIndex, reduceMotion],
  );

  useEffect(() => {
    if (outgoing === null) return;
    const timer = window.setTimeout(() => setOutgoing(null), PAGE_MS);
    return () => window.clearTimeout(timer);
  }, [outgoing, safeIndex]);

  useEffect(() => {
    if (!autoRotate || paused || items.length < 2) return;
    const timer = window.setInterval(() => {
      if (document.hidden) return;
      changePage((safeIndex + 1) % items.length, true, false);
    }, ROTATE_INTERVAL_MS);
    return () => window.clearInterval(timer);
  }, [autoRotate, paused, items.length, safeIndex, changePage, rotationEpoch]);

  useEffect(() => {
    if (metadata?.backdropUrl) onActiveChange?.(metadata.backdropUrl);
  }, [metadata, onActiveChange]);

  // Loads the next page ahead of time so it doesn't flash in empty.
  useEffect(() => {
    if (items.length < 2) return;
    const next = items[(safeIndex + 1) % items.length];
    let alive = true;
    heroMetadata(next).then((value) => {
      if (alive) preheatImages([value.backdropUrl, value.logoUrl], BACKDROP_WIDTH);
    });
    return () => {
      alive = false;
    };
  }, [items, safeIndex]);

  useEffect(() => {
    const onResize = () => setWidth(window.innerWidth);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  // Scroll parallax is written straight to the element to avoid re-rendering the page.
  useEffect(() => {
    if (reduceMotion) return;
    let frame = 0;
    const apply = () => {
      frame = 0;
      const offset = Math.min(window.scrollY, 800);
      const increase = offset < 0 ? -offset * SCROLL_UP_SCALE : offset * SCROLL_DOWN_SCALE;
      const scale = Math.min(1 + increase, MAX_SCROLL_SCALE);
      if (artworkRef.current) artworkRef.current.style.transform = `translate3d(0, ${Math.round(offset * SCROLL_PARALLAX)}px, 0) scale(${scale})`;
    };
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(apply);
    };
    apply();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => {
      window.removeEventListener('scroll', onScroll);
      if (frame) cancelAnimationFrame(frame);
    };
  }, [reduceMotion]);

  if (!current) return null;

  const step = (delta: number) => changePage((safeIndex + delta + items.length) % items.length, delta > 0, true);

  const onPointerDown = (event: PointerEvent<HTMLDivElement>) => {
    dragStart.current = { x: event.clientX, y: event.clientY };
  };
  const onPointerUp = (event: PointerEvent<HTMLDivElement>) => {
    const start = dragStart.current;
    dragStart.current = null;
    if (!start || items.length < 2) return;
    const dx = event.clientX - start.x;
    const dy = event.clientY - start.y;
    if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > (rootRef.current?.clientWidth ?? width) * SWIPE_THRESHOLD) {
      step(dx < 0 ? 1 : -1);
    }
  };

  const direction = forward ? 1 : -1;
  const artworkShift = Math.round(width * BACKGROUND_PARALLAX * direction);
  const contentShift = Math.round(width * CONTENT_PARALLAX * direction);

  return (
    <div
      ref={rootRef}
      className="bleed relative overflow-hidden"
      style={{ height: 'clamp(460px, 56vw, 640px)', touchAction: 'pan-y' }}
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      onPointerDown={onPointerDown}
      onPointerUp={onPointerUp}
      onKeyDown={(event) => {
        if (event.key === 'ArrowLeft') step(-1);
        if (event.key === 'ArrowRight') step(1);
      }}
    >
      <style>{`
        @keyframes hero-page-in { from { opacity: 0; transform: translateX(var(--hero-shift)); } to { opacity: 1; transform: translateX(0); } }
        @keyframes hero-page-out { from { opacity: 1; transform: translateX(0); } to { opacity: 0; transform: translateX(calc(var(--hero-shift) * -1)); } }
        .hero-page-in { animation: hero-page-in ${PAGE_MS}ms ease-in-out both; }
        .hero-page-out { animation: hero-page-out ${PAGE_MS}ms ease-in-out both; }
      `}</style>

      <div
        ref={artworkRef}
        className="absolute inset-0 will-change-transform"
        aria-hidden
        style={{
          maskImage: 'linear-gradient(to bottom, black calc(100% - 300px), transparent 100%)',
          WebkitMaskImage: 'linear-gradient(to bottom, black calc(100% - 300px), transparent 100%)',
        }}
      >
        {outgoing !== null && items[outgoing] && (
          <HeroArtwork key={`out-${items[outgoing].id}`} item={items[outgoing]} className="hero-page-out" shift={artworkShift} />
        )}
        <HeroArtwork
          key={current.id}
          item={current}
          className={outgoing !== null ? 'hero-page-in' : ''}
          shift={artworkShift}
          priority
        />
      </div>

      <div className="absolute inset-x-0 top-0 h-40 pointer-events-none bg-gradient-to-b from-black/80 to-transparent" />
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          background:
            'linear-gradient(to right, rgba(10,10,10,.96) 0%, rgba(10,10,10,.90) 8%, rgba(10,10,10,.76) 16%, rgba(10,10,10,.54) 26%, rgba(10,10,10,.30) 36%, rgba(10,10,10,.12) 46%, transparent 54%)',
        }}
      />

      <div
        key={`content-${current.id}`}
        className={`absolute bottom-10 cursor-pointer ${outgoing !== null ? 'hero-page-in' : ''}`}
        style={{
          left: 'var(--page-gutter)',
          right: 32,
          maxWidth: 'min(58%, 760px)',
          minWidth: 'min(300px, 80vw)',
          ['--hero-shift' as string]: `${contentShift}px`,
        }}
        onClick={() => onInfo(current)}
      >
        <HeroContent metadata={metadata} item={current} onInfo={() => onInfo(current)} />
      </div>

      <div className="absolute bottom-10 flex items-center gap-3" style={{ right: 'var(--page-gutter)' }}>
        <FullScreenButton />
        {items.length > 1 && (
          <div className="flex items-center" role="group" aria-label="Featured items">
            {items.map((item, i) => (
              <button
                key={item.id}
                onClick={() => changePage(i, i > safeIndex, true)}
                aria-label={`Show item ${i + 1} of ${items.length}`}
                aria-current={i === safeIndex}
                title={`Show item ${i + 1} of ${items.length}`}
                className="group flex items-center justify-center h-6 px-1"
              >
                <span
                  className={`block h-2 rounded-full transition-all duration-300 ${
                    i === safeIndex ? 'w-8 bg-white/90' : 'w-2 bg-white/35 group-hover:bg-white/70'
                  }`}
                />
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function HeroArtwork({ item, className, shift, priority }: { item: CardItem; className: string; shift: number; priority?: boolean }) {
  const metadata = useHeroMetadata(item);
  return (
    <div className={`absolute inset-0 ${className}`} style={{ ['--hero-shift' as string]: `${shift}px` }}>
      {metadata?.backdropUrl && (
        <SmartImage
          url={metadata.backdropUrl}
          alt=""
          width={BACKDROP_WIDTH}
          className="w-full h-full"
          imgClassName="object-cover object-[center_20%]"
          priority={priority}
        />
      )}
    </div>
  );
}

function HeroContent({ metadata, item, onInfo }: { metadata: HeroMetadata | null; item: CardItem; onInfo: () => void }) {
  const title = metadata?.title || item.showTitle || item.title;
  const genres = metadata?.genres ?? [];
  const metaLine = genres.length > 0 ? genres.join(' • ') : item.mediaType === 'movie' ? 'Movie' : 'Series';
  return (
    <>
      {metadata?.logoUrl ? (
        <img src={metadata.logoUrl} alt={title} className="h-16 md:h-[120px] w-[74%] object-contain object-left-bottom" draggable={false} />
      ) : metadata ? (
        <h1 className="text-4xl md:text-6xl font-extrabold tracking-tight text-white line-clamp-3">{title}</h1>
      ) : (
        <div className="h-16 md:h-[120px]" />
      )}
      <p className="mt-3 text-sm md:text-base font-medium text-white/70 line-clamp-1">{metaLine}</p>
      {metadata?.overview && <p className="mt-4 text-sm md:text-lg leading-relaxed text-white line-clamp-3 md:line-clamp-4">{metadata.overview}</p>}
      <button
        onClick={(event) => {
          event.stopPropagation();
          onInfo();
        }}
        className="mt-6 h-12 px-6 rounded-[40px] bg-white text-black text-sm md:text-base font-bold hover:bg-white/90 transition-colors"
      >
        View Details
      </button>
    </>
  );
}

function FullScreenButton() {
  const [isFullScreen, setIsFullScreen] = useState(!!document.fullscreenElement);
  useEffect(() => {
    const onChange = () => setIsFullScreen(!!document.fullscreenElement);
    document.addEventListener('fullscreenchange', onChange);
    return () => document.removeEventListener('fullscreenchange', onChange);
  }, []);
  if (!document.fullscreenEnabled) return null;
  const label = isFullScreen ? 'Exit Full Screen' : 'Full Screen';
  return (
    <button
      onClick={() => {
        if (document.fullscreenElement) document.exitFullscreen();
        else document.documentElement.requestFullscreen();
      }}
      title={label}
      aria-label={label}
      className="w-10 h-10 flex items-center justify-center rounded-full bg-neutral-800/80 text-white hover:bg-neutral-700/80 transition-colors"
    >
      <svg className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" viewBox="0 0 24 24">
        {isFullScreen ? <path d="M9 3v6H3M15 3v6h6M9 21v-6H3M15 21v-6h6" /> : <path d="M3 9V3h6M21 9V3h-6M3 15v6h6M21 15v6h-6" />}
      </svg>
    </button>
  );
}
