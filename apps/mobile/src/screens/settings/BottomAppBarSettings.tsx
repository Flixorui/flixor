import React from 'react';
import { View, ScrollView, Switch, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { useAppSettings } from '../../hooks/useAppSettings';

export default function BottomAppBarSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const headerHeight = insets.top + 52;

  return (
    <View style={styles.container}>
      <SettingsHeader title="Bottom App Bar" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        <SettingsCard title="TABS">
          <SettingItem
            title="New & Hot Tab"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show New & Hot tab in bottom navigation"}
            icon="play-circle-outline"
            renderRight={() => (
              <Switch
                value={settings.showNewHotTab}
                onValueChange={(value) => updateSetting('showNewHotTab', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Downloads Tab"
            description="Show Downloads tab in bottom navigation"
            icon="download-outline"
            renderRight={() => (
              <Switch
                value={settings.showDownloadsTab}
                onValueChange={(value) => updateSetting('showDownloadsTab', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="My List Tab"
            description="Show My List tab in bottom navigation"
            icon="bookmark-outline"
            renderRight={() => (
              <Switch
                value={settings.showMyListTab}
                onValueChange={(value) => updateSetting('showMyListTab', value)}
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
