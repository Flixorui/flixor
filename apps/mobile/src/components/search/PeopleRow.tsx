import React from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../../hooks/useTheme';
import type { PersonResult } from '../../core/SearchData';

const SIZE = 88;

export default function PeopleRow({ people, onPress }: { people: PersonResult[]; onPress: (person: PersonResult) => void }) {
  const theme = useTheme();
  if (people.length === 0) return null;

  return (
    <View style={styles.container}>
      <Text style={[styles.title, { color: theme.textPrimary }]}>People</Text>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingHorizontal: 16 }}>
        {people.map((person) => (
          <Pressable key={person.id} onPress={() => onPress(person)} style={styles.card}>
            <View style={[styles.avatar, { backgroundColor: theme.surface }]}>
              {person.image ? (
                <FastImage
                  source={{ uri: person.image, cache: FastImage.cacheControl.immutable }}
                  style={StyleSheet.absoluteFill}
                  resizeMode={FastImage.resizeMode.cover}
                />
              ) : (
                <Ionicons name="person" size={32} color={theme.textDisabled} />
              )}
            </View>
            <Text numberOfLines={2} style={[styles.name, { color: theme.textPrimary }]}>
              {person.name}
            </Text>
            {person.department ? (
              <Text numberOfLines={1} style={[styles.department, { color: theme.textTertiary }]}>
                {person.department}
              </Text>
            ) : null}
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { marginTop: 8, marginBottom: 16 },
  title: { fontSize: 18, fontWeight: '700', marginHorizontal: 16, marginBottom: 12 },
  card: { width: SIZE + 8, marginRight: 8, alignItems: 'center' },
  avatar: { width: SIZE, height: SIZE, borderRadius: SIZE / 2, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' },
  name: { fontSize: 13, fontWeight: '600', marginTop: 8, textAlign: 'center' },
  department: { fontSize: 11, marginTop: 2, textAlign: 'center' },
});
