import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../hooks/useTheme';

/** Recent searches shown above the recommendations while the field is empty. */
export default function RecentSearches({
  searches,
  onSelect,
  onRemove,
  onClear,
}: {
  searches: string[];
  onSelect: (query: string) => void;
  onRemove: (query: string) => void;
  onClear: () => void;
}) {
  const theme = useTheme();
  if (searches.length === 0) return null;

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={[styles.title, { color: theme.textPrimary }]}>Recent Searches</Text>
        <Pressable onPress={onClear} hitSlop={8} accessibilityLabel="Clear recent searches">
          <Text style={[styles.clear, { color: theme.textSecondary }]}>Clear</Text>
        </Pressable>
      </View>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={styles.chips}
      >
        {searches.map((query) => (
          <View key={query} style={[styles.chip, { backgroundColor: theme.surfaceOverlay, borderColor: theme.separator }]}>
            <Pressable onPress={() => onSelect(query)} style={styles.chipBody}>
              <Ionicons name="time-outline" size={14} color={theme.textTertiary} />
              <Text numberOfLines={1} style={[styles.chipText, { color: theme.textPrimary }]}>
                {query}
              </Text>
            </Pressable>
            <Pressable onPress={() => onRemove(query)} hitSlop={8} accessibilityLabel={`Remove ${query}`} style={styles.remove}>
              <Ionicons name="close" size={14} color={theme.textTertiary} />
            </Pressable>
          </View>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { paddingTop: 16 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginHorizontal: 16, marginBottom: 10 },
  title: { fontSize: 18, fontWeight: '700' },
  clear: { fontSize: 14, fontWeight: '600' },
  chips: { paddingHorizontal: 16 },
  chip: { flexDirection: 'row', alignItems: 'center', borderRadius: 16, borderWidth: StyleSheet.hairlineWidth, marginRight: 8, maxWidth: 240 },
  chipBody: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingLeft: 12, paddingVertical: 8, flexShrink: 1 },
  chipText: { fontSize: 14, fontWeight: '500', flexShrink: 1 },
  remove: { paddingHorizontal: 10, paddingVertical: 8 },
});
