import { useSearchParams } from 'react-router-dom';
import SmartImage from '@/components/SmartImage';
import { useSettings } from '@/state/settings';
import DetailsSectionHeading, { DetailsHorizontalRow } from './DetailsSectionHeading';
import { useTitledArtwork } from './useTitledArtwork';

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
        {items.map((item) => (
          <DetailsMediaCard
            key={item.id}
            item={item}
            usePoster={usePoster}
            isCurrent={item.id === currentId}
            onSelect={onSelect}
          />
        ))}
      </DetailsHorizontalRow>
    </section>
  );
}

/**
 * One title, as on macOS: artwork with the title designed into it (see
 * useTitledArtwork), and the name only as an overlay on hover.
 */
function DetailsMediaCard({ item, usePoster, isCurrent, onSelect }: {
  item: DetailsMediaItem;
  usePoster: boolean;
  isCurrent: boolean;
  onSelect: (id: string) => void;
}) {
  const fallback = usePoster ? item.poster || item.image : item.image || item.poster;
  const image = useTitledArtwork(item.id, usePoster ? 'portrait' : 'landscape', fallback);
  return (
    <button
      onClick={() => { if (!isCurrent) onSelect(item.id); }}
      disabled={isCurrent}
      title={item.title}
      aria-label={item.subtitle ? `${item.title}, ${item.subtitle}` : item.title}
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
        {image && (
          <div className="pointer-events-none absolute inset-0 flex flex-col justify-end bg-gradient-to-b from-transparent to-black/75 p-3 opacity-0 transition-opacity duration-200 group-hover:opacity-100 group-focus-visible:opacity-100">
            <p className="truncate text-sm font-semibold text-white">{item.title}</p>
            {item.subtitle && <p className="truncate text-xs text-white/80">{item.subtitle}</p>}
          </div>
        )}
        {isCurrent && (
          <span className="absolute left-2 top-2 rounded bg-white px-1.5 py-0.5 text-[10px] font-bold text-black">Viewing</span>
        )}
      </div>
    </button>
  );
}
