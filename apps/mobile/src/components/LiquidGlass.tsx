/**
 * Glass background for pills, round buttons and menus. On iOS 26 it is Apple's Liquid Glass
 * (what the Netflix app uses); elsewhere a light blur with a faint tint, a bright hairline
 * edge and a soft highlight across the top stands in for it.
 */

import React from 'react';
import { StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import ConditionalBlurView from './ConditionalBlurView';

let GlassViewComp: React.ComponentType<any> | null = null;
let available = false;
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const glass = require('expo-glass-effect');
  GlassViewComp = glass.GlassView;
  available = typeof glass.isLiquidGlassAvailable === 'function' ? glass.isLiquidGlassAvailable() : false;
} catch {
  available = false;
}

export const liquidGlassAvailable = available;

/** Fills its parent; put it first inside a view that has the shape's size. */
export default function LiquidGlass({
  radius,
  interactive,
  tint,
  fallbackIntensity = 14,
}: {
  radius: number;
  interactive?: boolean;
  /** Tints the glass; menus use a dark tint so their text reads over busy artwork. */
  tint?: string;
  /** Blur strength of the stand-in on systems without Liquid Glass. */
  fallbackIntensity?: number;
}) {
  if (available && GlassViewComp) {
    return (
      <View pointerEvents={interactive ? 'box-none' : 'none'} style={StyleSheet.absoluteFillObject}>
        <GlassViewComp
          glassEffectStyle="regular"
          isInteractive={!!interactive}
          tintColor={tint}
          style={[StyleSheet.absoluteFillObject, { borderRadius: radius }]}
        />
      </View>
    );
  }
  return (
    <View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { borderRadius: radius, overflow: 'hidden' }]}>
      <ConditionalBlurView intensity={fallbackIntensity} tint="dark" style={StyleSheet.absoluteFillObject} />
      <LinearGradient
        colors={['rgba(255,255,255,0.16)', 'rgba(255,255,255,0)']}
        start={{ x: 0.5, y: 0 }}
        end={{ x: 0.5, y: 0.6 }}
        style={StyleSheet.absoluteFillObject}
      />
      <View style={[StyleSheet.absoluteFillObject, styles.fallbackFill, { borderRadius: radius }]} />
    </View>
  );
}

const styles = StyleSheet.create({
  fallbackFill: {
    backgroundColor: 'rgba(255,255,255,0.10)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.28)',
  },
});
