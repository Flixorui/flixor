//
//  PerformanceStats.swift
//  FlixorMac
//
//  Performance statistics model for MPV player overlay
//  Based on plezy implementation
//

import Foundation

/// Performance statistics collected from MPV for the stats overlay
struct PerformanceStats {
    // MARK: - Video Properties
    var videoCodec: String?
    var videoFormat: String?
    var videoWidth: Int?
    var videoHeight: Int?
    var videoFps: Double?
    var videoBitrate: Double?
    var hwdecCurrent: String?

    // MARK: - HDR/Color Properties
    var videoParamsPrimaries: String?
    var videoParamsGamma: String?
    var sigPeak: Double?
    var maxCll: Int?
    var maxFall: Int?

    // MARK: - Audio Properties
    var audioCodec: String?
    var audioChannels: Int?
    var audioSampleRate: Int?
    var audioBitrate: Double?

    // MARK: - Playback Properties
    var droppedFrames: Int?
    var decoderFrameDropCount: Int?
    var frameDropCount: Int?
    var avsync: Double?
    var estimatedVfFps: Double?

    // MARK: - Cache/Network Properties
    var cacheUsed: Int?
    var demuxerCacheDuration: Double?
    var demuxerCacheState: String?

    // MARK: - Computed Properties

    var formattedResolution: String {
        guard let width = videoWidth, let height = videoHeight else { return "N/A" }
        return "\(width)x\(height)"
    }

    var formattedFps: String {
        guard let fps = videoFps else { return "N/A" }
        return String(format: "%.2f fps", fps)
    }

    var formattedEstimatedFps: String {
        guard let fps = estimatedVfFps else { return "N/A" }
        return String(format: "%.2f fps", fps)
    }

    var formattedVideoBitrate: String {
        guard let bitrate = videoBitrate else { return "N/A" }
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", bitrate / 1_000_000)
        } else if bitrate >= 1_000 {
            return String(format: "%.0f Kbps", bitrate / 1_000)
        }
        return String(format: "%.0f bps", bitrate)
    }

    var formattedAudioBitrate: String {
        guard let bitrate = audioBitrate else { return "N/A" }
        if bitrate >= 1_000 {
            return String(format: "%.0f Kbps", bitrate / 1_000)
        }
        return String(format: "%.0f bps", bitrate)
    }

    var formattedAudioChannels: String {
        guard let channels = audioChannels else { return "N/A" }
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels) ch"
        }
    }

    var formattedSampleRate: String {
        guard let rate = audioSampleRate else { return "N/A" }
        if rate >= 1000 {
            return String(format: "%.1f kHz", Double(rate) / 1000)
        }
        return "\(rate) Hz"
    }

    var formattedAvsync: String {
        guard let sync = avsync else { return "N/A" }
        return String(format: "%.3f s", sync)
    }

    var formattedDroppedFrames: String {
        let decoder = decoderFrameDropCount ?? 0
        let output = frameDropCount ?? 0
        return "\(decoder + output)"
    }

    var formattedCacheDuration: String {
        guard let duration = demuxerCacheDuration else { return "N/A" }
        return String(format: "%.1f s", duration)
    }

    var formattedCacheUsed: String {
        guard let used = cacheUsed else { return "N/A" }
        if used >= 1_000_000 {
            return String(format: "%.1f MB", Double(used) / 1_000_000)
        } else if used >= 1_000 {
            return String(format: "%.0f KB", Double(used) / 1_000)
        }
        return "\(used) B"
    }

    var hdrType: String {
        guard let sigPeak = sigPeak, sigPeak > 1.0 else { return "SDR" }

        // Check for Dolby Vision first (typically has very high peak)
        if let gamma = videoParamsGamma, gamma.lowercased().contains("dovi") {
            return "Dolby Vision"
        }

        // Check primaries and transfer function
        if let gamma = videoParamsGamma {
            if gamma.lowercased().contains("pq") || gamma.lowercased().contains("smpte2084") {
                if let primaries = videoParamsPrimaries, primaries.lowercased().contains("2020") {
                    return "HDR10"
                }
            } else if gamma.lowercased().contains("hlg") {
                return "HLG"
            }
        }

        return "HDR"
    }

    var formattedHdrMetadata: String {
        var parts: [String] = []

        if let peak = sigPeak, peak > 1.0 {
            parts.append(String(format: "Peak: %.0f nits", peak * 203))
        }

        if let cll = maxCll {
            parts.append("MaxCLL: \(cll)")
        }

        if let fall = maxFall {
            parts.append("MaxFALL: \(fall)")
        }

        return parts.isEmpty ? "N/A" : parts.joined(separator: ", ")
    }

    var formattedColorspace: String {
        var parts: [String] = []

        if let primaries = videoParamsPrimaries, !primaries.isEmpty {
            parts.append(primaries)
        }

        if let gamma = videoParamsGamma, !gamma.isEmpty {
            parts.append(gamma)
        }

        return parts.isEmpty ? "N/A" : parts.joined(separator: " / ")
    }

    var decoderType: String {
        guard let hwdec = hwdecCurrent, !hwdec.isEmpty, hwdec != "no" else {
            return "Software"
        }
        return hwdec.uppercased()
    }
}
