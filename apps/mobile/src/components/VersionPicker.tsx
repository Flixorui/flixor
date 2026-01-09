import React from 'react';
import { View, Text, Modal, Pressable, ScrollView, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { BlurView } from 'expo-blur';
import { TechBadge } from './badges';

export interface MediaVersion {
  index: number;
  resolution: string;      // "4K", "1080p", etc.
  videoCodec: string;      // "HEVC", "H.264"
  hdrType?: string | null; // "hdr10+", "dolby-vision", "hdr"
  audioCodec: string;      // "TrueHD Atmos", "AAC"
  audioChannels: string;   // "7.1", "5.1", "Stereo"
  bitrate?: string;        // "45 Mbps"
  fileSize?: string;       // "25.3 GB"
  hasSubtitles?: boolean;  // Has any subtitle tracks
  hasSDH?: boolean;        // Has SDH (Subtitles for Deaf/Hard of Hearing)
}

interface VersionPickerProps {
  visible: boolean;
  onClose: () => void;
  onSelect: (mediaIndex: number) => void;
  versions: MediaVersion[];
  title?: string;
}

export default function VersionPicker({ visible, onClose, onSelect, versions, title }: VersionPickerProps) {
  if (!visible) return null;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <Pressable style={styles.backdrop} onPress={onClose}>
        <BlurView intensity={40} tint="dark" style={styles.blurView}>
          <Pressable style={styles.content} onPress={(e) => e.stopPropagation()}>
            <View style={styles.header}>
              <Text style={styles.title}>{title || 'Select Version'}</Text>
              <Pressable onPress={onClose} style={styles.closeButton}>
                <Ionicons name="close" size={24} color="#fff" />
              </Pressable>
            </View>

            <ScrollView style={styles.list} showsVerticalScrollIndicator={false}>
              {versions.map((version, idx) => (
                <Pressable
                  key={version.index}
                  style={({ pressed }) => [
                    styles.versionRow,
                    pressed && styles.versionRowPressed,
                  ]}
                  onPress={() => onSelect(version.index)}
                >
                  <View style={styles.versionInfo}>
                    {/* Resolution, HDR, and accessibility badges */}
                    <View style={styles.badgeRow}>
                      {(version.resolution === '4K' || version.resolution === '2160p') && (
                        <TechBadge type="4k" size={12} />
                      )}
                      {(version.resolution === '1080p' || version.resolution === 'HD') && (
                        <TechBadge type="hd" size={12} />
                      )}
                      {version.hdrType && (
                        <View style={styles.badgeSpacing}>
                          <TechBadge type={version.hdrType as any} size={12} />
                        </View>
                      )}
                      {version.hasSDH && (
                        <View style={styles.badgeSpacing}>
                          <TechBadge type="sdh" size={12} />
                        </View>
                      )}
                      {(version.hasSubtitles || version.hasSDH) && (
                        <View style={styles.badgeSpacing}>
                          <TechBadge type="cc" size={12} />
                        </View>
                      )}
                    </View>

                    {/* Codec info */}
                    <Text style={styles.codecText}>
                      {version.videoCodec} {version.resolution}
                    </Text>

                    {/* Audio info */}
                    <Text style={styles.audioText}>
                      {version.audioCodec} {version.audioChannels}
                    </Text>

                    {/* File info */}
                    <View style={styles.metaRow}>
                      {version.bitrate && (
                        <Text style={styles.metaText}>{version.bitrate}</Text>
                      )}
                      {version.bitrate && version.fileSize && (
                        <Text style={styles.metaText}> • </Text>
                      )}
                      {version.fileSize && (
                        <Text style={styles.metaText}>{version.fileSize}</Text>
                      )}
                    </View>
                  </View>

                  <Ionicons name="play-circle" size={32} color="#fff" />
                </Pressable>
              ))}
            </ScrollView>
          </Pressable>
        </BlurView>
      </Pressable>
    </Modal>
  );
}

// Helper functions for parsing Plex media data

export function getResolutionLabel(width: number, height: number): string {
  if (width >= 3840 || height >= 2160) return '4K';
  if (width >= 1920 || height >= 1080) return '1080p';
  if (width >= 1280 || height >= 720) return '720p';
  if (width >= 720) return '480p';
  return 'SD';
}

