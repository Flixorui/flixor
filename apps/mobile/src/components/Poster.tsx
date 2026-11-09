import React from 'react';
import { View, Text, Pressable } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import * as Haptics from 'expo-haptics';
import { Ionicons } from '@expo/vector-icons';
import { useAppSettings } from '../hooks/useAppSettings';

export const POSTER_SIZES = {
  small: { width: 96, height: 144 },
  medium: { width: 110, height: 165 },
  large: { width: 128, height: 192 },
} as const;

export const POSTER_GAP = 12;
export const LANDSCAPE_CARD_SIZE = { width: 220, height: 124 } as const;

function Poster({ uri, title, subtitle, rating, width, height, authHeaders, onPress }: { uri?: string; title?: string; subtitle?: string; rating?: number; width?: number; height?: number; authHeaders?: Record<string,string>; onPress?: ()=>void }) {
  const { settings } = useAppSettings();
  const size = POSTER_SIZES[settings.posterSize] || POSTER_SIZES.medium;
  const finalWidth = width ?? size.width;
  const finalHeight = height ?? size.height;
  const border = { borderRadius: settings.posterBorderRadius, overflow: 'hidden' } as const;

  const handlePress = () => {
    if (onPress) {
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      onPress();
    }
  };

  return (
    <Pressable onPress={handlePress} style={{ width: finalWidth, marginRight: POSTER_GAP }} disabled={!onPress}>
      <View style={[{ width: finalWidth, height: finalHeight, backgroundColor: '#222' }, border]}>
        {uri ? (
          <FastImage
            source={{
              uri,
              headers: authHeaders,
              priority: FastImage.priority.normal,
              cache: FastImage.cacheControl.immutable,
            }}
            style={{ width: '100%', height: '100%' }}
            resizeMode={FastImage.resizeMode.cover}
          />
        ) : (
          <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ color: '#555', fontSize: 12 }}>No Image</Text>
          </View>
        )}
        {settings.showRatingBadges && rating && rating > 0 ? (
          <View style={{ position: 'absolute', top: 6, right: 6, flexDirection: 'row', alignItems: 'center', backgroundColor: 'rgba(0,0,0,0.65)', borderRadius: 6, paddingHorizontal: 5, paddingVertical: 2 }}>
            <Ionicons name="star" size={9} color="#FFC857" />
            <Text style={{ color: '#fff', fontSize: 10, fontWeight: '600', marginLeft: 3 }}>{rating.toFixed(1)}</Text>
          </View>
        ) : null}
      </View>
      {settings.showPosterTitles && (title || subtitle) ? (
        <View style={{ marginTop: 6 }}>
          {title ? (
            <Text style={{ color: '#ddd', fontSize: 12 }} numberOfLines={1}>{title}</Text>
          ) : null}
          {subtitle ? (
            <Text style={{ color: '#888', fontSize: 11, marginTop: 2 }} numberOfLines={1}>{subtitle}</Text>
          ) : null}
        </View>
      ) : null}
    </Pressable>
  );
}

export default React.memo(Poster);
