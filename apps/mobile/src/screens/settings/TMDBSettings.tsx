import React, { useMemo, useState } from 'react';
import { View, Text, ScrollView, TextInput, Pressable, StyleSheet, Switch } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { useAppSettings } from '../../hooks/useAppSettings';
import { reinitializeFlixorCore } from '../../core';

const LANGUAGE_OPTIONS = [
  { label: 'English', value: 'en' },
  { label: 'Spanish', value: 'es' },
  { label: 'French', value: 'fr' },
  { label: 'German', value: 'de' },
  { label: 'Japanese', value: 'ja' },
];

export default function TMDBSettings() {
  const nav: any = useNavigation();
  const { settings, updateSetting } = useAppSettings();
  const [apiKey, setApiKey] = useState(settings.tmdbApiKey || '');
  const hasKey = useMemo(() => apiKey.trim().length > 0, [apiKey]);

  const saveKey = async () => {
    const trimmed = apiKey.trim();
    await updateSetting('tmdbApiKey', trimmed.length ? trimmed : undefined);
    await reinitializeFlixorCore();
  };

  const setLanguage = async (value: string) => {
    await updateSetting('tmdbLanguagePreference', value);
    await reinitializeFlixorCore();
  };

  return (
    <View style={styles.container}>
      <SettingsHeader title="TMDB" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={styles.content}>
        <SettingsCard title="API KEY">
          <View style={styles.inputWrap}>
            <TextInput
              value={apiKey}
              onChangeText={setApiKey}
              placeholder="Enter your TMDB API key"
              placeholderTextColor="#6b7280"
              style={styles.input}
              autoCapitalize="none"
              autoCorrect={false}
            />
            <Pressable style={styles.saveButton} onPress={saveKey}>
              <Text style={styles.saveButtonText}>{hasKey ? 'Save Key' : 'Clear Key'}</Text>
            </Pressable>
          </View>
          <Text style={styles.note}>Leave empty to use the default app key.</Text>
        </SettingsCard>

        <SettingsCard title="METADATA">
          <SettingItem
            title="Enrich Metadata"
            description="Fetch cast, logos, and extras"
            icon="film-outline"
            renderRight={() => (
              <Switch
                value={settings.enrichMetadataWithTMDB}
                onValueChange={(value) => updateSetting('enrichMetadataWithTMDB', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Localized Metadata"
            description="Prefer localized titles and summaries"
            icon="language-outline"
            renderRight={() => (
              <Switch
                value={settings.useTmdbLocalizedMetadata}
                onValueChange={(value) => updateSetting('useTmdbLocalizedMetadata', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        <SettingsCard title="LANGUAGE">
          <View style={styles.languageGrid}>
            {LANGUAGE_OPTIONS.map((option) => {
              const selected = settings.tmdbLanguagePreference === option.value;
              return (
                  <Pressable
                    key={option.value}
                    style={[styles.langChip, selected && styles.langChipActive]}
                  onPress={() => setLanguage(option.value)}
                  >
                  <Text style={[styles.langText, selected && styles.langTextActive]}>
                    {option.label}
                  </Text>
                </Pressable>
              );
            })}
          </View>
          <Text style={styles.note}>Applies to TMDB requests and logo localization.</Text>
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
  inputWrap: {
    padding: 14,
    gap: 10,
  },
  input: {
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    color: '#fff',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  saveButton: {
    backgroundColor: '#fff',
    borderRadius: 10,
    paddingVertical: 10,
    alignItems: 'center',
  },
  saveButtonText: {
    color: '#0b0b0d',
    fontWeight: '700',
  },
  note: {
    color: '#9ca3af',
    fontSize: 12,
    paddingHorizontal: 14,
    paddingBottom: 12,
  },
  languageGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    padding: 14,
  },
  langChip: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    backgroundColor: 'rgba(255,255,255,0.04)',
  },
  langChipActive: {
    backgroundColor: '#fff',
    borderColor: '#fff',
  },
  langText: {
    color: '#e5e7eb',
    fontSize: 12,
    fontWeight: '600',
  },
  langTextActive: {
    color: '#111827',
  },
});
