import { useNavigate } from 'react-router-dom';
import SmartImage from './SmartImage';

export type Episode = {
  id: string;
  title: string;
  overview?: string;
  image?: string;
  duration?: number; // minutes
  progress?: number; // percent 0-100
  index?: number; // episode number shown at left
  rating?: number; // 0-10
  watched?: boolean;
};

type EpisodeItemProps = {
  ep: Episode;
  onClick?: (id: string) => void;
  disabled?: boolean;
  /** Blurs the still and hides the synopsis, until revealed. */
  spoilerHidden?: boolean;
  onReveal?: () => void;
  onToggleWatched?: () => void;
};

export default function EpisodeItem({ ep, onClick, disabled = false, spoilerHidden = false, onReveal, onToggleWatched }: EpisodeItemProps) {
  const nav = useNavigate();
  const go = () => !disabled && (onClick ? onClick(ep.id) : nav(`/player/${encodeURIComponent(ep.id)}`));
  return (
    <div className="group relative">
      <button onClick={go} disabled={disabled} className={`w-full text-left ${disabled ? 'opacity-60 cursor-default' : ''}`}>
        <div className="flex gap-4 items-start py-2">
          <div className="w-8 text-right pt-1 text-neutral-400 tabular-nums">{ep.index ?? ''}</div>
          <div className="relative w-44 h-24 rounded-xl overflow-hidden ring-1 ring-white/10 bg-neutral-800">
            {ep.image ? <SmartImage url={ep.image} alt={ep.title} width={160} className={`w-full h-full ${spoilerHidden ? 'blur-xl scale-110' : ''}`} imgClassName="object-cover" /> : null}
            <div className="absolute inset-0 bg-black/0 group-hover:bg-black/25 transition-colors" />
            <div className="absolute inset-0 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
              <div className="px-3 py-1.5 rounded-full bg-white text-black text-sm font-medium">Play</div>
            </div>
            {typeof ep.progress === 'number' && ep.progress > 0 && (
              <div className="absolute bottom-0 left-0 right-0 h-1.5 bg-white/20">
                <div className="h-full bg-brand" style={{ width: Math.min(100, Math.max(0, ep.progress)) + '%' }} />
              </div>
            )}
          </div>
          <div className="flex-1 pr-10">
            <div className="flex items-center gap-2 text-sm text-neutral-300">
              <span className="text-white font-medium line-clamp-1">{ep.title}</span>
              {ep.duration ? <span className="flex-shrink-0">• {ep.duration} min</span> : null}
              {ep.rating != null && <span className="flex-shrink-0 text-amber-300">★ {ep.rating.toFixed(1)}</span>}
            </div>
            {spoilerHidden ? (
              <p className="text-neutral-500 text-sm italic">Synopsis hidden to avoid spoilers.</p>
            ) : (
              <p className="text-neutral-400 text-sm line-clamp-2">{ep.overview}</p>
            )}
          </div>
        </div>
      </button>
      {(onToggleWatched || (spoilerHidden && onReveal)) && (
        <div className="absolute right-1 top-3 flex gap-1">
          {spoilerHidden && onReveal && (
            <button
              onClick={onReveal}
              className="rounded-full bg-white/10 px-2.5 py-1 text-xs text-white opacity-0 transition-opacity hover:bg-white/20 focus:opacity-100 group-hover:opacity-100"
            >
              Reveal
            </button>
          )}
          {onToggleWatched && (
            <button
              onClick={onToggleWatched}
              aria-label={ep.watched ? `Mark ${ep.title} as unwatched` : `Mark ${ep.title} as watched`}
              title={ep.watched ? 'Mark as unwatched' : 'Mark as watched'}
              className={`flex h-7 w-7 items-center justify-center rounded-full transition-opacity hover:bg-white/20 focus:opacity-100 group-hover:opacity-100 ${ep.watched ? 'bg-white/15 text-brand opacity-100' : 'bg-white/10 text-white opacity-0'}`}
            >
              <svg className="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={3} d="M5 13l4 4L19 7" />
              </svg>
            </button>
          )}
        </div>
      )}
    </div>
  );
}
