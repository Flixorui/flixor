import { useEffect, useState, useRef } from 'react';
import { extractUltraBlurColors, hexToRgba, DEFAULT_ULTRABLUR_COLORS, UltraBlurColors } from '@/services/colorExtractor';

type UltraBlurBackgroundProps = {
  imageUrl?: string;
  className?: string;
  children?: React.ReactNode;
};

/**
 * UltraBlur dynamic background component
 * Extracts colors from hero image and creates gradient overlays
 * Matches Mobile/MacOS implementation
 */
export default function UltraBlurBackground({
  imageUrl,
  className = '',
  children
}: UltraBlurBackgroundProps) {
  const [colors, setColors] = useState<UltraBlurColors>(DEFAULT_ULTRABLUR_COLORS);
  const [isAnimating, setIsAnimating] = useState(false);
  const lastImageRef = useRef<string | null>(null);
  const throttleRef = useRef<number>(0);

  useEffect(() => {
    if (!imageUrl) return;
    if (imageUrl === lastImageRef.current) return;

    // Throttle color extraction
    const now = Date.now();
    if (now - throttleRef.current < 300) return; // 300ms throttle for responsive carousel

    const extractColors = async () => {
      try {
        const extracted = await extractUltraBlurColors(imageUrl);
        if (extracted) {
          setIsAnimating(true);
          // Small delay to trigger animation
          setTimeout(() => {
            setColors(extracted);
            lastImageRef.current = imageUrl;
            throttleRef.current = now;
          }, 50);
          // Reset animation state after transition
          setTimeout(() => setIsAnimating(false), 850);
        }
      } catch (e) {
        console.error('[UltraBlur] Error:', e);
      }
    };

    extractColors();
  }, [imageUrl]);

  return (
    <div className={`relative ${className}`}>
      {/* Base dark gradient - fixed to cover entire viewport including nav */}
      <div
        className="fixed inset-0 pointer-events-none transition-opacity duration-500"
        style={{
          background: 'linear-gradient(to bottom, #1a1a1a 0%, #181818 50%, #151515 100%)'
        }}
      />

      {/* Bottom-left color gradient - fixed to cover entire viewport */}
      <div
        className={`fixed inset-0 pointer-events-none transition-all duration-800 ease-in-out ${
          isAnimating ? 'opacity-0' : 'opacity-100'
        }`}
        style={{
          background: `linear-gradient(135deg, ${hexToRgba(colors.bottomLeft, 0.55)} 0%, ${hexToRgba(colors.bottomLeft, 0.25)} 35%, transparent 65%)`
        }}
      />

      {/* Top-right color gradient - fixed to cover entire viewport */}
      <div
        className={`fixed inset-0 pointer-events-none transition-all duration-800 ease-in-out ${
          isAnimating ? 'opacity-0' : 'opacity-100'
        }`}
        style={{
          background: `linear-gradient(315deg, ${hexToRgba(colors.topRight, 0.50)} 0%, ${hexToRgba(colors.topRight, 0.20)} 35%, transparent 65%)`
        }}
      />

      {/* Content */}
      <div className="relative z-10">
        {children}
      </div>
    </div>
  );
}

/**
 * Hook version for more flexible integration
 */
export function useUltraBlurColors(imageUrl?: string): UltraBlurColors {
  const [colors, setColors] = useState<UltraBlurColors>(DEFAULT_ULTRABLUR_COLORS);
  const lastImageRef = useRef<string | null>(null);

  useEffect(() => {
    if (!imageUrl || imageUrl === lastImageRef.current) return;

    const extractColors = async () => {
      try {
        const extracted = await extractUltraBlurColors(imageUrl);
        if (extracted) {
          setColors(extracted);
          lastImageRef.current = imageUrl;
        }
      } catch (e) {
        console.error('[useUltraBlurColors] Error:', e);
      }
    };

    extractColors();
  }, [imageUrl]);

  return colors;
}

/**
 * Gradient overlay styles generator
 */
export function getUltraBlurGradientStyles(colors: UltraBlurColors) {
  return {
    bottomLeft: {
      background: `linear-gradient(135deg, ${hexToRgba(colors.bottomLeft, 0.55)} 0%, ${hexToRgba(colors.bottomLeft, 0.25)} 35%, transparent 65%)`
    },
    topRight: {
      background: `linear-gradient(315deg, ${hexToRgba(colors.topRight, 0.50)} 0%, ${hexToRgba(colors.topRight, 0.20)} 35%, transparent 65%)`
    }
  };
}
