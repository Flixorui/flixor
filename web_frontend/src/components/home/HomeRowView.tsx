import { useEffect, useRef, useState } from 'react';
import Row from '@/components/Row';
import SkeletonRow from '@/components/SkeletonRow';
import { useCardStyle } from '@/components/cards/cardStyle';
import type { CardItem } from '@/components/cards/cardTypes';
import { useSettings } from '@/state/settings';
import { preheatImages } from './preheat';
import { loadHomeRow, type HomeRowSpec } from './rowSpecs';

/** First posters preheated per row; the rest load as the row scrolls. */
const PREHEAT_PER_ROW = 12;

type RowState =
  | { status: 'waiting' | 'loading' }
  | { status: 'loaded'; items: CardItem[]; browseKey?: string }
  | { status: 'error'; message: string };

/** One Home row. Loads when it nears the viewport and hides itself if it comes back empty. */
export default function HomeRowView({
  spec,
  title,
  caption,
  onOpen,
  onEmpty,
}: {
  spec: HomeRowSpec;
  title: string;
  caption?: string;
  onOpen: (item: CardItem) => void;
  onEmpty: (id: string) => void;
}) {
  const hostRef = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<RowState>({ status: 'waiting' });
  const [attempt, setAttempt] = useState(0);
  const [near, setNear] = useState(false);
  const style = useCardStyle();
  const settings = useSettings();

  useEffect(() => {
    const el = hostRef.current;
    if (!el || near) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        observer.disconnect();
        setNear(true);
      },
      { rootMargin: '800px 0px' },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [near]);

  useEffect(() => {
    if (!near || spec.placeholder) return;
    let alive = true;
    setState((current) => (current.status === 'loaded' ? current : { status: 'loading' }));
    loadHomeRow(spec, attempt > 0)
      .then((result) => {
        if (!alive) return;
        setState({ status: 'loaded', items: result.items, browseKey: result.browseKey });
        if (result.items.length === 0) onEmpty(spec.id);
        const width = settings.rowLayout === 'poster' ? style.posterWidth : style.landscapeWidth;
        preheatImages(
          result.items.slice(0, PREHEAT_PER_ROW).map((item) => (settings.rowLayout === 'poster' ? item.image : item.backdrop || item.image)),
          width,
        );
      })
      .catch((error) => {
        if (alive) setState({ status: 'error', message: error?.message || 'Could not load this row' });
      });
    return () => {
      alive = false;
    };
    // `spec` identity changes when the row list is rebuilt; its id and items decide reloads.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [near, spec.id, spec.items, spec.placeholder, attempt]);

  if (state.status === 'loaded' && state.items.length === 0) return null;

  return (
    <div ref={hostRef}>
      {state.status === 'loaded' ? (
        <Row
          title={title}
          caption={caption}
          items={state.items}
          browseKey={state.browseKey || spec.browseKey}
          browseHref={spec.browseHref}
          onItemClick={(_id, item) => onOpen(item)}
        />
      ) : state.status === 'error' ? (
        <HomeRowErrorCard
          title={title}
          source={spec.source}
          message={state.message}
          onRetry={() => {
            if (spec.retry) spec.retry();
            else setAttempt((value) => value + 1);
          }}
        />
      ) : (
        <SkeletonRow title={title || undefined} />
      )}
    </div>
  );
}

export function HomeRowErrorCard({
  title,
  source,
  message,
  onRetry,
}: {
  title: string;
  source: string;
  message: string;
  onRetry: () => void;
}) {
  return (
    <section className="mb-4 page-gutter py-[15px]">
      <div className="flex items-center justify-between gap-4 rounded-xl bg-white/5 ring-1 ring-white/10 px-4 py-3">
        <div className="min-w-0">
          <p className="text-white font-semibold text-sm">{title}</p>
          <p className="text-white/60 text-xs line-clamp-2">
            {source ? `${source}: ` : ''}
            {message}
          </p>
        </div>
        <button onClick={onRetry} className="btn flex-shrink-0">
          Retry
        </button>
      </div>
    </section>
  );
}
