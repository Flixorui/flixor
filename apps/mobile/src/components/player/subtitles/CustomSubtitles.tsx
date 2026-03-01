import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

type Props = {
  enabled: boolean;
  text: string;
  controlsVisible?: boolean;
};

export default function CustomSubtitles({ enabled, text, controlsVisible }: Props) {
  if (!enabled || !text) {
    return null;
  }

  return (
    <View
      pointerEvents="none"
      style={[styles.container, controlsVisible ? styles.containerRaised : null]}
    >
      <View style={styles.pill}>
        <Text style={styles.text}>{text}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    left: 16,
    right: 16,
    bottom: 42,
    alignItems: 'center',
  },
  containerRaised: {
    bottom: 120,
  },
  pill: {
    maxWidth: '94%',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 12,
    backgroundColor: 'rgba(0,0,0,0.72)',
  },
  text: {
    color: '#ffffff',
    textAlign: 'center',
    fontSize: 18,
    fontWeight: '700',
    lineHeight: 24,
  },
});
