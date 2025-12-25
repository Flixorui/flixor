import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

type SettingsHeaderProps = {
  title: string;
  onBack?: () => void;
};

export default function SettingsHeader({ title, onBack }: SettingsHeaderProps) {
  const insets = useSafeAreaInsets();

  return (
    <View style={[styles.header, { paddingTop: insets.top + 8 }]}>
      <Pressable onPress={onBack} style={styles.backButton} hitSlop={8}>
        <Ionicons name="chevron-back" size={22} color="#fff" />
      </Pressable>
      <Text style={styles.title}>{title}</Text>
      <View style={styles.trailingSpace} />
    </View>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingBottom: 10,
  },
  backButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '700',
    flex: 1,
    textAlign: 'center',
  },
  trailingSpace: {
    width: 36,
  },
});
