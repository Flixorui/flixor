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
    /// Playback position, updated about 4 times a second. Not published: views that
    /// show it observe `playbackClock`. For the exact position use
    /// `mpvController?.currentTimePosition`.
    var currentTime: TimeInterval = 0 {
        didSet {
            if playbackClock.time != currentTime { playbackClock.time = currentTime }
        }
    }
    let playbackClock = PlaybackClock()
    @Published var duration: TimeInterval = 0 {
        didSet { invalidateNextEpisodeTrigger() }
    }
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
    /// Held by `statsModel`, which only the stats overlay observes.
    var performanceStats: PerformanceStats? {
        get { statsModel.stats }
        set { statsModel.stats = newValue }
    }
    let statsModel = PlaybackStatsModel()
    var performanceStatsTimer: Timer?

    // Chapter navigation
    @Published var chapters: [MPVChapter] = [] {
        didSet { invalidateNextEpisodeTrigger() }
    }
    @Published var currentChapterIndex: Int?

    // Subtitle styling (persisted)
    @Published var subtitleFontSize: Int = UserDefaults.standard.integer(forKey: "subtitleFontSize") == 0 ? 55 : UserDefaults.standard.integer(forKey: "subtitleFontSize")
    @Published var subtitleBorderSize: Double = UserDefaults.standard.double(forKey: "subtitleBorderSize") == 0 ? 3.0 : UserDefaults.standard.double(forKey: "subtitleBorderSize")
    @Published var subtitleBackgroundOpacity: Double = UserDefaults.standard.double(forKey: "subtitleBackgroundOpacity")

    // Audio/Subtitle sync offset
    @Published var audioDelay: Double = 0.0
    @Published var subtitleDelay: Double = 0.0

    // Markers (intro/credits) - no high-frequency updates
    @Published var markers: [PlayerMarker] = [] {
        didSet { invalidateNextEpisodeTrigger() }
    }
    @Published var currentMarker: PlayerMarker? = nil

    // Auto-skip state
    var autoSkipTriggeredMarkers: Set<String> = []
    var autoSkipTimer: Timer?
    @Published var autoSkipCountdown: Int? = nil  // Countdown seconds shown to user

    // Next episode & season episodes
    @Published var nextEpisode: EpisodeMetadata? = nil {
        didSet { invalidateNextEpisodeTrigger() }
    }
    @Published var seasonEpisodes: [EpisodeMetadata] = []
    @Published var nextEpisodeCountdown: Int? = nil
    var nextEpisodeCountdownTimer: Timer?
    /// The user cancelled the countdown. It stays off until they seek back before
    /// the trigger point or a new title loads.
    var nextEpisodeCountdownDismissed = false
    /// One-shot: this player has already navigated to another Plex episode.
    var didNavigateToEpisode = false
    /// Cached countdown trigger point, rebuilt when markers, chapters or duration change.
    var nextEpisodeTrigger: NextEpisodeTriggerPoint?
    /// Playback position of the last countdown check (checked about once a second).
    var lastNextEpisodeCheckTime: TimeInterval?
    /// `start()` ran.
    private(set) var hasStarted = false
    /// Trailing progress report after seeks (see `seek(to:)`).
    var seekProgressReportTask: Task<Void, Never>?

    // MARK: - Stream engine state (skip segments, stream next-episode, source recovery)
    // New stored properties for that work go directly below this line.

    // Episode panel (season browsing) and the in-player sources list.
    @Published var episodeBrowserSeasons: [Int] = []
    @Published var episodeBrowserSeason: Int? = nil
    @Published var episodeBrowserEpisodes: [EpisodeMetadata] = []
    @Published var isLoadingEpisodeBrowser = false
    @Published var isLoadingStreamSources = false
    var episodeBrowserPlexSeasonKeys: [Int: String] = [:]
    var episodeBrowserTask: Task<Void, Never>?
    var streamSourcesRefreshedKey: String?
    var nextEpisodeWaitTask: Task<Void, Never>?

    /// Community skip segments (IntroDB / AniSkip / Anime-Skip) for the current item;
    /// merged into `markers` for types Plex didn't provide.
    @Published var communitySkipSegments: [SkipSegment] = []
    /// Plex markers as fetched, so community data only fills missing types.
    var plexMarkersSnapshot: [PlayerMarker] = []
    /// Open-ended community segments that become markers once the duration is known.
    var communityMarkersAwaitDuration = false
    var skipSegmentsTask: Task<Void, Never>?
    /// Content key the stream skip segments / next-episode data were loaded for.
    var streamEngineContentKey: String?

    // Next episode for addon streams
    var streamNextEpisodeTask: Task<Void, Never>?
    var streamNextEpisodeInfo: StreamEpisodeInfo?
    var streamSeasonEpisodeInfos: [StreamEpisodeInfo] = []
    /// Prefetched source lookup for the next episode, keyed by "season:episode".
    var nextEpisodeSourceTask: Task<StreamEpisodeSourceOutcome, Never>?
    var nextEpisodeSourceKey: String?
    @Published var isResolvingNextEpisode = false
    /// Opens the Stremio sources picker for an episode/title. Wired by the player
    /// view; used when no source can be picked automatically.
    var onOpenStremioSources: ((StremioSourcesDestination) -> Void)?
    /// Set when the user has to pick a source (next episode couldn't be resolved,
    /// or recovery gave up). The error overlay can offer "Choose another source",
    /// which calls `openSourcesPicker()`.
    @Published var sourcesPickerDestination: StremioSourcesDestination?

    // Dead-link recovery for addon streams
    /// Background work status (recovering a source, finding the next episode's source).
    @Published var streamEngineStatus: StreamEngineStatus?
    /// True after recovery gave up; the error overlay should offer "Choose another source".
    @Published var streamRecoveryFailed = false
    var streamRecoveryAttempts = 0
    let maxStreamRecoveryAttempts = 2
    var isPerformingStreamRecovery = false
    var streamLoadWatchdog: Task<Void, Never>?
    var streamStallWatchdog: Task<Void, Never>?
    var failedStreamURLs: Set<String> = []
    /// Sources re-fetched during recovery (fetched once per playback).
    var streamRecoveryResults: [StremioAddonStreamResult]?

    /// The player view is going away: nothing may schedule hiding the cursor.
    /// Lives here, not in @State, so it still reads true after the view is gone.
    var isLeavingPlayer = false

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
    /// `forcedResumeSeconds` continues a running playback (source recovery or
    /// switch), so the "almost finished, restart" rule doesn't apply to it.
    var forcedResumeIsExact = false

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
    // Aspect mode (see PlayerViewModel+Aspect.swift)
    @Published var aspectMode: PlayerAspectMode = UserDefaults.standard.playerAspectMode
    @Published var zoomStep: Int = UserDefaults.standard.playerZoomStep
    // Hold-to-speed-up (see PlayerViewModel+Controls.swift)
    @Published var isSpeedBoostActive = false
    var speedBeforeBoost: Float?
    // Subtitle cues for cue-based sync (see PlayerViewModel+SubtitleEngine.swift)
    @Published var subtitleCues: [SubtitleCue] = []
    @Published var recentSubtitleCues: [SubtitleCue] = []
    /// Cues collected from embedded tracks; copied to `recentSubtitleCues` only while
    /// the sync panel is open, so a shown cue doesn't redraw the player.
    var observedSubtitleCues: [SubtitleCue] = []
    var isSubtitleSyncPanelOpen = false {
        didSet {
            if isSubtitleSyncPanelOpen { recentSubtitleCues = observedSubtitleCues }
        }
    }
    @Published var subtitleCueSource: SubtitleCueSource = .none {
        didSet { updateSubtitleCueObservation() }
    }
    @Published var subtitleFilterSDH: Bool = UserDefaults.standard.subtitleFilterSDH
    @Published var subtitleAppearance: SubtitleAppearance = SubtitleAppearance.fromDefaults()
    var subtitleCueLoadTask: Task<Void, Never>?
    /// An external subtitle file is being loaded; cues are observed meanwhile in case it fails.
    var isLoadingSubtitleCueFile = false
    var subtitleCueFilePath: String?
    var subtitleCueTrackId: Int?
    var subtitleHashTask: Task<Void, Never>?
    var subtitleHashLookupURL: String?
    var languageSelectionTask: Task<Void, Never>?
    let engineObservers = PlaybackEngineObserverBag()


    init(item: MediaItem) {
        self.item = item
    }

    /// Starts loading and registers Now Playing. Called once by the player view when
    /// it appears; the initializers do no work, so a view model SwiftUI builds and
    /// throws away never starts a load.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
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
            grandparentTitle: streamItem.mediaType == .episode ? (streamItem.showTitle ?? streamItem.title) : nil,
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
                self.error = String(localized: "MPV controller not initialized")
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
                self.error = String(localized: "MPV failed to initialize")
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
        // The controller calls back on the main thread (time-pos about 4 times a second).
        controller.onPropertyChange = { [weak self] property, value in
            Self.runOnMain { [weak self] in
                guard let self = self else { return }
                switch property {
                case "time-pos":
                    if let time = value as? Double {
                        self.currentTime = time
                        // Check for markers whenever time updates
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
                case "track-list":
                    // Tracks mpv added or reselected (external subtitles, selection)
                    self.refreshTrackListsFromEngine()
                case "paused-for-cache":
                    if let buffering = value as? Bool {
                        self.handleStreamBuffering(buffering)
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
            Self.runOnMain { [weak self] in
                guard let self = self else { return }
                print("🎯 [Player] MPV event: \(event)")
                switch event {
                case "file-started":
                    print("📺 [Player] MPV file started")
                    self.fileStartTime = Date()
                case "file-loaded":
                    print("✅ [Player] MPV file loaded")
                    self.isLoading = false
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
                    if let path = self.mpvController?.currentPath {
                        self.thumbnailGenerator?.onVideoLoaded(url: path)
                    }
                case "playback-restart":
                    print("▶️ [Player] MPV playback started")
                    self.streamLoadWatchdog?.cancel()
                    self.streamLoadWatchdog = nil
                    self.isPlaying = true
                    self.isLoading = false
                    self.enableDisplaySleep()
                    // Start Trakt scrobbling
                    self.startTraktScrobble()
                    // Also follows every seek: the position is current again.
                    self.updateNowPlayingInfo()
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
                    // An EOF well before the known duration means the stream was cut
                    // off (e.g. a dropped connection), not that the user finished it.
                    // Tolerant margin: container durations can be slightly off.
                    if self.duration > 0, self.duration - self.currentTime > max(120, self.duration * 0.15) {
                        print("⚠️ [Player] File ended at \(Int(self.currentTime))s of \(Int(self.duration))s; treating as interrupted")
                        self.handlePlaybackFailure(early: false)
                        return
                    }
                    print("✅ [Player] MPV playback finished")
                    self.directPlayRetryCount = 0  // Reset counter on successful playback
                    self.handlePlaybackEnd()
                case "file-stopped":
                    // Replaced by another file (quality/source change) or player closed:
                    // never a completion, never a failure.
                    break
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

    /// Runs `body` at once when called on the main thread (MPVPlayerController's
    /// callbacks are), otherwise in a main-actor task.
    nonisolated static func runOnMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }

    // MARK: - Stop Playback

    func stopPlayback() {
        print("🛑 [Player] Stopping playback")

        // Stop progress tracking immediately
        stopProgressTracking()
        seekProgressReportTask?.cancel()
        seekProgressReportTask = nil

        // Cancel next episode countdown
        nextEpisodeCountdownTimer?.invalidate()
        nextEpisodeCountdownTimer = nil
        nextEpisodeCountdown = nil
        cancelStreamWatchdogs()
        // Disable display sleep prevention
        disableDisplaySleep()

        // Clear Now Playing info
        clearNowPlayingInfo()

        // Shutdown MPV completely to stop rendering
        mpvController?.shutdown()
        // And the seek-bar thumbnail instance with its connection
        thumbnailGenerator?.shutdown()

        cleanupExternalSubtitleFiles()
    }

    func onDisappear() {
        // Stop performance stats polling
        stopPerformanceStatsPolling()
        // The final report below covers a pending seek report.
        seekProgressReportTask?.cancel()
        seekProgressReportTask = nil
        thumbnailGenerator?.shutdown()
        // Closed without stopPlayback() (which already did this): drop the remote-command
        // targets, whose handlers would otherwise outlive the player.
        if !remoteCommandTargets.isEmpty { clearNowPlayingInfo() }

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
            self.thumbnailGenerator = nil

            self.stopProgressTracking()
            self.cleanupExternalSubtitleFiles()
        }
    }

    func retry() {
        print("🔄 [Player] Retrying playback")
        guard hasStarted else { start(); return }
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
