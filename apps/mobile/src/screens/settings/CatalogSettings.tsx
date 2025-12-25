import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, ScrollView, Switch, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { fetchAllLibraries } from '../../core/HomeData';
import { useAppSettings } from '../../hooks/useAppSettings';

type LibraryItem = { key: string; title: string; type: string };

export default function CatalogSettings() {
  const nav: any = useNavigation();
  const { settings, updateSetting } = useAppSettings();
  const [libraries, setLibraries] = useState<LibraryItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const libs = await fetchAllLibraries();
      setLibraries(libs);
      setLoading(false);
    })();
  }, []);

  const enabledKeys = useMemo(() => new Set(settings.enabledLibraryKeys || []), [settings.enabledLibraryKeys]);
  const isDefaultAll = !settings.enabledLibraryKeys || settings.enabledLibraryKeys.length === 0;

  const updateEnabledKeys = async (nextKeys: string[]) => {
    const allKeys = libraries.map((lib) => String(lib.key));
    const normalized = nextKeys.filter((key) => allKeys.includes(key));
    const shouldUseDefaultAll = normalized.length === 0 || normalized.length === allKeys.length;
    await updateSetting('enabledLibraryKeys', shouldUseDefaultAll ? [] : normalized);
  };

  const toggleLibrary = async (key: string, enabled: boolean) => {
    const allKeys = libraries.map((lib) => String(lib.key));
    if (enabled) {
      const next = isDefaultAll ? allKeys : Array.from(new Set([...enabledKeys, key]));
      await updateEnabledKeys(next);
    } else {
      const base = isDefaultAll ? allKeys : Array.from(enabledKeys);
      const next = base.filter((k) => k !== key);
      await updateEnabledKeys(next);
    }
  };

  return (
    <View style={styles.container}>
      <SettingsHeader title="Catalogs" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={styles.content}>
        <SettingsCard title="LIBRARIES">
          {loading && (
            <View style={styles.loadingRow}>
              <Ionicons name="cloud-download-outline" size={18} color="#9ca3af" />
              <Text style={styles.loadingText}>Loading libraries…</Text>
            </View>
          )}
          {!loading && libraries.length === 0 && (
            <View style={styles.loadingRow}>
              <Text style={styles.loadingText}>No Plex libraries found.</Text>
            </View>
          )}
          {!loading && libraries.map((lib, index) => {
            const key = String(lib.key);
            const enabled = isDefaultAll ? true : enabledKeys.has(key);
            return (
              <SettingItem
                key={key}
                title={lib.title}
                description={lib.type === 'movie' ? 'Movies' : 'TV Shows'}
                icon={lib.type === 'movie' ? 'film-outline' : 'tv-outline'}
                renderRight={() => (
                  <Switch value={enabled} onValueChange={(value) => toggleLibrary(key, value)} />
                )}
                isLast={index === libraries.length - 1}
              />
            );
          })}
        </SettingsCard>

        <Text style={styles.note}>
          Disabled libraries are hidden from Browse and Library screens.
        </Text>
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
  loadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 14,
    paddingVertical: 14,
  },
  loadingText: {
    color: '#9ca3af',
    fontSize: 13,
  },
  note: {
    color: '#9ca3af',
    fontSize: 12,
    marginTop: 6,
  },
});
