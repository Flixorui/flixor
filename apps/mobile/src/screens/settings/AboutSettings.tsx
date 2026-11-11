/**
 * About: version, updates, community links and legal.
 * macOS reference: Views/Settings/SettingsView.swift (AboutSettingsContent)
 */

import React from 'react';
import { View, ScrollView, StyleSheet, Linking, Animated } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import { getAppVersion } from '../../core/SettingsData';
import { useTheme } from '../../hooks/useTheme';

const LINKS = {
  website: 'https://flixor.xyz',
  github: 'https://github.com/Flixorui/flixor',
  reportIssue: 'https://github.com/Flixorui/flixor/issues',
  discord: 'https://discord.gg/flixor',
  reddit: 'https://www.reddit.com/r/flixor/',
  privacy: 'https://flixor.xyz/privacy',
};

export default function AboutSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;
  const chevron = () => <Ionicons name="chevron-forward" size={18} color="#9ca3af" />;
  const open = (url: string) => () => Linking.openURL(url).catch(() => undefined);

  return (
    <View style={[styles.container, { backgroundColor: theme.settingsBackground }]}>
      <SettingsHeader scrollY={headerScrollY} title="About" onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })} contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}>
        <SettingsCard title="FLIXOR">
          <SettingItem title="Version" description={getAppVersion()} icon="information-circle-outline" isLast={false} />
          <SettingItem
            title="App Updates"
            description="Check for updates"
            icon="cloud-download-outline"
            renderRight={chevron}
            onPress={() => nav.navigate('UpdateSettings')}
            isLast={true}
          />
        </SettingsCard>

        <SettingsCard title="COMMUNITY">
          <SettingItem title="Website" description="flixor.xyz" icon="globe-outline" renderRight={chevron} onPress={open(LINKS.website)} isLast={false} />
          <SettingItem title="GitHub" description="Source code and contributors" icon="logo-github" renderRight={chevron} onPress={open(LINKS.github)} isLast={false} />
          <SettingItem title="Report an Issue" icon="bug-outline" renderRight={chevron} onPress={open(LINKS.reportIssue)} isLast={false} />
          <SettingItem title="Discord" icon="chatbubbles-outline" renderRight={chevron} onPress={open(LINKS.discord)} isLast={false} />
          <SettingItem title="Reddit" description="r/flixor" icon="chatbox-ellipses-outline" renderRight={chevron} onPress={open(LINKS.reddit)} isLast={true} />
        </SettingsCard>

        <SettingsCard title="LEGAL">
          <SettingItem title="Privacy Policy" icon="shield-outline" renderRight={chevron} onPress={open(LINKS.privacy)} isLast={true} />
        </SettingsCard>
      </Animated.ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { paddingHorizontal: 16 },
});
