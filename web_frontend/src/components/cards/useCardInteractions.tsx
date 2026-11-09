import { useCallback, useEffect, useRef, useState, type KeyboardEvent, type MouseEvent, type ReactNode, type RefObject } from 'react';
import { useNavigate } from 'react-router-dom';
import { useSettings } from '@/state/settings';
import CardContextMenu, { type OpenCardMenu } from './CardContextMenu';
import HoverPreview from './HoverPreview';
import type { CardItem, CardMenuAction } from './cardTypes';

/** Pointer must stay out of preview and card this long before it closes. */
const DISMISS_GRACE_MS = 150;
/** No preview within this long after a scroll event. */
const SCROLL_QUIET_MS = 350;

let lastScrollAt = 0;
let closeActivePreview: (() => void) | null = null;
if (typeof window !== 'undefined') {
  window.addEventListener(
    'scroll',
    () => {
      lastScrollAt = Date.now();
      closeActivePreview?.();
    },
    { capture: true, passive: true },
  );
  window.addEventListener('blur', () => closeActivePreview?.());
}

function canHover() {
  return typeof window !== 'undefined' && window.matchMedia('(hover: hover) and (pointer: fine)').matches;
}

export interface CardInteractionProps<E extends HTMLElement> {
  ref: RefObject<E>;
  role: 'button';
  tabIndex: number;
  'data-card': '';
  onClick: () => void;
  onMouseEnter: () => void;
  onMouseLeave: () => void;
  onContextMenu: (event: MouseEvent<E>) => void;
  onKeyDown: (event: KeyboardEvent<E>) => void;
}

/**
 * Behaviour shared by every card: open on click or Return, the context menu, and
 * the hover preview. Spread `cardProps` on the card root and render `overlay`.
 */
export function useCardInteractions<E extends HTMLElement = HTMLDivElement>({
  item,
  onOpen,
  menuActions,
  previewEnabled = true,
  tabIndex = 0,
}: {
  item: CardItem;
  onOpen?: () => void;
  menuActions?: CardMenuAction[];
  previewEnabled?: boolean;
  tabIndex?: number;
}): { cardProps: CardInteractionProps<E>; overlay: ReactNode } {
  const navigate = useNavigate();
  const settings = useSettings();
  const ref = useRef<E>(null);
  const [menu, setMenu] = useState<OpenCardMenu | null>(null);
  const [preview, setPreview] = useState<DOMRect | null>(null);
  const showTimer = useRef<number | undefined>(undefined);
  const hideTimer = useRef<number | undefined>(undefined);

  const closePreview = useCallback(() => {
    window.clearTimeout(showTimer.current);
    window.clearTimeout(hideTimer.current);
    setPreview(null);
  }, []);

  useEffect(() => () => {
    window.clearTimeout(showTimer.current);
    window.clearTimeout(hideTimer.current);
    if (closeActivePreview === closePreview) closeActivePreview = null;
  }, [closePreview]);

  const scheduleShow = () => {
    window.clearTimeout(hideTimer.current);
    if (preview || menu) return;
    if (!previewEnabled || !settings.cardHoverPreviewEnabled || !canHover()) return;
    window.clearTimeout(showTimer.current);
    showTimer.current = window.setTimeout(() => {
      const el = ref.current;
      if (!el) return;
      if (Date.now() - lastScrollAt < SCROLL_QUIET_MS) {
        scheduleShow();
        return;
      }
      closeActivePreview?.();
      closeActivePreview = closePreview;
      setPreview(el.getBoundingClientRect());
    }, settings.cardHoverPreviewDelay * 1000);
  };

  const scheduleHide = () => {
    window.clearTimeout(showTimer.current);
    window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(closePreview, DISMISS_GRACE_MS);
  };

  const openMenu = (x: number, y: number) => {
    closePreview();
    setMenu({ x, y });
  };

  const open = () => {
    closePreview();
    onOpen?.();
  };

  const cardProps: CardInteractionProps<E> = {
    ref,
    role: 'button',
    tabIndex,
    'data-card': '',
    onClick: open,
    onMouseEnter: scheduleShow,
    onMouseLeave: scheduleHide,
    onContextMenu: (event) => {
      event.preventDefault();
      openMenu(event.clientX, event.clientY);
    },
    onKeyDown: (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        open();
      } else if (event.key === 'ContextMenu' || (event.key === 'F10' && event.shiftKey)) {
        event.preventDefault();
        const rect = event.currentTarget.getBoundingClientRect();
        openMenu(rect.left + 16, rect.top + 16);
      }
    },
  };

  const overlay = (
    <>
      {menu && (
        <CardContextMenu
          item={item}
          at={menu}
          onClose={() => setMenu(null)}
          onOpen={onOpen}
          navigate={navigate}
          extraActions={menuActions}
        />
      )}
      {preview && (
        <HoverPreview
          item={item}
          anchor={preview}
          onOpen={open}
          navigate={navigate}
          onPointerEnter={() => window.clearTimeout(hideTimer.current)}
          onPointerLeave={scheduleHide}
        />
      )}
    </>
  );

  return { cardProps, overlay };
}
