import React, { useCallback, useState } from 'react';
import { View, Text, ScrollView, Pressable, StyleSheet, Animated } from 'react-native';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import HeroSourceSheet, { heroSourceLabel } from '../../components/home/HeroSourceSheet';
import { useAppSettings } from '../../hooks/useAppSettings';

export default function HomeScreenSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting, refresh } = useAppSettings();
  const headerHeight = insets.top + 52;
  const [heroSourceOpen, setHeroSourceOpen] = useState(false);

  // Home registers its rows without notifying, so pick up the list on focus.
  useFocusEffect(
    useCallback(() => {
      refresh();
    }, [refresh])
  );

  return (
    <View style={styles.container}>
      <SettingsHeader scrollY={headerScrollY} title="Home" onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })} contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        <SettingsCard title="HERO">
          <SettingItem
            title="Show Hero"
            description="Display the featured hero row"
            icon="star-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showHeroSection}
                onValueChange={(value) => updateSetting('showHeroSection', value)}
              />
            )}
            isLast={!settings.showHeroSection}
          />
          {settings.showHeroSection && (
            <>
              <SettingItem
                title="Auto-Rotate Hero"
                description="Advance the Carousel and Apple TV layouts every 8 seconds"
                icon="sync-outline"
                renderRight={() => (
                  <SettingsSwitch
                    value={settings.heroAutoRotate}
                    onValueChange={(value) => updateSetting('heroAutoRotate', value)}
                  />
                )}
                isLast={false}
              />
              <SettingItem
                title="Hero Source"
                description={`${heroSourceLabel(settings)}. Falls back to the default when empty.`}
                icon="image-outline"
                renderRight={() => <Ionicons name="chevron-forward" size={18} color="#9ca3af" />}
                onPress={() => setHeroSourceOpen(true)}
                isLast={true}
              />
            </>
          )}
        </SettingsCard>

        {settings.showHeroSection && (
          <SettingsCard title="HERO LAYOUT">
            <View style={styles.posterGroup}>
              <Text style={styles.posterLabel}>Hero Layout</Text>
              <View style={styles.posterSegment}>
                {[
                  { label: 'Netflix', value: 'legacy' },
                  { label: 'Carousel', value: 'carousel' },
                  { label: 'Apple TV', value: 'appletv' },
                ].map((option, index) => {
                  const selected = settings.heroLayout === option.value;
                  return (
                    <Pressable
                      key={option.value}
                      style={[
                        styles.posterChip,
                        styles.posterChipFill,
                        index > 0 && styles.posterChipDivider,
                        selected && styles.posterChipActive,
                      ]}
                      onPress={() => updateSetting('heroLayout', option.value as any)}
                    >
                      <Text style={[styles.posterChipText, selected && styles.posterChipTextActive]}>
                        {option.label}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>
            </View>
          </SettingsCard>
        )}

        <SettingsCard title="ROWS">
          <SettingItem
            title="Arrange Rows"
            description="Reorder, rename and hide rows"
            icon="reorder-three-outline"
            renderRight={() => <Ionicons name="chevron-forward" size={18} color="#9ca3af" />}
            onPress={() => nav.navigate('HomeRowsSettings')}
            isLast={false}
          />
          {/* Continue Watching lives under Home, as on macOS */}
          <SettingItem
            title="Continue Watching Options"
            description="Layout, source, spoilers and cached streams"
            icon="play-circle-outline"
            renderRight={() => <Ionicons name="chevron-forward" size={18} color="#9ca3af" />}
            onPress={() => nav.navigate('ContinueWatchingSettings')}
            isLast={false}
          />
          <SettingItem
            title="Addon Catalogs"
            description={settings.stremioPlaybackEnabled ? 'Show catalogs from your Stremio addons' : 'Turn on Stremio addons to use this'}
            icon="extension-puzzle-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showStremioCatalogRows}
                onValueChange={(value) => updateSetting('showStremioCatalogRows', value)}
                disabled={!settings.stremioPlaybackEnabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Continue Watching"
            description="Show continue watching row"
            icon="play-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showContinueWatchingRow}
                onValueChange={(value) => updateSetting('showContinueWatchingRow', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Trending"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show TMDB trending rows"}
            icon="stats-chart-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showTrendingRows}
                onValueChange={(value) => updateSetting('showTrendingRows', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Trakt Rows"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show Trakt watchlist, history, and recs"}
            icon="layers-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showTraktRows}
                onValueChange={(value) => updateSetting('showTraktRows', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Popular on Plex"
            description={settings.discoveryDisabled ? "Disabled by Library Only Mode" : "Show Plex popularity row"}
            icon="flame-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showPlexPopularRow}
                onValueChange={(value) => updateSetting('showPlexPopularRow', value)}
                disabled={settings.discoveryDisabled}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Genre Rows"
            description="Show genre-based rows (Drama, Animation, etc.)"
            icon="pricetags-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showPlexGenreRows}
                onValueChange={(value) => updateSetting('showPlexGenreRows', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Collections"
            description="Show Plex collection rows on home"
            icon="albums-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showCollectionRows}
                onValueChange={(value) => updateSetting('showCollectionRows', value)}
              />
            )}
            isLast={!settings.showCollectionRows}
          />
          {settings.showCollectionRows && (
            <SettingItem
              title="Manage Collections"
              description="Choose which collections appear"
              icon="sparkles-outline"
              renderRight={() => (
                <Ionicons name="chevron-forward" size={18} color="#9ca3af" />
              )}
              onPress={() => nav.navigate('CollectionRowsSettings')}
              isLast={false}
            />
          )}
          <SettingItem
            title="Recently Added"
            description="Show 'Recently Added in {Library}' rows"
            icon="time-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showRecentlyAddedRows}
                onValueChange={(value) => updateSetting('showRecentlyAddedRows', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        {settings.showRecentlyAddedRows && (
          <SettingsCard title="RECENTLY ADDED">
            <SettingItem
              title="Group Episodes by Series"
              description="Show series posters instead of individual episodes"
              icon="albums-outline"
              renderRight={() => (
                <SettingsSwitch
                  value={settings.groupRecentlyAddedEpisodes}
                  onValueChange={(value) => updateSetting('groupRecentlyAddedEpisodes', value)}
                />
              )}
              isLast={true}
            />
          </SettingsCard>
        )}

        <SettingsCard title="POSTERS">
          <SettingItem
            title="Show Titles"
            description="Display title text below each poster"
            icon="image-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showPosterTitles}
                onValueChange={(value) => updateSetting('showPosterTitles', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Library Titles"
            description="Display title text in Library grid"
            icon="library-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showLibraryTitles}
                onValueChange={(value) => updateSetting('showLibraryTitles', value)}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="Rating Badges"
            description="Show the rating on cards when one is available"
            icon="star-half-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.showRatingBadges}
                onValueChange={(value) => updateSetting('showRatingBadges', value)}
              />
            )}
            isLast={false}
          />
          <View style={styles.posterGroup}>
            <Text style={styles.posterLabel}>Row Layout</Text>
            <View style={styles.posterSegment}>
              {([
                { label: 'Poster', value: 'poster' },
                { label: 'Landscape', value: 'landscape' },
              ] as const).map((option, index) => {
                const selected = settings.rowLayout === option.value;
                return (
                  <Pressable
                    key={option.value}
                    style={[
                      styles.posterChip,
                      styles.posterChipFill,
                      index > 0 && styles.posterChipDivider,
                      selected && styles.posterChipActive,
                    ]}
                    onPress={() => updateSetting('rowLayout', option.value)}
                  >
                    <Text style={[styles.posterChipText, selected && styles.posterChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <View style={styles.posterGroup}>
            <Text style={styles.posterLabel}>Poster Size</Text>
            <View style={styles.posterSegment}>
              {['small', 'medium', 'large'].map((size, index) => {
                const selected = settings.posterSize === size;
                return (
                  <Pressable
                    key={size}
                    style={[
                      styles.posterChip,
                      styles.posterChipFill,
                      index > 0 && styles.posterChipDivider,
                      selected && styles.posterChipActive,
                    ]}
                    onPress={() => updateSetting('posterSize', size as any)}
                  >
                    <Text style={[styles.posterChipText, selected && styles.posterChipTextActive]}>
                      {size.charAt(0).toUpperCase() + size.slice(1)}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
          <View style={[styles.posterGroup, styles.posterGroupLast]}>
            <Text style={styles.posterLabel}>Poster Corners</Text>
            <View style={styles.posterSegment}>
              {[
                { label: 'Square', value: 0 },
                { label: 'Rounded', value: 12 },
                { label: 'Pill', value: 20 },
              ].map((option, index) => {
                const selected = settings.posterBorderRadius === option.value;
                return (
                  <Pressable
                    key={option.label}
                    style={[
                      styles.posterChip,
                      styles.posterChipFill,
                      index > 0 && styles.posterChipDivider,
                      selected && styles.posterChipActive,
                    ]}
                    onPress={() => updateSetting('posterBorderRadius', option.value)}
                  >
                    <Text style={[styles.posterChipText, selected && styles.posterChipTextActive]}>
                      {option.label}
                    </Text>
                  </Pressable>
                );
              })}
            </View>
          </View>
        </SettingsCard>
      </Animated.ScrollView>
      <HeroSourceSheet visible={heroSourceOpen} settings={settings} onClose={() => setHeroSourceOpen(false)} />
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
  posterGroup: {
    paddingHorizontal: 14,
    paddingTop: 12,
    paddingBottom: 4,
  },
  posterGroupLast: {
    paddingBottom: 14,
  },
  posterLabel: {
    color: '#f9fafb',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 10,
  },
  posterSegment: {
    flexDirection: 'row',
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.12)',
    overflow: 'hidden',
    height: 44,
    padding: 2,
  },
  posterChip: {
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 6,
  },
  posterChipFill: {
    flex: 1,
  },
  posterChipDivider: {
    borderLeftWidth: 1,
    borderLeftColor: 'rgba(255,255,255,0.08)',
  },
  posterChipActive: {
    backgroundColor: '#fff',
    borderRadius: 10,
  },
  posterChipText: {
    color: '#e5e7eb',
    fontSize: 12,
    fontWeight: '600',
    textAlign: 'center',
  },
  posterChipTextActive: {
    color: '#111827',
  },
});
