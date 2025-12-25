import React from 'react';
import { View, Text, TouchableOpacity, ScrollView, StyleSheet, Modal } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { LinearGradient } from 'expo-linear-gradient';
import { useAppSettings } from '../hooks/useAppSettings';

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

type PlayerSettingsSheetProps = {
  visible: boolean;
  onClose: () => void;
  audioStreams: Stream[];
  subtitleStreams: Stream[];
  selectedAudio: string | null;
  selectedSubtitle: string | null;
  onAudioChange: (streamId: string) => void;
  onSubtitleChange: (streamId: string) => void;
  qualityOptions: QualityOption[];
  selectedQuality: number | 'original';
  onQualityChange: (quality: number | 'original') => void;
};

export default function PlayerSettingsSheet({
  visible,
  onClose,
  audioStreams,
  subtitleStreams,
  selectedAudio,
  selectedSubtitle,
  onAudioChange,
  onSubtitleChange,
  qualityOptions,
  selectedQuality,
  onQualityChange,
}: PlayerSettingsSheetProps) {
  const [activeTab, setActiveTab] = React.useState<'audio' | 'subtitles' | 'quality'>('subtitles');
  const { settings } = useAppSettings();
  const showBackdrop = settings.enableStreamsBackdrop;

  return (
    <Modal
      visible={visible}
      transparent
      animationType="slide"
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
            </View>

            {/* Content */}
            <ScrollView style={styles.scrollContent}>
              {activeTab === 'audio' && (
                <View>
                  {audioStreams.length === 0 ? (
                    <Text style={styles.emptyText}>No audio tracks available</Text>
                  ) : (
                    audioStreams.map((stream) => (
                      <TouchableOpacity
                        key={stream.id}
                        style={styles.option}
                        onPress={() => onAudioChange(stream.id)}
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
                  )}
                </View>
              )}

              {activeTab === 'subtitles' && (
                <View>
                  {/* None option */}
                  <TouchableOpacity
                    style={styles.option}
                    onPress={() => onSubtitleChange('0')}
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
                        onPress={() => onSubtitleChange(stream.id)}
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
                </View>
              )}

              {activeTab === 'quality' && (
                <View>
                  {qualityOptions.map((option) => (
                    <TouchableOpacity
                      key={option.value}
                      style={styles.option}
                      onPress={() => onQualityChange(option.value)}
                    >
                      <View style={styles.optionContent}>
                        <Text style={styles.optionTitle}>{option.label}</Text>
                      </View>
                      {selectedQuality === option.value && (
                        <Ionicons name="checkmark" size={24} color="#4a9eff" />
                      )}
                    </TouchableOpacity>
                  ))}
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
});
