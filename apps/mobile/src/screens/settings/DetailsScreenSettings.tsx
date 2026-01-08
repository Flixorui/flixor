import React from 'react';
import { View, ScrollView, Switch, StyleSheet } from 'react-native';
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

  return (
    <View style={styles.container}>
      <SettingsHeader title="Details Screen" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
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
});
