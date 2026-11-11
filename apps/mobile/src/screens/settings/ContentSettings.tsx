/**
 * Content: which libraries show, Library Only mode and search sources on one page.
 * Replaces the separate Catalogs, Discovery Mode and Search pages.
 * macOS reference: Views/Settings/SettingsView.swift (ContentSettingsView)
 */

import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, ScrollView, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { fetchAllLibraries } from '../../core/HomeData';
import { setDiscoveryDisabled } from '../../core/SettingsData';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useAppMode } from '../../core/AppMode';
import { useTheme } from '../../hooks/useTheme';

type LibraryItem = { key: string; title: string; type: string };

export default function ContentSettings() {
  const nav: any = useNavigation();
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();
  const { isStremioOnly } = useAppMode();
  const [libraries, setLibraries] = useState<LibraryItem[]>([]);
  const [loading, setLoading] = useState(!isStremioOnly);

  useEffect(() => {
    if (isStremioOnly) return;
    (async () => {
      setLibraries(await fetchAllLibraries());
      setLoading(false);
    })();
  }, [isStremioOnly]);

  const enabledKeys = useMemo(() => new Set(settings.enabledLibraryKeys || []), [settings.enabledLibraryKeys]);
  const isDefaultAll = !settings.enabledLibraryKeys || settings.enabledLibraryKeys.length === 0;

  const toggleLibrary = async (key: string, enabled: boolean) => {
    const allKeys = libraries.map((lib) => String(lib.key));
    const base = isDefaultAll ? allKeys : Array.from(enabledKeys);
    const next = enabled ? Array.from(new Set([...base, key])) : base.filter((k) => k !== key);
    const normalized = next.filter((k) => allKeys.includes(k));
    // Every library on (or none) is stored as "all", so new libraries show up automatically
    const useAll = normalized.length === 0 || normalized.length === allKeys.length;
    await updateSetting('enabledLibraryKeys', useAll ? [] : normalized);
  };

  const setLibraryOnly = async (value: boolean) => {
    await setDiscoveryDisabled(value);
    updateSetting('discoveryDisabled', value);
    if (value) {
      updateSetting('showTrendingRows', false);
      updateSetting('showTraktRows', false);
      updateSetting('showPlexPopularRow', false);
      updateSetting('showNewHotTab', false);
      updateSetting('includeTmdbInSearch', false);
    }
  };

  const libraryOnly = settings.discoveryDisabled;

  return (
    <View style={[styles.container, { backgroundColor: theme.settingsBackground }]}>
      <SettingsHeader title="Content" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        {!isStremioOnly && (
          <>
            <SettingsCard title="LIBRARIES">
              {loading && (
                <View style={styles.messageRow}>
                  <Ionicons name="cloud-download-outline" size={18} color="#9ca3af" />
                  <Text style={styles.messageText}>Loading libraries…</Text>
                </View>
              )}
              {!loading && libraries.length === 0 && (
                <View style={styles.messageRow}>
                  <Text style={styles.messageText}>No Plex libraries found.</Text>
                </View>
              )}
              {!loading &&
                libraries.map((lib) => {
                  const key = String(lib.key);
                  const kind = lib.type === 'movie' ? 'Movies' : 'TV Shows';
                  return (
                    <SettingItem
                      key={key}
                      title={lib.title}
                      // No subtitle when it would only repeat the name ("Movies / Movies")
                      description={lib.title.trim().toLowerCase() === kind.toLowerCase() ? undefined : kind}
                      icon={lib.type === 'movie' ? 'film-outline' : 'tv-outline'}
                      renderRight={() => (
                        <SettingsSwitch
                          value={isDefaultAll || enabledKeys.has(key)}
                          onValueChange={(value) => toggleLibrary(key, value)}
                        />
                      )}
                      isLast={false}
                    />
                  );
                })}
              <SettingItem
                title="Library Mapping"
                description="Libraries behind the Movies and Shows chips"
                icon="layers-outline"
                renderRight={() => <Ionicons name="chevron-forward" size={18} color="#9ca3af" />}
                onPress={() => nav.navigate('LibraryMappingSettings')}
                isLast={true}
              />
            </SettingsCard>
            <Text style={styles.note}>Turned-off libraries are hidden from Home, Browse and Library.</Text>

            <SettingsCard title="DISCOVERY">
              <SettingItem
                title="Library Only"
                description="Hide Trending, Trakt picks, Popular on Plex, New & Hot and TMDB results"
                icon="eye-off-outline"
                renderRight={() => <SettingsSwitch value={libraryOnly} onValueChange={setLibraryOnly} />}
                isLast={true}
              />
            </SettingsCard>
          </>
        )}

        <SettingsCard title="SEARCH">
          <SettingItem
            title="TMDB Results"
            description={libraryOnly ? 'Off while Library Only is on' : 'Show TMDB movies and shows in search'}
            icon="search-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.includeTmdbInSearch}
                onValueChange={(value) => updateSetting('includeTmdbInSearch', value)}
                disabled={libraryOnly}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Addon Catalogs"
            description={
              !settings.stremioPlaybackEnabled
                ? 'Turn on Stremio addons to use this'
                : libraryOnly
                  ? 'Off while Library Only is on'
                  : 'Include results from your installed addons'
            }
            icon="extension-puzzle-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.stremioCatalogSearchEnabled}
                onValueChange={(value) => updateSetting('stremioCatalogSearchEnabled', value)}
                disabled={!settings.stremioPlaybackEnabled || libraryOnly}
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
  container: { flex: 1 },
  content: { paddingHorizontal: 16 },
  messageRow: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 14, paddingVertical: 14 },
  messageText: { color: '#9ca3af', fontSize: 13 },
  note: { color: '#9ca3af', fontSize: 12, marginTop: -6, marginBottom: 18, paddingHorizontal: 4 },
});
