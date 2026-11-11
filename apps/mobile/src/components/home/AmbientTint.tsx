/**
 * Page background tinted from the hero artwork, fading to near-black lower down, and
 * cross-fading (400 ms) when the hero changes. Netflix-style ambient colour.
 */

import React, { useEffect, useRef, useState } from 'react';
import { Animated, Easing, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

const BASE = '#0e0e10';

/** "7a1612" or "#7a1612" → a muted rgba that keeps white text readable on top. */
function tintColors(hex: string): [string, string, string] {
  const clean = hex.replace('#', '');
  const r = parseInt(clean.slice(0, 2), 16) || 0;
  const g = parseInt(clean.slice(2, 4), 16) || 0;
  const b = parseInt(clean.slice(4, 6), 16) || 0;
  // Darken towards the base so very bright artwork never washes out the header
  const mix = (c: number, base: number, k: number) => Math.round(c * k + base * (1 - k));
  const top = `rgb(${mix(r, 14, 0.55)},${mix(g, 14, 0.55)},${mix(b, 16, 0.55)})`;
  const mid = `rgb(${mix(r, 14, 0.28)},${mix(g, 14, 0.28)},${mix(b, 16, 0.28)})`;
  return [top, mid, BASE];
}

function Layer({ hex }: { hex: string }) {
  return (
    <LinearGradient
      colors={tintColors(hex)}
      locations={[0, 0.38, 0.75]}
      style={StyleSheet.absoluteFill}
    />
  );
}

export default function AmbientTint({ color }: { color: string }) {
  const [current, setCurrent] = useState(color);
  const [previous, setPrevious] = useState(color);
  const fade = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (color === current) return;
    setPrevious(current);
    setCurrent(color);
    fade.setValue(0);
    Animated.timing(fade, { toValue: 1, duration: 400, easing: Easing.out(Easing.quad), useNativeDriver: true }).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [color]);

  return (
    <View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: BASE }]}>
      <Layer hex={previous} />
      <Animated.View style={[StyleSheet.absoluteFill, { opacity: fade }]}>
        <Layer hex={current} />
      </Animated.View>
    </View>
  );
}
