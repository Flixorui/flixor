//
//  MPVTypes.swift
//  FlixorTV
//
//  Swift type definitions for MPV player
//

import Foundation

// MARK: - MPV Track

/// Represents an audio or subtitle track in MPV
struct MPVTrack: Identifiable, Equatable {
    let id: Int
    let type: String        // "audio", "sub", "video"
    let title: String?      // Track title (e.g., "English", "Japanese")
    let lang: String?       // Language code (e.g., "eng", "jpn")
    let codec: String?      // Codec name (e.g., "aac", "srt")
    let external: Bool      // Whether track is from external file

    var displayName: String {
        if let title = title {
            return title
        } else if let lang = lang {
            return lang.uppercased()
        } else {
            return "\(type.capitalized) Track \(id)"
        }
    }
}

// MARK: - MPV Event

/// MPV playback events
enum MPVEvent: String {
    case fileLoaded = "file-loaded"
    case fileStarted = "file-started"
    case playbackRestart = "playback-restart"
    case fileEnded = "file-ended"
    case seek = "seek"
    case pause = "pause"
    case unpause = "unpause"
    case idle = "idle"
    case shutdown = "shutdown"

    var description: String {
        switch self {
        case .fileLoaded: return "File loaded successfully"
        case .fileStarted: return "File started loading"
        case .playbackRestart: return "Playback restarted"
        case .fileEnded: return "File playback ended"
        case .seek: return "Seek operation"
        case .pause: return "Playback paused"
        case .unpause: return "Playback resumed"
        case .idle: return "Player idle"
        case .shutdown: return "Player shutdown"
        }
    }
}

// MARK: - MPV Property

/// Common MPV properties that can be observed
enum MPVProperty: String {
    case timePos = "time-pos"               // Current playback position (seconds)
    case duration = "duration"              // Total duration (seconds)
    case pause = "pause"                    // Pause state (bool)
    case volume = "volume"                  // Volume (0-100)
    case mute = "mute"                      // Mute state (bool)
    case speed = "speed"                    // Playback speed (0.01-100)
    case videoParams = "video-params"       // Video parameters
    case audioParams = "audio-params"       // Audio parameters
    case trackList = "track-list"           // Available tracks
    case aid = "aid"                        // Active audio track ID
    case sid = "sid"                        // Active subtitle track ID
    case vid = "vid"                        // Active video track ID
    case path = "path"                      // Current file path/URL
    case mediaTitle = "media-title"         // Media title
    case chapters = "chapter-list"          // Available chapters
    case demuxerCacheState = "demuxer-cache-state"  // Buffer state

    // HDR detection properties
    case videoPrimaries = "video-params/primaries"  // Color primaries
    case videoGamma = "video-params/gamma"          // Transfer function

    var description: String {
        switch self {
        case .timePos: return "Current Time Position"
        case .duration: return "Total Duration"
        case .pause: return "Pause State"
        case .volume: return "Volume Level"
        case .mute: return "Mute State"
        case .speed: return "Playback Speed"
        case .videoParams: return "Video Parameters"
        case .audioParams: return "Audio Parameters"
        case .trackList: return "Track List"
        case .aid: return "Active Audio Track"
        case .sid: return "Active Subtitle Track"
        case .vid: return "Active Video Track"
        case .path: return "File Path"
        case .mediaTitle: return "Media Title"
        case .chapters: return "Chapter List"
        case .demuxerCacheState: return "Buffer State"
        case .videoPrimaries: return "Video Color Primaries"
        case .videoGamma: return "Video Transfer Function"
        }
    }
}

// MARK: - HDR Mode

/// HDR/SDR playback mode
enum HDRMode: String {
    case sdr = "SDR"
    case hdr = "HDR"
    case dolbyVision = "Dolby Vision"

    var colorspace: String {
        switch self {
        case .sdr: return "sRGB"
        case .hdr: return "BT.2020 PQ"
        case .dolbyVision: return "BT.2020 PQ (Dolby Vision)"
        }
    }
}

