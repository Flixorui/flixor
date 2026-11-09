import React from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { homeRowTitle, isHeroEligibleRow, orderedHomeRowCatalog, setHomeHeroSource } from '../../core/HomeRowsStore';
import type { AppSettings, HomeHeroSource } from '../../core/SettingsData';
import { useTheme } from '../../hooks/useTheme';

interface Option {
  value: HomeHeroSource;
  label: string;
}

function rowOptions(settings: AppSettings): Option[] {
  return orderedHomeRowCatalog(settings)
    .filter(isHeroEligibleRow)
    .map((row) => ({
      value: `row:${row.id}` as HomeHeroSource,
      label: homeRowTitle(settings.homeRowTitles, row.id, row.defaultTitle),
    }));
}

export function heroSourceLabel(settings: AppSettings): string {
  switch (settings.homeHeroSource) {
    case 'default':
      return 'Default';
    case 'continueWatching':
      return 'Continue Watching';
    case 'myList':
      return 'My List';
    default:
      return rowOptions(settings).find((option) => option.value === settings.homeHeroSource)?.label ?? 'Unavailable row';
  }
}

export default function HeroSourceSheet({
  visible,
  settings,
  onClose,
}: {
  visible: boolean;
  settings: AppSettings;
  onClose: () => void;
}) {
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const options: Option[] = [
    { value: 'default', label: 'Default' },
    { value: 'continueWatching', label: 'Continue Watching' },
    { value: 'myList', label: 'My List' },
    ...rowOptions(settings),
  ];

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable
          style={[styles.sheet, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 12 }]}
          onPress={(event) => event.stopPropagation()}
        >
          <Text style={[styles.title, { color: theme.textPrimary }]}>Hero Source</Text>
          <ScrollView>
            {options.map((option) => {
              const selected = settings.homeHeroSource === option.value;
              return (
                <Pressable
                  key={option.value}
                  style={styles.option}
                  onPress={() => {
                    setHomeHeroSource(option.value);
                    onClose();
                  }}
                >
                  <Text style={[styles.optionText, { color: theme.textPrimary }]} numberOfLines={1}>
                    {option.label}
                  </Text>
                  {selected ? <Ionicons name="checkmark" size={20} color={theme.accentBright} /> : null}
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
  backdrop: { flex: 1, justifyContent: 'flex-end', backgroundColor: 'rgba(0,0,0,0.5)' },
  sheet: { maxHeight: '70%', borderTopLeftRadius: 16, borderTopRightRadius: 16, paddingTop: 16 },
  title: { fontSize: 17, fontWeight: '700', paddingHorizontal: 20, marginBottom: 8 },
  option: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 20, paddingVertical: 14 },
  optionText: { fontSize: 15, flex: 1, marginRight: 12 },
});
