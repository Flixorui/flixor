import React, { useEffect } from 'react';
import { View, Animated, StyleSheet, Dimensions } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useAppSettings } from '../hooks/useAppSettings';
import { LANDSCAPE_CARD_SIZE, POSTER_SIZES } from './Poster';
import type { RowLayout } from '../core/SettingsData';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

interface RowSkeletonProps {
  title?: string;
  itemCount?: number;
  layout?: RowLayout;
}

/*
 * One shimmer for the whole screen: every skeleton block shares a single clock and offsets
 * the highlight by its own position, so a single band sweeps across the page instead of
 * each tile shimmering from its own edge.
 */
const BAND = SCREEN_WIDTH * 0.7;
const SWEEP_MS = 1500;
const sweep = new Animated.Value(0);
let sweepUsers = 0;
let sweepLoop: Animated.CompositeAnimation | null = null;

function useSharedSweep() {
  useEffect(() => {
    sweepUsers += 1;
    if (!sweepLoop) {
      sweep.setValue(0);
      sweepLoop = Animated.loop(Animated.timing(sweep, { toValue: 1, duration: SWEEP_MS, useNativeDriver: true }));
      sweepLoop.start();
    }
    return () => {
      sweepUsers -= 1;
      if (sweepUsers === 0 && sweepLoop) {
        sweepLoop.stop();
        sweepLoop = null;
      }
    };
  }, []);
}

/** The highlight inside a block that starts `x` points from the left edge of the screen. */
function Highlight({ x, strong }: { x: number; strong?: boolean }) {
  const translateX = sweep.interpolate({ inputRange: [0, 1], outputRange: [-BAND - x, SCREEN_WIDTH - x] });
  return (
    <Animated.View style={[styles.shimmer, { transform: [{ translateX }] }]}>
      <LinearGradient
        colors={strong
          ? ['rgba(80,80,80,0)', 'rgba(110,110,110,0.55)', 'rgba(80,80,80,0)']
          : ['rgba(60,60,60,0)', 'rgba(90,90,90,0.5)', 'rgba(60,60,60,0)']}
        start={{ x: 0, y: 0.5 }}
        end={{ x: 1, y: 0.5 }}
        style={StyleSheet.absoluteFill}
      />
    </Animated.View>
  );
}

function RowSkeleton({ title, itemCount = 5, layout = 'poster' }: RowSkeletonProps) {
  const { settings } = useAppSettings();
  const size = layout === 'landscape' ? LANDSCAPE_CARD_SIZE : POSTER_SIZES[settings.posterSize] || POSTER_SIZES.medium;
  const borderRadius = settings.posterBorderRadius || 8;
  useSharedSweep();

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <View style={[styles.titleSkeleton, { width: title ? Math.min(220, title.length * 8) : 120 }]}>
          <Highlight x={16} strong />
        </View>
      </View>
      <View style={styles.postersContainer}>
        {Array.from({ length: itemCount }).map((_, index) => (
          <View
            key={index}
            style={[styles.posterContainer, { width: size.width, height: size.height, borderRadius, marginRight: 12 }]}
          >
            <Highlight x={16 + index * (size.width + 12)} />
          </View>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 16,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 15,
    marginTop: 15,
    paddingHorizontal: 16,
  },
  titleSkeleton: {
    height: 16,
    backgroundColor: '#2a2a2c',
    borderRadius: 4,
    overflow: 'hidden',
  },
  postersContainer: {
    flexDirection: 'row',
    paddingHorizontal: 16,
  },
  posterContainer: {
    backgroundColor: '#1f1f21',
    overflow: 'hidden',
  },
  shimmer: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    width: BAND,
  },
});

export default React.memo(RowSkeleton);
