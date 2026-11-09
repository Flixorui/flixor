import React from 'react';
import { ActivityIndicator, StyleSheet, Text, TouchableOpacity, View } from 'react-native';

type Props = {
  message: string;
  onCancel?: () => void;
};

/** What the stream engine is doing in the background: finding or replacing a source. */
export default function StreamStatusPill({ message, onCancel }: Props) {
  return (
    <View style={styles.wrapper} pointerEvents="box-none">
      <View style={styles.pill}>
        <ActivityIndicator size="small" color="#fff" />
        <Text style={styles.text} numberOfLines={2}>
          {message}
        </Text>
        {onCancel ? (
          <TouchableOpacity onPress={onCancel} style={styles.cancel} hitSlop={8} accessibilityRole="button">
            <Text style={styles.cancelText}>Cancel</Text>
          </TouchableOpacity>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    position: 'absolute',
    top: '42%',
    left: 24,
    right: 24,
    alignItems: 'center',
    zIndex: 6,
  },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    maxWidth: 460,
    paddingHorizontal: 18,
    paddingVertical: 12,
    borderRadius: 14,
    backgroundColor: 'rgba(0,0,0,0.82)',
  },
  text: {
    flexShrink: 1,
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  cancel: {
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 8,
    backgroundColor: 'rgba(255,255,255,0.14)',
  },
  cancelText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '700',
  },
});
