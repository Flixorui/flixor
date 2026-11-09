import { useSearchParams } from 'react-router-dom';
import SmartImage from '@/components/SmartImage';
import { useSettings } from '@/state/settings';
import DetailsSectionHeading, { DetailsHorizontalRow } from './DetailsSectionHeading';

export interface DetailsMediaItem {
  id: string;
  title: string;
  image?: string;
  poster?: string;
  subtitle?: string;
}

/** A row of titles under a shared details heading, in the layout chosen in Settings. */
export default function DetailsMediaRow({
  title,
  subtitle,
  items,
  browseKey,
  currentId,
  onSelect,
}: {
  title: string;
  subtitle?: string;
  items: DetailsMediaItem[];
  browseKey?: string;
  /** Highlighted and not clickable. */
  currentId?: string;
  onSelect: (id: string) => void;
}) {
  const { suggestedLayout } = useSettings();
  const [params, setParams] = useSearchParams();
  const usePoster = suggestedLayout === 'poster';

  if (!items.length) return null;

  return (
    <section>
      <div className="flex items-center gap-1 mb-4">
        <DetailsSectionHeading>{title}</DetailsSectionHeading>
        {browseKey && (
          <button
            onClick={() => { params.set('bkey', browseKey); setParams(params, { replace: false }); }}
            className="text-white hover:text-white/80 transition-colors"
            aria-label={`Browse ${title}`}
            title="Browse"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M9 5l7 7-7 7" />
            </svg>
          </button>
        )}
      </div>
      {subtitle && <p className="-mt-3 mb-4 text-sm text-white/50">{subtitle}</p>}
      <DetailsHorizontalRow>
        {items.map((item) => {
          const isCurrent = item.id === currentId;
          const image = usePoster ? item.poster || item.image : item.image || item.poster;
          return (
            <button
              key={item.id}
              onClick={() => { if (!isCurrent) onSelect(item.id); }}
              disabled={isCurrent}
              title={item.title}
              className={`group flex-shrink-0 text-left ${usePoster ? 'w-[140px] md:w-[160px]' : 'w-[240px] md:w-[280px]'}`}
            >
              <div
                className={`relative overflow-hidden rounded-xl bg-white/10 ${usePoster ? 'aspect-[2/3]' : 'aspect-video'} ${
                  isCurrent ? 'ring-2 ring-white' : 'ring-1 ring-white/10 group-hover:ring-white/40'
                } transition`}
              >
                {image ? (
                  <SmartImage url={image} alt={item.title} width={usePoster ? 300 : 500} className="h-full w-full" imgClassName="object-cover" />
                ) : (
                  <div className="flex h-full items-center justify-center p-3 text-center text-sm text-white/50">{item.title}</div>
                )}
                {isCurrent && (
                  <span className="absolute left-2 top-2 rounded bg-white px-1.5 py-0.5 text-[10px] font-bold text-black">Viewing</span>
                )}
              </div>
              <p className="mt-2 text-sm text-white/90 truncate">{item.title}</p>
              {item.subtitle && <p className="text-xs text-white/50 truncate">{item.subtitle}</p>}
            </button>
          );
        })}
      </DetailsHorizontalRow>
    </section>
  );
}
