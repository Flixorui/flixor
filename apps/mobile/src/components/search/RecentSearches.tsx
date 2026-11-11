import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../hooks/useTheme';
import LiquidGlass from '../LiquidGlass';

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
          // Home's glass pill, with a remove button at the end
          <View key={query} style={styles.chip}>
            <LiquidGlass radius={12} />
            <Pressable onPress={() => onSelect(query)} style={styles.chipBody}>
              <Ionicons name="time-outline" size={15} color="rgba(255,255,255,0.6)" />
              <Text numberOfLines={1} style={styles.chipText}>
                {query}
              </Text>
            </Pressable>
            <Pressable onPress={() => onRemove(query)} hitSlop={8} accessibilityLabel={`Remove ${query}`} style={styles.remove}>
              <Ionicons name="close" size={15} color="rgba(255,255,255,0.6)" />
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
  chips: { paddingHorizontal: 16, gap: 8 },
  chip: { height: 40, flexDirection: 'row', alignItems: 'center', borderRadius: 12, overflow: 'hidden', maxWidth: 260 },
  chipBody: { height: 40, flexDirection: 'row', alignItems: 'center', gap: 6, paddingLeft: 14, flexShrink: 1 },
  chipText: { color: '#fff', fontSize: 15, fontWeight: '600', flexShrink: 1 },
  remove: { height: 40, justifyContent: 'center', paddingLeft: 8, paddingRight: 12 },
});
