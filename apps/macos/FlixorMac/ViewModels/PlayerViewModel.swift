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
    private enum SourceKind {
        case plex
        case offline
        case stream
    }

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
    @Published var availableExternalSubtitleOptions: [StremioSubtitleCandidate] = []
    @Published var availableStremioSources: [StremioPlayableStream] = []
    @Published var currentAudioTrackId: Int? = nil
    @Published var currentSubtitleTrackId: Int? = nil
    @Published var selectedExternalSubtitleId: String? = nil
    @Published var currentStremioSourceId: String? = nil

    // Subtitle preference (persisted)
    private var subtitlesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "playerSubtitlesEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "playerSubtitlesEnabled") }
    }

    // Performance overlay
    @Published var showPerformanceOverlay = false
    @Published var performanceStats: PerformanceStats?
    private var performanceStatsTimer: Timer?

    // Chapter navigation
    @Published var chapters: [MPVChapter] = []
    @Published var currentChapterIndex: Int?

    // Subtitle styling (persisted)
    @Published var subtitleFontSize: Int = UserDefaults.standard.integer(forKey: "subtitleFontSize") == 0 ? 55 : UserDefaults.standard.integer(forKey: "subtitleFontSize")
    @Published var subtitleBorderSize: Double = UserDefaults.standard.double(forKey: "subtitleBorderSize") == 0 ? 3.0 : UserDefaults.standard.double(forKey: "subtitleBorderSize")
    @Published var subtitleBackgroundOpacity: Double = UserDefaults.standard.double(forKey: "subtitleBackgroundOpacity")

    // Audio/Subtitle sync offset
    @Published var audioDelay: Double = 0.0
    @Published var subtitleDelay: Double = 0.0

    // Markers (intro/credits) - no high-frequency updates
    @Published var markers: [PlayerMarker] = []
    @Published var currentMarker: PlayerMarker? = nil

    // Auto-skip state
    private var autoSkipTriggeredMarkers: Set<String> = []
    private var autoSkipTimer: Timer?
    @Published var autoSkipCountdown: Int? = nil  // Countdown seconds shown to user

    // Next episode & season episodes
    @Published var nextEpisode: EpisodeMetadata? = nil
    @Published var seasonEpisodes: [EpisodeMetadata] = []
    @Published var nextEpisodeCountdown: Int? = nil
    private var nextEpisodeCountdownTimer: Timer?

    // Playback metadata
    private(set) var item: MediaItem
    private(set) var player: AVPlayer?
    @Published var mpvController: MPVPlayerController?
    @Published var thumbnailGenerator: MPVThumbnailGenerator?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var kvoCancellables = Set<AnyCancellable>()
    private let api = APIClient.shared

    private var offlineFilePath: String?
    private var streamPlaybackItem: StreamPlaybackItem?
    private var externalSubtitleTempFiles: [URL] = []

    // Backend selection is fixed to MPV on macOS
    private var playerBackend: PlayerBackend { .mpv }

    private var sourceKind: SourceKind {
        if streamPlaybackItem != nil { return .stream }
        if offlineFilePath != nil { return .offline }
        return .plex
    }

    // Progress tracking
    private var progressTimer: Timer?
    private var lastReportedProgress: TimeInterval = 0
    private var initialSeekApplied = false
    private var serverResumeSeconds: TimeInterval?
    private var forcedResumeSeconds: TimeInterval?

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

    // Stremio resume/cache
    private let streamCache = StremioStreamCache.shared
    private let resumeStore = StremioResumeStore.shared

    // Navigation callback for next episode
    var onPlayNext: ((PlayerDestination) -> Void)?

    // Display sleep prevention
    private var displaySleepAssertion: NSObjectProtocol?

    /// Generate Plex HTTP headers for MPV streaming
    private var plexStreamHeaders: [String: String] {
        var headers: [String: String] = [
            "X-Plex-Client-Identifier": "FlixorMac",
            "X-Plex-Product": "Flixor",
            "X-Plex-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "X-Plex-Platform": "macOS",
            "X-Plex-Client-Profile-Name": "Generic",
            "Accept": "application/json",
            "Accept-Charset": "utf-8"
        ]
        if let token = plexToken {
            headers["X-Plex-Token"] = token
        }
        return headers
    }

    init(item: MediaItem) {
        self.item = item
        setupPlayer()
        setupNowPlayingInfo()
    }

    /// Initialize for offline playback from a local file
    init(offlineFilePath: String, title: String) {
        // Create a minimal MediaItem for offline playback
        self.item = MediaItem(
            id: "offline",
            title: title,
            type: "movie",
            thumb: nil,
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )

        self.offlineFilePath = offlineFilePath
        setupPlayer()
        setupNowPlayingInfo()
    }

    init(streamItem: StreamPlaybackItem) {
        self.item = MediaItem(
            id: "stream:\(streamItem.contentKey)",
            title: streamItem.mediaType == .episode ? (streamItem.episodeTitle ?? streamItem.title) : streamItem.title,
            type: streamItem.mediaType == .movie ? "movie" : "episode",
            thumb: streamItem.posterURL,
            art: streamItem.backdropURL,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: streamItem.resumePositionMs,
            summary: nil,
            grandparentTitle: streamItem.mediaType == .episode ? streamItem.title : nil,
            grandparentThumb: streamItem.posterURL,
            grandparentArt: streamItem.backdropURL,
            grandparentRatingKey: nil,
            parentIndex: streamItem.seasonNumber,
            index: streamItem.episodeNumber,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
        self.streamPlaybackItem = streamItem
        self.availableExternalSubtitleOptions = streamItem.externalSubtitles
        self.availableStremioSources = streamItem.availableStreams
        self.currentStremioSourceId = streamItem.availableStreams.first(where: { $0.url == streamItem.uri && $0.addonId == streamItem.addonId })?.id
        self.forcedResumeSeconds = TimeInterval(streamItem.resumePositionMs ?? 0) / 1000.0
        setupPlayer()
        setupNowPlayingInfo()
    }

    /// Setup player for offline file playback
    private func setupOfflinePlayer(filePath: String) {
        // Use MPV backend for offline playback (better file format support)
        setupMPVController()

        // Build file URL
        let fileUrl = filePath.hasPrefix("file://") ? filePath : "file://\(filePath)"

        print("[Player] Loading offline file: \(fileUrl)")
        isLoading = true

        // Wait for MPV to initialize before loading (view must be in window first)
        Task { @MainActor in
            guard let mpvController = self.mpvController else {
                print("❌ [Player] MPV controller not available for offline playback")
                self.error = "MPV controller not initialized"
                return
            }

            // Wait for MPV to be initialized (view must be in window first)
            var waitCount = 0
            let maxWaitCount = 50 // 5 seconds max
            while !mpvController.isInitialized && waitCount < maxWaitCount {
                print("⏳ [Player] Waiting for MPV initialization for offline file... (\(waitCount)/\(maxWaitCount))")
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                waitCount += 1
            }

            guard mpvController.isInitialized else {
                print("❌ [Player] MPV failed to initialize for offline playback (timeout)")
                self.error = "MPV failed to initialize"
                return
            }

            print("🎬 [Player] MPV initialized, loading offline file: \(fileUrl)")
            mpvController.loadFile(fileUrl, headers: nil)

            // Start progress tracking
            self.startProgressTracking()
        }
    }

    deinit {
        // Cleanup synchronously in deinit
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        progressTimer?.invalidate()
        progressTimer = nil
        autoSkipTimer?.invalidate()
        autoSkipTimer = nil
        nextEpisodeCountdownTimer?.invalidate()
        nextEpisodeCountdownTimer = nil
        player?.pause()
        player = nil
        cancellables.removeAll()
        externalSubtitleTempFiles.forEach { url in
            try? FileManager.default.removeItem(at: url)
        }
        externalSubtitleTempFiles.removeAll()

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
            switch sourceKind {
            case .plex:
                await fetchServerResumeOffset()
                print("🎬 [Player] Using MPV backend for Plex playback")
                setupMPVController()
                await loadStreamURL()
            case .offline:
                guard let offlineFilePath else { return }
                print("🎬 [Player] Using MPV backend for offline playback")
                setupOfflinePlayer(filePath: offlineFilePath)
            case .stream:
                print("🎬 [Player] Using MPV backend for direct stream playback")
                setupMPVController()
                if let streamPlaybackItem {
                    await loadExternalStream(streamPlaybackItem)
                }
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
                    // Load chapters
                    self.loadChapters()
                    // Apply subtitle styling from persisted settings
                    self.applySubtitleStyling()
                    if self.sourceKind == .stream {
                        Task {
                            await self.applyStreamTrackAutoSelectionIfNeeded()
                        }
                    }
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
        guard sourceKind == .plex else { return }
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

            // Debug: Print raw marker data
            for (index, m) in plexMarkers.enumerated() {
                print("   [Raw \(index)] type=\(m.type ?? "nil"), start=\(m.startTimeOffset ?? -1), end=\(m.endTimeOffset ?? -1)")
            }

            // Map to PlayerMarker (ensure id and ms fields present)
            let mapped: [PlayerMarker] = plexMarkers.compactMap { m in
                guard let type = m.type?.lowercased(),
                      let s = m.startTimeOffset, let e = m.endTimeOffset else { return nil }
                // Only care about intro/credits
                guard type == "intro" || type == "credits" else { return nil }
                // Convert Int id to String (Plex API returns Int)
                let id = m.id.map { String($0) } ?? "\(type)-\(s)-\(e)"
                return PlayerMarker(id: id, type: type, startTimeOffset: s, endTimeOffset: e)
            }
            self.markers = mapped
            let creditsMarker = mapped.first { $0.type == "credits" }
            let introMarker = mapped.first { $0.type == "intro" }
            print("🎬 [Player] Markers loaded: \(mapped.count) total")
            if let intro = introMarker {
                print("   📍 INTRO: \(intro.startTimeOffset)ms - \(intro.endTimeOffset)ms (\(TimeInterval(intro.startTimeOffset)/1000.0)s - \(TimeInterval(intro.endTimeOffset)/1000.0)s)")
            }
            if let credits = creditsMarker {
                print("   📍 CREDITS: \(credits.startTimeOffset)ms - \(credits.endTimeOffset)ms (\(TimeInterval(credits.startTimeOffset)/1000.0)s - \(TimeInterval(credits.endTimeOffset)/1000.0)s)")
            }
            if mapped.isEmpty {
                print("   ⚠️ No intro/credits markers found for this content")
            }
        } catch {
            print("❌ [Player] Failed to fetch markers: \(error)")
            print("❌ [Player] Error details: \(String(describing: error))")
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
                cancelAutoSkip()
            }
            return
        }

        let currentMs = Int(currentTime * 1000)

        let newMarker = markers.first { marker in
            (marker.type == "intro" || marker.type == "credits") &&
            currentMs >= marker.startTimeOffset && currentMs <= marker.endTimeOffset
        }

        // Only update if changed to avoid unnecessary UI updates
        if newMarker?.id != currentMarker?.id {
            if let marker = newMarker {
                print("🎬 [Player] ✅ Marker ACTIVE: \(marker.type) at \(currentMs)ms (range: \(marker.startTimeOffset)-\(marker.endTimeOffset))")
                // Trigger auto-skip if enabled and not already triggered for this marker
                triggerAutoSkipIfEnabled(for: marker)
            } else if currentMarker != nil {
                print("🎬 [Player] ❌ Marker ended at \(currentMs)ms")
                cancelAutoSkip()
            }
            currentMarker = newMarker
        }
    }

    // MARK: - Auto-Skip

    private func triggerAutoSkipIfEnabled(for marker: PlayerMarker) {
        guard !autoSkipTriggeredMarkers.contains(marker.id) else {
            print("⏭️ [Player] Marker \(marker.id) already triggered, skipping auto-skip")
            return
        }

        let defaults = UserDefaults.standard
        let skipIntro = defaults.skipIntroAutomatically
        let skipCredits = defaults.skipCreditsAutomatically
        let shouldAutoSkip = (marker.type == "intro" && skipIntro) ||
                             (marker.type == "credits" && skipCredits)

        print("⏭️ [Player] Auto-skip check: type=\(marker.type), skipIntro=\(skipIntro), skipCredits=\(skipCredits), shouldAutoSkip=\(shouldAutoSkip)")

        guard shouldAutoSkip else { return }

        let delay = defaults.autoSkipDelay
        print("⏭️ [Player] Starting auto-skip countdown for \(marker.type): \(delay)s")

        // Start countdown
        autoSkipCountdown = delay
        autoSkipTimer?.invalidate()

        // Countdown timer (fires every second)
        autoSkipTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            Task { @MainActor in
                guard let countdown = self.autoSkipCountdown, countdown > 0 else {
                    timer.invalidate()
                    return
                }

                if countdown == 1 {
                    // Time to skip
                    self.performAutoSkip(marker)
                } else {
                    self.autoSkipCountdown = countdown - 1
                }
            }
        }
    }

    private func performAutoSkip(_ marker: PlayerMarker) {
        // Verify we're still in the marker region
        guard currentMarker?.id == marker.id else {
            cancelAutoSkip()
            return
        }

        autoSkipTriggeredMarkers.insert(marker.id)
        cancelAutoSkip()
        skipMarker()
        print("⏭️ [Player] Auto-skipped \(marker.type)")
    }

    func cancelAutoSkip() {
        autoSkipTimer?.invalidate()
        autoSkipTimer = nil
        autoSkipCountdown = nil
    }

    /// Cancel auto-skip when user manually skips or interacts
    func userCancelledAutoSkip() {
        if let marker = currentMarker {
            autoSkipTriggeredMarkers.insert(marker.id)
        }
        cancelAutoSkip()
    }

    /// Find credits chapter by name (fallback when no Plex marker exists)
    private func findCreditsChapter() -> MPVChapter? {
        let creditsKeywords = ["credits", "end credits", "ending credits"]

        return chapters.first { chapter in
            guard let title = chapter.title?.lowercased() else { return false }
            return creditsKeywords.contains { title.contains($0) }
        }
    }

    private func updateNextEpisodeCountdown() {
        // Debug: Log when guard fails
        if item.type != "episode" {
            if nextEpisodeCountdown != nil { nextEpisodeCountdown = nil }
            return
        }
        if nextEpisode == nil {
            if nextEpisodeCountdown != nil { nextEpisodeCountdown = nil }
            return
        }
        if duration <= 0 {
            if nextEpisodeCountdown != nil { nextEpisodeCountdown = nil }
            return
        }

        // Priority: 1. Credits marker, 2. Credits chapter, 3. Time-based fallback
        let creditsMarker = markers.first { $0.type == "credits" }
        let creditsChapter = findCreditsChapter()
        let fallbackSeconds = TimeInterval(UserDefaults.standard.creditsCountdownFallback)
        let bufferSeconds: TimeInterval = 3.0  // Show overlay 3 seconds before trigger point
        var triggerStart: TimeInterval
        let triggerSource: String

        if let marker = creditsMarker {
            // Priority 1: Use Plex credits marker (convert ms to seconds, minus buffer)
            triggerStart = max(0, TimeInterval(marker.startTimeOffset) / 1000.0 - bufferSeconds)
            triggerSource = "CREDITS marker (3s early) at \(triggerStart)s"
        } else if let chapter = creditsChapter {
            // Priority 2: Use credits chapter start time (minus buffer)
            triggerStart = max(0, chapter.time - bufferSeconds)
            triggerSource = "CREDITS chapter '\(chapter.title ?? "Credits")' (3s early) at \(triggerStart)s"
        } else {
            // Priority 3: Use fallback (X seconds before end)
            triggerStart = max(0, duration - fallbackSeconds)
            triggerSource = "FALLBACK (\(Int(fallbackSeconds))s before end) at \(triggerStart)s"
        }

        if currentTime >= triggerStart {
            // Start 5-second countdown timer if not already running
            if nextEpisodeCountdown == nil && nextEpisodeCountdownTimer == nil {
                print("🎬 [Countdown] TRIGGERED via \(triggerSource)! Starting 5s countdown")
                startNextEpisodeCountdown()
            }
        } else {
            // Cancel countdown if we seeked back before trigger point
            if nextEpisodeCountdown != nil {
                cancelCountdown()
            }
        }
    }

    func skipMarker() {
        guard let marker = currentMarker else { return }
        // Mark as triggered so it won't auto-skip again if user seeks back
        autoSkipTriggeredMarkers.insert(marker.id)
        cancelAutoSkip()
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

            // Prefer current/preferred connection, then local, then first available
            guard let selectedConnection = connections.first(where: { $0.isCurrent == true })
                    ?? connections.first(where: { $0.isPreferred == true })
                    ?? connections.first(where: { $0.local == true })
                    ?? connections.first else {
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

                // Wait for MPV to be initialized (view must be in window first)
                var waitCount = 0
                let maxWaitCount = 50 // 5 seconds max
                while !mpvController.isInitialized && waitCount < maxWaitCount {
                    print("⏳ [MPV] Waiting for initialization... (\(waitCount)/\(maxWaitCount))")
                    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    waitCount += 1
                }

                guard mpvController.isInitialized else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV failed to initialize (timeout)"])
                }

                print("🎬 [MPV] Loading file: \(finalURL.absoluteString)")
                mpvController.loadFile(finalURL.absoluteString, headers: plexStreamHeaders)

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

    private func loadExternalStream(_ streamItem: StreamPlaybackItem) async {
        isLoading = true
        error = nil
        initialSeekApplied = false
        forcedResumeSeconds = TimeInterval(streamItem.resumePositionMs ?? 0) / 1000.0
        currentURLIsHLS = false
        isTranscoding = false
        markers = []
        currentMarker = nil
        nextEpisode = nil
        seasonEpisodes = []
        nextEpisodeCountdown = nil
        availableExternalSubtitleOptions = streamItem.externalSubtitles
        availableStremioSources = streamItem.availableStreams
        currentStremioSourceId = streamItem.availableStreams.first(where: { $0.url == streamItem.uri && $0.addonId == streamItem.addonId })?.id
        selectedExternalSubtitleId = nil
        cleanupExternalSubtitleFiles()

        do {
            guard let mpvController = self.mpvController else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller not initialized"])
            }

            var waitCount = 0
            let maxWaitCount = 50
            while !mpvController.isInitialized && waitCount < maxWaitCount {
                try await Task.sleep(nanoseconds: 100_000_000)
                waitCount += 1
            }

            guard mpvController.isInitialized else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV failed to initialize"])
            }

            streamURL = URL(string: streamItem.uri)
            mpvController.loadFile(streamItem.uri, headers: Dictionary(uniqueKeysWithValues: streamItem.headers.map { ($0.name, $0.value) }))
            startProgressTracking()

            if UserDefaults.standard.useCachedStreams {
                let now = Date()
                await streamCache.save(
                    CachedPlaybackSource(
                        kind: "stream",
                        provider: StreamProvider.stremio.rawValue,
                        contentKey: streamItem.contentKey,
                        playbackItem: streamItem,
                        savedAt: now,
                        expiresAt: now.addingTimeInterval(TimeInterval(UserDefaults.standard.streamCacheTTL))
                    )
                )
            }

            AppLogger.shared.info("[Stremio] Starting macOS stream playback", data: [
                "contentKey": streamItem.contentKey,
                "uri": streamItem.uri,
                "addonId": streamItem.addonId ?? "",
                "addonName": streamItem.addonName ?? "",
            ])
        } catch {
            AppLogger.shared.error("[Stremio] Failed to load stream playback", data: [
                "contentKey": streamItem.contentKey,
                "uri": streamItem.uri,
                "error": error.localizedDescription,
            ])
            self.error = "Failed to load Stremio stream: \(error.localizedDescription)"
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

        var seconds = forcedResumeSeconds ?? TimeInterval(item.viewOffset ?? 0) / 1000.0
        forcedResumeSeconds = nil
        if seconds <= 2, let s = serverResumeSeconds { seconds = s }

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

    // MARK: - Performance Overlay

    func togglePerformanceOverlay() {
        showPerformanceOverlay.toggle()

        if showPerformanceOverlay {
            startPerformanceStatsPolling()
        } else {
            stopPerformanceStatsPolling()
        }
    }

    private func startPerformanceStatsPolling() {
        guard playerBackend == .mpv else { return }

        // Initial fetch
        updatePerformanceStats()

        // Poll every 500ms
        performanceStatsTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePerformanceStats()
            }
        }
    }

    private func stopPerformanceStatsPolling() {
        performanceStatsTimer?.invalidate()
        performanceStatsTimer = nil
    }

    private func updatePerformanceStats() {
        guard let mpv = mpvController else { return }
        performanceStats = mpv.getPerformanceStats()
    }

    // MARK: - Chapter Navigation

    func loadChapters() {
        guard let mpv = mpvController else { return }
        chapters = mpv.getChapters()
        currentChapterIndex = mpv.getCurrentChapter()
        print("📖 [Player] Loaded \(chapters.count) chapters")
    }

    func seekToChapter(_ index: Int) {
        guard let mpv = mpvController, index >= 0, index < chapters.count else { return }
        mpv.seekToChapter(index)
        currentChapterIndex = index
        print("📖 [Player] Seeking to chapter \(index + 1): \(chapters[index].displayName)")
    }

    func previousChapter() {
        guard let mpv = mpvController else { return }
        mpv.previousChapter()
        // Update current chapter index after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.currentChapterIndex = mpv.getCurrentChapter()
        }
    }

    func nextChapter() {
        guard let mpv = mpvController else { return }
        mpv.nextChapter()
        // Update current chapter index after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.currentChapterIndex = mpv.getCurrentChapter()
        }
    }

    // MARK: - Subtitle Styling

    func setSubtitleFontSize(_ size: Int) {
        subtitleFontSize = size
        UserDefaults.standard.set(size, forKey: "subtitleFontSize")
        mpvController?.setSubtitleFontSize(size)
    }

    func setSubtitleBorderSize(_ size: Double) {
        subtitleBorderSize = size
        UserDefaults.standard.set(size, forKey: "subtitleBorderSize")
        mpvController?.setSubtitleBorderSize(size)
    }

    func setSubtitleBackgroundOpacity(_ opacity: Double) {
        subtitleBackgroundOpacity = opacity
        UserDefaults.standard.set(opacity, forKey: "subtitleBackgroundOpacity")
        // Convert opacity (0-1) to hex alpha (00-FF) with black background
        let alpha = Int(opacity * 255)
        let hexColor = String(format: "000000%02X", alpha)
        mpvController?.setSubtitleBackgroundColor(hexColor)
    }

    func applySubtitleStyling() {
        guard let mpv = mpvController else { return }
        mpv.setSubtitleFontSize(subtitleFontSize)
        mpv.setSubtitleBorderSize(subtitleBorderSize)
        let alpha = Int(subtitleBackgroundOpacity * 255)
        let hexColor = String(format: "000000%02X", alpha)
        mpv.setSubtitleBackgroundColor(hexColor)
    }

    // MARK: - Audio/Subtitle Sync

    func setAudioDelay(_ seconds: Double) {
        audioDelay = seconds
        mpvController?.setAudioDelay(seconds)
        print("🔊 [Player] Audio delay set to \(seconds)s")
    }

    func setSubtitleDelay(_ seconds: Double) {
        subtitleDelay = seconds
        mpvController?.setSubtitleDelay(seconds)
        print("💬 [Player] Subtitle delay set to \(seconds)s")
    }

    func resetSyncOffsets() {
        setAudioDelay(0)
        setSubtitleDelay(0)
    }

    func changeQuality(_ newQuality: PlaybackQuality) {
        guard sourceKind == .plex else { return }
        print("🎚️ [Player] Changing quality: \(selectedQuality.rawValue) → \(newQuality.rawValue)")

        // No change needed
        guard newQuality != selectedQuality else {
            print("   Already at \(newQuality.rawValue)")
            return
        }

        isChangingQuality = true

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
        let subtitleTracks = mpv.getSubtitleTracks()
        availableSubtitleTracks = subtitleTracks.filter { !$0.external }
        currentAudioTrackId = mpv.getCurrentAudioTrack()
        currentSubtitleTrackId = mpv.getCurrentSubtitleTrack()

        print("🎵 [Player] Loaded \(availableAudioTracks.count) audio tracks")
        print("💬 [Player] Loaded \(subtitleTracks.count) subtitle tracks")

        if sourceKind == .stream {
            print("💬 [Player] Stream subtitle options: internal=\(availableSubtitleTracks.count), external=\(availableExternalSubtitleOptions.count)")
            return
        }

        if subtitlesEnabled {
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
        selectedExternalSubtitleId = nil
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
            if let streamPlaybackItem {
                await scrobbler.startScrobble(for: streamPlaybackItem, initialProgress: initialProgress)
            } else {
                await scrobbler.startScrobble(for: item, initialProgress: initialProgress)
            }
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

        if let streamPlaybackItem {
            await saveStreamProgress(streamPlaybackItem, progressPercent: progressPercent)
            return
        }

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

    /// Persists resume position plus a local watch-history entry for stream playback.
    /// The history entry is what makes Continue Watching work without Plex or Trakt.
    private func saveStreamProgress(
        _ streamItem: StreamPlaybackItem,
        progressPercent: Int,
        isFinal: Bool = false
    ) async {
        let positionMs = Int(currentTime * 1000)
        let durationMs = Int(duration * 1000)

        if progressPercent >= 90 {
            await resumeStore.remove(contentKey: streamItem.contentKey)
        } else {
            await resumeStore.save(
                ResumeState(
                    contentKey: streamItem.contentKey,
                    positionMs: positionMs,
                    durationMs: durationMs,
                    updatedAt: Date()
                )
            )
        }

        // recordProgress handles the completion threshold itself, so it also clears
        // finished titles out of the row.
        await LocalLibraryStore.shared.recordProgress(
            for: streamItem,
            positionMs: positionMs,
            durationMs: durationMs,
            force: isFinal
        )
    }

    private func reportStopped() async {
        guard duration > 0 else { return }
        if let streamPlaybackItem {
            let progressPercent = Int((currentTime / duration) * 100)
            await saveStreamProgress(streamPlaybackItem, progressPercent: progressPercent, isFinal: true)
            return
        }
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

        if let streamPlaybackItem {
            Task {
                await resumeStore.remove(contentKey: streamPlaybackItem.contentKey)
                await scrobbler.stopScrobble(progress: 100)
            }
            return
        }

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

        // Cancel next episode countdown
        nextEpisodeCountdownTimer?.invalidate()
        nextEpisodeCountdownTimer = nil
        nextEpisodeCountdown = nil

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

        cleanupExternalSubtitleFiles()
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
        // Stop performance stats polling
        stopPerformanceStatsPolling()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.reportProgress() // Final progress snapshot
            await self.reportStopped()

            // Stop Trakt scrobble
            let progress = self.duration > 0 ? (self.currentTime / self.duration) * 100 : 0
            await self.scrobbler.stopScrobble(progress: progress)

            if self.sourceKind == .plex {
                await self.stopTranscodeSession()
            }

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
            self.cleanupExternalSubtitleFiles()
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
        onPlayNext?(.plex(nextItem))
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
        onPlayNext?(.plex(episodeItem))
    }

    func cancelCountdown() {
        nextEpisodeCountdownTimer?.invalidate()
        nextEpisodeCountdownTimer = nil
        nextEpisodeCountdown = nil
    }

    var isStreamPlayback: Bool {
        sourceKind == .stream
    }

    var canSwitchStreamSources: Bool {
        availableStremioSources.count > 1
    }

    func switchStreamSource(_ stream: StremioPlayableStream) {
        guard sourceKind == .stream else { return }
        Task {
            await replaceCurrentStremioSource(with: stream)
        }
    }

    func loadExternalSubtitle(_ subtitle: StremioSubtitleCandidate) {
        guard sourceKind == .stream else { return }
        Task {
            do {
                try await self.attachExternalSubtitle(subtitle)
            } catch {
                AppLogger.shared.error("[Stremio] Failed to load external subtitle", data: [
                    "subtitleId": subtitle.id,
                    "url": subtitle.url,
                    "error": error.localizedDescription,
                ])
            }
        }
    }

    private func startNextEpisodeCountdown() {
        nextEpisodeCountdown = 5
        nextEpisodeCountdownTimer?.invalidate()
        nextEpisodeCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                guard let countdown = self.nextEpisodeCountdown, countdown > 0 else {
                    timer.invalidate()
                    self.nextEpisodeCountdownTimer = nil
                    return
                }
                let newCount = countdown - 1
                self.nextEpisodeCountdown = newCount
                if newCount == 0 {
                    timer.invalidate()
                    self.nextEpisodeCountdownTimer = nil
                    self.playNext()
                }
            }
        }
    }

    private func applyStreamTrackAutoSelectionIfNeeded() async {
        guard sourceKind == .stream else { return }

        if !UserDefaults.standard.preferredAudioLanguage.isEmpty,
           let audioMatch = preferredAudioTrack() {
            setAudioTrack(audioMatch.id)
        }

        guard UserDefaults.standard.enableSubtitleAutoSelect else { return }

        let internalMatch = preferredInternalSubtitleTrack()
        let externalMatch = preferredExternalSubtitleCandidate()
        let preference = UserDefaults.standard.subtitleSourcePreference

        switch preference {
        case .internal:
            if let internalMatch {
                setSubtitleTrack(internalMatch.id)
            } else if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch) } catch {}
            }
        case .external:
            if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch) } catch {}
            } else if let internalMatch {
                setSubtitleTrack(internalMatch.id)
            }
        case .any:
            if let internalMatch {
                setSubtitleTrack(internalMatch.id)
            } else if let externalMatch {
                do { try await attachExternalSubtitle(externalMatch) } catch {}
            }
        }
    }

    private func preferredAudioTrack() -> MPVTrack? {
        let preferredLanguage = UserDefaults.standard.preferredAudioLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !preferredLanguage.isEmpty else { return nil }
        return availableAudioTracks.first { track in
            (track.lang ?? "").lowercased().hasPrefix(preferredLanguage)
        }
    }

    private func preferredInternalSubtitleTrack() -> MPVTrack? {
        let preferredLanguage = UserDefaults.standard.preferredSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !preferredLanguage.isEmpty else { return availableSubtitleTracks.first }
        return availableSubtitleTracks.first { track in
            (track.lang ?? "").lowercased().hasPrefix(preferredLanguage) ||
            track.displayName.lowercased().contains(preferredLanguage)
        }
    }

    private func preferredExternalSubtitleCandidate() -> StremioSubtitleCandidate? {
        let preferredLanguage = UserDefaults.standard.preferredSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !preferredLanguage.isEmpty else { return availableExternalSubtitleOptions.first }
        return availableExternalSubtitleOptions.first { subtitle in
            subtitle.lang.lowercased().hasPrefix(preferredLanguage)
        }
    }

    private func replaceCurrentStremioSource(with stream: StremioPlayableStream) async {
        guard let current = streamPlaybackItem,
              stream.id != currentStremioSourceId,
              let uri = stream.url else {
            return
        }

        await reportProgress()

        let resumePositionMs = Int(currentTime * 1000)
        let replacement = StreamPlaybackItem(
            id: "stremio-\(current.contentKey)-\(stream.id)",
            provider: .stremio,
            uri: uri,
            headers: mergedHeaders(for: stream),
            title: current.title,
            showTitle: current.showTitle,
            mediaType: current.mediaType,
            contentKey: current.contentKey,
            imdbId: current.imdbId,
            tmdbId: current.tmdbId,
            seasonNumber: current.seasonNumber,
            episodeNumber: current.episodeNumber,
            episodeTitle: current.episodeTitle,
            backdropURL: current.backdropURL,
            posterURL: current.posterURL,
            streamLabel: stream.title ?? stream.name ?? current.streamLabel,
            addonId: stream.addonId,
            addonName: stream.addonName,
            availableStreams: current.availableStreams,
            externalSubtitles: current.externalSubtitles,
            resumePositionMs: resumePositionMs
        )

        streamPlaybackItem = replacement
        forcedResumeSeconds = TimeInterval(resumePositionMs) / 1000.0
        initialSeekApplied = false
        currentStremioSourceId = stream.id
        selectedExternalSubtitleId = nil
        cleanupExternalSubtitleFiles()
        await loadExternalStream(replacement)
    }

    private func mergedHeaders(for stream: StremioPlayableStream) -> [HTTPHeaderField] {
        var headers = stream.headers ?? [:]
        let proxy = stream.behaviorHints?.proxyHeaders?.request ?? [:]
        for (key, value) in proxy {
            headers[key] = value
        }
        return headers.keys.sorted().map { HTTPHeaderField(name: $0, value: headers[$0] ?? "") }
    }

    private func attachExternalSubtitle(_ subtitle: StremioSubtitleCandidate) async throws {
        guard let mpv = mpvController else { throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller unavailable"]) }
        guard let remoteURL = URL(string: subtitle.url) else {
            throw NSError(domain: "PlayerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid subtitle URL"])
        }

        let (data, _) = try await URLSession.shared.data(from: remoteURL)
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("FlixorMac-StremioSubs", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)

        let fileExtension: String = {
            if let format = subtitle.format, !format.isEmpty {
                return format
            }
            return remoteURL.pathExtension.isEmpty ? "srt" : remoteURL.pathExtension
        }()
        let localURL = tempDirectory.appendingPathComponent("\(subtitle.id).\(fileExtension)")
        try data.write(to: localURL, options: .atomic)

        cleanupExternalSubtitleFiles()
        externalSubtitleTempFiles = [localURL]
        mpv.clearExternalSubtitleTracks()
        mpv.addExternalSubtitleFile(path: localURL.path, title: subtitle.addonName ?? subtitle.lang.uppercased(), language: subtitle.lang, select: true)
        selectedExternalSubtitleId = subtitle.id
        subtitlesEnabled = true

        try? await Task.sleep(nanoseconds: 200_000_000)
        loadTracks()

        AppLogger.shared.info("[Stremio] External subtitle loaded", data: [
            "subtitleId": subtitle.id,
            "language": subtitle.lang,
            "path": localURL.path,
        ])
    }

    private func cleanupExternalSubtitleFiles() {
        externalSubtitleTempFiles.forEach { url in
            try? FileManager.default.removeItem(at: url)
        }
        externalSubtitleTempFiles.removeAll()
        mpvController?.clearExternalSubtitleTracks()
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
            guard let connection = connectionsResponse.connections.first(where: { $0.isCurrent == true })
                                  ?? connectionsResponse.connections.first(where: { $0.isPreferred == true })
                                  ?? connectionsResponse.connections.first(where: { $0.local == true })
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
                mpvController.loadFile(url.absoluteString, headers: plexStreamHeaders)

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
                mpvController.loadFile(finalURL.absoluteString, headers: plexStreamHeaders)

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
            switch sourceKind {
            case .plex:
                await loadStreamURL()
            case .offline:
                if let offlineFilePath {
                    setupOfflinePlayer(filePath: offlineFilePath)
                }
            case .stream:
                if let streamPlaybackItem {
                    await loadExternalStream(streamPlaybackItem)
                }
            }
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
