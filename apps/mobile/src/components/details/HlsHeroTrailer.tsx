/**
 * Apple TV trailer playing muted over the Details artwork, in a native
 * player. The artwork shows until playback starts and returns when it ends;
 * a stream that fails, or doesn't start within 10 s, hands over to YouTube.
 * macOS reference: Services/Trailers/TrailerPlayer.swift (hero mode)
 */
import React, { useEffect, useRef, useState } from 'react';
import { Animated, StyleSheet } from 'react-native';
import { useEventListener } from 'expo';
import { useVideoPlayer, VideoView } from 'expo-video';

export default function HlsHeroTrailer({
  streamUrl,
  muted,
  active,
  onPlayingChange,
  onFinished,
  onFailed,
}: {
  streamUrl: string;
  muted: boolean;
  /** False pauses playback, for example when the hero is scrolled away. */
  active: boolean;
  onPlayingChange: (playing: boolean) => void;
  onFinished: () => void;
  /** The stream couldn't play: use YouTube instead. */
  onFailed: () => void;
}) {
  const [started, setStarted] = useState(false);
  const loaded = useRef(false);
  const finished = useRef(false);
  const failed = useRef(false);
  const reveal = useRef(new Animated.Value(0)).current;

  const player = useVideoPlayer(streamUrl, (p) => {
    p.muted = muted;
    p.loop = false;
    if (active) p.play();
  });

  const fail = (error: unknown) => {
    if (failed.current) return;
    failed.current = true;
    console.log('[HeroTrailer] stream failed', String(error));
    setStarted(false);
    onPlayingChange(false);
    onFailed();
  };

  // Watchdog: a stream that never loads gives no error, just silence
  useEffect(() => {
    loaded.current = false;
    failed.current = false;
    finished.current = false;
    const t = setTimeout(() => {
      if (!loaded.current) fail('timed out');
    }, 10000);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [streamUrl]);

  useEffect(() => {
    player.muted = muted;
  }, [player, muted]);

  useEffect(() => {
    if (finished.current || failed.current) return;
    if (active) player.play();
    else player.pause();
  }, [player, active]);

  useEffect(() => {
    Animated.timing(reveal, { toValue: started && active ? 1 : 0, duration: 250, useNativeDriver: true }).start();
  }, [started, active, reveal]);

  useEventListener(player, 'statusChange', ({ status, error }) => {
    if (status === 'readyToPlay') loaded.current = true;
    else if (status === 'error') fail(error?.message ?? 'error');
  });
  useEventListener(player, 'playingChange', ({ isPlaying }) => {
    if (isPlaying && !started) {
      setStarted(true);
      onPlayingChange(true);
    }
  });
  useEventListener(player, 'playToEnd', () => {
    if (finished.current) return;
    finished.current = true;
    setStarted(false);
    onPlayingChange(false);
    onFinished();
  });

  return (
    <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { opacity: reveal }]} accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
      <VideoView player={player} style={StyleSheet.absoluteFill} contentFit="cover" nativeControls={false} />
    </Animated.View>
  );
}
