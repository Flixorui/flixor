import { useEffect, useRef, useState } from 'react';
import { useSettings } from '@/state/settings';
import {
  PAGE_BACKGROUND,
  dominantColor,
  pageTint,
  rgbaString,
  type BackdropRGB,
} from './backdropColor';

/** How much of the art the tint covers once the page has scrolled. */
const MAX_TINT_ALPHA = 0.86;
/** The tint is fully in place after scrolling this share of the hero. */
const FADE_HERO_FRACTION = 0.75;
/** The hero's minimum height on large screens, as a share of the window. */
const HERO_WINDOW_FRACTION = 0.9;
const BLACK: BackdropRGB = { red: 0, green: 0, blue: 0 };

/**
 * The title's artwork stays fixed behind the whole page, and a tint taken from it
 * fades in as the page scrolls. Below the hero the tint is always full.
 */
export default function DetailsPersistentBackdrop({ imageUrl }: { imageUrl?: string }) {
  const { pureBlack } = useSettings();
  const [dominant, setDominant] = useState<BackdropRGB | null>(null);
  const tintRef = useRef<HTMLDivElement>(null);

  const maxAlpha = pureBlack ? 1 : MAX_TINT_ALPHA;
  const tint = pureBlack ? BLACK : dominant ? pageTint(dominant) : PAGE_BACKGROUND;

  useEffect(() => {
    setDominant(null);
    if (!imageUrl) return;
    let alive = true;
    dominantColor(imageUrl).then((color) => {
      if (alive) setDominant(color);
    });
    return () => { alive = false; };
  }, [imageUrl]);

  useEffect(() => {
    let frame = 0;
    const paint = () => {
      frame = 0;
      const element = tintRef.current;
      if (!element) return;
      const heroHeight = window.innerHeight * HERO_WINDOW_FRACTION;
      const progress = Math.min(Math.max(window.scrollY / (heroHeight * FADE_HERO_FRACTION), 0), 1);
      const topAlpha = progress * maxAlpha;
      const top = rgbaString(tint, topAlpha);
      // Scrolling past the hero leaves only the area below it on screen, so the
      // fade ends at the hero's height, measured from the top of the window.
      element.style.background =
        `linear-gradient(to bottom, ${top} 0%, ${top} 50%, ${rgbaString(tint, maxAlpha)} 90%)`;
    };
    const schedule = () => {
      if (!frame) frame = window.requestAnimationFrame(paint);
    };

    paint();
    window.addEventListener('scroll', schedule, { passive: true });
    window.addEventListener('resize', schedule);
    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      window.removeEventListener('scroll', schedule);
      window.removeEventListener('resize', schedule);
    };
  }, [tint.red, tint.green, tint.blue, maxAlpha]);

  return (
    <div className="pointer-events-none fixed inset-0 z-0" aria-hidden="true" style={{ backgroundColor: rgbaString(tint, 1) }}>
      {imageUrl && <img src={imageUrl} alt="" className="absolute inset-0 h-full w-full object-cover" />}

      {/* Readability: top for the navigation, left for the hero text */}
      <div className="absolute inset-0" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.6), rgba(0,0,0,0.1) 25%, transparent 50%)' }} />
      <div
        className="absolute inset-0"
        style={{ background: 'linear-gradient(to right, rgba(0,0,0,0.85), rgba(0,0,0,0.65) 25%, rgba(0,0,0,0.35) 50%, rgba(0,0,0,0.1) 75%, transparent)' }}
      />
      <div className="absolute inset-0" style={{ background: 'radial-gradient(ellipse at center, transparent 40%, rgba(0,0,0,0.4))' }} />

      <div ref={tintRef} className="absolute inset-0" />
    </div>
  );
}
