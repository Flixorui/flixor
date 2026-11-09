import { getSettings, subscribeSettings, SETTINGS_DEFAULTS, type AccentPalette } from '@/state/settings';

/** Space-separated RGB channels, so Tailwind can apply alpha to the CSS variables. */
type AccentShades = { base: string; strong: string; bright: string };

export const ACCENT_PALETTES: Record<AccentPalette, AccentShades & { label: string }> = {
  crimson: { label: 'Flixor Red', base: '229 9 20', strong: '178 7 16', bright: '255 59 71' },
  orange: { label: 'Orange', base: '234 88 12', strong: '194 65 12', bright: '251 146 60' },
  amber: { label: 'Amber', base: '217 119 6', strong: '180 83 9', bright: '251 191 36' },
  emerald: { label: 'Emerald', base: '5 150 105', strong: '4 120 87', bright: '52 211 153' },
  teal: { label: 'Teal', base: '13 148 136', strong: '15 118 110', bright: '45 212 191' },
  sky: { label: 'Sky', base: '2 132 199', strong: '3 105 161', bright: '56 189 248' },
  blue: { label: 'Blue', base: '37 99 235', strong: '29 78 216', bright: '96 165 250' },
  violet: { label: 'Violet', base: '124 58 237', strong: '109 40 217', bright: '167 139 250' },
  pink: { label: 'Pink', base: '219 39 119', strong: '190 24 93', bright: '244 114 182' },
  mono: { label: 'Graphite', base: '142 142 147', strong: '99 99 102', bright: '209 209 214' },
};

function applyAccent() {
  // An unrecognized stored value falls back to the default palette.
  const shades =
    ACCENT_PALETTES[getSettings().accentPalette] ?? ACCENT_PALETTES[SETTINGS_DEFAULTS.accentPalette];
  const root = document.documentElement.style;
  root.setProperty('--accent-rgb', shades.base);
  root.setProperty('--accent-strong-rgb', shades.strong);
  root.setProperty('--accent-bright-rgb', shades.bright);
  document.documentElement.toggleAttribute('data-pure-black', getSettings().pureBlack === true);
}

/** Applies the saved accent and background now and keeps them in sync with the settings. */
export function initAccent() {
  applyAccent();
  subscribeSettings(applyAccent);
}
