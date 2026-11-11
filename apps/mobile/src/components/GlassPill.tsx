/**
 * Home's Liquid Glass pill (white when selected) and the round glass header button, shared by
 * My List, Person, Downloads and the other pages with filter pills.
 */

import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import LiquidGlass from './LiquidGlass';

export function GlassPill({
  label,
  count,
  icon,
  selected,
  onPress,
  accessibilityRole = 'button',
}: {
  label: string;
  count?: number;
  icon?: keyof typeof Ionicons.glyphMap;
  selected?: boolean;
  onPress: () => void;
  accessibilityRole?: 'button' | 'link';
}) {
  return (
    <Pressable
      onPress={() => {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
        onPress();
      }}
      accessibilityRole={accessibilityRole}
      accessibilityState={{ selected: !!selected }}
      style={({ pressed }) => [styles.pill, selected && styles.pillSelected, pressed && { opacity: 0.75 }]}
    >
      {selected ? null : <LiquidGlass radius={12} />}
      {icon ? <Ionicons name={icon} size={15} color={selected ? '#000' : '#fff'} /> : null}
      <Text style={[styles.pillText, selected && { color: '#000' }]} numberOfLines={1}>{label}</Text>
      {count !== undefined ? <Text style={[styles.pillCount, selected && { color: 'rgba(0,0,0,0.55)' }]}>{count}</Text> : null}
    </Pressable>
  );
}

/**
 * A glass pill showing the current choice with a chevron, for use as a GlassMenu anchor
 * (the menu handles the press).
 */
export function GlassDropdownPill({ label, count }: { label: string; count?: number }) {
  return (
    <View style={styles.pill} accessibilityRole="button" accessibilityLabel={count !== undefined ? `${label}, ${count}` : label}>
      <LiquidGlass radius={12} />
      <Text style={styles.pillText} numberOfLines={1}>{label}</Text>
      {count !== undefined ? <Text style={styles.pillCount}>{count}</Text> : null}
      <Ionicons name="chevron-down" size={14} color="rgba(255,255,255,0.8)" style={{ marginLeft: -1 }} />
    </View>
  );
}

/** A round Liquid Glass icon button (40 pt by default, 36 pt in compact navigation bars). */
export function RoundGlassButton({
  icon,
  label,
  onPress,
  size = 40,
  iconSize,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  onPress?: () => void;
  size?: number;
  iconSize?: number;
}) {
  return (
    <Pressable
      onPress={onPress}
      disabled={!onPress}
      hitSlop={6}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={({ pressed }) => [roundStyle(size), pressed && { opacity: 0.7 }]}
    >
      <LiquidGlass radius={size / 2} />
      <Ionicons name={icon} size={iconSize ?? (size >= 40 ? 19 : 20)} color="#fff" />
    </Pressable>
  );
}

/** The same round glass look for a non-pressable anchor (e.g. inside a GlassMenu). */
export function RoundGlassIcon({ icon, size = 40, iconSize }: { icon: keyof typeof Ionicons.glyphMap; size?: number; iconSize?: number }) {
  return (
    <View style={roundStyle(size)}>
      <LiquidGlass radius={size / 2} />
      <Ionicons name={icon} size={iconSize ?? (size >= 40 ? 19 : 20)} color="#fff" />
    </View>
  );
}

const roundStyle = (size: number) => ({
  width: size,
  height: size,
  borderRadius: size / 2,
  overflow: 'hidden' as const,
  alignItems: 'center' as const,
  justifyContent: 'center' as const,
});

export const glassPillStyles = StyleSheet.create({
  /** Horizontal pill row content, as on Home and My List. */
  row: { paddingHorizontal: 16, gap: 8, alignItems: 'center', paddingVertical: 6 },
});

const styles = StyleSheet.create({
  pill: { height: 40, paddingHorizontal: 15, borderRadius: 12, overflow: 'hidden', flexDirection: 'row', alignItems: 'center', gap: 6 },
  pillSelected: { backgroundColor: '#fff' },
  pillText: { color: '#fff', fontSize: 15, fontWeight: '600' },
  pillCount: { color: 'rgba(255,255,255,0.6)', fontSize: 14, fontWeight: '600' },
});
