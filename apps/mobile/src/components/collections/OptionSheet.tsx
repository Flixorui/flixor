import React from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '../../hooks/useTheme';

export interface SheetOption<T> {
  value: T;
  label: string;
  detail?: string;
}

/** Bottom sheet with one choice per row. */
export default function OptionSheet<T>({
  visible,
  title,
  options,
  selected,
  onSelect,
  onClose,
}: {
  visible: boolean;
  title: string;
  options: Array<SheetOption<T>>;
  selected?: T;
  onSelect: (value: T) => void;
  onClose: () => void;
}) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable
          style={[styles.sheet, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 12 }]}
          onPress={() => undefined}
        >
          <Text style={[styles.title, { color: theme.textPrimary }]}>{title}</Text>
          <ScrollView style={{ maxHeight: 420 }} keyboardShouldPersistTaps="handled">
            {options.map((option, index) => {
              const active = option.value === selected;
              return (
                <Pressable
                  key={index}
                  onPress={() => {
                    onSelect(option.value);
                    onClose();
                  }}
                  style={[styles.row, active && { backgroundColor: theme.accentSoft }]}
                >
                  <View style={{ flex: 1 }}>
                    <Text style={[styles.label, { color: active ? theme.accentBright : theme.textPrimary }]}>
                      {option.label}
                    </Text>
                    {option.detail ? (
                      <Text style={[styles.detail, { color: theme.textTertiary }]}>{option.detail}</Text>
                    ) : null}
                  </View>
                  {active ? <Ionicons name="checkmark" size={20} color={theme.accentBright} /> : null}
                </Pressable>
              );
            })}
          </ScrollView>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.55)', justifyContent: 'flex-end' },
  sheet: { borderTopLeftRadius: 18, borderTopRightRadius: 18, paddingTop: 16, paddingHorizontal: 8 },
  title: { fontSize: 17, fontWeight: '700', paddingHorizontal: 12, marginBottom: 8 },
  row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 12, borderRadius: 10 },
  label: { fontSize: 16, fontWeight: '500' },
  detail: { fontSize: 13, marginTop: 2 },
});
