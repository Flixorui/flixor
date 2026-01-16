import { useState, useEffect, useRef } from 'react';
import RatingsBar from '@/components/RatingsBar';
import ContentRatingBadge from '@/components/ContentRatingBadge';
import { TechBadgeCompact, AccessibilityBadges } from '@/components/TechBadge';
import RequestButton from '@/components/RequestButton';
import { useNavigate } from 'react-router-dom';

interface Trailer {
  key: string;
  name: string;
  type?: string;
  site?: string;
}

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
  director?: string;
  moodTags?: string[];
  kind?: 'movie' | 'tv';
  techInfo?: { resolution?: string; hdr?: string; videoCodec?: string; audioCodec?: string };

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
  requestProps?: { tmdbId: number; mediaType: 'movie' | 'tv' };
  onMarkWatched?: () => void;
  onPersonClick?: (person: { id?: string; name: string }) => void;

  // Trailer background
  trailerUrl?: string;
  trailerKey?: string;
  trailerMuted?: boolean;
  showTrailer?: boolean;
  onToggleMute?: () => void;

  // Trailers row
  trailers?: Trailer[];
  onTrailerClick?: (trailer: Trailer) => void;

  // Accessibility badges
  hasCC?: boolean;
  hasSDH?: boolean;
  hasAD?: boolean;

  // Episode-specific
  isEpisode?: boolean;
  showTitle?: string;
  episodeInfo?: string;
  onViewShow?: () => void;
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
  director,
  moodTags = [],
  kind,
  techInfo,
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
  requestProps,
  onPersonClick,
  trailerUrl,
  trailerKey,
  trailerMuted = true,
  showTrailer = false,
  onToggleMute,
  continueLabel,
  onContinue,
  trailers = [],
  onTrailerClick,
  hasCC = false,
  hasSDH = false,
  hasAD = false,
  isEpisode = false,
  showTitle,
  episodeInfo,
  onViewShow,
}: DetailsHeroProps) {
  const [imageLoaded, setImageLoaded] = useState(false);
  const [localShowTrailer, setLocalShowTrailer] = useState(showTrailer);
  const videoRef = useRef<HTMLVideoElement>(null);

  // Reset trailer state when title changes (detected by backdrop/trailer change)
  useEffect(() => {
    console.log('[DetailsHero] Trailer props changed:', { showTrailer, trailerKey, trailerUrl });
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

        {/* Trailer overlay - prefer YouTube over Plex for reliability */}
        {localShowTrailer && (trailerUrl || trailerKey) && (
          <div className="absolute inset-0">
            {trailerKey ? (
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
            ) : trailerUrl ? (
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
                onError={() => {
                  console.error('[DetailsHero] Plex trailer failed to load');
                  setLocalShowTrailer(false);
                }}
              />
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

      {/* Content Layer - Two Column Layout like MacOS */}
      <div className="relative z-10 flex flex-col justify-end min-h-[85vh] md:min-h-[90vh]">
        <div className="px-4 md:px-8 lg:px-12 xl:px-16 pb-12 md:pb-16">
          <div className="flex justify-between items-end gap-8">
            {/* Left Column - Main Content */}
            <div className="flex-1 max-w-3xl">
              {/* Episode info header (for episodes) */}
              {isEpisode && showTitle && (
                <div className="mb-2">
                  <button
                    onClick={onViewShow}
                    className="text-sm text-white/70 hover:text-white transition-colors flex items-center gap-1"
                  >
                    <span className="font-medium">{showTitle}</span>
                    {episodeInfo && (
                      <>
                        <span className="text-white/40">•</span>
                        <span>{episodeInfo}</span>
                      </>
                    )}
                    <svg className="w-4 h-4 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                    </svg>
                  </button>
                </div>
              )}

              {/* Title/Logo */}
              <div className="mb-4">
                {logo && !isEpisode ? (
                  <img
                    src={logo}
                    alt={title}
                    className="h-20 md:h-28 lg:h-36 max-w-[90vw] md:max-w-[50vw] object-contain drop-shadow-2xl"
                    style={{ filter: 'drop-shadow(0 10px 40px rgba(0,0,0,0.8))' }}
                  />
                ) : (
                  <h1 className={`font-black tracking-tight text-white ${isEpisode ? 'text-3xl md:text-4xl lg:text-5xl' : 'text-4xl md:text-6xl lg:text-7xl'}`}
                      style={{ textShadow: '0 10px 40px rgba(0,0,0,0.8)' }}>
                    {title}
                  </h1>
                )}
              </div>

              {/* Type + Genres + Content Rating Row (like MacOS) */}
              <div className="flex flex-wrap items-center gap-2 mb-4 text-sm text-white/80">
                {kind && (
                  <>
                    <svg className="w-4 h-4 text-white/70" fill="currentColor" viewBox="0 0 24 24">
                      {kind === 'movie' ? (
                        <path d="M18 4l2 4h-3l-2-4h-2l2 4h-3l-2-4H8l2 4H7L5 4H4c-1.1 0-1.99.9-1.99 2L2 18c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V4h-4z"/>
                      ) : (
                        <path d="M21 3H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h5v2h8v-2h5c1.1 0 1.99-.9 1.99-2L23 5c0-1.1-.9-2-2-2zm0 14H3V5h18v12z"/>
                      )}
                    </svg>
                    <span>{kind === 'movie' ? 'Movie' : (isEpisode ? 'Episode' : 'TV Series')}</span>
                  </>
                )}
                {genres.length > 0 && (
                  <>
                    {kind && <span className="text-white/40">•</span>}
                    {genres.slice(0, 3).map((genre, i) => (
                      <span key={i}>
                        {genre}{i < Math.min(2, genres.length - 1) && <span className="text-white/40 mx-1">•</span>}
                      </span>
                    ))}
                  </>
                )}
                {rating && (
                  <>
                    <span className="text-white/40">•</span>
                    <ContentRatingBadge rating={rating} size="sm" />
                  </>
                )}
              </div>

              {/* Overview with MORE button */}
              {overview && (
                <div className="mb-4">
                  <p className="text-sm md:text-base text-white/80 leading-relaxed line-clamp-2">
                    {overview}
                  </p>
                </div>
              )}

              {/* Year + Runtime + Tech Badges + Ratings Row */}
              <div className="flex flex-wrap items-center gap-1.5 mb-5 text-xs">
                {year && <span className="text-white/90 font-medium">{year}</span>}
                {runtime && (
                  <>
                    <span className="text-white/40">•</span>
                    <span className="text-white/90 font-medium">{Math.floor(runtime / 60)}h {runtime % 60}m</span>
                  </>
                )}
                {techInfo && (techInfo.resolution || techInfo.hdr || techInfo.audioCodec) && (
                  <TechBadgeCompact
                    resolution={techInfo.resolution}
                    hdr={techInfo.hdr}
                    audioCodec={techInfo.audioCodec}
                    size="sm"
                    className="ml-0.5"
                  />
                )}
                {/* CC/SDH/AD badges */}
                {(hasCC || hasSDH || hasAD) && (
                  <AccessibilityBadges hasCC={hasCC} hasSDH={hasSDH} hasAD={hasAD} size="sm" />
                )}
                {/* Availability badge */}
                {(playable || !!onContinue) ? (
                  <span className="inline-flex items-center gap-1 px-1.5 py-0.5 text-[11px] font-medium text-green-400/90 rounded">
                    <svg className="w-2.5 h-2.5" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                    </svg>
                    Available
                  </span>
                ) : requestProps && (
                  <span className="inline-flex items-center gap-1 px-1.5 py-0.5 text-[11px] font-medium text-orange-400/90 rounded">
                    <svg className="w-2.5 h-2.5" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/>
                    </svg>
                    Not Available
                  </span>
                )}
                {ratings && (ratings.imdb || ratings.rt) && (
                  <RatingsBar imdb={ratings.imdb || undefined} rt={ratings.rt || undefined} size="sm" />
                )}
              </div>

              {/* Action Buttons - Clean MacOS Style */}
              <div className="flex items-center gap-3 mb-6">
                {onContinue ? (
                  <button
                    onClick={onContinue}
                    className="inline-flex items-center px-6 py-2.5 text-sm font-semibold rounded-md transition-all bg-white text-black hover:bg-white/90"
                  >
                    <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M8 5v14l11-7z" />
                    </svg>
                    {continueLabel || 'Continue'}
                  </button>
                ) : (
                  <button
                    onClick={onPlay}
                    disabled={!playable}
                    className={`inline-flex items-center px-6 py-2.5 text-sm font-semibold rounded-md transition-all ${
                      playable
                        ? 'bg-white text-black hover:bg-white/90'
                        : 'bg-white/50 text-neutral-500 cursor-not-allowed'
                    }`}
                  >
                    <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M8 5v14l11-7z" />
                    </svg>
                    Play
                  </button>
                )}

                {/* Add to List - Circle Icon Button */}
                {watchlistProps ? (
                  <WatchlistButton
                    itemId={watchlistProps.itemId}
                    itemType={watchlistProps.itemType}
                    tmdbId={watchlistProps.tmdbId}
                    imdbId={watchlistProps.imdbId}
                    variant="icon"
                  />
                ) : (
                  <button
                    onClick={onAddToList}
                    className="w-10 h-10 flex items-center justify-center rounded-full bg-white/10 border border-white/30 text-white hover:bg-white/20 transition-all"
                    title="Add to My List"
                  >
                    <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z" />
                    </svg>
                  </button>
                )}

                {/* Mark Watched - Circle Icon Button */}
                {onMarkWatched && (
                  <button
                    onClick={onMarkWatched}
                    className="w-10 h-10 flex items-center justify-center rounded-full bg-white/10 border border-white/30 text-white hover:bg-white/20 transition-all"
                    title="Mark as Watched"
                  >
                    <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>
                    </svg>
                  </button>
                )}

                {requestProps && (
                  <RequestButton
                    tmdbId={requestProps.tmdbId}
                    mediaType={requestProps.mediaType}
                    title={title}
                    variant="circle"
                  />
                )}

                {/* View Show button for episodes */}
                {isEpisode && onViewShow && (
                  <button
                    onClick={onViewShow}
                    className="inline-flex items-center px-4 py-2.5 text-sm font-medium rounded-md transition-all bg-white/10 border border-white/30 text-white hover:bg-white/20"
                  >
                    <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 24 24">
                      <path d="M21 3H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h5v2h8v-2h5c1.1 0 1.99-.9 1.99-2L23 5c0-1.1-.9-2-2-2zm0 14H3V5h18v12z"/>
                    </svg>
                    View Show
                  </button>
                )}
              </div>

              {/* Trailers & Videos Row */}
              {trailers.length > 0 && (
                <div className="mb-6">
                  <h3 className="text-xs font-medium text-white/50 mb-2 uppercase tracking-wider">Trailers & Videos</h3>
                  <div className="flex gap-3 overflow-x-auto no-scrollbar pb-2 -mx-1 px-1">
                    {trailers.slice(0, 8).map((trailer) => (
                      <button
                        key={trailer.key}
                        onClick={() => onTrailerClick?.(trailer)}
                        className="flex-shrink-0 group relative rounded-lg overflow-hidden focus:outline-none focus:ring-2 focus:ring-white/50"
                      >
                        {/* Thumbnail */}
                        <div className="relative w-[140px] md:w-[160px] aspect-video bg-black/40">
                          <img
                            src={`https://img.youtube.com/vi/${trailer.key}/mqdefault.jpg`}
                            alt={trailer.name}
                            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                            loading="lazy"
                          />
                          {/* Type Badge */}
                          {trailer.type && (
                            <span className="absolute top-1.5 left-1.5 px-1.5 py-0.5 text-[10px] font-semibold bg-red-600 text-white rounded">
                              {trailer.type === 'Trailer' ? 'TRAILER' : trailer.type.toUpperCase()}
                            </span>
                          )}
                          {/* Play overlay */}
                          <div className="absolute inset-0 flex items-center justify-center bg-black/20 group-hover:bg-black/40 transition-colors">
                            <div className="w-10 h-10 rounded-full bg-white/90 flex items-center justify-center group-hover:scale-110 transition-transform shadow-lg">
                              <svg className="w-4 h-4 text-black ml-0.5" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M8 5v14l11-7z" />
                              </svg>
                            </div>
                          </div>
                        </div>
                        {/* Title */}
                        <div className="absolute bottom-0 left-0 right-0 p-1.5 bg-gradient-to-t from-black/90 to-transparent">
                          <p className="text-[11px] text-white font-medium truncate">{trailer.name}</p>
                        </div>
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>

            {/* Right Column - Starring & Director (Desktop only) */}
            <div className="hidden lg:block w-64 text-right flex-shrink-0">
              {cast.length > 0 && (
                <div className="mb-4">
                  <h3 className="text-xs font-medium text-white/50 mb-1">Starring</h3>
                  <div className="text-sm text-white/90">
                    {cast.slice(0, 4).map((person, i) => (
                      <button
                        key={i}
                        onClick={() => onPersonClick?.(person)}
                        className="hover:text-white transition-colors"
                      >
                        {person.name}{i < Math.min(3, cast.length - 1) && ', '}
                      </button>
                    ))}
                  </div>
                </div>
              )}
              {director && (
                <div>
                  <h3 className="text-xs font-medium text-white/50 mb-1">Director</h3>
                  <p className="text-sm text-white/90">{director}</p>
                </div>
              )}
            </div>
          </div>

          {/* Media Info Panel */}
          {showMediaInfo && versionDetails.length > 0 && (
            <div className="max-w-4xl p-4 mt-6 bg-black/60 backdrop-blur-md rounded-lg border border-white/10">
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
