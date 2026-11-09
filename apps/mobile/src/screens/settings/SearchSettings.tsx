import React from 'react';
import { View, ScrollView, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { useAppSettings } from '../../hooks/useAppSettings';

export default function SearchSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const headerHeight = insets.top + 52;

  return (
    <View style={styles.container}>
      <SettingsHeader title="Search" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        <SettingsCard title="SOURCES">
          <SettingItem
            title="Include TMDB Results"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show TMDB movies and shows in search"}
            icon="search-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.includeTmdbInSearch}
                onValueChange={(value) => updateSetting('includeTmdbInSearch', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Search Addon Catalogs"
            description={
              !settings.stremioPlaybackEnabled
                ? "Turn on Stremio addons to use this"
                : settings.discoveryDisabled
                  ? "Disabled by Library Only Mode"
                  : "Include results from your installed addons"
            }
            icon="extension-puzzle-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.stremioCatalogSearchEnabled}
                onValueChange={(value) => updateSetting('stremioCatalogSearchEnabled', value)}
                disabled={!settings.stremioPlaybackEnabled || settings.discoveryDisabled}
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
});
