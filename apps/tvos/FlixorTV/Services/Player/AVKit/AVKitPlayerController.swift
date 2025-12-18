//
//  AVKitPlayerController.swift
//  FlixorTV
//
//  AVPlayer wrapper with Plex streaming support and HDR detection
//

import AVFoundation
import AVKit
import Combine
import FlixorKit

@MainActor
class AVKitPlayerController: ObservableObject, PlayerController {
    // MARK: - Properties

    private(set) var player: AVPlayer
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var streamingManager: PlexStreamingManager?
    private var cancellables = Set<AnyCancellable>()

    // Progress tracking
    private var progressTimer: Timer?
    private var lastReportedProgress: TimeInterval = 0
    private var ratingKey: String?
    private var sessionId: String?

    // Plex connection info for cleanup
    private var plexBaseUrl: String?
    private var plexToken: String?
    private var currentRatingKey: String?
    private var hasRetriedWithTranscode: Bool = false

    // MARK: - Published State

    @Published private(set) var state: PlayerState = .uninitialized
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPaused: Bool = true
    @Published private(set) var volume: Double = 100.0
    @Published private(set) var hdrMode: HDRMode = .sdr

    // MARK: - Callbacks

    var onPropertyChange: ((String, Any?) -> Void)?
    var onEvent: ((String) -> Void)?
    var onHDRDetected: ((Bool, String?, String?) -> Void)?

    // MARK: - Initialization

    init() {
        self.player = AVPlayer()
        setupPlayer()
        print("✅ [AVKit] Player initialized")
    }

    private func setupPlayer() {
        // Enable automatic HDR
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.allowsExternalPlayback = true

        // Observe playback state
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                self?.handleTimeControlStatus(status)
            }
            .store(in: &cancellables)

        // Observe rate changes
        player.publisher(for: \.rate)
            .sink { [weak self] rate in
                self?.isPaused = rate == 0
            }
            .store(in: &cancellables)

