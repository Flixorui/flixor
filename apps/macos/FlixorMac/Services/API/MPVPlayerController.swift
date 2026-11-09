//
//  MPVPlayerController.swift
//  FlixorMac
//
//  MPV player controller. Video goes through mpv's vo_avfoundation into an
//  AVSampleBufferDisplayLayer, as in plezy: https://github.com/edde746/plezy
//

import Foundation
import AppKit
import AVFoundation
import Libmpv

class MPVPlayerController {
    // MARK: - Properties

    /// The mpv handle
    private var mpv: OpaquePointer?

    /// The layer vo_avfoundation renders into (passed to mpv as "wid")
    private weak var videoLayer: MPVVideoLayer?

    /// Serial queue for every mpv call made after start-up. vo_avfoundation waits on
    /// the main thread while it reconfigures, so the main thread must never block on
    /// mpv: setters and commands run here, and reads come from the caches below, which
    /// mpv's property notifications keep current. Teardown runs here too, after
    /// everything queued before it.
    private let apiQueue = DispatchQueue(label: "com.flixor.mpv.api", qos: .userInitiated)

    /// Values mirrored from mpv for main-thread readers.
    private let cacheLock = NSLock()
    private var cachedTracks: [MPVTrack] = []
    private var cachedChapters: [MPVChapter] = []
    private var cachedChapter: Int?
    private var cachedPaused = false
    private var cachedSpeed: Double?
    private var cachedAudioDelay = 0.0
    private var cachedSubtitleDelay = 0.0
    private var cachedPath: String?

    /// Run once mpv is destroyed (see `shutdown(completion:)`).
    private var shutdownCompletions: [() -> Void] = []
    private var isFullyShutDown = false

    /// Reference to the window for screen info
    private weak var window: NSWindow?

    /// Dispatch queue for mpv events
    private lazy var queue = DispatchQueue(label: "com.flixor.mpv.controller", qos: .userInitiated)

    /// Shutdown flag to prevent double-shutdown
    private var isShuttingDown = false
    private let shutdownLock = NSLock()

    /// Public property to check if shut down
    var isShutDown: Bool {
        return isShuttingDown
    }

    /// HDR state
    private var hdrEnabled = true
    private var lastSigPeak: Double = 0.0
    private var lastGamma: String?
    private var lastPrimaries: String?
    private var isHDRModeActive = false

    /// Callback for property changes
    var onPropertyChange: ((String, Any?) -> Void)?

    /// Callback for events
    var onEvent: ((String) -> Void)?

    /// Callback for HDR detection (sig-peak based)
    var onHDRDetected: ((Bool, Double) -> Void)?

    /// Called (main thread) when mpv starts showing a subtitle cue. Set by the
    /// view model to collect recent cues of embedded tracks for cue-based sync.
    var onSubtitleCueShown: ((MPVShownSubtitleCue) -> Void)?

    /// Callback for thumbnail info updates
    var onThumbnailInfo: ((ThumbnailInfo) -> Void)?

    /// Current thumbnail information
    private(set) var thumbnailInfo: ThumbnailInfo?

    /// Initialization state
    private(set) var isInitialized = false

    // MARK: - Initialization

    init() {
        // Don't setup MPV here - wait for initialize(in:layer:)
    }

    deinit {
        if !isShuttingDown && mpv != nil {
            print("⚠️ [MPV] Cleanup in deinit (should have been called explicitly)")
            shutdown()
        }
    }

    // MARK: - Setup

