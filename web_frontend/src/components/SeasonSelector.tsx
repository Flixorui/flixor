type Season = {
  key: string;
  title: string;
  index?: number;
};

type Props = {
  seasons: Season[];
  seasonKey: string;
  onChange: (key: string) => void;
};

export default function SeasonSelector({ seasons, seasonKey, onChange }: Props) {
  if (!seasons?.length) return null;

  return (
    <div className="flex items-center gap-2.5 overflow-x-auto no-scrollbar pb-2">
      {seasons.map((s, idx) => {
        const key = s.key;
        const active = key === seasonKey;
        return (
          <button
            key={key}
            onClick={() => onChange(key)}
            className={`
              flex-shrink-0 px-4 py-2 rounded-full font-bold text-sm transition-all
              ${active
                ? 'bg-white/[0.13] border border-white text-white'
                : 'bg-[#1a1b20] border border-[#2a2b30] text-white hover:bg-white/10'
              }
            `}
          >
            {s.title || `Season ${s.index || (idx + 1)}`}
          </button>
        );
      })}
    </div>
  );
}
