import React from 'react';
import { View, ScrollView, Switch, Text, Pressable, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { useAppSettings } from '../../hooks/useAppSettings';

export default function DetailsScreenSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const headerHeight = insets.top + 52;

  const layoutOptions = [
    { label: 'Tabbed', value: 'tabbed' },
    { label: 'Unified', value: 'unified' },
  ];

  return (
    <View style={styles.container}>
      <SettingsHeader title="Details Screen" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        <SettingsCard title="SCREEN LAYOUT">
          <View style={styles.layoutGroup}>
            <Text style={styles.layoutLabel}>Details Page Style</Text>
            <Text style={styles.layoutDescription}>
              Tabbed shows sections in tabs, Unified shows all content on one scrollable page
            </Text>
            <View style={styles.layoutSegment}>
              {layoutOptions.map((option, index) => {
                const selected = (settings.detailsScreenLayout ?? 'tabbed') === option.value;
                return (
                  <Pressable
                    key={option.value}
                    style={[
                      styles.layoutChip,
                      styles.layoutChipFill,
                      index > 0 && styles.layoutChipDivider,
                      selected && styles.layoutChipActive,
                    ]}
                    onPress={() => updateSetting('detailsScreenLayout', option.value as 'tabbed' | 'unified')}
                  >
                    <Text style={[styles.layoutChipText, selected && styles.layoutChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        </SettingsCard>

        <SettingsCard title="RATINGS DISPLAY">
          <SettingItem
            title="IMDb Rating"
            description="Show IMDb rating on details screen"
            icon="star-outline"
            renderRight={() => (
              <Switch
                value={settings.showIMDbRating ?? true}
                onValueChange={(value) => updateSetting('showIMDbRating', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Rotten Tomatoes (Critics)"
            description="Show critic score from Rotten Tomatoes"
            icon="leaf-outline"
            renderRight={() => (
              <Switch
                value={settings.showRottenTomatoesCritic ?? true}
                onValueChange={(value) => updateSetting('showRottenTomatoesCritic', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Rotten Tomatoes (Audience)"
            description="Show audience score from Rotten Tomatoes"
            icon="people-outline"
            renderRight={() => (
              <Switch
                value={settings.showRottenTomatoesAudience ?? true}
                onValueChange={(value) => updateSetting('showRottenTomatoesAudience', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0b0b0d',
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 40,
  },
  layoutGroup: {
    paddingHorizontal: 14,
    paddingTop: 12,
    paddingBottom: 14,
  },
  layoutLabel: {
    color: '#f9fafb',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 6,
  },
  layoutDescription: {
    color: '#9ca3af',
    fontSize: 12,
    marginBottom: 12,
  },
  layoutSegment: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    overflow: 'hidden',
    height: 44,
    padding: 2,
  },
  layoutChip: {
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 6,
  },
  layoutChipFill: {
    flex: 1,
  },
  layoutChipDivider: {
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(255,255,255,0.08)',
  },
  layoutChipActive: {
    backgroundColor: '#fff',
    borderRadius: 10,
  },
  layoutChipText: {
    color: '#e5e7eb',
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'center',
  },
  layoutChipTextActive: {
    color: '#111827',
  },
});
