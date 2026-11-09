/** Recent searches shown when the search field is empty. */
export default function SearchRecent({
  searches,
  onSelect,
  onRemove,
  onClear,
}: {
  searches: string[];
  onSelect: (text: string) => void;
  onRemove: (text: string) => void;
  onClear: () => void;
}) {
  return (
    <div className="mb-10">
      <div className="flex items-baseline justify-between mb-3">
        <h2 className="text-lg font-semibold text-white">Recent Searches</h2>
        <button onClick={onClear} className="text-sm font-medium text-white/60 hover:text-white" aria-label="Clear recent searches">
          Clear
        </button>
      </div>
      <div className="flex flex-wrap gap-2">
        {searches.map((text) => (
          <div key={text} className="inline-flex items-center rounded-full bg-white/10 ring-1 ring-white/10 text-sm text-white">
            <button onClick={() => onSelect(text)} className="pl-3 pr-1 py-1.5 hover:text-white/80">{text}</button>
            <button onClick={() => onRemove(text)} aria-label={`Remove ${text}`} className="pr-2.5 pl-1 py-1.5 text-white/50 hover:text-white">
              ×
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
