import SmartImage from './SmartImage';
import { useCardStyle } from './cards/cardStyle';
import { useCardArtwork } from './cards/useCardArtwork';
import { useCardInteractions } from './cards/useCardInteractions';
import type { CardItem, CardMediaType, CardMenuAction } from './cards/cardTypes';

type CardProps = {
  id: string;
  title: string;
  image?: string;
  badge?: string;
  onClick?: (id: string) => void;
  layout?: 'row' | 'grid';
  item?: CardItem;
  mediaType?: CardMediaType;
  menuActions?: CardMenuAction[];
  tabIndex?: number;
};

export default function LandscapeCard({ id, title, image, badge, onClick, layout = 'row', item, mediaType, menuActions, tabIndex }: CardProps) {
  const style = useCardStyle();
  const normalizedId = id.replaceAll('%3A', ':');
  const cardItem: CardItem = item ?? { id: normalizedId, title, image, badge, mediaType };
  const { cardProps, overlay } = useCardInteractions<HTMLDivElement>({
    item: cardItem,
    onOpen: () => onClick?.(normalizedId),
    menuActions,
    tabIndex,
  });
  const upgraded = useCardArtwork(cardProps.ref, normalizedId, 'backdrop', cardItem.mediaType);
  const src = upgraded || cardItem.backdrop || image;
  const isGrid = layout === 'grid';

  return (
    <div
      {...cardProps}
      className={`group relative z-0 cursor-pointer outline-none ${isGrid ? 'w-full' : 'flex-shrink-0'}`}
      style={isGrid ? undefined : { width: `min(${style.landscapeWidth}px, 86vw)` }}
    >
      <div
        className={`relative ${isGrid ? 'aspect-video' : 'aspect-[2/1]'} card card-hover ring-1 ring-white/15 group-hover:ring-2 group-hover:ring-white/90 group-focus-visible:ring-2 group-focus-visible:ring-white transition-all duration-200 group-hover:z-20`}
        style={{ borderRadius: style.radius }}
      >
        {src ? (
          <SmartImage url={src} alt={title} width={style.landscapeWidth} className="w-full h-full" imgClassName="transition-transform duration-300 group-hover:scale-[1.03]" />
        ) : (
          <div className="w-full h-full skeleton" />
        )}
        {badge && <span className="absolute top-2 left-2 text-xs bg-black/70 text-white px-2 py-0.5 rounded">{badge}</span>}
        {style.showRatingBadges && cardItem.rating ? (
          <span className="absolute top-2 right-2 text-xs bg-black/70 text-white px-2 py-0.5 rounded">★ {Number(cardItem.rating).toFixed(1)}</span>
        ) : null}
        {style.titleMode !== 'never' && (
          <div
            className={`pointer-events-none absolute inset-x-0 bottom-0 p-3 pt-10 bg-gradient-to-t from-black/75 to-transparent transition-opacity ${
              style.titleMode === 'always' ? 'opacity-100' : 'opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100'
            }`}
          >
            <div className="text-white font-semibold text-sm line-clamp-2 drop-shadow-lg">{title}</div>
            {cardItem.subtitle && <div className="text-white/70 text-xs line-clamp-1">{cardItem.subtitle}</div>}
          </div>
        )}
      </div>
      {overlay}
    </div>
  );
}
