/**
 * Netflix's header motion (New & Hot, My List), measured at 60 fps from the Netflix app:
 * the header does not follow the finger. A short scroll starts a timed animation that runs
 * on its own curve, in either direction:
 * - hide after ~8 pt of scrolling down: 400 ms, cubic-bezier(0.2, 0, 0.3, 1)
 * - reveal after ~15 pt of scrolling up (anywhere on the page) or near the top:
 *   467 ms, cubic-bezier(0.2, 0, 0.2, 1)
 * (Measured: hiding, the header moves ~12 px/frame while the content moves 5; revealing, it
 * starts ~3 frames after the content and keeps its own pace.)
 * Returns a value from 0 (shown) to `distance` (hidden), driven natively.
 */

import { useCallback, useRef } from 'react';
import { Animated, Easing } from 'react-native';

const HIDE_AFTER = 8;
const SHOW_AFTER = 15;
export const HEADER_HIDE = { duration: 400, easing: Easing.bezier(0.2, 0, 0.3, 1) };
export const HEADER_SHOW = { duration: 467, easing: Easing.bezier(0.2, 0, 0.2, 1) };

export function useScrollLinkedHeader(distance: number) {
  const value = useRef(new Animated.Value(0)).current;
  const hidden = useRef(false);
  const lastY = useRef(0);
  const down = useRef(0);
  const up = useRef(0);

  const animateTo = useCallback((hide: boolean) => {
    if (hidden.current === hide) return;
    hidden.current = hide;
    Animated.timing(value, {
      toValue: hide ? distance : 0,
      ...(hide ? HEADER_HIDE : HEADER_SHOW),
      useNativeDriver: true,
    }).start();
  }, [distance, value]);

  /** Call with the scroll offset on every scroll event. */
  const onScrollY = useCallback((y: number) => {
    const delta = y - lastY.current;
    lastY.current = y;
    // Near the top the header always shows (it can't hide more than the page has scrolled)
    if (y <= distance / 2) {
      down.current = 0;
      up.current = 0;
      animateTo(false);
      return;
    }
    if (delta > 0) {
      down.current += delta;
      up.current = 0;
      if (down.current >= HIDE_AFTER) animateTo(true);
    } else if (delta < 0) {
      up.current -= delta;
      down.current = 0;
      if (up.current >= SHOW_AFTER) animateTo(false);
    }
  }, [animateTo, distance]);

  /** Brings the header back (e.g. after jumping to a section). */
  const show = useCallback(() => animateTo(false), [animateTo]);

  return { value, onScrollY, show };
}
