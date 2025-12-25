import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

type SettingsCardProps = {
  title?: string;
  children: React.ReactNode;
};

export default function SettingsCard({ title, children }: SettingsCardProps) {
  return (
    <View style={styles.container}>
      {title ? <Text style={styles.title}>{title}</Text> : null}
      <View style={styles.card}>{children}</View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginBottom: 18,
  },
  title: {
    color: '#9ca3af',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1,
    marginLeft: 4,
    marginBottom: 8,
  },
  card: {
    backgroundColor: 'rgba(17,17,20,0.92)',
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    overflow: 'hidden',
  },
});
