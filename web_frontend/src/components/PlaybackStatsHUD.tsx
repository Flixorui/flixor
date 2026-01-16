import { useState, useEffect, useRef } from 'react';

export interface PlaybackStats {
  // Video info
  videoCodec?: string;
  videoProfile?: string;
  resolution?: string;
  width?: number;
  height?: number;
  frameRate?: number;
  bitrate?: number; // kbps from metadata
  videoBitrate?: number; // real-time bitrate in bps
  bitDepth?: number;
  colorSpace?: string; // e.g., "bt709", "bt2020"
  colorPrimaries?: string;
  container?: string; // e.g., "mkv", "mp4"

  // Dynamic range
  dynamicRange?: string; // SDR, HDR10, HDR10+, Dolby Vision, HLG

  // Playback info
  currentTime?: number;
  duration?: number;
  bufferProgress?: number; // 0-100
  playableBufferSeconds?: number; // seconds of buffered content ahead
  playbackRate?: number;

  // Stream info
  isTranscoding?: boolean;
  videoDecision?: 'directplay' | 'directstream' | 'transcode' | 'copy';
  audioDecision?: 'directplay' | 'directstream' | 'transcode' | 'copy';
  transcodeReason?: string;

  // Audio info
  audioCodec?: string;
  audioChannels?: number;
  audioBitrate?: number; // bps
  audioSampleRate?: number;

  // Performance stats
  displayFPS?: number; // actual rendered FPS
  droppedFrames?: number;
  totalFrames?: number;
  avSyncDiff?: number; // audio-video sync difference in seconds
  isHardwareAccelerated?: boolean;

  // Network stats
  downloadSpeed?: number; // bps
  latency?: number; // ms
}

type PlaybackStatsHUDProps = {
  stats: PlaybackStats;
  visible: boolean;
  position?: 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right';
};

