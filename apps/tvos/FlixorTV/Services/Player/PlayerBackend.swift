//
//  PlayerBackend.swift
//  FlixorTV
//
//  Player backend selection (AVKit or MPV)
//

import Foundation

/// Available player backends
enum PlayerBackend: String, CaseIterable, Codable {
    case avkit = "AVKit (Native)"
    case mpv = "MPV (FFmpeg)"

    var description: String {
        switch self {
        case .avkit:
            return "Native Apple player with full HDR support (10-bit+)"
        case .mpv:
            return "FFmpeg-based player with advanced codec support (8-bit only)"
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
            • Advanced codec support
            • Limited to 8-bit color (OpenGL ES)
            • Higher CPU usage
            """
        }
    }

    var supportsNativeHDR: Bool {
        switch self {
        case .avkit: return true
        case .mpv: return false  // Limited to 8-bit via OpenGL ES
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
        case .mpv: return false
        }
    }
}
