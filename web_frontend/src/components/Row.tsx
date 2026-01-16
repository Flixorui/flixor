import LandscapeCard from './LandscapeCard';
import PosterCard from './PosterCard';
import ContinueWatchingLandscapeCard from './ContinueWatchingLandscapeCard';
import ContinueWatchingPosterCard from './ContinueWatchingPosterCard';
import { useSearchParams } from 'react-router-dom';
import { useMemo } from 'react';
import { loadSettings } from '@/state/settings';

type Item = {
  id: string;
  title: string;
  image: string;
  badge?: string;
  progress?: number;
  duration?: number;
  viewOffset?: number;
  episodeInfo?: string;
  showTitle?: string;
};

export default function Row({ title, items, variant = 'default', onItemClick, onRemove, onMarkWatched, browseKey, gutter = 'row' }: {
  title: string;
  items: Item[];
  variant?: 'default' | 'continue';
  onItemClick?: (id: string) => void;
  onRemove?: (id: string) => void;
  onMarkWatched?: (id: string) => void;
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
    <section className="mb-4">
      <div className={gutter === 'row' ? 'row-gutter' : ''}>
        <div className="row-band">
          <div className="py-[15px]">
            <div className="flex items-center gap-1">
              <h2 className="text-white font-bold text-lg cursor-default">{title}</h2>
              {browseKey && (
                <button
                  onClick={() => { params.set('bkey', browseKey); setParams(params, { replace: false }); }}
                  className="flex items-center text-white hover:text-white/80 transition-colors"
                  title="Browse"
                >
                  <svg className="w-[18px] h-[18px] ml-1 mt-[1px]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M9 5l7 7-7 7" />
                  </svg>
                </button>
              )}
            </div>
          </div>
          <div className={((gutter === 'row' || gutter === 'edge') ? 'row-edge' : 'row-edge-plain') + ' no-scrollbar overflow-x-auto py-[15px]'}>
            <div className="flex gap-3 md:gap-4 w-max">
              {uniqueItems.map((i) => {
                const settings = loadSettings();

                if (variant === 'continue') {
                  // Continue Watching uses continueWatchingLayout setting
                  // Default to poster layout, use landscape only when explicitly set
                  const useLandscape = settings.continueWatchingLayout === 'landscape';
                  if (useLandscape) {
                    return (
                      <ContinueWatchingLandscapeCard
                        key={i.id}
                        id={i.id}
                        title={i.title}
                        image={i.image!}
                        progress={i.progress ?? 0}
                        duration={i.duration}
                        viewOffset={i.viewOffset}
                        episodeInfo={i.episodeInfo}
                        showTitle={i.showTitle}
                        onClick={(id) => onItemClick?.(id)}
                        onRemove={onRemove}
                        onMarkWatched={onMarkWatched}
                      />
                    );
                  }
                  // Poster layout (default for continue watching)
                  return (
                    <ContinueWatchingPosterCard
                      key={i.id}
                      id={i.id}
                      title={i.title}
                      image={i.image!}
                      progress={i.progress ?? 0}
                      duration={i.duration}
                      viewOffset={i.viewOffset}
                      episodeInfo={i.episodeInfo}
                      showTitle={i.showTitle}
                      onClick={(id) => onItemClick?.(id)}
                      onRemove={onRemove}
                      onMarkWatched={onMarkWatched}
                    />
                  );
                }

                // Regular content rows use rowLayout setting
                // Default to landscape, use poster only when explicitly set
                const usePoster = settings.rowLayout === 'poster';
                if (usePoster) {
                  return (
                    <PosterCard
                      key={i.id}
                      id={i.id}
                      title={i.title}
                      image={i.image}
                      badge={i.badge}
                      onClick={(id) => onItemClick?.(id)}
                    />
                  );
                }

                return (
                  <LandscapeCard
                    key={i.id}
                    id={i.id}
                    title={i.title}
                    image={i.image!}
                    badge={i.badge}
                    onClick={() => onItemClick?.(i.id)}
                  />
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
