/**
 * Full-screen player for an Apple TV trailer (native controls, AirPlay),
 * up to 4K HDR as the screen and connection allow. If the stream fails it
 * switches to the trailer's YouTube fallback.
 * macOS reference: TrailerPlayer full-screen mode.
 */
import React, { useState } from 'react';
import { ActivityIndicator, Modal, StatusBar, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useEventListener } from 'expo';
import { useVideoPlayer, VideoView } from 'expo-video';
import type { MergedTrailer } from '../core/mybluray/trailers';
import { RoundGlassButton } from './GlassPill';

export default function HlsTrailerModal({
  trailer,
  onClose,
  onFallback,
}: {
  trailer: MergedTrailer | null;
  onClose: () => void;
  /** Play this YouTube key instead (the stream failed). */
  onFallback: (youtubeKey: string) => void;
}) {
  const insets = useSafeAreaInsets();
  const [failedUrl, setFailedUrl] = useState<string | null>(null);

  if (!trailer?.streamUrl) return null;
  const streamUrl = trailer.streamUrl;
  const failed = failedUrl === streamUrl;

  const fail = (error: unknown) => {
    console.log('[Trailer] stream failed', String(error));
    if (trailer.fallbackYouTubeKey) onFallback(trailer.fallbackYouTubeKey);
    else setFailedUrl(streamUrl);
  };

  return (
    <Modal visible animationType="fade" supportedOrientations={['portrait', 'landscape', 'landscape-left', 'landscape-right']} onRequestClose={onClose} statusBarTranslucent>
      <StatusBar hidden />
      <View style={styles.root}>
        {/* Our title and close button get their own bar: over the video they collided with the
            native player's controls (full screen and AirPlay top left, mute top right) */}
        <View style={[styles.top, { paddingTop: insets.top + 6, paddingLeft: insets.left + 16, paddingRight: insets.right + 16 }]}>
          <Text style={styles.title} numberOfLines={1}>{trailer.name}</Text>
          <RoundGlassButton icon="close" label="Close trailer" size={38} iconSize={22} onPress={onClose} />
        </View>
        <View style={[styles.stage, { marginBottom: insets.bottom }]}>
          {failed ? (
            <View style={styles.failed}>
              <Text style={styles.failedText}>This trailer won't play right now.</Text>
            </View>
          ) : (
            // Keyed by URL: each trailer gets its own player
            <TrailerStage key={streamUrl} streamUrl={streamUrl} onFail={fail} />
          )}
        </View>
      </View>
    </Modal>
  );
}

function TrailerStage({ streamUrl, onFail }: { streamUrl: string; onFail: (error: unknown) => void }) {
  const [loading, setLoading] = useState(true);
  const player = useVideoPlayer(streamUrl, (p) => {
    p.play();
  });

  useEventListener(player, 'statusChange', ({ status, error }) => {
    if (status === 'error') onFail(error?.message ?? 'error');
  });
  useEventListener(player, 'playingChange', ({ isPlaying }) => {
    if (isPlaying) setLoading(false);  });

  return (
    <>
      <VideoView
        player={player}
        style={StyleSheet.absoluteFill}
        contentFit="contain"
        nativeControls
        fullscreenOptions={{ enable: true }}
      />
      {loading ? <ActivityIndicator color="#fff" size="large" style={StyleSheet.absoluteFill} pointerEvents="none" /> : null}
    </>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  top: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingBottom: 8 },
  stage: { flex: 1 },
  title: { flex: 1, color: 'rgba(255,255,255,0.85)', fontSize: 15, fontWeight: '600' },
  failed: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  failedText: { color: 'rgba(255,255,255,0.7)', fontSize: 15 },
});
