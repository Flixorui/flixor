import React from 'react';
import { ScrollView, StyleSheet, Text, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../../hooks/useTheme';
import PlayerPanel from './PlayerPanel';

export const PLAYBACK_SPEED_PRESETS = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

export function formatSpeed(speed: number): string {
  return `${speed}x`;
}

type Props = {
  speed: number;
  onSelect: (speed: number) => void;
  onClose: () => void;
};

export default function SpeedPanel({ speed, onSelect, onClose }: Props) {
  const theme = useTheme();
  return (
    <PlayerPanel title="Playback Speed" onClose={onClose}>
      <ScrollView>
        {PLAYBACK_SPEED_PRESETS.map((preset) => {
          const selected = preset === speed;
          return (
            <TouchableOpacity
              key={preset}
              style={[styles.row, selected && { backgroundColor: theme.accentSoft }]}
              onPress={() => onSelect(preset)}
              accessibilityRole="button"
              accessibilityState={{ selected }}
            >
              <Text style={[styles.label, { color: theme.textPrimary }]}>
                {preset === 1 ? 'Normal' : formatSpeed(preset)}
              </Text>
              {selected ? <Ionicons name="checkmark" size={20} color={theme.accentBright} /> : null}
            </TouchableOpacity>
          );
        })}
      </ScrollView>
    </PlayerPanel>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 13,
  },
  label: {
    fontSize: 15,
    fontWeight: '600',
  },
});
