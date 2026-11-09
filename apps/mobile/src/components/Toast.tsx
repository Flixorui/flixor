/**
 * App-wide toast. `<ToastHost />` is mounted once in App.tsx; call `showToast` from anywhere.
 *
 * The host sits above React Navigation's card screens. Screens presented as native
 * modals (Player, Search on the Home stack) cover it; such a screen can render its
 * own `<ToastHost />`.
 */

import React, { useEffect, useRef, useState, useSyncExternalStore } from 'react';
import { Animated, Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../hooks/useTheme';

export type ToastKind = 'success' | 'error' | 'info';

export interface ToastOptions {
  kind?: ToastKind;
  /** Milliseconds on screen. 0 keeps it up until tapped. Default 3000. */
  duration?: number;
}

interface ToastItem {
  id: number;
  message: string;
  kind: ToastKind;
  duration: number;
}

let current: ToastItem | null = null;
let nextId = 1;
const listeners = new Set<() => void>();

function setCurrent(item: ToastItem | null): void {
  current = item;
  listeners.forEach((listener) => listener());
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

function getCurrent(): ToastItem | null {
  return current;
}

/** Shows a toast, replacing any toast already on screen. */
export function showToast(message: string, options?: ToastOptions): void {
  setCurrent({
    id: nextId++,
    message,
    kind: options?.kind ?? 'info',
    duration: options?.duration ?? 3000,
  });
}

export function hideToast(): void {
  setCurrent(null);
}

const ICONS: Record<ToastKind, keyof typeof Ionicons.glyphMap> = {
  success: 'checkmark-circle',
  error: 'close-circle',
  info: 'information-circle',
};

const FADE_MS = 200;

export default function ToastHost() {
  const item = useSyncExternalStore(subscribe, getCurrent, getCurrent);
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const progress = useRef(new Animated.Value(0)).current;
  // Keeps the last toast on screen while it fades out
  const [visible, setVisible] = useState<ToastItem | null>(item);

  useEffect(() => {
    if (item) {
      setVisible(item);
      Animated.timing(progress, { toValue: 1, duration: FADE_MS, useNativeDriver: true }).start();
      if (item.duration <= 0) return;
      const timer = setTimeout(() => {
        if (getCurrent()?.id === item.id) hideToast();
      }, item.duration);
      return () => clearTimeout(timer);
    }
    const animation = Animated.timing(progress, { toValue: 0, duration: FADE_MS, useNativeDriver: true });
    animation.start(({ finished }) => {
      if (finished) setVisible(null);
    });
    return () => animation.stop();
  }, [item, progress]);

  if (!visible) return null;

  const iconColor =
    visible.kind === 'success' ? theme.success : visible.kind === 'error' ? theme.danger : theme.info;
  const translateY = progress.interpolate({ inputRange: [0, 1], outputRange: [-16, 0] });

  return (
    <View pointerEvents="box-none" style={[styles.host, { top: insets.top + 8 }]}>
      <Animated.View style={{ opacity: progress, transform: [{ translateY }] }}>
        <Pressable
          accessibilityRole="alert"
          onPress={hideToast}
          style={[styles.toast, { borderColor: theme.separator }]}
        >
          <Ionicons name={ICONS[visible.kind]} size={20} color={iconColor} />
          <Text style={styles.message} numberOfLines={3}>
            {visible.message}
          </Text>
        </Pressable>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  host: {
    position: 'absolute',
    left: 16,
    right: 16,
    zIndex: 9999,
    elevation: 9999,
  },
  toast: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 14,
    paddingVertical: 12,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    backgroundColor: 'rgba(0,0,0,0.9)',
  },
  message: {
    flex: 1,
    color: '#fff',
    fontSize: 15,
  },
});
