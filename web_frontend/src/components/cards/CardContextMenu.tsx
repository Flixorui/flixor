import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { detailsPath, resolvePlayerRoute } from './cardMedia';
import { isInMyList, resolveCardMedia, setInMyList, setWatched, supportsMyList, watchTargetFor } from './cardActions';
import type { CardMedia } from './cardMedia';
import type { CardItem, CardMenuAction } from './cardTypes';

export interface OpenCardMenu {
  x: number;
  y: number;
}

/**
 * Right-click menu for a card: Open Details, Play, My List, watched state, then
 * any actions the card's owner adds. Rendered at the pointer, clamped to the window.
 */
export default function CardContextMenu({
  item,
  at,
  onClose,
  onOpen,
  navigate,
  extraActions = [],
}: {
  item: CardItem;
  at: OpenCardMenu;
  onClose: () => void;
  onOpen?: () => void;
  navigate: (path: string) => void;
  extraActions?: CardMenuAction[];
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState({ left: at.x, top: at.y });
  const [media, setMedia] = useState<CardMedia | null>(null);
  const [playRoute, setPlayRoute] = useState<string | null>(null);
  const [inList, setInList] = useState<boolean | null>(null);
  const [confirmWatched, setConfirmWatched] = useState<boolean | null>(null);

  useEffect(() => {
    let alive = true;
    resolveCardMedia(item.id, item.mediaType)
      .then(async (resolved) => {
        if (!alive) return;
        setMedia(resolved);
        resolvePlayerRoute(item.id, item.mediaType)
          .then((route) => alive && setPlayRoute(route))
          .catch(() => {});
        if (supportsMyList(resolved.mediaType || item.mediaType)) {
          const listed = await isInMyList(resolved).catch(() => false);
          if (alive) setInList(listed);
        }
      })
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [item.id, item.mediaType]);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const margin = 8;
    const { width, height } = el.getBoundingClientRect();
    setPosition({
      left: Math.min(at.x, window.innerWidth - width - margin),
      top: Math.min(at.y, window.innerHeight - height - margin),
    });
  }, [at.x, at.y, media, playRoute, inList, confirmWatched]);

  useEffect(() => {
    const close = (event: Event) => {
      if (ref.current?.contains(event.target as Node)) return;
      onClose();
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    const onScroll = () => onClose();
    document.addEventListener('mousedown', close);
    document.addEventListener('contextmenu', close);
    document.addEventListener('keydown', onKey);
    window.addEventListener('scroll', onScroll, true);
    window.addEventListener('blur', onScroll);
    return () => {
      document.removeEventListener('mousedown', close);
      document.removeEventListener('contextmenu', close);
      document.removeEventListener('keydown', onKey);
      window.removeEventListener('scroll', onScroll, true);
      window.removeEventListener('blur', onScroll);
    };
  }, [onClose]);

  const mediaType = media?.mediaType || item.mediaType;
  const target = media ? watchTargetFor(item, media) : null;
  const isWholeShow = (mediaType === 'show' || mediaType === 'season') && !item.newEpisodeCount;
  const wholeLabel = mediaType === 'season' ? 'Season' : 'Show';
  const hasWatchActions = !item.target && !item.newEpisodeCount && !!target;

  const run = (action: () => void) => () => {
    onClose();
    action();
  };

  const applyWatched = (watched: boolean) => {
    if (target) setWatched(target, watched, item.title);
  };

  const body =
    confirmWatched !== null ? (
      <div className="px-3 py-3 w-[260px]">
        <p className="text-sm text-white">
          Mark every episode of {item.title} as {confirmWatched ? 'watched' : 'unwatched'}?
        </p>
        <div className="mt-3 flex justify-end gap-2">
          <button className="px-3 py-1.5 text-sm rounded-md bg-white/10 hover:bg-white/20 text-white" onClick={onClose}>
            Cancel
          </button>
          <button
            className="px-3 py-1.5 text-sm rounded-md bg-white text-black font-semibold hover:bg-white/90"
            onClick={run(() => applyWatched(confirmWatched))}
          >
            Confirm
          </button>
        </div>
      </div>
    ) : (
      <>
        <MenuItem label="Open Details" onSelect={run(() => (onOpen ? onOpen() : navigate(detailsPath(item.id))))} />
        {playRoute && <MenuItem label="Play" onSelect={run(() => navigate(playRoute))} />}

        {media && inList !== null && supportsMyList(mediaType) && (
          <>
            <Divider />
            <MenuItem
              label={inList ? 'Remove from My List' : 'Add to My List'}
              onSelect={run(() => setInMyList(media, !inList, item.title))}
            />
          </>
        )}

        {hasWatchActions &&
          (isWholeShow ? (
            <>
              <MenuItem label={`Mark Entire ${wholeLabel} as Watched…`} onSelect={() => setConfirmWatched(true)} />
              <MenuItem label={`Mark Entire ${wholeLabel} as Unwatched…`} onSelect={() => setConfirmWatched(false)} />
            </>
          ) : (
            <>
              <MenuItem label="Mark as Watched" onSelect={run(() => applyWatched(true))} />
              <MenuItem label="Mark as Unwatched" onSelect={run(() => applyWatched(false))} />
            </>
          ))}

        {extraActions.length > 0 && <Divider />}
        {extraActions.map((action) => (
          <MenuItem key={action.label} label={action.label} danger={action.danger} onSelect={run(action.onSelect)} />
        ))}
      </>
    );

  return createPortal(
    <div
      ref={ref}
      role="menu"
      className="fixed z-[200] min-w-[220px] py-1 rounded-lg bg-neutral-900 ring-1 ring-white/10 shadow-2xl"
      style={position}
      onClick={(event) => event.stopPropagation()}
      onKeyDown={(event) => event.stopPropagation()}
      onContextMenu={(event) => {
        event.preventDefault();
        event.stopPropagation();
      }}
    >
      {body}
    </div>,
    document.body,
  );
}

function MenuItem({ label, danger, onSelect }: { label: string; danger?: boolean; onSelect: () => void }) {
  return (
    <button
      role="menuitem"
      onClick={onSelect}
      className={`w-full px-4 py-2 text-left text-sm hover:bg-white/10 transition-colors ${danger ? 'text-red-400' : 'text-white'}`}
    >
      {label}
    </button>
  );
}

function Divider() {
  return <div className="my-1 h-px bg-white/10" />;
}
