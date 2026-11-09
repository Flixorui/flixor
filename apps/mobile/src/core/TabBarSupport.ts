import { Platform } from 'react-native';

// Native iOS bottom tabs for liquid glass effect (React Navigation v7).
// iOS 18 and below, and Android, use the JS tab bar with a blur view.
let createNativeBottomTabNavigator: any = null;
let liquidGlassAvailable = false;

if (Platform.OS === 'ios') {
  try {
    createNativeBottomTabNavigator = require('@react-navigation/bottom-tabs/unstable').createNativeBottomTabNavigator;
  } catch {
    createNativeBottomTabNavigator = null;
  }
  try {
    const glass = require('expo-glass-effect');
    liquidGlassAvailable = typeof glass.isLiquidGlassAvailable === 'function'
      ? glass.isLiquidGlassAvailable()
      : false;
  } catch {
    liquidGlassAvailable = false;
  }
}

/** True on iOS 26+, where the system draws the tab bar. */
export const usesNativeTabBar = Platform.OS === 'ios' && !!createNativeBottomTabNavigator && liquidGlassAvailable;

/**
 * Created once here: creating a navigator during render gives it a new identity each
 * time, which remounts every tab whenever a setting changes.
 */
export const NativeTab: any = usesNativeTabBar ? createNativeBottomTabNavigator() : null;
