//
//  MPVPlayerController.swift
//  FlixorMac
//
//  MPV player controller with gpu-next rendering for Dolby Vision support
//  Based on plezy implementation: https://github.com/edde746/plezy
//

import Foundation
import AppKit
import Libmpv

class MPVPlayerController {
    // MARK: - Properties

    /// The mpv handle
    private var mpv: OpaquePointer?

    /// Reference to the Metal layer for EDR management
    private weak var metalLayer: MPVMetalLayer?

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

    /// Callback for property changes
    var onPropertyChange: ((String, Any?) -> Void)?

    /// Callback for events
    var onEvent: ((String) -> Void)?

    /// Callback for HDR detection (sig-peak based)
    var onHDRDetected: ((Bool, Double) -> Void)?

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

    // MARK: - Setup with Metal Layer

    /// Initialize MPV with a Metal layer for gpu-next rendering
    /// This must be called before any playback
    func initialize(in window: NSWindow, layer: MPVMetalLayer) -> Bool {
        guard !isInitialized else {
            print("[MPV] Already initialized")
            return true
        }

        self.window = window
        self.metalLayer = layer

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

        // CRITICAL: Pass Metal layer as wid for gpu-next rendering
        // Must use local var for & (plezy pattern)
        var metalLayerRef = layer
        setOptionWithLog("wid", layer: &metalLayerRef)

        // Video output settings for Metal/Vulkan (plezy pattern)
        setOptionStringWithLog("vo", "gpu-next")
        setOptionStringWithLog("gpu-api", "vulkan")
        setOptionStringWithLog("gpu-context", "moltenvk")
        setOptionStringWithLog("hwdec", "videotoolbox")
        setOptionStringWithLog("target-colorspace-hint", "yes")

        // Store the Metal layer reference
        self.metalLayer = layer

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
        print("✅ [MPV] Initialized with gpu-next and Metal rendering")
        return true
    }

    private func configureAdditionalOptions() {
        // Additional properties set AFTER mpv_initialize
        // Use mpv_set_property_string for post-init settings

        // Keep aspect ratio
        mpv_set_property_string(mpv, "keepaspect", "yes")

        // Disable on-screen display
        mpv_set_property_string(mpv, "osd-level", "0")

        // Network/HTTP options for Plex streaming
        mpv_set_property_string(mpv, "tls-verify", "no")  // Plex direct uses custom certs
        mpv_set_property_string(mpv, "network-timeout", "30")
        mpv_set_property_string(mpv, "stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=5")
        print("[MPV] Network options configured (TLS verify disabled for Plex)")

        // Apply user settings from UserDefaults
        applyUserSettings()

        // Load thumbfast.lua script for thumbnails
        if let scriptPath = Bundle.main.path(forResource: "thumbfast", ofType: "lua") {
            print("📸 [MPV] Loading thumbfast script: \(scriptPath)")
            // Scripts need to be loaded via command after init
            command(.loadScript, args: [scriptPath])
        } else {
            print("⚠️ [MPV] thumbfast.lua not found in bundle")
        }

        print("✅ [MPV] Additional options configured")
    }

    /// Apply user settings from UserDefaults to MPV
    private func applyUserSettings() {
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
        mpv_set_property_string(mpv, "target-colorspace-hint", hdrEnabled ? "yes" : "no")
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
        guard mpv != nil else { return }
        applyUserSettings()
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

        // CRITICAL: Observe sig-peak for HDR/EDR activation (plezy approach)
        mpv_observe_property(mpv, 0, "video-params/sig-peak", MPV_FORMAT_DOUBLE)

        // Observe thumbfast-info property for thumbnail metadata
        mpv_observe_property(mpv, 0, "user-data/thumbfast-info", MPV_FORMAT_STRING)
    }

    // MARK: - HDR/EDR Support

    /// Update EDR mode based on sig-peak (plezy approach)
    private func updateEDRMode(sigPeak: Double) {
        guard let layer = metalLayer else { return }

        // Check if screen supports EDR
        var edrHeadroom: CGFloat = 1.0
        if let screen = window?.screen ?? NSScreen.main {
            edrHeadroom = screen.maximumExtendedDynamicRangeColorComponentValue
        }

        let isHDRContent = sigPeak > 1.0
        let screenSupportsEDR = edrHeadroom > 1.0
        let shouldEnableEDR = hdrEnabled && isHDRContent && screenSupportsEDR

        layer.wantsExtendedDynamicRangeContent = shouldEnableEDR

        print("[MPV] EDR: \(shouldEnableEDR) (hdrEnabled: \(hdrEnabled), sigPeak: \(sigPeak), headroom: \(edrHeadroom))")
    }

