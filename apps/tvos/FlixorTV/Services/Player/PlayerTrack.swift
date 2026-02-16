import Foundation

enum PlaybackQuality: String, CaseIterable, Identifiable, Codable {
    case original = "Original"
    case ultraHD = "4K (80 Mbps)"
    case fullHD = "1080p (20 Mbps)"
    case hd = "720p (10 Mbps)"
    case sd = "480p (4 Mbps)"
    case low = "360p (2 Mbps)"

    var id: String { rawValue }

    var bitrate: Int? {
        switch self {
        case .original: return nil
        case .ultraHD: return 80_000
        case .fullHD: return 20_000
        case .hd: return 10_000
        case .sd: return 4_000
        case .low: return 2_000
        }
    }

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

    var requiresTranscoding: Bool {
        self != .original
    }

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

    static func availableQualities(sourceWidth: Int?) -> [PlaybackQuality] {
        guard let sourceWidth else {
            return PlaybackQuality.allCases
        }

        var available: [PlaybackQuality] = [.original]
        if sourceWidth >= 3840 { available.append(.ultraHD) }
        if sourceWidth >= 1920 { available.append(.fullHD) }
        if sourceWidth >= 1280 { available.append(.hd) }
        if sourceWidth >= 854 { available.append(.sd) }
        available.append(.low)
        return available
    }
}

enum MPVSessionMode: String {
    case directPlay
    case directStream
    case transcode
}

struct PlaybackOverride: Equatable {
    var quality: PlaybackQuality = .original
    var audioStreamID: String?
    var subtitleStreamID: String?
}

enum SubtitleKind: String {
    case text
    case image
    case unknown

    var label: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .unknown: return "Unknown"
        }
    }
}

struct PlayerAudioOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let mpvTrackID: Int?
    let plexStreamID: String?
    let isSelected: Bool
    let requiresSessionRebuild: Bool
}

struct PlayerSubtitleOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let mpvTrackID: Int?
    let plexStreamID: String?
    let kind: SubtitleKind
    let isSelected: Bool
    let requiresSessionRebuild: Bool
}

struct PlayerTrack: Identifiable, Hashable {
    enum TrackType: String {
        case audio
        case subtitle = "sub"
        case video
    }

    let id: Int
    let ffIndex: Int?
    let type: TrackType
    let title: String?
    let language: String?
    let codec: String?
    let isDefault: Bool
    let isSelected: Bool

    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        if let language, !language.isEmpty {
            return language.uppercased()
        }
        if let codec, !codec.isEmpty {
            return codec.uppercased()
        }
        return "Track \(id)"
    }
}
