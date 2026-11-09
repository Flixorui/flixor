/**
 * The page tint for the details screen. macOS reference: Services/BackdropColorExtractor.swift
 *
 * Colors come from Plex UltraBlur for the artwork, which any connected server provides,
 * for TMDB art as well as its own. With no server (Stremio-only mode) the tint is the
 * theme background, the same result macOS gets when extraction fails.
 */

import { useEffect, useState } from 'react';
import { getFlixorCore } from '../../core';
import { isStremioOnlyMode } from '../../core/AppMode';
import { getUltraBlurColors, type PlexUltraBlurColors } from '../../core/HomeData';
import { type FlixorTheme } from '../../core/theme';

export interface BackdropRGB {
  red: number;
  green: number;
  blue: number;
}

const TINT_FRACTION = 0.42;
const MAX_LUMINANCE = 0.13;
const MAX_TINT_ALPHA = 0.86;

export function parseHexColor(value?: string | null): BackdropRGB | null {
  if (!value) return null;
  const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})/i.exec(value);
  if (!match) return null;
  return {
    red: parseInt(match[1], 16) / 255,
    green: parseInt(match[2], 16) / 255,
    blue: parseInt(match[3], 16) / 255,
  };
}

function toHex({ red, green, blue }: BackdropRGB): string {
  const channel = (value: number) =>
    Math.round(Math.min(1, Math.max(0, value)) * 255)
      .toString(16)
      .padStart(2, '0');
  return `#${channel(red)}${channel(green)}${channel(blue)}`;
}

/**
 * The most vivid UltraBlur corner, skipping near-black and near-white ones.
 * Null when every corner was skipped.
 */
export function dominantUltraBlurColor(colors?: PlexUltraBlurColors | null): BackdropRGB | null {
  if (!colors) return null;
  let best: BackdropRGB | null = null;
  let bestWeight = -1;
  for (const corner of [colors.topLeft, colors.topRight, colors.bottomLeft, colors.bottomRight]) {
    const rgb = parseHexColor(corner);
    if (!rgb) continue;
    const high = Math.max(rgb.red, rgb.green, rgb.blue);
    if (high <= 24 / 255) continue;
    const saturation = (high - Math.min(rgb.red, rgb.green, rgb.blue)) / high;
    if (high > 240 / 255 && saturation < 0.1) continue;
    const weight = 0.25 + saturation;
    if (weight > bestWeight) {
      best = rgb;
      bestWeight = weight;
    }
  }
  return best;
}

/** Mostly the theme background, moved toward the color, and kept dark enough for white text. */
export function pageTint(color: BackdropRGB, background: BackdropRGB): BackdropRGB {
  const tint = {
    red: background.red + (color.red - background.red) * TINT_FRACTION,
    green: background.green + (color.green - background.green) * TINT_FRACTION,
    blue: background.blue + (color.blue - background.blue) * TINT_FRACTION,
  };
  const luminance = 0.2126 * tint.red + 0.7152 * tint.green + 0.0722 * tint.blue;
  if (luminance <= MAX_LUMINANCE) return tint;
  const scale = MAX_LUMINANCE / luminance;
  return { red: tint.red * scale, green: tint.green * scale, blue: tint.blue * scale };
}

export interface DetailsBackdropTint {
  /** Opaque #RRGGBB page color. */
  tint: string;
  /** How much of the artwork the tint covers once the page has scrolled. */
  maxTintAlpha: number;
}

export function useDetailsBackdropTint(imageUrl: string | undefined, theme: FlixorTheme): DetailsBackdropTint {
  const [dominant, setDominant] = useState<BackdropRGB | null>(null);

  useEffect(() => {
    setDominant(null);
    if (!imageUrl || isStremioOnlyMode() || !getFlixorCore().isPlexServerConnected) return;
    let cancelled = false;
    getUltraBlurColors(imageUrl).then((colors) => {
      if (!cancelled) setDominant(dominantUltraBlurColor(colors));
    });
    return () => {
      cancelled = true;
    };
  }, [imageUrl]);

  if (theme.pureBlack) return { tint: '#000000', maxTintAlpha: 1 };
  const background = parseHexColor(theme.background);
  if (!dominant || !background) return { tint: theme.background, maxTintAlpha: MAX_TINT_ALPHA };
  return { tint: toHex(pageTint(dominant, background)), maxTintAlpha: MAX_TINT_ALPHA };
}
