// Plex decision and capability detection
import { PlexConfig } from './plex';

// Check if content has Dolby Vision
export function hasDolbyVision(media: any): boolean {
  if (!media?.Media?.[0]) return false;

  const mediaInfo = media.Media[0];
  const videoCodec = mediaInfo.videoCodec?.toLowerCase();
  const videoProfile = mediaInfo.videoProfile?.toLowerCase();

  // Check for Dolby Vision in codec or profile
  return videoCodec?.includes('dovi') ||
         videoCodec?.includes('dolbyvision') ||
         videoCodec?.includes('dv') ||
         videoProfile?.includes('dolby') ||
         videoProfile?.includes('dv');
}

// Check if browser can play a specific codec
export function canDirectPlay(media: any): boolean {
  if (!media?.Media?.[0]) return false;

  const videoElement = document.createElement('video');
  const mediaInfo = media.Media[0];
  const container = mediaInfo.container?.toLowerCase();
  const videoCodec = mediaInfo.videoCodec?.toLowerCase();
  const audioCodec = mediaInfo.audioCodec?.toLowerCase();

  // Dolby Vision is not supported in browsers
  if (hasDolbyVision(media)) {
    console.warn('Dolby Vision detected - direct play not possible');
    return false;
  }
  
  // HEVC/H.265 is NOT supported in browsers (except Safari with hardware support)
  if (videoCodec?.includes('hevc') || videoCodec?.includes('h265')) {
    // Only Safari on macOS with hardware support can play HEVC
    const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
    if (!isSafari) return false;
    
    // Even on Safari, check if HEVC is actually supported
    const canPlayHEVC = videoElement.canPlayType('video/mp4; codecs="hvc1"') !== '' ||
                       videoElement.canPlayType('video/mp4; codecs="hev1"') !== '';
    if (!canPlayHEVC) return false;
  }
  
  // Check container support
  const supportedContainers = ['mp4', 'webm', 'ogg', 'm4v', 'mov'];
  if (!container || !supportedContainers.includes(container)) {
    return false;
  }
  
  // Check video codec support
  const supportedVideoCodecs = ['h264', 'avc', 'vp8', 'vp9', 'av1'];
  const hasValidVideoCodec = supportedVideoCodecs.some(codec => videoCodec?.includes(codec));
  
  // If not a standard codec and not HEVC (handled above), reject
  if (!hasValidVideoCodec && !videoCodec?.includes('hevc') && !videoCodec?.includes('h265')) {
    return false;
  }
  
  // Check audio codec support  
  const supportedAudioCodecs = ['aac', 'mp3', 'vorbis', 'opus', 'flac', 'ac3', 'eac3'];
  const hasValidAudioCodec = supportedAudioCodecs.some(codec => audioCodec?.includes(codec));
  
  // AC3/EAC3 requires special handling
  if ((audioCodec?.includes('ac3') || audioCodec?.includes('eac3')) && !audioCodec?.includes('aac')) {
    // Most browsers don't support AC3/EAC3 natively
    return false;
  }
  
  if (!hasValidAudioCodec) {
    return false;
  }
  
  // Additional specific codec checks
  if (container === 'mp4') {
    const canPlayH264 = videoElement.canPlayType('video/mp4; codecs="avc1.42E01E"') !== '';
    if (!canPlayH264) return false;
  } else if (container === 'webm') {
    const canPlayWebM = videoElement.canPlayType('video/webm; codecs="vp8, vorbis"') !== '';
    if (!canPlayWebM) return false;
  }
  
  return true;
}

// Check if content should request direct stream
export function canDirectStream(media: any): boolean {
  // Direct stream means Plex remuxes the container and/or transcodes audio only
  // Video stream is kept as-is (including HEVC)
  // Even though browser can't play HEVC, we request directStream=1 for original quality
  
  if (!media?.Media?.[0]) return false;
  
  const mediaInfo = media.Media[0];
  const container = mediaInfo.container?.toLowerCase();
  const audioCodec = mediaInfo.audioCodec?.toLowerCase();
  
  // Always try direct stream for "original" quality when possible
  // This tells Plex to keep the video stream untouched
  
  // Direct stream is possible when:
  // 1. Container can be remuxed to MP4/TS for streaming
  // 2. Audio can be transcoded if needed
  // 3. Video stays as-is (even HEVC)
  
  // Containers that can be remuxed
  const remuxableContainers = ['mkv', 'avi', 'mp4', 'm4v', 'mov'];
  const canRemuxContainer = remuxableContainers.includes(container);
  
  // Audio codecs that might need transcoding during direct stream
  const audioNeedsTranscode = audioCodec?.includes('dts') || 
                              audioCodec?.includes('truehd') || 
                              audioCodec?.includes('flac') ||
                              audioCodec?.includes('ac3') ||
                              audioCodec?.includes('eac3');
  
  // We can request direct stream if the container is remuxable
  // Plex will decide whether to actually direct stream or transcode
  return canRemuxContainer;
}