    /// Initialize mpv rendering into `layer`. Must be called before any playback.
    func initialize(in window: NSWindow, layer: MPVVideoLayer) -> Bool {
        guard !isInitialized else {
            print("[MPV] Already initialized")
            return true
        }

        self.window = window
        self.videoLayer = layer

        // Create mpv instance
        mpv = mpv_create()
        guard mpv != nil else {
            print("❌ [MPV] Failed to create mpv instance")
            return false
        }

        // Configure logging - use debug level to see GPU initialization
        #if DEBUG
        checkError(mpv_request_log_messages(mpv, "v"))
        #else
        checkError(mpv_request_log_messages(mpv, "warn"))
        #endif

        // vo_avfoundation renders into this AVSampleBufferDisplayLayer and adds its
        // subtitle (OSD) layer beside it. It replaced gpu-next on Vulkan/MoltenVK, whose
        // teardown crashed in MoltenVK's command-buffer completion handler.
        var layerRef = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layerRef))
        setOptionStringWithLog("vo", "avfoundation")
        // Host-clock presentation: frames carry their display time against a free-running
        // timebase, so seeks and stops never move the layer's clock. With media time,
        // macOS 27 can stop updating the screen until the clock catches up (plezy #2823).
        setOptionStringWithLog("avfoundation-presentation", "host")
        // Subtitles stay in their own layer instead of a Core Image composite per frame.
        setOptionStringWithLog("avfoundation-composite-osd", "no")
        setOptionStringWithLog("hwdec", "videotoolbox")
        setOptionStringWithLog("hwdec-software-fallback", "yes")
        setOptionStringWithLog("target-colorspace-hint", "auto")
        // No user config and no scripts. This mpv includes LuaJIT, whose compiled code
        // the hardened runtime kills the app for (executable memory without MAP_JIT).
        setOptionStringWithLog("config", "no")
        for option in Self.builtInScriptOptions {
            setOptionStringWithLog(option, "no")
        }

        // Audio output: prefer AVFoundation, with CoreAudio as the fallback. mpv 0.40's
        // CoreAudio output could leave a device listener on freed state when it failed
        // to set up, and its AVFoundation output leaked a buffer each time it ran dry
        // (fixed in 0.41, which this build of mpv includes).
        setOptionStringWithLog("ao", "avfoundation,coreaudio")

        // Initialize MPV (BEFORE wakeup callback - plezy pattern)
        let status = mpv_initialize(mpv)
        if status < 0 {
            print("❌ [MPV] Failed to initialize: \(String(cString: mpv_error_string(status)))")
            mpv_terminate_destroy(mpv)
            mpv = nil
            return false
        }

        // Set wakeup callback AFTER mpv_initialize (plezy pattern)
        mpv_set_wakeup_callback(mpv, { ctx in
            let controller = Unmanaged<MPVPlayerController>.fromOpaque(ctx!).takeUnretainedValue()
            controller.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        // Observe properties after initialization
        observeProperties()

        // Configure additional options after initialization
        configureAdditionalOptions()

        isInitialized = true
        print("✅ [MPV] Initialized with vo_avfoundation")
        return true
    }

    /// Switches for mpv's script folders and each of its built-in Lua scripts.
    /// `load-scripts` alone leaves the built-in ones (stats, console, auto_profiles,
    /// select, positioning, commands, context_menu) running. Some names differ
    /// between mpv versions; unknown ones are rejected harmlessly.
    static let builtInScriptOptions = [
        "load-scripts", "ytdl", "osc", "load-stats-overlay", "load-console", "load-osd-console",
        "load-auto-profiles", "load-select", "load-positioning", "load-commands", "load-context-menu",
    ]

    /// FFmpeg HTTP reconnect options (MPVKit ships FFmpeg 8.0, which supports all of them).
    /// - reconnect / reconnect_streamed: reconnect dropped connections, also for non-seekable streams.
    /// - reconnect_on_network_error: also reconnect when the TCP/TLS connection fails (not only on EOF).
    /// - reconnect_on_http_error: retry on 408 (timeout), 429 (rate limited) and any 5xx. Auth and
    ///   not-found errors (401/403/404) still fail at once, so Plex direct-play -> HLS fallback and
    ///   expired-token retries are unaffected. The list is wrapped in [...] because mpv's key=value
    ///   list is itself comma separated.
    /// - reconnect_delay_max=15: exponential backoff 0, 1, 3, 7, 15 s before giving up.
    /// reconnect_at_eof is deliberately NOT set: it would loop at the real end of a file
    /// (and on finite HLS playlists).
    static let reconnectOptions = "reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,"
        + "reconnect_on_http_error=[408,429,5xx],reconnect_delay_max=15"
    /// Same rules with a short backoff (0, 1, 3 s) for Plex, so an unreachable
    /// endpoint fails fast and the direct-play -> HLS fallback isn't delayed.
    static let plexReconnectOptions = "reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,"
        + "reconnect_on_http_error=[408,429,5xx],reconnect_delay_max=3"
    /// Previous options, used only if mpv rejects `reconnectOptions`.
    static let basicReconnectOptions = "reconnect=1,reconnect_streamed=1,reconnect_delay_max=5"

    private func configureAdditionalOptions() {
        // Additional properties set AFTER mpv_initialize
        // Use mpv_set_property_string for post-init settings

        // Keep aspect ratio
        mpv_set_property_string(mpv, "keepaspect", "yes")

        // Disable on-screen display
        mpv_set_property_string(mpv, "osd-level", "0")

        // Network/HTTP options for Plex streaming
        // TLS verification is decided per file in loadFile(_:headers:verifyTLS:)
        // (off for Plex, which can use custom certs; on for addon streams).
        mpv_set_property_string(mpv, "tls-verify", "no")
        mpv_set_property_string(mpv, "network-timeout", "30")
        if mpv_set_property_string(mpv, "stream-lavf-o", Self.reconnectOptions) < 0 {
            // Never end up without reconnects if this mpv rejects the extended list.
            mpv_set_property_string(mpv, "stream-lavf-o", Self.basicReconnectOptions)
            print("⚠️ [MPV] Extended reconnect options rejected, using basic reconnect")
        }
        print("[MPV] Network options configured")

        // Apply user settings from UserDefaults
        if let mpv { applyUserSettings(on: mpv) }

        // thumbfast.lua is not loaded: seek-bar thumbnails come from ThumbnailMPVPlayer,
        // and with Lua now available the script would try to start an external mpv.

        print("✅ [MPV] Additional options configured")
    }

    /// Apply user settings from UserDefaults to MPV
    private func applyUserSettings(on mpv: OpaquePointer) {
        let defaults = UserDefaults.standard

        // Buffer size (demuxer-max-bytes)
        let bufferMB = defaults.bufferSize
        mpv_set_property_string(mpv, "demuxer-max-bytes", "\(bufferMB)MiB")
        mpv_set_property_string(mpv, "demuxer-max-back-bytes", "\(bufferMB / 2)MiB")
        print("[MPV] Buffer size set to \(bufferMB)MiB")

        // Hardware decoding
        let hwdec = defaults.hardwareDecoding ? "videotoolbox" : "no"
        mpv_set_property_string(mpv, "hwdec", hwdec)
        print("[MPV] Hardware decoding: \(hwdec)")

        // HDR setting
        hdrEnabled = defaults.hdrEnabled
        mpv_set_property_string(mpv, "target-colorspace-hint", hdrEnabled ? "auto" : "no")
        print("[MPV] HDR enabled: \(hdrEnabled)")

        // Max volume (for volume boost)
        mpv_set_property_string(mpv, "volume-max", "\(defaults.maxVolume)")
        print("[MPV] Max volume: \(defaults.maxVolume)%")

        // Default playback speed
        if defaults.defaultPlaybackSpeed != 1.0 {
            var speed = defaults.defaultPlaybackSpeed
            mpv_set_property(mpv, "speed", MPV_FORMAT_DOUBLE, &speed)
            print("[MPV] Default playback speed: \(speed)x")
        }

        // Saved volume
        var volume = defaults.playerVolume
        mpv_set_property(mpv, "volume", MPV_FORMAT_DOUBLE, &volume)

        // Apply custom MPV config entries
        let customEntries = defaults.getEnabledMpvConfigEntries()
        for entry in customEntries {
            mpv_set_property_string(mpv, entry.key, entry.value)
            print("[MPV] Custom config: \(entry.key)=\(entry.value)")
        }

        print("✅ [MPV] User settings applied")
    }

    /// Refresh settings at runtime (call when settings change)
    func refreshUserSettings() {
        perform { [weak self] mpv in self?.applyUserSettings(on: mpv) }
    }

    private func observeProperties() {
        guard mpv != nil else { return }

        // Observe playback state
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "volume", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "mute", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "seeking", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)

        // CRITICAL: Observe HDR/EDR properties (IINA approach)
        mpv_observe_property(mpv, 0, "video-params/sig-peak", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "video-params/gamma", MPV_FORMAT_STRING)
        mpv_observe_property(mpv, 0, "video-params/primaries", MPV_FORMAT_STRING)

        // Current subtitle text, used to collect recently shown cues (cue-based sync)
        mpv_observe_property(mpv, 0, "sub-text", MPV_FORMAT_STRING)

        // Mirrored for main-thread readers (see apiQueue)
        mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE)
        mpv_observe_property(mpv, 0, "chapter-list", MPV_FORMAT_NODE)
        mpv_observe_property(mpv, 0, "chapter", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "speed", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "audio-delay", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "sub-delay", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "path", MPV_FORMAT_STRING)
    }

    // MARK: - Threading helpers

    /// Runs `body` on apiQueue with the current handle. Teardown is queued on the
    /// same queue, so the handle stays valid for everything queued before it.
    private func perform(_ body: @escaping (OpaquePointer) -> Void) {
        guard let handle = mpv, !isShuttingDown else { return }
        apiQueue.async { body(handle) }
    }

    private func setString(_ name: String, _ value: String) {
        perform { mpv_set_property_string($0, name, value) }
    }

    @discardableResult
    private func withCache<T>(_ body: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return body()
    }

    // MARK: - HDR/EDR

    /// vo_avfoundation hands HDR frames to the display layer as they are, so HDR is the
    /// layer's EDR mode: on, it shows highlights above SDR white; off, macOS tone-maps
    /// them to SDR. HDR content is PQ or HLG, or reports a peak above SDR white.
    private func configureHDRMode() {
        guard let layer = videoLayer, let gamma = lastGamma else { return }
        let isHDRContent = gamma == "pq" || gamma == "hlg" || lastSigPeak > 1.0
        let shouldEnableHDR = hdrEnabled && isHDRContent
        guard shouldEnableHDR != isHDRModeActive else { return }
        isHDRModeActive = shouldEnableHDR
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if #available(macOS 26.0, *) {
            layer.preferredDynamicRange = shouldEnableHDR ? .high : .standard
        } else if #available(macOS 14.0, *) {
            layer.wantsExtendedDynamicRangeContent = shouldEnableHDR
        }
        CATransaction.commit()
        print("🎨 [MPV] HDR Mode: \(shouldEnableHDR) (gamma: \(gamma), primaries: \(lastPrimaries ?? "?"), sigPeak: \(lastSigPeak))")
    }

    /// Enable or disable HDR mode
    func setHDREnabled(_ enabled: Bool) {
        hdrEnabled = enabled
        print("[MPV] HDR user preference: \(enabled)")
        setString("target-colorspace-hint", enabled ? "auto" : "no")
        DispatchQueue.main.async {
            self.configureHDRMode()
        }
    }

    /// Reset HDR state (call when loading new file).
    /// `isHDRModeActive` is kept on purpose: it describes how the layer is
    /// configured right now, so an SDR file after an HDR one switches back to SDR
    /// once its video params arrive.
    func resetHDRState() {
        lastGamma = nil
        lastPrimaries = nil
        lastSigPeak = 0.0
    }

    // MARK: - Playback Control

    /// - Parameter verifyTLS: Verify HTTPS certificates. Pass `false` for Plex
    ///   (custom/self-signed certs). Hosts on the local network are never verified.
    func loadFile(_ url: String, headers: [String: String]? = nil, verifyTLS: Bool = true) {
        guard mpv != nil else {
            print("❌ [MPV] Cannot load file: mpv not initialized")
            return
        }

        // Reset HDR state for new file
        resetHDRState()

        let shouldVerify = verifyTLS && !Self.isLocalNetworkURL(url)
        // verifyTLS == false identifies Plex (see the parameter docs).
        let reconnect = verifyTLS ? Self.reconnectOptions : Self.plexReconnectOptions
        // HTTP headers (required for some Plex servers and addon streams).
        // Always (re)set the list: mpv keeps `http-header-fields` across files,
        // so loading without headers must clear the previous file's headers.
        let headerFields = Self.httpHeaderFieldsValue(headers)
        if let headers, !headers.isEmpty {
            print("📺 [MPV] HTTP headers set: \(headers.count) headers")
        }
        withCache { cachedPath = nil }

        print("📺 [MPV] Loading file: \(url)")
        perform { mpv in
            mpv_set_property_string(mpv, "tls-verify", shouldVerify ? "yes" : "no")
            if mpv_set_property_string(mpv, "stream-lavf-o", reconnect) < 0 {
                mpv_set_property_string(mpv, "stream-lavf-o", Self.basicReconnectOptions)
            }
            mpv_set_property_string(mpv, "http-header-fields", headerFields)
            let status = mpv_command_string(mpv, "loadfile \"\(url)\" replace")
            if status < 0 {
                print("❌ [MPV] Failed to load file: \(String(cString: mpv_error_string(status)))")
            }
        }
    }

    /// mpv string-list value for `http-header-fields`. Items are separated by
    /// commas, so a comma inside a header value is escaped as `\,` (mpv's list escape).
    /// Returns "" (empty list) when there are no headers.
    static func httpHeaderFieldsValue(_ headers: [String: String]?) -> String {
        guard let headers, !headers.isEmpty else { return "" }
        return headers.keys.sorted().map { key in
            "\(key): \(headers[key] ?? "")".replacingOccurrences(of: ",", with: "\\,")
        }.joined(separator: ",")
    }

    /// True for localhost, *.local and private IPv4 ranges (self-hosted addons, LAN servers).
    static func isLocalNetworkURL(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    func play() {
        withCache { cachedPaused = false }
        setProperty("pause", value: false)
    }

    func pause() {
        withCache { cachedPaused = true }
        setProperty("pause", value: true)
    }

    func togglePlayPause() {
        let isPaused = self.isPaused
        withCache { cachedPaused = !isPaused }
        setProperty("pause", value: !isPaused)
        print("✅ [MPV] Toggled pause: \(isPaused) -> \(!isPaused)")
    }

    /// Last known pause state (see apiQueue).
    var isPaused: Bool { withCache { cachedPaused } }

    /// Last known playback speed, nil before mpv reported one.
    var currentSpeed: Double? { withCache { cachedSpeed } }

    /// Path or URL of the loaded file, nil until it has loaded.
    var currentPath: String? { withCache { cachedPath } }

    func seek(to seconds: Double) {
        setProperty("time-pos", value: seconds)
    }

    func seekRelative(seconds: Double) {
        command(.seek, args: ["\(seconds)", "relative"])
    }

    func setVolume(_ volume: Double) {
        setProperty("volume", value: volume)
    }

    func setMute(_ muted: Bool) {
        setProperty("mute", value: muted)
    }

    func setSpeed(_ speed: Double) {
        setProperty("speed", value: speed)
    }

    func stop() {
        command(.stop)
    }

    // MARK: - Track Management

    /// All tracks (audio, subtitle, video) of the loaded file, as last reported by mpv.
    func getTrackList() -> [MPVTrack] {
        withCache { cachedTracks }
    }

    /// Parses mpv's `track-list` node.
    private static func parseTracks(_ node: mpv_node) -> [MPVTrack] {
        var tracks: [MPVTrack] = []
        guard node.format == MPV_FORMAT_NODE_ARRAY else { return [] }

        let list = node.u.list.pointee
        let count = Int(list.num)

        for i in 0..<count {
            guard let values = list.values else { continue }
            let trackNode = values[i]

            guard trackNode.format == MPV_FORMAT_NODE_MAP else { continue }

            let trackMap = trackNode.u.list.pointee
            let trackCount = Int(trackMap.num)

            var track = MPVTrack()

            for j in 0..<trackCount {
                guard let keys = trackMap.keys, let values = trackMap.values else { continue }
                let key = String(cString: keys[j]!)
                let value = values[j]

                switch key {
                case "id":
                    if value.format == MPV_FORMAT_INT64 {
                        track.id = Int(value.u.int64)
                    }
                case "type":
                    if value.format == MPV_FORMAT_STRING {
                        track.type = String(cString: value.u.string!)
                    }
                case "src-id":
                    if value.format == MPV_FORMAT_INT64 {
                        track.srcId = Int(value.u.int64)
                    }
                case "title":
                    if value.format == MPV_FORMAT_STRING {
                        track.title = String(cString: value.u.string!)
                    }
                case "lang":
                    if value.format == MPV_FORMAT_STRING {
                        track.lang = String(cString: value.u.string!)
                    }
                case "selected":
                    if value.format == MPV_FORMAT_FLAG {
                        track.selected = value.u.flag != 0
                    }
                case "external":
                    if value.format == MPV_FORMAT_FLAG {
                        track.external = value.u.flag != 0
                    }
                case "default":
                    if value.format == MPV_FORMAT_FLAG {
                        track.isDefault = value.u.flag != 0
                    }
                case "forced":
                    if value.format == MPV_FORMAT_FLAG {
                        track.forced = value.u.flag != 0
                    }
                case "hearing-impaired":
                    if value.format == MPV_FORMAT_FLAG {
                        track.hearingImpaired = value.u.flag != 0
                    }
                case "external-filename":
                    if value.format == MPV_FORMAT_STRING, let str = value.u.string {
                        track.externalFilename = String(cString: str)
                    }
                default:
                    break
                }
            }

            tracks.append(track)
        }

        return tracks
    }

    /// Get available audio tracks
    func getAudioTracks() -> [MPVTrack] {
        return getTrackList().filter { $0.type == "audio" }
    }

    /// Get available subtitle tracks
    func getSubtitleTracks() -> [MPVTrack] {
        return getTrackList().filter { $0.type == "sub" }
    }

    /// Get current audio track ID
    func getCurrentAudioTrack() -> Int? {
        getAudioTracks().first(where: \.selected)?.id
    }

    /// Get current subtitle track ID
    func getCurrentSubtitleTrack() -> Int? {
        getSubtitleTracks().first(where: \.selected)?.id
    }

    /// Updates the cached selection at once; mpv's notification confirms it later.
    private func markSelected(type: String, id: Int?) {
        withCache {
            for index in cachedTracks.indices where cachedTracks[index].type == type {
                cachedTracks[index].selected = cachedTracks[index].id == id
            }
        }
    }

    /// Set audio track by ID
    func setAudioTrack(_ trackId: Int) {
        markSelected(type: "audio", id: trackId)
        setProperty("aid", value: Int64(trackId))
        print("🎵 [MPV] Audio track set to: \(trackId)")
    }

    /// Set subtitle track by ID (0 to disable)
    func setSubtitleTrack(_ trackId: Int) {
        markSelected(type: "sub", id: trackId > 0 ? trackId : nil)
        setProperty("sid", value: Int64(trackId))
        print("💬 [MPV] Subtitle track set to: \(trackId)")
    }

    /// Disable subtitles
    func disableSubtitles() {
        markSelected(type: "sub", id: nil)
        setProperty("sid", value: "no")
        print("💬 [MPV] Subtitles disabled")
    }

    func addExternalSubtitleFile(path: String, title: String?, language: String?, select: Bool) {
        var args = [path]
        if let title, !title.isEmpty {
            args.append("title=\(title)")
        }
        if let language, !language.isEmpty {
            args.append("lang=\(language)")
        }
        if select {
            args.append("select=yes")
        }
        command(.subAdd, args: args)
    }

    func clearExternalSubtitleTracks() {
        let external = getSubtitleTracks().filter(\.external)
        guard !external.isEmpty else { return }
        withCache { cachedTracks.removeAll { $0.type == "sub" && $0.external } }
        for track in external {
            command(.subRemove, args: ["\(track.id)"])
        }
    }

    // MARK: - Property Management

    /// Blocking read. Never call it on the main thread (see apiQueue): use the cached
    /// accessors there. Used on the event and API queues.
    func getProperty<T>(_ name: String, type: PropertyType) -> T? {
        guard let mpv else { return nil }
        if Thread.isMainThread { print("⚠️ [MPV] Blocking read of \(name) on the main thread") }

        switch type {
        case .flag:
            var value: Int64 = 0
            mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &value)
            return (value != 0) as? T

        case .int64:
            var value: Int64 = 0
            mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value)
            return value as? T

        case .double:
            var value: Double = 0
            mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
            return value as? T

        case .string:
            let cstr = mpv_get_property_string(mpv, name)
            let str = cstr == nil ? nil : String(cString: cstr!)
            mpv_free(cstr)
            return str as? T
        }
    }

    func setProperty(_ name: String, value: Any) {
        if let boolValue = value as? Bool {
            perform { mpv in
                var data: Int32 = boolValue ? 1 : 0
                mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
            }
        } else if let intValue = value as? Int64 {
            perform { mpv in
                var data = intValue
                mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
            }
        } else if let doubleValue = value as? Double {
            perform { mpv in
                var data = doubleValue
                mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
            }
        } else if let stringValue = value as? String {
            setString(name, stringValue)
        }
    }

    /// Double property, or nil when mpv has no value (e.g. `sub-start` without a current cue).
    /// Unlike `getProperty(_:type: .double)`, failures are not reported as 0.
    /// Blocking: event and API queues only.
    func getPropertyIfAvailable(_ name: String) -> Double? {
        guard let mpv else { return nil }
        if Thread.isMainThread { print("⚠️ [MPV] Blocking read of \(name) on the main thread") }
        var value: Double = 0
        return mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    /// Sets a property, trying each name in order until mpv accepts one
    /// (for options renamed between mpv versions). Returns false if none was accepted.
    private func setPropertyString(firstAccepted names: [String], _ value: String) {
        perform { mpv in
            for name in names where mpv_set_property_string(mpv, name, value) >= 0 {
                return
            }
            print("⚠️ [MPV] None of \(names) accepted value \(value)")
        }
    }

    private func setOption(_ name: String, value: String) {
        guard mpv != nil else { return }
        let status = mpv_set_option_string(mpv, name, value)
        if status < 0 {
            print("⚠️ [MPV] Failed to set option \(name)=\(value): \(String(cString: mpv_error_string(status)))")
        }
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            print("[MPV] Error: \(String(cString: mpv_error_string(status)))")
        }
    }

    private func setOptionStringWithLog(_ name: String, _ value: String) {
        let status = mpv_set_option_string(mpv, name, value)
        if status < 0 {
            print("⚠️ [MPV] Failed to set option \(name)=\(value): \(String(cString: mpv_error_string(status)))")
        } else {
            print("✅ [MPV] Set option \(name)=\(value)")
        }
    }

    // MARK: - Commands

    private func command(_ cmd: MPVCommand, args: [String] = []) {
        let strArgs = [cmd.rawValue] + args
        print("🎮 [MPV] Executing command: \(strArgs.joined(separator: " "))")
        perform { mpv in
            let cArgs = strArgs.map { $0.withCString { strdup($0) } }
            defer {
                cArgs.forEach { free(UnsafeMutablePointer(mutating: $0)) }
            }
            var mutableArgs: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) } + [nil]
            let status = mpv_command(mpv, &mutableArgs)
            if status < 0 {
                print("❌ [MPV] Command \(cmd.rawValue) failed: \(String(cString: mpv_error_string(status)))")
            }
        }
    }

    // MARK: - Event Handling

    private func readEvents() {
        queue.async { [weak self] in
            // Captured once: shutdown clears `mpv`, and destroys the handle only after
            // this block has finished (see shutdown(completion:)).
            guard let self = self, let handle = self.mpv else { return }

            while true {
                let event = mpv_wait_event(handle, 0)
                guard let event = event else { break }

                let eventId = event.pointee.event_id
                if eventId == MPV_EVENT_NONE {
                    break
                }

                self.handleEvent(event)

                if eventId == MPV_EVENT_SHUTDOWN {
                    break
                }
            }
        }
    }

    private func handleEvent(_ event: UnsafePointer<mpv_event>) {
        let eventId = event.pointee.event_id

        switch eventId {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.pointee.data else { break }
            let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
            let propertyName = String(cString: property.name)

            if property.format == MPV_FORMAT_NODE {
                if let ptr = property.data {
                    let node = ptr.assumingMemoryBound(to: mpv_node.self).pointee
                    if propertyName == "track-list" {
                        let tracks = Self.parseTracks(node)
                        withCache { cachedTracks = tracks }
                    } else if propertyName == "chapter-list" {
                        let chapters = Self.parseChapters(node)
                        withCache { cachedChapters = chapters }
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onPropertyChange?(propertyName, nil)
                }
                break
            }

            let value: Any? = {
                guard let ptr = property.data else { return nil }
                switch property.format {
                case MPV_FORMAT_FLAG:
                    // Flags are Int32 in MPV, not Bool
                    return ptr.assumingMemoryBound(to: Int32.self).pointee != 0
                case MPV_FORMAT_INT64:
                    return ptr.assumingMemoryBound(to: Int64.self).pointee
                case MPV_FORMAT_DOUBLE:
                    return ptr.assumingMemoryBound(to: Double.self).pointee
                case MPV_FORMAT_STRING:
                    let cstr = ptr.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee
                    return cstr.map { String(cString: $0) }
                default:
                    return nil
                }
            }()

            switch propertyName {
            case "pause": if let paused = value as? Bool { withCache { cachedPaused = paused } }
            case "speed": if let speed = value as? Double { withCache { cachedSpeed = speed } }
            case "chapter": withCache { cachedChapter = (value as? Int64).map(Int.init) }
            case "audio-delay": if let delay = value as? Double { withCache { cachedAudioDelay = delay } }
            case "sub-delay": if let delay = value as? Double { withCache { cachedSubtitleDelay = delay } }
            case "path": withCache { cachedPath = value as? String }
            default: break
            }

            // Handle HDR properties
            if propertyName == "video-params/sig-peak", let sigPeak = value as? Double {
                lastSigPeak = sigPeak
                DispatchQueue.main.async {
                    self.configureHDRMode()
                    self.onHDRDetected?(sigPeak > 1.0, sigPeak)
                }
            } else if propertyName == "video-params/gamma", let gamma = value as? String {
                lastGamma = gamma
                DispatchQueue.main.async {
                    self.configureHDRMode()
                }
            } else if propertyName == "video-params/primaries", let primaries = value as? String {
                lastPrimaries = primaries
                DispatchQueue.main.async {
                    self.configureHDRMode()
                }
            }

            // Subtitle cue shown: read its timing on this (event) queue while it is current
            if propertyName == "sub-text", let text = value as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               onSubtitleCueShown != nil {
                let start: Double? = getPropertyIfAvailable("sub-start")
                let end: Double? = getPropertyIfAvailable("sub-end")
                let playback: Double? = getPropertyIfAvailable("time-pos")
                let delay: Double = getPropertyIfAvailable("sub-delay") ?? 0
                if let start, let playback {
                    let shown = MPVShownSubtitleCue(text: text, start: start, end: end, playbackTime: playback, subDelay: delay)
                    DispatchQueue.main.async { [weak self] in
                        self?.onSubtitleCueShown?(shown)
                    }
                }
            }

            // Check for thumbfast-info updates
            if propertyName == "user-data/thumbfast-info", let jsonString = value as? String {
                self.parseThumbnailInfo(jsonString)
            }

            DispatchQueue.main.async { [weak self] in
                self?.onPropertyChange?(propertyName, value)
            }

        case MPV_EVENT_START_FILE:
            print("📺 [MPV] File started")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("file-started")
            }

        case MPV_EVENT_FILE_LOADED:
            print("✅ [MPV] File loaded")
            refreshCachesForLoadedFile()
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("file-loaded")
            }

        case MPV_EVENT_END_FILE:
            // Report why the file ended so only a real end of file counts as
            // "finished watching" (which scrobbles to Plex and auto-plays next):
            //   EOF   -> "file-ended"
            //   ERROR -> "file-error"   (network drop, 4xx/5xx, demuxer error)
            //   STOP / QUIT / REDIRECT -> "file-stopped" (a new file replaced this
            //   one, e.g. quality change or source switch, or the player closed)
            var eventName = "file-ended"
            if let data = event.pointee.data {
                let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                switch endFile.reason {
                case MPV_END_FILE_REASON_EOF:
                    eventName = "file-ended"
                case MPV_END_FILE_REASON_ERROR:
                    eventName = "file-error"
                    if let message = mpv_error_string(endFile.error) {
                        print("❌ [MPV] File ended with error: \(String(cString: message))")
                    }
                default:
                    eventName = "file-stopped"
                }
            }
            print("🏁 [MPV] File ended (\(eventName))")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(eventName)
            }

        case MPV_EVENT_PLAYBACK_RESTART:
            print("▶️ [MPV] Playback restarted")
            let audioOutput: String? = getProperty("current-ao", type: .string)
            print("🔊 [MPV] Audio output: \(audioOutput ?? "none")")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("playback-restart")
            }

        case MPV_EVENT_SEEK:
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("seek")
            }

        case MPV_EVENT_SHUTDOWN:
            print("🛑 [MPV] Shutdown")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("shutdown")
            }

        case MPV_EVENT_LOG_MESSAGE:
            let logData = event.pointee.data.assumingMemoryBound(to: mpv_event_log_message.self)
            let log = logData.pointee
            let prefix = String(cString: log.prefix)
            let level = String(cString: log.level)
            let text = String(cString: log.text).trimmingCharacters(in: .whitespacesAndNewlines)

            // Filter out repetitive Dolby Vision warnings
            if text.contains("Multiple Dolby Vision RPUs found") {
                return
            }

            print("📝 [MPV] [\(prefix)] \(level): \(text)")

        default:
            break
        }
    }

    /// Reads the new file's tracks, chapters and path here on the event queue (never
    /// the main thread), so the "file-loaded" handlers see them at once.
    private func refreshCachesForLoadedFile() {
        guard let mpv else { return }
        var trackNode = mpv_node()
        if mpv_get_property(mpv, "track-list", MPV_FORMAT_NODE, &trackNode) >= 0 {
            let tracks = Self.parseTracks(trackNode)
            mpv_free_node_contents(&trackNode)
            withCache { cachedTracks = tracks }
        }
        var chapterNode = mpv_node()
        if mpv_get_property(mpv, "chapter-list", MPV_FORMAT_NODE, &chapterNode) >= 0 {
            let chapters = Self.parseChapters(chapterNode)
            mpv_free_node_contents(&chapterNode)
            withCache { cachedChapters = chapters }
        } else {
            withCache { cachedChapters = [] }
        }
        let path: String? = getProperty("path", type: .string)
        withCache { cachedPath = path }
    }

    // MARK: - Shutdown

    /// Stops mpv without blocking the main thread. vo_avfoundation needs the main thread
    /// to let go of its layers, so `mpv_terminate_destroy` runs on apiQueue, after every
    /// call queued before it. `completion` runs on the main thread once mpv is gone;
    /// remove the video layers only then.
    func shutdown(completion: (() -> Void)? = nil) {
        shutdownLock.lock()
        if isShuttingDown {
            if let completion {
                if isFullyShutDown {
                    DispatchQueue.main.async(execute: completion)
                } else {
                    shutdownCompletions.append(completion)
                }
            }
            shutdownLock.unlock()
            return
        }
        guard let handle = mpv else {
            shutdownLock.unlock()
            if let completion { DispatchQueue.main.async(execute: completion) }
            return
        }
        isShuttingDown = true
        if let completion { shutdownCompletions.append(completion) }
        mpv = nil
        shutdownLock.unlock()
        print("🛑 [MPV] Shutting down")

        // Clear callbacks
        onPropertyChange = nil
        onEvent = nil
        onHDRDetected = nil
        onSubtitleCueShown = nil
        mpv_set_wakeup_callback(handle, nil, nil)

        // Kept alive until mpv has let go of it.
        let layer = videoLayer
        let eventQueue = queue
        apiQueue.async { [weak self] in
            // Let an event batch that is running finish with the handle.
            eventQueue.sync {}
            while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {}
            print("🛑 [MPV] Calling mpv_terminate_destroy...")
            mpv_terminate_destroy(handle)
            DispatchQueue.main.async {
                withExtendedLifetime(layer) {}
                self?.finishShutdown()
            }
        }
        isInitialized = false
    }

    private func finishShutdown() {
        shutdownLock.lock()
        isFullyShutDown = true
        let completions = shutdownCompletions
        shutdownCompletions = []
        shutdownLock.unlock()
        videoLayer = nil
        window = nil
        print("✅ [MPV] Shutdown complete")
        completions.forEach { $0() }
    }

    // MARK: - Thumbnail Support

    /// Request a thumbnail at a specific timestamp
    func requestThumbnail(at time: Double) {
        let commandString = "script-message-to thumbfast thumb \(time) \"\" \"\""
        perform { _ = mpv_command_string($0, commandString) }
    }

    /// Clear the current thumbnail
    func clearThumbnail() {
        perform { _ = mpv_command_string($0, "script-message-to thumbfast clear") }
    }

    /// Parse thumbfast-info JSON
    private func parseThumbnailInfo(_ json: String) {
        print("📸 [MPV] Received thumbfast-info JSON: \(json)")

        guard let data = json.data(using: .utf8) else {
            print("❌ [MPV] Failed to convert JSON string to data")
            return
        }

        do {
            let decoder = JSONDecoder()

            var actualJSON = json
            if let decodedString = try? decoder.decode(String.self, from: data) {
                actualJSON = decodedString
            }

            guard let actualData = actualJSON.data(using: .utf8) else {
                print("❌ [MPV] Failed to convert actual JSON to data")
                return
            }

            let info = try decoder.decode(ThumbnailInfo.self, from: actualData)
            self.thumbnailInfo = info

            print("📸 [MPV] Thumbnail info parsed: \(info.width)x\(info.height), available: \(info.available)")

            DispatchQueue.main.async { [weak self] in
                if let info = self?.thumbnailInfo {
                    self?.onThumbnailInfo?(info)
                }
            }
        } catch {
            print("❌ [MPV] Failed to parse thumbfast-info: \(error)")
        }
    }

    // MARK: - Performance Stats

    /// Reads the stats overlay's values on apiQueue and hands them back on the main thread.
    func fetchPerformanceStats(_ completion: @escaping (PerformanceStats) -> Void) {
        perform { [weak self] _ in
            guard let self else { return }
            let stats = self.collectPerformanceStats()
            DispatchQueue.main.async { completion(stats) }
        }
    }

    private func collectPerformanceStats() -> PerformanceStats {
        var stats = PerformanceStats()

        // Video properties
        stats.videoCodec = getPropertyString("video-codec")
        stats.videoFormat = getPropertyString("video-format")
        stats.videoWidth = getPropertyAsInt("video-params/w")
        stats.videoHeight = getPropertyAsInt("video-params/h")
        stats.videoFps = getPropertyDouble("container-fps")
        stats.videoBitrate = getPropertyDouble("video-bitrate")
        stats.hwdecCurrent = getPropertyString("hwdec-current")

        // Color/Format properties
        stats.pixelFormat = getPropertyString("video-params/pixelformat")
        stats.hwPixelFormat = getPropertyString("video-params/hw-pixelformat")
        stats.colorMatrix = getPropertyString("video-params/colormatrix")
        stats.videoParamsPrimaries = getPropertyString("video-params/primaries")
        stats.videoParamsGamma = getPropertyString("video-params/gamma")

        // HDR Metadata
        stats.sigPeak = getPropertyDouble("video-params/sig-peak")
        stats.maxLuma = getPropertyDouble("video-params/max-luma")
        stats.minLuma = getPropertyDouble("video-params/min-luma")
        stats.maxCll = getPropertyDouble("video-params/max-cll")
        stats.maxFall = getPropertyDouble("video-params/max-fall")

        // Audio properties
        stats.audioCodec = getPropertyString("audio-codec-name")
        stats.audioChannels = getPropertyAsInt("audio-params/channel-count")
        stats.audioSampleRate = getPropertyAsInt("audio-params/samplerate")
        stats.audioBitrate = getPropertyDouble("audio-bitrate")

        // Playback properties
        stats.decoderFrameDropCount = getPropertyAsInt("decoder-frame-drop-count")
        stats.frameDropCount = getPropertyAsInt("frame-drop-count")
        stats.avsync = getPropertyDouble("avsync")
        stats.estimatedVfFps = getPropertyDouble("estimated-vf-fps")
        stats.displayFps = getPropertyDouble("display-fps")

        // Cache properties
        stats.cacheUsed = getPropertyAsInt("cache-used")
        stats.cacheSpeed = getPropertyDouble("cache-speed")
        stats.demuxerCacheDuration = getPropertyDouble("demuxer-cache-duration")

        // App metrics (memory usage)
        stats.appMemoryBytes = getAppMemoryUsage()

        return stats
    }

    /// Get current app memory usage in bytes
    private func getAppMemoryUsage() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) : nil
    }

    /// Helper to get Int properties
    private func getPropertyAsInt(_ name: String) -> Int? {
        if let value: Int64 = getProperty(name, type: .int64) {
            return Int(value)
        }
        return nil
    }

    /// Helper to get String properties
    private func getPropertyString(_ name: String) -> String? {
        return getProperty(name, type: .string)
    }

    /// Helper to get Double properties
    private func getPropertyDouble(_ name: String) -> Double? {
        return getProperty(name, type: .double)
    }

    // MARK: - Subtitle Styling

    /// Set subtitle font size
    func setSubtitleFontSize(_ size: Int) {
        setString("sub-font-size", "\(size)")
    }

    /// Set subtitle text color (hex string like "FFFFFF" or "#FFFFFF")
    func setSubtitleColor(_ color: String) {
        setString("sub-color", Self.mpvColor(color))
    }

    /// Set subtitle border (outline) size. mpv 0.38 renamed sub-border-* to sub-outline-*.
    func setSubtitleBorderSize(_ size: Double) {
        setPropertyString(firstAccepted: ["sub-outline-size", "sub-border-size"], String(format: "%.2f", size))
    }

    /// Set subtitle border (outline) color (hex string "RRGGBB", "#RRGGBB" or "#AARRGGBB")
    func setSubtitleBorderColor(_ color: String) {
        setPropertyString(firstAccepted: ["sub-outline-color", "sub-border-color"], Self.mpvColor(color))
    }

    /// Set subtitle background color. `color` is "RRGGBB"/"#RRGGBB"; `opacity` 0...1.
    /// A visible background switches mpv to `sub-border-style=background-box`.
    func setSubtitleBackground(color: String, opacity: Double) {
        let clamped = min(1, max(0, opacity))
        setString("sub-back-color", Self.mpvColor(color, alpha: clamped))
        setString("sub-border-style", clamped > 0 ? "background-box" : "outline-and-shadow")
    }

    /// Subtitle font family; empty string restores mpv's default (sans-serif).
    func setSubtitleFont(_ family: String) {
        let trimmed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        setString("sub-font", trimmed.isEmpty ? "sans-serif" : trimmed)
    }

    /// Bold subtitle text.
    func setSubtitleBold(_ bold: Bool) {
        setProperty("sub-bold", value: bold)
    }

    /// Vertical subtitle position (`sub-pos`: 0 = top, 100 = bottom, up to 150).
    func setSubtitlePosition(_ position: Int) {
        // As a string: sub-pos is an integer or a float depending on the mpv version
        setString("sub-pos", "\(min(150, max(0, position)))")
    }

    /// Strip SDH/hearing-impaired annotations (`sub-filter-sdh`). Text subtitles only;
    /// mpv applies it to cues decoded after the change.
    func setSubtitleFilterSDH(_ enabled: Bool) {
        setProperty("sub-filter-sdh", value: enabled)
    }

    /// Applies a complete subtitle appearance (size, font, bold, colours, outline, background, position).
    /// Text-based subtitles only: styled ASS/SSA tracks keep their own styles
    /// (mpv's default `sub-ass-override=scale`), bitmap (PGS/VobSub) tracks are images.
    func applySubtitleAppearance(_ appearance: SubtitleAppearance) {
        setSubtitleFontSize(appearance.fontSize)
        setSubtitleFont(appearance.fontName)
        setSubtitleBold(appearance.bold)
        setSubtitleColor(appearance.textColor)
        setSubtitleBorderSize(appearance.borderSize)
        setSubtitleBorderColor(appearance.borderColor)
        setSubtitleBackground(color: appearance.backgroundColor, opacity: appearance.backgroundOpacity)
        setSubtitlePosition(appearance.position)

        // Explicit sub-* entries in the user's custom MPV config keep priority
        for entry in UserDefaults.standard.getEnabledMpvConfigEntries() where entry.key.hasPrefix("sub-") {
            setString(entry.key, entry.value)
        }
    }

    /// mpv colour string: "#RRGGBB", or "#AARRGGBB" when `alpha` is given (mpv puts alpha FIRST).
    /// Accepts "RRGGBB", "#RRGGBB" or "#AARRGGBB" input; anything else falls back to white.
    static func mpvColor(_ hex: String, alpha: Double? = nil) -> String {
        var digits = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        digits = digits.uppercased()
        guard digits.allSatisfy(\.isHexDigit), digits.count == 6 || digits.count == 8 else {
            return alpha.map { String(format: "#%02XFFFFFF", Int(($0 * 255).rounded())) } ?? "#FFFFFF"
        }
        let rgb = String(digits.suffix(6))
        guard let alpha else { return "#\(digits)" }
        return String(format: "#%02X", Int((min(1, max(0, alpha)) * 255).rounded())) + rgb
    }

    // MARK: - Aspect / Zoom

    /// Applies an aspect mode via mpv: `panscan` (crop to fill), `video-zoom`
    /// (log2 scale), `keepaspect` (off = stretch to the view) and resets
    /// `video-aspect-override` to the file's own aspect ratio.
    func applyAspect(panscan: Double, zoomFactor: Double, keepAspect: Bool) {
        setProperty("panscan", value: min(1, max(0, panscan)))
        setProperty("video-zoom", value: log2(max(0.1, zoomFactor)))
        setString("keepaspect", keepAspect ? "yes" : "no")
        setString("video-aspect-override", "-1")
    }

    // MARK: - Audio/Subtitle Sync

    /// Set audio delay in seconds (positive delays audio, negative advances it)
    func setAudioDelay(_ seconds: Double) {
        withCache { cachedAudioDelay = seconds }
        setProperty("audio-delay", value: seconds)
    }

    /// Get current audio delay
    func getAudioDelay() -> Double {
        withCache { cachedAudioDelay }
    }

    /// Set subtitle delay in seconds (positive delays subtitles, negative advances them)
    func setSubtitleDelay(_ seconds: Double) {
        withCache { cachedSubtitleDelay = seconds }
        setProperty("sub-delay", value: seconds)
    }

    /// Get current subtitle delay
    func getSubtitleDelay() -> Double {
        withCache { cachedSubtitleDelay }
    }

    // MARK: - Chapter Navigation

    /// Chapters of the loaded file, as last reported by mpv.
    func getChapters() -> [MPVChapter] {
        withCache { cachedChapters }
    }

    /// Parses mpv's `chapter-list` node.
    private static func parseChapters(_ node: mpv_node) -> [MPVChapter] {
        var chapters: [MPVChapter] = []
        guard node.format == MPV_FORMAT_NODE_ARRAY else { return [] }

        let list = node.u.list.pointee
        let count = Int(list.num)

        for i in 0..<count {
            guard let values = list.values else { continue }
            let chapterNode = values[i]

            guard chapterNode.format == MPV_FORMAT_NODE_MAP else { continue }

            let chapterMap = chapterNode.u.list.pointee
            let chapterCount = Int(chapterMap.num)

            var chapter = MPVChapter(index: i)

            for j in 0..<chapterCount {
                guard let keys = chapterMap.keys, let values = chapterMap.values else { continue }
                let key = String(cString: keys[j]!)
                let value = values[j]

                switch key {
                case "title":
                    if value.format == MPV_FORMAT_STRING {
                        chapter.title = String(cString: value.u.string!)
                    }
                case "time":
                    if value.format == MPV_FORMAT_DOUBLE {
                        chapter.time = value.u.double_
                    }
                default:
                    break
                }
            }

            chapters.append(chapter)
        }

        return chapters
    }

    /// Get current chapter index
    func getCurrentChapter() -> Int? {
        withCache { cachedChapter }
    }

    /// Seek to a specific chapter by index
    func seekToChapter(_ index: Int) {
        setProperty("chapter", value: Int64(index))
    }

    /// Go to previous chapter
    func previousChapter() {
        perform { _ = mpv_command_string($0, "add chapter -1") }
    }

    /// Go to next chapter
    func nextChapter() {
        perform { _ = mpv_command_string($0, "add chapter 1") }
    }
}

