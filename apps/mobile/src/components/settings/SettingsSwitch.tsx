import React from 'react';
import { Switch, type SwitchProps } from 'react-native';
import { useTheme } from '../../hooks/useTheme';

/** A Switch that follows the picked accent, and keeps its usual color otherwise. */
export default function SettingsSwitch({ trackColor, ...props }: SwitchProps) {
  const { chosenAccent } = useTheme();
  return <Switch {...props} trackColor={chosenAccent ? { ...trackColor, true: chosenAccent } : trackColor} />;
}
