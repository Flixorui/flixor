import { useState, useEffect, useRef, useCallback } from 'react';
import SmartImage from './SmartImage';

type HeroItem = {
  id: string;
  title: string;
  overview?: string;
  backdropUrl?: string;
  logoUrl?: string;
  year?: string;
  runtime?: number;
  rating?: string;
  genres?: string[];
};

type HeroCarouselProps = {
  items: HeroItem[];
  autoRotate?: boolean;
  rotateInterval?: number; // ms, default 8000 (matches MacOS)
  onPlay?: (id: string) => void;
  onMoreInfo?: (id: string) => void;
  onActiveChange?: (item: HeroItem, index: number) => void;
};

export default function HeroCarousel({
  items,
  autoRotate = false,
  rotateInterval = 8000,
  onPlay,
  onMoreInfo,
  onActiveChange,
}: HeroCarouselProps) {
  const [activeIndex, setActiveIndex] = useState(0);
  const [isPaused, setIsPaused] = useState(false);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  const goToNext = useCallback(() => {
    setActiveIndex((prev) => (prev + 1) % items.length);
  }, [items.length]);

  const goToPrev = useCallback(() => {
    setActiveIndex((prev) => (prev - 1 + items.length) % items.length);
  }, [items.length]);

  const goToIndex = useCallback((index: number) => {
    setActiveIndex(index);
  }, []);

  // Auto-rotation
  useEffect(() => {
    if (!autoRotate || isPaused || items.length <= 1) return;

    intervalRef.current = setInterval(goToNext, rotateInterval);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
      }
    };
  }, [autoRotate, isPaused, rotateInterval, goToNext, items.length]);

  // Notify parent when active item changes
  useEffect(() => {
    if (items[activeIndex] && onActiveChange) {
      onActiveChange(items[activeIndex], activeIndex);
    }
  }, [activeIndex, items, onActiveChange]);

  // Reset timer when manually changing slides
  const handleManualChange = (index: number) => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
    }
    goToIndex(index);
    if (autoRotate && !isPaused && items.length > 1) {
      intervalRef.current = setInterval(goToNext, rotateInterval);
    }
  };

  const currentItem = items[activeIndex];

  if (!currentItem) return null;

  // Metadata badges
  const metaBadges: string[] = [];
  if (currentItem.year) metaBadges.push(currentItem.year);
  if (currentItem.runtime) metaBadges.push(`${currentItem.runtime} min`);
  if (currentItem.rating) metaBadges.push(currentItem.rating);

  return (
    <div
      className="bleed relative"
      style={{
        paddingTop: '16px',
        paddingBottom: '16px',
        paddingLeft: 'var(--page-gutter)',
        paddingRight: 'var(--page-gutter)',
      }}
      onMouseEnter={() => setIsPaused(true)}
      onMouseLeave={() => setIsPaused(false)}
    >
      {/* Taller aspect ratio to match macOS billboard, capped at max height and centered */}
      <div className="group rounded-2xl overflow-hidden shadow-billboard ring-1 ring-white/10 bg-neutral-900/40 relative aspect-[2/1] max-h-[1000px] max-w-[2000px] mx-auto">
        {/* Background Images */}
        <div className="absolute inset-0">
          {items.map((item, index) => (
            <div
              key={item.id}
              className={`absolute inset-0 transition-opacity duration-700 ${
                index === activeIndex ? 'opacity-100' : 'opacity-0'
              }`}
            >
              {item.backdropUrl && (
                <SmartImage
                  url={item.backdropUrl}
                  alt=""
                  width={1280}
                  className="w-full h-full"
                  imgClassName="object-cover"
                  priority={index === activeIndex}
                />
              )}
            </div>
          ))}

          {/* Gradient Overlays */}
          <div className="absolute inset-0 bg-gradient-to-t from-black via-black/50 to-transparent" />
          <div className="absolute inset-0 bg-gradient-to-r from-black/80 via-black/30 to-transparent" />
        </div>

        {/* Content Layer */}
        <div className="absolute inset-0 flex flex-col justify-end p-5 md:p-8">
          <div className="max-w-4xl">
            {/* Title/Logo */}
            <div className="mb-4">
              {currentItem.logoUrl ? (
                <img
                  src={currentItem.logoUrl}
                  alt={currentItem.title}
                  className="h-12 md:h-20 lg:h-24 max-w-[80vw] md:max-w-[50vw] object-contain drop-shadow-2xl"
                  style={{ filter: 'drop-shadow(0 10px 30px rgba(0,0,0,0.9))' }}
                />
              ) : (
                <h1
                  className="text-3xl md:text-5xl lg:text-6xl font-black tracking-tight text-white"
                  style={{ textShadow: '0 4px 20px rgba(0,0,0,0.9)' }}
                >
                  {currentItem.title}
                </h1>
              )}
            </div>

            {/* Metadata */}
            {(metaBadges.length > 0 || (currentItem.genres?.length ?? 0) > 0) && (
              <div className="flex flex-wrap items-center gap-2 mb-4 text-sm md:text-base">
                {metaBadges.map((badge, i) => (
                  <span key={i} className="text-white/90 font-medium">
                    {badge}
                  </span>
                ))}
                {metaBadges.length > 0 && (currentItem.genres?.length ?? 0) > 0 && (
                  <span className="text-white/50">•</span>
                )}
                {currentItem.genres?.slice(0, 3).map((genre, i) => (
                  <span key={i} className="text-white/70">
                    {genre}
                  </span>
                ))}
              </div>
            )}

            {/* Overview */}
            {currentItem.overview && (
              <p className="mb-6 text-sm md:text-base text-white/80 leading-relaxed line-clamp-2 md:line-clamp-3 max-w-3xl">
                {currentItem.overview}
              </p>
            )}

            {/* Action Buttons */}
            <div className="flex flex-wrap items-center gap-3">
              {onPlay && (
                <button
                  onClick={() => onPlay(currentItem.id)}
                  className="inline-flex items-center px-5 py-2.5 text-sm md:text-base font-semibold bg-white text-black rounded-md hover:bg-white/90 transition-all shadow-lg"
                >
                  <svg className="w-4 h-4 md:w-5 md:h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M8 5v14l11-7z" />
                  </svg>
                  Play
                </button>
              )}

              {onMoreInfo && (
                <button
                  onClick={() => onMoreInfo(currentItem.id)}
                  className="inline-flex items-center px-5 py-2.5 text-sm md:text-base font-medium text-white bg-white/20 backdrop-blur-sm rounded-md hover:bg-white/30 transition-all"
                >
                  <svg className="w-4 h-4 md:w-5 md:h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z" />
                  </svg>
                  More Info
                </button>
              )}
            </div>
          </div>
        </div>

        {/* Navigation Arrows */}
        {items.length > 1 && (
          <>
            <button
              onClick={() => handleManualChange((activeIndex - 1 + items.length) % items.length)}
              className="absolute left-4 top-1/2 -translate-y-1/2 w-12 h-12 flex items-center justify-center bg-black/60 backdrop-blur-sm rounded-full hover:bg-black/80 hover:scale-105 transition-all duration-200 opacity-0 group-hover:opacity-100"
              aria-label="Previous"
            >
              <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
              </svg>
            </button>
            <button
              onClick={() => handleManualChange((activeIndex + 1) % items.length)}
              className="absolute right-4 top-1/2 -translate-y-1/2 w-12 h-12 flex items-center justify-center bg-black/60 backdrop-blur-sm rounded-full hover:bg-black/80 hover:scale-105 transition-all duration-200 opacity-0 group-hover:opacity-100"
              aria-label="Next"
            >
              <svg className="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </button>
          </>
        )}

        {/* Pagination Dots */}
        {items.length > 1 && (
          <div className="absolute bottom-4 left-1/2 -translate-x-1/2 flex items-center gap-2">
            {items.map((_, index) => (
              <button
                key={index}
                onClick={() => handleManualChange(index)}
                className={`transition-all duration-300 rounded-full ${
                  index === activeIndex
                    ? 'w-8 h-2 bg-white'
                    : 'w-2 h-2 bg-white/50 hover:bg-white/70'
                }`}
                aria-label={`Go to slide ${index + 1}`}
              />
            ))}
          </div>
        )}

        {/* Progress Bar (optional visual indicator of auto-rotation) */}
        {autoRotate && items.length > 1 && !isPaused && (
          <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-white/10">
            <div
              className="h-full bg-white/50 animate-progress"
              style={{
                animation: `progress ${rotateInterval}ms linear`,
              }}
              key={activeIndex}
            />
          </div>
        )}
      </div>

      <style>{`
        @keyframes progress {
          from { width: 0%; }
          to { width: 100%; }
        }
      `}</style>
    </div>
  );
}
