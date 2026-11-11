/**
 * Trailers: autoplaying trailers wherever the app shows them (the Details hero and New & Hot
 * cards), so the switch isn't hidden under one screen's settings.
 * The setting keys keep their original names (detailsHero…) so saved choices carry over.
 */

import React from 'react';
import { Animated, StyleSheet, Text, View } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import SettingsHeader from '../../components/settings/SettingsHeader';
import SettingsCard from '../../components/settings/SettingsCard';
import SettingItem from '../../components/settings/SettingItem';
import SettingsSwitch from '../../components/settings/SettingsSwitch';
import { useAppSettings } from '../../hooks/useAppSettings';

export default function TrailerSettings() {
  const headerScrollY = React.useRef(new Animated.Value(0)).current;
  const nav: any = useNavigation();
  const insets = useSafeAreaInsets();
  const { settings, updateSetting } = useAppSettings();
  const headerHeight = insets.top + 52;
  const on = settings.detailsHeroInlineTrailerEnabled;

  return (
    <View style={styles.container}>
      <SettingsHeader scrollY={headerScrollY} title="Trailers" onBack={() => nav.goBack()} />
      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: headerScrollY } } }], { useNativeDriver: false })}
        contentContainerStyle={[styles.content, { paddingTop: headerHeight + 12, paddingBottom: insets.bottom + 100 }]}
      >
        <SettingsCard title="AUTOPLAY">
          <SettingItem
            title="Play Trailers Automatically"
            description="On Details and in New & Hot. Uses data."
            icon="film-outline"
            renderRight={() => (
              <SettingsSwitch value={on} onValueChange={(value) => updateSetting('detailsHeroInlineTrailerEnabled', value)} />
            )}
            isLast={!on}
          />
          {on ? (
            <SettingItem
              title="Start Muted on Details"
              description="New & Hot always starts muted"
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
        <Text style={styles.footnote}>
          The Trailers & Videos section on Details is separate: turn it on or off under Details › Sections.
        </Text>
      </Animated.ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#0b0b0d' },
  content: { paddingHorizontal: 16, paddingBottom: 40 },
  footnote: { color: '#8e8e93', fontSize: 13, lineHeight: 18, marginTop: 4, paddingHorizontal: 16 },
});
