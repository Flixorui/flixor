/**
 * A frosted dropdown that grows out of its anchor (Netflix's Categories menu), with
 * drill-in submenus. Built in React Native so it opens the same way in a header or inside a
 * scrolling page; the native iOS menu only opens on tap in some of those places.
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Animated, Easing, Modal, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import ConditionalBlurView from './ConditionalBlurView';
import LiquidGlass, { liquidGlassAvailable } from './LiquidGlass';

export type GlassMenuItem = {
  title: string;
  icon?: keyof typeof Ionicons.glyphMap;
  checked?: boolean;
  onPress?: () => void;
  /** Opens a submenu in place, with a back row at the top. */
  children?: GlassMenuItem[];
};

const MENU_W = 250;
const ROW_H = 44;

export default function GlassMenu({
  items,
  children,
  accessibilityLabel,
}: {
  items: GlassMenuItem[];
  children: React.ReactNode;
  accessibilityLabel?: string;
}) {
  const anchorRef = useRef<View>(null);
  const { width: screenW, height: screenH } = useWindowDimensions();
  const [open, setOpen] = useState(false);
  const [anchor, setAnchor] = useState({ x: 0, y: 0, w: 0, h: 0 });
  const [path, setPath] = useState<number[]>([]);
  const progress = useRef(new Animated.Value(0)).current;

  const show = useCallback(() => {
    anchorRef.current?.measureInWindow((x, y, w, h) => {
      setAnchor({ x, y, w, h });
      setPath([]);
      setOpen(true);
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    });
  }, []);

  useEffect(() => {
    if (!open) return;
    progress.setValue(0);
    Animated.timing(progress, { toValue: 1, duration: 200, easing: Easing.out(Easing.cubic), useNativeDriver: true }).start();
  }, [open, progress]);

  const close = useCallback((after?: () => void) => {
    Animated.timing(progress, { toValue: 0, duration: 140, easing: Easing.in(Easing.quad), useNativeDriver: true }).start(() => {
      setOpen(false);
      after?.();
    });
  }, [progress]);

  // The level being shown, following the submenus opened so far
  let level = items;
  let parentTitle: string | undefined;
  for (const i of path) {
    parentTitle = level[i]?.title;
    level = level[i]?.children ?? [];
  }

  const left = Math.min(Math.max(12, anchor.x + anchor.w / 2 - MENU_W / 2), screenW - MENU_W - 12);
  const top = anchor.y + anchor.h + 8;
  const maxHeight = Math.max(ROW_H * 3, screenH - top - 110);

  return (
    <>
      <Pressable ref={anchorRef} onPress={show} accessibilityRole="button" accessibilityLabel={accessibilityLabel} hitSlop={4}>
        {children}
      </Pressable>
      <Modal visible={open} transparent animationType="none" onRequestClose={() => close()} statusBarTranslucent>
        <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, styles.dim, { opacity: progress }]} />
        <Pressable style={StyleSheet.absoluteFill} onPress={() => close()} accessibilityLabel="Close menu" />
        <Animated.View
          style={[
            styles.menu,
            {
              left,
              top,
              maxHeight,
              // Never fully 0: iOS doesn't draw Liquid Glass properly once a parent has been
              // at zero alpha, so the menu fades from an invisible 2% instead
              opacity: progress.interpolate({ inputRange: [0, 1], outputRange: [0.02, 1] }),
              // Grows from the point under the anchor's centre
              transformOrigin: [anchor.x + anchor.w / 2 - left, 0, 0],
              transform: [{ scale: progress.interpolate({ inputRange: [0, 1], outputRange: [0.85, 1] }) }],
            },
          ]}
        >
          {liquidGlassAvailable ? (
            // Apple's Liquid Glass (Expo GlassView), with a dark tint so the text reads over
            // bright artwork
            <LiquidGlass radius={22} tint="rgba(20,20,24,0.55)" />
          ) : (
            <>
              <ConditionalBlurView intensity={60} tint="dark" style={StyleSheet.absoluteFill} />
              <View style={[StyleSheet.absoluteFill, styles.fill]} pointerEvents="none" />
            </>
          )}
          <ScrollView bounces={false} showsVerticalScrollIndicator={level.length > 8}>
            {path.length > 0 ? (
              <Pressable onPress={() => setPath((p) => p.slice(0, -1))} style={({ pressed }) => [styles.row, pressed && styles.pressed]}>
                <Ionicons name="chevron-back" size={17} color="#fff" style={styles.leading} />
                <Text style={[styles.title, styles.backTitle]} numberOfLines={1}>{parentTitle}</Text>
              </Pressable>
            ) : null}
            {level.map((item, index) => (
              <Pressable
                key={`${item.title}-${index}`}
                onPress={() => {
                  if (item.children?.length) {
                    setPath((p) => [...p, index]);
                    return;
                  }
                  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
                  close(item.onPress);
                }}
                style={({ pressed }) => [styles.row, index > 0 || path.length > 0 ? styles.divider : null, pressed && styles.pressed]}
                accessibilityRole="menuitem"
                accessibilityState={{ checked: item.checked }}
              >
                {item.checked ? (
                  <Ionicons name="checkmark" size={17} color="#fff" style={styles.leading} />
                ) : item.icon ? (
                  <Ionicons name={item.icon} size={18} color="#fff" style={styles.leading} />
                ) : null}
                <Text style={styles.title} numberOfLines={1}>{item.title}</Text>
                {item.children?.length ? <Ionicons name="chevron-forward" size={16} color="rgba(255,255,255,0.6)" /> : null}
              </Pressable>
            ))}
          </ScrollView>
        </Animated.View>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  menu: {
    position: 'absolute',
    width: MENU_W,
    borderRadius: 22,
    overflow: 'hidden',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.18)',
    paddingVertical: 6,
  },
  fill: { backgroundColor: 'rgba(60,62,68,0.55)' },
  dim: { backgroundColor: 'rgba(0,0,0,0.25)' },
  row: { height: ROW_H, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 18 },
  divider: { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: 'rgba(255,255,255,0.08)' },
  pressed: { backgroundColor: 'rgba(255,255,255,0.12)' },
  leading: { width: 26 },
  title: { flex: 1, color: '#fff', fontSize: 16 },
  backTitle: { fontWeight: '600' },
});
