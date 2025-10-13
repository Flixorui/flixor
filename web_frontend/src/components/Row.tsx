import LandscapeCard from './LandscapeCard';
import ContinueCard from './ContinueCard';
import { useSearchParams } from 'react-router-dom';
import { useMemo } from 'react';

type Item = { id: string; title: string; image: string; badge?: string; progress?: number };

export default function Row({ title, items, variant = 'default', onItemClick, browseKey, gutter = 'row' }: {
  title: string;
  items: Item[];
  variant?: 'default' | 'continue';
  onItemClick?: (id: string) => void;
  browseKey?: string;
  gutter?: 'row' | 'inherit' | 'edge'; // 'row' = left-only wrapper + edge scroller; 'inherit' = plain; 'edge' = edge scroller only (no wrapper padding)
}) {
  const [params, setParams] = useSearchParams();
  // Deduplicate by stable item id to avoid React key collisions
  const uniqueItems = useMemo(() => {
    const seen = new Set<string>();
    const out: Item[] = [];
    for (const it of items || []) {
      const key = it?.id;
      if (!key) continue;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(it);
    }
    return out;
  }, [items]);
  return (
    <section className="py-0 my-6 md:my-8 lg:my-10">
      <div className={gutter === 'row' ? 'row-gutter' : ''}>
        <div className="row-band">
          <div className="pt-4">
            <div className="flex items-baseline gap-3 group">
              <h2 className="text-neutral-200 font-semibold text-xl md:text-2xl cursor-default">{title}</h2>
              {browseKey && (
                <button
                  onClick={() => { params.set('bkey', browseKey); setParams(params, { replace: false }); }}
                  className="flex items-center gap-1 text-sm text-neutral-300 hover:text-white opacity-0 group-hover:opacity-100 translate-x-0 group-hover:translate-x-1 transition-all duration-500 ease-out"
                  title="Browse"
                >
                  <span>Browse</span>
                  <span aria-hidden>›</span>
                </button>
              )}
            </div>
          </div>
          <div className={((gutter === 'row' || gutter === 'edge') ? 'row-edge' : 'row-edge-plain') + ' no-scrollbar overflow-x-auto py-3 md:py-4'}>
            <div className="flex gap-6 md:gap-8 pb-2 md:pb-4 w-max">
              {uniqueItems.map((i) => variant === 'continue' ? (
                <ContinueCard key={i.id} id={i.id} title={i.title} image={i.image!} progress={i.progress ?? 0} onClick={(id) => onItemClick?.(id)} />
              ) : (
                <LandscapeCard key={i.id} id={i.id} title={i.title} image={i.image!} badge={i.badge} onClick={() => onItemClick?.(i.id)} />
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
