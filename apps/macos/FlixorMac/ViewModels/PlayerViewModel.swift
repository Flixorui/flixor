//
//  PlayerViewModel.swift
//  FlixorMac
//
//  Video player view model with AVPlayer integration
//

import Foundation
import AVKit
import SwiftUI
import Combine
import MediaPlayer

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

@MainActor
class PlayerViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = true
    @Published var isChangingQuality = false
    @Published var error: String?
    @Published var volume: Float = 1.0
    @Published var isMuted = false
    @Published var isFullScreen = false
    @Published var playbackSpeed: Float = 1.0

    // Stream info
    @Published var streamURL: URL?
    @Published var selectedQuality: PlaybackQuality = .original
    @Published var isTranscoding: Bool = false  // True when using transcoding (non-original quality)

    // Source media info
    @Published var sourceWidth: Int? = nil
    @Published var sourceHeight: Int? = nil

    // Computed: Available qualities filtered by source resolution
    var availableQualities: [PlaybackQuality] {
        return PlaybackQuality.availableQualities(sourceWidth: sourceWidth)
    }

    // MPV Track info (audio/subtitle)
    @Published var availableAudioTracks: [MPVTrack] = []
    @Published var availableSubtitleTracks: [MPVTrack] = []
    @Published var currentAudioTrackId: Int? = nil
    @Published var currentSubtitleTrackId: Int? = nil

    // Subtitle preference (persisted)
    private var subtitlesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "playerSubtitlesEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "playerSubtitlesEnabled") }
    }

    // Markers (intro/credits) - no high-frequency updates
    @Published var markers: [PlayerMarker] = []
    @Published var currentMarker: PlayerMarker? = nil

    // Next episode & season episodes
    @Published var nextEpisode: EpisodeMetadata? = nil
    @Published var seasonEpisodes: [EpisodeMetadata] = []
    @Published var nextEpisodeCountdown: Int? = nil

    // Playback metadata
    let item: MediaItem
    private(set) var player: AVPlayer?
    @Published var mpvController: MPVPlayerController?
    @Published var thumbnailGenerator: MPVThumbnailGenerator?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var kvoCancellables = Set<AnyCancellable>()
    private let api = APIClient.shared

    // Backend selection
    private var playerBackend: PlayerBackend {
        UserDefaults.standard.playerBackend
    }

    // Progress tracking
    private var progressTimer: Timer?
    private var lastReportedProgress: TimeInterval = 0
    private var initialSeekApplied = false
    private var serverResumeSeconds: TimeInterval?

    // MPV error detection
    private var fileStartTime: Date?
    private var directPlayRetryCount: Int = 0
    private var maxDirectPlayRetries: Int = 2

    // Countdown timer for next episode
    private var countdownTimer: Timer?

    // Session tracking for cleanup
    private var sessionId: String?
    private var plexBaseUrl: String?
    private var plexToken: String?
    private var currentURLIsHLS: Bool = false

    // Trakt scrobbling
    private let scrobbler = TraktScrobbler.shared
    private var scrobbleStarted = false

    // Navigation callback for next episode
    var onPlayNext: ((MediaItem) -> Void)?

    // Display sleep prevention
    private var displaySleepAssertion: NSObjectProtocol?

    init(item: MediaItem) {
        self.item = item
        setupPlayer()
        setupNowPlayingInfo()
    }

    deinit {
        // Cleanup synchronously in deinit
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        progressTimer?.invalidate()
        progressTimer = nil
        player?.pause()
        player = nil
        cancellables.removeAll()

        // Clean up display sleep assertion
        #if os(macOS)
        if let activity = displaySleepAssertion {
            ProcessInfo.processInfo.endActivity(activity)
            displaySleepAssertion = nil
        }
        #endif

        print("🧹 [Player] Cleaned up")
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        Task {
            await fetchServerResumeOffset()

            // Initialize backend based on user preference
            switch playerBackend {
            case .avplayer:
                print("🎬 [Player] Using AVPlayer backend")
                await loadStreamURL()
            case .mpv:
                print("🎬 [Player] Using MPV backend")
                setupMPVController()
                await loadStreamURL()
            }
        }
    }

    private func setupMPVController() {
        let controller = MPVPlayerController()

        // Setup property change callback
        controller.onPropertyChange = { [weak self] property, value in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch property {
                case "time-pos":
                    if let time = value as? Double {
                        self.currentTime = time
                        // Check for markers whenever time updates (matches web/mobile frequency)
                        self.updateCurrentMarker()
                        // Update next episode countdown
                        self.updateNextEpisodeCountdown()
                    }
                case "duration":
                    if let dur = value as? Double {
                        self.duration = dur
                        // Apply initial seek after duration is available (for MPV)
                        self.applyInitialSeekIfNeeded()
                    }
                case "pause":
                    if let paused = value as? Bool {
                        self.isPlaying = !paused
                    }
                case "volume":
                    if let vol = value as? Double {
                        self.volume = Float(vol / 100.0)
                    }
                case "mute":
                    if let muted = value as? Bool {
                        self.isMuted = muted
                    }
                default:
                    break
                }
            }
        }

        // Setup event callback
        controller.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("🎯 [Player] MPV event: \(event)")
                switch event {
                case "file-started":
                    print("📺 [Player] MPV file started")
                    self.fileStartTime = Date()
                case "file-loaded":
                    print("✅ [Player] MPV file loaded")
                    self.isLoading = false
                    self.directPlayRetryCount = 0  // Reset counter on successful load
                    self.applyInitialSeekIfNeeded()
                    // Load available tracks
                    self.loadTracks()
                    // Notify thumbnail generator
                    if let path: String = self.mpvController?.getProperty("path", type: .string) {
                        self.thumbnailGenerator?.onVideoLoaded(url: path)
                    }
                case "playback-restart":
                    print("▶️ [Player] MPV playback started")
                    self.isPlaying = true
                    self.isLoading = false
                    self.enableDisplaySleep()
                    // Start Trakt scrobbling
                    self.startTraktScrobble()
                case "file-ended":
                    // Check if file-ended happened too quickly after file-started (< 3 seconds)
                    // This indicates a loading error, not actual playback completion
                    if let startTime = self.fileStartTime {
                        let timeSinceStart = Date().timeIntervalSince(startTime)
                        if timeSinceStart < 3.0 {
                            print("❌ [Player] MPV playback failed (file-ended after \(String(format: "%.1f", timeSinceStart))s) - likely connection error")
                            // If direct play URL failed (404, expired token, etc.), try to refresh it
                            if self.currentURLIsHLS == false {
                                if self.directPlayRetryCount < self.maxDirectPlayRetries {
                                    self.directPlayRetryCount += 1
                                    print("🔄 [Player] Attempting to refresh direct play URL (attempt \(self.directPlayRetryCount)/\(self.maxDirectPlayRetries))")
                                    self.fileStartTime = nil
                                    Task {
                                        let success = await self.retryDirectPlay()
                                        if !success {
                                            print("↩️ [Player] Direct play retry failed; falling back to HLS")
                                            self.directPlayRetryCount = 0
                                            await self.retryWithHLS()
                                        }
                                    }
                                } else {
                                    print("⚠️ [Player] Max direct play retries (\(self.maxDirectPlayRetries)) reached; falling back to HLS")
                                    self.directPlayRetryCount = 0
                                    self.fileStartTime = nil
                                    Task {
                                        await self.retryWithHLS()
                                    }
                                }
                            } else {
                                // Already using HLS, can't retry further
                                self.error = "Failed to load video. Please check your network connection and try again."
                                self.isLoading = false
                                self.isPlaying = false
                            }
                            return
                        }
                    }
                    print("✅ [Player] MPV playback finished")
                    self.directPlayRetryCount = 0  // Reset counter on successful playback
                    self.handlePlaybackEnd()
                default:
                    print("ℹ️ [Player] MPV event (unhandled): \(event)")
                    break
                }
            }
        }

        self.mpvController = controller

        // Initialize thumbnail generator
        let generator = MPVThumbnailGenerator(mpvController: controller)
        self.thumbnailGenerator = generator

        print("✅ [Player] MPV controller initialized with thumbnail support")
    }

    private func fetchServerResumeOffset() async {
        // Try to get latest playstate from backend metadata if not included
        let rk = item.id.replacingOccurrences(of: "plex:", with: "")
        guard !rk.isEmpty else { return }
        do {
            struct Meta: Decodable { let viewOffset: Int? }
            let meta: Meta = try await api.get("/api/plex/metadata/\(rk)")
            if let ms = meta.viewOffset, ms > 2000 {
                serverResumeSeconds = TimeInterval(ms) / 1000.0
                print("🕑 [Player] Server resume offset: \(ms) ms")
            }
        } catch {
            print("⚠️ [Player] Failed to fetch server resume offset: \(error)")
        }
    }

    private func fetchMarkers(ratingKey: String) async {
        print("🎯 [Player] fetchMarkers() CALLED for ratingKey: \(ratingKey)")
        do {
            print("🌐 [Player] Calling api.getPlexMarkers...")
            let plexMarkers = try await api.getPlexMarkers(ratingKey: ratingKey)
            print("✅ [Player] Got \(plexMarkers.count) raw markers from API")
            // Map to PlayerMarker (ensure id and ms fields present)
            let mapped: [PlayerMarker] = plexMarkers.compactMap { m in
                guard let type = m.type?.lowercased(),
                      let s = m.startTimeOffset, let e = m.endTimeOffset else { return nil }
                // Only care about intro/credits
                guard type == "intro" || type == "credits" else { return nil }
                let id = m.id ?? "\(type)-\(s)-\(e)"
                return PlayerMarker(id: id, type: type, startTimeOffset: s, endTimeOffset: e)
            }
            self.markers = mapped
            print("🎬 [Player] Markers found: \(mapped.count) - \(mapped.map { "\($0.type): \($0.startTimeOffset)-\($0.endTimeOffset)" })")
        } catch {
            print("⚠️ [Player] Failed to fetch markers: \(error)")
            self.markers = []
        }
    }

    private func fetchNextEpisode(parentRatingKey: String, currentRatingKey: String) async {
        do {
            // Fetch all episodes in the season
            struct EpisodeResponse: Decodable {
                let Metadata: [EpisodeMetadata]?
            }
            let response: EpisodeResponse = try await api.get("/api/plex/dir/library/metadata/\(parentRatingKey)/children")
            let episodes = response.Metadata ?? []
            self.seasonEpisodes = episodes

            // Find next episode
            if let currentIndex = episodes.firstIndex(where: { $0.ratingKey == currentRatingKey }),
               currentIndex + 1 < episodes.count {
                self.nextEpisode = episodes[currentIndex + 1]
                print("📺 [Player] Next episode: \(self.nextEpisode?.title ?? "nil")")
            } else {
                self.nextEpisode = nil
                print("📺 [Player] No next episode")
            }
        } catch {
            print("⚠️ [Player] Failed to fetch next episode: \(error)")
            self.nextEpisode = nil
        }
    }

    private func updateCurrentMarker() {
        guard !markers.isEmpty else {
            if currentMarker != nil {
                print("⚠️ [Player] Clearing marker - no markers available")
                currentMarker = nil
            }
            return
        }

        let currentMs = Int(currentTime * 1000)

        // Debug: Log periodically what we're checking
        if Int(currentTime).isMultiple(of: 30) {
            print("🔍 [Player] Checking markers at \(currentMs)ms against \(markers.count) markers:")
            for marker in markers {
                print("   - \(marker.type): \(marker.startTimeOffset)-\(marker.endTimeOffset)ms")
            }
        }

        let newMarker = markers.first { marker in
            (marker.type == "intro" || marker.type == "credits") &&
            currentMs >= marker.startTimeOffset && currentMs <= marker.endTimeOffset
        }

        // Only update if changed to avoid unnecessary UI updates
        if newMarker?.id != currentMarker?.id {
            if let marker = newMarker {
                print("🎬 [Player] ✅ Marker ACTIVE: \(marker.type) at \(currentMs)ms (range: \(marker.startTimeOffset)-\(marker.endTimeOffset))")
            } else if currentMarker != nil {
                print("🎬 [Player] ❌ Marker ended at \(currentMs)ms")
            }
            currentMarker = newMarker
        }
    }

    private func updateNextEpisodeCountdown() {
        guard item.type == "episode", nextEpisode != nil, duration > 0 else {
            if nextEpisodeCountdown != nil {
                nextEpisodeCountdown = nil
            }
            return
        }

        // Start countdown at credits marker or last 30s
        let creditsMarker = markers.first { $0.type == "credits" }
        let triggerStart = creditsMarker != nil ? TimeInterval(creditsMarker!.startTimeOffset) / 1000.0 : max(0, duration - 30)

        if currentTime >= triggerStart {
            let remaining = max(0, Int(ceil(duration - currentTime)))
            if nextEpisodeCountdown != remaining {
                nextEpisodeCountdown = remaining
            }
        } else {
            if nextEpisodeCountdown != nil {
                nextEpisodeCountdown = nil
            }
        }
    }

    func skipMarker() {
        guard let marker = currentMarker else { return }
        let skipToTime = TimeInterval(marker.endTimeOffset) / 1000.0 + 1.0
        seek(to: skipToTime)
        print("⏭️ [Player] Skipped \(marker.type) to \(skipToTime)s")
    }

    private func loadStreamURL() async {
        isLoading = true
        error = nil
        directPlayRetryCount = 0  // Reset retry counter for new stream

        do {
            // Validate this is a Plex item
            guard item.id.hasPrefix("plex:") else {
                throw NSError(
                    domain: "PlayerError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot play non-Plex content. Item must be in your Plex library.\n\nID: \(item.id)"]
                )
            }

            // Validate item type - only movies, episodes, and clips have playable media
            guard ["movie", "episode", "clip"].contains(item.type) else {
                throw NSError(
                    domain: "PlayerError",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot play \(item.type) type. Only movies and episodes can be played.\n\nPlease select an episode from the show."]
                )
            }

            // Extract ratingKey from item.id
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")

            guard !ratingKey.isEmpty else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid item ID: \(item.id)"])
            }

            print("📺 [Player] Fetching stream URL for ratingKey: \(ratingKey)")
            print("📺 [Player] Item title: \(item.title) (type: \(item.type))")

            // Fetch markers (intro/credits)
            print("📺 [Player] About to call fetchMarkers...")
            await fetchMarkers(ratingKey: ratingKey)
            print("📺 [Player] fetchMarkers returned, markers count: \(markers.count)")

            // Fetch next episode if this is an episode - get parentRatingKey from metadata
            if item.type == "episode" {
                do {
                    struct EpMetadata: Decodable {
                        let parentRatingKey: String?
                    }
                    let meta: EpMetadata = try await api.get("/api/plex/metadata/\(ratingKey)")
                    if let parentKey = meta.parentRatingKey {
                        await fetchNextEpisode(parentRatingKey: parentKey, currentRatingKey: ratingKey)
                    }
                } catch {
                    print("⚠️ [Player] Failed to get parent rating key: \(error)")
                }
            }

            // Get Plex server connection details (like mobile app)
            let servers = try await api.getPlexServers()
            guard let activeServer = servers.first(where: { $0.isActive == true }) else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active Plex server configured"])
            }

            print("📺 [Player] Using server: \(activeServer.name)")

            let connectionsResponse = try await api.getPlexConnections(serverId: activeServer.id)
            let connections = connectionsResponse.connections

            // Prefer local connection, fall back to first available
            guard let selectedConnection = connections.first(where: { $0.local == true }) ?? connections.first else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Plex server connection available"])
            }

            let baseUrl = selectedConnection.uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            print("📺 [Player] Server URL: \(baseUrl)")

            // Store for cleanup
            self.plexBaseUrl = baseUrl

            // Get Plex access token
            let authServers = try await api.getPlexAuthServers()
            guard let serverWithToken = authServers.first(where: {
                $0.clientIdentifier == activeServer.id ||
                $0.clientIdentifier == activeServer.machineIdentifier
            }), let token = serverWithToken.token as String? else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get Plex access token"])
            }

            // Store for cleanup
            self.plexToken = token

            print("📺 [Player] Got access token")

            // First try: Direct Play via Plex part URL if available (only if quality is Original)
            struct MetaMedia: Decodable {
                struct Part: Decodable { let key: String? }
                let Part: [Part]?
                let container: String?
                let videoCodec: String?
                let audioCodec: String?
                let width: Int?
                let height: Int?
            }
            struct MetaResponse: Decodable { let Media: [MetaMedia]? }
            var directURL: URL? = nil

            // Always fetch metadata to get source resolution (for quality filtering)
            do {
                // Bypass cache to get fresh part keys (they can change when Plex rescans)
                let meta: MetaResponse = try await api.get("/api/plex/metadata/\(ratingKey)", bypassCache: true)
                // Use mediaIndex from item if specified, otherwise use first version
                let mediaArray = meta.Media ?? []
                let selectedIndex = item.mediaIndex ?? 0
                let m = selectedIndex < mediaArray.count ? mediaArray[selectedIndex] : mediaArray.first
                print("📺 [Player] Using media version \(selectedIndex + 1) of \(mediaArray.count)")

                // Store source resolution for quality filtering
                if let width = m?.width {
                    self.sourceWidth = width
                    print("📺 [Player] Source resolution: \(width)x\(m?.height ?? 0)")
                }
                if let height = m?.height {
                    self.sourceHeight = height
                }

                // Skip Direct Play if user selected a specific quality (transcoding required)
                if selectedQuality == .original {
                    let container = (m?.container ?? "").lowercased()
                    let vcodec = (m?.videoCodec ?? "").lowercased()
                    let acodec = (m?.audioCodec ?? "").lowercased()

                    // MPV can handle MKV/HEVC/TrueHD directly, AVPlayer cannot
                    let allowDirect: Bool
                    if playerBackend == .mpv {
                        // MPV: Allow all formats, it's very capable
                        allowDirect = true
                        print("✅ [Player] MPV backend: Allowing direct play for all codecs")
                    } else {
                        // AVPlayer: Gate direct play for incompatible formats
                        let unsafeContainer = container.contains("mkv") || container.contains("mka")
                        let unsafeVideo = vcodec.contains("hevc") || vcodec.contains("dvh") || vcodec.contains("dvhe")
                        let unsafeAudio = acodec.contains("truehd") || acodec.contains("eac3")
                        allowDirect = !(unsafeContainer || unsafeVideo || unsafeAudio)
                        if !allowDirect {
                            print("🚫 [Player] AVPlayer: Skipping Direct Play due to incompatible container/codec: cont=\(container), v=\(vcodec), a=\(acodec)")
                        }
                    }

                    if allowDirect, let key = m?.Part?.first?.key, !key.isEmpty {
                        let direct = "\(baseUrl)\(key)?X-Plex-Token=\(token)"
                        directURL = URL(string: direct)
                        if directURL != nil { print("🎯 [Player] Attempting Direct Play: \(direct)") }
                    }
                } else {
                    print("🎚️ [Player] Quality set to \(selectedQuality.rawValue) - transcoding required, skipping Direct Play")
                }
            } catch {
                print("⚠️ [Player] Could not fetch metadata: \(error)")
            }

            var startURL: URL
            var isDirectPlay = false
            if let d = directURL {
                self.streamURL = d
                startURL = d
                isDirectPlay = true
            } else {
                // Fallback: backend HLS endpoint with selected quality
                print("📺 [Player] Requesting stream URL from backend (HLS, quality: \(selectedQuality.rawValue))")
                struct StreamResponse: Codable { let url: String }
                let response: StreamResponse = try await api.get(
                    "/api/plex/stream/\(ratingKey)",
                    queryItems: buildTranscodeQueryItems(quality: selectedQuality)
                )
                print("📺 [Player] Received stream URL: \(response.url)")
                guard let u = URL(string: response.url) else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid stream URL"])
                }
                startURL = u
                self.currentURLIsHLS = true
                self.isTranscoding = selectedQuality.requiresTranscoding
            }

            // Handle transcoding URLs
            // DASH: Use start.mpd URL directly (like web player)
            // Direct Play: Use URL as-is
            if !isDirectPlay && startURL.absoluteString.contains("start.mpd") {
                // DASH transcode: Use start.mpd directly (MPV/DASH.js handles it)
                print("📺 [Player] Using DASH transcode URL directly")

                // Extract session ID for cleanup
                if let sessionParam = URLComponents(string: startURL.absoluteString)?.queryItems?.first(where: { $0.name == "session" })?.value {
                    self.sessionId = sessionParam
                }

                self.streamURL = startURL
                print("✅ [Player] DASH URL: \(startURL.absoluteString)")

            } else {
                // Direct Play
                self.streamURL = startURL
                print("✅ [Player] Stream URL ready: \(startURL.absoluteString)")
            }

            // Initialize player based on backend
            guard let finalURL = self.streamURL else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Stream URL not set"])
            }

            switch playerBackend {
            case .avplayer:
                // Configure asset with better buffering
                let asset = AVURLAsset(url: finalURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
                let playerItem = AVPlayerItem(asset: asset)
                // Buffering preferences
                if currentURLIsHLS || startURL.absoluteString.contains("m3u8") {
                    playerItem.preferredForwardBufferDuration = 45 // HLS: buffer more
                } else {
                    playerItem.preferredForwardBufferDuration = 10 // Direct play: lighter buffer
                }
                playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                playerItem.preferredPeakBitRate = 0

                // Add error observer
                playerItem.publisher(for: \.error)
                    .sink { [weak self] error in
                        if let error = error {
                            print("❌ [Player] AVPlayerItem error: \(error.localizedDescription)")
                            Task { @MainActor [weak self] in
                                self?.error = "Playback error: \(error.localizedDescription)"
                                self?.isLoading = false
                            }
                        }
                    }
                    .store(in: &cancellables)

                self.player = AVPlayer(playerItem: playerItem)
                self.player?.automaticallyWaitsToMinimizeStalling = true
                self.player?.actionAtItemEnd = .pause
                self.player?.allowsExternalPlayback = false

                // Setup observers
                setupTimeObserver()
                setupPlayerObservers(playerItem: playerItem)
                setupPlayerStateObservers()

                // Auto-play immediately with current speed
                self.player?.rate = self.playbackSpeed
                self.isPlaying = true

                // Start progress tracking and prevent display sleep
                startProgressTracking()
                enableDisplaySleep()

            case .mpv:
                // Load file in MPV
                guard let mpvController = self.mpvController else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller not initialized"])
                }

                print("🎬 [MPV] Loading file: \(finalURL.absoluteString)")
                mpvController.loadFile(finalURL.absoluteString)

                // MPV will handle playback automatically
                // Property and event callbacks will update our @Published properties

                // Start progress tracking
                startProgressTracking()
            }

        } catch {
            print("❌ [Player] Failed to load stream: \(error)")

            // If transcoding failed, reset to Original quality
            if selectedQuality != .original && isTranscoding {
                print("⚠️ [Player] Transcoding failed - resetting to Original quality")
                selectedQuality = .original
                isTranscoding = false

                // Retry with Direct Play
                print("🔄 [Player] Retrying with Direct Play...")
                self.error = nil
                await loadStreamURL()
                return
            }

            self.error = "Failed to load video stream: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    // MARK: - Player Observers

    private func setupTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime = time.seconds

                // Update duration if available
                if let duration = player.currentItem?.duration.seconds, !duration.isNaN {
                    self.duration = duration
                }

                // Check for markers every 0.5s (matches web/mobile frequency)
                self.updateCurrentMarker()
                // Update next episode countdown
                self.updateNextEpisodeCountdown()
            }
        }
    }

    private func setupPlayerObservers(playerItem: AVPlayerItem) {
        // Observe status
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch status {
                    case .readyToPlay:
                        print("✅ [Player] Ready to play")
                        self.isLoading = false
                        self.directPlayRetryCount = 0  // Reset counter on successful load
                        // Apply initial resume seek once when ready
                        self.applyInitialSeekIfNeeded()
                        // Start Trakt scrobbling
                        self.startTraktScrobble()
                    case .failed:
                        print("❌ [Player] Failed: \(playerItem.error?.localizedDescription ?? "Unknown error")")
                        if self.currentURLIsHLS == false {
                            if self.directPlayRetryCount < self.maxDirectPlayRetries {
                                self.directPlayRetryCount += 1
                                print("🔄 [Player] Attempting to refresh direct play URL (attempt \(self.directPlayRetryCount)/\(self.maxDirectPlayRetries))")
                                let success = await self.retryDirectPlay()
                                if !success {
                                    print("↩️ [Player] Direct play retry failed; falling back to HLS")
                                    self.directPlayRetryCount = 0
                                    await self.reloadAsHLSFallback()
                                }
                            } else {
                                print("⚠️ [Player] Max direct play retries (\(self.maxDirectPlayRetries)) reached; falling back to HLS")
                                self.directPlayRetryCount = 0
                                await self.reloadAsHLSFallback()
                            }
                        } else {
                            self.error = playerItem.error?.localizedDescription ?? "Playback failed"
                            self.isLoading = false
                        }
                    case .unknown:
                        print("⏳ [Player] Status unknown")
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)

        // Observe playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("✅ [Player] Playback finished")
                    self.handlePlaybackEnd()
                }
            }
            .store(in: &cancellables)

        // Observe stalls
        NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: playerItem)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("⚠️ [Player] Playback stalled")
                    self.isLoading = true
                    if let it = self.player?.currentItem {
                        it.preferredForwardBufferDuration = max(30, it.preferredForwardBufferDuration)
                    }
                    // Nudge playback
                    self.player?.pause()
                    self.player?.play()
                }
            }
            .store(in: &cancellables)

        // Observe buffering-related properties
        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] keepUp in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if keepUp {
                        self.isLoading = false
                    }
                }
            }
            .store(in: &cancellables)

        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .sink { [weak self] empty in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if empty {
                        self.isLoading = true
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func setupPlayerStateObservers() {
        guard let player = player else { return }
        // Track timeControlStatus to reflect buffering/playing state
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch status {
                    case .waitingToPlayAtSpecifiedRate:
                        self.isLoading = true
                    case .playing, .paused:
                        self.isLoading = false
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &kvoCancellables)
    }

    private func reloadAsHLSFallback() async {
        // Build HLS URL and replace current item
        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            struct StreamResponse: Codable { let url: String }
            let response: StreamResponse = try await api.get(
                "/api/plex/stream/\(ratingKey)",
                queryItems: buildTranscodeQueryItems(quality: selectedQuality)
            )
            guard let url = URL(string: response.url) else {
                throw NSError(domain: "PlayerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid HLS URL"])
            }
            self.streamURL = url
            self.currentURLIsHLS = true
            self.isTranscoding = selectedQuality.requiresTranscoding

            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 45
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            item.preferredPeakBitRate = 0

            if self.player == nil { self.player = AVPlayer(playerItem: item) } else { self.player?.replaceCurrentItem(with: item) }
            self.player?.automaticallyWaitsToMinimizeStalling = true
            self.player?.allowsExternalPlayback = false

            setupPlayerObservers(playerItem: item)
            setupPlayerStateObservers()
            self.player?.rate = self.playbackSpeed
            self.isPlaying = true
            self.isLoading = false
        } catch {
            print("❌ [Player] HLS fallback failed: \(error)")
            self.error = "Playback failed: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    private func applyInitialSeekIfNeeded() {
        guard !initialSeekApplied else { return }
        guard duration > 0 else {
            // Duration not available yet, will be called again when duration is set
            return
        }

        initialSeekApplied = true

        let ms = item.viewOffset ?? 0
        var seconds = TimeInterval(ms) / 1000.0
        if (seconds <= 2), let s = serverResumeSeconds { seconds = s }

        // If viewOffset is at or past the duration, definitely restart from beginning
        if seconds >= duration {
            print("🔄 [Player] Content fully watched (offset=\(Int(seconds))s >= duration=\(Int(duration))s) - restarting from beginning")
            seconds = 0
        }
        // If content is almost finished (within last 30s or >95% watched), restart from beginning
        else if duration > 0 {
            let progress = seconds / duration
            let secondsRemaining = duration - seconds
            if progress > 0.95 || secondsRemaining < 30 {
                print("🔄 [Player] Content almost finished (progress: \(Int(progress * 100))%, \(Int(secondsRemaining))s remaining) - restarting from beginning")
                seconds = 0
            }
        }

        // Only seek if we have a meaningful offset
        if seconds > 2 {
            seek(to: seconds)
            print("⏩ [Player] Resuming playback at \(Int(seconds))s")
        } else if seconds == 0 && (item.viewOffset ?? 0) > 0 {
            // Explicitly seeking to 0 after restarting fully watched content
            seek(to: 0)
            print("▶️ [Player] Starting from beginning")
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        let progress = duration > 0 ? (currentTime / duration) * 100 : 0

        switch playerBackend {
        case .avplayer:
            guard let player = player else { return }
            if isPlaying {
                player.pause()
                isPlaying = false
                stopProgressTracking()
                disableDisplaySleep()
                // Pause Trakt scrobble
                Task { await scrobbler.pauseScrobble(progress: progress) }
            } else {
                player.rate = playbackSpeed // Restore playback speed
                isPlaying = true
                startProgressTracking()
                enableDisplaySleep()
                // Resume Trakt scrobble
                Task { await scrobbler.resumeScrobble(progress: progress) }
            }
        case .mpv:
            guard let mpv = mpvController else { return }
            if isPlaying {
                mpv.pause()
                isPlaying = false
                stopProgressTracking()
                disableDisplaySleep()
                // Pause Trakt scrobble
                Task { await scrobbler.pauseScrobble(progress: progress) }
            } else {
                mpv.play()
                isPlaying = true
                startProgressTracking()
                enableDisplaySleep()
                // Resume Trakt scrobble
                Task { await scrobbler.resumeScrobble(progress: progress) }
            }
        }

        // Update Now Playing info
        updateNowPlayingInfo()
    }

    func seek(to time: TimeInterval) {
        switch playerBackend {
        case .avplayer:
            guard let player = player else { return }
            let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player.seek(to: cmTime) { [weak self] finished in
                if finished {
                    print("✅ [Player] Seeked to \(time)s")
                    Task { @MainActor [weak self] in
                        await self?.reportProgress()
                        self?.updateNowPlayingInfo()
                    }
                }
            }
        case .mpv:
            guard let mpv = mpvController else { return }
            mpv.seek(to: time)
            print("✅ [MPV] Seeked to \(time)s")
            Task { @MainActor [weak self] in
                await self?.reportProgress()
                self?.updateNowPlayingInfo()
            }
        }
    }

    func skip(seconds: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        switch playerBackend {
        case .avplayer:
            player?.volume = isMuted ? 0 : volume
        case .mpv:
            mpvController?.setVolume(Double(volume * 100)) // MPV uses 0-100 scale
        }
    }

    func toggleMute() {
        isMuted.toggle()
        switch playerBackend {
        case .avplayer:
            player?.volume = isMuted ? 0 : volume
        case .mpv:
            mpvController?.setMute(isMuted)
        }
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        switch playerBackend {
        case .avplayer:
            player?.rate = isPlaying ? speed : 0
        case .mpv:
            mpvController?.setSpeed(Double(speed))
        }
        print("⚡ [Player] Playback speed set to \(speed)x")
    }

    func changeQuality(_ newQuality: PlaybackQuality) {
        print("🎚️ [Player] Changing quality: \(selectedQuality.rawValue) → \(newQuality.rawValue)")

        // No change needed
        guard newQuality != selectedQuality else {
            print("   Already at \(newQuality.rawValue)")
            return
        }

        isChangingQuality = true

        // Check if we're switching TO a transcoded quality (not FROM)
        let switchingToTranscode = newQuality.requiresTranscoding && !selectedQuality.requiresTranscoding
        let savedTime = currentTime > 2 ? currentTime : 0

        selectedQuality = newQuality
        isTranscoding = newQuality.requiresTranscoding

        Task {
            defer {
                // Always reset changing quality flag
                isChangingQuality = false
            }

            // Stop current playback
            stopProgressTracking()

            // Reload stream with new quality
            await loadStreamURL()

            // DASH supports seeking to any position (unlike HLS)
            // MPV and DASH.js handle adaptive segment loading automatically
            if savedTime > 2 {
                // Wait for stream to initialize
                let waitTime: UInt64 = isTranscoding ? 3_000_000_000 : 500_000_000 // 3s for DASH, 0.5s for Direct Play
                try? await Task.sleep(nanoseconds: waitTime)

                seek(to: savedTime)
                print("⏩ [Player] Restored position: \(Int(savedTime))s")
            }
        }
    }

    // MARK: - Stream URL Building

    /// Build query items for DASH transcoding based on selected quality
    /// Backend expects "quality" and "resolution" params, which it converts to Plex params
    private func buildTranscodeQueryItems(quality: PlaybackQuality) -> [URLQueryItem] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "protocol", value: "dash"),  // Use DASH only (better seek support than HLS)
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "0")
        ]

        // Backend expects "quality" (not "maxVideoBitrate") and "resolution" (not "videoResolution")
        // The backend converts these to the proper Plex API params
        if let bitrate = quality.bitrate {
            queryItems.append(URLQueryItem(name: "quality", value: String(bitrate)))
        }

        if let resolution = quality.resolution {
            queryItems.append(URLQueryItem(name: "resolution", value: resolution))
        }

        return queryItems
    }

    // MARK: - Track Management (MPV only)

    /// Load available audio and subtitle tracks (MPV only)
    func loadTracks() {
        guard playerBackend == .mpv,
              let mpv = mpvController else {
            return
        }

        availableAudioTracks = mpv.getAudioTracks()
        availableSubtitleTracks = mpv.getSubtitleTracks()
        currentAudioTrackId = mpv.getCurrentAudioTrack()

        print("🎵 [Player] Loaded \(availableAudioTracks.count) audio tracks")
        print("💬 [Player] Loaded \(availableSubtitleTracks.count) subtitle tracks")

        // Apply user's subtitle preference
        if subtitlesEnabled {
            // User prefers subtitles on - keep MPV's auto-selected track
            currentSubtitleTrackId = mpv.getCurrentSubtitleTrack()
            print("💬 [Player] Subtitles enabled by preference, track: \(currentSubtitleTrackId ?? -1)")
        } else {
            // User prefers subtitles off - disable them
            mpv.disableSubtitles()
            currentSubtitleTrackId = nil
            print("💬 [Player] Subtitles disabled by preference")
        }
    }

    /// Set audio track (MPV only)
    func setAudioTrack(_ trackId: Int) {
        guard playerBackend == .mpv,
              let mpv = mpvController else {
            return
        }

        mpv.setAudioTrack(trackId)
        currentAudioTrackId = trackId
    }

    /// Set subtitle track (MPV only)
    func setSubtitleTrack(_ trackId: Int) {
        guard playerBackend == .mpv,
              let mpv = mpvController else {
            return
        }

        mpv.setSubtitleTrack(trackId)
        currentSubtitleTrackId = trackId
        subtitlesEnabled = true  // Remember that user wants subtitles
        print("💬 [Player] Subtitle track set to \(trackId), preference saved: enabled")
    }

    /// Disable subtitles (MPV only)
    func disableSubtitles() {
        guard playerBackend == .mpv,
              let mpv = mpvController else {
            return
        }

        mpv.disableSubtitles()
        currentSubtitleTrackId = nil
        subtitlesEnabled = false  // Remember that user wants subtitles off
        print("💬 [Player] Subtitles disabled, preference saved: disabled")
    }

    // MARK: - Progress Tracking

    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reportProgress()
                self?.updateTraktProgress()
            }
        }
    }

    private func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Trakt Scrobbling

    private func startTraktScrobble() {
        guard !scrobbleStarted else { return }
        scrobbleStarted = true

        let initialProgress = duration > 0 ? (currentTime / duration) * 100 : 0
        Task {
            await scrobbler.startScrobble(for: item, initialProgress: initialProgress)
        }
    }

    private func updateTraktProgress() {
        guard duration > 0 else { return }
        let progress = (currentTime / duration) * 100
        scrobbler.updateProgress(progress)
    }

    // MARK: - Plex Progress Reporting

    private func reportProgress() async {
        guard currentTime > 0, duration > 0 else { return }

        // Only report if progress changed significantly (more than 5 seconds)
        guard abs(currentTime - lastReportedProgress) > 5 else { return }

        lastReportedProgress = currentTime

        let progressPercent = Int((currentTime / duration) * 100)
        print("📊 [Player] Progress: \(Int(currentTime))s / \(Int(duration))s (\(progressPercent)%)")

        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
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
                state: isPlaying ? "playing" : "paused"
            )
            let _: EmptyResponse = try await api.post("/api/plex/progress", body: request)
        } catch {
            print("⚠️ [Player] Failed to report progress: \(error)")
        }
    }

    private func reportStopped() async {
        guard duration > 0 else { return }
        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
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
            let _: EmptyResponse = try await api.post("/api/plex/progress", body: request)
        } catch {
            print("⚠️ [Player] Failed to report stopped: \(error)")
        }
    }

    private func handlePlaybackEnd() {
        isPlaying = false
        stopProgressTracking()
        disableDisplaySleep()

        // Mark as watched
        Task {
            do {
                let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
                struct ScrobbleRequest: Encodable {
                    let ratingKey: String
                }
                let _: EmptyResponse = try await api.post("/api/plex/scrobble", body: ScrobbleRequest(ratingKey: ratingKey))
                print("✅ [Player] Marked as watched")
            } catch {
                print("⚠️ [Player] Failed to mark as watched: \(error)")
            }

            // Auto-play next episode if available
            if item.type == "episode" && nextEpisode != nil {
                print("▶️ [Player] Auto-playing next episode...")
                // Small delay to ensure scrobble completes
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await MainActor.run {
                    playNext()
                }
            }
        }
    }

    // MARK: - Now Playing Info (Control Center / Lock Screen)

    private func setupNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()

        // Title
        nowPlayingInfo[MPMediaItemPropertyTitle] = item.title

        // Show/Series info
        if let grandparentTitle = item.grandparentTitle {
            nowPlayingInfo[MPMediaItemPropertyArtist] = grandparentTitle

            // Episode info
            if let seasonNum = item.parentIndex, let episodeNum = item.index {
                nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Season \(seasonNum), Episode \(episodeNum)"
            }
        } else {
            // Movie - use year as artist
            if let year = item.year {
                nowPlayingInfo[MPMediaItemPropertyArtist] = String(year)
            }
        }

        // Duration and playback rate
        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0

        // Set the info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        // Load artwork asynchronously
        loadNowPlayingArtwork()

        print("🎵 [Player] Now Playing info set: \(item.title)")
    }

    private func loadNowPlayingArtwork() {
        // Use the item's thumb for artwork
        guard let thumbPath = item.thumb ?? item.grandparentThumb,
              let imageURL = ImageService.shared.plexImageURL(path: thumbPath, width: 600, height: 600) else {
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                if let nsImage = NSImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: nsImage.size) { _ in nsImage }

                    await MainActor.run {
                        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        info[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                        print("🖼️ [Player] Now Playing artwork loaded")
                    }
                }
            } catch {
                print("⚠️ [Player] Failed to load artwork: \(error)")
            }
        }
    }

    private func updateNowPlayingInfo() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }

        // Update time and playback state
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackSpeed : 0.0

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("🎵 [Player] Now Playing info cleared")
    }

    // MARK: - Display Sleep Prevention

    private func enableDisplaySleep() {
        #if os(macOS)
        guard displaySleepAssertion == nil else { return }

        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Playing video"
        )
        displaySleepAssertion = activity
        print("💤 [Player] Display sleep disabled (media playing)")
        #endif
    }

    private func disableDisplaySleep() {
        #if os(macOS)
        guard let activity = displaySleepAssertion else { return }

        ProcessInfo.processInfo.endActivity(activity)
        displaySleepAssertion = nil
        print("💤 [Player] Display sleep re-enabled (media stopped)")
        #endif
    }

    // MARK: - Stop Playback

    func stopPlayback() {
        print("🛑 [Player] Stopping playback")

        // Stop progress tracking immediately
        stopProgressTracking()

        // Disable display sleep prevention
        disableDisplaySleep()

        // Clear Now Playing info
        clearNowPlayingInfo()

        // Stop based on backend
        switch playerBackend {
        case .avplayer:
            player?.pause()
        case .mpv:
            // Shutdown MPV completely to stop rendering
            mpvController?.shutdown()
        }
    }

    // MARK: - Cleanup

    private func stopTranscodeSession() async {
        guard let sessionId = sessionId,
              let baseUrl = plexBaseUrl,
              let token = plexToken else {
            return
        }

        do {
            let stopUrl = "\(baseUrl)/video/:/transcode/universal/stop?session=\(sessionId)&X-Plex-Token=\(token)"
            guard let url = URL(string: stopUrl) else { return }

            print("🛑 [Player] Stopping transcode session: \(sessionId)")
            _ = try await URLSession.shared.data(from: url)
            print("✅ [Player] Transcode session stopped")
        } catch {
            print("⚠️ [Player] Failed to stop transcode session: \(error)")
        }
    }

    func onDisappear() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.reportProgress() // Final progress snapshot
            await self.reportStopped()  // Explicit stopped state like web

            // Stop Trakt scrobble
            let progress = self.duration > 0 ? (self.currentTime / self.duration) * 100 : 0
            await self.scrobbler.stopScrobble(progress: progress)

            // Stop the transcode session
            await self.stopTranscodeSession()

            // Clean up based on backend
            switch self.playerBackend {
            case .avplayer:
                if let observer = self.timeObserver {
                    self.player?.removeTimeObserver(observer)
                    self.timeObserver = nil
                }
                self.player?.pause()
                self.player = nil
            case .mpv:
                // MPV shutdown already called in stopPlayback(), just release the controller
                // Shutdown is idempotent, so it's safe to call again if not already shut down
                if let controller = self.mpvController, !controller.isShutDown {
                    controller.shutdown()
                }
                self.mpvController = nil
            }

            self.stopProgressTracking()
            self.cancellables.removeAll()
        }
    }

    // MARK: - Next Episode

    func playNext() {
        guard let next = nextEpisode else { return }

        // Create MediaItem from next episode, preserving mediaIndex for version consistency
        let nextItem = MediaItem(
            id: "plex:\(next.ratingKey)",
            title: next.title,
            type: "episode",
            thumb: next.thumb,
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: next.summary,
            grandparentTitle: item.grandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            grandparentRatingKey: item.grandparentRatingKey,
            parentIndex: next.parentIndex,
            index: next.index,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            mediaIndex: item.mediaIndex  // Preserve version selection
        )

        print("▶️ [Player] Play next: \(next.title) (mediaIndex: \(item.mediaIndex ?? 0))")

        // Stop current playback
        stopPlayback()

        // Call navigation callback
        onPlayNext?(nextItem)
    }

    /// Play a specific episode from the season (e.g., from episode selector)
    func playEpisode(_ episode: EpisodeMetadata) {
        let episodeItem = MediaItem(
            id: "plex:\(episode.ratingKey)",
            title: episode.title,
            type: "episode",
            thumb: episode.thumb,
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: episode.summary,
            grandparentTitle: item.grandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            grandparentRatingKey: item.grandparentRatingKey,
            parentIndex: episode.parentIndex,
            index: episode.index,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            mediaIndex: item.mediaIndex  // Preserve version selection
        )

        print("▶️ [Player] Play episode: S\(episode.parentIndex ?? 0)E\(episode.index ?? 0) \(episode.title) (mediaIndex: \(item.mediaIndex ?? 0))")

        // Stop current playback
        stopPlayback()

        // Call navigation callback
        onPlayNext?(episodeItem)
    }

    func cancelCountdown() {
        nextEpisodeCountdown = nil
    }

    // MARK: - Retry

    /// Retry direct play with fresh metadata and token (handles URL expiration)
    private func retryDirectPlay() async -> Bool {
        print("🔄 [Player] Retrying direct play with fresh metadata and token")

        do {
            // 1. Get ratingKey
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            guard !ratingKey.isEmpty else {
                print("❌ [Player] Invalid ratingKey")
                return false
            }

            // 2. Re-fetch metadata to get fresh part key
            struct MetaMedia: Decodable {
                struct Part: Decodable { let key: String? }
                let Part: [Part]?
                let container: String?
                let videoCodec: String?
                let audioCodec: String?
            }
            struct MetaResponse: Decodable { let Media: [MetaMedia]? }
            // CRITICAL: Bypass all caching to get truly fresh part key
            let meta: MetaResponse = try await api.get("/api/plex/metadata/\(ratingKey)", bypassCache: true)

            guard let partKey = meta.Media?.first?.Part?.first?.key, !partKey.isEmpty else {
                print("❌ [Player] No part key in fresh metadata")
                return false
            }

            // Check if part key changed (indicates Plex rescanned library)
            if let oldURL = self.streamURL?.absoluteString, oldURL.contains("/library/parts/") {
                let oldPartKey = oldURL.components(separatedBy: "?").first?.components(separatedBy: "/library/parts").last ?? ""
                let newPartKey = partKey.replacingOccurrences(of: "/library/parts", with: "")
                if !oldPartKey.isEmpty && oldPartKey != newPartKey {
                    print("🔄 [Player] Part key changed: \(oldPartKey) → \(newPartKey)")
                    print("   (Plex rescanned library and reassigned file IDs)")
                }
            }

            print("✅ [Player] Fresh part key: \(partKey)")

            // 3. Re-fetch server connection and token
            let servers = try await api.getPlexServers()
            guard let activeServer = servers.first(where: { $0.isActive == true }) else {
                print("❌ [Player] No active server")
                return false
            }

            let connectionsResponse = try await api.getPlexConnections(serverId: activeServer.id)
            guard let connection = connectionsResponse.connections.first(where: { $0.local == true })
                                  ?? connectionsResponse.connections.first else {
                print("❌ [Player] No server connection")
                return false
            }

            let baseUrl = connection.uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            let authServers = try await api.getPlexAuthServers()
            guard let serverWithToken = authServers.first(where: {
                $0.clientIdentifier == activeServer.id ||
                $0.clientIdentifier == activeServer.machineIdentifier
            }), let token = serverWithToken.token as String? else {
                print("❌ [Player] No fresh token")
                return false
            }

            print("✅ [Player] Fresh token obtained")

            // 4. Build new direct play URL
            let newDirectURL = "\(baseUrl)\(partKey)?X-Plex-Token=\(token)"
            guard let url = URL(string: newDirectURL) else {
                print("❌ [Player] Invalid URL")
                return false
            }

            print("✅ [Player] New direct play URL: \(newDirectURL)")

            // 5. Update state
            self.streamURL = url
            self.currentURLIsHLS = false
            self.plexBaseUrl = baseUrl
            self.plexToken = token

            // 6. Reload based on backend
            let savedPosition = currentTime > 2 ? currentTime : 0

            switch playerBackend {
            case .mpv:
                guard let mpvController = self.mpvController else {
                    print("❌ [Player] MPV controller not available")
                    return false
                }

                print("🎬 [MPV] Reloading file with fresh URL")
                self.fileStartTime = nil // Reset to detect new loading errors
                mpvController.loadFile(url.absoluteString)

                // Seek will happen after file-loaded event via applyInitialSeekIfNeeded
                // But we need to preserve the position
                if savedPosition > 2 {
                    // Wait for file to load, then seek
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    if self.duration > 0 && savedPosition < self.duration {
                        self.seek(to: savedPosition)
                        print("⏩ [Player] Restored position: \(Int(savedPosition))s")
                    }
                }

            case .avplayer:
                let asset = AVURLAsset(url: url)
                let playerItem = AVPlayerItem(asset: asset)
                playerItem.preferredForwardBufferDuration = 10 // Direct play: lighter buffer
                playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                playerItem.preferredPeakBitRate = 0

                if self.player == nil {
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.automaticallyWaitsToMinimizeStalling = true
                    self.player?.allowsExternalPlayback = false
                } else {
                    self.player?.replaceCurrentItem(with: playerItem)
                }

                setupPlayerObservers(playerItem: playerItem)
                setupPlayerStateObservers()
                self.player?.rate = self.playbackSpeed
                self.isPlaying = true

                // Restore position
                if savedPosition > 2 {
                    seek(to: savedPosition)
                    print("⏩ [Player] Restored position: \(Int(savedPosition))s")
                }
            }

            print("✅ [Player] Successfully retried direct play with fresh URL")
            return true

        } catch {
            print("❌ [Player] Failed to retry direct play: \(error)")
            return false
        }
    }

    /// Retry with HLS transcoding as fallback (for MPV backend)
    private func retryWithHLS() async {
        print("↩️ [Player] Falling back to HLS transcoding (quality: \(selectedQuality.rawValue))")

        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            struct StreamResponse: Codable { let url: String }
            let response: StreamResponse = try await api.get(
                "/api/plex/stream/\(ratingKey)",
                queryItems: buildTranscodeQueryItems(quality: selectedQuality)
            )
            guard let url = URL(string: response.url) else {
                throw NSError(domain: "PlayerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid HLS URL"])
            }

            self.streamURL = url
            self.currentURLIsHLS = true
            self.isTranscoding = selectedQuality.requiresTranscoding

            // Handle session URL if needed (start.m3u8)
            var finalURL = url
            if url.absoluteString.contains("start.m3u8") {
                print("📺 [Player] Starting HLS transcode session")

                // Extract session ID
                if let sessionParam = URLComponents(string: url.absoluteString)?.queryItems?.first(where: { $0.name == "session" })?.value {
                    self.sessionId = sessionParam
                }

                // Start the session
                let (_, startResponse) = try await URLSession.shared.data(from: url)
                if let httpResponse = startResponse as? HTTPURLResponse {
                    print("📺 [Player] Start response: \(httpResponse.statusCode)")
                }

                // Wait for transcoder (MPV needs more time)
                let delaySeconds = 5
                print("⏳ [Player] Waiting \(delaySeconds)s for transcoder...")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)

                // Build session URL
                if let sessionId = self.sessionId,
                   let baseUrlString = url.absoluteString.components(separatedBy: "/video/").first,
                   let token = URLComponents(string: url.absoluteString)?.queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value {
                    let sessionURL = "\(baseUrlString)/video/:/transcode/universal/session/\(sessionId)/base/index.m3u8?X-Plex-Token=\(token)"
                    if let sessionUrl = URL(string: sessionURL) {
                        finalURL = sessionUrl
                        self.streamURL = sessionUrl
                        print("✅ [Player] Using session URL: \(sessionURL)")
                    }
                }
            }

            let savedPosition = currentTime > 2 ? currentTime : 0

            switch playerBackend {
            case .mpv:
                guard let mpvController = self.mpvController else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller not available"])
                }

                print("🎬 [MPV] Loading HLS stream")
                self.fileStartTime = nil
                mpvController.loadFile(finalURL.absoluteString)

                // Restore position after file loads
                if savedPosition > 2 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds for HLS
                    if self.duration > 0 && savedPosition < self.duration {
                        self.seek(to: savedPosition)
                        print("⏩ [Player] Restored position: \(Int(savedPosition))s")
                    }
                }

            case .avplayer:
                // AVPlayer has its own reloadAsHLSFallback method
                await reloadAsHLSFallback()
            }

            self.isLoading = false
            print("✅ [Player] HLS fallback successful")

        } catch {
            print("❌ [Player] HLS fallback failed: \(error)")
            self.error = "Failed to load video: \(error.localizedDescription)"
            self.isLoading = false
            self.isPlaying = false
        }
    }

    func retry() {
        print("🔄 [Player] Retrying playback")
        error = nil
        isLoading = true
        initialSeekApplied = false

        Task {
            await loadStreamURL()
        }
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
