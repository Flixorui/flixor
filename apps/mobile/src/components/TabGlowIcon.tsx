import React from 'react';
import { Platform, StyleSheet, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import type { FlixorTheme } from '../core/theme';

type Props = {
  name: keyof typeof Ionicons.glyphMap;
  size: number;
  color: string;
  /** Shows the soft accent light behind the icon. */
  glow: boolean;
  theme: FlixorTheme;
};

/** A tab icon with the selected-tab light from macOS's "Glass Glow". */
export default function TabGlowIcon({ name, size, color, glow, theme }: Props) {
  return (
    <View style={styles.wrap}>
      {glow ? (
        <View
          pointerEvents="none"
          style={[
            styles.glow,
            { backgroundColor: theme.accentSoft },
            Platform.OS === 'ios' && { shadowColor: theme.accent },
          ]}
        />
      ) : null}
      <Ionicons name={name} size={size} color={color} />
    </View>
  );
}

const GLOW_SIZE = 40;

const styles = StyleSheet.create({
  wrap: { alignItems: 'center', justifyContent: 'center' },
  glow: {
    position: 'absolute',
    width: GLOW_SIZE,
    height: GLOW_SIZE,
    borderRadius: GLOW_SIZE / 2,
    shadowOpacity: 0.55,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 0 },
  },
});
