import React from 'react';
import { View, ScrollView, Text, Pressable, StyleSheet, Animated, Modal } from 'react-native';
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
import { DEFAULT_APP_SETTINGS, type AppSettings, type DetailsSectionKey, type DetailsSeasonPickerStyle } from '../../core/SettingsData';
import RatingLogo from '../../components/RatingLogo';
import {
  RATING_KINDS,
  RATING_META,
  SOURCE_TITLES,
  isRatingShown,
  ratingShownPatch,
  ratingSource,
  type RatingKind,
  type RatingSource,
} from '../../core/ratings/merged';

export default function DetailsScreenSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const theme = useTheme();
  const headerHeight = insets.top + 52;
  const sections = normalizeDetailsSections(settings.detailsSectionPreferences);
  const [picking, setPicking] = React.useState<RatingKind | null>(null);
  const setAppSettingsPatch = async (patch: Partial<AppSettings>) => {
    for (const [key, value] of Object.entries(patch)) {
      await updateSetting(key as keyof AppSettings, value as any);
    }
  };

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

        {/* Trailers moved to their own page (Settings › Trailers): they also play in New & Hot */}
        <SettingsCard title="HERO">
          <SettingItem
            title="Trailers"
            description="Autoplay on Details and New & Hot"
            icon="film-outline"
            onPress={() => nav.navigate('TrailerSettings')}
            renderRight={() => (
              <View style={styles.linkRight}>
                <Text style={styles.linkValue}>{settings.detailsHeroInlineTrailerEnabled ? 'On' : 'Off'}</Text>
                <Ionicons name="chevron-forward" size={16} color="#8e8e93" />
              </View>
            )}
            isLast={true}
          />
        </SettingsCard>

        <Pressable onPress={resetSections} style={styles.reset} accessibilityRole="button">
          <Text style={styles.resetText}>Reset Sections and Episode Options</Text>
        </Pressable>

        <SettingsCard title="RATINGS">
          {RATING_KINDS.map((kind, index) => {
            const meta = RATING_META[kind];
            const shown = isRatingShown(kind, settings);
            const source = ratingSource(kind, settings);
            const needsMdblist = meta.sources.length === 1 && meta.sources[0] === 'mdblist' && !settings.mdblistApiKey;
            const canPick = meta.sources.length > 1;
            return (
              <SettingItem
                key={kind}
                title={meta.title}
                description={needsMdblist ? 'Needs an MDBList key' : canPick ? `${meta.subtitle} · ${SOURCE_TITLES[source]}` : meta.subtitle}
                renderIcon={() => <RatingLogo kind={kind} value={kind === 'metacritic' ? 75 : 80} size={kind === 'imdb' || kind === 'letterboxd' ? 9 : 16} />}
                onPress={canPick ? () => setPicking(kind) : undefined}
                renderRight={() => (
                  <SettingsSwitch
                    value={shown}
                    onValueChange={(value) => setAppSettingsPatch(ratingShownPatch(kind, value, settings))}
                  />
                )}
                isLast={index === RATING_KINDS.length - 1}
              />
            );
          })}
        </SettingsCard>
        <Text style={styles.footnote}>Tap a rating to choose where it comes from. Automatic uses MyBluray, then Plex, then MDBList, then TMDB. Long-press a rating on a Details page to see its votes and source.</Text>
      </Animated.ScrollView>

      <Modal visible={picking !== null} transparent animationType="slide" onRequestClose={() => setPicking(null)}>
        <Pressable style={styles.sheetScrim} onPress={() => setPicking(null)} />
        {picking ? (
          <View style={[styles.sheet, { backgroundColor: theme.surfaceElevated, paddingBottom: insets.bottom + 12 }]}>
            <View style={styles.grabber} />
            <Text style={styles.sheetTitle}>{RATING_META[picking].title}</Text>
            <Text style={styles.sheetSubtitle}>Where this rating comes from. When the chosen source has nothing for a title, the next one is used.</Text>
            {(['automatic', ...RATING_META[picking].sources] as RatingSource[]).map((option) => {
              const selected = ratingSource(picking, settings) === option;
              const note = option === 'mybluray' && !settings.myblurayApiKey
                ? 'Needs a MyBluray key'
                : option === 'mdblist' && !settings.mdblistApiKey
                  ? 'Needs an MDBList key'
                  : option === 'automatic'
                    ? RATING_META[picking].sources.map((x) => SOURCE_TITLES[x]).join(' → ')
                    : undefined;
              return (
                <Pressable
                  key={option}
                  style={styles.sheetRow}
                  onPress={() => {
                    setAppSettingsPatch({ ratingSource: { ...(settings.ratingSource ?? {}), [picking]: option } });
                    setPicking(null);
                  }}
                >
                  <View style={{ flex: 1 }}>
                    <Text style={[styles.sheetRowText, selected && { fontWeight: '700' }]}>{SOURCE_TITLES[option]}</Text>
                    {note ? <Text style={styles.sheetRowNote}>{note}</Text> : null}
                  </View>
                  {selected ? <Ionicons name="checkmark" size={18} color="#fff" /> : null}
                </Pressable>
              );
            })}
          </View>
        ) : null}
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  linkRight: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  footnote: { color: '#8e8e93', fontSize: 12, lineHeight: 17, marginTop: -8, marginBottom: 20, paddingHorizontal: 6 },
  sheetScrim: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)' },
  sheet: { borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingHorizontal: 16, paddingTop: 8 },
  grabber: { alignSelf: 'center', width: 40, height: 4, borderRadius: 2, backgroundColor: 'rgba(255,255,255,0.25)', marginBottom: 12 },
  sheetTitle: { color: '#fff', fontSize: 17, fontWeight: '700', marginBottom: 4 },
  sheetSubtitle: { color: '#9ca3af', fontSize: 13, lineHeight: 18, marginBottom: 8 },
  sheetRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 13, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: 'rgba(255,255,255,0.08)' },
  sheetRowText: { color: '#fff', fontSize: 15 },
  sheetRowNote: { color: '#8e8e93', fontSize: 12, marginTop: 2 },
  linkValue: { color: '#8e8e93', fontSize: 15 },
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