export default function PlaybackStatsHUD({
  stats,
  visible,
  position = 'top-left',
}: PlaybackStatsHUDProps) {
  if (!visible) return null;

  const positionClasses = {
    'top-left': 'top-4 left-4',
    'top-right': 'top-4 right-4',
    'bottom-left': 'bottom-20 left-4',
    'bottom-right': 'bottom-20 right-4',
  };

  const formatBitrate = (bps?: number) => {
    if (!bps) return null;
    if (bps >= 1_000_000) return `${(bps / 1_000_000).toFixed(1)} Mbps`;
    if (bps >= 1_000) return `${(bps / 1_000).toFixed(0)} Kbps`;
    return `${bps} bps`;
  };

  const formatBitrateKbps = (kbps?: number) => {
    if (!kbps) return null;
    if (kbps >= 1000) return `${(kbps / 1000).toFixed(1)} Mbps`;
    return `${kbps} Kbps`;
  };

  const formatResolution = () => {
    if (stats.resolution) return stats.resolution;
    if (stats.width && stats.height) return `${stats.width}x${stats.height}`;
    return 'Unknown';
  };

  const formatAudioChannels = (channels?: number) => {
    if (!channels) return null;
    if (channels >= 8) return `7.1 (${channels}ch)`;
    if (channels >= 6) return `5.1 (${channels}ch)`;
    if (channels >= 2) return `Stereo (${channels}ch)`;
    return `Mono (${channels}ch)`;
  };

  const getDynamicRangeLabel = () => {
    const range = stats.dynamicRange?.toLowerCase() || '';
    if (range.includes('dolby') || range.includes('vision') || range.includes('dv')) return 'Dolby Vision';
    if (range.includes('hdr10+')) return 'HDR10+';
    if (range.includes('hdr10') || range.includes('hdr')) return 'HDR10';
    if (range.includes('hlg')) return 'HLG';
    if (range === 'sdr' || !stats.dynamicRange) return 'SDR';
    return stats.dynamicRange;
  };

  const getDynamicRangeBadgeClass = () => {
    const range = stats.dynamicRange?.toLowerCase() || '';
    if (range.includes('dolby') || range.includes('vision') || range.includes('dv'))
      return 'bg-black border border-yellow-500 text-yellow-500';
    if (range.includes('hdr10+')) return 'bg-purple-600';
    if (range.includes('hdr10') || range.includes('hdr')) return 'bg-purple-700';
    if (range.includes('hlg')) return 'bg-green-600';
    return 'bg-gray-600';
  };

  const getDecisionLabel = (decision?: string) => {
    switch (decision) {
      case 'directplay': return 'Direct Play';
      case 'directstream': return 'Direct Stream';
      case 'copy': return 'Direct Stream'; // "copy" in Plex = Direct Stream (no re-encoding)
      case 'transcode': return 'Transcode';
      default: return decision || 'Unknown';
    }
  };

  const getDecisionBadgeClass = (decision?: string) => {
    switch (decision) {
      case 'directplay': return 'bg-green-600';
      case 'directstream': return 'bg-blue-600';
      case 'copy': return 'bg-blue-600'; // Same as directstream - no re-encoding
      case 'transcode': return 'bg-yellow-600';
      default: return 'bg-gray-600';
    }
  };

  const codecLabel = stats.videoCodec?.toUpperCase() || 'Unknown';
  const profileLabel = stats.videoProfile ? ` (${stats.videoProfile})` : '';

  return (
    <div
      className={`absolute ${positionClasses[position]} z-40 pointer-events-none`}
    >
      <div className="bg-black/90 backdrop-blur-sm rounded-lg p-3 text-xs font-mono text-white/90 space-y-2 min-w-[240px] border border-white/10">
        {/* Header */}
        <div className="flex items-center justify-between pb-2 border-b border-white/20">
          <span className="font-semibold text-sm">Playback Stats</span>
          {stats.videoDecision && (
            <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${getDecisionBadgeClass(stats.videoDecision)}`}>
              {stats.videoDecision === 'transcode' ? 'TRANSCODING' :
               stats.videoDecision === 'directplay' ? 'DIRECT PLAY' : 'DIRECT STREAM'}
            </span>
          )}
        </div>

        {/* Video Info */}
        <div className="space-y-1">
          <div className="text-white/50 text-[10px] uppercase tracking-wider font-semibold">Video</div>
          <Row label="Resolution" value={formatResolution()} />
          <Row label="Frame Rate" value={stats.frameRate ? `${stats.frameRate.toFixed(2)} fps` : 'Unknown'} />
          <Row label="Dynamic Range">
            <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${getDynamicRangeBadgeClass()}`}>
              {getDynamicRangeLabel()}
            </span>
          </Row>
          {stats.bitDepth && <Row label="Bit Depth" value={`${stats.bitDepth}-bit`} />}
          <Row label="Codec" value={`${codecLabel}${profileLabel}`} />
          {stats.colorSpace && <Row label="Color Space" value={stats.colorSpace.toUpperCase()} />}
          {stats.container && <Row label="Container" value={stats.container.toUpperCase()} />}
          <Row label="Bitrate" value={formatBitrate(stats.videoBitrate) || formatBitrateKbps(stats.bitrate) || 'Unknown'} />
          <Row label="Playback">
            <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${getDecisionBadgeClass(stats.videoDecision)}`}>
              {getDecisionLabel(stats.videoDecision)}
            </span>
          </Row>
        </div>

        {/* Audio Info */}
        <div className="space-y-1 pt-1 border-t border-white/10">
          <div className="text-white/50 text-[10px] uppercase tracking-wider font-semibold">Audio</div>
          <Row label="Codec" value={stats.audioCodec?.toUpperCase() || 'Unknown'} />
          <Row label="Channels" value={formatAudioChannels(stats.audioChannels) || 'Unknown'} />
          {stats.audioBitrate && <Row label="Bitrate" value={formatBitrate(stats.audioBitrate)} />}
          {stats.audioSampleRate && <Row label="Sample Rate" value={`${(stats.audioSampleRate / 1000).toFixed(1)} kHz`} />}
          <Row label="Playback">
            <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${getDecisionBadgeClass(stats.audioDecision)}`}>
              {getDecisionLabel(stats.audioDecision)}
            </span>
          </Row>
        </div>

        {/* Buffer Info */}
        <div className="space-y-1 pt-1 border-t border-white/10">
          <div className="text-white/50 text-[10px] uppercase tracking-wider font-semibold">Buffer</div>
          {stats.bufferProgress !== undefined && (
            <div className="flex justify-between items-center">
              <span className="text-white/60">Progress:</span>
              <div className="flex items-center gap-2">
                <div className="w-16 h-1.5 bg-white/20 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-green-500 transition-all duration-300"
                    style={{ width: `${Math.min(stats.bufferProgress, 100)}%` }}
                  />
                </div>
                <span className="w-10 text-right tabular-nums">{stats.bufferProgress.toFixed(0)}%</span>
              </div>
            </div>
          )}
          {stats.playableBufferSeconds !== undefined && (
            <Row label="Playable" value={`${stats.playableBufferSeconds.toFixed(1)}s`} />
          )}
          {stats.downloadSpeed !== undefined && stats.downloadSpeed > 0 && (
            <Row label="Download" value={formatBitrate(stats.downloadSpeed)} />
          )}
        </div>

        {/* Performance Stats */}
        <div className="space-y-1 pt-1 border-t border-white/10">
          <div className="text-white/50 text-[10px] uppercase tracking-wider font-semibold">Performance</div>
          {stats.displayFPS !== undefined && (
            <Row
              label="Render FPS"
              value={`${stats.displayFPS.toFixed(1)} fps`}
              warning={(stats.frameRate && stats.displayFPS < stats.frameRate * 0.9) || false}
            />
          )}
          {stats.droppedFrames !== undefined && (
            <Row
              label="Dropped"
              value={`${stats.droppedFrames} frames`}
              warning={stats.droppedFrames > 0}
            />
          )}
          {stats.totalFrames !== undefined && stats.totalFrames > 0 && (
            <Row
              label="Drop Rate"
              value={`${((stats.droppedFrames || 0) / stats.totalFrames * 100).toFixed(2)}%`}
              warning={(stats.droppedFrames || 0) / stats.totalFrames > 0.01}
            />
          )}
          {stats.avSyncDiff !== undefined && (
            <Row
              label="A/V Sync"
              value={`${(stats.avSyncDiff * 1000).toFixed(0)}ms`}
              warning={Math.abs(stats.avSyncDiff) > 0.1}
            />
          )}
          <Row label="HW Accel">
            <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${
              stats.isHardwareAccelerated ? 'bg-green-600' : 'bg-red-600'
            }`}>
              {stats.isHardwareAccelerated ? 'ON' : 'OFF'}
            </span>
          </Row>
        </div>

        {/* Playback Speed */}
        {stats.playbackRate && stats.playbackRate !== 1 && (
          <div className="pt-1 border-t border-white/10">
            <Row label="Speed" value={`${stats.playbackRate}x`} />
          </div>
        )}
      </div>
    </div>
  );
}

// Helper component for rows
function Row({
  label,
  value,
  children,
  warning = false,
}: {
  label: string;
  value?: string | null;
  children?: React.ReactNode;
  warning?: boolean;
}) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-white/60">{label}:</span>
      {children || (
        <span className={`tabular-nums ${warning ? 'text-red-400' : ''}`}>
          {value || 'Unknown'}
        </span>
      )}
    </div>
  );
}

// Hook to collect real-time playback stats from video element
// Set enabled=false to disable stats collection (reduces React re-render overhead)
export function usePlaybackStats(
  videoRef: React.RefObject<HTMLVideoElement>,
  playerStatsRef?: React.RefObject<{ getStats: () => any } | null>,
  enabled: boolean = true
) {
  const [stats, setStats] = useState<PlaybackStats>({});
  const lastQualityRef = useRef<VideoPlaybackQuality | null>(null);
  const lastTimeRef = useRef<number>(0);
  const fpsHistoryRef = useRef<number[]>([]);
  const droppedPerSecondRef = useRef<number[]>([]);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    // Clear any existing interval
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }

    // Don't collect stats if disabled (reduces React re-render overhead during playback)
    if (!enabled) {
      return;
    }

    // Reset history when video changes
    lastQualityRef.current = null;
    lastTimeRef.current = 0;
    fpsHistoryRef.current = [];
    droppedPerSecondRef.current = [];

    const updateStats = () => {
      // Get current video element (may not be available yet)
      const video = videoRef.current;
      if (!video) return;

      // Get video playback quality for FPS and dropped frames
      const quality = video.getVideoPlaybackQuality?.();
      const now = performance.now();

      let instantFPS: number | undefined;
      let droppedPerSecond: number | undefined;

      if (quality && lastQualityRef.current && lastTimeRef.current) {
        const framesDelta = quality.totalVideoFrames - lastQualityRef.current.totalVideoFrames;
        const droppedDelta = quality.droppedVideoFrames - lastQualityRef.current.droppedVideoFrames;
        const timeDelta = (now - lastTimeRef.current) / 1000; // convert to seconds

        if (timeDelta > 0 && framesDelta >= 0) {
          instantFPS = framesDelta / timeDelta;
          droppedPerSecond = droppedDelta / timeDelta;

          // Keep history for smoothing (last 5 samples = ~1.25 seconds at 250ms intervals)
          fpsHistoryRef.current.push(instantFPS);
          if (fpsHistoryRef.current.length > 5) fpsHistoryRef.current.shift();

          droppedPerSecondRef.current.push(droppedPerSecond);
          if (droppedPerSecondRef.current.length > 5) droppedPerSecondRef.current.shift();
        }
      }

      lastQualityRef.current = quality || null;
      lastTimeRef.current = now;

      // Calculate smoothed FPS (average of recent samples)
      const smoothedFPS = fpsHistoryRef.current.length > 0
        ? fpsHistoryRef.current.reduce((a, b) => a + b, 0) / fpsHistoryRef.current.length
        : undefined;

      // Calculate average dropped frames per second
      const avgDroppedPerSec = droppedPerSecondRef.current.length > 0
        ? droppedPerSecondRef.current.reduce((a, b) => a + b, 0) / droppedPerSecondRef.current.length
        : 0;

      // Calculate playable buffer seconds
      let playableBufferSeconds: number | undefined;
      if (video.buffered.length > 0) {
        const bufferedEnd = video.buffered.end(video.buffered.length - 1);
        playableBufferSeconds = Math.max(0, bufferedEnd - video.currentTime);
      }

      // Get player-specific stats if available
      const playerStats = playerStatsRef?.current?.getStats?.() || {};

      // Hardware acceleration detection:
      // - If dropping < 1% of frames, likely hardware accelerated
      // - If dropping > 5% of frames, likely software decoding struggling
      const dropRate = quality && quality.totalVideoFrames > 0
        ? quality.droppedVideoFrames / quality.totalVideoFrames
        : 0;
      const isHwAccelerated = quality && quality.totalVideoFrames > 100
        ? dropRate < 0.01 && avgDroppedPerSec < 1
        : undefined;

      setStats((prev) => ({
        ...prev,
        currentTime: video.currentTime,
        duration: video.duration,
        playbackRate: video.playbackRate,
        width: video.videoWidth,
        height: video.videoHeight,
        bufferProgress: video.buffered.length > 0 && video.duration > 0
          ? (video.buffered.end(video.buffered.length - 1) / video.duration) * 100
          : 0,
        playableBufferSeconds,
        displayFPS: smoothedFPS !== undefined ? smoothedFPS : prev.displayFPS,
        droppedFrames: quality?.droppedVideoFrames,
        totalFrames: quality?.totalVideoFrames,
        isHardwareAccelerated: isHwAccelerated,
        ...playerStats,
      }));
    };

    // Update every 500ms to balance FPS display smoothness with CPU overhead
    // This will poll even if video isn't available yet
    intervalRef.current = setInterval(updateStats, 500);

    // Add event listeners if video is already available
    const video = videoRef.current;
    if (video) {
      video.addEventListener('loadedmetadata', updateStats);
      video.addEventListener('progress', updateStats);
    }

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      // Clean up event listeners if video exists
      const v = videoRef.current;
      if (v) {
        v.removeEventListener('loadedmetadata', updateStats);
        v.removeEventListener('progress', updateStats);
      }
    };
  }, [videoRef, playerStatsRef, enabled]);

  return stats;
}
