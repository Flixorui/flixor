/**
 * The frosted band behind a screen header (Home, Shows / Movies, New & Hot, My List).
 * On iOS 26 it is Apple's Liquid Glass (Expo GlassView), lightly tinted dark so white
 * titles stay readable; elsewhere a dark blur stands in for it.
 *
 * Fades that reveal it must stop at HEADER_GLASS_MIN_OPACITY, not 0: iOS stops drawing
 * Liquid Glass inside a view whose ancestor reaches zero alpha and doesn't recover.
 */

import React from 'react';
import { StyleSheet, View } from 'react-native';
import ConditionalBlurView from './ConditionalBlurView';
import LiquidGlass, { liquidGlassAvailable } from './LiquidGlass';

export const HEADER_GLASS_MIN_OPACITY = 0.02;

export default function HeaderGlass({
  fallbackIntensity = 45,
  tint = 'rgba(14,14,16,0.45)',
  fallbackTint = 'rgba(14,14,16,0.5)',
}: {
  fallbackIntensity?: number;
  /** Glass tint (Details passes its artwork colour). */
  tint?: string;
  /** Overlay over the blur on systems without Liquid Glass. */
  fallbackTint?: string;
}) {
  if (liquidGlassAvailable) {
    // 0.01, not 0: a zero radius is never sent to the native view (it equals the default),
    // and the glass then keeps iOS's own rounded shape, inset from the screen edges
    return <LiquidGlass radius={0.01} tint={tint} />;
  }
  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      <ConditionalBlurView intensity={fallbackIntensity} tint="dark" style={StyleSheet.absoluteFill} />
      <View style={[StyleSheet.absoluteFill, { backgroundColor: fallbackTint }]} />
    </View>
  );
}