export function detectHDRType(videoStream: any): string | null {
  if (!videoStream) return null;

  const displayTitle = (videoStream.displayTitle || '').toLowerCase();
  const colorTrc = (videoStream.colorTrc || '').toLowerCase();

  if (displayTitle.includes('dolby vision') || displayTitle.includes('dovi')) {
    return 'dolby-vision';
  }
  if (displayTitle.includes('hdr10+') || displayTitle.includes('hdr10 plus') || colorTrc.includes('smpte2094')) {
    return 'hdr10+';
  }
  if (displayTitle.includes('hdr10') || displayTitle.includes('hdr 10') || colorTrc.includes('smpte2084') || colorTrc.includes('pq')) {
    return 'hdr';
  }
  if (displayTitle.includes('hlg') || colorTrc.includes('hlg')) {
    return 'hdr';
  }
  if (videoStream.bitDepth >= 10) {
    return 'hdr';
  }

  return null;
}

export function getChannelLabel(channels: number | undefined): string {
  if (!channels) return 'Stereo';
  if (channels >= 8) return '7.1';
  if (channels >= 6) return '5.1';
  if (channels >= 2) return 'Stereo';
  return 'Mono';
}

export function formatBytes(bytes: number): string {
  if (bytes >= 1073741824) {
    return `${(bytes / 1073741824).toFixed(1)} GB`;
  }
  if (bytes >= 1048576) {
    return `${(bytes / 1048576).toFixed(0)} MB`;
  }
  return `${(bytes / 1024).toFixed(0)} KB`;
}

export function parseVersionDetails(media: any, index: number): MediaVersion {
  const width = media.width || 0;
  const height = media.height || 0;
  const streams = media.Part?.[0]?.Stream || [];
  const videoStream = streams.find((s: any) => s.streamType === 1);
  const audioStream = streams.find((s: any) => s.streamType === 2);

  // Find subtitle streams (streamType 3)
  const subtitleStreams = streams.filter((s: any) => s.streamType === 3);
  const hasSubtitles = subtitleStreams.length > 0;

  // Check for SDH subtitles (look for "SDH" in displayTitle or title)
  const hasSDH = subtitleStreams.some((s: any) => {
    const displayTitle = (s.displayTitle || s.title || '').toLowerCase();
    return displayTitle.includes('sdh') ||
           displayTitle.includes('hearing') ||
           displayTitle.includes('deaf');
  });

  return {
    index,
    resolution: getResolutionLabel(width, height),
    videoCodec: videoStream?.codec?.toUpperCase() || media.videoCodec?.toUpperCase() || 'Unknown',
    hdrType: detectHDRType(videoStream),
    audioCodec: audioStream?.displayTitle || audioStream?.codec?.toUpperCase() || media.audioCodec?.toUpperCase() || 'Unknown',
    audioChannels: getChannelLabel(audioStream?.channels || media.audioChannels),
    bitrate: media.bitrate ? `${Math.round(media.bitrate / 1000)} Mbps` : undefined,
    fileSize: media.Part?.[0]?.size ? formatBytes(media.Part[0].size) : undefined,
    hasSubtitles,
    hasSDH,
  };
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.5)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  blurView: {
    width: '90%',
    maxWidth: 400,
    borderRadius: 16,
    overflow: 'hidden',
  },
  content: {
    backgroundColor: 'rgba(30,30,30,0.95)',
    padding: 20,
    maxHeight: '80%',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  title: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '700',
  },
  closeButton: {
    padding: 4,
  },
  list: {
    flexGrow: 0,
  },
  versionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 16,
    paddingHorizontal: 12,
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 12,
    marginBottom: 10,
  },
  versionRowPressed: {
    backgroundColor: 'rgba(255,255,255,0.15)',
  },
  versionInfo: {
    flex: 1,
    marginRight: 12,
  },
  badgeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 6,
  },
  badgeSpacing: {
    marginLeft: 6,
  },
  codecText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 2,
  },
  audioText: {
    color: '#aaa',
    fontSize: 13,
    marginBottom: 4,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  metaText: {
    color: '#777',
    fontSize: 12,
  },
});
