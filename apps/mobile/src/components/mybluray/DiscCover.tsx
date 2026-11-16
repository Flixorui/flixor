/**
 * A disc cover drawn from Blu-ray.com's full front scan, with MyBluray's
 * small cover shown while it loads and kept if the full scan fails.
 * expo-image decodes at the drawn size, so grid tiles cost no more memory.
 */
import React, { useState } from 'react';
import { StyleSheet, type StyleProp, type ImageStyle } from 'react-native';
import { Image } from 'expo-image';
import { fullCoverUrl } from '../../core/mybluray/editionText';

export default function DiscCover({ uri, style = StyleSheet.absoluteFill }: { uri: string; style?: StyleProp<ImageStyle> }) {
  const full = fullCoverUrl(uri);
  const [failed, setFailed] = useState<string | null>(null);
  const useFull = full && full !== uri && failed !== full;
  return (
    <Image
      source={{ uri: useFull ? full : uri }}
      placeholder={useFull ? { uri } : undefined}
      placeholderContentFit="cover"
      contentFit="cover"
      transition={0}
      recyclingKey={uri}
      onError={() => useFull && setFailed(full)}
      style={style}
    />
  );
}
