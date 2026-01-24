/**
 * DownloadButton - Button to trigger downloads from Details screen
 *
 * Shows different states:
 * - Download (cloud-download icon)
 * - Downloading (progress circle)
 * - Downloaded (checkmark)
 * - Failed (retry icon)
 */

import React, { useCallback, useMemo } from 'react';
import { View, Text, Pressable, StyleSheet, ActivityIndicator, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import type { PlexMediaItem } from '@flixor/core';
import { getFlixorCore } from '../../core/index';
import { downloadService, useDownloadStatus } from '../../services/downloads';
import { DownloadStatus } from '../../types/downloads';
import DownloadProgressBar from './DownloadProgressBar';

interface DownloadButtonProps {
  metadata: PlexMediaItem;
  variant?: 'icon' | 'button' | 'pill';
  size?: 'small' | 'medium' | 'large';
  showLabel?: boolean;
}

function DownloadButton({
  metadata,
  variant = 'button',
  size = 'medium',
  showLabel = true,
}: DownloadButtonProps) {
  const serverId = useMemo(() => {
    try {
      const core = getFlixorCore();
      return core.server?.id || '';
    } catch {
      return '';
    }
  }, []);
  const globalKey = `${serverId}:${metadata.ratingKey}`;

  const { progress, isDownloaded, isDownloading, isPaused, isFailed, status } = useDownloadStatus(globalKey);

  const handlePress = useCallback(async () => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);

    try {
      if (isDownloaded) {
        // Already downloaded - show options
        Alert.alert(
          'Download Complete',
          'This item has already been downloaded.',
          [
            { text: 'OK', style: 'cancel' },
            {
              text: 'Delete Download',
              style: 'destructive',
              onPress: () => downloadService.deleteDownload(globalKey),
            },
          ]
        );
        return;
      }

      if (isDownloading) {
        // Currently downloading - offer to pause
        Alert.alert(
          'Downloading',
          'Do you want to pause this download?',
          [
            { text: 'Continue', style: 'cancel' },
            {
              text: 'Pause',
              onPress: () => downloadService.pauseDownload(globalKey),
            },
            {
              text: 'Cancel Download',
              style: 'destructive',
              onPress: () => downloadService.cancelDownload(globalKey),
            },
          ]
        );
        return;
      }

      if (isPaused) {
        // Paused - offer to resume
        Alert.alert(
          'Download Paused',
          'Resume this download?',
          [
            { text: 'Cancel', style: 'cancel' },
            {
              text: 'Resume',
              onPress: () => downloadService.resumeDownload(globalKey),
            },
            {
              text: 'Delete',
              style: 'destructive',
              onPress: () => downloadService.deleteDownload(globalKey),
            },
          ]
        );
        return;
      }

      if (isFailed) {
        // Failed - offer to retry
        Alert.alert(
          'Download Failed',
          progress?.errorMessage || 'The download failed. Would you like to retry?',
          [
            { text: 'Cancel', style: 'cancel' },
            {
              text: 'Retry',
              onPress: () => downloadService.retryDownload(globalKey),
            },
            {
              text: 'Delete',
              style: 'destructive',
              onPress: () => downloadService.deleteDownload(globalKey),
            },
          ]
        );
        return;
      }

      // Not downloaded - start download
      await downloadService.queueDownload(metadata, serverId);
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } catch (error: any) {
      Alert.alert('Download Error', error.message || 'Failed to start download');
    }
  }, [globalKey, isDownloaded, isDownloading, isPaused, isFailed, metadata, serverId, progress]);

  // Render based on variant
  const iconSize = size === 'small' ? 20 : size === 'medium' ? 24 : 28;
  const progressPercent = progress?.progress || 0;

  const getIcon = () => {
    if (isDownloaded) {
      return <Ionicons name="checkmark-circle" size={iconSize} color="#4CAF50" />;
    }
    if (isDownloading) {
      return (
        <View style={styles.progressContainer}>
          <ActivityIndicator size="small" color="#e50914" />
        </View>
      );
    }
    if (isPaused) {
      return <Ionicons name="pause-circle" size={iconSize} color="#FFA500" />;
    }
    if (isFailed) {
      return <Ionicons name="refresh-circle" size={iconSize} color="#f44336" />;
    }
    return <Ionicons name="cloud-download-outline" size={iconSize} color="#fff" />;
  };

  const getLabel = () => {
    if (isDownloaded) return 'Downloaded';
    if (isDownloading) return `${progressPercent}%`;
    if (isPaused) return 'Paused';
    if (isFailed) return 'Retry';
    return 'Download';
  };

  if (variant === 'icon') {
    return (
      <Pressable onPress={handlePress} hitSlop={8}>
        {getIcon()}
      </Pressable>
    );
  }

  if (variant === 'pill') {
    return (
      <Pressable onPress={handlePress} style={styles.pill}>
        {getIcon()}
        {showLabel && (
          <Text style={styles.pillLabel}>{getLabel()}</Text>
        )}
        {isDownloading && progressPercent > 0 && (
          <View style={styles.pillProgress}>
            <DownloadProgressBar progress={progressPercent} height={2} />
          </View>
        )}
      </Pressable>
    );
  }

  // Default button variant
  return (
    <Pressable onPress={handlePress} style={styles.button}>
      {getIcon()}
      {showLabel && (
        <Text style={styles.buttonLabel}>{getLabel()}</Text>
      )}
      {isDownloading && progressPercent > 0 && (
        <View style={styles.buttonProgress}>
          <DownloadProgressBar progress={progressPercent} height={3} />
        </View>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#333',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 8,
    minWidth: 120,
    justifyContent: 'center',
  },
  buttonLabel: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    marginLeft: 8,
  },
  buttonProgress: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    borderBottomLeftRadius: 8,
    borderBottomRightRadius: 8,
    overflow: 'hidden',
  },
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.15)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 20,
  },
  pillLabel: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '500',
    marginLeft: 6,
  },
  pillProgress: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    borderBottomLeftRadius: 20,
    borderBottomRightRadius: 20,
    overflow: 'hidden',
  },
  progressContainer: {
    width: 24,
    height: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
});

export default React.memo(DownloadButton);
