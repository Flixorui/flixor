import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View, Animated } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { appSettingsEmitter, useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import { ACCENT_PALETTES, ACCENT_PALETTE_IDS, type FlixorTheme } from '../../core/theme';
import { setAppSettings, type AccentPalette } from '../../core/SettingsData';

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

export default function AppearanceSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const theme = useTheme();
  const { settings, updateSetting } = useAppSettings();

  // Tab labels, top bar and tab glow are on Settings > Navigation
  const isDefault = !settings.accentPalette && !settings.pureBlack;

  const resetToDefault = async () => {
    await setAppSettings({
      accentPalette: undefined,
      pureBlack: false,
    });
    appSettingsEmitter.emit();
  };

  const selectPalette = (palette: AccentPalette | undefined) => updateSetting('accentPalette', palette);

  return (
    <View style={[styles.container, { backgroundColor: theme.settingsBackground }]}>
      <SettingsHeader scrollY={headerScrollY} title="Appearance" onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
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
              Used for switches and progress bars. Everything else stays neutral, and the Flixor logo always stays red.
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

        <Pressable
          onPress={resetToDefault}
          disabled={isDefault}
          style={[styles.resetButton, isDefault && styles.resetButtonDisabled]}
          accessibilityRole="button"
        >
          <Text style={[styles.resetText, { color: theme.textPrimary }]}>Reset to Default</Text>
        </Pressable>
      </Animated.ScrollView>
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
  resetButton: { alignSelf: 'center', paddingVertical: 10, paddingHorizontal: 16 },
  resetButtonDisabled: { opacity: 0.4 },
  resetText: { fontSize: 14, fontWeight: '600' },
});
