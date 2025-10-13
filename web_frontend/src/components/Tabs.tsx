export default function Tabs({ tabs, active, onChange }: { tabs: string[]; active: string; onChange: (t: string) => void }) {
  // De-duplicate and keep order
  const seen = new Set<string>();
  const uniq = tabs.filter((t) => (seen.has(t) ? false : (seen.add(t), true)));
  return (
    <div className="page-gutter mt-6">
      <div className="flex gap-6 text-sm">
        {uniq.map((t) => (
          <button key={t} onClick={() => onChange(t)} className={`pb-2 transition-colors ${active===t? 'text-white border-b-2 border-white':'text-neutral-400 hover:text-white'}`}>{t.toUpperCase()}</button>
        ))}
      </div>
      <div className="h-px bg-white/10 mt-1" />
    </div>
  );
}
