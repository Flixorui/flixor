import React from 'react';
import { View, Text, TouchableOpacity, ScrollView, StyleSheet, Modal, Platform } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useAppSettings } from '../hooks/useAppSettings';
import type { AudioTrack, TextTrack } from './player';

export type Stream = {
  id: string;
  index: number;
  streamType: number; // 1: video, 2: audio, 3: subtitle
  codec?: string;
  language?: string;
  languageCode?: string;
  displayTitle?: string;
  extendedDisplayTitle?: string;
  selected?: boolean;
};

export type QualityOption = {
  label: string;
  value: number | 'original';
};

export type PlaybackInfo = {
  isDirectPlay: boolean;
  videoCodec?: string;
  videoResolution?: string;
  videoBitrate?: number;
  audioCodec?: string;
  audioChannels?: string;
  container?: string;
  playerBackend?: string;
  hdrType?: 'HDR10' | 'HDR10+' | 'Dolby Vision' | 'HLG' | null;
  colorSpace?: string;
  colorPrimaries?: string;
  colorTransfer?: string;
};

type PlayerSettingsSheetProps = {
  visible: boolean;
  onClose: () => void;
  // Legacy stream format (for non-KSPlayer)
  audioStreams?: Stream[];
  subtitleStreams?: Stream[];
  selectedAudio?: string | null;
  selectedSubtitle?: string | null;
  onAudioChange?: (streamId: string) => void;
  onSubtitleChange?: (streamId: string) => void;
  // KSPlayer track format (iOS)
  ksAudioTracks?: AudioTrack[];
  ksTextTracks?: TextTrack[];
  selectedKsAudioTrack?: number | null;
  selectedKsTextTrack?: number | null;
  onKsAudioChange?: (trackId: number) => void;
  onKsTextTrack?: (trackId: number) => void;
  // Quality options
  qualityOptions?: QualityOption[];
  selectedQuality?: number | 'original';
  onQualityChange?: (quality: number | 'original') => void;
  // Playback info
  playbackInfo?: PlaybackInfo;
};

