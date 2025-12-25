import React from 'react';
import { View, Text, FlatList, Pressable } from 'react-native';
import Poster from './Poster';
import * as Haptics from 'expo-haptics';
import { Ionicons } from '@expo/vector-icons';

export default function Row({ title, items, getImageUri, getTitle, authHeaders, onItemPress, onTitlePress, onBrowsePress }: {
  title: string;
  items: any[];
  getImageUri: (item: any) => string | undefined;
  getTitle: (item: any) => string | undefined;
  authHeaders?: Record<string,string>;
  onItemPress?: (item: any) => void;
  onTitlePress?: () => void;
  onBrowsePress?: () => void;
}) {
  const handleTitlePress = () => {
    if (onTitlePress) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onTitlePress();
    }
  };

  const handleBrowsePress = () => {
    if (onBrowsePress) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onBrowsePress();
    }
  };

  return (
    <View style={{ marginBottom: 16 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 15, marginTop: 15, paddingRight: 8 }}>
        <Pressable onPress={handleTitlePress} disabled={!onTitlePress}>
          <Text style={{ color: '#fff', fontSize: 16, fontWeight: '700', lineHeight: 20 }}>{title}</Text>
        </Pressable>
        {onBrowsePress && (
          <Pressable
            onPress={handleBrowsePress}
            style={({ pressed }) => ({
              paddingHorizontal: 12,
              paddingVertical: 6,
              borderRadius: 999,
              borderWidth: 1,
              borderColor: '#4a4a4a',
              backgroundColor: 'transparent',
              opacity: pressed ? 0.6 : 1,
            })}
          >
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 3 }}>
              <Text style={{ color: '#fff', fontWeight: '600', fontSize: 13, lineHeight: 15 }}>Browse</Text>
              <Ionicons name="chevron-forward-outline" size={15} color="#fff" style={{ marginTop: 1 }} />
            </View>
          </Pressable>
        )}
      </View>
      <FlatList
        horizontal
        data={items}
        keyExtractor={(_, idx) => String(idx)}
        renderItem={({ item }) => (
          <Poster uri={getImageUri(item)} title={getTitle(item)} authHeaders={authHeaders} onPress={() => onItemPress && onItemPress(item)} />
        )}
        showsHorizontalScrollIndicator={false}
      />
    </View>
  );
}
