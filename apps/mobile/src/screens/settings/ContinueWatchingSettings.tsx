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
});
