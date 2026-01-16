import { loadSettings } from '@/state/settings';

export type RatingsData = {
  imdb?: { rating?: number; votes?: number } | null;
  rt?: { critic?: number; audience?: number } | null;
  // MDBList ratings
  letterboxd?: number | null;
  metacritic?: number | null;
  tmdb?: number | null;
  trakt?: number | null;
  plex?: number | null;
};

type RatingsBarProps = RatingsData & {
  className?: string;
  compact?: boolean;
  size?: 'sm' | 'md';
};

// Vote count formatter
function formatVotes(n?: number): string | undefined {
  if (!n) return undefined;
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1_000) return Math.round(n / 100) / 10 + 'k';
  return String(n);
}

// Color based on score
function getScoreColor(score: number | null | undefined, maxScore = 100): string {
  if (score == null) return 'text-white';
  const normalized = maxScore === 10 ? score * 10 : score;
  if (normalized >= 85) return 'text-green-400';
  if (normalized >= 60) return 'text-yellow-300';
  return 'text-red-400';
}

// Rating pill base classes
const getPillClasses = (size: 'sm' | 'md' = 'md') =>
  size === 'sm'
    ? 'inline-flex items-center h-5 px-1.5 rounded bg-white/10 backdrop-blur-sm text-white text-[10px] font-medium gap-1'
    : 'inline-flex items-center h-7 px-2.5 rounded-md bg-white/10 backdrop-blur-sm text-white text-xs font-medium gap-1.5';

// Legacy constant for backward compat
const pillClasses = getPillClasses('md');

// Image-based rating icon
function RatingIcon({ src, alt, className = '', size = 'md' }: { src: string; alt: string; className?: string; size?: 'sm' | 'md' }) {
  const sizeClass = size === 'sm' ? 'h-3' : 'h-4';
  return (
    <img
      src={src}
      alt={alt}
      className={`${sizeClass} w-auto object-contain ${className}`}
      loading="lazy"
    />
  );
}

// IMDb rating pill
function IMDbRating({ rating, votes, size = 'md' }: { rating: number; votes?: number; size?: 'sm' | 'md' }) {
  return (
    <span className="flex items-center gap-1" title="IMDb">
      <RatingIcon src="/ratings/imdb.png" alt="IMDb" size={size} />
      <span>{rating.toFixed(1)}</span>
      {size === 'md' && votes != null && <span className="text-white/60">({formatVotes(votes)})</span>}
    </span>
  );
}

// Rotten Tomatoes critic rating
function RTCriticRating({ score, size = 'md' }: { score: number; size?: 'sm' | 'md' }) {
  const isFresh = score >= 60;
  return (
    <span className="flex items-center gap-1" title="Rotten Tomatoes (Critic)">
      <RatingIcon
        src={isFresh ? '/ratings/tomato-fresh.png' : '/ratings/tomato-rotten.png'}
        alt={isFresh ? 'Fresh' : 'Rotten'}
        size={size}
      />
      <span className={getScoreColor(score)}>{score}%</span>
    </span>
  );
}

// Rotten Tomatoes audience rating
function RTAudienceRating({ score, size = 'md' }: { score: number; size?: 'sm' | 'md' }) {
  const isPositive = score >= 60;
  return (
    <span className="flex items-center gap-1" title="Rotten Tomatoes (Audience)">
      <RatingIcon
        src={isPositive ? '/ratings/popcorn-full.png' : '/ratings/popcorn-fallen.png'}
        alt={isPositive ? 'Upright' : 'Spilled'}
        size={size}
      />
      <span className={getScoreColor(score)}>{score}%</span>
    </span>
  );
}

// Letterboxd rating (0-5 scale)
function LetterboxdRating({ score }: { score: number }) {
  return (
    <span className={pillClasses} title="Letterboxd">
      <RatingIcon src="/ratings/letterboxd.svg" alt="Letterboxd" className="h-4" />
      <span className={getScoreColor(score * 20)}>{score.toFixed(1)}</span>
    </span>
  );
}

// Metacritic rating (0-100 scale)
function MetacriticRating({ score }: { score: number }) {
  return (
    <span className={pillClasses} title="Metacritic">
      <RatingIcon src="/ratings/metacritic.png" alt="Metacritic" />
      <span className={getScoreColor(score)}>{score}</span>
    </span>
  );
}

