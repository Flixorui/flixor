/**
 * MPV Player Component for Android
 *
 * Native MPV-based video player with full codec support including:
 * - Direct play of MKV, MP4, and other containers
 * - HEVC/H.265, AV1, VP9 hardware decoding
 * - HDR10, HDR10+, Dolby Vision passthrough
 * - Embedded subtitle support (SRT, ASS, PGS)
 * - Audio/subtitle track selection
 */
import React, { useRef, useCallback, forwardRef, useImperativeHandle } from 'react';
import { View, StyleSheet, requireNativeComponent, Platform, UIManager, findNodeHandle, ViewStyle } from 'react-native';

// Only available on Android
const MpvPlayerNative = Platform.OS === 'android'
  ? requireNativeComponent<any>('MpvPlayer')
  : null;

export interface MPVAudioTrack {
  id: number;
  name: string;
  language: string;
  codec: string;
}

export interface MPVSubtitleTrack {
  id: number;
  name: string;
  language: string;
  codec: string;
}

export interface MPVPlayerRef {
  seek: (positionSeconds: number) => void;
  setAudioTrack: (trackId: number) => void;
  setSubtitleTrack: (trackId: number) => void;
}

export interface MPVPlayerSource {
  uri: string;
  headers?: Record<string, string>;
}

export interface MPVPlayerProps {
  source?: MPVPlayerSource;
  paused?: boolean;
  volume?: number;
  rate?: number;
  resizeMode?: 'contain' | 'cover' | 'stretch';
  style?: ViewStyle;

  // Decoder settings
  decoderMode?: 'auto' | 'sw' | 'hw' | 'hw+';
  gpuMode?: 'gpu' | 'gpu-next';

  // Events
  onLoad?: (data: { duration: number; width: number; height: number }) => void;
  onProgress?: (data: { currentTime: number; duration: number }) => void;
  onEnd?: () => void;
  onError?: (error: { error: string }) => void;
  onTracksChanged?: (data: { audioTracks: MPVAudioTrack[]; subtitleTracks: MPVSubtitleTrack[] }) => void;

  // Subtitle Styling
  subtitleSize?: number;
  subtitleColor?: string;
  subtitleBackgroundOpacity?: number;
  subtitleBorderSize?: number;
  subtitleBorderColor?: string;
  subtitleShadowEnabled?: boolean;
  subtitlePosition?: number;
}

const MPVPlayerComponent = forwardRef<MPVPlayerRef, MPVPlayerProps>((props, ref) => {
  const nativeRef = useRef<any>(null);

  const dispatchCommand = useCallback((commandName: string, args: any[] = []) => {
    if (nativeRef.current && Platform.OS === 'android') {
      const handle = findNodeHandle(nativeRef.current);
      if (handle) {
        UIManager.dispatchViewManagerCommand(
          handle,
          commandName,
          args
        );
      }
    }
  }, []);

  useImperativeHandle(ref, () => ({
    seek: (positionSeconds: number) => {
      dispatchCommand('seek', [positionSeconds]);
    },
    setAudioTrack: (trackId: number) => {
      dispatchCommand('setAudioTrack', [trackId]);
    },
    setSubtitleTrack: (trackId: number) => {
      dispatchCommand('setSubtitleTrack', [trackId]);
    },
  }), [dispatchCommand]);

  // Fallback for iOS or if native component is not available
  if (Platform.OS !== 'android' || !MpvPlayerNative) {
    return (
      <View style={[styles.container, props.style, { backgroundColor: 'black' }]} />
    );
  }

  const handleLoad = (event: any) => {
    console.log('[MPVPlayer] onLoad:', event?.nativeEvent);
    props.onLoad?.(event?.nativeEvent);
  };

  const handleProgress = (event: any) => {
    props.onProgress?.(event?.nativeEvent);
  };

  const handleEnd = () => {
    console.log('[MPVPlayer] onEnd');
    props.onEnd?.();
  };

  const handleError = (event: any) => {
    console.log('[MPVPlayer] onError:', event?.nativeEvent);
    props.onError?.(event?.nativeEvent);
  };

  const handleTracksChanged = (event: any) => {
    console.log('[MPVPlayer] onTracksChanged:', event?.nativeEvent);
    props.onTracksChanged?.(event?.nativeEvent);
  };

  return (
    <MpvPlayerNative
      ref={nativeRef}
      style={[styles.container, props.style]}
      source={props.source?.uri}
      headers={props.source?.headers}
      paused={props.paused ?? true}
      volume={props.volume ?? 1.0}
      rate={props.rate ?? 1.0}
      resizeMode={props.resizeMode ?? 'contain'}
      onLoad={handleLoad}
      onProgress={handleProgress}
      onEnd={handleEnd}
      onError={handleError}
      onTracksChanged={handleTracksChanged}
      decoderMode={props.decoderMode ?? 'auto'}
      gpuMode={props.gpuMode ?? 'gpu'}
      // Subtitle Styling
      subtitleSize={props.subtitleSize ?? 48}
      subtitleColor={props.subtitleColor ?? '#FFFFFF'}
      subtitleBackgroundOpacity={props.subtitleBackgroundOpacity ?? 0}
      subtitleBorderSize={props.subtitleBorderSize ?? 3}
      subtitleBorderColor={props.subtitleBorderColor ?? '#000000'}
      subtitleShadowEnabled={props.subtitleShadowEnabled ?? true}
      subtitlePosition={props.subtitlePosition ?? 100}
    />
  );
});

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'black',
  },
});

MPVPlayerComponent.displayName = 'MPVPlayerComponent';

export default MPVPlayerComponent;
