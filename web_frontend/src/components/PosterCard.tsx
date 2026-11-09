import SmartImage from './SmartImage';
import { useCardStyle } from './cards/cardStyle';
import { useCardArtwork } from './cards/useCardArtwork';
import { useCardInteractions } from './cards/useCardInteractions';
import type { CardItem, CardMediaType, CardMenuAction, CardSurface } from './cards/cardTypes';

type PosterCardProps = {
  id: string;
  title: string;
  image?: string;
  subtitle?: string;
  badge?: string;
  onClick?: (id: string) => void;
  /** Extra details for the hover preview and menu. Rows pass the whole item. */
  item?: CardItem;
  mediaType?: CardMediaType;
  menuActions?: CardMenuAction[];
  surface?: CardSurface;
  tabIndex?: number;
  /** Fill the parent's width instead of using the configured poster size. */
  fill?: boolean;
};

export default function PosterCard({ id, title, image, subtitle, badge, onClick, item, mediaType, menuActions, surface = 'row', tabIndex, fill }: PosterCardProps) {
  const style = useCardStyle(surface);
  const cardItem: CardItem = item ?? { id, title, image, subtitle, badge, mediaType };
  const { cardProps, overlay } = useCardInteractions<HTMLDivElement>({
    item: cardItem,
    onOpen: () => onClick?.(id),
    menuActions,
    tabIndex,
  });
  const upgraded = useCardArtwork(cardProps.ref, id, 'poster', cardItem.mediaType);
  const src = upgraded || image;

  return (
    <div
      {...cardProps}
      className="group flex-shrink-0 text-left cursor-pointer outline-none"
      style={fill ? undefined : { width: style.posterWidth }}
    >
      <div
        className="relative overflow-hidden aspect-[2/3] bg-neutral-800 ring-1 ring-white/15 group-hover:ring-2 group-hover:ring-white/90 group-focus-visible:ring-2 group-focus-visible:ring-white transition-all duration-200 group-hover:z-20"
        style={{ borderRadius: style.radius }}
      >
        {src ? (
          <SmartImage
            url={src}
            alt={title}
            width={style.posterWidth}
            className="w-full h-full"
            imgClassName="transition-transform duration-300 group-hover:scale-[1.03]"
          />
        ) : (
          <div className="w-full h-full skeleton" />
        )}
        {badge && (
          <span className="absolute top-2 left-2 text-[10px] font-semibold bg-black/70 text-white px-1.5 py-0.5 rounded">
            {badge}
          </span>
        )}
        {style.showRatingBadges && cardItem.rating ? (
          <span className="absolute top-2 right-2 text-[10px] font-semibold bg-black/70 text-white px-1.5 py-0.5 rounded">
            ★ {Number(cardItem.rating).toFixed(1)}
          </span>
        ) : null}
        {style.titleMode === 'hover' && (
          <div className="absolute inset-x-0 bottom-0 p-2 bg-gradient-to-t from-black/85 to-transparent opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100 transition-opacity">
            <p className="text-xs font-semibold text-white line-clamp-2">{title}</p>
            {subtitle && <p className="text-[11px] text-white/70 line-clamp-1">{subtitle}</p>}
          </div>
        )}
      </div>
      {style.titleMode === 'always' && (
        <div className="pt-2 px-0.5">
          <p className="text-sm font-medium text-white/90 line-clamp-2">{title}</p>
          {subtitle && <p className="text-xs text-neutral-400 line-clamp-1 mt-0.5">{subtitle}</p>}
        </div>
      )}
      {overlay}
    </div>
  );
}
