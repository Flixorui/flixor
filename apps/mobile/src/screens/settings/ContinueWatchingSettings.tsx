import React from 'react';
import { View, Text, ScrollView, Switch, Pressable, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { useAppSettings } from '../../hooks/useAppSettings';

const TTL_OPTIONS = [
  { label: '15 min', value: 15 * 60 * 1000 },
  { label: '30 min', value: 30 * 60 * 1000 },
  { label: '1 hour', value: 60 * 60 * 1000 },
  { label: '6 hours', value: 6 * 60 * 60 * 1000 },
  { label: '12 hours', value: 12 * 60 * 60 * 1000 },
  { label: '24 hours', value: 24 * 60 * 60 * 1000 },
];

export default function ContinueWatchingSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();

  return (
    <View style={styles.container}>
      <SettingsHeader title="Continue Watching" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight }]}>
        <SettingsCard title="LAYOUT">
          <View style={styles.layoutGroup}>
            <Text style={styles.layoutLabel}>Card Style</Text>
            <View style={styles.layoutSegment}>
              {[
                { label: 'Landscape', value: 'landscape' },
                { label: 'Poster', value: 'poster' },
              ].map((option) => {
                const selected = settings.continueWatchingLayout === option.value;
                return (
                  <Pressable
                    key={option.value}
                    style={[styles.layoutChip, selected && styles.layoutChipActive]}
                    onPress={() => updateSetting('continueWatchingLayout', option.value as 'poster' | 'landscape')}
                  >
                    <Text style={[styles.layoutChipText, selected && styles.layoutChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
            <Text style={styles.layoutDescription}>
              Landscape shows large cards with progress bar. Poster shows traditional vertical cards.
            </Text>
          </View>
        </SettingsCard>

        <SettingsCard title="PLAYBACK">
          <SettingItem
            title="Use Cached Streams"
            description="Open the player directly using saved stream info"
            icon="flash-outline"
            renderRight={() => (
              <Switch
                value={settings.useCachedStreams}
                onValueChange={(value) => updateSetting('useCachedStreams', value)}
              />
            )}
            isLast={!settings.useCachedStreams}
          />
          {!settings.useCachedStreams && (
            <SettingItem
              title="Open Metadata Screen"
              description="When cache is off, open details instead of player"
              icon="information-circle-outline"
              renderRight={() => (
                <Switch
                  value={settings.openMetadataScreenWhenCacheDisabled}
                  onValueChange={(value) => updateSetting('openMetadataScreenWhenCacheDisabled', value)}
                />
              )}
              isLast={true}
            />
          )}
        </SettingsCard>

        {settings.useCachedStreams && (
          <SettingsCard title="CACHE DURATION">
            <View style={styles.ttlGrid}>
              {TTL_OPTIONS.map((option) => {
                const selected = settings.streamCacheTTL === option.value;
                return (
                  <Pressable
                    key={option.label}
                    style={[styles.ttlChip, selected && styles.ttlChipActive]}
                    onPress={() => updateSetting('streamCacheTTL', option.value)}
                  >
                    <Text style={[styles.ttlText, selected && styles.ttlTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
            <Text style={styles.note}>Applies to direct play from Continue Watching.</Text>
          </SettingsCard>
        )}
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
  ttlGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    padding: 14,
  },
  ttlChip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    backgroundColor: 'rgba(255,255,255,0.04)',
  },
  ttlChipActive: {
    backgroundColor: '#fff',
    borderColor: '#fff',
  },
  ttlText: {
    color: '#e5e7eb',
    fontSize: 12,
    fontWeight: '600',
  },
  ttlTextActive: {
    color: '#111827',
  },
  note: {
    color: '#9ca3af',
    fontSize: 12,
    paddingHorizontal: 14,
    paddingBottom: 12,
  },
  layoutGroup: {
    padding: 14,
  },
  layoutLabel: {
    color: '#f9fafb',
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 12,
  },
  layoutSegment: {
    flexDirection: 'row',
    gap: 8,
  },
  layoutChip: {
    flex: 1,
    paddingVertical: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    backgroundColor: 'rgba(255,255,255,0.04)',
    alignItems: 'center',
  },
  layoutChipActive: {
    backgroundColor: 'rgba(229, 160, 13, 0.2)',
    borderColor: '#e5a00d',
  },
  layoutChipText: {
    color: '#9ca3af',
    fontSize: 14,
    fontWeight: '600',
  },
  layoutChipTextActive: {
    color: '#fff',
  },
  layoutDescription: {
    color: '#6b7280',
    fontSize: 12,
    marginTop: 12,
    lineHeight: 16,
  },
});
