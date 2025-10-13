import { useState, useEffect, useRef } from 'react';
import RatingsBar from '@/components/RatingsBar';
import { useNavigate } from 'react-router-dom';

interface DetailsHeroProps {
  title: string;
  overview?: string;
  backdrop?: string;
  poster?: string;
  logo?: string;
  year?: string;
  rating?: string;
  runtime?: number;
  genres?: string[];
  badges?: string[];
  ratings?: { imdb?: { rating?: number; votes?: number } | null; rt?: { critic?: number; audience?: number } | null } | null;
  cast?: Array<{ id?: string; name: string; img?: string }>;
  moodTags?: string[];
  kind?: 'movie' | 'tv';

  // Media info
  hasMediaInfo?: boolean;
  onToggleMediaInfo?: () => void;
  showMediaInfo?: boolean;
  versionDetails?: Array<{
    id: string;
    label: string;
    audios: any[];
    subs: any[];
    tech: any;
  }>;
  infoVersion?: string;
  onVersionChange?: (id: string) => void;

  // Playback
  playable?: boolean;
  onPlay?: () => void;
  continueLabel?: string;
  onContinue?: () => void;

  // Actions
  onAddToList?: () => void;
  watchlistProps?: { itemId: string; itemType: 'movie'|'show'; tmdbId?: string|number; imdbId?: string };
  onMarkWatched?: () => void;
  onPersonClick?: (person: { id?: string; name: string }) => void;

  // Trailer
  trailerUrl?: string;
  trailerKey?: string;
  trailerMuted?: boolean;
  showTrailer?: boolean;
  onToggleMute?: () => void;
}

