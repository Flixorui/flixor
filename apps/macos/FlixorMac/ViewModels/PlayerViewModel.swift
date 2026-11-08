//
//  PlayerViewModel.swift
//  FlixorMac
//
//  Video player view model (MPV playback engine)
//

import Foundation
import SwiftUI
import Combine
import MediaPlayer

@MainActor
class PlayerViewModel: ObservableObject {
    enum SourceKind {
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
    var subtitlesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "playerSubtitlesEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "playerSubtitlesEnabled") }
    }

    // Performance overlay
    @Published var showPerformanceOverlay = false
    @Published var performanceStats: PerformanceStats?
    var performanceStatsTimer: Timer?

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
    var autoSkipTriggeredMarkers: Set<String> = []
    var autoSkipTimer: Timer?
    @Published var autoSkipCountdown: Int? = nil  // Countdown seconds shown to user

    // Next episode & season episodes
    @Published var nextEpisode: EpisodeMetadata? = nil
    @Published var seasonEpisodes: [EpisodeMetadata] = []
    @Published var nextEpisodeCountdown: Int? = nil
    var nextEpisodeCountdownTimer: Timer?

    // MARK: - Stream engine state (skip segments, stream next-episode, source recovery)
    // New stored properties for that work go directly below this line.


    // Playback metadata
    private(set) var item: MediaItem
    @Published var mpvController: MPVPlayerController?
    @Published var thumbnailGenerator: MPVThumbnailGenerator?
    let api = APIClient.shared

    private var offlineFilePath: String?
    var streamPlaybackItem: StreamPlaybackItem?
    var externalSubtitleTempFiles: [URL] = []

    var sourceKind: SourceKind {
        if streamPlaybackItem != nil { return .stream }
        if offlineFilePath != nil { return .offline }
        return .plex
    }

    // Progress tracking
    var progressTimer: Timer?
    var lastReportedProgress: TimeInterval = 0
    var initialSeekApplied = false
    var serverResumeSeconds: TimeInterval?
    var forcedResumeSeconds: TimeInterval?

    // MPV error detection
    var fileStartTime: Date?
    var directPlayRetryCount: Int = 0
    var maxDirectPlayRetries: Int = 2

    // Session tracking for cleanup
    var sessionId: String?
    var plexBaseUrl: String?
    var plexToken: String?
    var currentURLIsHLS: Bool = false

    // Trakt scrobbling
    let scrobbler = TraktScrobbler.shared
    var scrobbleStarted = false

    // Stremio resume/cache
    let streamCache = StremioStreamCache.shared
    let resumeStore = StremioResumeStore.shared

    // Navigation callback for next episode
    var onPlayNext: ((PlayerDestination) -> Void)?

    // Display sleep prevention
    var displaySleepAssertion: NSObjectProtocol?
    var remoteCommandTargets: [(MPRemoteCommand, Any)] = []

    // MARK: - Playback engine state (tracks, subtitles, aspect, speed, HDR, network)
    // New stored properties for that work go directly below this line.


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
        progressTimer?.invalidate()
        progressTimer = nil
        autoSkipTimer?.invalidate()
        autoSkipTimer = nil
        nextEpisodeCountdownTimer?.invalidate()
        nextEpisodeCountdownTimer = nil
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
                    // Re-apply audio/subtitle choices remembered for this title or show
                    let remembered = self.applyRememberedTrackPreferences()
                    // Load chapters
                    self.loadChapters()
                    // Apply subtitle styling from persisted settings
                    self.applySubtitleStyling()
                    if self.sourceKind == .stream {
                        Task {
                            await self.applyStreamTrackAutoSelectionIfNeeded(
                                skipAudio: remembered.audio,
                                skipSubtitles: remembered.subtitle
                            )
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
                case "file-ended", "file-error":
                    // "file-error" = mpv reported MPV_END_FILE_REASON_ERROR.
                    // An end within 3s of start is also treated as a load failure,
                    // since some broken URLs end with EOF instead of an error.
                    let isError = event == "file-error"
                    let failedEarly: Bool = {
                        guard let startTime = self.fileStartTime else { return isError }
                        return Date().timeIntervalSince(startTime) < 3.0
                    }()
                    if failedEarly || isError {
                        self.handlePlaybackFailure(early: failedEarly)
                        return
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

        // Shutdown MPV completely to stop rendering
        mpvController?.shutdown()

        cleanupExternalSubtitleFiles()
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

            // MPV shutdown already called in stopPlayback(), just release the controller
            // Shutdown is idempotent, so it's safe to call again if not already shut down
            if let controller = self.mpvController, !controller.isShutDown {
                controller.shutdown()
            }
            self.mpvController = nil

            self.stopProgressTracking()
            self.cleanupExternalSubtitleFiles()
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
