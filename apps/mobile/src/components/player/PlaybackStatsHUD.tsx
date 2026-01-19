/**
 * PlaybackStatsHUD - Developer overlay showing real-time playback statistics
 * Used to verify HDR playback, frame rate, and codec information
 */
import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, StyleSheet, NativeModules, findNodeHandle, Platform } from 'react-native';
import type { MPVPlayerRef } from './MPVPlayerComponent';

// Stats format (unified for both platforms)
interface PlaybackStats {
  currentTime?: number;
  duration?: number;
  fps?: number;
  videoBitrate?: number;
  bitRate?: number;
  audioBitrate?: number;
  audioBitRate?: number;
  droppedFrames?: number;
  cacheSeconds?: number;
  naturalSize?: { width: number; height: number };
  videoCodec?: string;
  audioCodec?: string;
  colorSpace?: string;
  hdrType?: string;
  dynamicRange?: string;
  bitDepth?: number;
  audioChannels?: number;
  bufferProgress?: number;
  playableTime?: number;
  displayFPS?: number;
  avSyncDiff?: number;
  isHardwareAccelerated?: boolean;
}

interface PlaybackStatsHUDProps {
  playerRef: React.RefObject<MPVPlayerRef | null>;
  visible: boolean;
}

export default function PlaybackStatsHUD({ playerRef, visible }: PlaybackStatsHUDProps) {
  const [stats, setStats] = useState<PlaybackStats | null>(null);

  const fetchStats = useCallback(async () => {
    if (!playerRef.current || !visible) return;
    try {
      // Use native module to get playback stats
      const nodeHandle = findNodeHandle(playerRef.current as any);
      if (!nodeHandle) return;

      const MPVPlayerViewManager = NativeModules.MPVPlayerViewManager;
      if (MPVPlayerViewManager?.getPlaybackStats) {
        const playbackStats = await MPVPlayerViewManager.getPlaybackStats(nodeHandle);
        setStats(playbackStats);
      }
    } catch (err) {
      console.log('[PlaybackStatsHUD] Error fetching stats:', err);
    }
  }, [playerRef, visible]);

  useEffect(() => {
    if (!visible) {
      setStats(null);
      return;
    }

    // Fetch immediately
    fetchStats();

    // Poll every 500ms
    const interval = setInterval(fetchStats, 500);
    return () => clearInterval(interval);
  }, [visible, fetchStats]);

  if (!visible || !stats) return null;

  const formatBitrate = (bitrate: number) => {
    if (bitrate >= 1_000_000) return `${(bitrate / 1_000_000).toFixed(1)} Mbps`;
    if (bitrate >= 1_000) return `${(bitrate / 1_000).toFixed(0)} Kbps`;
    return `${bitrate} bps`;
  };

  const formatResolution = () => {
    const { width, height } = stats.naturalSize || {};
    if (!width || !height) return 'Unknown';
    return `${width}x${height}`;
  };

  const getHDRBadgeStyle = () => {
    const range = stats.dynamicRange?.toLowerCase() || '';
    if (range.includes('dolby') || range.includes('vision')) return styles.badgeDolbyVision;
    if (range.includes('hdr10+')) return styles.badgeHDR10Plus;
    if (range.includes('hdr10') || range.includes('hdr')) return styles.badgeHDR10;
    if (range.includes('hlg')) return styles.badgeHLG;
    return styles.badgeSDR;
  };

  const getDynamicRangeLabel = () => {
    const range = stats.dynamicRange?.toLowerCase() || '';
    if (range.includes('dolby') || range.includes('vision')) return 'Dolby Vision';
    if (range.includes('hdr10+')) return 'HDR10+';
    if (range.includes('hdr10') || range.includes('hdr')) return 'HDR10';
    if (range.includes('hlg')) return 'HLG';
    if (range === 'sdr') return 'SDR';
    return stats.dynamicRange || 'Unknown';
  };

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerText}>Playback Stats</Text>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Video</Text>
        <View style={styles.row}>
          <Text style={styles.label}>Resolution:</Text>
          <Text style={styles.value}>{formatResolution()}</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Frame Rate:</Text>
          <Text style={styles.value}>{stats.fps?.toFixed(2) || '0'} fps</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Dynamic Range:</Text>
          <View style={[styles.badge, getHDRBadgeStyle()]}>
            <Text style={styles.badgeText}>{getDynamicRangeLabel()}</Text>
          </View>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Bit Depth:</Text>
          <Text style={styles.value}>{stats.bitDepth || 0}-bit</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Codec:</Text>
          <Text style={styles.value}>{stats.videoCodec || 'Unknown'}</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Bitrate:</Text>
          <Text style={styles.value}>{formatBitrate(stats.bitRate || 0)}</Text>
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Audio</Text>
        <View style={styles.row}>
          <Text style={styles.label}>Codec:</Text>
          <Text style={styles.value}>{stats.audioCodec || 'Unknown'}</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Channels:</Text>
          <Text style={styles.value}>{stats.audioChannels || 0}</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Bitrate:</Text>
          <Text style={styles.value}>{formatBitrate(stats.audioBitRate || 0)}</Text>
        </View>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Buffer</Text>
        <View style={styles.row}>
          <Text style={styles.label}>Progress:</Text>
          <Text style={styles.value}>{((stats.bufferProgress || 0) * 100).toFixed(0)}%</Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Playable:</Text>
          <Text style={styles.value}>{stats.playableTime?.toFixed(1) || '0'}s</Text>
        </View>
      </View>

      {/* Real-time performance stats (KSMEPlayer only) */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Performance</Text>
        <View style={styles.row}>
          <Text style={styles.label}>Render FPS:</Text>
          <Text style={[styles.value, (stats.displayFPS ?? 0) < (stats.fps ?? 24) * 0.9 ? styles.valueWarning : null]}>
            {stats.displayFPS?.toFixed(1) || 'N/A'} fps
          </Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>Dropped:</Text>
          <Text style={[styles.value, (stats.droppedFrames ?? 0) > 0 ? styles.valueWarning : null]}>
            {stats.droppedFrames ?? 0} frames
          </Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>A/V Sync:</Text>
          <Text style={[styles.value, Math.abs(stats.avSyncDiff ?? 0) > 0.1 ? styles.valueWarning : null]}>
            {stats.avSyncDiff != null ? `${(stats.avSyncDiff * 1000).toFixed(0)}ms` : 'N/A'}
          </Text>
        </View>
        <View style={styles.row}>
          <Text style={styles.label}>HW Accel:</Text>
          <View style={[styles.badge, stats.isHardwareAccelerated ? styles.badgeHW : styles.badgeSW]}>
            <Text style={styles.badgeText}>{stats.isHardwareAccelerated ? 'ON' : 'OFF'}</Text>
          </View>
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 60,
    left: 20,
    backgroundColor: 'rgba(0, 0, 0, 0.85)',
    borderRadius: 12,
    padding: 12,
    minWidth: 220,
    borderWidth: 1,
    borderColor: 'rgba(255, 255, 255, 0.1)',
  },
  header: {
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255, 255, 255, 0.2)',
    paddingBottom: 8,
    marginBottom: 8,
  },
  headerText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  section: {
    marginBottom: 10,
  },
  sectionTitle: {
    color: '#8e8e93',
    fontSize: 11,
    fontWeight: '600',
    textTransform: 'uppercase',
    marginBottom: 4,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 2,
  },
  label: {
    color: '#a0a0a0',
    fontSize: 12,
  },
  value: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  valueWarning: {
    color: '#ff6b6b',
  },
  badge: {
    paddingHorizontal: 8,
    paddingVertical: 2,
    borderRadius: 4,
  },
  badgeText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '700',
  },
  badgeSDR: {
    backgroundColor: '#555',
  },
  badgeHDR10: {
    backgroundColor: '#8e44ad',
  },
  badgeHDR10Plus: {
    backgroundColor: '#9b59b6',
  },
  badgeDolbyVision: {
    backgroundColor: '#000',
    borderWidth: 1,
    borderColor: '#e5a00d',
  },
  badgeHLG: {
    backgroundColor: '#27ae60',
  },
  badgeHW: {
    backgroundColor: '#27ae60',
  },
  badgeSW: {
    backgroundColor: '#e74c3c',
  },
});
