//
//  PlayerBackend.swift
//  FlixorTV
//
//  Player backend selection (AVKit or MPV)
//

import Foundation

/// Available player backends
enum PlayerBackend: String, CaseIterable, Codable, Hashable, Identifiable {
    case avkit = "AVKit (Native)"
    case mpv = "MPV (FFmpeg)"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var description: String {
        switch self {
        case .avkit:
            return "Native Apple player with full HDR support (10-bit+)"
        case .mpv:
            return "MPVKit-backed player with gpu-next and advanced codec support"
        }
    }

    var detailedDescription: String {
        switch self {
        case .avkit:
            return """
            • Full HDR10/Dolby Vision support
            • 10-bit+ color depth via Metal
            • Native PiP, AirPlay, Spatial Audio
            • DirectStream: MKV → HLS remux (no transcode)
            • Lower CPU/memory usage
            """
        case .mpv:
            return """
            • Direct MKV playback (no remux)
            • gpu-next + MoltenVK rendering path
            • Advanced codec/subtitle track support
            • Better format resilience for Plex libraries
            """
        }
    }

    var supportsNativeHDR: Bool {
        switch self {
        case .avkit: return true
        case .mpv: return true
        }
    }

    var supportsMKVDirectPlay: Bool {
        switch self {
        case .avkit: return false  // Needs DirectStream (remux to HLS/MP4)
        case .mpv: return true     // Native MKV support
        }
    }

    var supportsNativeControls: Bool {
        switch self {
        case .avkit: return true   // Native tvOS controls
        case .mpv: return false    // Custom controls only
        }
    }

    var supports10BitColor: Bool {
        switch self {
        case .avkit: return true
        case .mpv: return true
        }
    }
}
