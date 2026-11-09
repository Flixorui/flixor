import React, { useMemo } from 'react';
import { Platform, StyleSheet, View } from 'react-native';

type Marker = { type: string; startTimeOffset: number; endTimeOffset: number };

type Props = {
  markers: Marker[];
  durationMs: number;
  color: string;
};

const MARKED_TYPES = new Set(['intro', 'recap', 'credits', 'preview', 'postcredits']);
// The native sliders inset their track differently from the view edges.
const TRACK_INSET = Platform.OS === 'android' ? 16 : 2;

/** Intro, recap and credits ranges drawn on the seek bar. Never takes the slider's touches. */
function SeekBarMarks({ markers, durationMs, color }: Props) {
  const segments = useMemo(() => {
    if (durationMs <= 0) return [];
    return markers
      .filter((marker) => MARKED_TYPES.has(marker.type))
      .map((marker) => ({
        key: `${marker.type}-${marker.startTimeOffset}`,
        start: Math.max(0, marker.startTimeOffset / durationMs),
        end: Math.min(1, marker.endTimeOffset / durationMs),
      }))
      .filter((segment) => segment.end > segment.start);
  }, [durationMs, markers]);

  if (segments.length === 0) {
    return null;
  }

  return (
    <View pointerEvents="none" style={styles.layer}>
      {segments.map((segment) => (
        <View
          key={segment.key}
          style={[
            styles.segment,
            {
              left: `${segment.start * 100}%`,
              width: `${(segment.end - segment.start) * 100}%`,
              backgroundColor: color,
            },
          ]}
        />
      ))}
    </View>
  );
}

export default React.memo(SeekBarMarks);

const styles = StyleSheet.create({
  layer: {
    position: 'absolute',
    top: 12,
    height: 4,
    left: TRACK_INSET,
    right: TRACK_INSET,
  },
  segment: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    minWidth: 2,
    borderRadius: 1,
  },
});
