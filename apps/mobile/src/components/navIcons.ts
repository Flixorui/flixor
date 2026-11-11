/**
 * Tab bar icons, the same set as the macOS app (Assets.xcassets/NavIcons: Phosphor, with
 * New & Popular from Heroicons). Downloads uses the app's own icon, the one in the Home
 * header, so both places match. Each has an outline version and a filled one for the
 * selected tab. Rendered to PNG at 1x/2x/3x; tinted by the tab bar, so only the shape counts.
 */

import type { ImageSourcePropType } from 'react-native';

export type NavIconPair = { outline: ImageSourcePropType; fill: ImageSourcePropType };

export const NAV_ICONS = {
  home: { outline: require('../../assets/nav/nav-home.png'), fill: require('../../assets/nav/nav-home-fill.png') },
  myList: { outline: require('../../assets/nav/nav-mylist.png'), fill: require('../../assets/nav/nav-mylist-fill.png') },
  newHot: { outline: require('../../assets/nav/nav-newpopular.png'), fill: require('../../assets/nav/nav-newpopular-fill.png') },
  // The Home header's downloads icon (it has no filled version, so it serves both states)
  downloads: { outline: require('../../assets/nav/nav-downloads-header.png'), fill: require('../../assets/nav/nav-downloads-header.png') },
  search: { outline: require('../../assets/nav/nav-search.png'), fill: require('../../assets/nav/nav-search-fill.png') },
  settings: { outline: require('../../assets/nav/nav-settings.png'), fill: require('../../assets/nav/nav-settings-fill.png') },
} satisfies Record<string, NavIconPair>;

/** The icon pair for a tab route. */
export function navIconForRoute(route: string): NavIconPair {
  switch (route) {
    case 'SearchTab': return NAV_ICONS.search;
    case 'NewHotTab': return NAV_ICONS.newHot;
    case 'MyTab': return NAV_ICONS.myList;
    case 'DownloadsTab': return NAV_ICONS.downloads;
    case 'SettingsTab': return NAV_ICONS.settings;
    default: return NAV_ICONS.home;
  }
}
