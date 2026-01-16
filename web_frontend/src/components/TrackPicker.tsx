export type Track = { id: string; label: string; forced?: boolean };

export default function TrackPicker({
  audios,
  subs,
  audioActive,
  subActive,
  onAudio,
  onSub,
}: {
  audios: Track[];
  subs: Track[];
  audioActive?: string;
  subActive?: string;
  onAudio: (id: string) => void;
  onSub: (id: string) => void;
}) {
  if (!audios.length && !subs.length) return null;
  return (
    <div className="flex items-center gap-4 text-sm mt-3">
      {audios.length > 0 && (
        <div className="flex items-center gap-2">
          <span className="text-neutral-400">Audio</span>
          <div className="flex gap-2 flex-wrap">
            {audios.map((a) => (
              <button key={a.id} onClick={() => onAudio(a.id)} className={`h-8 px-3 rounded-full ring-1 ${audioActive===a.id? 'bg-white text-black ring-white/0':'bg-white/5 text-neutral-200 hover:bg-white/10 ring-white/10'}`}>{a.label}</button>
            ))}
          </div>
        </div>
      )}
      {subs.length > 0 && (
        <div className="flex items-center gap-2">
          <span className="text-neutral-400">Subtitles</span>
          <div className="flex gap-2 flex-wrap">
            {subs.map((s) => (
              <button key={s.id} onClick={() => onSub(s.id)} className={`h-8 px-3 rounded-full ring-1 ${subActive===s.id? 'bg-white text-black ring-white/0':'bg-white/5 text-neutral-200 hover:bg-white/10 ring-white/10'}`}>{s.label}</button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

