/**
 * Advanced: logging, diagnostics and the reset actions.
 * macOS reference: Views/Settings/SettingsView.swift (AdvancedSettingsContent)
 */

import React, { useCallback } from 'react';
import { View, ScrollView, StyleSheet, Platform, Alert, Pressable, Text, Animated } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { useAppSettings } from '../../hooks/useAppSettings';
import { useTheme } from '../../hooks/useTheme';
import { appLogger } from '../../core/AppLogger';
import { clearAllCaches } from '../../core/MemoryManager';
import { resetAllSettingsWithNotify } from '../../core/SettingsData';

/** iOS system red, kept for destructive actions (as macOS does for Sign Out and Remove). */
const DESTRUCTIVE = '#FF453A';

export default function AdvancedSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const { settings, updateSetting } = useAppSettings();

  const confirm = useCallback((title: string, message: string, action: string, run: () => Promise<void>, done: string) => {
    Alert.alert(title, message, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: action,
        style: 'destructive',
        onPress: async () => {
          try {
            await run();
            Alert.alert(done);
          } catch {
            Alert.alert('Something went wrong', 'Please try again.');
          }
        },
      },
    ]);
  }, []);

  return (
    <View style={[styles.container, { backgroundColor: theme.settingsBackground }]}>
      <SettingsHeader scrollY={headerScrollY} title="Advanced" onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })} contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        <SettingsCard title="DIAGNOSTICS">
          <SettingItem
            title="Debug Logging"
            description="Verbose logging for troubleshooting"
            icon="bug-outline"
            renderRight={() => (
              <SettingsSwitch
                value={settings.enableDebugLogging}
                onValueChange={(value) => {
                  updateSetting('enableDebugLogging', value);
                  appLogger.setDebugEnabled(value);
                }}
              />
            )}
            isLast={false}
          />
          <SettingItem
            title="View Logs"
            icon="document-text-outline"
            renderRight={() => <Ionicons name="chevron-forward" size={18} color="#9ca3af" />}
            onPress={() => nav.navigate('LogsScreen')}
            isLast={Platform.OS !== 'android'}
          />
          {Platform.OS === 'android' ? (
            <SettingItem
              title="Blur Effects"
              description="May slow down some devices"
              icon="sparkles-outline"
              renderRight={() => (
                <SettingsSwitch
                  value={settings.enableAndroidBlurView}
                  onValueChange={(value) => updateSetting('enableAndroidBlurView', value)}
                />
              )}
              isLast={true}
            />
          ) : null}
        </SettingsCard>

        <SettingsCard title="RESET">
          <Pressable
            style={[styles.actionRow, styles.actionBorder]}
            onPress={() =>
              confirm('Clear Cache', 'Clears cached images and data. This cannot be undone.', 'Clear', clearAllCaches, 'Cache cleared')
            }
            accessibilityRole="button"
          >
            <Text style={styles.destructiveText}>Clear Cache…</Text>
          </Pressable>
          <Pressable
            style={styles.actionRow}
            onPress={() =>
              confirm(
                'Reset Settings',
                'Puts every setting back to its default. This cannot be undone.',
                'Reset',
                resetAllSettingsWithNotify,
                'Settings reset to defaults'
              )
            }
            accessibilityRole="button"
          >
            <Text style={styles.destructiveText}>Reset Settings…</Text>
          </Pressable>
        </SettingsCard>
      </Animated.ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { paddingHorizontal: 16 },
  actionRow: { paddingHorizontal: 14, paddingVertical: 14, minHeight: 48, justifyContent: 'center' },
  actionBorder: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: 'rgba(255,255,255,0.08)' },
  destructiveText: { color: DESTRUCTIVE, fontSize: 15, fontWeight: '600' },
});
