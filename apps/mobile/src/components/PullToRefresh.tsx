import React, { useEffect, useRef, useState } from 'react';
import { View, ActivityIndicator, Animated, StyleSheet } from 'react-native';
import { useTopBarStore } from './TopBarStore';

interface PullToRefreshProps {
  scrollY: Animated.Value;
  refreshing: boolean;
  onRefresh: () => void;
}

const PULL_THRESHOLD = 80;

export default function PullToRefresh({ scrollY, refreshing, onRefresh }: PullToRefreshProps) {
  const barHeight = useTopBarStore((s) => s.height || 90);
  const [pullDistance, setPullDistance] = useState(0);
  const hasTriggeredRef = useRef(false);

  useEffect(() => {
    const listenerId = scrollY.addListener(({ value }) => {
      // Negative value = pulling down (overscroll)
      const pull = Math.max(0, -value);
      setPullDistance(pull);

      // Trigger refresh when pulled past threshold and released
      if (value < -PULL_THRESHOLD && !hasTriggeredRef.current && !refreshing) {
        hasTriggeredRef.current = true;
        onRefresh();
      }

      // Reset trigger flag when back at top
      if (value >= -10) {
        hasTriggeredRef.current = false;
      }
    });

    return () => scrollY.removeListener(listenerId);
  }, [scrollY, refreshing, onRefresh]);

  // Reset pull distance when refreshing ends
  useEffect(() => {
    if (!refreshing) {
      setPullDistance(0);
    }
  }, [refreshing]);

  const showIndicator = pullDistance > 15 || refreshing;
  const progress = Math.min(1, pullDistance / PULL_THRESHOLD);
  const isReady = pullDistance >= PULL_THRESHOLD;

  if (!showIndicator) return null;

  return (
    <View style={[styles.container, { top: barHeight + 8 }]} pointerEvents="none">
      <View style={styles.indicatorWrapper}>
        {refreshing ? (
          <ActivityIndicator size="small" color="#fff" />
        ) : (
          <View style={styles.progressContainer}>
            {/* Circular progress indicator */}
            <View style={[styles.progressRing, isReady && styles.progressRingReady]}>
              <View
                style={[
                  styles.progressArc,
                  {
                    opacity: progress,
                    transform: [{ rotate: `${progress * 360}deg` }],
                  },
                ]}
              />
            </View>
          </View>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    left: 0,
    right: 0,
    alignItems: 'center',
    zIndex: 30,
  },
  indicatorWrapper: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(0,0,0,0.6)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  progressContainer: {
    width: 24,
    height: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  progressRing: {
    width: 22,
    height: 22,
    borderRadius: 11,
    borderWidth: 2.5,
    borderColor: 'rgba(255,255,255,0.3)',
    borderTopColor: '#fff',
  },
  progressRingReady: {
    borderColor: '#fff',
  },
  progressArc: {
    position: 'absolute',
    width: 22,
    height: 22,
    borderRadius: 11,
  },
});
