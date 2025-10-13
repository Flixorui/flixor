type Version = { id: string; label: string };

export default function VersionSelector({ versions, active, onSelect }: { versions: Version[]; active?: string; onSelect: (id: string) => void }) {
  if (!versions.length) return null;
  return (
    <div className="flex gap-2 flex-wrap mt-2">
      {versions.map(v => (
        <button key={v.id} onClick={() => onSelect(v.id)} className={`h-8 px-3 rounded-full text-sm ring-1 ${active===v.id? 'bg-white text-black ring-white/0':'bg-white/5 text-neutral-200 hover:bg-white/10 ring-white/10'}`}>{v.label}</button>
      ))}
    </div>
  );
}