// MARK: - MPV Error

/// MPV-specific errors
enum MPVError: LocalizedError {
    case initializationFailed
    case invalidHandle
    case commandFailed(String)
    case propertyNotFound(String)
    case renderContextFailed
    case fileLoadFailed(String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize MPV player"
        case .invalidHandle:
            return "Invalid MPV handle"
        case .commandFailed(let cmd):
            return "MPV command failed: \(cmd)"
        case .propertyNotFound(let prop):
            return "MPV property not found: \(prop)"
        case .renderContextFailed:
            return "Failed to create MPV render context"
        case .fileLoadFailed(let url):
            return "Failed to load file: \(url)"
        case .unsupportedFormat:
            return "Unsupported media format"
        }
    }
}

// MARK: - MPV Options

/// Common MPV configuration options
struct MPVOptions {
    // Note: 'vo' option removed - when using mpv_render_context, video output is handled automatically
    // Note: 'video' option removed - not a valid MPV option. Use 'vid' property at runtime.
    var audio: Bool = false                     // Enable audio decoding

    // Hardware decoding: videotoolbox-copy for correct colors
    // Decode with VideoToolbox, copy to CPU, MPV converts to RGB
    #if targetEnvironment(simulator)
    var hwdec: String = "no"                    // Software decode for simulator
    #else
    var hwdec: String = "videotoolbox-copy"     // Hardware decode + copy (correct RGB)
    #endif

    var cache: Bool = true                      // Enable caching
    var demuxerMaxBytes: String = "400MiB"      // Cache size
    var demuxerReadahead: String = "30"         // Readahead in seconds
    var userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    // Subtitle options
    var subAuto: Bool = false                   // Auto-load external subs
    var subVisibility: Bool = true              // Show subtitles if track selected

    // Audio options
    var audioFileAuto: Bool = false             // Auto-load external audio
    var volumeMax: Int = 100                    // Maximum volume

    // HDR passthrough (no tone-mapping - native HDR output)
    var toneMapping: String = "auto"            // Auto (disables tone-mapping for HDR displays)
    var targetPeak: String = "auto"             // Auto-detect from display
    var targetTrc: String = "auto"              // Auto-detect (will use PQ/HLG for HDR content)
    var targetPrim: String = "auto"             // Auto-detect color primaries
    var hdrComputePeak: String = "yes"          // Compute peak from video metadata
    var iccProfileAuto: String = "no"           // Disable ICC profiles for HDR

    /// Convert to dictionary for MPV option setting
    func toDictionary() -> [String: String] {
        return [
            // 'vo' not set - mpv_render_context handles video output automatically
            // "video" option removed - not valid. Video track enabled via 'vid' property at runtime.
            "audio": audio ? "yes" : "no",
            "hwdec": hwdec,
            "cache": cache ? "yes" : "no",
            "demuxer-max-bytes": demuxerMaxBytes,
            "demuxer-readahead-secs": demuxerReadahead,
            "user-agent": userAgent,
            "sub-auto": subAuto ? "yes" : "no",
            "sub-visibility": subVisibility ? "yes" : "no",
            "audio-file-auto": audioFileAuto ? "yes" : "no",
            "volume-max": String(volumeMax),
            // HDR passthrough settings (native HDR output)
            "tone-mapping": toneMapping,
            "target-peak": targetPeak,
            "target-trc": targetTrc,
            "target-prim": targetPrim,
            "hdr-compute-peak": hdrComputePeak,
            "icc-profile-auto": iccProfileAuto
        ]
    }
}

// MARK: - MPV State

/// Current state of MPV player
enum MPVState: Equatable {
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

    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }

    var isLoading: Bool {
        switch self {
        case .initializing, .loading, .buffering:
            return true
        default:
            return false
        }
    }

    // Manual Equatable implementation for enum with associated value
    static func == (lhs: MPVState, rhs: MPVState) -> Bool {
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
