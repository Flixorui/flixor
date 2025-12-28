import React, { useState, useCallback } from 'react';
import { View, Text, Modal, Pressable, StyleSheet, Dimensions, ActivityIndicator } from 'react-native';
import { BlurView } from 'expo-blur';
import * as Haptics from 'expo-haptics';
import YoutubePlayer from 'react-native-youtube-iframe';

interface TrailerVideo {
  key: string;
  name: string;
  site: string;
  type: string;
  official?: boolean;
  publishedAt?: string;
}

interface TrailerModalProps {
  visible: boolean;
  trailer: TrailerVideo | null;
  onClose: () => void;
  contentTitle?: string;
}

const { width: SCREEN_WIDTH, height: SCREEN_HEIGHT } = Dimensions.get('window');
const isTablet = SCREEN_WIDTH >= 768;

// Modal sizing
const MODAL_WIDTH = isTablet ? SCREEN_WIDTH * 0.8 : SCREEN_WIDTH * 0.95;
const MODAL_MAX_HEIGHT = isTablet ? SCREEN_HEIGHT * 0.8 : SCREEN_HEIGHT * 0.7;

// Format trailer type for display
function formatTrailerType(type: string): string {
  switch (type) {
    case 'Trailer': return 'Official Trailer';
    case 'Teaser': return 'Teaser';
    case 'Clip': return 'Clip';
    case 'Featurette': return 'Featurette';
    case 'Behind the Scenes': return 'Behind the Scenes';
    default: return type;
  }
}

export default function TrailerModal({ visible, trailer, onClose, contentTitle }: TrailerModalProps) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [playing, setPlaying] = useState(true);

  const handleReady = useCallback(() => {
    setLoading(false);
    setError(false);
  }, []);

  const handleError = useCallback(() => {
    setLoading(false);
    setError(true);
  }, []);

  const handleStateChange = useCallback((state: string) => {
    if (state === 'ended') {
      setPlaying(false);
    }
  }, []);

  const handleClose = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setPlaying(false);
    setLoading(true);
    setError(false);
    onClose();
  }, [onClose]);

  const handleRetry = useCallback(() => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setError(false);
    setLoading(true);
    setPlaying(true);
  }, []);

  if (!trailer) return null;

  const year = trailer.publishedAt ? new Date(trailer.publishedAt).getFullYear() : null;

  return (
    <Modal
      visible={visible}
      animationType="fade"
      transparent
      onRequestClose={handleClose}
      supportedOrientations={['portrait', 'landscape']}
    >
      <Pressable style={styles.overlay} onPress={handleClose}>
        <Pressable style={[styles.modalContainer, { width: MODAL_WIDTH, maxHeight: MODAL_MAX_HEIGHT }]} onPress={(e) => e.stopPropagation()}>
          <BlurView intensity={100} tint="dark" style={styles.modalBlur}>
            {/* Header */}
            <View style={styles.header}>
              <View style={styles.headerLeft}>
                <Text style={styles.title} numberOfLines={2}>
                  {trailer.name}
                </Text>
                <Text style={styles.meta}>
                  {formatTrailerType(trailer.type)}{year ? ` • ${year}` : ''}
                </Text>
              </View>
              <Pressable
                onPress={handleClose}
                style={({ pressed }) => [
                  styles.closeButton,
                  { opacity: pressed ? 0.7 : 1 }
                ]}
              >
                <Text style={styles.closeButtonText}>Close</Text>
              </Pressable>
            </View>

            {/* Player Container */}
            <View style={styles.playerContainer}>
              {loading && (
                <View style={styles.loadingContainer}>
                  <ActivityIndicator size="large" color="#e50914" />
                  <Text style={styles.loadingText}>Loading trailer...</Text>
                </View>
              )}

              {error && !loading && (
                <View style={styles.errorContainer}>
                  <Text style={styles.errorText}>Unable to play trailer</Text>
                  <Pressable
                    onPress={handleRetry}
                    style={({ pressed }) => [
                      styles.retryButton,
                      { opacity: pressed ? 0.8 : 1 }
                    ]}
                  >
                    <Text style={styles.retryButtonText}>Try Again</Text>
                  </Pressable>
                </View>
              )}

              <YoutubePlayer
                height={MODAL_WIDTH * (9 / 16)}
                width={MODAL_WIDTH}
                videoId={trailer.key}
                play={playing}
                onReady={handleReady}
                onError={handleError}
                onChangeState={handleStateChange}
                webViewProps={{
                  allowsInlineMediaPlayback: true,
                  mediaPlaybackRequiresUserAction: false,
                }}
                initialPlayerParams={{
                  controls: true,
                  modestbranding: true,
                  rel: false,
                  showClosedCaptions: false,
                }}
              />
            </View>

            {/* Footer */}
            {contentTitle && (
              <View style={styles.footer}>
                <Text style={styles.footerText}>{contentTitle}</Text>
              </View>
            )}
          </BlurView>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContainer: {
    borderRadius: 20,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.15)',
  },
  modalBlur: {
    overflow: 'hidden',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    paddingHorizontal: 20,
    paddingVertical: 18,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.08)',
  },
  headerLeft: {
    flex: 1,
    marginRight: 16,
    gap: 4,
  },
  title: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
    lineHeight: 20,
  },
  meta: {
    color: 'rgba(255,255,255,0.5)',
    fontSize: 12,
    fontWeight: '500',
  },
  closeButton: {
    backgroundColor: 'rgba(255,255,255,0.1)',
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 16,
  },
  closeButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  playerContainer: {
    aspectRatio: 16 / 9,
    backgroundColor: '#000',
    position: 'relative',
  },
  loadingContainer: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#000',
    gap: 16,
    zIndex: 10,
  },
  loadingText: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 14,
  },
  errorContainer: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#000',
    padding: 20,
    gap: 16,
    zIndex: 10,
  },
  errorText: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 14,
    textAlign: 'center',
  },
  retryButton: {
    backgroundColor: '#e50914',
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 20,
  },
  retryButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  footer: {
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.08)',
  },
  footerText: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 13,
    fontWeight: '500',
  },
});
