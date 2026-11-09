import React, { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import TabGlowIcon from '../../components/TabGlowIcon';
import { appSettingsEmitter, useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import { ACCENT_PALETTES, ACCENT_PALETTE_IDS, type FlixorTheme } from '../../core/theme';
import { usesNativeTabBar } from '../../core/TabBarSupport';
import { setAppSettings, type AccentPalette, type TabLabelMode, type TopBarStyle } from '../../core/SettingsData';

const TAB_LABEL_OPTIONS: Array<{ value: TabLabelMode; label: string }> = [
  { value: 'always', label: 'Always' },
  { value: 'selected', label: 'Selected' },
  { value: 'none', label: 'Never' },
];

const TOP_BAR_OPTIONS: Array<{ value: TopBarStyle; label: string; help: string }> = [
  { value: 'adaptive', label: 'Adaptive', help: 'Filters hide as you scroll down and return when you scroll up.' },
  { value: 'expanded', label: 'Expanded', help: 'Filters stay on screen while you scroll.' },
  { value: 'compact', label: 'Compact', help: 'A smaller title. Filters only show at the top of the page.' },
];

const PREVIEW_TABS: Array<{ key: string; label: string; icon: keyof typeof Ionicons.glyphMap; focusedIcon: keyof typeof Ionicons.glyphMap }> = [
  { key: 'home', label: 'Home', icon: 'home-outline', focusedIcon: 'home' },
  { key: 'search', label: 'Search', icon: 'search-outline', focusedIcon: 'search' },
  { key: 'list', label: 'My List', icon: 'bookmark-outline', focusedIcon: 'bookmark' },
  { key: 'settings', label: 'Settings', icon: 'settings-outline', focusedIcon: 'settings' },
];

function Swatch({
  label,
  selected,
  onPress,
  theme,
  colors,
}: {
  label: string;
  selected: boolean;
  onPress: () => void;
  theme: FlixorTheme;
  colors?: [string, string, string];
}) {
  return (
    <Pressable
      onPress={onPress}
      style={styles.swatch}
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      accessibilityLabel={label}
    >
      <View style={[styles.swatchRing, { borderColor: selected ? colors?.[0] ?? theme.textPrimary : 'transparent' }]}>
        {colors ? (
          <LinearGradient colors={colors} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.swatchFill}>
            {selected ? <Ionicons name="checkmark" size={18} color={theme.onAccent} /> : null}
          </LinearGradient>
        ) : (
          <View style={[styles.swatchFill, { backgroundColor: theme.surfaceElevated }]}>
            <Ionicons name={selected ? 'checkmark' : 'contrast-outline'} size={18} color={theme.textSecondary} />
          </View>
        )}
      </View>
      <Text
        numberOfLines={1}
        style={[styles.swatchLabel, { color: selected ? theme.textPrimary : theme.textSecondary }]}
      >
        {label}
      </Text>
    </Pressable>
  );
}

function Segmented<T extends string>({
  options,
  value,
  onChange,
  theme,
}: {
  options: Array<{ value: T; label: string }>;
  value: T;
  onChange: (value: T) => void;
  theme: FlixorTheme;
}) {
  return (
    <View style={[styles.segmented, { backgroundColor: theme.surfaceOverlay }]}>
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <Pressable
            key={option.value}
            onPress={() => onChange(option.value)}
            style={[styles.segment, selected && { backgroundColor: theme.chosenAccent ?? theme.pressedFill }]}
            accessibilityRole="radio"
            accessibilityState={{ selected }}
          >
            <Text style={[styles.segmentText, { color: selected ? theme.textPrimary : theme.textSecondary }]}>
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

/** Live example of the tab bar. Tap a tab to try it. */
function TabBarPreview({ theme, labelMode, glow }: { theme: FlixorTheme; labelMode: TabLabelMode; glow: boolean }) {
  const [selected, setSelected] = useState(PREVIEW_TABS[0].key);
  const activeColor = theme.chosenAccentBright ?? theme.textPrimary;

  return (
    <LinearGradient
      colors={[theme.accentSoft, theme.background]}
      style={styles.preview}
    >
      <View style={[styles.previewBar, { backgroundColor: theme.surfaceElevated, borderColor: theme.separator }]}>
        {PREVIEW_TABS.map((tab) => {
          const focused = tab.key === selected;
          const color = focused ? activeColor : theme.textSecondary;
          const showLabel = labelMode === 'always' || (labelMode === 'selected' && focused);
          return (
            <Pressable key={tab.key} onPress={() => setSelected(tab.key)} style={styles.previewTab}>
              <TabGlowIcon
                name={focused ? tab.focusedIcon : tab.icon}
                size={22}
                color={color}
                glow={glow && focused}
                theme={theme}
              />
              {labelMode !== 'none' ? (
                <Text style={[styles.previewLabel, { color, opacity: showLabel ? 1 : 0 }]}>{tab.label}</Text>
              ) : null}
            </Pressable>
          );
        })}
      </View>
    </LinearGradient>
  );
}

export default function AppearanceSettings() {
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const { settings, updateSetting } = useAppSettings();

  const topBarHelp = TOP_BAR_OPTIONS.find((option) => option.value === settings.topBarStyle)?.help;
  const isDefault =
    !settings.accentPalette &&
    !settings.pureBlack &&
    settings.tabLabelMode === 'always' &&
    settings.topBarStyle === 'adaptive' &&
    !settings.navGlowEnabled;

  const resetToDefault = async () => {
    await setAppSettings({
      accentPalette: undefined,
      pureBlack: false,
      tabLabelMode: 'always',
      topBarStyle: 'adaptive',
      navGlowEnabled: false,
    });
    appSettingsEmitter.emit();
  };

  const selectPalette = (palette: AccentPalette | undefined) => updateSetting('accentPalette', palette);

  return (
    <View style={[styles.container, { backgroundColor: theme.settingsBackground }]}>
      <SettingsHeader title="Appearance" onBack={() => nav.goBack()} />
      <ScrollView
        contentContainerStyle={[styles.content, { paddingTop: insets.top + 64, paddingBottom: insets.bottom + 100 }]}
      >
        <SettingsCard title="ACCENT COLOR">
          <View style={styles.cardBody}>
            <View style={styles.swatchGrid} accessibilityRole="radiogroup">
              <Swatch
                label="Default"
                selected={!settings.accentPalette}
                onPress={() => selectPalette(undefined)}
                theme={theme}
              />
              {ACCENT_PALETTE_IDS.map((id) => {
                const palette = ACCENT_PALETTES[id];
                return (
                  <Swatch
                    key={id}
                    label={palette.displayName}
                    selected={settings.accentPalette === id}
                    onPress={() => selectPalette(id)}
                    theme={theme}
                    colors={[palette.bright, palette.color, palette.strong]}
                  />
                );
              })}
            </View>
            <Text style={[styles.note, { color: theme.textSecondary }]}>
              Used for selection, progress bars, toggles and highlights. The Flixor logo always stays red.
            </Text>
          </View>
        </SettingsCard>

        <SettingsCard title="BACKGROUND">
          <SettingItem
            title="Pure Black Background"
            description="True black instead of near-black, for OLED screens"
            icon="contrast-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.pureBlack}
                onValueChange={(value) => updateSetting('pureBlack', value)}
              />
            )}
            isLast={true}
          />
        </SettingsCard>

        <SettingsCard title="NAVIGATION">
          <View style={styles.cardBody}>
            <Text style={[styles.fieldTitle, { color: theme.textPrimary }]}>Tab Labels</Text>
            <Segmented
              options={TAB_LABEL_OPTIONS}
              value={settings.tabLabelMode}
              onChange={(value) => updateSetting('tabLabelMode', value)}
              theme={theme}
            />
            <Text style={[styles.fieldTitle, styles.fieldTitleSpaced, { color: theme.textPrimary }]}>Top Bar</Text>
            <Segmented
              options={TOP_BAR_OPTIONS}
              value={settings.topBarStyle}
              onChange={(value) => updateSetting('topBarStyle', value)}
              theme={theme}
            />
            {topBarHelp ? <Text style={[styles.note, { color: theme.textSecondary }]}>{topBarHelp}</Text> : null}
          </View>
          {/* iOS 26 draws its own tab bar, so there is nothing to put a glow on */}
          {usesNativeTabBar ? null : (
            <SettingItem
              title="Tab Glow"
              description="Soft light around the selected tab"
              icon="sparkles-outline"
              renderRight={() => (
                <SettingsSwitch
                  value={settings.navGlowEnabled}
                  onValueChange={(value) => updateSetting('navGlowEnabled', value)}
                />
              )}
              isLast={true}
            />
          )}
        </SettingsCard>

        <SettingsCard title="PREVIEW">
          <TabBarPreview theme={theme} labelMode={settings.tabLabelMode} glow={settings.navGlowEnabled && !usesNativeTabBar} />
        </SettingsCard>

        <Pressable
          onPress={resetToDefault}
          disabled={isDefault}
          style={[styles.resetButton, isDefault && styles.resetButtonDisabled]}
          accessibilityRole="button"
        >
          <Text style={[styles.resetText, { color: theme.textPrimary }]}>Reset to Default</Text>
        </Pressable>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { paddingHorizontal: 16 },
  cardBody: { padding: 14 },
  swatchGrid: { flexDirection: 'row', flexWrap: 'wrap', marginHorizontal: -4 },
  swatch: { width: '25%', alignItems: 'center', paddingHorizontal: 2, marginBottom: 14 },
  swatchRing: { padding: 3, borderRadius: 26, borderWidth: 2, marginBottom: 6 },
  swatchFill: { width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center' },
  swatchLabel: { fontSize: 12, fontWeight: '500' },
  note: { fontSize: 12, lineHeight: 17, marginTop: 8 },
  fieldTitle: { fontSize: 15, fontWeight: '600', marginBottom: 8 },
  fieldTitleSpaced: { marginTop: 16 },
  segmented: { flexDirection: 'row', borderRadius: 10, padding: 3 },
  segment: { flex: 1, paddingVertical: 8, borderRadius: 8, alignItems: 'center' },
  segmentText: { fontSize: 13, fontWeight: '600' },
  preview: { paddingVertical: 28, paddingHorizontal: 16 },
  previewBar: { flexDirection: 'row', paddingVertical: 10, borderRadius: 16, borderWidth: 1 },
  previewTab: { flex: 1, alignItems: 'center', justifyContent: 'center', minHeight: 40 },
  previewLabel: { fontSize: 10, marginTop: 4 },
  resetButton: { alignSelf: 'center', paddingVertical: 10, paddingHorizontal: 16 },
  resetButtonDisabled: { opacity: 0.4 },
  resetText: { fontSize: 14, fontWeight: '600' },
});