export default function PlayerSettingsSheet({
  visible,
  onClose,
  audioStreams = [],
  subtitleStreams = [],
  selectedAudio,
  selectedSubtitle,
  onAudioChange,
  onSubtitleChange,
  ksAudioTracks = [],
  ksTextTracks = [],
  selectedKsAudioTrack,
  selectedKsTextTrack,
  onKsAudioChange,
  onKsTextTrack,
  qualityOptions = [],
  selectedQuality,
  onQualityChange,
  playbackInfo,
}: PlayerSettingsSheetProps) {
  // Prefer Plex streams (legacy format with proper names) over KSPlayer tracks
  // Only use KSPlayer tracks if Plex streams are not available
  const hasPlexStreams = audioStreams.length > 0 || subtitleStreams.length > 0;
  const useKsPlayer = !hasPlexStreams && (ksAudioTracks.length > 0 || ksTextTracks.length > 0);
  const [activeTab, setActiveTab] = React.useState<'audio' | 'subtitles' | 'quality' | 'info'>('subtitles');
  const { settings } = useAppSettings();
  const showBackdrop = settings.enableStreamsBackdrop;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
      presentationStyle="overFullScreen"
      supportedOrientations={['portrait', 'landscape']}
      onRequestClose={onClose}
    >
      <View style={[styles.backdrop, !showBackdrop && styles.backdropDisabled]}>
        <TouchableOpacity
          style={styles.backdropTouchable}
          activeOpacity={1}
          onPress={onClose}
        />

        <View style={styles.sheet}>
          <LinearGradient
            colors={['rgba(20,20,20,0.98)', 'rgba(15,15,15,0.98)']}
            style={styles.sheetContent}
          >
            {/* Header */}
            <View style={styles.header}>
              <Text style={styles.headerTitle}>Player Settings</Text>
              <TouchableOpacity onPress={onClose} style={styles.closeButton}>
                <Ionicons name="close" size={28} color="#fff" />
              </TouchableOpacity>
            </View>

            {/* Tabs */}
            <View style={styles.tabs}>
              <TouchableOpacity
                style={[styles.tab, activeTab === 'audio' && styles.tabActive]}
                onPress={() => setActiveTab('audio')}
              >
                <Ionicons name="volume-high" size={20} color={activeTab === 'audio' ? '#fff' : '#888'} />
                <Text style={[styles.tabText, activeTab === 'audio' && styles.tabTextActive]}>
                  Audio
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.tab, activeTab === 'subtitles' && styles.tabActive]}
                onPress={() => setActiveTab('subtitles')}
              >
                <Ionicons name="text" size={20} color={activeTab === 'subtitles' ? '#fff' : '#888'} />
                <Text style={[styles.tabText, activeTab === 'subtitles' && styles.tabTextActive]}>
                  Subtitles
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.tab, activeTab === 'quality' && styles.tabActive]}
                onPress={() => setActiveTab('quality')}
              >
                <Ionicons name="settings" size={20} color={activeTab === 'quality' ? '#fff' : '#888'} />
                <Text style={[styles.tabText, activeTab === 'quality' && styles.tabTextActive]}>
                  Quality
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[styles.tab, activeTab === 'info' && styles.tabActive]}
                onPress={() => setActiveTab('info')}
              >
                <Ionicons name="information-circle" size={20} color={activeTab === 'info' ? '#fff' : '#888'} />
                <Text style={[styles.tabText, activeTab === 'info' && styles.tabTextActive]}>
                  Info
                </Text>
              </TouchableOpacity>
            </View>

            {/* Content */}
            <ScrollView style={styles.scrollContent}>
              {activeTab === 'audio' && (
                <View>
                  {useKsPlayer ? (
                    // KSPlayer tracks (iOS)
                    ksAudioTracks.length === 0 ? (
                      <Text style={styles.emptyText}>No audio tracks available</Text>
                    ) : (
                      ksAudioTracks.map((track) => (
                        <TouchableOpacity
                          key={track.id}
                          style={styles.option}
                          onPress={() => onKsAudioChange?.(track.id)}
                        >
                          <View style={styles.optionContent}>
                            <Text style={styles.optionTitle}>
                              {track.name || track.language || `Track ${track.index}`}
                            </Text>
                            {track.languageCode && (
                              <Text style={styles.optionSubtitle}>{track.languageCode.toUpperCase()}</Text>
                            )}
                          </View>
                          {selectedKsAudioTrack === track.id && (
                            <Ionicons name="checkmark" size={24} color="#4a9eff" />
                          )}
                        </TouchableOpacity>
                      ))
                    )
                  ) : (
                    // Legacy streams (Android/expo-av)
                    audioStreams.length === 0 ? (
                      <Text style={styles.emptyText}>No audio tracks available</Text>
                    ) : (
                      audioStreams.map((stream) => (
                        <TouchableOpacity
                          key={stream.id}
                          style={styles.option}
                          onPress={() => onAudioChange?.(stream.id)}
                        >
                          <View style={styles.optionContent}>
                            <Text style={styles.optionTitle}>
                              {stream.displayTitle || stream.language || `Track ${stream.index}`}
                            </Text>
                            {stream.codec && (
                              <Text style={styles.optionSubtitle}>{stream.codec.toUpperCase()}</Text>
                            )}
                          </View>
                          {selectedAudio === stream.id && (
                            <Ionicons name="checkmark" size={24} color="#4a9eff" />
                          )}
                        </TouchableOpacity>
                      ))
                    )
                  )}
                </View>
              )}

              {activeTab === 'subtitles' && (
                <View>
                  {useKsPlayer ? (
                    // KSPlayer text tracks (iOS)
                    <>
                      {/* None option */}
                      <TouchableOpacity
                        style={styles.option}
                        onPress={() => onKsTextTrack?.(-1)}
                      >
                        <View style={styles.optionContent}>
                          <Text style={styles.optionTitle}>None</Text>
                        </View>
                        {selectedKsTextTrack === -1 && (
                          <Ionicons name="checkmark" size={24} color="#4a9eff" />
                        )}
                      </TouchableOpacity>

                      {ksTextTracks.length === 0 ? (
                        <Text style={styles.emptyText}>No subtitle tracks available</Text>
                      ) : (
                        ksTextTracks.map((track) => (
                          <TouchableOpacity
                            key={track.id}
                            style={styles.option}
                            onPress={() => onKsTextTrack?.(track.id)}
                          >
                            <View style={styles.optionContent}>
                              <Text style={styles.optionTitle}>
                                {track.name || track.language || `Track ${track.index}`}
                              </Text>
                              {track.languageCode && (
                                <Text style={styles.optionSubtitle}>{track.languageCode.toUpperCase()}</Text>
                              )}
                            </View>
                            {selectedKsTextTrack === track.id && (
                              <Ionicons name="checkmark" size={24} color="#4a9eff" />
                            )}
                          </TouchableOpacity>
                        ))
                      )}
                    </>
                  ) : (
                    // Legacy streams (Android/expo-av)
                    <>
                      {/* None option */}
                      <TouchableOpacity
                        style={styles.option}
                        onPress={() => onSubtitleChange?.('0')}
                      >
                        <View style={styles.optionContent}>
                          <Text style={styles.optionTitle}>None</Text>
                        </View>
                        {selectedSubtitle === '0' && (
                          <Ionicons name="checkmark" size={24} color="#4a9eff" />
                        )}
                      </TouchableOpacity>

                      {subtitleStreams.length === 0 ? (
                        <Text style={styles.emptyText}>No subtitle tracks available</Text>
                      ) : (
                        subtitleStreams.map((stream) => (
                          <TouchableOpacity
                            key={stream.id}
                            style={styles.option}
                            onPress={() => onSubtitleChange?.(stream.id)}
                          >
                            <View style={styles.optionContent}>
                              <Text style={styles.optionTitle}>
                                {stream.displayTitle || stream.language || `Track ${stream.index}`}
                              </Text>
                              {stream.codec && (
                                <Text style={styles.optionSubtitle}>{stream.codec.toUpperCase()}</Text>
                              )}
                            </View>
                            {selectedSubtitle === stream.id && (
                              <Ionicons name="checkmark" size={24} color="#4a9eff" />
                            )}
                          </TouchableOpacity>
                        ))
                      )}
                    </>
                  )}
                </View>
              )}

              {activeTab === 'quality' && (
                <View>
                  {qualityOptions.length === 0 ? (
                    <Text style={styles.emptyText}>No quality options available</Text>
                  ) : (
                    qualityOptions.map((option) => (
                      <TouchableOpacity
                        key={option.value}
                        style={styles.option}
                        onPress={() => onQualityChange?.(option.value)}
                      >
                        <View style={styles.optionContent}>
                          <Text style={styles.optionTitle}>{option.label}</Text>
                        </View>
                        {selectedQuality === option.value && (
                          <Ionicons name="checkmark" size={24} color="#4a9eff" />
                        )}
                      </TouchableOpacity>
                    ))
                  )}
                </View>
              )}

              {activeTab === 'info' && (
                <View>
                  {!playbackInfo ? (
                    <Text style={styles.emptyText}>No playback info available</Text>
                  ) : (
                    <>
                      {/* Playback Mode */}
                      <View style={styles.infoRow}>
                        <View style={styles.infoLabel}>
                          <Ionicons name="play-circle" size={18} color="#888" />
                          <Text style={styles.infoLabelText}>Playback Mode</Text>
                        </View>
                        <View style={[styles.infoBadge, playbackInfo.isDirectPlay ? styles.infoBadgeSuccess : styles.infoBadgeWarning]}>
                          <Text style={styles.infoBadgeText}>
                            {playbackInfo.isDirectPlay ? 'Direct Play' : 'Transcoding'}
                          </Text>
                        </View>
                      </View>

                      {/* Player Backend */}
                      {playbackInfo.playerBackend && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="hardware-chip" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Player Backend</Text>
                          </View>
                          <Text style={styles.infoValue}>{playbackInfo.playerBackend}</Text>
                        </View>
                      )}

                      {/* Container */}
                      {playbackInfo.container && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="folder" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Container</Text>
                          </View>
                          <Text style={styles.infoValue}>{playbackInfo.container.toUpperCase()}</Text>
                        </View>
                      )}

                      {/* Video Codec */}
                      {playbackInfo.videoCodec && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="videocam" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Video Codec</Text>
                          </View>
                          <Text style={styles.infoValue}>{playbackInfo.videoCodec.toUpperCase()}</Text>
                        </View>
                      )}

                      {/* Video Resolution */}
                      {playbackInfo.videoResolution && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="resize" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Resolution</Text>
                          </View>
                          <Text style={styles.infoValue}>{playbackInfo.videoResolution}</Text>
                        </View>
                      )}

                      {/* HDR Type */}
                      {playbackInfo.hdrType && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="sunny" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Dynamic Range</Text>
                          </View>
                          <View style={[styles.infoBadge, styles.infoBadgeHdr]}>
                            <Text style={styles.infoBadgeText}>{playbackInfo.hdrType}</Text>
                          </View>
                        </View>
                      )}

                      {/* Color Space */}
                      {playbackInfo.colorSpace && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="color-palette" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Color Space</Text>
                          </View>
                          <Text style={styles.infoValue}>{playbackInfo.colorSpace}</Text>
                        </View>
                      )}

                      {/* Video Bitrate */}
                      {playbackInfo.videoBitrate && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="speedometer" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Video Bitrate</Text>
                          </View>
                          <Text style={styles.infoValue}>
                            {playbackInfo.videoBitrate >= 1000
                              ? `${(playbackInfo.videoBitrate / 1000).toFixed(1)} Mbps`
                              : `${playbackInfo.videoBitrate} Kbps`}
                          </Text>
                        </View>
                      )}

                      {/* Audio Codec */}
                      {playbackInfo.audioCodec && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="volume-high" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Audio Codec</Text>
                          </View>
                          <Text style={styles.infoValue}>{playbackInfo.audioCodec.toUpperCase()}</Text>
                        </View>
                      )}

                      {/* Audio Channels */}
                      {playbackInfo.audioChannels && (
                        <View style={styles.infoRow}>
                          <View style={styles.infoLabel}>
                            <Ionicons name="headset" size={18} color="#888" />
                            <Text style={styles.infoLabelText}>Audio Channels</Text>
                          </View>
                          <Text style={styles.infoValue}>{playbackInfo.audioChannels}</Text>
                        </View>
                      )}
                    </>
                  )}
                </View>
              )}
            </ScrollView>
          </LinearGradient>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.7)',
    justifyContent: 'flex-end',
  },
  backdropDisabled: {
    backgroundColor: 'transparent',
  },
  backdropTouchable: {
    flex: 1,
  },
  sheet: {
    height: '70%',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    overflow: 'hidden',
  },
  sheetContent: {
    flex: 1,
    paddingBottom: 20,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.1)',
  },
  headerTitle: {
    fontSize: 20,
    fontWeight: '700',
    color: '#fff',
  },
  closeButton: {
    padding: 4,
  },
  tabs: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 12,
    gap: 8,
  },
  tab: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 8,
    backgroundColor: 'rgba(255,255,255,0.05)',
  },
  tabActive: {
    backgroundColor: 'rgba(74,158,255,0.2)',
  },
  tabText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#888',
  },
  tabTextActive: {
    color: '#fff',
  },
  scrollContent: {
    flex: 1,
    paddingHorizontal: 16,
  },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  optionContent: {
    flex: 1,
  },
  optionTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
    marginBottom: 2,
  },
  optionSubtitle: {
    fontSize: 13,
    color: '#888',
  },
  emptyText: {
    color: '#888',
    textAlign: 'center',
    paddingVertical: 32,
    fontSize: 15,
  },
  // Info tab styles
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 14,
    paddingHorizontal: 16,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  infoLabel: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  infoLabelText: {
    fontSize: 15,
    color: '#888',
  },
  infoValue: {
    fontSize: 15,
    fontWeight: '600',
    color: '#fff',
  },
  infoBadge: {
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 12,
  },
  infoBadgeSuccess: {
    backgroundColor: 'rgba(46, 204, 113, 0.2)',
  },
  infoBadgeWarning: {
    backgroundColor: 'rgba(241, 196, 15, 0.2)',
  },
  infoBadgeHdr: {
    backgroundColor: 'rgba(155, 89, 182, 0.3)', // Purple for HDR
  },
  infoBadgeText: {
    fontSize: 13,
    fontWeight: '700',
    color: '#fff',
  },
});
