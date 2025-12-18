//
//  PlayerSettings.swift
//  FlixorTV
//
//  User settings for player configuration
//

import Foundation
import SwiftUI

/// Streaming protocol
enum StreamingProtocol: String, Codable, CaseIterable {
    case hls = "HLS"
    case dash = "DASH"

    var description: String {
        switch self {
        case .hls:
            return "HTTP Live Streaming (Apple standard)"
        case .dash:
            return "MPEG-DASH (adaptive streaming)"
        }
    }
}

/// Player settings (persisted via AppStorage)
class PlayerSettings: ObservableObject {
    /// Selected player backend
    @AppStorage("playerBackend") var backend: PlayerBackend = .avkit

    // MARK: - Playback Quality

    /// Prefer DirectPlay when possible (raw file playback)
    @AppStorage("preferDirectPlay") var preferDirectPlay: Bool = true

    /// Allow DirectStream (container remux without transcoding)
    @AppStorage("allowDirectStream") var allowDirectStream: Bool = true

    /// Maximum video bitrate (0 = original quality)
    @AppStorage("maxBitrate") var maxBitrate: Int = 0

    /// Enable auto quality adjustment based on network
    @AppStorage("autoAdjustQuality") var autoAdjustQuality: Bool = true

    // MARK: - Streaming

    /// Preferred streaming protocol
    @AppStorage("streamingProtocol") var streamingProtocol: StreamingProtocol = .hls

    // MARK: - Advanced

    /// Force HDR mode (for testing)
    @AppStorage("forceHDRMode") var forceHDRMode: Bool = false

    /// Show debug info overlay
    @AppStorage("showDebugInfo") var showDebugInfo: Bool = false

    // MARK: - Helpers

    /// Get bitrate display string
    var bitrateDisplay: String {
        if maxBitrate == 0 {
            return "Original Quality"
        } else {
            return "\(maxBitrate / 1000) Mbps"
        }
    }

    /// Reset to defaults
    func resetToDefaults() {
        backend = .avkit
        preferDirectPlay = true
        allowDirectStream = true
        maxBitrate = 0
        autoAdjustQuality = true
        streamingProtocol = .hls
        forceHDRMode = false
        showDebugInfo = false
    }
}
