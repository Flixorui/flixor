/**
 * MPV Player Component for iOS and Android
 *
 * Native MPV-based video player with full codec support including:
 * - Direct play of MKV, MP4, and other containers
 * - HEVC/H.265, AV1, VP9 hardware decoding
 * - HDR10, HDR10+, Dolby Vision passthrough
 * - Embedded subtitle support (SRT, ASS, PGS)
 * - Audio/subtitle track selection
 *
 * iOS: Uses MPVKit (libmpv) with Metal/Vulkan rendering
 * Android: Uses native MPV with OpenGL/Vulkan rendering
 */
import React, { useRef, useCallback, forwardRef, useImperativeHandle } from 'react';
import { View, StyleSheet, requireNativeComponent, Platform, UIManager, findNodeHandle, ViewStyle, NativeModules } from 'react-native';

// Native components for each platform
const MpvPlayerAndroid = Platform.OS === 'android'
  ? requireNativeComponent<any>('MpvPlayer')
  : null;

let MpvPlayerIOS: any = null;
if (Platform.OS === 'ios') {
  try {
    MpvPlayerIOS = requireNativeComponent<any>('MPVPlayerView');
    console.log('[MPVPlayerComponent] iOS native component loaded:', MpvPlayerIOS);
  } catch (error) {
    console.error('[MPVPlayerComponent] Failed to load iOS native component:', error);
  }
}

// Native module for iOS imperative commands
const MPVPlayerViewManager = Platform.OS === 'ios'
  ? NativeModules.MPVPlayerViewManager
  : null;

console.log('[MPVPlayerComponent] MPVPlayerViewManager module:', MPVPlayerViewManager);

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
    const handle = findNodeHandle(nativeRef.current);
    if (!handle) return;

    if (Platform.OS === 'android') {
      UIManager.dispatchViewManagerCommand(
        handle,
        commandName,
        args
      );
    } else if (Platform.OS === 'ios' && MPVPlayerViewManager) {
      // iOS uses native module methods
      switch (commandName) {
        case 'seek':
          MPVPlayerViewManager.seek(handle, args[0]);
          break;
        case 'setAudioTrack':
          MPVPlayerViewManager.setAudioTrack(handle, args[0]);
          break;
        case 'setSubtitleTrack':
          MPVPlayerViewManager.setSubtitleTrack(handle, args[0]);
          break;
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

  // Fallback if native component is not available
  const NativePlayer = Platform.OS === 'ios' ? MpvPlayerIOS : MpvPlayerAndroid;
  console.log('[MPVPlayerComponent] render - NativePlayer:', NativePlayer, 'Platform:', Platform.OS);

  if (!NativePlayer) {
    console.error('[MPVPlayerComponent] NativePlayer is null! Showing fallback view.');
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

  // Build source object for iOS (expects NSDictionary) vs Android (separate props)
  const sourceProps = Platform.OS === 'ios'
    ? { source: props.source }
    : { source: props.source?.uri, headers: props.source?.headers };

  // iOS uses subtitleTrack prop, Android uses native commands
  const trackProps = Platform.OS === 'ios'
    ? {}
    : {};

  return (
    <NativePlayer
      ref={nativeRef}
      style={[styles.container, props.style]}
      {...sourceProps}
      paused={props.paused ?? true}
      volume={props.volume ?? 1.0}
      rate={props.rate ?? 1.0}
      resizeMode={props.resizeMode ?? 'contain'}
      onLoad={handleLoad}
      onProgress={handleProgress}
      onEnd={handleEnd}
      onError={handleError}
      onTracksChanged={handleTracksChanged}
      // Android-specific props
      {...(Platform.OS === 'android' ? {
        decoderMode: props.decoderMode ?? 'auto',
        gpuMode: props.gpuMode ?? 'gpu',
        subtitleBackgroundOpacity: props.subtitleBackgroundOpacity ?? 0,
        subtitleBorderColor: props.subtitleBorderColor ?? '#000000',
        subtitleShadowEnabled: props.subtitleShadowEnabled ?? true,
      } : {})}
      // Subtitle Styling (shared)
      subtitleSize={props.subtitleSize ?? 48}
      subtitleColor={props.subtitleColor ?? '#FFFFFF'}
      subtitleBorderSize={props.subtitleBorderSize ?? 3}
      subtitlePosition={props.subtitlePosition ?? 100}
      {...trackProps}
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
