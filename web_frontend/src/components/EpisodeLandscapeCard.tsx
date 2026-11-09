import SmartImage from './SmartImage';

export type Episode = {
  id: string;
  title: string;
  overview?: string;
  image?: string;
  duration?: number; // minutes
  progress?: number; // percent 0-100
  index?: number; // episode number
  airDate?: string;
  rating?: number; // 0-10
  watched?: boolean;
};

type Props = {
  ep: Episode;
  onClick?: (id: string) => void;
  disabled?: boolean;
  /** Blurs the still and hides the synopsis, until revealed. */
  spoilerHidden?: boolean;
  onReveal?: () => void;
  onToggleWatched?: () => void;
};

export default function EpisodeLandscapeCard({ ep, onClick, disabled = false, spoilerHidden = false, onReveal, onToggleWatched }: Props) {
  const progressPercent = ep.progress || 0;
  const showProgress = progressPercent > 0 && progressPercent < 85;
  const showCompleted = progressPercent >= 85 || !!ep.watched;

  return (
    <div className="group relative flex-shrink-0 w-[300px] md:w-[420px] aspect-[16/10]">
    <button
      onClick={() => !disabled && onClick?.(ep.id)}
      disabled={disabled}
      className={`absolute inset-0 rounded-xl overflow-hidden bg-neutral-800 text-left ${
        disabled ? 'opacity-60 cursor-default' : 'cursor-pointer'
      }`}
    >
      {/* Background image */}
      {ep.image ? (
        <SmartImage
          url={ep.image}
          alt={ep.title}
          width={420}
          className={`absolute inset-0 w-full h-full ${spoilerHidden ? 'blur-2xl scale-110' : ''}`}
          imgClassName="object-cover"
        />
      ) : (
        <div className="absolute inset-0 w-full h-full bg-neutral-800" />
      )}

      {/* Gradient overlay - stronger at bottom for text readability */}
      <div className="absolute inset-0 bg-gradient-to-t from-black/95 via-black/50 to-transparent" />

      {/* Completed checkmark - TOP RIGHT */}
      {showCompleted && (
        <div className="absolute top-3 right-3 w-7 h-7 rounded-full bg-white flex items-center justify-center">
          <svg className="w-5 h-5 text-black" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
          </svg>
        </div>
      )}

      {/* Content overlay - bottom aligned, left aligned */}
      <div className="absolute inset-x-0 bottom-0 p-3.5">
        {/* Episode pill badge */}
        <span className="inline-block bg-black/60 text-white text-[10px] font-bold tracking-widest uppercase px-2.5 py-1 rounded-md">
          Episode {ep.index || 1}
        </span>

        {/* Title */}
        <h3 className="text-white font-bold text-[15px] mt-1.5 line-clamp-1">
          {ep.title || 'Episode'}
        </h3>

        {/* Overview - 2 lines max */}
        {spoilerHidden ? (
          <p className="text-neutral-400 text-[13px] italic mt-1">Synopsis hidden to avoid spoilers.</p>
        ) : ep.overview && (
          <p className="text-neutral-300 text-[13px] line-clamp-2 mt-1 leading-[1.4]">
            {ep.overview}
          </p>
        )}

        {/* Duration */}
        {ep.duration && (
          <div className="flex items-center gap-1.5 mt-2 text-neutral-400">
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span className="text-[13px]">{ep.duration}m</span>
            {ep.rating != null && <span className="text-[13px] text-amber-300">★ {ep.rating.toFixed(1)}</span>}
          </div>
        )}
      </div>

      {/* Progress bar - at very bottom */}
      {showProgress && (
        <div className="absolute left-0 right-0 bottom-0 h-1 bg-white/30">
          <div
            className="h-full bg-white"
            style={{ width: `${progressPercent}%` }}
          />
        </div>
      )}
    </button>
    {(onToggleWatched || (spoilerHidden && onReveal)) && (
      <div className="absolute right-3 top-3 flex gap-2 opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100">
        {spoilerHidden && onReveal && (
          <button onClick={onReveal} className="rounded-full bg-black/60 px-2.5 py-1 text-xs text-white hover:bg-black/80">Reveal</button>
        )}
        {onToggleWatched && (
          <button
            onClick={onToggleWatched}
            aria-label={ep.watched ? `Mark ${ep.title} as unwatched` : `Mark ${ep.title} as watched`}
            title={ep.watched ? 'Mark as unwatched' : 'Mark as watched'}
            className={`rounded-full px-2.5 py-1 text-xs hover:bg-black/80 ${ep.watched ? 'bg-white text-black' : 'bg-black/60 text-white'}`}
          >
            {ep.watched ? 'Unwatched' : 'Watched'}
          </button>
        )}
      </div>
    )}
    </div>
  );
}
