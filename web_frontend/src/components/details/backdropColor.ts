/** Dominant artwork color for tinting the details page, matching the macOS app. */

export interface BackdropRGB {
  red: number;
  green: number;
  blue: number;
}

/** The app's page background (#0b0b0b), which the tint is mixed against. */
export const PAGE_BACKGROUND: BackdropRGB = { red: 11 / 255, green: 11 / 255, blue: 11 / 255 };

const TINT_FRACTION = 0.42;
const MAX_LUMINANCE = 0.13;

/** Mostly the page background, moved toward `color`, and kept dark enough for white text. */
export function pageTint(color: BackdropRGB, background: BackdropRGB = PAGE_BACKGROUND): BackdropRGB {
  let tint: BackdropRGB = {
    red: background.red + (color.red - background.red) * TINT_FRACTION,
    green: background.green + (color.green - background.green) * TINT_FRACTION,
    blue: background.blue + (color.blue - background.blue) * TINT_FRACTION,
  };
  const luminance = 0.2126 * tint.red + 0.7152 * tint.green + 0.0722 * tint.blue;
  if (luminance > MAX_LUMINANCE) {
    const scale = MAX_LUMINANCE / luminance;
    tint = { red: tint.red * scale, green: tint.green * scale, blue: tint.blue * scale };
  }
  return tint;
}

export function rgbaString(color: BackdropRGB, alpha: number): string {
  const channel = (value: number) => Math.round(Math.min(Math.max(value, 0), 1) * 255);
  return `rgba(${channel(color.red)}, ${channel(color.green)}, ${channel(color.blue)}, ${alpha})`;
}

/**
 * Groups pixels into color buckets, counting vivid pixels for more, and averages
 * the winning bucket. Null when the image is almost entirely black or white.
 */
export function dominantColorOfPixels(pixels: ArrayLike<number>): BackdropRGB | null {
  const buckets = new Map<number, { weight: number; red: number; green: number; blue: number }>();

  for (let offset = 0; offset + 2 < pixels.length; offset += 4) {
    const r = pixels[offset];
    const g = pixels[offset + 1];
    const b = pixels[offset + 2];
    const high = Math.max(r, g, b);
    if (high <= 24) continue;
    const saturation = (high - Math.min(r, g, b)) / high;
    if (high > 240 && saturation < 0.1) continue;

    const weight = 0.25 + saturation;
    const key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
    const bucket = buckets.get(key) ?? { weight: 0, red: 0, green: 0, blue: 0 };
    bucket.weight += weight;
    bucket.red += r * weight;
    bucket.green += g * weight;
    bucket.blue += b * weight;
    buckets.set(key, bucket);
  }

  let best: { weight: number; red: number; green: number; blue: number } | undefined;
  for (const bucket of buckets.values()) {
    if (!best || bucket.weight > best.weight) best = bucket;
  }
  if (!best) return null;
  return {
    red: best.red / best.weight / 255,
    green: best.green / best.weight / 255,
    blue: best.blue / best.weight / 255,
  };
}

const cache = new Map<string, Promise<BackdropRGB | null>>();

/** Null when the image can't be loaded, or the server sends no CORS headers for it. */
export function dominantColor(url: string): Promise<BackdropRGB | null> {
  const cached = cache.get(url);
  if (cached) return cached;

  const result = new Promise<BackdropRGB | null>((resolve) => {
    const image = new Image();
    image.crossOrigin = 'anonymous';
    image.decoding = 'async';
    image.onerror = () => resolve(null);
    image.onload = () => {
      try {
        const canvas = document.createElement('canvas');
        canvas.width = 48;
        canvas.height = 27;
        const context = canvas.getContext('2d', { willReadFrequently: true });
        if (!context) {
          resolve(null);
          return;
        }
        context.drawImage(image, 0, 0, canvas.width, canvas.height);
        resolve(dominantColorOfPixels(context.getImageData(0, 0, canvas.width, canvas.height).data));
      } catch {
        resolve(null);
      }
    };
    image.src = url;
  });
  cache.set(url, result);
  return result;
}