// MARK: - Supporting Types

enum MPVCommand: String {
    case loadfile = "loadfile"
    case stop = "stop"
    case seek = "seek"
    case cycle = "cycle"
    case quit = "quit"
    case loadScript = "load-script"
    case addChapter = "add"
    case subAdd = "sub-add"
    case subRemove = "sub-remove"
}

enum PropertyType {
    case flag
    case int64
    case double
    case string
}

/// Thumbnail information from thumbfast
struct ThumbnailInfo: Codable {
    let width: Int
    let height: Int
    let disabled: Bool
    let available: Bool
    let socket: String?
    let thumbnail: String?
    let overlay_id: Int?

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case disabled
        case available
        case socket
        case thumbnail
        case overlay_id
    }
}

/// MPV track information (audio, subtitle, video)
struct MPVTrack {
    var id: Int = 0
    var type: String = ""
    var srcId: Int = 0
    var title: String?
    var lang: String?
    var selected: Bool = false
    var external: Bool = false
    /// Container "default" flag.
    var isDefault: Bool = false
    /// Container "forced" flag (signs/foreign-dialogue-only subtitles).
    var forced: Bool = false
    /// Hearing-impaired (SDH) flag, when the container sets it.
    var hearingImpaired: Bool = false
    /// Path or URL of an external track (sub-add / sidecar files), nil for embedded tracks.
    var externalFilename: String?

