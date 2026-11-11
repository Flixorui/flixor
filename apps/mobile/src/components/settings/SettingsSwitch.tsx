import React from 'react';
import { Switch, type SwitchProps } from 'react-native';
import { useTheme } from '../../hooks/useTheme';

/**
 * A Switch in the accent color. Switches are one of the two places the accent appears
 * (the other is progress), so this ignores the caller's "on" color; Default is Flixor red.
 */
export default function SettingsSwitch({ trackColor, ...props }: SwitchProps) {
  const { accent } = useTheme();
  return <Switch {...props} trackColor={{ ...trackColor, true: accent }} />;
}