        // Add time observer (updates every 0.5s)
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }

        state = .ready
    }

    // MARK: - Playback Control

    func loadFile(_ url: String) {
        print("📺 [AVKit] Loading: \(url)")
        state = .loading

        // Check if this is a Plex URL (metadata URL from backend or direct Plex server)
        if url.contains("/library/metadata/") {
            loadPlexContent(url)
        } else {
            loadDirectURL(url)
        }
    }

    private func loadDirectURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            print("❌ [AVKit] Invalid URL: \(urlString)")
            state = .error(NSError(domain: "AVKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        print("▶️ [AVKit] DirectPlay: \(url.lastPathComponent)")

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        setupPlayerItem(item)
        player.replaceCurrentItem(with: item)
        self.playerItem = item

        // Don't call play() here - wait for item to be ready
        // play() will be called in handleItemStatus when status becomes .readyToPlay
    }

    private func loadPlexContent(_ urlString: String) {
        // Parse URL to extract ratingKey
        // URL format: http://backend:3001/plex/library/metadata/13624
        guard let ratingKey = parsePlexRatingKey(urlString) else {
            print("❌ [AVKit] Failed to extract rating key from URL")
            state = .error(NSError(domain: "AVKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Plex URL"]))
            return
        }

        // Store ratingKey for progress tracking and retry logic
        self.ratingKey = ratingKey
        self.currentRatingKey = ratingKey
        self.hasRetriedWithTranscode = false

        print("📡 [AVKit] Loading Plex content: ratingKey=\(ratingKey)")

        Task {
            do {
                // Get Plex server info from backend (like macOS app)
                let api = APIClient.shared
                let servers = try await api.getPlexServers()
                guard let activeServer = servers.first(where: { $0.isActive == true }) else {
                    throw NSError(domain: "AVKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active Plex server configured"])
                }

                print("📡 [AVKit] Using server: \(activeServer.name)")

                let connectionsResponse = try await api.getPlexConnections(serverId: activeServer.id)
                let connections = connectionsResponse.connections

                // Prefer local connection, fall back to first available
                guard let selectedConnection = connections.first(where: { $0.local == true }) ?? connections.first else {
                    throw NSError(domain: "AVKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Plex server connection available"])
                }

                let baseUrl = selectedConnection.uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                print("📡 [AVKit] Server URL: \(baseUrl)")

                // Get Plex access token
                let authServers = try await api.getPlexAuthServers()
                guard let serverWithToken = authServers.first(where: {
                    $0.clientIdentifier == activeServer.id ||
                    $0.clientIdentifier == activeServer.machineIdentifier
                }), let token = serverWithToken.token as String? else {
                    throw NSError(domain: "AVKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get Plex access token"])
                }

                print("📡 [AVKit] Got access token")

                // Store for cleanup
                self.plexBaseUrl = baseUrl
                self.plexToken = token

                // Now call Plex server directly using PlexStreamingManager
                streamingManager = PlexStreamingManager(baseUrl: baseUrl, token: token)

                // Check if device supports HDR playback
                let supportsHDR = AVPlayer.eligibleForHDRPlayback
                print("📺 [AVKit] Device HDR capability: \(supportsHDR ? "Yes" : "No")")

                let decision = try await streamingManager!.getStreamingDecision(
                    ratingKey: ratingKey,
                    options: PlexStreamingManager.StreamingOptions(
                        streamingProtocol: "hls",
                        directPlay: false,       // Disable DirectPlay
                        directStream: true,      // Try DirectStream first
                        maxVideoBitrate: nil,    // No bitrate limit (original quality)
                        videoResolution: nil,    // Preserve original resolution
                        autoAdjustQuality: true
                    )
                )

                await loadWithDecision(decision)
            } catch {
                print("❌ [AVKit] Streaming failed: \(error)")
                state = .error(error)
            }
        }
    }

    private func loadWithDecision(_ decision: PlexStreamingManager.StreamingDecision) async {
        var finalURLString: String

        // Store sessionId for cleanup
        self.sessionId = decision.sessionId

        switch decision.method {
        case .directPlay(let url):
            print("▶️ [AVKit] DirectPlay (Original Quality)")
            print("   Video: \(decision.videoDecision) (\(decision.videoCodec))")
            print("   Audio: \(decision.audioDecision) (\(decision.audioCodec))")
            finalURLString = url

        case .directStream(let url):
            print("📡 [AVKit] DirectStream (Container remux, no transcoding)")
            print("   Video: \(decision.videoDecision) (\(decision.videoCodec))")
            print("   Audio: \(decision.audioDecision) (\(decision.audioCodec))")
            print("   Start URL: \(url)")

            // DirectStream uses transcode infrastructure for remuxing
            // Need to start session first
            if url.contains("start.m3u8") {
                do {
                    finalURLString = try await startStreamSession(url: url, sessionId: decision.sessionId)
                } catch {
                    print("❌ [AVKit] Failed to start DirectStream session: \(error)")
                    state = .error(error)
                    return
                }
            } else {
                finalURLString = url
            }

        case .transcode(let url):
            print("🔄 [AVKit] Transcode (Re-encoding to H.264/AAC for compatibility)")
            print("   Video: \(decision.videoCodec) → H.264 (transcoding)")
            print("   Audio: \(decision.audioCodec) → \(decision.audioDecision == "copy" ? decision.audioCodec + " (copy)" : "AAC (transcoding)")")
            print("   Start URL: \(url)")

            // Transcode requires starting session first
            if url.contains("start.m3u8") {
                do {
                    finalURLString = try await startStreamSession(url: url, sessionId: decision.sessionId)
                } catch {
                    print("❌ [AVKit] Failed to start transcode session: \(error)")
                    state = .error(error)
                    return
                }
            } else {
                finalURLString = url
            }
        }

        guard let url = URL(string: finalURLString) else {
            print("❌ [AVKit] Invalid stream URL")
            state = .error(NSError(domain: "AVKit", code: -1))
            return
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        setupPlayerItem(item)
        player.replaceCurrentItem(with: item)
        self.playerItem = item

        // Don't call play() here - wait for item to be ready
        // play() will be called in handleItemStatus when status becomes .readyToPlay
    }

    private func startStreamSession(url: String, sessionId: String) async throws -> String {
        print("🎬 [AVKit] Starting stream session: \(sessionId)")

        guard let startURL = URL(string: url) else {
            throw NSError(domain: "AVKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid start URL"])
        }

        // Hit the start.m3u8 URL to initiate the session
        let (data, response) = try await URLSession.shared.data(from: startURL)
        if let httpResponse = response as? HTTPURLResponse {
            print("📺 [AVKit] Start response: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let errorText = String(data: data, encoding: .utf8) {
                    print("❌ [AVKit] Start error: \(errorText)")
                }
                throw NSError(domain: "AVKit", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "Start session failed with status \(httpResponse.statusCode)"])
            }
        }

        // Wait for session to generate initial segments
        let delaySeconds = 2
        print("⏳ [AVKit] Waiting \(delaySeconds)s for session to start...")
        try await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)

        // Build session URL
        // Parse base URL and token from start URL
        guard let urlComponents = URLComponents(string: url),
              let baseUrlString = url.components(separatedBy: "/video/").first else {
            throw NSError(domain: "AVKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not parse base URL"])
        }

        // Get token from query parameters
        let token = urlComponents.queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value

        // Build the session playback URL
        var sessionURL = "\(baseUrlString)/video/:/transcode/universal/session/\(sessionId)/base/index.m3u8"
        if let token = token {
            sessionURL += "?X-Plex-Token=\(token)"
        }

        print("✅ [AVKit] Session URL: \(sessionURL)")
        return sessionURL
    }

    private func setupPlayerItem(_ item: AVPlayerItem) {
        // Observe status
        item.publisher(for: \.status)
            .sink { [weak self] status in
                self?.handleItemStatus(status)
            }
            .store(in: &cancellables)

        // Observe duration
        item.publisher(for: \.duration)
            .sink { [weak self] duration in
                if duration.isNumeric && !duration.seconds.isNaN {
                    self?.duration = duration.seconds
                }
            }
            .store(in: &cancellables)

        // Observe loaded time ranges (for buffering state)
        item.publisher(for: \.loadedTimeRanges)
            .sink { [weak self] _ in
                // Could update buffering state here
            }
            .store(in: &cancellables)

        // Detect HDR
        detectHDRMode(from: item)
    }

    // MARK: - HDR Detection

    private func detectHDRMode(from item: AVPlayerItem) {
        Task {
            print("🔍 [AVKit] Detecting video tracks and HDR mode...")

            // Wait a bit for HLS manifest to fully load
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

            // Log asset type
            let asset = item.asset
            if asset is AVURLAsset {
                let urlAsset = asset as! AVURLAsset
                print("📁 [AVKit] Asset URL: \(urlAsset.url.absoluteString)")
            }

            // Try to load all tracks (video + audio) for debugging
            do {
                let allTracks = try await asset.loadTracks(withMediaType: .video)
                print("📹 [AVKit] Found \(allTracks.count) video track(s)")

                guard let track = allTracks.first else {
                    print("⚠️ [AVKit] No video track found in HLS stream")

                    // Check if there are audio tracks at least
                    let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
                    print("🔊 [AVKit] Found \(audioTracks?.count ?? 0) audio track(s)")

                    // Check player item tracks
                    print("🔍 [AVKit] Checking AVPlayerItem.tracks...")
                    let itemTracks = item.tracks
                    print("📊 [AVKit] AVPlayerItem has \(itemTracks.count) total tracks")
                    for (index, itemTrack) in itemTracks.enumerated() {
                        print("   Track \(index): enabled=\(itemTrack.isEnabled), assetTrack=\(itemTrack.assetTrack != nil)")
                    }

                    // Attempt fallback: If this was a DirectStream attempt and we haven't retried yet,
                    // retry with forced transcode (for Dolby Vision compatibility)
                    await self.retryWithTranscodeIfNeeded()

                    return
                }

                print("✅ [AVKit] Video track found, analyzing...")

                // Get track properties (these are synchronous)
                let trackID = track.trackID
                let isEnabled = track.isEnabled
                print("   Track ID: \(trackID), Enabled: \(isEnabled)")

                // Load format descriptions for HDR detection
                if let formatDescriptions = try? await track.load(.formatDescriptions) {
                    print("   Format descriptions: \(formatDescriptions.count)")

                    for description in formatDescriptions {
                        let formatDesc = description as! CMFormatDescription

                        // Log codec info
                        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
                        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
                        let codecString = String(format: "%c%c%c%c",
                            (mediaSubType >> 24) & 0xff,
                            (mediaSubType >> 16) & 0xff,
                            (mediaSubType >> 8) & 0xff,
                            mediaSubType & 0xff)
                        print("   Codec: \(codecString)")

                        // Check for HDR metadata
                        if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] {
                            print("   Format extensions: \(extensions.keys.joined(separator: ", "))")

                            // Check color primaries
                            if let colorPrimaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String {
                                let isHDR = colorPrimaries.contains("2020") || colorPrimaries.contains("2100")

                                if isHDR {
                                    print("🌈 [AVKit] HDR detected via color primaries: \(colorPrimaries)")
                                    hdrMode = .hdr

                                    // Check transfer function for Dolby Vision
                                    if let transferFunction = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String {
                                        print("   Transfer function: \(transferFunction)")
                                        if transferFunction.contains("SMPTE2084") || transferFunction.contains("PQ") {
                                            print("🌈 [AVKit] Dolby Vision/HDR10 (PQ) detected")
                                            hdrMode = .hdr
                                        } else if transferFunction.contains("HLG") || transferFunction.contains("ARIB") {
                                            print("🌈 [AVKit] HLG HDR detected")
                                            hdrMode = .hdr
                                        }
                                    }

                                    onHDRDetected?(true, nil, colorPrimaries)
                                } else {
                                    print("📺 [AVKit] SDR content (primaries: \(colorPrimaries))")
                                    hdrMode = .sdr
                                    onHDRDetected?(false, nil, nil)
                                }
                            }
                        }
                    }
                }
            } catch {
                print("❌ [AVKit] Error loading video tracks: \(error)")
            }
        }
    }

    // MARK: - Playback Control

    func play() {
        print("▶️ [AVKit] Play")
        player.play()
        isPaused = false
    }

    func pause() {
        print("⏸️ [AVKit] Pause")
        player.pause()
        isPaused = true
    }

    func seek(to seconds: Double) {
        print("⏩ [AVKit] Seek to: \(seconds)s")
        state = .seeking

        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time) { [weak self] finished in
            if finished {
                self?.state = self?.isPaused == true ? .paused : .playing
            }
        }
    }

    func setVolume(_ volume: Double) {
        print("🔊 [AVKit] Set volume: \(volume)")
        player.volume = Float(volume / 100.0)
        self.volume = volume
    }

    func shutdown() {
        print("🛑 [AVKit] Shutdown")

        // Stop progress tracking
        stopProgressTracking()

        // Report final progress, timeline, and stop transcode session
        Task {
            await reportProgress()
            await reportStopped()
            await reportTimelineStopped()
            await stopTranscodeSession()
        }

        player.pause()
        player.replaceCurrentItem(with: nil)

        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        cancellables.removeAll()

        state = .uninitialized
    }

    // MARK: - Progress Tracking

    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reportProgress()
                await self?.reportTimeline()
            }
        }
        print("📊 [AVKit] Progress and timeline tracking started")
    }

    private func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
        print("📊 [AVKit] Progress tracking stopped")
    }

    private func reportProgress() async {
        guard let ratingKey = ratingKey else { return }
        guard currentTime > 0, duration > 0 else { return }

        // Only report if progress changed significantly (more than 5 seconds)
        guard abs(currentTime - lastReportedProgress) > 5 else { return }

        lastReportedProgress = currentTime

        let progressPercent = Int((currentTime / duration) * 100)
        print("📊 [AVKit] Progress: \(Int(currentTime))s / \(Int(duration))s (\(progressPercent)%)")

        do {
            struct ProgressRequest: Encodable {
                let ratingKey: String
                let time: Int
                let duration: Int
                let state: String
            }
            let request = ProgressRequest(
                ratingKey: ratingKey,
                time: Int(currentTime * 1000),
                duration: Int(duration * 1000),
                state: isPaused ? "paused" : "playing"
            )
            let api = APIClient.shared
            let _: EmptyResponse = try await api.post("/api/plex/progress", body: request)
        } catch {
            print("⚠️ [AVKit] Failed to report progress: \(error)")
        }
    }

    private func reportStopped() async {
        guard let ratingKey = ratingKey else { return }
        guard duration > 0 else { return }

        do {
            struct ProgressRequest: Encodable {
                let ratingKey: String
                let time: Int
                let duration: Int
                let state: String
            }
            let request = ProgressRequest(
                ratingKey: ratingKey,
                time: Int(currentTime * 1000),
                duration: Int(duration * 1000),
                state: "stopped"
            )
            let api = APIClient.shared
            let _: EmptyResponse = try await api.post("/api/plex/progress", body: request)
            print("✅ [AVKit] Reported stopped state")
        } catch {
            print("⚠️ [AVKit] Failed to report stopped: \(error)")
        }
    }

    private func stopTranscodeSession() async {
        guard let sessionId = sessionId,
              let baseUrl = plexBaseUrl,
              let token = plexToken else {
            return
        }

        do {
            let stopUrl = "\(baseUrl)/video/:/transcode/universal/stop?session=\(sessionId)&X-Plex-Token=\(token)"
            guard let url = URL(string: stopUrl) else { return }

            print("🛑 [AVKit] Stopping transcode session: \(sessionId)")
            _ = try await URLSession.shared.data(from: url)
            print("✅ [AVKit] Transcode session stopped")
        } catch {
            print("⚠️ [AVKit] Failed to stop transcode session: \(error)")
        }
    }

    private func reportTimeline() async {
        guard let ratingKey = ratingKey,
              let baseUrl = plexBaseUrl,
              let token = plexToken else {
            return
        }

        guard duration > 0 else { return }

        let state = isPaused ? "paused" : "playing"
        let timeMs = Int(currentTime * 1000)
        let durationMs = Int(duration * 1000)

        // Build timeline URL
        var components = URLComponents(string: "\(baseUrl)/:/timeline")!
        var params: [URLQueryItem] = [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "time", value: String(timeMs)),
            URLQueryItem(name: "duration", value: String(durationMs)),
            URLQueryItem(name: "X-Plex-Token", value: token),
        ]

        // Add session ID if we have one (for transcode sessions)
        if let sessionId = sessionId {
            params.append(URLQueryItem(name: "X-Plex-Session-Identifier", value: sessionId))
        }

        // Add client info
        params.append(URLQueryItem(name: "X-Plex-Client-Identifier", value: getClientId()))
        params.append(URLQueryItem(name: "X-Plex-Product", value: "Flixor"))
        params.append(URLQueryItem(name: "X-Plex-Platform", value: "tvOS"))

        components.queryItems = params

        guard let url = components.url else { return }

        do {
            _ = try await URLSession.shared.data(from: url)
            print("📍 [AVKit] Timeline reported: \(state) at \(Int(currentTime))s")
        } catch {
            // Don't spam logs with timeline errors
        }
    }

    private func reportTimelineStopped() async {
        guard let ratingKey = ratingKey,
              let baseUrl = plexBaseUrl,
              let token = plexToken else {
            return
        }

        guard duration > 0 else { return }

        let timeMs = Int(currentTime * 1000)
        let durationMs = Int(duration * 1000)

        // Build timeline URL
        var components = URLComponents(string: "\(baseUrl)/:/timeline")!
        var params: [URLQueryItem] = [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "state", value: "stopped"),
            URLQueryItem(name: "time", value: String(timeMs)),
            URLQueryItem(name: "duration", value: String(durationMs)),
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: getClientId()),
            URLQueryItem(name: "X-Plex-Product", value: "Flixor"),
            URLQueryItem(name: "X-Plex-Platform", value: "tvOS"),
        ]

        if let sessionId = sessionId {
            params.append(URLQueryItem(name: "X-Plex-Session-Identifier", value: sessionId))
        }

        components.queryItems = params
        guard let url = components.url else { return }

        do {
            _ = try await URLSession.shared.data(from: url)
            print("📍 [AVKit] Timeline stopped reported")
        } catch {
            print("⚠️ [AVKit] Failed to report timeline stopped: \(error)")
        }
    }

    private func getClientId() -> String {
        let key = "plex_client_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }

    // MARK: - Event Handlers

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            if state != .playing {
                state = .playing
                onEvent?("playback-restart")

                // Check video presentation size when playback starts
                if let item = playerItem {
                    let presentationSize = item.presentationSize
                    if presentationSize.width > 0 && presentationSize.height > 0 {
                        print("📺 [AVKit] Video presentation size: \(Int(presentationSize.width))x\(Int(presentationSize.height))")
                    } else {
                        print("⚠️ [AVKit] Video presentation size is zero - no video frames detected")
                    }
                }
            }
            isPaused = false

        case .paused:
            state = .paused
            isPaused = true

        case .waitingToPlayAtSpecifiedRate:
            state = .buffering

        @unknown default:
            break
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            print("✅ [AVKit] Ready to play")

            // Log track information now that item is ready
            if let item = playerItem {
                print("📊 [AVKit] Player item tracks: \(item.tracks.count)")
                for (index, track) in item.tracks.enumerated() {
                    let mediaType = track.assetTrack?.mediaType.rawValue ?? "unknown"
                    print("   Track \(index): type=\(mediaType), enabled=\(track.isEnabled)")
                }

                // Log asset tracks
                let asset = item.asset
                Task {
                    let videoTracks = try? await asset.loadTracks(withMediaType: .video)
                    let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
                    print("📹 [AVKit] Asset has \(videoTracks?.count ?? 0) video track(s), \(audioTracks?.count ?? 0) audio track(s)")
                }
            }

            state = .ready
            onEvent?("file-loaded")

            // Auto-play now that item is ready
            print("▶️ [AVKit] Auto-playing...")
            player.play()

            // Start progress tracking
            startProgressTracking()

        case .failed:
            let error = playerItem?.error
            print("❌ [AVKit] Failed: \(error?.localizedDescription ?? "Unknown error")")
            state = .error(error ?? NSError(domain: "AVKit", code: -1))

        case .unknown:
            break

        @unknown default:
            break
        }
    }

    // MARK: - Fallback Logic

    private func retryWithTranscodeIfNeeded() async {
        // Check if we should retry
        guard !hasRetriedWithTranscode,
              let ratingKey = currentRatingKey,
              let streamingManager = streamingManager else {
            print("ℹ️ [AVKit] Not retrying (already retried or no context)")
            return
        }

        print("🔄 [AVKit] DirectStream failed - retrying with forced transcode (Dolby Vision fallback)...")
        hasRetriedWithTranscode = true

        // Stop current playback
        player.pause()
        player.replaceCurrentItem(with: nil)

        do {
            // Request new decision with DirectStream disabled
            // IMPORTANT: Preserve original resolution and quality during transcode
            let decision = try await streamingManager.getStreamingDecision(
                ratingKey: ratingKey,
                options: PlexStreamingManager.StreamingOptions(
                    streamingProtocol: "hls",
                    directPlay: false,
                    directStream: false,     // Force transcode
                    maxVideoBitrate: nil,    // No bitrate limit (original quality)
                    videoResolution: nil,    // Preserve original resolution
                    autoAdjustQuality: true
                )
            )

            print("✅ [AVKit] Retrying with transcode decision (original quality preserved)")
            await loadWithDecision(decision)
        } catch {
            print("❌ [AVKit] Retry failed: \(error)")
            state = .error(error)
        }
    }

    // MARK: - URL Parsing

    private func parsePlexRatingKey(_ url: String) -> String? {
        // Extract ratingKey from URL
        // URL format: http://backend:3001/plex/library/metadata/13624

        guard let urlComponents = URLComponents(string: url) else { return nil }

        // Extract ratingKey
        let pathComponents = urlComponents.path.split(separator: "/")
        guard let metadataIndex = pathComponents.firstIndex(of: "metadata"),
              metadataIndex + 1 < pathComponents.count else {
            return nil
        }
        let ratingKey = String(pathComponents[metadataIndex + 1])

        print("🔍 [AVKit] Extracted ratingKey: \(ratingKey)")
        return ratingKey
    }

    // MARK: - Deinitialization

    nonisolated deinit {
        print("🗑️ [AVKit] AVKitPlayerController deinitialized")
    }
}

// MARK: - Helper Types

struct EmptyResponse: Codable {}