// Quality options based on source resolution
export function getQualityOptions(media: any) {
  const resolution = media?.Media?.[0]?.videoResolution?.toLowerCase();
  
  const allOptions = [
    { label: 'Original', value: 'original', bitrate: undefined },
    { label: '4K (40 Mbps)', value: 40000, bitrate: 40000 },
    { label: '4K (30 Mbps)', value: 30000, bitrate: 30000 },
    { label: '4K (20 Mbps)', value: 20000, bitrate: 20000 },
    { label: '1080p HD (20 Mbps)', value: 20000, bitrate: 20000 },
    { label: '1080p HD (12 Mbps)', value: 12000, bitrate: 12000 },
    { label: '1080p HD (10 Mbps)', value: 10000, bitrate: 10000 },
    { label: '1080p HD (8 Mbps)', value: 8000, bitrate: 8000 },
    { label: '720p HD (4 Mbps)', value: 4000, bitrate: 4000 },
    { label: '720p HD (3 Mbps)', value: 3000, bitrate: 3000 },
    { label: '720p HD (2 Mbps)', value: 2000, bitrate: 2000 },
    { label: '480p SD (1.5 Mbps)', value: 1500, bitrate: 1500 },
    { label: '360p SD (0.75 Mbps)', value: 750, bitrate: 750 },
    { label: '240p SD (0.3 Mbps)', value: 300, bitrate: 300 },
  ];
  
  // Filter options based on source resolution
  if (resolution === '4k' || resolution === '2160') {
    return allOptions;
  } else if (resolution === '1080' || resolution === '1080p') {
    return allOptions.filter(opt => !opt.bitrate || opt.bitrate <= 20000);
  } else if (resolution === '720' || resolution === '720p') {
    return allOptions.filter(opt => !opt.bitrate || opt.bitrate <= 4000);
  } else {
    // Default to all options if resolution is unknown
    return allOptions;
  }
}

// Get stream decision parameters
export function getStreamDecision(metadata: any, options: {
  quality?: string | number;
  directPlay?: boolean;
  audioStreamId?: string;
  subtitleStreamId?: string;
}) {
  const canPlay = canDirectPlay(metadata);
  const canStream = canDirectStream(metadata);
  
  // For "original" quality
  if (options.quality === 'original') {
    if (canPlay) {
      // Can play directly without any transcoding (H.264 in MP4)
      return {
        directPlay: true,
        directStream: false,
        transcode: false,
        quality: undefined,
        audioStreamId: options.audioStreamId,
        subtitleStreamId: options.subtitleStreamId,
      };
    } else {
      // For HEVC or other unplayable codecs, request direct stream
      // Plex will try to direct stream (remux) if possible
      // If the client can't handle HEVC, Plex will automatically fall back to transcoding
      // But by requesting directStream=1, we tell Plex to try keeping original quality
      return {
        directPlay: false,
        directStream: true, // Request direct stream for original quality
        transcode: false,
        quality: undefined, // No bitrate limit for original
        audioStreamId: options.audioStreamId,
        subtitleStreamId: options.subtitleStreamId,
      };
    }
  }
  
  // For specific quality settings, always transcode
  return {
    directPlay: false,
    directStream: false,
    transcode: true,
    quality: options.quality,
    audioStreamId: options.audioStreamId,
    subtitleStreamId: options.subtitleStreamId,
  };
}

// Get subtitle options from metadata
export function getSubtitleOptions(metadata: any) {
  const streams = metadata?.Media?.[0]?.Part?.[0]?.Stream || [];
  
  const subtitles = streams
    .filter((s: any) => s.streamType === 3)
    .map((s: any) => ({
      id: s.id,
      index: s.index,
      language: s.language || 'Unknown',
      languageCode: s.languageCode,
      languageTag: s.languageTag,
      title: s.title || s.displayTitle || `${s.language || 'Unknown'} ${s.codec || ''}`,
      codec: s.codec,
      selected: s.selected,
      forced: s.forced,
      external: s.key ? true : false,
      key: s.key,
    }));
  
  // Add "None" option
  return [
    { id: '0', title: 'None', language: 'None' },
    ...subtitles,
  ];
}

// Get audio track options from metadata
export function getAudioOptions(metadata: any) {
  const streams = metadata?.Media?.[0]?.Part?.[0]?.Stream || [];
  
  return streams
    .filter((s: any) => s.streamType === 2)
    .map((s: any) => ({
      id: s.id,
      index: s.index,
      language: s.language || 'Unknown',
      languageCode: s.languageCode,
      languageTag: s.languageTag,
      title: s.displayTitle || s.extendedDisplayTitle || `${s.language || 'Unknown'} ${s.codec || ''} ${s.channels || ''}ch`,
      codec: s.codec,
      channels: s.channels,
      selected: s.selected,
      default: s.default,
    }));
}

// Get external subtitle URL
export function getExternalSubtitleUrl(plexConfig: PlexConfig, subtitleKey: string) {
  if (!subtitleKey) return null;
  
  // If it's already a full URL, return it
  if (subtitleKey.startsWith('http')) return subtitleKey;
  
  // Build Plex subtitle URL
  const baseUrl = plexConfig.baseUrl.replace(/\/$/, '');
  const key = subtitleKey.startsWith('/') ? subtitleKey : `/${subtitleKey}`;
  return `${baseUrl}${key}?X-Plex-Token=${plexConfig.token}`;
}