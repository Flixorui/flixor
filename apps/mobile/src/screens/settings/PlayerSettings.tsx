import React from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet, TextInput } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { useAppSettings } from '../../hooks/useAppSettings';
import { PLAYBACK_SPEED_PRESETS, formatSpeed } from '../../components/player/panels/SpeedPanel';
import { SUBTITLE_TEXT_COLORS } from '../../components/player/panels/SubtitlePanel';

export default function PlayerSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const headerHeight = insets.top + 52;

  const segmented = <T,>(
    options: Array<{ label: string; value: T }>,
    selected: T,
    onSelect: (value: T) => void
  ) => (
    <View style={styles.segmentedControl}>
      {options.map((option, index) => {
        const isSelected = option.value === selected;
        return (
          <Pressable
            key={option.label}
            style={[styles.segmentedChip, index > 0 && styles.segmentedChipDivider, isSelected && styles.segmentedChipActive]}
            onPress={() => onSelect(option.value)}
          >
            <Text style={[styles.segmentedChipText, isSelected && styles.segmentedChipTextActive]}>{option.label}</Text>
          </Pressable>
        );
      })}
    </View>
  );

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
              <SettingsSwitch
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
              <SettingsSwitch
                value={settings.rememberTrackSelections}
                onValueChange={(value) => updateSetting('rememberTrackSelections', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Streams Backdrop"
            description="Dim the backdrop behind the player's source and track panels"
            icon="image-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.enableStreamsBackdrop}
                onValueChange={(value) => updateSetting('enableStreamsBackdrop', value)}
              />
            )}
            isLast={false}
          />
          <View style={[styles.sliderGroup, styles.sliderGroupLast]}>
            <Text style={styles.sliderLabel}>Default Speed</Text>
            <Text style={styles.sliderSubtitle}>Speed each video starts at</Text>
            {segmented(
              PLAYBACK_SPEED_PRESETS.filter((speed) => speed >= 0.75 && speed !== 1.75).map((speed) => ({
                label: formatSpeed(speed),
                value: speed,
              })),
              settings.defaultPlaybackSpeed,
              (speed) => updateSetting('defaultPlaybackSpeed', speed)
            )}
          </View>
        </SettingsCard>

        <SettingsCard title="SUBTITLE STYLE">
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Size</Text>
            {segmented(
              [35, 45, 55, 65, 75].map((size) => ({ label: String(size), value: size })),
              settings.subtitleFontSize,
              (size) => updateSetting('subtitleFontSize', size)
            )}
          </View>
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Color</Text>
            {segmented(
              SUBTITLE_TEXT_COLORS.map((option) => ({ label: option.name, value: option.hex })),
              settings.subtitleTextColor.toUpperCase(),
              (hex) => updateSetting('subtitleTextColor', hex)
            )}
          </View>
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Outline</Text>
            {segmented(
              [0, 1, 2, 3, 4, 5].map((size) => ({ label: String(size), value: size })),
              settings.subtitleBorderSize,
              (size) => updateSetting('subtitleBorderSize', size)
            )}
          </View>
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Position</Text>
            <Text style={styles.sliderSubtitle}>100 is the bottom of the screen</Text>
            {segmented(
              [70, 80, 90, 95, 100].map((position) => ({ label: String(position), value: position })),
              settings.subtitlePosition,
              (position) => updateSetting('subtitlePosition', position)
            )}
          </View>
          <SettingItem
            title="Remove Hearing-Impaired Text"
            description="Strip [MUSIC], (laughs) and speaker labels from addon subtitles"
            icon="ear-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.subtitleFilterSDH}
                onValueChange={(value) => updateSetting('subtitleFilterSDH', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        <SettingsCard title="TRACK PREFERENCES">
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Preferred Subtitle Language</Text>
            <Text style={styles.sliderSubtitle}>Used for embedded and addon subtitles when auto-select is enabled</Text>
            <View style={styles.segmentedControl}>
              {[
                { label: 'Off', value: undefined },
                { label: 'English', value: 'en' },
                { label: 'Spanish', value: 'es' },
                { label: 'French', value: 'fr' },
              ].map((option, index) => {
                const selected = settings.preferredSubtitleLanguage === option.value;
                return (
                  <Pressable
                    key={option.label}
                    style={[
                      styles.segmentedChip,
                      index > 0 && styles.segmentedChipDivider,
                      selected && styles.segmentedChipActive,
                    ]}
                    onPress={() => updateSetting('preferredSubtitleLanguage', option.value)}
                  >
                    <Text style={[styles.segmentedChipText, selected && styles.segmentedChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Preferred Audio Language</Text>
            <Text style={styles.sliderSubtitle}>Select a preferred spoken language when multiple audio tracks exist</Text>
            <View style={styles.segmentedControl}>
              {[
                { label: 'System', value: undefined },
                { label: 'Original', value: 'original' },
                { label: 'English', value: 'en' },
                { label: 'Japanese', value: 'ja' },
                { label: 'Spanish', value: 'es' },
              ].map((option, index) => {
                const selected = settings.preferredAudioLanguage === option.value;
                return (
                  <Pressable
                    key={option.label}
                    style={[
                      styles.segmentedChip,
                      index > 0 && styles.segmentedChipDivider,
                      selected && styles.segmentedChipActive,
                    ]}
                    onPress={() => updateSetting('preferredAudioLanguage', option.value)}
                  >
                    <Text style={[styles.segmentedChipText, selected && styles.segmentedChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <View style={styles.sliderGroup}>
            <Text style={styles.sliderLabel}>Subtitle Source Preference</Text>
            <Text style={styles.sliderSubtitle}>Choose whether internal or external subtitles are preferred during auto-select</Text>
            <View style={styles.segmentedControl}>
              {[
                { label: 'Internal', value: 'internal' },
                { label: 'External', value: 'external' },
                { label: 'Any', value: 'any' },
              ].map((option, index) => {
                const selected = settings.subtitleSourcePreference === option.value;
                return (
                  <Pressable
                    key={option.label}
                    style={[
                      styles.segmentedChip,
                      index > 0 && styles.segmentedChipDivider,
                      selected && styles.segmentedChipActive,
                    ]}
                    onPress={() =>
                      updateSetting('subtitleSourcePreference', option.value as 'internal' | 'external' | 'any')
                    }
                  >
                    <Text style={[styles.segmentedChipText, selected && styles.segmentedChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <SettingItem
            title="Auto-Select Subtitles"
            description="Automatically choose subtitles based on the preferences above"
            icon="text-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.enableSubtitleAutoSelect ?? true}
                onValueChange={(value) => updateSetting('enableSubtitleAutoSelect', value)}
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
              <SettingsSwitch
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
              <SettingsSwitch
                value={settings.skipCreditsAutomatically}
                onValueChange={(value) => updateSetting('skipCreditsAutomatically', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Skip Recap Automatically"
            description="Auto-skip detected recap segments"
            icon="play-skip-forward-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.skipRecapAutomatically}
                onValueChange={(value) => updateSetting('skipRecapAutomatically', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Community Skip Data"
            description="Look up intro, recap and credits timings from IntroDB and AniSkip when Plex has none"
            icon="people-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.communitySkipSegmentsEnabled}
                onValueChange={(value) => updateSetting('communitySkipSegmentsEnabled', value)}
              />
            )}
            isLast={false}
          />
          {settings.communitySkipSegmentsEnabled ? (
            <View style={styles.sliderGroup}>
              <Text style={styles.sliderLabel}>Anime-Skip Client ID</Text>
              <Text style={styles.sliderSubtitle}>Optional. Anime-Skip is only used with your own client ID</Text>
              <TextInput
                defaultValue={settings.animeSkipClientId}
                onEndEditing={(event) => updateSetting('animeSkipClientId', event.nativeEvent.text.trim())}
                placeholder="Client ID"
                placeholderTextColor="#6b7280"
                autoCapitalize="none"
                autoCorrect={false}
                secureTextEntry
                style={styles.textInput}
              />
            </View>
          ) : null}
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
            updateSetting('preferredSubtitleLanguage', 'en');
            updateSetting('preferredAudioLanguage', undefined);
            updateSetting('subtitleSourcePreference', 'internal');
            updateSetting('enableSubtitleAutoSelect', true);
            updateSetting('defaultPlaybackSpeed', 1);
            updateSetting('subtitleFontSize', 55);
            updateSetting('subtitleTextColor', '#FFFFFF');
            updateSetting('subtitleBorderSize', 3);
            updateSetting('subtitlePosition', 100);
            updateSetting('subtitleFilterSDH', false);
            updateSetting('skipRecapAutomatically', true);
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
  textInput: {
    color: '#f9fafb',
    fontSize: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
    marginBottom: 10,
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
