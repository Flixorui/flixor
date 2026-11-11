import React from 'react';
import { View, ScrollView, Text, Pressable, StyleSheet, Animated } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import {
  DETAILS_SECTION_META,
  defaultDetailsSections,
  moveDetailsSection,
  normalizeDetailsSections,
} from '../../core/DetailsSectionsStore';
import { DEFAULT_APP_SETTINGS, type DetailsSectionKey, type DetailsSeasonPickerStyle } from '../../core/SettingsData';

export default function DetailsScreenSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const theme = useTheme();
  const headerHeight = insets.top + 52;
  const sections = normalizeDetailsSections(settings.detailsSectionPreferences);

  const setSectionEnabled = (key: DetailsSectionKey, enabled: boolean) =>
    updateSetting(
      'detailsSectionPreferences',
      sections.map((section) => (section.key === key ? { ...section, enabled } : section))
    );

  const moveSection = (key: DetailsSectionKey, offset: -1 | 1) =>
    updateSetting('detailsSectionPreferences', moveDetailsSection(sections, key, offset));

  const resetSections = async () => {
    await updateSetting('detailsSectionPreferences', defaultDetailsSections());
    await updateSetting('detailsHideEpisodeSpoilers', DEFAULT_APP_SETTINGS.detailsHideEpisodeSpoilers);
    await updateSetting('detailsSeasonPickerStyle', DEFAULT_APP_SETTINGS.detailsSeasonPickerStyle);
    await updateSetting('detailsShowEpisodeRatings', DEFAULT_APP_SETTINGS.detailsShowEpisodeRatings);
  };

  const seasonPickerOptions: Array<{ label: string; value: DetailsSeasonPickerStyle }> = [
    { label: 'Chips', value: 'chips' },
    { label: 'Posters', value: 'posters' },
  ];

  // Moved here from the Settings root, next to the other episode options (as on macOS)
  const episodeLayoutOptions: Array<{ label: string; value: 'vertical' | 'horizontal' }> = [
    { label: 'Vertical', value: 'vertical' },
    { label: 'Horizontal', value: 'horizontal' },
  ];

  const layoutOptions = [
    { label: 'Tabbed', value: 'tabbed' },
    { label: 'Unified', value: 'unified' },
  ];

  return (
    <View style={styles.container}>
      <SettingsHeader scrollY={headerScrollY} title="Details" onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })} contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        <SettingsCard title="SCREEN LAYOUT">
          <View style={styles.layoutGroup}>
            <Text style={styles.layoutLabel}>Details Page Style</Text>
            <Text style={styles.layoutDescription}>
              Tabbed shows sections in tabs, Unified shows all content on one scrollable page
            </Text>
            <View style={styles.layoutSegment}>
              {layoutOptions.map((option, index) => {
                const selected = (settings.detailsScreenLayout ?? 'unified') === option.value;
                return (
                  <Pressable
                    key={option.value}
                    style={[
                      styles.layoutChip,
                      styles.layoutChipFill,
                      index > 0 && styles.layoutChipDivider,
                      selected && styles.layoutChipActive,
                    ]}
                    onPress={() => updateSetting('detailsScreenLayout', option.value as 'tabbed' | 'unified')}
                  >
                    <Text style={[styles.layoutChipText, selected && styles.layoutChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        </SettingsCard>

        <SettingsCard title="SECTIONS">
          {sections.map((section, index) => {
            const meta = DETAILS_SECTION_META[section.key];
            const atTop = index === 0;
            const atBottom = index === sections.length - 1;
            return (
              <SettingItem
                key={section.key}
                title={meta.title}
                description={meta.subtitle}
                icon={meta.icon}
                renderRight={() => (
                  <View style={styles.sectionControls}>
                    <Pressable
                      disabled={atTop}
                      onPress={() => moveSection(section.key, -1)}
                      hitSlop={6}
                      accessibilityRole="button"
                      accessibilityLabel={`Move ${meta.title} up`}
                    >
                      <Ionicons name="chevron-up" size={20} color={atTop ? theme.textDisabled : theme.textPrimary} />
                    </Pressable>
                    <Pressable
                      disabled={atBottom}
                      onPress={() => moveSection(section.key, 1)}
                      hitSlop={6}
                      accessibilityRole="button"
                      accessibilityLabel={`Move ${meta.title} down`}
                    >
                      <Ionicons name="chevron-down" size={20} color={atBottom ? theme.textDisabled : theme.textPrimary} />
                    </Pressable>
                    <SettingsSwitch
                      value={section.enabled}
                      onValueChange={(value) => setSectionEnabled(section.key, value)}
                      accessibilityLabel={`Show ${meta.title}`}
                    />
                  </View>
                )}
                isLast={atBottom}
              />
            );
          })}
        </SettingsCard>

        <SettingsCard title="EPISODES">
          <View style={styles.layoutGroup}>
            <Text style={styles.layoutLabel}>Season Picker</Text>
            <Text style={styles.layoutDescription}>Text chips, or season posters with episode counts</Text>
            <View style={styles.layoutSegment}>
              {seasonPickerOptions.map((option, index) => {
                const selected = settings.detailsSeasonPickerStyle === option.value;
                return (
                  <Pressable
                    key={option.value}
                    style={[
                      styles.layoutChip,
                      styles.layoutChipFill,
                      index > 0 && styles.layoutChipDivider,
                      selected && styles.layoutChipActive,
                    ]}
                    onPress={() => updateSetting('detailsSeasonPickerStyle', option.value)}
                  >
                    <Text style={[styles.layoutChipText, selected && styles.layoutChipTextActive]}>{option.label}</Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <View style={styles.layoutGroup}>
            <Text style={styles.layoutLabel}>Episode Layout</Text>
            <Text style={styles.layoutDescription}>A vertical list, or a horizontal row of episode cards</Text>
            <View style={styles.layoutSegment}>
              {episodeLayoutOptions.map((option, index) => {
                const selected = (settings.episodeLayoutStyle ?? 'vertical') === option.value;
                return (
                  <Pressable
                    key={option.value}
                    style={[
                      styles.layoutChip,
                      styles.layoutChipFill,
                      index > 0 && styles.layoutChipDivider,
                      selected && styles.layoutChipActive,
                    ]}
                    onPress={() => updateSetting('episodeLayoutStyle', option.value)}
                  >
                    <Text style={[styles.layoutChipText, selected && styles.layoutChipTextActive]}>{option.label}</Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <SettingItem
            title="Hide Spoilers for Unwatched Episodes"
            description="Blur thumbnails and hide descriptions"
            icon="eye-off-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.detailsHideEpisodeSpoilers}
                onValueChange={(value) => updateSetting('detailsHideEpisodeSpoilers', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Episode Ratings"
            description="Show the TMDB rating on each episode"
            icon="star-half-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.detailsShowEpisodeRatings}
                onValueChange={(value) => updateSetting('detailsShowEpisodeRatings', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        <SettingsCard title="HERO">
          <SettingItem
            title="Inline Trailer"
            description="Play the trailer over the artwork. Uses data."
            icon="film-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.detailsHeroInlineTrailerEnabled}
                onValueChange={(value) => updateSetting('detailsHeroInlineTrailerEnabled', value)}
              />
            )}
            isLast={!settings.detailsHeroInlineTrailerEnabled}
          />
          {settings.detailsHeroInlineTrailerEnabled ? (
            <SettingItem
              title="Start Muted"
              description="Use the speaker button to unmute"
              icon="volume-mute-outline"
              renderRight={() => (
                <SettingsSwitch
                  value={settings.detailsHeroTrailerStartsMuted}
                  onValueChange={(value) => updateSetting('detailsHeroTrailerStartsMuted', value)}
                />
              )}
              isLast={true}
            />
          ) : null}
        </SettingsCard>

        <Pressable onPress={resetSections} style={styles.reset} accessibilityRole="button">
          <Text style={styles.resetText}>Reset Sections and Episode Options</Text>
        </Pressable>

        <SettingsCard title="RATINGS DISPLAY">
          <SettingItem
            title="IMDb Rating"
            description="Show IMDb rating on details screen"
            icon="star-outline"
            renderRight={() => (
              <SettingsSwitch
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
              <SettingsSwitch
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
              <SettingsSwitch
                value={settings.showRottenTomatoesAudience ?? true}
                onValueChange={(value) => updateSetting('showRottenTomatoesAudience', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>
      </Animated.ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  sectionControls: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  reset: {
    alignSelf: 'center',
    paddingVertical: 8,
    marginBottom: 16,
  },
  resetText: {
    color: '#9ca3af',
    fontSize: 13,
    fontWeight: '600',
  },
  container: {
    flex: 1,
    backgroundColor: '#0b0b0d',
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 40,
  },
  layoutGroup: {
    paddingHorizontal: 14,
    paddingTop: 12,
    paddingBottom: 14,
  },
  layoutLabel: {
    color: '#f9fafb',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 6,
  },
  layoutDescription: {
    color: '#9ca3af',
    fontSize: 12,
    marginBottom: 12,
  },
  layoutSegment: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    overflow: 'hidden',
    height: 44,
    padding: 2,
  },
  layoutChip: {
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 6,
  },
  layoutChipFill: {
    flex: 1,
  },
  layoutChipDivider: {
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(255,255,255,0.08)',
  },
  layoutChipActive: {
    backgroundColor: '#fff',
    borderRadius: 10,
  },
  layoutChipText: {
    color: '#e5e7eb',
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'center',
  },
  layoutChipTextActive: {
    color: '#111827',
  },
});
