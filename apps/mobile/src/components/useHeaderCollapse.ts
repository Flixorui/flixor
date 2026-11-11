/**
 * Netflix's pill hide / show on scroll, shared by Home's header and the Shows / Movies page.
 */

import React from 'react';
import { Animated, Easing } from 'react-native';

/*
 * Pill-row motion, measured frame by frame from the Netflix iOS app (Nov 2026):
 * - Hide after a small downward scroll: pills scale to 0.9, rise 6 pt and fade in ~180 ms,
 *   while the frosted band shrinks to the title row.
 * - A small nudge up is ignored; a deliberate upward scroll (or reaching the top) brings
 *   them back in ~250 ms, anywhere on the page.
 * - The title row shrinks ~6.5% while the pills are hidden (title toward the left edge,
 *   icons toward the right edge, lifted ~1.3 pt): 340 ms out, 400 ms back with a soft settle.
 * Time-based, not tied to the scroll position, so it plays the same at any scroll speed.
 */
const HIDE_AFTER = 8; // pt of downward scroll
const SHOW_AFTER = 60; // pt of upward scroll
const TOP_ZONE = 8; // pt from the top where the pills always show
const PILLS_HIDE = { duration: 180, easing: Easing.bezier(0.4, 0, 0.2, 1) };
// Reveal: Netflix's measured curve (467 ms, gentle start, long glide in)
const PILLS_SHOW = { duration: 467, easing: Easing.bezier(0.2, 0, 0.2, 1) };
const TITLE_HIDE = { duration: 340, easing: Easing.bezier(0.33, 0, 0.2, 1) };
const TITLE_SHOW = { duration: 467, easing: Easing.bezier(0.2, 0, 0.2, 1) };

/**
 * Lowest opacity of hidden pills. Not 0: iOS stops drawing Liquid Glass inside a view whose
 * ancestor reaches zero alpha and doesn't bring it back when the view fades in again, so
 * the pills keep a trace of opacity that is invisible but keeps the glass alive.
 */
export const HIDDEN_PILL_OPACITY = 0.02;

/**
 * Returns three values that go from 0 (pills shown) to 1 (hidden): `pillsP` and `titleP`
 * (native driver, for opacity and transforms) and `bandP` (JS driver, for the frosted
 * band's height). `pillsHidden` turns off touches on the hidden pills.
 */
export function useHeaderCollapse({
  scrollY,
  enabled,
  showOnUpwardScroll = true,
  hideAfter = HIDE_AFTER,
  showTiming = PILLS_SHOW,
  hideTiming = PILLS_HIDE,
}: {
  scrollY?: Animated.Value;
  enabled: boolean;
  /** Off for the compact style: the pills come back only at the top. */
  showOnUpwardScroll?: boolean;
  /** Downward scroll (pt) before the pills hide. */
  hideAfter?: number;
  /** How the pills come back (Home: 250 ms; the Shows / Movies pill slides back slower). */
  showTiming?: { duration: number; easing: (t: number) => number };
  /** How the pills hide (Home: 180 ms; New & Hot's pill row rises over ~430 ms). */
  hideTiming?: { duration: number; easing: (t: number) => number };
}) {
  const pillsP = React.useRef(new Animated.Value(0)).current;
  const titleP = React.useRef(new Animated.Value(0)).current;
  const bandP = React.useRef(new Animated.Value(0)).current;
  const [pillsHidden, setPillsHidden] = React.useState(false);
  const hiddenRef = React.useRef(false);

  const setHidden = React.useCallback((hide: boolean) => {
    if (hiddenRef.current === hide) return;
    hiddenRef.current = hide;
    setPillsHidden(hide);
    const to = hide ? 1 : 0;
    const pills = hide ? hideTiming : showTiming;
    const title = hide ? TITLE_HIDE : TITLE_SHOW;
    Animated.parallel([
      Animated.timing(pillsP, { toValue: to, ...pills, useNativeDriver: true }),
      Animated.timing(titleP, { toValue: to, ...title, useNativeDriver: true }),
      Animated.timing(bandP, { toValue: to, ...pills, useNativeDriver: false }),
    ]).start();
  }, [pillsP, titleP, bandP, showTiming, hideTiming]);

  React.useEffect(() => {
    if (!enabled || !scrollY) {
      setHidden(false);
      return;
    }
    let lastY = 0;
    let down = 0;
    let up = 0;
    const id = scrollY.addListener(({ value: y }) => {
      const delta = y - lastY;
      lastY = y;
      if (y <= TOP_ZONE) {
        down = 0;
        up = 0;
        setHidden(false);
        return;
      }
      if (delta > 0) {
        down += delta;
        up = 0;
        if (down >= hideAfter) setHidden(true);
      } else if (delta < 0) {
        up -= delta;
        down = 0;
        if (showOnUpwardScroll && up >= SHOW_AFTER) setHidden(false);
      }
    });
    return () => scrollY.removeListener(id);
  }, [enabled, scrollY, showOnUpwardScroll, hideAfter, setHidden]);

  /** Brings the header back now (e.g. after jumping to a section). */
  const show = React.useCallback(() => setHidden(false), [setHidden]);

  return { pillsP, titleP, bandP, pillsHidden, show };
}
