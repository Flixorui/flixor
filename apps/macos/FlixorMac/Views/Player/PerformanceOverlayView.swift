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
            // Left column
            VStack(alignment: .leading, spacing: 10) {
                // Video section
                SectionHeader(icon: "video", title: "Video")
                StatRow(label: "Codec", value: stats.videoCodec ?? "N/A")
                StatRow(label: "Resolution", value: stats.formattedResolution)
                StatRow(label: "FPS", value: stats.formattedFps)
                StatRow(label: "Bitrate", value: stats.formattedVideoBitrate)
                StatRow(label: "Decoder", value: stats.decoderType)

                Spacer().frame(height: 8)

                // Color section
                SectionHeader(icon: "paintpalette", title: "Color")
                StatRow(label: "Pixel Fmt", value: stats.pixelFormat ?? "N/A")
                if let hwFmt = stats.hwPixelFormat, hwFmt != stats.pixelFormat {
                    StatRow(label: "HW Fmt", value: hwFmt)
                }
                StatRow(label: "Matrix", value: stats.colorMatrix ?? "N/A")
                StatRow(label: "Primaries", value: stats.videoParamsPrimaries ?? "N/A")
                StatRow(label: "Transfer", value: stats.videoParamsGamma ?? "N/A")

                // HDR section (only if HDR metadata available)
                if stats.hasHdrMetadata {
                    Spacer().frame(height: 8)

                    SectionHeader(icon: "sun.max", title: "HDR")
                    if stats.maxLuma != nil {
                        StatRow(label: "Max Luma", value: stats.formattedMaxLuma)
                    }
                    if stats.minLuma != nil {
                        StatRow(label: "Min Luma", value: stats.formattedMinLuma)
                    }
                    if stats.maxCll != nil {
                        StatRow(label: "MaxCLL", value: stats.formattedMaxCll)
                    }
                    if stats.maxFall != nil {
                        StatRow(label: "MaxFALL", value: stats.formattedMaxFall)
                    }
                }
            }

            // Right column
            VStack(alignment: .leading, spacing: 10) {
                // Audio section
                SectionHeader(icon: "speaker.wave.2", title: "Audio")
                StatRow(label: "Codec", value: stats.audioCodec ?? "N/A")
                StatRow(label: "Sample Rate", value: stats.formattedSampleRate)
                StatRow(label: "Channels", value: stats.formattedAudioChannels)
                StatRow(label: "Bitrate", value: stats.formattedAudioBitrate)

                Spacer().frame(height: 8)

                // Performance section
                SectionHeader(icon: "speedometer", title: "Performance")
                StatRow(label: "Render FPS", value: stats.formattedEstimatedFps)
                StatRow(label: "Display FPS", value: stats.formattedDisplayFps)
                StatRow(label: "A/V Sync", value: stats.formattedAvsync)
                StatRow(label: "Dropped", value: stats.formattedDroppedFrames)

                Spacer().frame(height: 8)

                // Buffer section
                SectionHeader(icon: "externaldrive", title: "Buffer")
                StatRow(label: "Duration", value: stats.formattedCacheDuration)
                StatRow(label: "Cache Used", value: stats.formattedCacheUsed)
                StatRow(label: "Speed", value: stats.formattedCacheSpeed)

                Spacer().frame(height: 8)

                // App section
                SectionHeader(icon: "app", title: "App")
                StatRow(label: "Memory", value: stats.formattedAppMemory)
                if let uiFps = stats.uiFps {
                    StatRow(label: "UI FPS", value: String(format: "%.1f", uiFps))
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(label):")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))

            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
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
        pixelFormat: "p010le",
        hwPixelFormat: "videotoolbox_vld",
        colorMatrix: "bt.2020-ncl",
        videoParamsPrimaries: "bt.2020",
        videoParamsGamma: "dolbyvision",
        sigPeak: 10.0,
        maxLuma: 1000,
        minLuma: 0.0001,
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
        displayFps: 60.0,
        cacheUsed: 50_000_000,
        cacheSpeed: 5_000_000,
        demuxerCacheDuration: 30.5,
        appMemoryBytes: 256_000_000,
        uiFps: 60.0
    ))
    .padding()
    .background(Color.gray)
}