    /// Enable or disable HDR mode
    func setHDREnabled(_ enabled: Bool) {
        hdrEnabled = enabled
        print("[MPV] HDR enabled: \(enabled)")

        // Update MPV's target-colorspace-hint
        if mpv != nil {
            mpv_set_property_string(mpv, "target-colorspace-hint", enabled ? "yes" : "no")
        }

        // Re-evaluate EDR mode with current sig-peak
        DispatchQueue.main.async {
            self.updateEDRMode(sigPeak: self.lastSigPeak)
        }
    }

    // MARK: - Playback Control

    func loadFile(_ url: String, headers: [String: String]? = nil) {
        guard mpv != nil else {
            print("❌ [MPV] Cannot load file: mpv not initialized")
            return
        }

        // Set HTTP headers if provided (required for some Plex servers)
        if let headers = headers, !headers.isEmpty {
            let headerString = headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
            mpv_set_property_string(mpv, "http-header-fields", headerString)
            print("📺 [MPV] HTTP headers set: \(headers.count) headers")
        }

        print("📺 [MPV] Loading file: \(url)")
        let commandString = "loadfile \"\(url)\" replace"
        let status = mpv_command_string(mpv, commandString)
        if status < 0 {
            print("❌ [MPV] Failed to load file: \(String(cString: mpv_error_string(status)))")
        }
    }

    func play() {
        setProperty("pause", value: false)
    }

    func pause() {
        setProperty("pause", value: true)
    }

    func togglePlayPause() {
        guard let isPaused: Bool = getProperty("pause", type: .flag) else {
            print("⚠️ [MPV] Could not get pause state")
            return
        }
        setProperty("pause", value: !isPaused)
        print("✅ [MPV] Toggled pause: \(isPaused) -> \(!isPaused)")
    }

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

    /// Get all available tracks (audio, subtitle, video)
    func getTrackList() -> [MPVTrack] {
        guard mpv != nil else { return [] }

        var tracks: [MPVTrack] = []
        var node = mpv_node()

        let status = mpv_get_property(mpv, "track-list", MPV_FORMAT_NODE, &node)
        guard status >= 0 else {
            print("❌ [MPV] Failed to get track-list: \(String(cString: mpv_error_string(status)))")
            return []
        }

        defer { mpv_free_node_contents(&node) }

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
        return getProperty("aid", type: .int64)
    }

    /// Get current subtitle track ID
    func getCurrentSubtitleTrack() -> Int? {
        return getProperty("sid", type: .int64)
    }

    /// Set audio track by ID
    func setAudioTrack(_ trackId: Int) {
        setProperty("aid", value: Int64(trackId))
        print("🎵 [MPV] Audio track set to: \(trackId)")
    }

    /// Set subtitle track by ID (0 to disable)
    func setSubtitleTrack(_ trackId: Int) {
        setProperty("sid", value: Int64(trackId))
        print("💬 [MPV] Subtitle track set to: \(trackId)")
    }

    /// Disable subtitles
    func disableSubtitles() {
        setProperty("sid", value: "no")
        print("💬 [MPV] Subtitles disabled")
    }

    // MARK: - Property Management

