//
//  MPVPlayerCore.swift
//  Flixor
//
//  Core MPV player engine using Metal rendering for iOS
//  Adapted from Plezy's MpvPlayerCore for React Native integration
//

import Libmpv
import UIKit

/// Protocol for receiving player events
protocol MPVPlayerDelegate: AnyObject {
    func onPropertyChange(name: String, value: Any?)
    func onEvent(name: String, data: [String: Any]?)
}

// Workaround for MoltenVK problems that cause flicker
// https://github.com/mpv-player/mpv/pull/13651
private class MetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { return super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    // Fix for target-colorspace-hint - needs main thread for EDR
    @available(iOS 16.0, *)
    override var wantsExtendedDynamicRangeContent: Bool {
        get { return super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.sync {
                    super.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }
}

/// Core MPV player using Metal rendering for iOS
class MPVPlayerCore: NSObject {

    // MARK: - Properties

    private var metalLayer: MetalLayer?
    private var containerView: UIView?
    private var mpv: OpaquePointer?
    private weak var parentView: UIView?
    private lazy var queue = DispatchQueue(label: "mpv", qos: .userInitiated)

    weak var delegate: MPVPlayerDelegate?

    private(set) var isInitialized = false
    private var isDisposing = false

    // HDR settings
    private var hdrEnabled = true
    private var lastSigPeak: Double = 0.0

    // Playback state
    private(set) var duration: Double = 0
    private(set) var currentTime: Double = 0
    private(set) var isPaused: Bool = true
    private(set) var isBuffering: Bool = false

    // Track information
    private(set) var audioTracks: [[String: Any]] = []
    private(set) var subtitleTracks: [[String: Any]] = []
    private(set) var videoWidth: Int = 0
    private(set) var videoHeight: Int = 0

    // MARK: - Initialization

    func initialize(in view: UIView) -> Bool {
        guard !isInitialized else {
            print("[MPVPlayerCore] Already initialized")
            return true
        }

        self.parentView = view

        // Create container view for proper EDR activation
        let container = UIView(frame: view.bounds)
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Create Metal layer for video rendering
        let layer = MetalLayer()
        layer.frame = container.bounds
        layer.contentsScale = UIScreen.main.nativeScale
        layer.framebufferOnly = true
        layer.backgroundColor = UIColor.black.cgColor

        // Set drawable size explicitly (required for MoltenVK)
        let scale = UIScreen.main.nativeScale
        layer.drawableSize = CGSize(
            width: max(1, container.bounds.width * scale),
            height: max(1, container.bounds.height * scale)
        )
        print("[MPVPlayerCore] Setting drawable size: \(layer.drawableSize)")

        container.layer.addSublayer(layer)
        containerView = container
        metalLayer = layer

        // Add container view to parent view
        view.insertSubview(container, at: 0)

        print("[MPVPlayerCore] Metal layer added to view, frame: \(layer.frame)")

        // Initialize MPV with this Metal layer
        guard setupMpv() else {
            print("[MPVPlayerCore] Failed to setup MPV")
            layer.removeFromSuperlayer()
            container.removeFromSuperview()
            metalLayer = nil
            containerView = nil
            return false
        }

        // Setup background/foreground notifications
        setupNotifications()

        isInitialized = true
        print("[MPVPlayerCore] Initialized successfully with MPV")
        return true
    }

    private func setupMpv() -> Bool {
        guard let metalLayer = metalLayer else { return false }

        mpv = mpv_create()
        guard mpv != nil else {
            print("[MPVPlayerCore] Failed to create MPV context")
            return false
        }

        // Logging
        #if DEBUG
            checkError(mpv_request_log_messages(mpv, "info"))
        #else
            checkError(mpv_request_log_messages(mpv, "warn"))
        #endif

        // Set the Metal layer as the render target
        var layer = metalLayer
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &layer))

        // Video output settings for Metal/Vulkan
        // Try gpu-next first, fall back to gpu if needed
        print("[MPVPlayerCore] Setting video output options...")
        print("[MPVPlayerCore] Metal layer frame: \(metalLayer.frame), drawableSize: \(metalLayer.drawableSize)")

        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox"))
        checkError(mpv_set_option_string(mpv, "target-colorspace-hint", "yes"))

        // Force video chain creation
        checkError(mpv_set_option_string(mpv, "force-window", "yes"))

        // Additional performance options
        checkError(mpv_set_option_string(mpv, "demuxer-max-bytes", "150MiB"))
        checkError(mpv_set_option_string(mpv, "demuxer-max-back-bytes", "75MiB"))
        checkError(mpv_set_option_string(mpv, "cache", "yes"))
        checkError(mpv_set_option_string(mpv, "cache-secs", "120"))

        // Initialize MPV
        print("[MPVPlayerCore] Calling mpv_initialize...")
        let initResult = mpv_initialize(mpv)
        if initResult < 0 {
            let errorMsg = String(cString: mpv_error_string(initResult))
            print("[MPVPlayerCore] mpv_initialize failed: \(errorMsg)")
            delegate?.onEvent(name: "error", data: ["error": "MPV init failed: \(errorMsg)"])
            mpv_terminate_destroy(mpv)
            mpv = nil
            return false
        }
        print("[MPVPlayerCore] mpv_initialize succeeded")

        // Set up wakeup callback for event handling
        mpv_set_wakeup_callback(
            mpv,
            { ctx in
                guard let ctx = ctx else { return }
                let core = Unmanaged<MPVPlayerCore>.fromOpaque(ctx).takeUnretainedValue()
                core.readEvents()
            }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        // Observe properties
        mpv_observe_property(mpv, 0, "video-params/sig-peak", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE)
        mpv_observe_property(mpv, 0, "width", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "height", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "demuxer-cache-time", MPV_FORMAT_DOUBLE)

        // Configure subtitle fonts AFTER initialization (using mpv_set_property_string)
        // This is critical - font properties must be set after mpv_initialize()
        configureSubtitleFonts()

        print("[MPVPlayerCore] MPV initialized successfully")
        return true
    }

    /// Configures subtitle fonts for CJK character support
    /// Must be called AFTER mpv_initialize() - uses mpv_set_property_string, not options
    private func configureSubtitleFonts() {
        guard mpv != nil else { return }

        if let fontDir = setupSubtitleFont() {
            // Enable config reading
            mpv_set_property_string(mpv, "config", "yes")

            // Set font directory and font name
            mpv_set_property_string(mpv, "sub-fonts-dir", fontDir)
            mpv_set_property_string(mpv, "sub-font", "Go Noto Current-Regular")

            print("[MPVPlayerCore] Configured subtitle font: Go Noto Current-Regular at \(fontDir)")
        } else {
            print("[MPVPlayerCore] WARNING: Failed to setup subtitle font, CJK subtitles may not render")
        }
    }

    // MARK: - Subtitle Font Setup

    /// Copies the subtitle font from bundle to cache directory for libass to access
    private func setupSubtitleFont() -> String? {
        let fontFileName = "go-noto-current-regular.ttf"

        // Get the font from bundle
        guard let bundleFontPath = Bundle.main.path(forResource: "go-noto-current-regular", ofType: "ttf") else {
            print("[MPVPlayerCore] Subtitle font not found in bundle")
            return nil
        }

        // Create subtitle_fonts directory in cache
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fontDir = cacheDir.appendingPathComponent("subtitle_fonts")

        do {
            // Create directory if needed
            if !FileManager.default.fileExists(atPath: fontDir.path) {
                try FileManager.default.createDirectory(at: fontDir, withIntermediateDirectories: true)
            }

            // Copy font to cache directory if not already there
            let destFontPath = fontDir.appendingPathComponent(fontFileName)
            if !FileManager.default.fileExists(atPath: destFontPath.path) {
                try FileManager.default.copyItem(atPath: bundleFontPath, toPath: destFontPath.path)
                print("[MPVPlayerCore] Copied subtitle font to: \(destFontPath.path)")
            } else {
                print("[MPVPlayerCore] Subtitle font already exists at: \(destFontPath.path)")
            }

            return fontDir.path
        } catch {
            print("[MPVPlayerCore] Failed to setup subtitle font: \(error)")
            return nil
        }
    }

    // MARK: - Background/Foreground Handling

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(enterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(enterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func enterBackground() {
        print("[MPVPlayerCore] Entering background - disabling video")
        if mpv != nil {
            mpv_set_option_string(mpv, "vid", "no")
        }
    }

    @objc private func enterForeground() {
        print("[MPVPlayerCore] Entering foreground - enabling video")
        if mpv != nil {
            mpv_set_option_string(mpv, "vid", "auto")
        }
    }

    // MARK: - Playback Control

    func loadFile(_ url: String, headers: [String: String]? = nil) {
        guard mpv != nil else { return }

        // Set HTTP headers if provided
        if let headers = headers, !headers.isEmpty {
            var headerStrings: [String] = []
            for (key, value) in headers {
                headerStrings.append("\(key): \(value)")
            }
            let headerString = headerStrings.joined(separator: "\r\n")
            mpv_set_option_string(mpv, "http-header-fields", headerString)
        }

        command(["loadfile", url])
        print("[MPVPlayerCore] Loading file: \(url.prefix(100))...")
    }

    func play() {
        setProperty("pause", value: "no")
    }

    func pause() {
        setProperty("pause", value: "yes")
    }

    func seek(to seconds: Double) {
        command(["seek", String(seconds), "absolute"])
    }

    func setVolume(_ volume: Double) {
        setProperty("volume", value: String(Int(volume * 100)))
    }

    func setSpeed(_ speed: Double) {
        setProperty("speed", value: String(speed))
    }

    func setAudioTrack(_ trackId: Int) {
        setProperty("aid", value: trackId == -1 ? "no" : String(trackId))
    }

    func setSubtitleTrack(_ trackId: Int) {
        setProperty("sid", value: trackId == -1 ? "no" : String(trackId))
    }

    // MARK: - MPV Properties and Commands

    func setProperty(_ name: String, value: String) {
        guard mpv != nil else { return }

        // Handle custom HDR toggle property
        if name == "hdr-enabled" {
            let enabled = value == "yes" || value == "true" || value == "1"
            setHDREnabled(enabled)
            return
        }

        mpv_set_property_string(mpv, name, value)
    }

    func setHDREnabled(_ enabled: Bool) {
        hdrEnabled = enabled
        print("[MPVPlayerCore] HDR enabled: \(enabled)")

        if mpv != nil {
            mpv_set_property_string(mpv, "target-colorspace-hint", enabled ? "yes" : "no")
        }

        DispatchQueue.main.async {
            self.updateEDRMode(sigPeak: self.lastSigPeak)
        }
    }

    func getProperty(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        let cstr = mpv_get_property_string(mpv, name)
        defer { mpv_free(cstr) }
        return cstr.map { String(cString: $0) }
    }

    func observeProperty(_ name: String, format: String) {
        guard mpv != nil else { return }

        let mpvFormat: mpv_format
        switch format {
        case "double": mpvFormat = MPV_FORMAT_DOUBLE
        case "flag": mpvFormat = MPV_FORMAT_FLAG
        case "node": mpvFormat = MPV_FORMAT_NODE
        case "string": mpvFormat = MPV_FORMAT_STRING
        default: return
        }

        mpv_observe_property(mpv, 0, name, mpvFormat)
    }

    func command(_ args: [String]) {
        guard mpv != nil, !args.isEmpty else { return }

        var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cargs.append(nil)
        defer {
            for ptr in cargs {
                free(ptr)
            }
        }

        cargs.withUnsafeBufferPointer { buffer in
            var constPtrs = buffer.map { UnsafePointer($0) }
            _ = mpv_command(mpv, &constPtrs)
        }
    }

    // MARK: - Frame Management

    func updateFrame(_ frame: CGRect? = nil) {
        guard let metalLayer = metalLayer, let container = containerView else { return }

        if let frame = frame {
            container.frame = frame
            metalLayer.frame = container.bounds
        } else if let parentView = parentView {
            container.frame = parentView.bounds
            metalLayer.frame = container.bounds
        }

        let scale = UIScreen.main.nativeScale
        metalLayer.drawableSize = CGSize(
            width: metalLayer.frame.width * scale,
            height: metalLayer.frame.height * scale
        )

        print("[MPVPlayerCore] updateFrame: \(container.frame)")
    }

    // MARK: - Event Handling

    private func readEvents() {
        queue.async { [weak self] in
            guard let self = self, !self.isDisposing, let mpv = self.mpv else { return }

            while true {
                let event = mpv_wait_event(mpv, 0)
                guard let eventPtr = event else { break }

                if eventPtr.pointee.event_id == MPV_EVENT_NONE {
                    break
                }

                self.handleEvent(eventPtr.pointee)
            }
        }
    }

    private func handleEvent(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data else { break }
            let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
            let name = String(cString: property.name)
            handlePropertyChange(name: name, property: property)

        case MPV_EVENT_FILE_LOADED:
            // Parse track information
            parseTrackList()
            DispatchQueue.main.async {
                self.delegate?.onEvent(name: "file-loaded", data: [
                    "duration": self.duration,
                    "width": self.videoWidth,
                    "height": self.videoHeight,
                    "audioTracks": self.audioTracks,
                    "subtitleTracks": self.subtitleTracks
                ])
            }

        case MPV_EVENT_END_FILE:
            DispatchQueue.main.async {
                self.delegate?.onEvent(name: "end-file", data: nil)
            }

        case MPV_EVENT_SHUTDOWN:
            print("[MPVPlayerCore] MPV shutdown event")

        case MPV_EVENT_PLAYBACK_RESTART:
            DispatchQueue.main.async {
                self.delegate?.onEvent(name: "playback-restart", data: nil)
            }

        case MPV_EVENT_LOG_MESSAGE:
            if let msgPtr = event.data?.assumingMemoryBound(to: mpv_event_log_message.self) {
                let msg = msgPtr.pointee
                let prefix = msg.prefix.map { String(cString: $0) } ?? ""
                let level = msg.level.map { String(cString: $0) } ?? ""
                let text = msg.text.map { String(cString: $0) } ?? ""

                DispatchQueue.main.async {
                    self.delegate?.onEvent(name: "log-message", data: [
                        "prefix": prefix,
                        "level": level,
                        "text": text
                    ])
                }
            }

        default:
            break
        }
    }

    private func handlePropertyChange(name: String, property: mpv_event_property) {
        var value: Any?

        switch property.format {
        case MPV_FORMAT_DOUBLE:
            if let ptr = property.data {
                value = ptr.assumingMemoryBound(to: Double.self).pointee
            }

        case MPV_FORMAT_FLAG:
            if let ptr = property.data {
                value = ptr.assumingMemoryBound(to: Int32.self).pointee != 0
            }

        case MPV_FORMAT_INT64:
            if let ptr = property.data {
                value = ptr.assumingMemoryBound(to: Int64.self).pointee
            }

        case MPV_FORMAT_NODE:
            if let ptr = property.data {
                let node = ptr.assumingMemoryBound(to: mpv_node.self).pointee
                value = convertNode(node)
            }

        case MPV_FORMAT_STRING:
            if let ptr = property.data {
                let cstr = ptr.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee
                value = cstr.map { String(cString: $0) }
            }

        default:
            break
        }

        // Handle specific properties
        switch name {
        case "video-params/sig-peak":
            if let sigPeak = value as? Double {
                lastSigPeak = sigPeak
                DispatchQueue.main.async {
                    self.updateEDRMode(sigPeak: sigPeak)
                }
            }

        case "time-pos":
            if let time = value as? Double {
                currentTime = time
            }

        case "duration":
            if let dur = value as? Double {
                duration = dur
            }

        case "pause":
            if let paused = value as? Bool {
                isPaused = paused
            }

        case "paused-for-cache":
            if let buffering = value as? Bool {
                isBuffering = buffering
            }

        case "width":
            if let w = value as? Int64 {
                videoWidth = Int(w)
            }

        case "height":
            if let h = value as? Int64 {
                videoHeight = Int(h)
            }

        case "track-list":
            parseTrackList()

        default:
            break
        }

        DispatchQueue.main.async {
            self.delegate?.onPropertyChange(name: name, value: value)
        }
    }

    // MARK: - Track Parsing

    private func parseTrackList() {
        guard mpv != nil else { return }

        var node = mpv_node()
        let result = mpv_get_property(mpv, "track-list", MPV_FORMAT_NODE, &node)

        guard result >= 0 else { return }
        defer { mpv_free_node_contents(&node) }

        guard let tracks = convertNode(node) as? [[String: Any]] else { return }

        var audio: [[String: Any]] = []
        var subtitle: [[String: Any]] = []

        for track in tracks {
            guard let type = track["type"] as? String,
                  let id = track["id"] as? Int64 else { continue }

            let name = track["title"] as? String ?? track["lang"] as? String ?? "Track \(id)"
            let language = track["lang"] as? String ?? "Unknown"
            let codec = track["codec"] as? String ?? "Unknown"

            let trackInfo: [String: Any] = [
                "id": Int(id),
                "name": name,
                "language": language,
                "codec": codec,
                "isDefault": track["default"] as? Bool ?? false,
                "isForced": track["forced"] as? Bool ?? false
            ]

            switch type {
            case "audio":
                audio.append(trackInfo)
            case "sub":
                subtitle.append(trackInfo)
            default:
                break
            }
        }

        audioTracks = audio
        subtitleTracks = subtitle
    }

    // MARK: - HDR/EDR Support

    private func updateEDRMode(sigPeak: Double) {
        guard let layer = metalLayer else { return }

        var edrHeadroom: CGFloat = 1.0
        if #available(iOS 16.0, *) {
            edrHeadroom = containerView?.window?.screen.potentialEDRHeadroom ?? 1.0
        }

        let isHDRContent = sigPeak > 1.0
        let screenSupportsEDR = edrHeadroom > 1.0
        let shouldEnableEDR = hdrEnabled && isHDRContent && screenSupportsEDR

        if #available(iOS 16.0, *) {
            layer.wantsExtendedDynamicRangeContent = shouldEnableEDR
        }

        print("[MPVPlayerCore] EDR mode: \(shouldEnableEDR) (hdrEnabled: \(hdrEnabled), sigPeak: \(sigPeak), headroom: \(edrHeadroom))")
    }

