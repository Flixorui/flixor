import { type ReactNode, useLayoutEffect, useRef } from 'react';
import { Link } from 'react-router-dom';
import type { NavItem } from '@/components/nav/navItems';

const SELECTION_ANIMATION_MS = 420;

type FloatingNavTrackProps = {
  items: NavItem[];
  selectedId: NavItem['id'] | null;
  showsLabels: boolean;
  isFrosted: boolean;
  glowEnabled: boolean;
  /** The profile button at the end of the pill. */
  trailing?: ReactNode;
  /** When set, tabs are buttons (the Settings preview) instead of links. */
  onSelect?: (item: NavItem) => void;
};

/** The floating pill itself, shared by the app and the preview in Settings. */
export default function FloatingNavTrack({
  items,
  selectedId,
  showsLabels,
  isFrosted,
  glowEnabled,
  trailing,
  onSelect,
}: FloatingNavTrackProps) {
  const trackRef = useRef<HTMLDivElement>(null);
  const selectionRef = useRef<HTMLSpanElement>(null);
  const tabRefs = useRef(new Map<string, HTMLElement>());
  const previousId = useRef<NavItem['id'] | null>(null);

  // Writes straight to the DOM, so label animations do not re-render on each frame.
  useLayoutEffect(() => {
    const selection = selectionRef.current;
    if (!selection) return;

    const place = () => {
      const tab = selectedId ? tabRefs.current.get(selectedId) : undefined;
      if (!tab) {
        selection.style.opacity = '0';
        return;
      }
      selection.style.opacity = '1';
      selection.style.width = `${tab.offsetWidth}px`;
      selection.style.transform = `translateX(${tab.offsetLeft}px)`;
    };

    let timer: number | undefined;
    if (previousId.current && selectedId && previousId.current !== selectedId) {
      selection.dataset.animate = 'true';
      timer = window.setTimeout(() => {
        delete selection.dataset.animate;
      }, SELECTION_ANIMATION_MS);
    }
    previousId.current = selectedId;
    place();

    const observer = new ResizeObserver(place);
    tabRefs.current.forEach((tab) => observer.observe(tab));
    return () => {
      observer.disconnect();
      window.clearTimeout(timer);
    };
  }, [selectedId, items]);

  return (
    <div
      ref={trackRef}
      data-frosted={isFrosted}
      className="nav-track relative inline-flex items-center h-12 p-1 rounded-full ring-1 ring-inset ring-white/[0.08]"
    >
      <span
        ref={selectionRef}
        data-glow={glowEnabled}
        aria-hidden="true"
        className="nav-selection absolute left-0 top-1 bottom-1 rounded-full opacity-0"
      />
      {items.map((item) => {
        const selected = item.id === selectedId;
        const Icon = item.icon;
        const className = `relative flex items-center h-10 rounded-full transition-[padding,color] duration-300 motion-reduce:transition-none ${
          showsLabels ? 'pl-2.5 pr-3.5' : 'px-1.5'
        } ${selected ? 'text-white' : 'text-neutral-400 hover:text-white hover:bg-white/[0.06]'}`;
        const content = (
          <>
            <span className="w-7 h-7 flex items-center justify-center flex-shrink-0">
              <Icon size={20} filled={selected} />
            </span>
            <span className="nav-label" data-open={showsLabels}>
              <span className={`text-[13px] ${selected ? 'font-semibold' : 'font-medium'}`}>
                <span className="pl-1.5">{item.label}</span>
              </span>
            </span>
          </>
        );
        const setRef = (el: HTMLElement | null) => {
          if (el) tabRefs.current.set(item.id, el);
          else tabRefs.current.delete(item.id);
        };
        const shared = {
          ref: setRef,
          className,
          title: showsLabels ? undefined : item.label,
          'aria-label': item.label,
        };
        return onSelect ? (
          <button key={item.id} type="button" {...shared} aria-pressed={selected} onClick={() => onSelect(item)}>
            {content}
          </button>
        ) : (
          <Link key={item.id} to={item.to} {...shared} aria-current={selected ? 'page' : undefined}>
            {content}
          </Link>
        );
      })}
      {trailing}
    </div>
  );
}
