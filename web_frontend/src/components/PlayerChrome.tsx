export default function PlayerChrome({
  title,
  onPlayPause,
  onSeek,
  onBack,
  isPlaying,
  currentTime,
  duration,
}: {
  title?: string;
  onPlayPause?: () => void;
  onSeek?: (t: number) => void;
  onBack?: () => void;
  isPlaying?: boolean;
  currentTime?: number;
  duration?: number;
}) {
  const pct = duration ? Math.max(0, Math.min(100, (100 * (currentTime || 0)) / duration)) : 0;
  return (
    <div className="absolute inset-x-0 bottom-0 p-4 bg-gradient-to-t from-black/80 to-transparent">
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center gap-3 text-sm text-neutral-200">
          <button onClick={onBack} className="px-2 py-1 rounded bg-white/10 hover:bg-white/20">Back</button>
          <button onClick={onPlayPause} className="px-3 py-1.5 rounded bg-white/10 hover:bg-white/20 min-w-[80px]">
            {isPlaying ? 'Pause' : 'Play'}
          </button>
          <div className="flex-1">
            <div className="h-1.5 bg-white/20 rounded">
              <div className="h-full bg-brand rounded" style={{ width: pct + '%' }} />
            </div>
          </div>
          <div className="min-w-[120px] text-right tabular-nums">
            {format(currentTime)} / {format(duration)}
          </div>
        </div>
        {title && <div className="mt-2 text-lg font-medium">{title}</div>}
      </div>
    </div>
  );
}

function format(t?: number) {
  if (!t || !isFinite(t)) return '0:00';
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = Math.floor(t % 60);
  return h > 0 ? `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}` : `${m}:${s.toString().padStart(2, '0')}`;
}

