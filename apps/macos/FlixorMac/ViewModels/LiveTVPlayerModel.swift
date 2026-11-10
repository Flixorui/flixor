//
//  LiveTVPlayerModel.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Live playback on the shared mpv
//  engine, with xtream-web's verified source failover (docs/stream-failover.md):
//  Auto moves to the next verified source after a fatal error or 25 seconds
//  without startup or progress, tries each source once, then shows an error.
//  A pinned source surfaces its error instead. Pause never counts as a stall.
//

#if FLIXOR_LIVE_TV
import Foundation
import IOKit.pwr_mgt

@MainActor
final class LiveTVPlayerModel: ObservableObject {
    enum State: Equatable { case idle, starting, playing, failed(String) }

    @Published private(set) var controller: MPVPlayerController?
    @Published private(set) var channel: LiveChannel?
    @Published private(set) var state: State = .idle
    @Published private(set) var isPaused = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentSourceId: String?
    /// nil = Auto.
    @Published private(set) var pinnedSourceId: String?
    @Published private(set) var audioTracks: [MPVTrack] = []
    @Published private(set) var subtitleTracks: [MPVTrack] = []
    @Published var volume: Double = 100 { didSet { controller?.setVolume(volume) } }
    @Published var isMuted = false { didSet { controller?.setMute(isMuted) } }

    static let stallTimeout: TimeInterval = 25

    private var failed: Set<String> = []
    private var lastProgressAt = Date()
    private var startedPlayback = false
    private var lastTimePos: Double?
    /// True from loadfile until mpv starts the new file, so a late error from
    /// the replaced file is not blamed on the new source.
    private var awaitingFileStart = false
    private var watchdog: Timer?
    private var loadGeneration = 0
    private var sleepAssertion: IOPMAssertionID = 0

    var sourceIds: [String] { channel?.sourceIds ?? [] }

    var sourceIndexLabel: String? {
        guard let channel, channel.sources.count > 1, let current = currentSourceId,
              let index = channel.sourceIds.firstIndex(of: current) else { return nil }
        return "\(index + 1) of \(channel.sources.count)"
    }

    // MARK: Lifecycle

    func play(_ channel: LiveChannel) {
        let sameChannel = self.channel?.id == channel.id && self.channel?.referenceName == channel.referenceName
        if sameChannel, state == .playing || state == .starting { return }
        self.channel = channel
        failed = []
        pinnedSourceId = nil
        audioTracks = []
        subtitleTracks = []
        ensureController()
        guard let first = LiveTVLineupBuilder.nextSource(channel.sourceIds, failed: failed) else {
            state = .failed("This channel has no playable source.")
            return
        }
        load(sourceId: first)
        preventDisplaySleep(true)
    }

    /// Retry resets the attempted set (stream-failover.md).
    func retry() {
        guard let channel else { return }
        failed = []
        if let pinned = pinnedSourceId { load(sourceId: pinned) }
        else if let first = channel.sourceIds.first { load(sourceId: first) }
    }

    /// Source menu: nil = Auto, otherwise pin that source.
    func selectSource(_ id: String?) {
        guard let channel else { return }
        pinnedSourceId = id
        failed = []
        load(sourceId: id ?? currentSourceId ?? channel.sourceIds.first ?? channel.id)
    }

    /// Jumps back to the live edge by reopening the current source.
    func goLive() {
        guard let current = currentSourceId else { return }
        load(sourceId: current)
    }

    func togglePause() {
        guard let controller else { return }
        controller.togglePlayPause()
    }

    func stop() {
        loadGeneration += 1
        watchdog?.invalidate(); watchdog = nil
        if let controller, !controller.isShutDown { controller.shutdown() }
        controller = nil
        channel = nil
        currentSourceId = nil
        state = .idle
        preventDisplaySleep(false)
    }

    // MARK: Tracks

    func refreshTracks() {
        guard let controller else { return }
        audioTracks = controller.getAudioTracks()
        subtitleTracks = controller.getSubtitleTracks()
    }

    func selectAudio(_ id: Int) { controller?.setAudioTrack(id); refreshTracksSoon() }
    func selectSubtitle(_ id: Int?) {
        if let id { controller?.setSubtitleTrack(id) } else { controller?.disableSubtitles() }
        refreshTracksSoon()
    }

