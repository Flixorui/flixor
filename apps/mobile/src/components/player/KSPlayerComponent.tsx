/**
 * KSPlayerComponent - React Native bridge to native KSPlayer iOS view
 */
import React, { useRef, useImperativeHandle, forwardRef, useEffect, useState } from 'react';
import { requireNativeComponent, UIManager, findNodeHandle, NativeModules, Platform } from 'react-native';

export interface KSPlayerSource {
  uri: string;
  headers?: Record<string, string>;
}

interface KSPlayerViewProps {
  source?: KSPlayerSource;
  paused?: boolean;
  volume?: number;
  rate?: number;
  audioTrack?: number;
  textTrack?: number;
  allowsExternalPlayback?: boolean;
  usesExternalPlaybackWhileExternalScreenIsActive?: boolean;
  subtitleBottomOffset?: number;
  subtitleFontSize?: number;
  resizeMode?: 'contain' | 'cover' | 'stretch';
  onLoad?: (data: any) => void;
  onProgress?: (data: any) => void;
  onBuffering?: (data: any) => void;
  onEnd?: () => void;
  onError?: (error: any) => void;
  onBufferingProgress?: (data: any) => void;
  style?: any;
}

// Only require native component on iOS
const KSPlayerViewManager = Platform.OS === 'ios'
  ? requireNativeComponent<KSPlayerViewProps>('KSPlayerView')
  : null;

const KSPlayerModule = Platform.OS === 'ios' ? NativeModules.KSPlayerModule : null;

export interface AudioTrack {
  id: number;
  index: number;
  name: string;
  language: string;
  languageCode: string;
  isEnabled: boolean;
  bitRate: number;
  bitDepth: number;
}

export interface TextTrack {
  id: number;
  index: number;
  name: string;
  language: string;
  languageCode: string;
  isEnabled: boolean;
  isImageSubtitle: boolean;
}

export interface KSPlayerRef {
  seek: (time: number) => void;
  setSource: (source: KSPlayerSource) => void;
  setPaused: (paused: boolean) => void;
  setVolume: (volume: number) => void;
  setPlaybackRate: (rate: number) => void;
  setAudioTrack: (trackId: number) => void;
  setTextTrack: (trackId: number) => void;
  getTracks: () => Promise<{ audioTracks: AudioTrack[]; textTracks: TextTrack[] }>;
  setAllowsExternalPlayback: (allows: boolean) => void;
  setUsesExternalPlaybackWhileExternalScreenIsActive: (uses: boolean) => void;
  getAirPlayState: () => Promise<{ allowsExternalPlayback: boolean; usesExternalPlaybackWhileExternalScreenIsActive: boolean; isExternalPlaybackActive: boolean }>;
  showAirPlayPicker: () => void;
}

export interface KSPlayerProps {
  source?: KSPlayerSource;
  paused?: boolean;
  volume?: number;
  rate?: number;
  audioTrack?: number;
  textTrack?: number;
  allowsExternalPlayback?: boolean;
  usesExternalPlaybackWhileExternalScreenIsActive?: boolean;
  subtitleBottomOffset?: number;
  subtitleFontSize?: number;
  resizeMode?: 'contain' | 'cover' | 'stretch';
  onLoad?: (data: any) => void;
  onProgress?: (data: any) => void;
  onBuffering?: (data: any) => void;
  onEnd?: () => void;
  onError?: (error: any) => void;
  onBufferingProgress?: (data: any) => void;
  style?: any;
}

