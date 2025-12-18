//
//  PlayerController.swift
//  FlixorTV
//
//  Protocol for unified player interface (AVKit and MPV)
//

import Foundation

/// Player state
enum PlayerState: Equatable {
    case uninitialized
    case initializing
    case ready
    case loading
    case playing
    case paused
    case seeking
    case buffering
    case stopped
    case error(Error)

    static func == (lhs: PlayerState, rhs: PlayerState) -> Bool {
        switch (lhs, rhs) {
        case (.uninitialized, .uninitialized),
             (.initializing, .initializing),
             (.ready, .ready),
             (.loading, .loading),
             (.playing, .playing),
             (.paused, .paused),
             (.seeking, .seeking),
             (.buffering, .buffering),
             (.stopped, .stopped):
            return true
        case (.error, .error):
            return true  // Consider all errors equal for state comparison
        default:
            return false
        }
    }
}

/// Unified player controller protocol
/// Implemented by both AVKitPlayerController and MPVPlayerController
@MainActor
protocol PlayerController: ObservableObject {
    // MARK: - State Properties

    /// Current player state
    var state: PlayerState { get }

    /// Current playback position in seconds
    var currentTime: TimeInterval { get }

    /// Total duration in seconds
    var duration: TimeInterval { get }

    /// Whether playback is paused
    var isPaused: Bool { get }

    /// Volume level (0-100)
    var volume: Double { get }

    /// Current HDR mode
    var hdrMode: HDRMode { get }

    // MARK: - Playback Control

    /// Load a video file or stream URL
    /// - Parameter url: URL string (local file, HTTP URL, or Plex URL)
    func loadFile(_ url: String)

    /// Resume playback
    func play()

    /// Pause playback
    func pause()

    /// Seek to specific position
    /// - Parameter seconds: Position in seconds
    func seek(to seconds: Double)

    /// Set volume level
    /// - Parameter volume: Volume level (0-100)
    func setVolume(_ volume: Double)

    /// Shutdown player and release resources
    func shutdown()

    // MARK: - Callbacks

    /// Called when a property value changes
    /// - Parameters:
    ///   - property: Property name
    ///   - value: New value
    var onPropertyChange: ((String, Any?) -> Void)? { get set }

    /// Called when a player event occurs
    /// - Parameter event: Event name
    var onEvent: ((String) -> Void)? { get set }

    /// Called when HDR is detected
    /// - Parameters:
    ///   - isHDR: Whether content is HDR
    ///   - gamma: Gamma/transfer function (e.g., "pq", "hlg")
    ///   - primaries: Color primaries (e.g., "bt.2020")
    var onHDRDetected: ((Bool, String?, String?) -> Void)? { get set }
}