    func getProperty<T>(_ name: String, type: PropertyType) -> T? {
        guard mpv != nil else { return nil }

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
        guard mpv != nil else { return }

        if let boolValue = value as? Bool {
            var data: Int = boolValue ? 1 : 0
            mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
        } else if let intValue = value as? Int64 {
            var data = intValue
            mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
        } else if let doubleValue = value as? Double {
            var data = doubleValue
            mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        } else if let stringValue = value as? String {
            mpv_set_property_string(mpv, name, stringValue)
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

    private func setOptionWithLog(_ name: String, layer: inout MPVMetalLayer) {
        let status = mpv_set_option(mpv, name, MPV_FORMAT_INT64, &layer)
        if status < 0 {
            print("⚠️ [MPV] Failed to set option \(name): \(String(cString: mpv_error_string(status)))")
        } else {
            print("✅ [MPV] Set option \(name)")
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
        guard mpv != nil else { return }

        var strArgs = args
        strArgs.insert(cmd.rawValue, at: 0)
        strArgs.append("")

        print("🎮 [MPV] Executing command: \(strArgs.dropLast().joined(separator: " "))")

        let cArgs = strArgs.map { $0.withCString { strdup($0) } }
        defer {
            cArgs.forEach { free(UnsafeMutablePointer(mutating: $0)) }
        }

        var mutableArgs = cArgs.map { UnsafePointer($0) }
        let status = mpv_command(mpv, &mutableArgs)

        if status < 0 {
            print("❌ [MPV] Command failed: \(String(cString: mpv_error_string(status)))")
        } else {
            print("✅ [MPV] Command succeeded")
        }
    }

    // MARK: - Event Handling

    private func readEvents() {
        queue.async { [weak self] in
            guard let self = self, self.mpv != nil else { return }

            while true {
                let event = mpv_wait_event(self.mpv, 0)
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

            // Handle sig-peak for HDR/EDR activation (plezy approach)
            if propertyName == "video-params/sig-peak", let sigPeak = value as? Double {
                lastSigPeak = sigPeak
                DispatchQueue.main.async {
                    self.updateEDRMode(sigPeak: sigPeak)
                    self.onHDRDetected?(sigPeak > 1.0, sigPeak)
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
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("file-loaded")
            }

        case MPV_EVENT_END_FILE:
            print("🏁 [MPV] File ended")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("file-ended")
            }

        case MPV_EVENT_PLAYBACK_RESTART:
            print("▶️ [MPV] Playback restarted")
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

    // MARK: - Shutdown

    func shutdown() {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }

        guard !isShuttingDown else {
            print("⚠️ [MPV] Already shutting down, skipping")
            return
        }

        guard mpv != nil else {
            print("⚠️ [MPV] Already shut down")
            return
        }

        isShuttingDown = true
        print("🛑 [MPV] Shutting down")

        // Clear callbacks
        onPropertyChange = nil
        onEvent = nil
        onHDRDetected = nil

        // Clear wakeup callback before draining events
        if let mpv = mpv {
            mpv_set_wakeup_callback(mpv, nil, nil)
        }

        // Drain all pending events before terminating
        if let mpv = mpv {
            print("🔄 [MPV] Draining event queue...")
            while true {
                let event = mpv_wait_event(mpv, 0)
                guard let event = event, event.pointee.event_id != MPV_EVENT_NONE else {
                    break
                }
            }
            print("✅ [MPV] Event queue drained")
        }

        // Small delay to ensure everything is settled
        Thread.sleep(forTimeInterval: 0.05)

        // Terminate MPV
        if let mpv = mpv {
            print("🛑 [MPV] Calling mpv_terminate_destroy...")
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }

        metalLayer = nil
        window = nil
        isInitialized = false
        print("✅ [MPV] Shutdown complete")
    }

    // MARK: - Thumbnail Support

    /// Request a thumbnail at a specific timestamp
    func requestThumbnail(at time: Double) {
        guard mpv != nil else {
            print("❌ [MPV] Cannot request thumbnail: mpv not initialized")
            return
        }

        let commandString = "script-message-to thumbfast thumb \(time) \"\" \"\""
        print("📸 [MPV] Requesting thumbnail at \(time)s")
        let status = mpv_command_string(mpv, commandString)

        if status < 0 {
            print("❌ [MPV] Failed to request thumbnail: \(String(cString: mpv_error_string(status)))")
        }
    }

    /// Clear the current thumbnail
    func clearThumbnail() {
        guard mpv != nil else { return }

        let commandString = "script-message-to thumbfast clear"
        let _ = mpv_command_string(mpv, commandString)
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

    /// Fetch all performance statistics for the stats overlay
    func getPerformanceStats() -> PerformanceStats {
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
        mpv_set_property_string(mpv, "sub-font-size", "\(size)")
    }

    /// Set subtitle text color (hex string like "FFFFFF")
    func setSubtitleColor(_ color: String) {
        mpv_set_property_string(mpv, "sub-color", "#\(color)")
    }

    /// Set subtitle border size
    func setSubtitleBorderSize(_ size: Double) {
        var value = size
        mpv_set_property(mpv, "sub-border-size", MPV_FORMAT_DOUBLE, &value)
    }

    /// Set subtitle border color (hex string)
    func setSubtitleBorderColor(_ color: String) {
        mpv_set_property_string(mpv, "sub-border-color", "#\(color)")
    }

    /// Set subtitle background color with alpha (hex string with alpha like "00000080")
    func setSubtitleBackgroundColor(_ color: String) {
        mpv_set_property_string(mpv, "sub-back-color", "#\(color)")
    }

    // MARK: - Audio/Subtitle Sync

    /// Set audio delay in seconds (positive delays audio, negative advances it)
    func setAudioDelay(_ seconds: Double) {
        var value = seconds
        mpv_set_property(mpv, "audio-delay", MPV_FORMAT_DOUBLE, &value)
    }

    /// Get current audio delay
    func getAudioDelay() -> Double {
        return getProperty("audio-delay", type: .double) ?? 0.0
    }

    /// Set subtitle delay in seconds (positive delays subtitles, negative advances them)
    func setSubtitleDelay(_ seconds: Double) {
        var value = seconds
        mpv_set_property(mpv, "sub-delay", MPV_FORMAT_DOUBLE, &value)
    }

    /// Get current subtitle delay
    func getSubtitleDelay() -> Double {
        return getProperty("sub-delay", type: .double) ?? 0.0
    }

    // MARK: - Chapter Navigation

    /// Get list of chapters
    func getChapters() -> [MPVChapter] {
        guard mpv != nil else { return [] }

        var chapters: [MPVChapter] = []
        var node = mpv_node()

        let status = mpv_get_property(mpv, "chapter-list", MPV_FORMAT_NODE, &node)
        guard status >= 0 else { return [] }

        defer { mpv_free_node_contents(&node) }

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
        return getPropertyAsInt("chapter")
    }

    /// Seek to a specific chapter by index
    func seekToChapter(_ index: Int) {
        setProperty("chapter", value: Int64(index))
    }

    /// Go to previous chapter
    func previousChapter() {
        guard mpv != nil else { return }
        mpv_command_string(mpv, "add chapter -1")
    }

    /// Go to next chapter
    func nextChapter() {
        guard mpv != nil else { return }
        mpv_command_string(mpv, "add chapter 1")
    }

    // MARK: - Legacy Compatibility

    // These methods are kept for backward compatibility but are no longer needed
    // with gpu-next rendering (MPV handles rendering internally)

    /// No longer needed - kept for API compatibility
    var videoUpdateCallback: (() -> Void)?

    /// No longer needed - MPV renders directly to Metal layer
    func initializeRendering(openGLContext: CGLContextObj) {
        print("⚠️ [MPV] initializeRendering(openGLContext:) is deprecated - using gpu-next Metal rendering")
    }

    /// No longer needed - MPV renders directly to Metal layer
    func render(width: Int, height: Int, fbo: GLint) {
        // No-op: gpu-next renders directly to the Metal layer
    }

    /// No longer needed
    func reportSwap() {
        // No-op: gpu-next handles this internally
    }

    /// No longer needed
    func shouldRenderUpdateFrame() -> Bool {
        return false
    }

    /// No longer needed
    func getRenderContext() -> OpaquePointer? {
        return nil
    }

    /// No longer needed
    func setRenderICCProfile(_ colorSpace: NSColorSpace) {
        // No-op: gpu-next handles color management
    }

    /// No longer needed with sig-peak based detection
    func setHDRProperties(primaries: String) {
        // No-op: target-colorspace-hint handles this
    }

    /// No longer needed with sig-peak based detection
    func setSDRProperties() {
        // No-op: target-colorspace-hint handles this
    }

    /// No longer needed
    func setICCProfile(path: String?) {
        // No-op: gpu-next handles color management
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

    /// Display name for the track
    var displayName: String {
        if let title = title, !title.isEmpty {
            return title
        }
        if let lang = lang, !lang.isEmpty {
            return lang.uppercased()
        }
        return "Track \(id)"
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
        return "Chapter \(index + 1)"
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