const KSPlayer = forwardRef<KSPlayerRef, KSPlayerProps>((props, ref) => {
  const nativeRef = useRef<any>(null);
  const [key, setKey] = useState(0);

  useImperativeHandle(ref, () => ({
    seek: (time: number) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.seek;
        UIManager.dispatchViewManagerCommand(node, commandId, [time]);
      }
    },
    setSource: (source: KSPlayerSource) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.setSource;
        UIManager.dispatchViewManagerCommand(node, commandId, [source]);
      }
    },
    setPaused: (paused: boolean) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.setPaused;
        UIManager.dispatchViewManagerCommand(node, commandId, [paused]);
      }
    },
    setVolume: (volume: number) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.setVolume;
        UIManager.dispatchViewManagerCommand(node, commandId, [volume]);
      }
    },
    setPlaybackRate: (rate: number) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.setPlaybackRate;
        UIManager.dispatchViewManagerCommand(node, commandId, [rate]);
      }
    },
    setAudioTrack: (trackId: number) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.setAudioTrack;
        UIManager.dispatchViewManagerCommand(node, commandId, [trackId]);
      }
    },
    setTextTrack: (trackId: number) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.setTextTrack;
        UIManager.dispatchViewManagerCommand(node, commandId, [trackId]);
      }
    },
    getTracks: async () => {
      if (nativeRef.current && KSPlayerModule) {
        const node = findNodeHandle(nativeRef.current);
        if (node) {
          return await KSPlayerModule.getTracks(node);
        }
      }
      return { audioTracks: [], textTracks: [] };
    },
    setAllowsExternalPlayback: (allows: boolean) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.setAllowsExternalPlayback;
        UIManager.dispatchViewManagerCommand(node, commandId, [allows]);
      }
    },
    setUsesExternalPlaybackWhileExternalScreenIsActive: (uses: boolean) => {
      if (nativeRef.current && Platform.OS === 'ios') {
        const node = findNodeHandle(nativeRef.current);
        // @ts-ignore legacy UIManager commands path
        const commandId = UIManager.getViewManagerConfig('KSPlayerView').Commands.setUsesExternalPlaybackWhileExternalScreenIsActive;
        UIManager.dispatchViewManagerCommand(node, commandId, [uses]);
      }
    },
    getAirPlayState: async () => {
      if (nativeRef.current && KSPlayerModule) {
        const node = findNodeHandle(nativeRef.current);
        if (node) {
          return await KSPlayerModule.getAirPlayState(node);
        }
      }
      return { allowsExternalPlayback: false, usesExternalPlaybackWhileExternalScreenIsActive: false, isExternalPlaybackActive: false };
    },
    showAirPlayPicker: () => {
      if (nativeRef.current && KSPlayerModule) {
        const node = findNodeHandle(nativeRef.current);
        if (node) {
          console.log('[KSPlayerComponent] Calling showAirPlayPicker with node:', node);
          KSPlayerModule.showAirPlayPicker(node);
        }
      }
    },
  }));

  // Force re-render when source changes
  useEffect(() => {
    if (props.source) {
      setKey(prev => prev + 1);
    }
  }, [props.source?.uri]);

  // Don't render on non-iOS platforms
  if (Platform.OS !== 'ios' || !KSPlayerViewManager) {
    return null;
  }

  return (
    <KSPlayerViewManager
      key={key}
      ref={nativeRef}
      source={props.source}
      paused={props.paused}
      volume={props.volume}
      rate={props.rate}
      audioTrack={props.audioTrack}
      textTrack={props.textTrack}
      allowsExternalPlayback={props.allowsExternalPlayback}
      usesExternalPlaybackWhileExternalScreenIsActive={props.usesExternalPlaybackWhileExternalScreenIsActive}
      subtitleBottomOffset={props.subtitleBottomOffset}
      subtitleFontSize={props.subtitleFontSize}
      resizeMode={props.resizeMode}
      onLoad={(e: any) => props.onLoad?.(e?.nativeEvent ?? e)}
      onProgress={(e: any) => props.onProgress?.(e?.nativeEvent ?? e)}
      onBuffering={(e: any) => props.onBuffering?.(e?.nativeEvent ?? e)}
      onEnd={() => props.onEnd?.()}
      onError={(e: any) => props.onError?.(e?.nativeEvent ?? e)}
      onBufferingProgress={(e: any) => props.onBufferingProgress?.(e?.nativeEvent ?? e)}
      style={props.style}
    />
  );
});

KSPlayer.displayName = 'KSPlayer';

export default KSPlayer;
