//
//  PerformanceOverlayView.swift
//  FlixorMac
//
//  Performance statistics overlay for video playback
//  Based on plezy implementation
//

import SwiftUI

struct PerformanceOverlayView: View {
    let stats: PerformanceStats

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            // Left column - Video info
            VStack(alignment: .leading, spacing: 6) {
                Text("VIDEO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))

                StatRow(label: "Codec", value: stats.videoCodec ?? "N/A")
                StatRow(label: "Format", value: stats.videoFormat ?? "N/A")
                StatRow(label: "Resolution", value: stats.formattedResolution)
                StatRow(label: "FPS (container)", value: stats.formattedFps)
                StatRow(label: "FPS (actual)", value: stats.formattedEstimatedFps)
                StatRow(label: "Bitrate", value: stats.formattedVideoBitrate)
                StatRow(label: "Decoder", value: stats.decoderType)
            }

            // Middle column - Color/HDR info
            VStack(alignment: .leading, spacing: 6) {
                Text("COLOR/HDR")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))

                StatRow(label: "Type", value: stats.hdrType)
                StatRow(label: "Colorspace", value: stats.formattedColorspace)
                StatRow(label: "HDR Metadata", value: stats.formattedHdrMetadata)

                Spacer().frame(height: 12)

                Text("AUDIO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))

                StatRow(label: "Codec", value: stats.audioCodec ?? "N/A")
                StatRow(label: "Channels", value: stats.formattedAudioChannels)
                StatRow(label: "Sample Rate", value: stats.formattedSampleRate)
                StatRow(label: "Bitrate", value: stats.formattedAudioBitrate)
            }

            // Right column - Playback info
            VStack(alignment: .leading, spacing: 6) {
                Text("PLAYBACK")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))

                StatRow(label: "Dropped Frames", value: stats.formattedDroppedFrames)
                StatRow(label: "A/V Sync", value: stats.formattedAvsync)

                Spacer().frame(height: 12)

                Text("CACHE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))

                StatRow(label: "Buffer", value: stats.formattedCacheDuration)
                StatRow(label: "Used", value: stats.formattedCacheUsed)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

#Preview {
    PerformanceOverlayView(stats: PerformanceStats(
        videoCodec: "hevc",
        videoFormat: "p010le",
        videoWidth: 3840,
        videoHeight: 2160,
        videoFps: 23.976,
        videoBitrate: 45_000_000,
        hwdecCurrent: "videotoolbox",
        videoParamsPrimaries: "bt.2020",
        videoParamsGamma: "pq",
        sigPeak: 10.0,
        maxCll: 1000,
        maxFall: 400,
        audioCodec: "eac3",
        audioChannels: 6,
        audioSampleRate: 48000,
        audioBitrate: 640_000,
        decoderFrameDropCount: 0,
        frameDropCount: 0,
        avsync: 0.001,
        estimatedVfFps: 23.98,
        cacheUsed: 50_000_000,
        demuxerCacheDuration: 30.5
    ))
    .padding()
    .background(Color.gray)
}
