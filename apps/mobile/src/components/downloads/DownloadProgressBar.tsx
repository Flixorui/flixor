/**
 * DownloadProgressBar - Progress indicator for downloads
 */

import React from 'react';
import { View, StyleSheet } from 'react-native';

interface DownloadProgressBarProps {
  progress: number; // 0-100
  height?: number;
  backgroundColor?: string;
  progressColor?: string;
}

function DownloadProgressBar({
  progress,
  height = 4,
  backgroundColor = '#333',
  progressColor = '#e50914',
}: DownloadProgressBarProps) {
  const clampedProgress = Math.min(100, Math.max(0, progress));

  return (
    <View style={[styles.container, { height, backgroundColor }]}>
      <View
        style={[
          styles.progress,
          {
            width: `${clampedProgress}%`,
            backgroundColor: progressColor,
          },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
    borderRadius: 2,
    overflow: 'hidden',
  },
  progress: {
    height: '100%',
    borderRadius: 2,
  },
});

export default React.memo(DownloadProgressBar);
