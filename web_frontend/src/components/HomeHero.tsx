import { useEffect, useRef, useState } from 'react';
import SmartImage from './SmartImage';

type HomeHeroProps = {
  title: string;
  overview?: string;
  backdropUrl?: string;
  posterUrl?: string;
  rating?: string;
  year?: string;
  runtime?: number;
  genres?: string[];
  onPlay?: () => void;
  onMoreInfo?: () => void;
  videoUrl?: string; // Plex Extras direct URL
  ytKey?: string; // YouTube trailer key fallback
  logoUrl?: string;
  extraActions?: React.ReactNode;
};

export default function HomeHero({
  title,
  overview,
  backdropUrl,
  posterUrl,
  rating,
  year,
  runtime,
  genres = [],
  onPlay,
  onMoreInfo,
  videoUrl,
  ytKey,
  logoUrl,
  extraActions
}: HomeHeroProps) {
  const [muted, setMuted] = useState(true);
  const [playing, setPlaying] = useState(false);
  const [imageLoaded, setImageLoaded] = useState(false);
  const scrollHandler = useRef<(e: any) => void>();
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    const t = setTimeout(() => setPlaying(true), 5000);
    scrollHandler.current = () => {
      const y = window.scrollY || document.documentElement.scrollTop;
      setPlaying(y < 120);
    };
    window.addEventListener('scroll', scrollHandler.current);

    return () => {
      clearTimeout(t);
      if (scrollHandler.current) window.removeEventListener('scroll', scrollHandler.current);
    };
  }, []);

  // Handle video ended
  const handleVideoEnded = () => {
    setPlaying(false);
  };

  // Metadata badges
  const metaBadges = [];
  if (year) metaBadges.push(year);
  if (runtime) metaBadges.push(`${runtime} min`);
  if (rating) metaBadges.push(rating);

  return (
    <div
      className="bleed"
      style={{
        paddingTop: '16px',
        paddingBottom: '16px',
        paddingLeft: 'var(--page-gutter)',
        paddingRight: 'var(--page-gutter)'
      }}
    >
      {/* Taller aspect ratio to match macOS billboard */}
      <div className="rounded-2xl overflow-hidden shadow-billboard ring-1 ring-white/10 bg-neutral-900/40 relative aspect-[2/1]">
        {/* Background Image/Video Layer */}
        <div className="absolute inset-0">
          {/* Backdrop image */}
          {backdropUrl && (
            <div className={`absolute inset-0 transition-opacity duration-1000 ${!playing ? 'opacity-100' : 'opacity-0'}`}>
              <SmartImage url={backdropUrl} alt="" width={1280} className="w-full h-full" imgClassName="object-cover" priority onLoad={() => setImageLoaded(true)} />
            </div>
          )}

          {/* Trailer overlay */}
          {playing && (videoUrl || ytKey) && (
            <div className="absolute inset-0 opacity-60">
              {videoUrl ? (
                <video
                  ref={videoRef}
                  id="home-plex-trailer"
                  className="w-full h-full object-cover"
                  src={videoUrl}
                  autoPlay
                  muted={muted}
                  loop={false}
                  playsInline
                  onEnded={handleVideoEnded}
                />
              ) : ytKey ? (
                <iframe
                  id="home-yt-trailer"
                  className="w-full h-full"
                  src={`https://www.youtube.com/embed/${ytKey}?autoplay=1&mute=${
                    muted ? 1 : 0
                  }&controls=0&loop=0&playsinline=1&rel=0&showinfo=0&modestbranding=1&enablejsapi=1&origin=${window.location.origin}`}
                  allow="autoplay; encrypted-media"
                  style={{ pointerEvents: 'none' }}
                />
              ) : null}
            </div>
          )}

          {/* Gradient Overlays */}
          <div className="absolute inset-0 bg-gradient-to-t from-black via-black/50 to-transparent" />
          <div className="absolute inset-0 bg-gradient-to-r from-black/80 via-black/30 to-transparent" />
        </div>

        {/* Content Layer */}
        <div className="absolute inset-0 flex flex-col justify-end p-5 md:p-8">
          <div className="max-w-4xl">
            {/* Title/Logo */}
            <div className="mb-4">
              {logoUrl ? (
                <img
                  src={logoUrl}
                  alt={title}
                  className="h-12 md:h-20 lg:h-24 max-w-[80vw] md:max-w-[50vw] object-contain drop-shadow-2xl"
                  style={{ filter: 'drop-shadow(0 10px 30px rgba(0,0,0,0.9))' }}
                />
              ) : (
                <h1
                  className="text-3xl md:text-5xl lg:text-6xl font-black tracking-tight text-white"
                  style={{ textShadow: '0 4px 20px rgba(0,0,0,0.9)' }}
                >
                  {title}
                </h1>
              )}
            </div>

            {/* Metadata */}
            {(metaBadges.length > 0 || genres.length > 0) && (
              <div className="flex flex-wrap items-center gap-2 mb-4 text-sm md:text-base">
                {metaBadges.map((badge, i) => (
                  <span key={i} className="text-white/90 font-medium">
                    {badge}
                  </span>
                ))}
                {metaBadges.length > 0 && genres.length > 0 && (
                  <span className="text-white/50">•</span>
                )}
                {genres.slice(0, 3).map((genre, i) => (
                  <span key={i} className="text-white/70">
                    {genre}
                  </span>
                ))}
              </div>
            )}

            {/* Overview */}
            {overview && (
              <p className="mb-6 text-sm md:text-base text-white/80 leading-relaxed line-clamp-2 md:line-clamp-3 max-w-3xl">
                {overview}
              </p>
            )}

            {/* Action Buttons */}
            <div className="flex flex-wrap items-center gap-3">
              {onPlay && (
                <button
                  onClick={onPlay}
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
                  onClick={onMoreInfo}
                  className="inline-flex items-center px-5 py-2.5 text-sm md:text-base font-medium text-white bg-white/20 backdrop-blur-sm rounded-md hover:bg-white/30 transition-all"
                >
                  <svg className="w-4 h-4 md:w-5 md:h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z" />
                  </svg>
                  More Info
                </button>
              )}

              {extraActions}
            </div>
          </div>
        </div>

        {/* Mute Button */}
        {(playing || (!playing && (videoUrl || ytKey))) && (
          <button
            onClick={() => setMuted(!muted)}
            className="absolute top-4 right-4 w-10 h-10 flex items-center justify-center bg-black/60 rounded-full hover:bg-black/80 transition-all ring-1 ring-white/20"
            aria-label={muted ? 'Unmute' : 'Mute'}
          >
            {muted ? (
              <svg className="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 24 24">
                <path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/>
              </svg>
            ) : (
              <svg className="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 24 24">
                <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/>
              </svg>
            )}
          </button>
        )}
      </div>
    </div>
  );
}
