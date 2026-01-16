/**
 * Color extraction service for UltraBlur dynamic backgrounds
 * Extracts dominant colors from hero images for gradient overlays
 */

export type UltraBlurColors = {
  bottomLeft: string; // hex color
  topRight: string; // hex color
};

// In-memory cache for extracted colors
const colorCache = new Map<string, UltraBlurColors>();

/**
 * Convert RGB values to hex string
 */
function rgbToHex(r: number, g: number, b: number): string {
  return ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
}

/**
 * Get average color from a region of pixel data
 */
function getRegionColor(
  imageData: ImageData,
  startX: number,
  startY: number,
  width: number,
  height: number,
  canvasWidth: number
): { r: number; g: number; b: number } {
  let r = 0, g = 0, b = 0, count = 0;

  for (let y = startY; y < startY + height && y < imageData.height; y++) {
    for (let x = startX; x < startX + width && x < canvasWidth; x++) {
      const idx = (y * canvasWidth + x) * 4;
      r += imageData.data[idx];
      g += imageData.data[idx + 1];
      b += imageData.data[idx + 2];
      count++;
    }
  }

  return {
    r: Math.round(r / count),
    g: Math.round(g / count),
    b: Math.round(b / count)
  };
}

/**
 * Adjust color saturation and brightness for better gradient effect
 */
function enhanceColor(r: number, g: number, b: number): { r: number; g: number; b: number } {
  // Convert to HSL
  const rNorm = r / 255;
  const gNorm = g / 255;
  const bNorm = b / 255;

  const max = Math.max(rNorm, gNorm, bNorm);
  const min = Math.min(rNorm, gNorm, bNorm);
  const l = (max + min) / 2;

  if (max === min) {
    // Achromatic - return slightly tinted version
    return { r: Math.min(255, r + 20), g: Math.min(255, g + 20), b: Math.min(255, b + 20) };
  }

  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);

  let h = 0;
  if (max === rNorm) {
    h = ((gNorm - bNorm) / d + (gNorm < bNorm ? 6 : 0)) / 6;
  } else if (max === gNorm) {
    h = ((bNorm - rNorm) / d + 2) / 6;
  } else {
    h = ((rNorm - gNorm) / d + 4) / 6;
  }

  // Enhance saturation slightly, reduce lightness for richer colors
  const newS = Math.min(1, s * 1.3);
  const newL = Math.max(0.15, Math.min(0.5, l * 0.8));

  // Convert back to RGB
  const hue2rgb = (p: number, q: number, t: number) => {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1/6) return p + (q - p) * 6 * t;
    if (t < 1/2) return q;
    if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
    return p;
  };

  const q = newL < 0.5 ? newL * (1 + newS) : newL + newS - newL * newS;
  const p = 2 * newL - q;

  return {
    r: Math.round(hue2rgb(p, q, h + 1/3) * 255),
    g: Math.round(hue2rgb(p, q, h) * 255),
    b: Math.round(hue2rgb(p, q, h - 1/3) * 255)
  };
}

/**
 * Extract UltraBlur colors from an image URL
 * Samples bottom-left and top-right regions for gradient effect
 */
