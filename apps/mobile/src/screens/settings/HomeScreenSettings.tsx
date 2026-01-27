import React, { useCallback } from 'react';
import { View, Text, ScrollView, Switch, Pressable, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { useAppSettings } from '../../hooks/useAppSettings';
import { setDiscoveryDisabled } from '../../core/SettingsData';

export default function HomeScreenSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const headerHeight = insets.top + 52;

  return (
    <View style={styles.container}>
      <SettingsHeader title="Home Screen" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        <SettingsCard title="DISCOVERY MODE">
          <SettingItem
            title="Library Only Mode"
            description="Turn off all discovery features. Only show content from your Plex library."
            icon="eye-off-outline"
            renderRight={() => (
              <Switch
                value={settings.discoveryDisabled}
                onValueChange={async (value) => {
                  await setDiscoveryDisabled(value);
                  // Refresh settings state
                  updateSetting('discoveryDisabled', value);
                  if (value) {
                    // Also update the local state for individual toggles
                    updateSetting('showTrendingRows', false);
                    updateSetting('showTraktRows', false);
                    updateSetting('showPlexPopularRow', false);
                    updateSetting('showNewHotTab', false);
                    updateSetting('includeTmdbInSearch', false);
                  }
                }}
                trackColor={{ false: 'rgba(255,255,255,0.2)', true: '#FF6B6B' }}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        <SettingsCard title="HERO">
          <SettingItem
            title="Show Hero"
            description="Display the featured hero row"
            icon="star-outline"
            renderRight={() => (
              <Switch
                value={settings.showHeroSection}
                onValueChange={(value) => updateSetting('showHeroSection', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        {settings.showHeroSection && (
          <SettingsCard title="HERO LAYOUT">
            <View style={styles.posterGroup}>
              <Text style={styles.posterLabel}>Hero Layout</Text>
              <View style={styles.posterSegment}>
                {[
                  { label: 'Netflix', value: 'legacy' },
                  { label: 'Carousel', value: 'carousel' },
                  { label: 'Apple TV', value: 'appletv' },
                ].map((option, index) => {
                  const selected = settings.heroLayout === option.value;
                  return (
                    <Pressable
                      key={option.value}
                      style={[
                        styles.posterChip,
                        styles.posterChipFill,
                        index > 0 && styles.posterChipDivider,
                        selected && styles.posterChipActive,
                      ]}
                      onPress={() => updateSetting('heroLayout', option.value as any)}
                    >
                      <Text style={[styles.posterChipText, selected && styles.posterChipTextActive]}>
                        {option.label}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>
            </View>
          </SettingsCard>
        )}

        <SettingsCard title="ROWS">
          <SettingItem
            title="Continue Watching"
            description="Show continue watching row"
            icon="play-outline"
            renderRight={() => (
              <Switch
                value={settings.showContinueWatchingRow}
                onValueChange={(value) => updateSetting('showContinueWatchingRow', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Trending"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show TMDB trending rows"}
            icon="stats-chart-outline"
            renderRight={() => (
              <Switch
                value={settings.showTrendingRows}
                onValueChange={(value) => updateSetting('showTrendingRows', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Trakt Rows"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show Trakt watchlist, history, and recs"}
            icon="layers-outline"
            renderRight={() => (
              <Switch
                value={settings.showTraktRows}
                onValueChange={(value) => updateSetting('showTraktRows', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Trakt Continue Watching"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show in-progress items synced from Trakt"}
            icon="time-outline"
            renderRight={() => (
              <Switch
                value={settings.showTraktContinueWatching}
                onValueChange={(value) => updateSetting('showTraktContinueWatching', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Popular on Plex"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show Plex popularity row"}
            icon="flame-outline"
            renderRight={() => (
              <Switch
                value={settings.showPlexPopularRow}
                onValueChange={(value) => updateSetting('showPlexPopularRow', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Collections"
            description="Show Plex collection rows on home"
            icon="albums-outline"
            renderRight={() => (
              <Switch
                value={settings.showCollectionRows}
                onValueChange={(value) => updateSetting('showCollectionRows', value)}
              />
            )}
            isLast={!settings.showCollectionRows}
          />
          {settings.showCollectionRows && (
            <SettingItem
              title="Manage Collections"
              description="Choose which collections appear"
              icon="sparkles-outline"
              renderRight={() => (
                <Ionicons name="chevron-forward" size={18} color="#9ca3af" />
              )}
              onPress={() => nav.navigate('CollectionRowsSettings')}
              isLast={true}
            />
          )}
        </SettingsCard>

        <SettingsCard title="POSTERS">
          <SettingItem
            title="Show Titles"
            description="Display title text below each poster"
            icon="image-outline"
            renderRight={() => (
              <Switch
                value={settings.showPosterTitles}
                onValueChange={(value) => updateSetting('showPosterTitles', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Library Titles"
            description="Display title text in Library grid"
            icon="library-outline"
            renderRight={() => (
              <Switch
                value={settings.showLibraryTitles}
                onValueChange={(value) => updateSetting('showLibraryTitles', value)}
              />
            )}
            isLast={false}
          />
          <View style={styles.posterGroup}>
            <Text style={styles.posterLabel}>Poster Size</Text>
            <View style={styles.posterSegment}>
              {['small', 'medium', 'large'].map((size, index) => {
                const selected = settings.posterSize === size;
                return (
                  <Pressable
                    key={size}
                    style={[
                      styles.posterChip,
                      styles.posterChipFill,
                      index > 0 && styles.posterChipDivider,
                      selected && styles.posterChipActive,
                    ]}
                    onPress={() => updateSetting('posterSize', size as any)}
                  >
                    <Text style={[styles.posterChipText, selected && styles.posterChipTextActive]}>
                      {size.charAt(0).toUpperCase() + size.slice(1)}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <View style={[styles.posterGroup, styles.posterGroupLast]}>
            <Text style={styles.posterLabel}>Poster Corners</Text>
            <View style={styles.posterSegment}>
              {[
                { label: 'Square', value: 0 },
                { label: 'Rounded', value: 12 },
                { label: 'Pill', value: 20 },
              ].map((option, index) => {
                const selected = settings.posterBorderRadius === option.value;
                return (
                  <Pressable
                    key={option.label}
                    style={[
                      styles.posterChip,
                      styles.posterChipFill,
                      index > 0 && styles.posterChipDivider,
                      selected && styles.posterChipActive,
                    ]}
                    onPress={() => updateSetting('posterBorderRadius', option.value)}
                  >
                    <Text style={[styles.posterChipText, selected && styles.posterChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
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
  posterGroup: {
    paddingHorizontal: 14,
    paddingTop: 12,
    paddingBottom: 4,
  },
  posterGroupLast: {
    paddingBottom: 14,
  },
  posterLabel: {
    color: '#f9fafb',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 10,
  },
  posterSegment: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    overflow: 'hidden',
    height: 44,
    padding: 2,
  },
  posterChip: {
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 6,
  },
  posterChipFill: {
    flex: 1,
  },
  posterChipDivider: {
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(255,255,255,0.08)',
  },
  posterChipActive: {
    backgroundColor: '#fff',
    borderRadius: 10,
  },
  posterChipText: {
    color: '#e5e7eb',
    fontSize: 12,
    fontWeight: '600',
    textAlign: 'center',
  },
  posterChipTextActive: {
    color: '#111827',
  },
});