    private func convertNode(_ node: mpv_node) -> Any? {
        switch node.format {
        case MPV_FORMAT_STRING:
            return node.u.string.map { String(cString: $0) }

        case MPV_FORMAT_FLAG:
            return node.u.flag != 0

        case MPV_FORMAT_INT64:
            return node.u.int64

        case MPV_FORMAT_DOUBLE:
            return node.u.double_

        case MPV_FORMAT_NODE_ARRAY:
            guard let list = node.u.list?.pointee else { return nil }
            var array = [Any]()
            for i in 0..<Int(list.num) {
                if let item = convertNode(list.values[i]) {
                    array.append(item)
                }
            }
            return array

        case MPV_FORMAT_NODE_MAP:
            guard let list = node.u.list?.pointee else { return nil }
            var dict = [String: Any]()
            for i in 0..<Int(list.num) {
                if let key = list.keys?[i].map({ String(cString: $0) }),
                    let val = convertNode(list.values[i])
                {
                    dict[key] = val
                }
            }
            return dict

        default:
            return nil
        }
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            print("[MPVPlayerCore] MPV error: \(String(cString: mpv_error_string(status)))")
        }
    }

    // MARK: - Playback Stats

    func getPlaybackStats() -> [String: Any] {
        guard mpv != nil else { return [:] }

        var stats: [String: Any] = [:]

        stats["currentTime"] = currentTime
        stats["duration"] = duration
        stats["isPaused"] = isPaused
        stats["isBuffering"] = isBuffering
        stats["videoWidth"] = videoWidth
        stats["videoHeight"] = videoHeight

        // Get additional stats from MPV
        if let fps = getProperty("estimated-vf-fps") {
            stats["fps"] = Double(fps) ?? 0
        }
        if let bitrate = getProperty("video-bitrate") {
            stats["videoBitrate"] = Int(bitrate) ?? 0
        }
        if let droppedFrames = getProperty("vo-delayed-frame-count") {
            stats["droppedFrames"] = Int(droppedFrames) ?? 0
        }
        if let cacheUsed = getProperty("demuxer-cache-duration") {
            stats["cacheSeconds"] = Double(cacheUsed) ?? 0
        }

        return stats
    }

    // MARK: - Cleanup

    func dispose() {
        isDisposing = true

        NotificationCenter.default.removeObserver(self)

        let mpvHandle = mpv
        mpv = nil

        queue.async {
            if let handle = mpvHandle {
                mpv_set_wakeup_callback(handle, nil, nil)
                mpv_terminate_destroy(handle)
            }
        }

        metalLayer?.removeFromSuperlayer()
        metalLayer = nil
        containerView?.removeFromSuperview()
        containerView = nil
        isInitialized = false
        print("[MPVPlayerCore] Disposed")
    }

    deinit {
        dispose()
    }
}
