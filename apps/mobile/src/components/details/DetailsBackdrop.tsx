/**
 * The title's artwork stays fixed behind the page, and a tint taken from it fades
 * in as the page scrolls. macOS reference: Views/Details/DetailsPersistentBackdrop.swift
 *
 * On a portrait phone the art would be heavily cropped at full-window size, so it
 * covers the hero area and fades into the tint below it.
 */

import React, { useMemo, useState } from 'react';
import { StyleSheet, useWindowDimensions, View } from 'react-native';
import Animated, {
  Extrapolation,
  interpolate,
  runOnJS,
  useAnimatedReaction,
  useAnimatedStyle,
  type SharedValue,
} from 'react-native-reanimated';
import { LinearGradient } from 'expo-linear-gradient';
import FastImage from '@d11/react-native-fast-image';
import DetailsHeroTrailer from './DetailsHeroTrailer';
import { withAlpha } from '../../core/theme';

const FADE_HERO_FRACTION = 0.75;
/** The art runs slightly past the hero so the fade finishes under the content. */
const ART_HEIGHT_FACTOR = 1.15;

export default function DetailsBackdrop({
  imageUrl,
  tint,
  maxTintAlpha,
  heroHeight,
  scrollY,
  trailerKey,
  trailerMuted = true,
  trailerAllowed = false,
  onTrailerPlayingChange,
  onTrailerFinished,
}: {
  imageUrl?: string;
  tint: string;
  maxTintAlpha: number;
  heroHeight: number;
  scrollY: SharedValue<number>;
  /** YouTube key of the inline hero trailer. Omit for artwork only. */
  trailerKey?: string;
  trailerMuted?: boolean;
  /** False pauses the trailer, for example while another screen is on top. */
  trailerAllowed?: boolean;
  onTrailerPlayingChange?: (playing: boolean) => void;
  onTrailerFinished?: () => void;
}) {
  const { width } = useWindowDimensions();
  const artHeight = heroHeight * ART_HEIGHT_FACTOR;
  const [heroVisible, setHeroVisible] = useState(true);

  useAnimatedReaction(
    () => scrollY.value < heroHeight,
    (visible, previous) => {
      if (visible !== previous) runOnJS(setHeroVisible)(visible);
    },
    [heroHeight]
  );

  const artStyle = useAnimatedStyle(() => ({
    transform: [
      { scale: interpolate(scrollY.value, [-150, 0], [1.15, 1], Extrapolation.CLAMP) },
    ],
  }));

  const tintStyle = useAnimatedStyle(() => ({
    opacity: interpolate(
      scrollY.value,
      [0, heroHeight * FADE_HERO_FRACTION],
      [0, maxTintAlpha],
      Extrapolation.CLAMP
    ),
  }));

  const fadeColors = useMemo(
    () => [withAlpha(tint, 0), withAlpha(tint, 0.4), withAlpha(tint, 0.7), withAlpha(tint, 0.9), tint] as const,
    [tint]
  );

  return (
    <View pointerEvents="none" style={[StyleSheet.absoluteFill, { backgroundColor: tint }]}>
      <View style={{ height: artHeight, overflow: 'hidden' }}>
        {imageUrl ? (
          <Animated.View style={[StyleSheet.absoluteFill, artStyle]}>
            <FastImage source={{ uri: imageUrl }} style={StyleSheet.absoluteFill} resizeMode="cover" />
          </Animated.View>
        ) : null}
        {trailerKey ? (
          <DetailsHeroTrailer
            videoKey={trailerKey}
            width={width}
            height={artHeight}
            muted={trailerMuted}
            active={trailerAllowed && heroVisible}
            onPlayingChange={(playing) => onTrailerPlayingChange?.(playing)}
            onFinished={() => onTrailerFinished?.()}
          />
        ) : null}
        <LinearGradient
          colors={['rgba(0,0,0,0.55)', 'rgba(0,0,0,0)']}
          style={[StyleSheet.absoluteFill, { bottom: '55%' }]}
        />
        <LinearGradient
          colors={fadeColors}
          locations={[0, 0.3, 0.5, 0.7, 1]}
          style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: '70%' }}
        />
        <Animated.View style={[StyleSheet.absoluteFill, { backgroundColor: tint }, tintStyle]} />
      </View>
    </View>
  );
}
