import { loadSettings, useSettings, type CardTitleMode, type ResolvedSettings } from '@/state/settings';
import type { CardSurface } from './cardTypes';

const POSTER_WIDTH = { small: 130, medium: 160, large: 190, xlarge: 220 } as const;
const LANDSCAPE_WIDTH = { small: 320, medium: 420, large: 480, xlarge: 540 } as const;
const CORNER_RADIUS = { none: 0, small: 6, medium: 12, large: 20 } as const;

export function cardCornerRadius(settings: ResolvedSettings): number {
  if (typeof settings.posterBorderRadius === 'number') return settings.posterBorderRadius;
  if (settings.cardCornerRadius) return CORNER_RADIUS[settings.cardCornerRadius] ?? 12;
  return 12;
}

// One parse per settings change, not per card.
let storedFor: { settings: ResolvedSettings; mode?: CardTitleMode } | null = null;

function storedTitleMode(settings: ResolvedSettings) {
  if (storedFor?.settings !== settings) storedFor = { settings, mode: loadSettings().cardTitleMode };
  return storedFor.mode;
}

/**
 * `cardTitleMode` wins once the user has set it. Before that, the older Show Titles
 * toggle applies, so anyone who turned titles off keeps them off.
 */
export function cardTitleMode(settings: ResolvedSettings, surface: CardSurface): CardTitleMode {
  if (surface === 'library') return settings.showLibraryTitles === false ? 'never' : 'always';
  const stored = storedTitleMode(settings);
  if (stored) return stored;
  if (settings.showPosterTitles === false) return 'never';
  return settings.showPosterTitles === true ? 'always' : settings.cardTitleMode;
}

export interface CardStyle {
  posterWidth: number;
  landscapeWidth: number;
  radius: number;
  titleMode: CardTitleMode;
  showRatingBadges: boolean;
}

export function useCardStyle(surface: CardSurface = 'row'): CardStyle {
  const settings = useSettings();
  const size = settings.posterSize || 'medium';
  return {
    posterWidth: POSTER_WIDTH[size] ?? POSTER_WIDTH.medium,
    landscapeWidth: LANDSCAPE_WIDTH[size] ?? LANDSCAPE_WIDTH.medium,
    radius: cardCornerRadius(settings),
    titleMode: cardTitleMode(settings, surface),
    showRatingBadges: settings.cardShowRatingBadges,
  };
}
