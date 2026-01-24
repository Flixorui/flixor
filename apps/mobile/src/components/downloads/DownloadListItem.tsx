/**
 * DownloadListItem - List item component for Downloads screen
 *
 * Displays:
 * - Poster thumbnail
 * - Title and metadata
 * - Progress bar (if downloading)
 * - Action buttons (play, delete, retry)
 */

import React, { useCallback } from 'react';
import { View, Text, Pressable, StyleSheet, Alert, Image } from 'react-native';
import FastImage from '@d11/react-native-fast-image';
import { Ionicons } from '@expo/vector-icons';
import * as Haptics from 'expo-haptics';
import { useNavigation } from '@react-navigation/native';
import { DownloadStatus, DownloadedMetadata, DownloadedMedia, DownloadProgress as DownloadProgressType } from '../../types/downloads';
import { downloadService, useDownloadStatus } from '../../services/downloads';
import DownloadProgressBar from './DownloadProgressBar';

interface DownloadListItemProps {
  globalKey: string;
  metadata: DownloadedMetadata;
  media: DownloadedMedia;
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
}

function formatDuration(ms: number | undefined): string {
  if (!ms) return '';
  const totalMinutes = Math.floor(ms / 60000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
}

function DownloadListItem({ globalKey, metadata, media }: DownloadListItemProps) {
  const nav: any = useNavigation();
  const { progress, isDownloaded, isDownloading, isPaused, isFailed } = useDownloadStatus(globalKey);

  const handlePlay = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);

    if (!isDownloaded || !media.videoFilePath) {
      Alert.alert('Not Available', 'This download is not yet complete.');
      return;
    }

    // Navigate to player with offline params
    nav.navigate('Player', {
      type: 'offline',
      offlineFilePath: media.videoFilePath,
      offlineGlobalKey: globalKey,
    });
  }, [isDownloaded, media.videoFilePath, globalKey, nav]);

  const handleDelete = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);

    Alert.alert(
      'Delete Download',
      `Are you sure you want to delete "${metadata.title}"? This cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => downloadService.deleteDownload(globalKey),
        },
      ]
    );
  }, [globalKey, metadata.title]);

  const handleRetry = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    downloadService.retryDownload(globalKey);
  }, [globalKey]);

  const handlePause = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    downloadService.pauseDownload(globalKey);
  }, [globalKey]);

  const handleResume = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    downloadService.resumeDownload(globalKey);
  }, [globalKey]);

  // Build subtitle
  const subtitle = metadata.type === 'episode'
    ? `S${(metadata.parentIndex || 1).toString().padStart(2, '0')}:E${(metadata.index || 1).toString().padStart(2, '0')} - ${metadata.grandparentTitle || ''}`
    : metadata.year ? `${metadata.year}` : '';

  // Build status text
  const getStatusText = () => {
    if (isDownloading) {
      const percent = progress?.progress || 0;
      const downloaded = progress?.downloadedBytes || 0;
      const total = progress?.totalBytes || 0;
      if (total > 0) {
        return `${percent}% • ${formatBytes(downloaded)} / ${formatBytes(total)}`;
      }
      return `${percent}%`;
    }
    if (isPaused) {
      return 'Paused';
    }
    if (isFailed) {
      return progress?.errorMessage || 'Failed';
    }
    if (isDownloaded) {
      const size = media.downloadedBytes ? formatBytes(media.downloadedBytes) : '';
      const duration = formatDuration(metadata.duration);
      return [size, duration].filter(Boolean).join(' • ');
    }
    return 'Queued';
  };

  // Artwork source
  const artworkSource = metadata.localThumbPath
    ? { uri: `file://${metadata.localThumbPath}` }
    : undefined;

  return (
    <View style={styles.container}>
      <Pressable
        style={styles.content}
        onPress={isDownloaded ? handlePlay : undefined}
        disabled={!isDownloaded}
      >
        {/* Poster */}
        <View style={styles.posterContainer}>
          {artworkSource ? (
            <Image source={artworkSource} style={styles.poster} resizeMode="cover" />
          ) : (
            <View style={[styles.poster, styles.posterPlaceholder]}>
              <Ionicons name="film-outline" size={24} color="#555" />
            </View>
          )}
          {isDownloaded && (
            <View style={styles.playOverlay}>
              <Ionicons name="play" size={20} color="#fff" />
            </View>
          )}
        </View>

        {/* Info */}
        <View style={styles.info}>
          <Text style={styles.title} numberOfLines={1}>
            {metadata.title}
          </Text>
          {subtitle ? (
            <Text style={styles.subtitle} numberOfLines={1}>
              {subtitle}
            </Text>
          ) : null}
          <Text style={styles.status} numberOfLines={1}>
            {getStatusText()}
          </Text>

          {/* Progress bar for active downloads */}
          {(isDownloading || isPaused) && progress && (
            <View style={styles.progressContainer}>
              <DownloadProgressBar
                progress={progress.progress}
                progressColor={isPaused ? '#FFA500' : '#e50914'}
              />
            </View>
          )}
        </View>
      </Pressable>

      {/* Actions */}
      <View style={styles.actions}>
        {isDownloading && (
          <Pressable onPress={handlePause} style={styles.actionButton} hitSlop={8}>
            <Ionicons name="pause" size={20} color="#fff" />
          </Pressable>
        )}
        {isPaused && (
          <Pressable onPress={handleResume} style={styles.actionButton} hitSlop={8}>
            <Ionicons name="play" size={20} color="#fff" />
          </Pressable>
        )}
        {isFailed && (
          <Pressable onPress={handleRetry} style={styles.actionButton} hitSlop={8}>
            <Ionicons name="refresh" size={20} color="#f44336" />
          </Pressable>
        )}
        <Pressable onPress={handleDelete} style={styles.actionButton} hitSlop={8}>
          <Ionicons name="trash-outline" size={20} color="#f44336" />
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: '#111',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#333',
  },
  content: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
  },
  posterContainer: {
    position: 'relative',
  },
  poster: {
    width: 60,
    height: 90,
    borderRadius: 6,
    backgroundColor: '#222',
  },
  posterPlaceholder: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  playOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.4)',
    borderRadius: 6,
  },
  info: {
    flex: 1,
    marginLeft: 12,
  },
  title: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
  },
  subtitle: {
    color: '#999',
    fontSize: 13,
    marginTop: 2,
  },
  status: {
    color: '#666',
    fontSize: 12,
    marginTop: 4,
  },
  progressContainer: {
    marginTop: 8,
  },
  actions: {
    flexDirection: 'row',
    alignItems: 'center',
    marginLeft: 8,
  },
  actionButton: {
    padding: 8,
    marginLeft: 4,
  },
});

export default React.memo(DownloadListItem);
