import React from 'react';
import { View, Text, ScrollView, Switch, Pressable, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { useAppSettings } from '../../hooks/useAppSettings';

export default function PlayerSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const headerHeight = insets.top + 52;

  return (
    <View style={styles.container}>
      <SettingsHeader title="Player" onBack={() => nav.goBack()} />
      <ScrollView contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        {/* Playback */}
        <SettingsCard title="PLAYBACK">
          <SettingItem
            title="Auto-Play Next"
            description="Automatically play next episode when current finishes"
            icon="play-forward-outline"
            renderRight={() => (
              <Switch
                value={settings.autoPlayNext}
                onValueChange={(value) => updateSetting('autoPlayNext', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Remember Track Selection"
            description="Remember audio/subtitle language choices"
            icon="list-outline"
            renderRight={() => (
              <Switch
                value={settings.rememberTrackSelections}
                onValueChange={(value) => updateSetting('rememberTrackSelections', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        {/* Auto-Skip */}
        <SettingsCard title="AUTO-SKIP">
          <SettingItem
            title="Skip Intro Automatically"
            description="Auto-skip detected intro segments"
            icon="play-skip-forward-outline"
            renderRight={() => (
              <Switch
                value={settings.skipIntroAutomatically}
                onValueChange={(value) => updateSetting('skipIntroAutomatically', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Skip Credits Automatically"
            description="Auto-skip detected credits segments"
            icon="play-skip-forward-outline"
            renderRight={() => (
              <Switch
                value={settings.skipCreditsAutomatically}
                onValueChange={(value) => updateSetting('skipCreditsAutomatically', value)}
              />
            )}
            isLast={false}
          />
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Skip Delay</Text>
            <Text style={styles.sliderSubtitle}>Seconds before auto-skipping</Text>
            <View style={styles.segmentedControl}>
              {[3, 5, 7, 10].map((delay, index) => {
                const selected = settings.autoSkipDelay === delay;
                return (
                  <Pressable
                    key={delay}
                    style={[
                      styles.segmentedChip,
                      index > 0 && styles.segmentedChipDivider,
                      selected && styles.segmentedChipActive,
                    ]}
                    onPress={() => updateSetting('autoSkipDelay', delay)}
                  >
                    <Text style={[styles.segmentedChipText, selected && styles.segmentedChipTextActive]}>
                      {delay}s
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <View style={[styles.sliderGroup, styles.sliderGroupLast]}>
            <Text style={styles.sliderLabel}>Credits Fallback</Text>
            <Text style={styles.sliderSubtitle}>Seconds before end to show 'Next' when no credits marker</Text>
            <View style={styles.segmentedControl}>
              {[15, 30, 45, 60].map((seconds, index) => {
                const selected = settings.creditsCountdownFallback === seconds;
                return (
                  <Pressable
                    key={seconds}
                    style={[
                      styles.segmentedChip,
                      index > 0 && styles.segmentedChipDivider,
                      selected && styles.segmentedChipActive,
                    ]}
                    onPress={() => updateSetting('creditsCountdownFallback', seconds)}
                  >
                    <Text style={[styles.segmentedChipText, selected && styles.segmentedChipTextActive]}>
                      {seconds}s
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        </SettingsCard>

        {/* Seek Durations */}
        <SettingsCard title="SEEK DURATIONS">
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Small Seek</Text>
            <Text style={styles.sliderSubtitle}>Arrow/tap seek duration</Text>
            <View style={styles.segmentedControl}>
              {[5, 10, 15, 30].map((seconds, index) => {
                const selected = settings.seekTimeSmall === seconds;
                return (
                  <Pressable
                    key={seconds}
                    style={[
                      styles.segmentedChip,
                      index > 0 && styles.segmentedChipDivider,
                      selected && styles.segmentedChipActive,
                    ]}
                    onPress={() => updateSetting('seekTimeSmall', seconds)}
                  >
                    <Text style={[styles.segmentedChipText, selected && styles.segmentedChipTextActive]}>
                      {seconds}s
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <View style={[styles.sliderGroup, styles.sliderGroupLast]}>
            <Text style={styles.sliderLabel}>Large Seek</Text>
            <Text style={styles.sliderSubtitle}>Double-tap or hold seek duration</Text>
            <View style={styles.segmentedControl}>
              {[15, 30, 60, 90].map((seconds, index) => {
                const selected = settings.seekTimeLarge === seconds;
                return (
                  <Pressable
                    key={seconds}
                    style={[
                      styles.segmentedChip,
                      index > 0 && styles.segmentedChipDivider,
                      selected && styles.segmentedChipActive,
                    ]}
                    onPress={() => updateSetting('seekTimeLarge', seconds)}
                  >
                    <Text style={[styles.segmentedChipText, selected && styles.segmentedChipTextActive]}>
                      {seconds}s
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        </SettingsCard>

        {/* Reset */}
        <Pressable
          style={styles.resetButton}
          onPress={() => {
            updateSetting('autoPlayNext', false);
            updateSetting('skipIntroAutomatically', true);
            updateSetting('skipCreditsAutomatically', true);
            updateSetting('autoSkipDelay', 5);
            updateSetting('creditsCountdownFallback', 30);
            updateSetting('seekTimeSmall', 10);
            updateSetting('seekTimeLarge', 30);
            updateSetting('rememberTrackSelections', true);
          }}
        >
          <Text style={styles.resetButtonText}>Reset to Defaults</Text>
        </Pressable>
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
  sliderGroup: {
    paddingHorizontal: 14,
    paddingTop: 12,
    paddingBottom: 4,
  },
  sliderGroupLast: {
    paddingBottom: 14,
  },
  sliderLabel: {
    color: '#f9fafb',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 2,
  },
  sliderSubtitle: {
    color: '#9ca3af',
    fontSize: 12,
    marginBottom: 10,
  },
  segmentedControl: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    overflow: 'hidden',
    height: 44,
    padding: 2,
  },
  segmentedChip: {
    flex: 1,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 6,
  },
  segmentedChipDivider: {
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(255,255,255,0.08)',
  },
  segmentedChipActive: {
    backgroundColor: '#fff',
    borderRadius: 10,
  },
  segmentedChipText: {
    color: '#e5e7eb',
    fontSize: 12,
    fontWeight: '600',
    textAlign: 'center',
  },
  segmentedChipTextActive: {
    color: '#111827',
  },
  resetButton: {
    alignSelf: 'center',
    marginTop: 16,
    paddingVertical: 8,
    paddingHorizontal: 16,
  },
  resetButtonText: {
    color: '#9ca3af',
    fontSize: 12,
    fontWeight: '600',
  },
});
