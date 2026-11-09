/**
 * Accent palettes and the resolved theme. macOS reference:
 * apps/macos/FlixorMac/Extensions/FlixorTheme.swift
 *
 * Read the theme in components with hooks/useTheme. Use `resolveTheme` directly
 * only outside React.
 */

import type { AccentPalette } from './SettingsData';

export type { AccentPalette };

export const DEFAULT_ACCENT_PALETTE: AccentPalette = 'crimson';

export interface AccentPaletteColors {
  displayName: string;
  /** Base accent. Mid-to-deep shades so white text on an accent fill stays readable. */
  color: string;
  /** Deeper shade for pressed fills. */
  strong: string;
  /** Lighter shade for accent text and icons on dark backgrounds. */
  bright: string;
}

export const ACCENT_PALETTES: Record<AccentPalette, AccentPaletteColors> = {
  crimson: { displayName: 'Flixor Red', color: '#E50914', strong: '#B20710', bright: '#FF3B47' },
  orange: { displayName: 'Orange', color: '#EA580C', strong: '#C2410C', bright: '#FB923C' },
  amber: { displayName: 'Amber', color: '#D97706', strong: '#B45309', bright: '#FBBF24' },
  emerald: { displayName: 'Emerald', color: '#059669', strong: '#047857', bright: '#34D399' },
  teal: { displayName: 'Teal', color: '#0D9488', strong: '#0F766E', bright: '#2DD4BF' },
  sky: { displayName: 'Sky', color: '#0284C7', strong: '#0369A1', bright: '#38BDF8' },
  blue: { displayName: 'Blue', color: '#2563EB', strong: '#1D4ED8', bright: '#60A5FA' },
  violet: { displayName: 'Violet', color: '#7C3AED', strong: '#6D28D9', bright: '#A78BFA' },
  pink: { displayName: 'Pink', color: '#DB2777', strong: '#BE185D', bright: '#F472B6' },
  mono: { displayName: 'Graphite', color: '#8E8E93', strong: '#636366', bright: '#D1D1D6' },
};

/** Palette ids in display order. */
export const ACCENT_PALETTE_IDS = Object.keys(ACCENT_PALETTES) as AccentPalette[];

export interface FlixorTheme {
  palette: AccentPalette;
  pureBlack: boolean;

  /** Interactive accent: selection, progress, toggles, focus. */
  accent: string;
  /** Pressed accent fill. */
  accentStrong: string;
  /** Accent for text and small icons on dark backgrounds. */
  accentBright: string;
  /** Tinted background for selected chips and rows. */
  accentSoft: string;
  /** Text and icons placed on an accent fill. */
  onAccent: string;
  focusRing: string;
  /** Brand red for logos. Does not follow the accent. */
  brand: string;
  /**
   * The accent the user picked, or undefined if they never picked one. Surfaces whose
   * original color was not red use `theme.chosenAccent ?? original`, so nothing changes
   * for people who stay on the default.
   */
  chosenAccent?: string;
  /** `accentBright` of the picked accent, for text and small icons. */
  chosenAccentBright?: string;

  background: string;
  backgroundSecondary: string;
  /** Behind tab scenes. */
  shellBackground: string;
  /** Behind settings screens. */
  settingsBackground: string;
  /** Tint layered over the frosted top bar and settings header. */
  glassTint: string;
  /** Cards, rows and grouped boxes resting on the background. */
  surface: string;
  /** Menus and sheets. */
  surfaceElevated: string;
  /** Translucent fill for cards drawn over artwork or gradients. */
  surfaceOverlay: string;
  pressedFill: string;

  separator: string;
  separatorStrong: string;

  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  textDisabled: string;

  success: string;
  warning: string;
  danger: string;
  info: string;
}

/** Appends an alpha channel to a #RRGGBB colour. */
export function withAlpha(hex: string, opacity: number): string {
  const alpha = Math.round(Math.min(1, Math.max(0, opacity)) * 255)
    .toString(16)
    .padStart(2, '0');
  return `${hex}${alpha}`;
}

const white = (opacity: number) => `rgba(255,255,255,${opacity})`;

function buildTheme(palette: AccentPalette, pureBlack: boolean, chosen: boolean): FlixorTheme {
  const colors = ACCENT_PALETTES[palette];
  return {
    palette,
    pureBlack,

    accent: colors.color,
    accentStrong: colors.strong,
    accentBright: colors.bright,
    accentSoft: withAlpha(colors.color, 0.15),
    onAccent: '#FFFFFF',
    focusRing: colors.bright,
    brand: '#E50914',
    chosenAccent: chosen ? colors.color : undefined,
    chosenAccentBright: chosen ? colors.bright : undefined,

    background: pureBlack ? '#000000' : '#0A0A0A',
    backgroundSecondary: pureBlack ? '#000000' : '#0F0F10',
    shellBackground: pureBlack ? '#000000' : '#1b0a10',
    settingsBackground: pureBlack ? '#000000' : '#0b0b0d',
    glassTint: pureBlack
      ? 'rgba(0,0,0,0.35)'
      : chosen
        ? withAlpha(colors.color, 0.12)
        : 'rgba(27,10,16,0.12)',
    surface: pureBlack ? '#0A0A0A' : '#141414',
    surfaceElevated: pureBlack ? '#141414' : '#1C1C1E',
    surfaceOverlay: white(0.06),
    pressedFill: white(0.12),

    separator: white(pureBlack ? 0.1 : 0.08),
    separatorStrong: white(pureBlack ? 0.18 : 0.14),

    textPrimary: '#FFFFFF',
    textSecondary: white(0.7),
    textTertiary: white(0.5),
    textDisabled: white(0.38),

    success: '#30D158',
    warning: '#FFC857',
    danger: '#FF453A',
    info: '#0A84FF',
  };
}

const themeCache = new Map<string, FlixorTheme>();

/**
 * Resolves the theme for the given settings. Returns the same object for the same
 * inputs, so it is safe as a React dependency. Unknown palettes fall back to the default
 * and count as not chosen.
 */
export function resolveTheme(palette: string | undefined, pureBlack: boolean | undefined): FlixorTheme {
  const id: AccentPalette =
    palette && palette in ACCENT_PALETTES ? (palette as AccentPalette) : DEFAULT_ACCENT_PALETTE;
  const black = pureBlack === true;
  const chosen = id === palette;
  const key = `${id}:${black}:${chosen}`;
  let theme = themeCache.get(key);
  if (!theme) {
    theme = buildTheme(id, black, chosen);
    themeCache.set(key, theme);
  }
  return theme;
}
