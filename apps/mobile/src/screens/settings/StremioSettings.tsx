import React, { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View, Animated } from 'react-native';
import { useFocusEffect, useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import StreamSelectionSettings from '../../components/stremio/StreamSelectionSettings';
import { useAppSettings } from '../../hooks/useAppSettings';
import { stremioService } from '../../stremio/StremioService';

export default function StremioSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();
  const [addonCount, setAddonCount] = useState(0);

  useFocusEffect(
    useCallback(() => {
      (async () => {
        const addons = await stremioService.getInstalledAddons();
        setAddonCount(addons.length);
      })();
    }, [])
  );

  return (
    <View style={styles.container}>
      <SettingsHeader scrollY={headerScrollY} title="Stremio" onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
        contentContainerStyle={[
          styles.content,
          { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 },
        ]}
      >
        <SettingsCard title="PLAYBACK">
          <SettingItem
            title="Enable Stremio Playback"
            description="Show Stremio actions on supported mobile details screens"
            icon="play-circle-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.stremioPlaybackEnabled}
                onValueChange={async (value) => {
                  await updateSetting('stremioPlaybackEnabled', value);
                  if (value) {
                    await stremioService.ensureInitialized({ installDefaults: true });
                    const addons = await stremioService.getInstalledAddons();
                    setAddonCount(addons.length);
                  }
                }}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Manage Addons"
            description={
              addonCount > 0
                ? `${addonCount} addon${addonCount === 1 ? '' : 's'} installed`
                : 'Install and order stream or subtitle addons'
            }
            icon="extension-puzzle-outline"
            renderRight={() => <Text style={styles.chevron}>›</Text>}
            onPress={() => nav.navigate('StremioAddons')}
            isLast={false}
          />
          <SettingItem
            title="Show On TMDB Details"
            description="Display Stremio actions on TMDB-backed details pages when IDs can be mapped"
            icon="film-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.stremioShowOnTmdbDetails}
                onValueChange={(value) => updateSetting('stremioShowOnTmdbDetails', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Prefer Cached Resume"
            description="Highlight and reopen the last saved Stremio stream when available"
            icon="time-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.stremioPreferCachedSourceResume}
                onValueChange={(value) => updateSetting('stremioPreferCachedSourceResume', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Enable Subtitle Addons"
            description="Fetch external subtitles from subtitle-capable Stremio addons"
            icon="text-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.stremioSubtitleAddonsEnabled}
                onValueChange={(value) => updateSetting('stremioSubtitleAddonsEnabled', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Show Addon Catalogs on Home"
            description="Add rows from the catalogs your addons provide to the Home screen"
            icon="albums-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showStremioCatalogRows}
                onValueChange={(value) => updateSetting('showStremioCatalogRows', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        <StreamSelectionSettings />

        <SettingsCard title="SOURCE VISIBILITY">
          <View style={styles.segmentGroup}>
            {[
              { value: 'show_disabled', label: 'Show Disabled' },
              { value: 'hide', label: 'Hide Unsupported' },
            ].map((option) => {
              const selected = settings.stremioUnsupportedSourceVisibility === option.value;
              return (
                <Text
                  key={option.value}
                  onPress={() =>
                    updateSetting(
                      'stremioUnsupportedSourceVisibility',
                      option.value as 'show_disabled' | 'hide'
                    )
                  }
                  style={[styles.segment, selected && styles.segmentSelected]}
                >
                  {option.label}
                </Text>
              );
            })}
          </View>
          <Text style={styles.note}>
            Unsupported entries include torrents, archive streams, and external-only URLs that cannot be played in-app.
          </Text>
        </SettingsCard>

        <SettingsCard title="NOTE">
          <View style={styles.noteCard}>
            <Text style={styles.noteText}>
              Plex login still powers app access, library context, and the default play path. Stremio is an alternate playback provider, not a standalone mode.
            </Text>
          </View>
        </SettingsCard>
      </Animated.ScrollView>
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
  },
  chevron: {
    color: '#9ca3af',
    fontSize: 24,
    lineHeight: 24,
  },
  segmentGroup: {
    flexDirection: 'row',
    gap: 8,
    padding: 14,
  },
  segment: {
    flex: 1,
    overflow: 'hidden',
    textAlign: 'center',
    color: '#d1d5db',
    fontSize: 13,
    fontWeight: '700',
    paddingVertical: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    backgroundColor: 'rgba(255,255,255,0.04)',
  },
  segmentSelected: {
    color: '#111827',
    backgroundColor: '#ffffff',
    borderColor: '#ffffff',
  },
  note: {
    color: '#9ca3af',
    fontSize: 12,
    lineHeight: 17,
    paddingHorizontal: 14,
    paddingBottom: 14,
  },
  noteCard: {
    padding: 14,
  },
  noteText: {
    color: '#d1d5db',
    fontSize: 13,
    lineHeight: 20,
  },
});
