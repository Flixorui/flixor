import React, { useEffect, useRef, useState } from 'react';
import { View, ActivityIndicator, Animated, StyleSheet } from 'react-native';
import { useTopBarStore } from './TopBarStore';
import * as Haptics from 'expo-haptics';

interface PullToRefreshProps {
  scrollY: Animated.Value;
  refreshing: boolean;
  onRefresh: () => void;
}

const PULL_THRESHOLD = 120;

const HAPTIC_INTERVAL = 30; // Haptic feedback every 30px of pull

export default function PullToRefresh({ scrollY, refreshing, onRefresh }: PullToRefreshProps) {
  const barHeight = useTopBarStore((s) => s.height || 90);
  const [pullDistance, setPullDistance] = useState(0);
  const hasTriggeredRef = useRef(false);
  const lastHapticPullRef = useRef(0);

  useEffect(() => {
    const listenerId = scrollY.addListener(({ value }) => {
      // Negative value = pulling down (overscroll)
      const pull = Math.max(0, -value);
      setPullDistance(pull);

      // Progressive haptic feedback while pulling
      if (pull > 20 && pull < PULL_THRESHOLD && !refreshing) {
        const hapticStep = Math.floor(pull / HAPTIC_INTERVAL);
        const lastStep = Math.floor(lastHapticPullRef.current / HAPTIC_INTERVAL);
        if (hapticStep > lastStep) {
          Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
        }
      }
      lastHapticPullRef.current = pull;

      // Stronger haptic when reaching threshold
      if (pull >= PULL_THRESHOLD && lastHapticPullRef.current < PULL_THRESHOLD) {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      }

      // Trigger refresh when pulled past threshold
      if (value < -PULL_THRESHOLD && !hasTriggeredRef.current && !refreshing) {
        hasTriggeredRef.current = true;
        Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
        onRefresh();
      }

      // Reset trigger flag when back at top
      if (value >= -10) {
        hasTriggeredRef.current = false;
        lastHapticPullRef.current = 0;
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
