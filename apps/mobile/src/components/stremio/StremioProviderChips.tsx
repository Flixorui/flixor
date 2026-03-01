import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';

type Props = {
  providers: Array<{ id: string; label: string }>;
  selectedProvider: string;
  onSelect: (providerId: string) => void;
};

export default function StremioProviderChips({
  providers,
  selectedProvider,
  onSelect,
}: Props) {
  return (
    <View style={styles.container}>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.content}>
        {providers.map((provider) => {
          const selected = provider.id === selectedProvider;
          return (
            <Pressable
              key={provider.id}
              onPress={() => onSelect(provider.id)}
              style={[styles.chip, selected && styles.chipSelected]}
            >
              <Text style={[styles.label, selected && styles.labelSelected]}>{provider.label}</Text>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    marginTop: 16,
  },
  content: {
    paddingHorizontal: 16,
    gap: 8,
  },
  chip: {
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.14)',
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  chipSelected: {
    backgroundColor: '#ffffff',
    borderColor: '#ffffff',
  },
  label: {
    color: '#f3f4f6',
    fontSize: 13,
    fontWeight: '700',
  },
  labelSelected: {
    color: '#111827',
  },
});
