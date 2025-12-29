/**
 * ConditionalBlurView - A BlurView wrapper that respects Android blur settings
 *
 * On iOS: Always renders BlurView
 * On Android: Only renders BlurView if enableAndroidBlurView setting is enabled,
 *             uses experimentalBlurMethod='dimezisBlurView' for blur effect.
 *             Falls back to a semi-transparent View when disabled.
 */
import React from 'react';
import { View, Platform, StyleSheet, ViewStyle, StyleProp } from 'react-native';
import { BlurView, BlurViewProps } from 'expo-blur';
import { getAppSettings } from '../core/SettingsData';

interface ConditionalBlurViewProps extends Omit<BlurViewProps, 'experimentalBlurMethod'> {
  style?: StyleProp<ViewStyle>;
  fallbackColor?: string;
  children?: React.ReactNode;
}

export default function ConditionalBlurView({
  style,
  intensity = 50,
  tint = 'dark',
  fallbackColor = 'rgba(11, 11, 13, 0.85)',
  children,
  ...rest
}: ConditionalBlurViewProps) {
  // On iOS, always use BlurView
  if (Platform.OS === 'ios') {
    return (
      <BlurView style={style} intensity={intensity} tint={tint} {...rest}>
        {children}
      </BlurView>
    );
  }

  // On Android, check settings
  const settings = getAppSettings();
  const useBlur = settings.enableAndroidBlurView;

  if (useBlur) {
    return (
      <BlurView
        style={style}
        intensity={intensity}
        tint={tint}
        experimentalBlurMethod="dimezisBlurView"
        {...rest}
      >
        {children}
      </BlurView>
    );
  }

  // Fallback: semi-transparent view
  return (
    <View style={[style, { backgroundColor: fallbackColor }]}>
      {children}
    </View>
  );
}