export async function extractUltraBlurColors(imageUrl: string): Promise<UltraBlurColors | null> {
  // Check cache first
  const cacheKey = imageUrl;
  if (colorCache.has(cacheKey)) {
    return colorCache.get(cacheKey)!;
  }

  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';

    img.onload = () => {
      try {
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');

        if (!ctx) {
          resolve(null);
          return;
        }

        // Use smaller size for faster processing
        const maxSize = 100;
        const scale = Math.min(maxSize / img.width, maxSize / img.height);
        canvas.width = Math.round(img.width * scale);
        canvas.height = Math.round(img.height * scale);

        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

        const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);

        // Sample bottom-left region (25% of image)
        const bottomLeftRegion = getRegionColor(
          imageData,
          0,
          Math.round(canvas.height * 0.6),
          Math.round(canvas.width * 0.4),
          Math.round(canvas.height * 0.4),
          canvas.width
        );

        // Sample top-right region (25% of image)
        const topRightRegion = getRegionColor(
          imageData,
          Math.round(canvas.width * 0.6),
          0,
          Math.round(canvas.width * 0.4),
          Math.round(canvas.height * 0.4),
          canvas.width
        );

        // Enhance colors for better gradient effect
        const enhancedBottomLeft = enhanceColor(bottomLeftRegion.r, bottomLeftRegion.g, bottomLeftRegion.b);
        const enhancedTopRight = enhanceColor(topRightRegion.r, topRightRegion.g, topRightRegion.b);

        const colors: UltraBlurColors = {
          bottomLeft: rgbToHex(enhancedBottomLeft.r, enhancedBottomLeft.g, enhancedBottomLeft.b),
          topRight: rgbToHex(enhancedTopRight.r, enhancedTopRight.g, enhancedTopRight.b)
        };

        // Cache the result
        colorCache.set(cacheKey, colors);

        resolve(colors);
      } catch (e) {
        console.error('[ColorExtractor] Error extracting colors:', e);
        resolve(null);
      }
    };

    img.onerror = () => {
      console.error('[ColorExtractor] Failed to load image:', imageUrl);
      resolve(null);
    };

    // Set timeout for loading
    const timeout = setTimeout(() => {
      resolve(null);
    }, 5000);

    img.onload = function(this: HTMLImageElement) {
      clearTimeout(timeout);
      // Re-run the onload logic
      try {
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');

        if (!ctx) {
          resolve(null);
          return;
        }

        const maxSize = 100;
        const scale = Math.min(maxSize / this.width, maxSize / this.height);
        canvas.width = Math.round(this.width * scale);
        canvas.height = Math.round(this.height * scale);

        ctx.drawImage(this, 0, 0, canvas.width, canvas.height);

        const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);

        const bottomLeftRegion = getRegionColor(
          imageData,
          0,
          Math.round(canvas.height * 0.6),
          Math.round(canvas.width * 0.4),
          Math.round(canvas.height * 0.4),
          canvas.width
        );

        const topRightRegion = getRegionColor(
          imageData,
          Math.round(canvas.width * 0.6),
          0,
          Math.round(canvas.width * 0.4),
          Math.round(canvas.height * 0.4),
          canvas.width
        );

        const enhancedBottomLeft = enhanceColor(bottomLeftRegion.r, bottomLeftRegion.g, bottomLeftRegion.b);
        const enhancedTopRight = enhanceColor(topRightRegion.r, topRightRegion.g, topRightRegion.b);

        const colors: UltraBlurColors = {
          bottomLeft: rgbToHex(enhancedBottomLeft.r, enhancedBottomLeft.g, enhancedBottomLeft.b),
          topRight: rgbToHex(enhancedTopRight.r, enhancedTopRight.g, enhancedTopRight.b)
        };

        colorCache.set(cacheKey, colors);
        resolve(colors);
      } catch (e) {
        resolve(null);
      }
    };

    img.src = imageUrl;
  });
}

/**
 * Convert hex color to rgba string
 */
export function hexToRgba(hex: string, alpha: number): string {
  const cleanHex = hex.replace('#', '');
  const r = parseInt(cleanHex.substring(0, 2), 16);
  const g = parseInt(cleanHex.substring(2, 4), 16);
  const b = parseInt(cleanHex.substring(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/**
 * Clear the color cache (useful when navigating away)
 */
export function clearColorCache(): void {
  colorCache.clear();
}

/**
 * Default UltraBlur colors (used as fallback)
 */
export const DEFAULT_ULTRABLUR_COLORS: UltraBlurColors = {
  bottomLeft: '7a1612', // Deep red
  topRight: '144c54'    // Deep teal
};
