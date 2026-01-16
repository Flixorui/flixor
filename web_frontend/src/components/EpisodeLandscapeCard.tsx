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
};

type Props = {
  ep: Episode;
  onClick?: (id: string) => void;
  disabled?: boolean;
};

export default function EpisodeLandscapeCard({ ep, onClick, disabled = false }: Props) {
  const progressPercent = ep.progress || 0;
  const showProgress = progressPercent > 0 && progressPercent < 85;
  const showCompleted = progressPercent >= 85;

  return (
    <button
      onClick={() => !disabled && onClick?.(ep.id)}
      disabled={disabled}
      className={`flex-shrink-0 w-[300px] md:w-[420px] aspect-[16/10] rounded-xl overflow-hidden bg-neutral-800 relative group text-left ${
        disabled ? 'opacity-60 cursor-default' : 'cursor-pointer'
      }`}
    >
      {/* Background image */}
      {ep.image ? (
        <SmartImage
          url={ep.image}
          alt={ep.title}
          width={420}
          className="absolute inset-0 w-full h-full"
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
        {ep.overview && (
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
  );
}
