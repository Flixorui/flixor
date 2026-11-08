//
//  PlayerViewModel+Types.swift
//  FlixorMac
//
//  Value types used by the player: playback quality profiles, markers, episode metadata
//

import Foundation

// MARK: - Playback Quality

/// Quality profiles for video playback with transcoding support
enum PlaybackQuality: String, CaseIterable, Identifiable, Codable {
    case original = "Original"           // Direct Play (no transcoding)
    case ultraHD = "4K (80 Mbps)"       // 3840x2160, 80000 kbps
    case fullHD = "1080p (20 Mbps)"     // 1920x1080, 20000 kbps
    case hd = "720p (10 Mbps)"          // 1280x720, 10000 kbps
    case sd = "480p (4 Mbps)"           // 854x480, 4000 kbps
    case low = "360p (2 Mbps)"          // 640x360, 2000 kbps

    var id: String { rawValue }

    /// Bitrate in kbps (nil for original/direct play)
    var bitrate: Int? {
        switch self {
        case .original: return nil
        case .ultraHD: return 80000
        case .fullHD: return 20000
        case .hd: return 10000
        case .sd: return 4000
        case .low: return 2000
        }
    }

    /// Resolution string for Plex API (nil for original/direct play)
    var resolution: String? {
        switch self {
        case .original: return nil
        case .ultraHD: return "3840x2160"
        case .fullHD: return "1920x1080"
        case .hd: return "1280x720"
        case .sd: return "854x480"
        case .low: return "640x360"
        }
    }

    /// Whether this quality requires transcoding
    var requiresTranscoding: Bool {
        return self != .original
    }

    /// Resolution width for comparison
    var widthValue: Int? {
        switch self {
        case .original: return nil
        case .ultraHD: return 3840
        case .fullHD: return 1920
        case .hd: return 1280
        case .sd: return 854
        case .low: return 640
        }
    }

    /// Filter qualities to only show options equal to or lower than source
    static func availableQualities(sourceWidth: Int?) -> [PlaybackQuality] {
        guard let sourceWidth = sourceWidth else {
            // If we don't know source resolution, show all options
            return PlaybackQuality.allCases
        }

        // Always include Original (Direct Play)
        var available: [PlaybackQuality] = [.original]

        // Add transcoding options that are <= source resolution
        if sourceWidth >= 3840 {
            available.append(.ultraHD)
        }
        if sourceWidth >= 1920 {
            available.append(.fullHD)
        }
        if sourceWidth >= 1280 {
            available.append(.hd)
        }
        if sourceWidth >= 854 {
            available.append(.sd)
        }
        // Always include low quality as a fallback
        available.append(.low)

        return available
    }
}

// MARK: - Helper Response Types

struct EmptyResponse: Codable {}

struct PlayerMarker: Codable, Identifiable {
    let id: String
    let type: String // "intro", "credits", "commercial"
    let startTimeOffset: Int // milliseconds
    let endTimeOffset: Int // milliseconds

    enum CodingKeys: String, CodingKey {
        case id, type, startTimeOffset, endTimeOffset
    }
}

struct EpisodeMetadata: Codable, Identifiable, Equatable {
    let ratingKey: String
    let title: String
    let index: Int?
    let parentIndex: Int?
    let thumb: String?
    let summary: String?
    let viewOffset: Int? // Resume position in milliseconds
    let duration: Int? // Total duration in milliseconds
    let viewCount: Int? // Number of times watched

    var id: String { ratingKey }

    // Calculate progress percentage (0-100)
    var progressPercent: Int? {
        guard let dur = duration, dur > 0 else { return nil }

        // If fully watched (viewCount > 0), show 100%
        if let vc = viewCount, vc > 0 {
            if let o = viewOffset {
                let progress = Double(o) / Double(dur)
                // If within last 2% or viewOffset is very small, treat as fully watched
                if progress < 0.02 {
                    return 100
                }
                return Int(round(progress * 100))
            } else {
                // viewCount > 0 but no viewOffset = fully watched
                return 100
            }
        }

        // Partially watched - calculate from viewOffset
        guard let offset = viewOffset, offset > 0 else { return nil }
        let percent = Int((Double(offset) / Double(dur)) * 100)
        return min(100, max(0, percent))
    }

    static func == (lhs: EpisodeMetadata, rhs: EpisodeMetadata) -> Bool {
        lhs.ratingKey == rhs.ratingKey
    }
}
