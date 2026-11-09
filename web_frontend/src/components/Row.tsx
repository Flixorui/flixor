import { useMemo, useState, type FocusEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import LandscapeCard from './LandscapeCard';
import PosterCard from './PosterCard';
import ContinueWatchingCard from './cards/ContinueWatchingCard';
import { handleRowKeyDown } from './cards/rowKeyboard';
import type { CardItem, CardMenuAction } from './cards/cardTypes';
import { useSettings } from '@/state/settings';

export default function Row({ title, caption, items, variant = 'default', onItemClick, menuActions, browseKey, browseHref, gutter = 'row' }: {
  title: string;
  /** Secondary label next to the title, for example the addon a catalog comes from. */
  caption?: string;
  items: CardItem[];
  variant?: 'default' | 'continue';
  onItemClick?: (id: string, item: CardItem) => void;
  /** Extra actions for an item's context menu. */
  menuActions?: (item: CardItem) => CardMenuAction[];
  browseKey?: string;
  /** Opens this page instead of the Browse popup. */
  browseHref?: string;
  gutter?: 'row' | 'inherit' | 'edge'; // 'row' = left-only wrapper + edge scroller; 'inherit' = plain; 'edge' = edge scroller only (no wrapper padding)
}) {
  const [params, setParams] = useSearchParams();
  const settings = useSettings();
  const [rovingIndex, setRovingIndex] = useState(0);
  // Deduplicate by stable item id to avoid React key collisions
  const uniqueItems = useMemo(() => {
    const seen = new Set<string>();
    const out: CardItem[] = [];
    for (const it of items || []) {
      const key = it?.id;
      if (!key) continue;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(it);
    }
    return out;
  }, [items]);

  const onFocusCapture = (event: FocusEvent<HTMLDivElement>) => {
    const card = (event.target as HTMLElement).closest('[data-card]');
    if (!card) return;
    const index = Array.from(event.currentTarget.querySelectorAll('[data-card]')).indexOf(card);
    if (index >= 0) setRovingIndex(index);
  };

  return (
    <section className="mb-4">
      <div className={gutter === 'row' ? 'row-gutter' : ''}>
        <div className="row-band">
          <div className="py-[15px]">
            <div className="flex items-center gap-1">
              <h2 className="text-white font-bold text-lg cursor-default">{title}</h2>
              {caption && <span className="ml-2 text-xs font-medium text-white/50">{caption}</span>}
              {browseHref && (
                <Link to={browseHref} className="flex items-center text-white hover:text-white/80 transition-colors" title="Browse" aria-label={`Browse ${title}`}>
                  <svg className="w-[18px] h-[18px] ml-1 mt-[1px]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M9 5l7 7-7 7" />
                  </svg>
                </Link>
              )}
              {browseKey && !browseHref && (
                <button
                  onClick={() => { params.set('bkey', browseKey); setParams(params, { replace: false }); }}
                  className="flex items-center text-white hover:text-white/80 transition-colors"
                  title="Browse"
                  aria-label={`Browse ${title}`}
                >
                  <svg className="w-[18px] h-[18px] ml-1 mt-[1px]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M9 5l7 7-7 7" />
                  </svg>
                </button>
              )}
            </div>
          </div>
          <div
            data-card-row=""
            onKeyDown={handleRowKeyDown}
            onFocusCapture={onFocusCapture}
            className={((gutter === 'row' || gutter === 'edge') ? 'row-edge' : 'row-edge-plain') + ' no-scrollbar overflow-x-auto py-[15px]'}
          >
            <div className="flex gap-3 md:gap-4 w-max">
              {uniqueItems.map((item, index) => {
                const tabIndex = index === Math.min(rovingIndex, uniqueItems.length - 1) ? 0 : -1;
                const open = () => onItemClick?.(item.id, item);
                const actions = menuActions?.(item);

                if (variant === 'continue') {
                  return (
                    <ContinueWatchingCard
                      key={item.id}
                      item={item}
                      cardStyle={settings.continueWatchingLayout || 'landscape'}
                      onClick={open}
                      menuActions={actions}
                      tabIndex={tabIndex}
                    />
                  );
                }

                if (settings.rowLayout === 'poster') {
                  return (
                    <PosterCard
                      key={item.id}
                      id={item.id}
                      title={item.title}
                      image={item.image}
                      subtitle={item.subtitle}
                      badge={item.badge}
                      item={item}
                      onClick={open}
                      menuActions={actions}
                      tabIndex={tabIndex}
                    />
                  );
                }

                return (
                  <LandscapeCard
                    key={item.id}
                    id={item.id}
                    title={item.title}
                    image={item.backdrop || item.image}
                    badge={item.badge}
                    item={item}
                    onClick={open}
                    menuActions={actions}
                    tabIndex={tabIndex}
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
