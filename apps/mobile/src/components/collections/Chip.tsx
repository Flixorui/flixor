import React from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { useTheme } from '../../hooks/useTheme';

/** Filter chip. `caret` marks one that opens a picker. */
export default function Chip({
  label,
  active,
  caret,
  onPress,
  disabled,
}: {
  label: string;
  active?: boolean;
  caret?: boolean;
  onPress: () => void;
  disabled?: boolean;
}) {
  const theme = useTheme();
  const color = active ? theme.accentBright : theme.textPrimary;
  return (
    <Pressable
      disabled={disabled}
      onPress={() => {
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
        onPress();
      }}
      style={[
        styles.chip,
        {
          borderColor: active ? theme.accent : theme.separatorStrong,
          backgroundColor: active ? theme.accentSoft : 'transparent',
          opacity: disabled ? 0.5 : 1,
        },
      ]}
    >
      <Text style={[styles.label, { color }]} numberOfLines={1}>
        {label}
      </Text>
      {caret ? <Ionicons name="chevron-down" size={14} color={color} style={{ marginLeft: 4 }} /> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 16,
    borderWidth: 1,
    marginRight: 8,
    marginBottom: 8,
  },
  label: { fontSize: 14, fontWeight: '600' },
});
