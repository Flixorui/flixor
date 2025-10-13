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
};

export default function EpisodeItem({ ep, onClick }: { ep: Episode; onClick?: (id: string) => void }) {
  const nav = useNavigate();
  const go = () => (onClick ? onClick(ep.id) : nav(`/player/${encodeURIComponent(ep.id)}`));
  return (
    <button onClick={go} className="group w-full text-left">
      <div className="flex gap-4 items-start py-2">
        <div className="w-8 text-right pt-1 text-neutral-400 tabular-nums">{ep.index ?? ''}</div>
        <div className="relative w-44 h-24 rounded-xl overflow-hidden ring-1 ring-white/10 bg-neutral-800">
          {ep.image ? <SmartImage url={ep.image} alt={ep.title} width={160} className="w-full h-full" imgClassName="object-cover" /> : null}
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
        <div className="flex-1">
          <div className="flex items-center gap-2 text-sm text-neutral-300"><span className="text-white font-medium line-clamp-1">{ep.title}</span>{ep.duration? <span>• {ep.duration} min</span>: null}</div>
          <p className="text-neutral-400 text-sm line-clamp-2">{ep.overview}</p>
        </div>
      </div>
    </button>
  );
}