    /// Display name for the track
    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        if let lang = lang, !lang.isEmpty {
            return lang.uppercased()
        }
        return String(localized: "Track \(id)")
    }
}

/// MPV chapter information
struct MPVChapter: Identifiable {
    var id: Int { index }
    var index: Int
    var title: String?
    var time: Double = 0

    /// Display name for the chapter
    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return String(localized: "Chapter \(index + 1)")
    }

    /// Formatted time string
    var formattedTime: String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

/// A subtitle cue mpv started showing (from `sub-text` / `sub-start` / `sub-end`).
/// `start`/`end` are as mpv reports them; `playbackTime` and `subDelay` are
/// sampled at the same moment so callers can tell which timeline they are in.
struct MPVShownSubtitleCue {
    let text: String
    let start: Double
    let end: Double?
    let playbackTime: Double
    let subDelay: Double
}

/// Subtitle styling applied to mpv. Colours are "#RRGGBB" hex strings.
struct SubtitleAppearance: Equatable {
    var fontSize: Int
    var fontName: String
    var bold: Bool
    var textColor: String
    var borderSize: Double
    var borderColor: String
    var backgroundColor: String
    /// 0...1; 0 = no background box.
    var backgroundOpacity: Double
    /// mpv `sub-pos` (0 = top, 100 = bottom).
    var position: Int

    /// Current profile's saved appearance.
    static func fromDefaults(_ defaults: UserDefaults = .standard) -> SubtitleAppearance {
        SubtitleAppearance(
            fontSize: defaults.subtitleFontSize,
            fontName: defaults.subtitleFontName,
            bold: defaults.subtitleBold,
            textColor: defaults.subtitleTextColor,
            borderSize: defaults.subtitleBorderSize,
            borderColor: defaults.subtitleBorderColor,
            backgroundColor: defaults.subtitleBackgroundColor,
            backgroundOpacity: defaults.subtitleBackgroundOpacity,
            position: defaults.subtitlePosition
        )
    }
}
