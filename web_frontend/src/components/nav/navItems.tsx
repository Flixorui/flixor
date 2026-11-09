import { useMemo } from 'react';
import { useSettings } from '@/state/settings';
import {
  NavBookmarkIcon,
  NavFlameIcon,
  NavHomeIcon,
  NavLibraryIcon,
  NavSearchIcon,
} from '@/components/nav/NavIcons';

export type NavItem = {
  id: 'home' | 'library' | 'myList' | 'newPopular' | 'search';
  to: string;
  label: string;
  /** Shorter label for the phone tab bar. */
  shortLabel?: string;
  icon: (props: { size?: number; filled?: boolean }) => JSX.Element;
};

export const NAV_ITEMS: NavItem[] = [
  { id: 'home', to: '/', label: 'Home', icon: NavHomeIcon },
  { id: 'library', to: '/library', label: 'Library', icon: NavLibraryIcon },
  { id: 'myList', to: '/my-list', label: 'My List', icon: NavBookmarkIcon },
  { id: 'newPopular', to: '/new-popular', label: 'New & Popular', shortLabel: 'New', icon: NavFlameIcon },
  { id: 'search', to: '/search', label: 'Search', icon: NavSearchIcon },
];

export function isNavItemActive(item: NavItem, pathname: string): boolean {
  return item.to === '/' ? pathname === '/' : pathname.startsWith(item.to);
}

/** The tabs this profile shows, per Settings > Navigation and Library Only Mode. */
export function useVisibleNavItems(): NavItem[] {
  const { discoveryDisabled, showNewPopularTab } = useSettings();
  const hideNewPopular = discoveryDisabled === true || showNewPopularTab === false;
  return useMemo(
    () => NAV_ITEMS.filter((item) => item.id !== 'newPopular' || !hideNewPopular),
    [hideNewPopular]
  );
}
