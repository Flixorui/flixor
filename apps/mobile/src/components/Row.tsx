import React from 'react';
import { View, Text, FlatList, Pressable } from 'react-native';
import Poster from './Poster';
import * as Haptics from 'expo-haptics';
import { Ionicons } from '@expo/vector-icons';

function Row({ title, items, getImageUri, getTitle, getSubtitle, authHeaders, onItemPress, onTitlePress, onBrowsePress }: {
  title: string;
  items: any[];
  getImageUri: (item: any) => string | undefined;
  getTitle: (item: any) => string | undefined;
  getSubtitle?: (item: any) => string | undefined;
  authHeaders?: Record<string,string>;
  onItemPress?: (item: any) => void;
  onTitlePress?: () => void;
  onBrowsePress?: () => void;
}) {
  const handleTitlePress = () => {
    // Prefer onBrowsePress for chevron tap, fall back to onTitlePress
    const handler = onBrowsePress || onTitlePress;
    if (handler) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      handler();
    }
  };

  return (
    <View style={{ marginBottom: 16 }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 15, marginTop: 15, paddingHorizontal: 16 }}>
        <Pressable
          onPress={handleTitlePress}
          disabled={!onBrowsePress && !onTitlePress}
          style={{ flexDirection: 'row', alignItems: 'center' }}
        >
          <Text style={{ color: '#fff', fontSize: 18, fontWeight: '700', lineHeight: 22 }}>{title}</Text>
          {(onBrowsePress || onTitlePress) && (
            <Ionicons name="chevron-forward" size={18} color="#fff" style={{ marginLeft: 4, marginTop: 1 }} />
          )}
        </Pressable>
      </View>
      <FlatList
        horizontal
        data={items}
        keyExtractor={(item, idx) => item.id || item.ratingKey || `${title}-${idx}`}
        renderItem={({ item }) => (
          <Poster uri={getImageUri(item)} title={getTitle(item)} subtitle={getSubtitle?.(item)} authHeaders={authHeaders} onPress={() => onItemPress && onItemPress(item)} />
        )}
        showsHorizontalScrollIndicator={false}
        bounces={false}
        overScrollMode="never"
        alwaysBounceHorizontal={false}
        contentContainerStyle={{ paddingHorizontal: 16 }}
        windowSize={5}
        initialNumToRender={6}
        maxToRenderPerBatch={4}
        removeClippedSubviews={true}
        getItemLayout={(_, index) => ({ length: 122, offset: 122 * index, index })}
      />
    </View>
  );
}

export default React.memo(Row);