// TMDB rating (0-10 scale)
function TMDBRating({ score }: { score: number }) {
  return (
    <span className={pillClasses} title="TMDB">
      <RatingIcon src="/ratings/tmdb.svg" alt="TMDB" className="h-3.5" />
      <span className={getScoreColor(score, 10)}>{score.toFixed(1)}</span>
    </span>
  );
}

// Trakt rating (0-100 scale)
function TraktRating({ score }: { score: number }) {
  return (
    <span className={pillClasses} title="Trakt">
      <RatingIcon src="/ratings/trakt.svg" alt="Trakt" className="h-3.5" />
      <span className={getScoreColor(score)}>{score}%</span>
    </span>
  );
}

// Plex rating (0-10 scale)
function PlexRating({ score }: { score: number }) {
  return (
    <span className={pillClasses} title="Plex">
      <RatingIcon src="/ratings/plex.svg" alt="Plex" className="h-3.5" />
      <span className={getScoreColor(score, 10)}>{score.toFixed(1)}</span>
    </span>
  );
}

export function RatingsBar({
  imdb,
  rt,
  letterboxd,
  metacritic,
  tmdb,
  trakt,
  plex,
  className = '',
  compact = false,
  size = 'md',
}: RatingsBarProps) {
  const settings = loadSettings();
  const ratingsVisible = settings.ratingsVisible || {
    imdb: true,
    rtCritic: true,
    rtAudience: true,
    letterboxd: true,
    metacritic: true,
  };

  const hasAnyRating =
    imdb?.rating != null ||
    rt?.critic != null ||
    rt?.audience != null ||
    letterboxd != null ||
    metacritic != null ||
    tmdb != null ||
    trakt != null ||
    plex != null;

  if (!hasAnyRating) return null;

  const gapClass = size === 'sm' ? 'gap-1.5' : 'gap-2';

  // In compact mode, show only primary ratings
  if (compact) {
    return (
      <div className={`flex items-center ${gapClass} flex-wrap ${className}`}>
        {ratingsVisible.imdb !== false && imdb?.rating != null && (
          <IMDbRating rating={imdb.rating} votes={imdb.votes} size={size} />
        )}
        {ratingsVisible.rtCritic !== false && rt?.critic != null && (
          <RTCriticRating score={rt.critic} size={size} />
        )}
      </div>
    );
  }

  return (
    <div className={`flex items-center ${gapClass} flex-wrap ${className}`}>
      {/* Primary ratings */}
      {ratingsVisible.imdb !== false && imdb?.rating != null && (
        <IMDbRating rating={imdb.rating} votes={imdb.votes} size={size} />
      )}
      {ratingsVisible.rtCritic !== false && rt?.critic != null && (
        <RTCriticRating score={rt.critic} size={size} />
      )}
      {ratingsVisible.rtAudience !== false && rt?.audience != null && (
        <RTAudienceRating score={rt.audience} size={size} />
      )}

      {/* MDBList ratings */}
      {ratingsVisible.letterboxd !== false && letterboxd != null && (
        <LetterboxdRating score={letterboxd} />
      )}
      {ratingsVisible.metacritic !== false && metacritic != null && (
        <MetacriticRating score={metacritic} />
      )}

      {/* Additional ratings (always shown if available) */}
      {tmdb != null && <TMDBRating score={tmdb} />}
      {trakt != null && <TraktRating score={trakt} />}
      {plex != null && <PlexRating score={plex} />}
    </div>
  );
}

// Compact inline ratings for cards
export function RatingsInline({
  imdb,
  rt,
  className = '',
}: Pick<RatingsBarProps, 'imdb' | 'rt' | 'className'>) {
  if (!imdb?.rating && !rt?.critic) return null;

  return (
    <div className={`flex items-center gap-3 text-xs ${className}`}>
      {imdb?.rating != null && (
        <span className="flex items-center gap-1 text-yellow-400">
          <RatingIcon src="/ratings/imdb.png" alt="IMDb" className="h-3" />
          <span>{imdb.rating.toFixed(1)}</span>
        </span>
      )}
      {rt?.critic != null && (
        <span className={`flex items-center gap-1 ${getScoreColor(rt.critic)}`}>
          <RatingIcon
            src={rt.critic >= 60 ? '/ratings/tomato-fresh.png' : '/ratings/tomato-rotten.png'}
            alt="RT"
            className="h-3"
          />
          <span>{rt.critic}%</span>
        </span>
      )}
    </div>
  );
}

export default RatingsBar;
