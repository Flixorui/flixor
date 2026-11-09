/**
 * Muted trailer playing over the hero artwork. macOS reference: Views/Details/DetailsHeroTrailer.swift
 *
 * Off by default on mobile since it streams video as soon as the screen opens.
 * The artwork shows until playback actually starts, and returns when it ends or fails.
 */

import React, { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import YoutubePlayer from 'react-native-youtube-iframe';

export default function DetailsHeroTrailer({
  videoKey,
  width,
  height,
  muted,
  active,
  onPlayingChange,
  onFinished,
}: {
  videoKey: string;
  width: number;
  height: number;
  muted: boolean;
  /** False pauses playback, for example when the hero is scrolled away. */
  active: boolean;
  onPlayingChange: (playing: boolean) => void;
  onFinished: () => void;
}) {
  const [started, setStarted] = useState(false);

  // Smallest 16:9 box covering the hero, so the video never letterboxes
  const coverHeight = Math.max(height, (width * 9) / 16);
  const coverWidth = Math.max(width, (coverHeight * 16) / 9);

  return (
    <View
      pointerEvents="none"
      style={[StyleSheet.absoluteFill, styles.clip, { opacity: started ? 1 : 0 }]}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <View style={{ marginLeft: (width - coverWidth) / 2, marginTop: (height - coverHeight) / 2 }}>
        <YoutubePlayer
          videoId={videoKey}
          width={coverWidth}
          height={coverHeight}
          play={active}
          mute={muted}
          onChangeState={(state: string) => {
            if (state === 'playing') {
              setStarted(true);
              onPlayingChange(true);
            } else if (state === 'ended') {
              onPlayingChange(false);
              onFinished();
            }
          }}
          onError={() => {
            onPlayingChange(false);
            onFinished();
          }}
          initialPlayerParams={{ controls: false, modestbranding: true, rel: false, preventFullScreen: true, iv_load_policy: 3 }}
          webViewProps={{
            allowsInlineMediaPlayback: true,
            mediaPlaybackRequiresUserAction: false,
            scrollEnabled: false,
          }}
        />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  clip: {
    overflow: 'hidden',
  },
});
