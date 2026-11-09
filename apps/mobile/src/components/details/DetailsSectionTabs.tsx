import React from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { DETAILS_SECTION_META } from '../../core/DetailsSectionsStore';
import type { DetailsSectionKey } from '../../core/SettingsData';
import { useTheme } from '../../hooks/useTheme';
import { DetailsSectionStyle } from './DetailsSectionHeading';

/** The tabbed layout's bar: one tab per visible section, in the user's order. */
export default function DetailsSectionTabs({
  sections,
  active,
  onSelect,
}: {
  sections: DetailsSectionKey[];
  active: DetailsSectionKey;
  onSelect: (key: DetailsSectionKey) => void;
}) {
  const theme = useTheme();
  return (
    <View style={{ marginTop: 18 }}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: DetailsSectionStyle.inset }}>
        {sections.map((key) => {
          const selected = key === active;
          return (
            <Pressable
              key={key}
              onPress={() => onSelect(key)}
              style={{ marginRight: 24 }}
              accessibilityRole="tab"
              accessibilityState={{ selected }}
            >
              <Text style={{ color: theme.textPrimary, fontWeight: '900', letterSpacing: 1.2, fontSize: 14 }}>
                {DETAILS_SECTION_META[key].tabLabel.toUpperCase()}
              </Text>
              <View style={{ height: 4, marginTop: 6, borderRadius: 2, backgroundColor: selected ? theme.chosenAccent ?? '#fff' : 'transparent' }} />
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}
