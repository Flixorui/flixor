import SmartImage from '@/components/SmartImage';
import { useSettings } from '@/state/settings';
import { useCardStyle } from './cardStyle';
import { useCardArtwork } from './useCardArtwork';
import { useCardInteractions } from './useCardInteractions';
import type { CardItem, CardMenuAction } from './cardTypes';

export type ContinueWatchingCardStyle = 'landscape' | 'poster' | 'wide';

const WIDE_CARD_WIDTH = 520;

function formatRemaining(ms: number) {
  const totalMinutes = Math.floor(ms / 60000);
  if (totalMinutes < 60) return `${totalMinutes}m left`;
  const hours = Math.floor(totalMinutes / 60);
  const mins = totalMinutes % 60;
  return mins > 0 ? `${hours}h ${mins}m left` : `${hours}h left`;
}

function ProgressBar({ percent, className = '' }: { percent: number; className?: string }) {
  return (
    <div className={`h-1 rounded-full bg-white/30 overflow-hidden ${className}`}>
      <div className="h-full rounded-full bg-brand" style={{ width: `${percent}%` }} />
    </div>
  );
}

export default function ContinueWatchingCard({
  item,
  cardStyle,
  onClick,
  menuActions,
  tabIndex,
}: {
  item: CardItem;
  cardStyle: ContinueWatchingCardStyle;
  onClick?: (id: string) => void;
  menuActions?: CardMenuAction[];
  tabIndex?: number;
}) {
  const style = useCardStyle();
  const settings = useSettings();
  const { cardProps, overlay } = useCardInteractions<HTMLDivElement>({
    item,
    onOpen: () => onClick?.(item.id),
    menuActions,
    tabIndex,
  });
  // Wide cards show the episode still, so only the other styles swap in show art.
  const upgraded = useCardArtwork(
    cardProps.ref,
    cardStyle === 'wide' ? '' : item.id,
    cardStyle === 'poster' ? 'poster' : 'backdrop',
    item.mediaType,
  );

  const src = upgraded || (cardStyle === 'poster' ? item.image : item.backdrop || item.image);
  const percent = Math.max(0, Math.min(100, item.progress ?? 0));
  const remaining = item.duration && item.viewOffset ? Math.max(0, item.duration - item.viewOffset) : 0;
  const heading = item.showTitle || item.title;
  const detail = [item.episodeInfo, item.showTitle ? item.title : undefined].filter(Boolean).join(' · ') || item.subtitle;
  const blurStill = cardStyle === 'wide' && settings.continueWatchingBlurNextUp && item.isNextUp;
  const artClass = 'relative overflow-hidden bg-neutral-800 ring-1 ring-white/10 group-hover:ring-2 group-hover:ring-white/90 group-focus-visible:ring-2 group-focus-visible:ring-white transition-all duration-200';
  const art = src ? (
    <SmartImage
      url={src}
      alt={heading}
      width={cardStyle === 'poster' ? style.posterWidth : WIDE_CARD_WIDTH}
      className="w-full h-full"
      imgClassName={blurStill ? 'blur-xl scale-110' : 'object-cover'}
    />
  ) : (
    <div className="w-full h-full skeleton" />
  );

  if (cardStyle === 'wide') {
    return (
      <div {...cardProps} className="group flex-shrink-0 cursor-pointer outline-none" style={{ width: `min(${WIDE_CARD_WIDTH}px, 86vw)` }}>
        <div className={`${artClass} aspect-video`} style={{ borderRadius: style.radius }}>
          {art}
          {item.isNextUp && (
            <span className="absolute top-2 left-2 text-[11px] font-semibold bg-black/70 text-white px-2 py-0.5 rounded">Up Next</span>
          )}
        </div>
        <div className="mt-2 px-0.5">
          <p className="text-white font-semibold text-sm line-clamp-1">{heading}</p>
          {detail && <p className="text-white/60 text-xs line-clamp-1 mt-0.5">{detail}</p>}
          {percent > 0 && (
            <div className="flex items-center gap-2 mt-1.5">
              <ProgressBar percent={percent} className="flex-1" />
              {remaining > 0 && <span className="text-white/60 text-[11px]">{formatRemaining(remaining)}</span>}
            </div>
          )}
        </div>
        {overlay}
      </div>
    );
  }

  if (cardStyle === 'poster') {
    return (
      <div {...cardProps} className="group flex-shrink-0 cursor-pointer outline-none" style={{ width: style.posterWidth }}>
        <div className={`${artClass} aspect-[2/3]`} style={{ borderRadius: style.radius }}>
          {art}
          {percent > 0 && <ProgressBar percent={percent} className="absolute left-2 right-2 bottom-2" />}
        </div>
        {style.titleMode !== 'never' && (
          <div className="pt-2 px-0.5">
            <p className="text-sm font-medium text-white/90 line-clamp-1">{heading}</p>
            {detail && <p className="text-xs text-neutral-400 line-clamp-1 mt-0.5">{detail}</p>}
          </div>
        )}
        {overlay}
      </div>
    );
  }

  return (
    <div {...cardProps} className="group flex-shrink-0 cursor-pointer outline-none" style={{ width: `min(${style.landscapeWidth}px, 86vw)` }}>
      <div className={`${artClass} aspect-video`} style={{ borderRadius: style.radius }}>
        {art}
        <div className="absolute inset-x-0 bottom-0 p-3 pt-10 bg-gradient-to-t from-black/80 to-transparent">
          <p className="text-white font-semibold text-sm line-clamp-1">{heading}</p>
          {detail && <p className="text-white/70 text-xs line-clamp-1">{detail}</p>}
          {percent > 0 && (
            <div className="flex items-center gap-2 mt-1.5">
              <ProgressBar percent={percent} className="flex-1" />
              {remaining > 0 && <span className="text-white text-[11px] font-medium">{formatRemaining(remaining)}</span>}
            </div>
          )}
        </div>
      </div>
      {overlay}
    </div>
  );
}