export default function DetailsHero({
  title,
  overview,
  backdrop,
  poster,
  logo,
  year,
  rating,
  runtime,
  genres = [],
  badges = [],
  ratings,
  cast = [],
  moodTags = [],
  kind,
  hasMediaInfo,
  onToggleMediaInfo,
  showMediaInfo,
  versionDetails = [],
  infoVersion,
  onVersionChange,
  playable = false,
  onPlay,
  onAddToList,
  onMarkWatched,
  watchlistProps,
  onPersonClick,
  trailerUrl,
  trailerKey,
  trailerMuted = true,
  showTrailer = false,
  onToggleMute,
  continueLabel,
  onContinue,
}: DetailsHeroProps) {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [localShowTrailer, setLocalShowTrailer] = useState(showTrailer);
  const videoRef = useRef<HTMLVideoElement>(null);

  // Reset trailer state when title changes (detected by backdrop/trailer change)
  useEffect(() => {
    setLocalShowTrailer(showTrailer);
  }, [showTrailer, trailerUrl, trailerKey, backdrop]);

  // Handle video ended event
  const handleVideoEnded = () => {
    setLocalShowTrailer(false);
  };

  // Handle YouTube iframe ended event
  useEffect(() => {
    if (!localShowTrailer || !trailerKey) return;

    const handleMessage = (event: MessageEvent) => {
      if (event.origin !== 'https://www.youtube.com') return;

      try {
        let data;
        if (typeof event.data === 'string') {
          data = JSON.parse(event.data);
        } else {
          data = event.data;
        }

        // YouTube Player State: 0 = ended, check multiple event types
        if (data.event === 'onStateChange' && data.info === 0) {
          setLocalShowTrailer(false);
        }
        // Alternative event structure
        if (data.event === 'infoDelivery' && data.info?.playerState === 0) {
          setLocalShowTrailer(false);
        }
      } catch {}
    };

    window.addEventListener('message', handleMessage);
    return () => window.removeEventListener('message', handleMessage);
  }, [localShowTrailer, trailerKey]);

  // Metadata badges
  const metaBadges = [];
  if (year) metaBadges.push(year);
  if (runtime) metaBadges.push(`${runtime} min`);
  if (rating) metaBadges.push(rating);

  return (
    <div className="relative w-full min-h-[85vh] md:min-h-[90vh] overflow-hidden">
      {/* Background Image/Video Layer */}
      <div className="absolute inset-0">
        {/* Backdrop image */}
        {backdrop && (
          <div className="absolute inset-0">
            <img
              src={backdrop}
              alt=""
              className={`absolute inset-0 w-full h-full object-cover transition-opacity duration-1000 ${
                imageLoaded && !localShowTrailer ? 'opacity-100' : 'opacity-0'
              }`}
              style={{
                maskImage: 'linear-gradient(to bottom, rgba(0,0,0,1) 0%, rgba(0,0,0,1) 60%, rgba(0,0,0,0.8) 80%, rgba(0,0,0,0) 100%)',
                WebkitMaskImage: 'linear-gradient(to bottom, rgba(0,0,0,1) 0%, rgba(0,0,0,1) 60%, rgba(0,0,0,0.8) 80%, rgba(0,0,0,0) 100%)'
              }}
              onLoad={() => setImageLoaded(true)}
            />
          </div>
        )}

        {/* Trailer overlay */}
        {localShowTrailer && (trailerUrl || trailerKey) && (
          <div className="absolute inset-0">
            {trailerUrl ? (
              <video
                ref={videoRef}
                id="hero-trailer-video"
                className="w-full h-full object-cover"
                style={{
                  maskImage: 'linear-gradient(to bottom, rgba(0,0,0,1) 0%, rgba(0,0,0,1) 60%, rgba(0,0,0,0.8) 80%, rgba(0,0,0,0) 100%)',
                  WebkitMaskImage: 'linear-gradient(to bottom, rgba(0,0,0,1) 0%, rgba(0,0,0,1) 60%, rgba(0,0,0,0.8) 80%, rgba(0,0,0,0) 100%)'
                }}
                src={trailerUrl}
                autoPlay
                muted={trailerMuted}
                loop={false}
                playsInline
                onEnded={handleVideoEnded}
              />
            ) : trailerKey ? (
              <div
                className="absolute inset-0 w-full h-full"
                style={{
                  maskImage: 'linear-gradient(to bottom, rgba(0,0,0,1) 0%, rgba(0,0,0,1) 60%, rgba(0,0,0,0.8) 80%, rgba(0,0,0,0) 100%)',
                  WebkitMaskImage: 'linear-gradient(to bottom, rgba(0,0,0,1) 0%, rgba(0,0,0,1) 60%, rgba(0,0,0,0.8) 80%, rgba(0,0,0,0) 100%)'
                }}
              >
                <iframe
                  id="hero-trailer-iframe"
                  className="absolute inset-0 w-full h-full scale-125 origin-center"
                src={`https://www.youtube.com/embed/${trailerKey}?autoplay=1&mute=${
                  trailerMuted ? 1 : 0
                }&controls=0&loop=0&playsinline=1&rel=0&showinfo=0&modestbranding=1&enablejsapi=1&origin=${window.location.origin}&widget_referrer=${window.location.origin}`}
                allow="autoplay; encrypted-media"
                style={{ pointerEvents: 'none' }}
                onLoad={() => {
                  // Send API ready message to enable events
                  const iframe = document.getElementById('hero-trailer-iframe') as HTMLIFrameElement;
                  if (iframe && iframe.contentWindow) {
                    setTimeout(() => {
                      iframe.contentWindow?.postMessage(
                        JSON.stringify({ event: 'listening', id: 1, channel: 'widget' }),
                        'https://www.youtube.com'
                      );
                    }, 1000);
                  }
                }}
                />
              </div>
            ) : null}
          </div>
        )}

        {/* Gradient Overlays - seamless blend */}
        <div className="absolute inset-0">
          {/* Bottom fade - matches page background */}
          <div className="absolute inset-0 bg-gradient-to-t from-[#0b0b0b] via-[#0b0b0b]/80 via-50% to-transparent" />
          <div className="absolute inset-0 bg-gradient-to-t from-[#141414] via-[#141414]/40 via-60% to-transparent" />
          {/* Side fade for content readability */}
          <div className="absolute inset-0 bg-gradient-to-r from-black/80 via-black/40 via-50% to-transparent" />
          {/* Extra bottom blend for seamless transition */}
          <div className="absolute bottom-0 left-0 right-0 h-32 bg-gradient-to-t from-[#0b0b0b] to-transparent" />
        </div>
      </div>

      {/* Content Layer */}
      <div className="relative z-10 flex flex-col justify-end min-h-[85vh] md:min-h-[90vh]">
        <div className="px-4 md:px-8 lg:px-12 xl:px-16 pb-12 md:pb-16">
          {/* Type Badge */}
          {kind && (
            <div className="mb-4">
              <span className="inline-flex items-center px-3 py-1 text-xs font-medium tracking-wider text-white/80 bg-white/10 backdrop-blur-sm rounded">
                {kind === 'movie' ? 'MOVIE' : 'TV SERIES'}
              </span>
            </div>
          )}

          {/* Title/Logo */}
          <div className="mb-6">
            {logo ? (
              <img
                src={logo}
                alt={title}
                className="h-24 md:h-32 lg:h-40 max-w-[90vw] md:max-w-[60vw] object-contain drop-shadow-2xl"
                style={{ filter: 'drop-shadow(0 10px 40px rgba(0,0,0,0.8))' }}
              />
            ) : (
              <h1 className="text-5xl md:text-7xl lg:text-8xl font-black tracking-tight text-white max-w-4xl"
                  style={{ textShadow: '0 10px 40px rgba(0,0,0,0.8)' }}>
                {title}
              </h1>
            )}
          </div>

          {/* Metadata Row (inline ratings) */}
          <div className="flex flex-wrap items-center gap-3 mb-6 text-sm md:text-base">
            {metaBadges.map((badge, i) => (
              <span key={i} className="text-white/90 font-medium">
                {badge}
              </span>
            ))}
            {metaBadges.length > 0 && badges.length > 0 && (
              <span className="text-white/40">•</span>
            )}
            {badges.map((badge, i) => (
              <span
                key={i}
                className="inline-flex items-center px-2 py-0.5 text-xs font-medium text-white bg-white/20 backdrop-blur-sm rounded"
              >
                {badge}
              </span>
            ))}
            {ratings && (ratings.imdb || ratings.rt) && (
              <div className="inline-flex items-center gap-3">
                <RatingsBar imdb={ratings.imdb || undefined} rt={ratings.rt || undefined} />
              </div>
            )}
          </div>

          {/* Overview */}
          {overview && (
            <p className="max-w-3xl mb-8 text-base md:text-lg text-white/80 leading-relaxed">
              {overview.length > 300 ? overview.substring(0, 300) + '...' : overview}
            </p>
          )}

          {/* Action Buttons */}
          <div className="flex flex-wrap items-center gap-3 mb-8">
            {onContinue ? (
              <button
                onClick={onContinue}
                className="inline-flex items-center px-6 py-3 text-base font-medium rounded-lg transition-all bg-white/10 text-white hover:bg-white/20"
              >
                <svg className="w-5 h-5 mr-2" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M5 2.69127C5 1.93067 5.81547 1.44851 6.48192 1.81506L23.4069 11.1238C24.0977 11.5037 24.0977 12.4963 23.4069 12.8762L6.48192 22.1849C5.81546 22.5515 5 22.0693 5 21.3087V2.69127Z" />
                </svg>
                {continueLabel || 'Continue Watching'}
              </button>
            ) : (
              <button
                onClick={onPlay}
                disabled={!playable}
                className={`inline-flex items-center px-6 py-3 text-base font-medium rounded-lg transition-all ${
                  playable
                    ? 'bg-white text-black hover:bg-white/90'
                    : 'bg-white/20 text-white/60 cursor-not-allowed'
                }`}
              >
                <svg className="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M8 5v14l11-7z" />
                </svg>
                Play
              </button>
            )}

            {watchlistProps ? (
              <WatchlistButton
                itemId={watchlistProps.itemId}
                itemType={watchlistProps.itemType}
                tmdbId={watchlistProps.tmdbId}
                imdbId={watchlistProps.imdbId}
                variant="button"
              />
            ) : (
              <button
                onClick={onAddToList}
                className="inline-flex items-center px-5 py-3 text-base font-medium text-white bg-white/20 backdrop-blur-sm rounded-lg hover:bg-white/30 transition-all"
              >
                <svg className="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z" />
                </svg>
                My List
              </button>
            )}

            {hasMediaInfo && (
              <button
                onClick={onToggleMediaInfo}
                className="inline-flex items-center px-5 py-3 text-base font-medium text-white bg-white/20 backdrop-blur-sm rounded-lg hover:bg-white/30 transition-all"
              >
                <svg className="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z" />
                </svg>
                Info
              </button>
            )}
          </div>

          {/* Media Info Panel */}
          {showMediaInfo && versionDetails.length > 0 && (
            <div className="max-w-4xl p-4 mb-8 bg-black/60 backdrop-blur-md rounded-lg border border-white/10">
              {/* Version Selector */}
              {versionDetails.length > 1 && (
                <div className="flex flex-wrap gap-2 mb-4">
                  {versionDetails.map(v => (
                    <button
                      key={v.id}
                      onClick={() => onVersionChange?.(v.id)}
                      className={`px-4 py-2 text-sm font-medium rounded-full transition-all ${
                        infoVersion === v.id
                          ? 'bg-white text-black'
                          : 'bg-white/10 text-white hover:bg-white/20'
                      }`}
                    >
                      {v.label}
                    </button>
                  ))}
                </div>
              )}

              {/* Selected Version Details */}
              {infoVersion && (
                <div className="space-y-3 text-sm text-white/80">
                  {versionDetails.find(v => v.id === infoVersion)?.audios?.length > 0 && (
                    <div>
                      <span className="text-white/50 mr-2">Audio:</span>
                      {versionDetails.find(v => v.id === infoVersion)?.audios.map((a, i) => (
                        <span key={i} className="inline-block mr-2 px-2 py-1 bg-white/10 rounded">
                          {a.label}
                        </span>
                      ))}
                    </div>
                  )}
                  {versionDetails.find(v => v.id === infoVersion)?.subs?.length > 0 && (
                    <div>
                      <span className="text-white/50 mr-2">Subtitles:</span>
                      {versionDetails.find(v => v.id === infoVersion)?.subs.map((s, i) => (
                        <span key={i} className="inline-block mr-2 px-2 py-1 bg-white/10 rounded">
                          {s.label}
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {/* Bottom Metadata Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 max-w-5xl">
            {/* Cast */}
            {cast.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-white/50 mb-2">Cast</h3>
                <div className="flex flex-wrap gap-2">
                  {cast.slice(0, 4).map((person, i) => (
                    <button
                      key={i}
                      onClick={() => onPersonClick?.(person)}
                      className="text-white/80 hover:text-white transition-colors"
                    >
                      {person.name}{i < Math.min(3, cast.length - 1) && ','}
                    </button>
                  ))}
                  {cast.length > 4 && (
                    <span className="text-white/50">+{cast.length - 4} more</span>
                  )}
                </div>
              </div>
            )}

            {/* Genres */}
            {genres.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-white/50 mb-2">Genres</h3>
                <div className="flex flex-wrap gap-2">
                  {genres.map((genre, i) => (
                    <span key={i} className="text-white/80">
                      {genre}{i < genres.length - 1 && ','}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {/* Mood Tags */}
            {moodTags.length > 0 && (
              <div>
                <h3 className="text-sm font-medium text-white/50 mb-2">
                  This {kind === 'tv' ? 'Series' : 'Movie'} Is
                </h3>
                <div className="flex flex-wrap gap-2">
                  {moodTags.map((tag, i) => (
                    <span key={i} className="text-white/80">
                      {tag}{i < moodTags.length - 1 && ','}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Mute Button for Trailer */}
      {localShowTrailer && (trailerUrl || trailerKey) && (
        <button
          onClick={onToggleMute}
          className="absolute bottom-8 right-8 p-3 bg-white/20 backdrop-blur-sm rounded-full hover:bg-white/30 transition-all"
          aria-label={trailerMuted ? 'Unmute' : 'Mute'}
        >
          {trailerMuted ? (
            <svg className="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 24 24">
              <path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/>
            </svg>
          ) : (
            <svg className="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 24 24">
              <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/>
            </svg>
          )}
        </button>
      )}
    </div>
  );
}
import WatchlistButton from '@/components/WatchlistButton';
