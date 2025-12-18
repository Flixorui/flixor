//
//  PlexStreamingManager.swift
//  FlixorTV
//
//  Manages Plex streaming decisions and URL building
//  Handles DirectPlay, DirectStream (remux), and Transcode
//

import Foundation

class PlexStreamingManager {
    // MARK: - Properties

    private let baseUrl: String
    private let token: String
    private let clientId: String
    private let isBackendProxy: Bool

    // MARK: - Types

    /// Playback method determined by Plex
    enum PlaybackMethod {
        /// DirectPlay: Play raw file from disk (MP4, MOV)
        case directPlay(url: String)

        /// DirectStream: Remux container (MKV → MP4/HLS) WITHOUT transcoding video/audio
        case directStream(url: String)

        /// Transcode: Re-encode video and/or audio
        case transcode(url: String)
    }

    /// Streaming decision from Plex API
    struct StreamingDecision {
        let method: PlaybackMethod
        let canDirectPlay: Bool           // directPlayDecisionCode="1000"
        let canDirectStream: Bool          // video decision="copy"
        let willTranscode: Bool            // video decision="transcode"
        let videoDecision: String          // "copy" or "transcode"
        let audioDecision: String          // "copy" or "transcode"
        let videoCodec: String             // Codec name (e.g., "hevc", "h264")
        let audioCodec: String             // Codec name (e.g., "aac", "eac3")
        let sessionId: String              // Unique session identifier
    }

    /// Options for streaming
    struct StreamingOptions {
        var streamingProtocol: String = "hls"  // "hls" or "dash"
        var directPlay: Bool = true            // Allow DirectPlay
        var directStream: Bool = true          // Allow DirectStream (remux)
        var maxVideoBitrate: Int? = nil        // Bitrate limit (nil = original)
        var videoResolution: String? = nil     // e.g., "1920x1080"
        var audioStreamID: String? = nil       // Selected audio track
        var subtitleStreamID: String? = nil    // Selected subtitle track
        var autoAdjustQuality: Bool = true     // Enable adaptive bitrate
    }

    // MARK: - Initialization

    init(baseUrl: String, token: String) {
        self.baseUrl = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
        self.isBackendProxy = (token == "backend-proxy")
        self.clientId = Self.getOrCreateClientId()

        print("📡 [PlexStreaming] Initialized: \(baseUrl) (backend proxy: \(isBackendProxy))")
    }

    // MARK: - Decision API

    /// Get streaming decision from Plex
    func getStreamingDecision(
        ratingKey: String,
        options: StreamingOptions = StreamingOptions()
    ) async throws -> StreamingDecision {
        let sessionId = UUID().uuidString

        // Build decision URL
        let decisionURL = buildDecisionURL(ratingKey: ratingKey, options: options, sessionId: sessionId)

        print("📡 [PlexStreaming] Requesting decision for ratingKey: \(ratingKey)")

        // Fetch decision with JSON response
        var request = decisionURL
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)

