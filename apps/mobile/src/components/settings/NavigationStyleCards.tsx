/**
 * Tab labels and tab glow, with a live tab bar preview. Shown on
 * Settings > Navigation under the tab switches (moved from Appearance).
 * macOS reference: Views/Navigation/NavigationStyleSettingsSection.swift
 */

import React, { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import SettingsCard from './SettingsCard';
import SettingItem from './SettingItem';
import SettingsSwitch from './SettingsSwitch';
import TabGlowIcon from '../TabGlowIcon';
import { NAV_ICONS, type NavIconPair } from '../navIcons';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import type { FlixorTheme } from '../../core/theme';
import { usesNativeTabBar } from '../../core/TabBarSupport';
import type { TabLabelMode } from '../../core/SettingsData';

const TAB_LABEL_OPTIONS: Array<{ value: TabLabelMode; label: string }> = [
  { value: 'always', label: 'Always' },
  { value: 'selected', label: 'Selected' },
  { value: 'none', label: 'Never' },
];

// The same icons as the tab bar
const PREVIEW_TABS: Array<{ key: string; label: string; icons: NavIconPair }> = [
  { key: 'home', label: 'Home', icons: NAV_ICONS.home },
  { key: 'list', label: 'My List', icons: NAV_ICONS.myList },
  { key: 'downloads', label: 'Downloads', icons: NAV_ICONS.downloads },
  { key: 'settings', label: 'Settings', icons: NAV_ICONS.settings },
];

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
    <LinearGradient colors={[theme.accentSoft, theme.background]} style={styles.preview}>
      <View style={[styles.previewBar, { backgroundColor: theme.surfaceElevated, borderColor: theme.separator }]}>
        {PREVIEW_TABS.map((tab) => {
          const focused = tab.key === selected;
          const color = focused ? activeColor : theme.textSecondary;
          const showLabel = labelMode === 'always' || (labelMode === 'selected' && focused);
          return (
            <Pressable key={tab.key} onPress={() => setSelected(tab.key)} style={styles.previewTab}>
              <TabGlowIcon source={focused ? tab.icons.fill : tab.icons.outline} size={22} color={color} glow={glow && focused} theme={theme} />
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

export default function NavigationStyleCards() {
  const theme = useTheme();
  const { settings, updateSetting } = useAppSettings();

  return (
    <>
      <SettingsCard title="STYLE">
        <View style={styles.cardBody}>
          <Text style={[styles.fieldTitle, { color: theme.textPrimary }]}>Tab Labels</Text>
          <Segmented
            options={TAB_LABEL_OPTIONS}
            value={settings.tabLabelMode}
            onChange={(value) => updateSetting('tabLabelMode', value)}
            theme={theme}
          />
        </View>
        {/* iOS 26 draws its own tab bar, so there is nothing to put a glow on */}
        {usesNativeTabBar ? null : (
          <SettingItem
            title="Tab Glow"
            description="Soft light around the selected tab"
            icon="sparkles-outline"
            renderRight={() => (
              <SettingsSwitch value={settings.navGlowEnabled} onValueChange={(value) => updateSetting('navGlowEnabled', value)} />
            )}
            isLast={true}
          />
        )}
      </SettingsCard>

      <SettingsCard title="PREVIEW">
        <TabBarPreview theme={theme} labelMode={settings.tabLabelMode} glow={settings.navGlowEnabled && !usesNativeTabBar} />
      </SettingsCard>
    </>
  );
}

const styles = StyleSheet.create({
  cardBody: { padding: 14 },
  fieldTitle: { fontSize: 15, fontWeight: '600', marginBottom: 8 },
  segmented: { flexDirection: 'row', borderRadius: 10, padding: 3 },
  segment: { flex: 1, paddingVertical: 8, borderRadius: 8, alignItems: 'center' },
  segmentText: { fontSize: 13, fontWeight: '600' },
  preview: { paddingVertical: 28, paddingHorizontal: 16 },
  previewBar: { flexDirection: 'row', paddingVertical: 10, borderRadius: 16, borderWidth: 1 },
  previewTab: { flex: 1, alignItems: 'center', justifyContent: 'center', minHeight: 40 },
  previewLabel: { fontSize: 10, marginTop: 4 },
});
