import React from 'react';
import { Pressable, StyleSheet, Text, TouchableOpacity, View, useWindowDimensions } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../../hooks/useTheme';

type Props = {
  title: string;
  onClose: () => void;
  headerAccessory?: React.ReactNode;
  children: React.ReactNode;
};

const MAX_PANEL_WIDTH = 440;

/** Side panel drawn over the video. Tapping outside closes it. */
export default function PlayerPanel({ title, onClose, headerAccessory, children }: Props) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const panelWidth = Math.min(MAX_PANEL_WIDTH, width - insets.left - insets.right - 32);

  return (
    <View style={StyleSheet.absoluteFill} accessibilityViewIsModal>
      <Pressable style={[StyleSheet.absoluteFill, styles.backdrop]} onPress={onClose} accessibilityLabel="Close" />
      <View
        style={[
          styles.panel,
          {
            width: panelWidth,
            top: insets.top + 12,
            bottom: insets.bottom + 12,
            right: insets.right + 16,
            backgroundColor: theme.surfaceElevated,
            borderColor: theme.separatorStrong,
          },
        ]}
      >
        <View style={[styles.header, { borderBottomColor: theme.separator }]}>
          <Text style={[styles.title, { color: theme.textPrimary }]} numberOfLines={1}>
            {title}
          </Text>
          <View style={styles.headerRight}>
            {headerAccessory}
            <TouchableOpacity onPress={onClose} hitSlop={10} accessibilityRole="button" accessibilityLabel="Close">
              <Ionicons name="close" size={22} color={theme.textSecondary} />
            </TouchableOpacity>
          </View>
        </View>
        <View style={styles.body}>{children}</View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    backgroundColor: 'rgba(0,0,0,0.45)',
  },
  panel: {
    position: 'absolute',
    borderRadius: 14,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  title: {
    flex: 1,
    fontSize: 16,
    fontWeight: '700',
  },
  headerRight: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  body: {
    flex: 1,
  },
});
