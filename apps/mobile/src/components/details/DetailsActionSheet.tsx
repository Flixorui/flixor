import React from 'react';
import { ActivityIndicator, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../hooks/useTheme';

export interface DetailsAction {
  key: string;
  title: string;
  icon?: keyof typeof Ionicons.glyphMap;
  disabled?: boolean;
  /** Leaves the sheet open, for an action that swaps its contents. */
  keepOpen?: boolean;
  onPress: () => void;
}

/** A bottom sheet of actions. Used for the watched menu and episode menus. */
export default function DetailsActionSheet({
  visible,
  title,
  message,
  loading,
  actions,
  onClose,
}: {
  visible: boolean;
  title?: string;
  /** Muted line under the title, such as progress. */
  message?: string;
  loading?: boolean;
  actions: DetailsAction[];
  onClose: () => void;
}) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <Modal visible={visible} transparent animationType="fade" statusBarTranslucent onRequestClose={onClose}>
      <Pressable style={styles.scrim} onPress={onClose} accessibilityRole="button" accessibilityLabel="Close">
        <Pressable
          style={[styles.sheet, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 12 }]}
          onPress={() => undefined}
        >
          <View style={[styles.handle, { backgroundColor: theme.separatorStrong }]} />
          {title ? (
            <Text numberOfLines={2} style={[styles.title, { color: theme.textPrimary }]}>
              {title}
            </Text>
          ) : null}
          {message ? <Text style={[styles.message, { color: theme.textSecondary }]}>{message}</Text> : null}
          {loading ? <ActivityIndicator style={styles.loading} color={theme.textPrimary} /> : null}
          <ScrollView bounces={false} style={styles.list}>
            {actions.map((action) => (
              <Pressable
                key={action.key}
                disabled={action.disabled}
                onPress={() => {
                  if (!action.keepOpen) onClose();
                  action.onPress();
                }}
                style={({ pressed }) => [
                  styles.row,
                  { opacity: action.disabled ? 0.4 : 1, backgroundColor: pressed ? theme.pressedFill : 'transparent' },
                ]}
              >
                {action.icon ? <Ionicons name={action.icon} size={20} color={theme.textPrimary} style={styles.icon} /> : null}
                <Text style={[styles.rowText, { color: theme.textPrimary }]}>{action.title}</Text>
              </Pressable>
            ))}
          </ScrollView>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  scrim: {
    flex: 1,
    justifyContent: 'flex-end',
    backgroundColor: 'rgba(0,0,0,0.55)',
  },
  sheet: {
    maxHeight: '70%',
    paddingTop: 10,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
  },
  handle: {
    alignSelf: 'center',
    width: 40,
    height: 4,
    borderRadius: 2,
    marginBottom: 12,
  },
  title: {
    fontSize: 17,
    fontWeight: '700',
    paddingHorizontal: 20,
  },
  message: {
    fontSize: 13,
    paddingHorizontal: 20,
    marginTop: 4,
  },
  loading: {
    marginTop: 12,
  },
  list: {
    marginTop: 8,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 14,
  },
  icon: {
    marginRight: 14,
  },
  rowText: {
    fontSize: 16,
    fontWeight: '500',
  },
});