        // Debug: Print raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📄 [PlexStreaming] Decision Response JSON:")
            print(jsonString)
        }

        // Parse JSON response
        let response = try JSONDecoder().decode(DecisionResponse.self, from: data)

        guard let container = response.MediaContainer,
              let part = container.Metadata?.first?.Media?.first?.Part?.first else {
            throw NSError(domain: "PlexStreaming", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid decision response"])
        }

        let canDirectPlay = (part.decision == "directplay")
        let videoStream = part.Stream?.first(where: { $0.streamType == 1 })
        let audioStream = part.Stream?.first(where: { $0.streamType == 2 })

        let videoDecision = videoStream?.decision ?? "transcode"
        let audioDecision = audioStream?.decision ?? "copy"
        let videoCodec = videoStream?.codec ?? "unknown"
        let audioCodec = audioStream?.codec ?? "unknown"

        let media = container.Metadata?.first?.Media?.first

        print("📊 [PlexStreaming] Decision:")
        print("   DirectPlay Code: \(container.directPlayDecisionCode ?? -1)")
        print("   DirectPlay Text: \(container.directPlayDecisionText ?? "unknown")")
        print("   Transcode Code:  \(container.transcodeDecisionCode ?? -1)")
        print("   Transcode Text:  \(container.transcodeDecisionText ?? "unknown")")
        print("   Container:       \(media?.container ?? "unknown") → \(media?.protocol ?? "unknown")")
        print("   Video:           \(videoDecision) (codec: \(videoCodec))")
        print("   Audio:           \(audioDecision) (codec: \(audioCodec))")
        if let videoBitrate = videoStream?.bitrate {
            print("   Video Bitrate:   \(videoBitrate / 1000) kbps")
        }
        if let audioBitrate = audioStream?.bitrate {
            print("   Audio Bitrate:   \(audioBitrate / 1000) kbps")
        }

        // Determine playback method
        let method: PlaybackMethod

        if canDirectPlay && options.directPlay {
            // DirectPlay: Use raw file URL
            let fileUrl = try await getDirectPlayURL(ratingKey: ratingKey)
            method = .directPlay(url: fileUrl)
            print("▶️ [PlexStreaming] Method: DirectPlay")

        } else if videoDecision == "copy" && options.directStream {
            // DirectStream: Remux container WITHOUT transcoding
            let streamUrl = buildStreamURL(ratingKey: ratingKey, options: options, sessionId: sessionId)
            method = .directStream(url: streamUrl)
            print("📡 [PlexStreaming] Method: DirectStream (remux \(videoCodec) in HLS)")

        } else {
            // Transcode: Re-encode video/audio
            let streamUrl = buildStreamURL(ratingKey: ratingKey, options: options, sessionId: sessionId)
            method = .transcode(url: streamUrl)
            print("🔄 [PlexStreaming] Method: Transcode (\(videoCodec) → H.264)")
        }

        return StreamingDecision(
            method: method,
            canDirectPlay: canDirectPlay,
            canDirectStream: videoDecision == "copy",
            willTranscode: videoDecision == "transcode",
            videoDecision: videoDecision,
            audioDecision: audioDecision,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            sessionId: sessionId
        )
    }

    // MARK: - URL Building

    /// Build decision API URL
    private func buildDecisionURL(
        ratingKey: String,
        options: StreamingOptions,
        sessionId: String
    ) -> URLRequest {
        let path = isBackendProxy ? "/plex/video/:/transcode/universal/decision" : "/video/:/transcode/universal/decision"
        var components = URLComponents(string: "\(baseUrl)\(path)")!

        var params: [URLQueryItem] = [
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: options.streamingProtocol),
            URLQueryItem(name: "directPlay", value: options.directPlay ? "1" : "0"),
            URLQueryItem(name: "directStream", value: options.directStream ? "1" : "0"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "videoQuality", value: "12"),  // 12 = Original quality (Plex uses 0-12 scale)
            URLQueryItem(name: "session", value: sessionId),
        ]

        // Add token only for direct Plex (backend handles auth internally)
        if !isBackendProxy {
            params.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }

        // Add quality settings
        if let bitrate = options.maxVideoBitrate {
            params.append(URLQueryItem(name: "maxVideoBitrate", value: String(bitrate)))
        }

        // Only add videoResolution if explicitly specified
        // Omitting this parameter tells Plex to preserve original resolution
        if let resolution = options.videoResolution {
            params.append(URLQueryItem(name: "videoResolution", value: resolution))
        }
        // DO NOT send empty string - that makes Plex default to 1080p!

        components.queryItems = params

        // Create URLRequest with proper HTTP headers
        var request = URLRequest(url: components.url!)
        addPlexHeaders(to: &request)

        // Log the full decision URL for debugging
        print("🔍 [PlexStreaming] Decision URL: \(components.url?.absoluteString ?? "invalid")")

        return request
    }

    /// Build streaming URL (DirectStream or Transcode)
    private func buildStreamURL(
        ratingKey: String,
        options: StreamingOptions,
        sessionId: String
    ) -> String {
        let ext = options.streamingProtocol == "hls" ? "m3u8" : "mpd"
        let path = isBackendProxy ? "/plex/video/:/transcode/universal/start.\(ext)" : "/video/:/transcode/universal/start.\(ext)"
        var components = URLComponents(string: "\(baseUrl)\(path)")!

        var params: [URLQueryItem] = [
            URLQueryItem(name: "hasMDE", value: "1"),
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: options.streamingProtocol),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: options.directStream ? "1" : "0"),
            URLQueryItem(name: "directStreamAudio", value: "1"),
            URLQueryItem(name: "subtitleSize", value: "100"),
            URLQueryItem(name: "audioBoost", value: "100"),
            URLQueryItem(name: "videoQuality", value: "12"),  // 12 = Original quality (Plex uses 0-12 scale)
            URLQueryItem(name: "autoAdjustQuality", value: "0"),  // Disable adaptive - force original quality
            URLQueryItem(name: "session", value: sessionId),
        ]

        // Add token only for direct Plex (backend handles auth internally)
        if !isBackendProxy {
            params.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }

        // Add X-Plex client identification (required for streaming)
        params.append(URLQueryItem(name: "X-Plex-Client-Identifier", value: clientId))
        params.append(URLQueryItem(name: "X-Plex-Product", value: "Flixor"))
        params.append(URLQueryItem(name: "X-Plex-Platform", value: "tvOS"))
        params.append(URLQueryItem(name: "X-Plex-Platform-Version", value: "18.0"))
        params.append(URLQueryItem(name: "X-Plex-Device", value: "Apple TV"))

        // Add quality settings
        if let bitrate = options.maxVideoBitrate {
            params.append(URLQueryItem(name: "maxVideoBitrate", value: String(bitrate)))
        }

        // Only add videoResolution if explicitly specified
        // Omitting this parameter tells Plex to preserve original resolution
        if let resolution = options.videoResolution {
            params.append(URLQueryItem(name: "videoResolution", value: resolution))
        }
        // DO NOT send empty string - that makes Plex default to 1080p!

        components.queryItems = params
        let finalURL = components.url!.absoluteString
        print("🔗 [PlexStreaming] Stream URL: \(finalURL)")
        return finalURL
    }

    /// Get DirectPlay URL (raw file)
    private func getDirectPlayURL(ratingKey: String) async throws -> String {
        // Fetch metadata to get file path
        let metaPath = isBackendProxy ? "/plex/library/metadata/\(ratingKey)" : "/library/metadata/\(ratingKey)"
        var metaURLString = "\(baseUrl)\(metaPath)"
        if !isBackendProxy {
            metaURLString += "?X-Plex-Token=\(token)"
        }

        let metaURL = URL(string: metaURLString)!

        // Request JSON response
        var request = URLRequest(url: metaURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)

        // Debug: Print raw JSON response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📄 [PlexStreaming] Metadata Response JSON:")
            print(jsonString)
        }

        // Parse JSON to get Media.Part.key
        let response = try JSONDecoder().decode(MetadataResponse.self, from: data)

        guard let partKey = response.MediaContainer?.Metadata?.first?.Media?.first?.Part?.first?.key else {
            throw NSError(
                domain: "PlexStreaming",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No part key found in metadata"]
            )
        }

        if isBackendProxy {
            return "\(baseUrl)/plex\(partKey)"
        } else {
            return "\(baseUrl)\(partKey)?X-Plex-Token=\(token)"
        }
    }

    /// Add X-Plex headers to request with device capabilities
    private func addPlexHeaders(to request: inout URLRequest) {
        request.setValue("Flixor", forHTTPHeaderField: "X-Plex-Product")
        request.setValue("1.0.0", forHTTPHeaderField: "X-Plex-Version")
        request.setValue(clientId, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("tvOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue("18.0", forHTTPHeaderField: "X-Plex-Platform-Version")
        request.setValue("Apple TV", forHTTPHeaderField: "X-Plex-Device")
        request.setValue("Flixor for Apple TV", forHTTPHeaderField: "X-Plex-Device-Name")

        // Build Apple TV profile augmentation
        // Apple TV supports HEVC (HDR10) and H.264 for HLS streaming
        // Dolby Vision will fail DirectStream → automatic fallback to transcode with HDR preserved
        var profileParts: [String] = []

        // 1. Add DirectPlay profile for MP4/MOV containers
        profileParts.append("add-direct-play-profile(type=videoProfile&container=mp4,mov&videoCodec=hevc,h264&audioCodec=aac,ac3,eac3,mp3&subtitleCodec=*)")

        // 2. Add DirectPlay profile for MPEG-TS (HLS)
        profileParts.append("add-direct-play-profile(type=videoProfile&container=mpegts&videoCodec=hevc,h264&audioCodec=aac,ac3,eac3,mp3&subtitleCodec=*)")

        // 3. Add transcode target for HLS with HEVC ONLY (preserves 10-bit HDR)
        // H.264 is excluded because it doesn't support 10-bit HDR properly
        // Regular HEVC/HDR10: DirectStream (copy)
        // Dolby Vision: DirectStream fails → Transcode to HEVC with HDR10 preserved
        profileParts.append("add-transcode-target-codec(type=videoProfile&context=streaming&protocol=hls&videoCodec=hevc&audioCodec=aac,ac3,eac3)")

        // 4. Set limitations for HEVC ONLY
        // By not declaring H.264 limitations, we signal to Plex that H.264 is NOT supported for transcoding
        // H.264 will still work for DirectPlay/DirectStream via the direct-play-profile declarations above
        profileParts.append("add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.level&value=153)")  // Level 5.1
        profileParts.append("add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.width&value=3840)")  // 4K width
        profileParts.append("add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.height&value=2160)")  // 4K height
        profileParts.append("add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.bitrate&value=120000)")  // 120 Mbps
        profileParts.append("add-limitation(scope=videoCodec&scopeName=hevc&type=upperBound&name=video.bitDepth&value=10)")  // 10-bit (HDR)

        let profileExtra = profileParts.joined(separator: "+")
        request.setValue(profileExtra, forHTTPHeaderField: "X-Plex-Client-Profile-Extra")

        print("📤 [PlexStreaming] Request Headers:")
        print("   X-Plex-Product: Flixor")
        print("   X-Plex-Platform: tvOS")
        print("   X-Plex-Client-Profile-Extra: \(profileExtra)")
    }

    // MARK: - Client ID

    private static func getOrCreateClientId() -> String {
        let key = "plex_client_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}

// MARK: - JSON Response Models

/// Decision API response
private struct DecisionResponse: Decodable {
    let MediaContainer: DecisionMediaContainer?
}

private struct DecisionMediaContainer: Decodable {
    let Metadata: [DecisionMetadata]?
    let directPlayDecisionCode: Int?
    let directPlayDecisionText: String?
    let transcodeDecisionCode: Int?
    let transcodeDecisionText: String?
}

private struct DecisionMetadata: Decodable {
    let Media: [DecisionMedia]?
}

private struct DecisionMedia: Decodable {
    let Part: [DecisionPart]?
    let `protocol`: String?
    let container: String?
    let videoCodec: String?
    let audioCodec: String?
}

private struct DecisionPart: Decodable {
    let decision: String?
    let Stream: [DecisionStream]?
}

private struct DecisionStream: Decodable {
    let streamType: Int?
    let decision: String?
    let codec: String?
    let bitrate: Int?
    let location: String?
}

/// Metadata API response
private struct MetadataResponse: Decodable {
    let MediaContainer: MetadataMediaContainer?
}

private struct MetadataMediaContainer: Decodable {
    let Metadata: [MetadataItem]?
}

private struct MetadataItem: Decodable {
    let Media: [MetadataMedia]?
}

private struct MetadataMedia: Decodable {
    let Part: [MetadataPart]?
}

private struct MetadataPart: Decodable {
    let key: String?
}
