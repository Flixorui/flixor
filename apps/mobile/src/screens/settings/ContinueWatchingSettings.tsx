import React from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import { useAppMode } from '../../core/AppMode';
import { getFlixorCore } from '../../core/index';
import { setContinueWatchingSource } from '../../core/HomeRowsStore';
import { effectiveContinueWatchingSource } from '../../core/TraktContinueWatching';
import type { ContinueWatchingSort, ContinueWatchingSource } from '../../core/SettingsData';

const TTL_OPTIONS = [
  { label: '15 min', value: 15 * 60 * 1000 },
  { label: '30 min', value: 30 * 60 * 1000 },
  { label: '1 hour', value: 60 * 60 * 1000 },
  { label: '6 hours', value: 6 * 60 * 60 * 1000 },
  { label: '12 hours', value: 12 * 60 * 60 * 1000 },
  { label: '24 hours', value: 24 * 60 * 60 * 1000 },
];

const SORT_OPTIONS: Array<{ label: string; value: ContinueWatchingSort }> = [
  { label: 'Recent', value: 'recent' },
  { label: 'Next Up First', value: 'nextEpisodeFirst' },
  { label: 'Title', value: 'title' },
];

export default function ContinueWatchingSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();
  const theme = useTheme();
  const { isStremioOnly } = useAppMode();
  const activeLayoutColor = theme.chosenAccent ?? '#e5a00d';
  const traktConnected = getFlixorCore().isTraktAuthenticated;
  const source = effectiveContinueWatchingSource({ ...settings, discoveryDisabled: false });
  const sourceOptions: Array<{ label: string; value: ContinueWatchingSource }> = [
    { label: 'Automatic', value: 'automatic' },
    { label: isStremioOnly ? 'This Device' : 'Plex Only', value: 'library' },
    { label: 'Trakt Only', value: 'trakt' },
  ];

  return (
    <View style={styles.container}>
      <SettingsHeader title="Continue Watching" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
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
                    style={[
                      styles.layoutChip,
                      selected && { backgroundColor: `${activeLayoutColor}33`, borderColor: activeLayoutColor },
                    ]}
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

        <SettingsCard title="SOURCE">
          <View style={styles.layoutGroup}>
            <Text style={styles.layoutLabel}>Continue Watching From</Text>
            <View style={styles.layoutSegment}>
              {sourceOptions.map((option) => {
                const selected = source === option.value;
                return (
                  <Pressable
                    key={option.value}
                    style={[
                      styles.layoutChip,
                      selected && { backgroundColor: `${activeLayoutColor}33`, borderColor: activeLayoutColor },
                    ]}
                    onPress={() => setContinueWatchingSource(option.value)}
                  >
                    <Text style={[styles.layoutChipText, selected && styles.layoutChipTextActive]}>{option.label}</Text>
                  </Pressable>
                );
              })}
            </View>
            <Text style={styles.layoutDescription}>
              {settings.discoveryDisabled
                ? 'Library Only Mode keeps Trakt out of this row.'
                : traktConnected
                  ? 'Automatic combines your library with Trakt progress and next episodes.'
                  : 'Connect Trakt in Settings to include your Trakt progress.'}
            </Text>
          </View>
        </SettingsCard>

        <SettingsCard title="ORDER AND SPOILERS">
          <View style={styles.layoutGroup}>
            <Text style={styles.layoutLabel}>Sort Order</Text>
            <View style={styles.layoutSegment}>
              {SORT_OPTIONS.map((option) => {
                const selected = settings.continueWatchingSort === option.value;
                return (
                  <Pressable
                    key={option.value}
                    style={[
                      styles.layoutChip,
                      selected && { backgroundColor: `${activeLayoutColor}33`, borderColor: activeLayoutColor },
                    ]}
                    onPress={() => updateSetting('continueWatchingSort', option.value)}
                  >
                    <Text style={[styles.layoutChipText, selected && styles.layoutChipTextActive]}>{option.label}</Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <SettingItem
            title="Blur Next-Up Thumbnails"
            description="Hide artwork of episodes you haven't started"
            icon="eye-off-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.continueWatchingBlurNextUp}
                onValueChange={(value) => updateSetting('continueWatchingBlurNextUp', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        <SettingsCard title="PLAYBACK">
          <SettingItem
            title="Use Cached Streams"
            description="Open the player directly using saved alternate stream info when it is still valid"
            icon="flash-outline"
            renderRight={() => (
              <SettingsSwitch
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
                <SettingsSwitch
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
            <Text style={styles.note}>Applies to cached alternate sources such as Stremio playback.</Text>
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
