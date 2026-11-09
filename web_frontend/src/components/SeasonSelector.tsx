import SmartImage from './SmartImage';

type Season = {
  key: string;
  title: string;
  index?: number;
  number?: number;
  image?: string;
};

type Props = {
  seasons: Season[];
  seasonKey: string;
  onChange: (key: string) => void;
  /** 'posters' shows artwork cards, as in the macOS "Season picker style" setting. */
  variant?: 'chips' | 'posters';
};

export default function SeasonSelector({ seasons, seasonKey, onChange, variant = 'chips' }: Props) {
  if (!seasons?.length) return null;

  if (variant === 'posters') {
    return (
      <div className="row-edge overflow-x-auto no-scrollbar pb-2">
        <div className="flex w-max gap-3">
          {seasons.map((s, idx) => {
            const active = s.key === seasonKey;
            const label = s.title || `Season ${s.number ?? idx + 1}`;
            return (
              <button key={s.key} onClick={() => onChange(s.key)} className="w-[110px] flex-shrink-0 text-left" aria-pressed={active}>
                <div className={`aspect-[2/3] overflow-hidden rounded-lg bg-white/10 transition ${active ? 'ring-2 ring-white' : 'ring-1 ring-white/10 hover:ring-white/40'}`}>
                  {s.image ? (
                    <SmartImage url={s.image} alt={label} width={220} className="h-full w-full" imgClassName="object-cover" />
                  ) : (
                    <div className="flex h-full items-center justify-center text-sm text-white/60">{label}</div>
                  )}
                </div>
                <p className={`mt-1.5 truncate text-xs ${active ? 'font-semibold text-white' : 'text-white/60'}`}>{label}</p>
              </button>
            );
          })}
        </div>
      </div>
    );
  }

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
