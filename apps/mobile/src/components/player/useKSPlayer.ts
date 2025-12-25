/**
 * useKSPlayer - Hook for managing KSPlayer reference
 */
import { useRef } from 'react';
import { KSPlayerRef } from './KSPlayerComponent';

export const useKSPlayer = () => {
  const ksPlayerRef = useRef<KSPlayerRef>(null);

  const seek = (time: number) => {
    ksPlayerRef.current?.seek(time);
  };

  const getTracks = async () => {
    return ksPlayerRef.current?.getTracks() ?? { audioTracks: [], textTracks: [] };
  };

  const setAudioTrack = (trackId: number) => {
    ksPlayerRef.current?.setAudioTrack(trackId);
  };

  const setTextTrack = (trackId: number) => {
    ksPlayerRef.current?.setTextTrack(trackId);
  };

  const showAirPlayPicker = () => {
    ksPlayerRef.current?.showAirPlayPicker();
  };

  const getAirPlayState = async () => {
    return ksPlayerRef.current?.getAirPlayState() ?? {
      allowsExternalPlayback: false,
      usesExternalPlaybackWhileExternalScreenIsActive: false,
      isExternalPlaybackActive: false,
    };
  };

  return {
    ksPlayerRef,
    seek,
    getTracks,
    setAudioTrack,
    setTextTrack,
    showAirPlayPicker,
    getAirPlayState,
  };
};
