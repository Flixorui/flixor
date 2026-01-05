import React from 'react';
import { View, Text, Pressable, StyleSheet, Animated } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import ConditionalBlurView from '../ConditionalBlurView';

type SettingsHeaderProps = {
  title: string;
  onBack?: () => void;
  scrollY?: Animated.Value;
};

export default function SettingsHeader({ title, onBack, scrollY }: SettingsHeaderProps) {
  const insets = useSafeAreaInsets();
  const headerHeight = insets.top + 52;

  // Animate blur/tint based on scroll (matching TopAppBar behavior)
  const blurOpacity = scrollY
    ? scrollY.interpolate({ inputRange: [0, 120], outputRange: [0, 1], extrapolate: 'clamp' })
    : new Animated.Value(1);
  const separatorOpacity = scrollY
    ? scrollY.interpolate({ inputRange: [0, 120], outputRange: [0, 0.08], extrapolate: 'clamp' })
    : new Animated.Value(0.08);

  return (
    <View style={[styles.header, { height: headerHeight }]}>
      {/* Animated blur background - fades in on scroll */}
      <Animated.View style={[StyleSheet.absoluteFillObject, { opacity: blurOpacity }]}>
        <ConditionalBlurView intensity={90} tint="dark" style={StyleSheet.absoluteFillObject} />
        {/* Glass tint overlay */}
        <View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { backgroundColor: 'rgba(27,10,16,0.12)' }]} />
      </Animated.View>
      {/* Hairline separator - fades in on scroll */}
      <Animated.View style={[styles.separator, { opacity: separatorOpacity }]} />

      {/* Content */}
      <View style={[styles.content, { paddingTop: insets.top }]}>
        {onBack ? (
          <Pressable onPress={onBack} style={styles.backButton} hitSlop={8}>
            <Ionicons name="chevron-back" size={22} color="#fff" />
          </Pressable>
        ) : null}
        <Text style={styles.title}>{title}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 20,
    overflow: 'hidden',
  },
  content: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
  },
  separator: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    height: StyleSheet.hairlineWidth,
    backgroundColor: 'rgba(255,255,255,1)',
  },
  backButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 8,
  },
  title: {
    color: '#fff',
    fontSize: 25,
    fontWeight: '600',
  },
});
