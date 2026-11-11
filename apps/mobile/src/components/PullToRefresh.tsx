/**
 * Pull to refresh with a round Liquid Glass button.
 *
 * Refresh starts only when the finger is lifted past the line (like iOS), never while
 * dragging and never from momentum: a fast flick back to the top bounces past the line
 * without a finger on the screen and must not refresh. Pushing back up before letting go
 * cancels it.
 *
 * Feedback: the button follows the pull, grows in, and its arrow flips (with one tap) once
 * the pull is far enough; while refreshing it holds still and spins.
 *
 * Usage:
 *   const pull = usePullToRefresh(scrollY, refreshing, onRefresh);
 *   <ScrollView {...pull.dragHandlers} onScroll={...sets scrollY...} />
 *   <PullToRefresh {...pull.indicatorProps} top={headerHeight + 6} />
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Animated, StyleSheet, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import LiquidGlass from './LiquidGlass';

const THRESHOLD = 100; // pt of pull before letting go refreshes
const SHOW_AFTER = 6; // pt of pull before the button appears
const SIZE = 40;
// Never fully transparent: iOS stops drawing Liquid Glass inside a view that reached 0 alpha
const MIN_OPACITY = 0.02;

export function usePullToRefresh(scrollY: Animated.Value, refreshing: boolean, onRefresh: () => void) {
  const dragging = useRef(false);
  const readyRef = useRef(false);
  const visibleRef = useRef(false);
  const refreshingRef = useRef(refreshing);
  refreshingRef.current = refreshing;
  const [ready, setReady] = useState(false);
  const [visible, setVisible] = useState(false);

  const setVisibleOnce = (v: boolean) => {
    if (visibleRef.current !== v) {
      visibleRef.current = v;
      setVisible(v);
    }
  };

  useEffect(() => {
    const id = scrollY.addListener(({ value }) => {
      const pull = Math.max(0, -value);
      setVisibleOnce(pull > SHOW_AFTER || refreshingRef.current);
      const nowReady = dragging.current && pull >= THRESHOLD && !refreshingRef.current;
      if (nowReady !== readyRef.current) {
        readyRef.current = nowReady;
        setReady(nowReady);
        if (nowReady) Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
      }
    });
    return () => scrollY.removeListener(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [scrollY]);

  useEffect(() => {
    if (refreshing) setVisibleOnce(true);
    // When refreshing ends the page is back at the top, so the button can go
    else setVisibleOnce(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [refreshing]);

  const onScrollBeginDrag = useCallback(() => {
    dragging.current = true;
  }, []);

  const onScrollEndDrag = useCallback((e: any) => {
    dragging.current = false;
    const pull = -(e?.nativeEvent?.contentOffset?.y ?? 0);
    if (readyRef.current) {
      readyRef.current = false;
      setReady(false);
    }
    if (pull >= THRESHOLD && !refreshingRef.current) {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      onRefresh();
    }
  }, [onRefresh]);

  return {
    dragHandlers: { onScrollBeginDrag, onScrollEndDrag },
    indicatorProps: { scrollY, refreshing, ready, visible },
  };
}

export default function PullToRefresh({
  scrollY,
  refreshing,
  ready,
  visible,
  top,
}: {
  scrollY: Animated.Value;
  refreshing: boolean;
  ready: boolean;
  visible: boolean;
  /** Where the button rests, below the screen's header. */
  top: number;
}) {
  if (!visible) return null;

  // While pulling it follows the finger at half speed and grows in; while refreshing it holds
  const translateY = refreshing
    ? 0
    : scrollY.interpolate({ inputRange: [-THRESHOLD * 2, 0], outputRange: [THRESHOLD * 0.6, 0], extrapolate: 'clamp' });
  const scale = refreshing
    ? 1
    : scrollY.interpolate({ inputRange: [-THRESHOLD, -SHOW_AFTER], outputRange: [1, 0.55], extrapolate: 'clamp' });
  const opacity = refreshing
    ? 1
    : scrollY.interpolate({ inputRange: [-THRESHOLD * 0.6, -SHOW_AFTER], outputRange: [1, MIN_OPACITY], extrapolate: 'clamp' });

  return (
    <Animated.View
      pointerEvents="none"
      style={[styles.container, { top, opacity, transform: [{ translateY }, { scale }] }]}
      accessibilityLabel={refreshing ? 'Refreshing' : ready ? 'Release to refresh' : 'Pull to refresh'}
    >
      <View style={styles.button}>
        <LiquidGlass radius={SIZE / 2} />
        {refreshing ? (
          <ActivityIndicator size="small" color="#fff" />
        ) : (
          <Ionicons name="arrow-down" size={20} color="#fff" style={{ transform: [{ rotate: ready ? '180deg' : '0deg' }] }} />
        )}
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  container: { position: 'absolute', left: 0, right: 0, alignItems: 'center', zIndex: 30 },
  button: {
    width: SIZE,
    height: SIZE,
    borderRadius: SIZE / 2,
    overflow: 'hidden',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