    private func refreshTracksSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshTracks() }
    }

    // MARK: Loading and failover

    private func ensureController() {
        guard controller == nil || controller?.isShutDown == true else { return }
        let c = MPVPlayerController()
        c.onPropertyChange = { [weak self] name, value in
            Task { @MainActor [weak self] in self?.handleProperty(name, value) }
        }
        c.onEvent = { [weak self] name in
            Task { @MainActor [weak self] in self?.handleEvent(name) }
        }
        controller = c
    }

    private func load(sourceId: String) {
        guard let account = LiveTVStore.shared.account,
              let url = XtreamClient(account: account).streamURL(sourceId: sourceId) else {
            state = .failed(LiveTVError.notConfigured.localizedDescription)
            return
        }
        ensureController()
        loadGeneration += 1
        let generation = loadGeneration
        currentSourceId = sourceId
        state = .starting
        startedPlayback = false
        lastTimePos = nil
        lastProgressAt = Date()
        awaitingFileStart = true
        audioTracks = []
        subtitleTracks = []
        startWatchdog()
        Task { [weak self] in
            guard let self, let controller = self.controller else { return }
            var waited = 0
            while !controller.isInitialized && waited < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            guard generation == self.loadGeneration else { return }
            guard controller.isInitialized else {
                self.state = .failed("The video engine did not start.")
                return
            }
            controller.setVolume(self.volume)
            controller.setMute(self.isMuted)
            // The URL carries the account credentials: log only the source id.
            controller.loadFile(url.absoluteString, logLabel: "live:\(sourceId)")
            AppLogger.shared.info("[LiveTV] Playing \(self.channel?.displayName ?? "") source \(sourceId)")
        }
    }

    /// A fatal error or a stall on the current source.
    private func sourceFailed(reason: String) {
        guard let channel, let current = currentSourceId else { return }
        watchdog?.invalidate(); watchdog = nil
        AppLogger.shared.info("[LiveTV] Source \(current) failed: \(reason)")
        if pinnedSourceId != nil {
            state = .failed("This source is not playing (\(reason)). Choose another source or Retry.")
            return
        }
        failed.insert(current)
        if let next = LiveTVLineupBuilder.nextSource(channel.sourceIds, failed: failed) {
            load(sourceId: next)
        } else {
            state = .failed(channel.sources.count > 1
                ? "None of the \(channel.sources.count) verified sources is playing right now."
                : "This channel is not playing right now. The provider may be down or at its connection limit.")
            controller?.stop()
        }
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkStall() }
        }
    }

    private func checkStall() {
        guard state == .starting || state == .playing else { return }
        // Paused playback does not trigger stall switching.
        if isPaused { lastProgressAt = Date(); return }
        if Date().timeIntervalSince(lastProgressAt) >= Self.stallTimeout {
            sourceFailed(reason: startedPlayback ? "no progress for 25 seconds" : "no startup within 25 seconds")
        }
    }

    private func handleProperty(_ name: String, _ value: Any?) {
        switch name {
        case "time-pos":
            guard let t = value as? Double else { return }
            if let last = lastTimePos, t > last {
                lastProgressAt = Date()
                if !startedPlayback {
                    startedPlayback = true
                    state = .playing
                    refreshTracks()
                }
            }
            lastTimePos = t
        case "pause":
            isPaused = (value as? Bool) ?? false
        case "paused-for-cache":
            isBuffering = (value as? Bool) ?? false
        case "track-list":
            refreshTracks()
        default:
            break
        }
    }

    private func handleEvent(_ name: String) {
        if name == "file-started" { awaitingFileStart = false; return }
        if awaitingFileStart { return }
        switch name {
        case "file-error":
            sourceFailed(reason: "stream error")
        case "file-ended":
            // A live stream that "ends" has dropped.
            if state == .playing || state == .starting { sourceFailed(reason: "stream ended") }
        case "file-loaded":
            refreshTracks()
        default:
            break
        }
    }

    // MARK: Display sleep

    private func preventDisplaySleep(_ on: Bool) {
        if on, sleepAssertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Flixor Live TV playback" as CFString, &sleepAssertion)
        } else if !on, sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }
}
#endif
