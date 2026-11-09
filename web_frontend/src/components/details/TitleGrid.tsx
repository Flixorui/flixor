import { useNavigate } from 'react-router-dom';
import SmartImage from '@/components/SmartImage';

export interface TitleGridItem {
  id: string;
  title: string;
  image?: string;
  subtitle?: string;
}

/** Poster grid that opens a title's details page. */
export default function TitleGrid({
  items,
  renderOverlay,
}: {
  items: TitleGridItem[];
  /** Extra control over a poster, such as a remove button. */
  renderOverlay?: (item: TitleGridItem) => React.ReactNode;
}) {
  const nav = useNavigate();
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(130px,1fr))] gap-x-4 gap-y-6 md:grid-cols-[repeat(auto-fill,minmax(160px,1fr))]">
      {items.map((item) => (
        <div key={item.id} className="group relative min-w-0">
          <button onClick={() => nav(`/details/${encodeURIComponent(item.id)}`)} className="block w-full text-left" title={item.title}>
            <div className="aspect-[2/3] overflow-hidden rounded-xl bg-white/10 ring-1 ring-white/10 transition group-hover:ring-white/40">
              {item.image ? (
                <SmartImage url={item.image} alt={item.title} width={320} className="h-full w-full" imgClassName="object-cover" />
              ) : (
                <div className="flex h-full items-center justify-center p-3 text-center text-sm text-white/50">{item.title}</div>
              )}
            </div>
            <p className="mt-2 truncate text-sm text-white/90">{item.title}</p>
            {item.subtitle && <p className="truncate text-xs text-white/50">{item.subtitle}</p>}
          </button>
          {renderOverlay?.(item)}
        </div>
      ))}
    </div>
  );
}

/** Maps a TMDB movie or TV result to a grid item. */
export function tmdbGridItem(result: any, media: 'movie' | 'tv', image: (path?: string) => string | undefined, subtitle?: string): TitleGridItem {
  const date: string | undefined = media === 'tv' ? result.first_air_date || result.release_date : result.release_date || result.first_air_date;
  return {
    id: `tmdb:${media}:${result.id}`,
    title: result.title || result.name || '',
    image: image(result.poster_path),
    subtitle: subtitle ?? (date ? date.slice(0, 4) : undefined),
  };
}
