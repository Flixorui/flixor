//
//  MPVPlayerController.swift
//  FlixorTV
//
//  Core MPV player controller for tvOS
//  Phase 1: Basic structure without libmpv binary (stub implementation)
//

import Foundation
import Combine
import Metal
import GLKit

@MainActor
class MPVPlayerController: ObservableObject {
    // MARK: - Properties

    private var mpvHandle: OpaquePointer?
    private var renderContext: OpaquePointer?

    private var eventLoopQueue = DispatchQueue(label: "com.flixor.mpv.event", qos: .userInitiated)
    private var shouldStopEventLoop = false
    private var isInitialized = false
    private var options = MPVOptions()
    private var pendingFileURL: String?  // File to load after render context is ready
    private(set) var isPlaybackActive = false  // True after playback starts

    // Video dimensions
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    // MARK: - Published State

    @Published private(set) var state: MPVState = .uninitialized
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPaused: Bool = true
    @Published private(set) var volume: Double = 100
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var hdrMode: HDRMode = .sdr

    // MARK: - Callbacks

    /// Called when a property value changes
    /// - Parameters:
    ///   - property: Property name
    ///   - value: New value (type depends on property)
    var onPropertyChange: ((String, Any?) -> Void)?

    /// Called when an MPV event occurs
    /// - Parameter event: Event name
    var onEvent: ((String) -> Void)?

    /// Callback for when mpv requests a video redraw
    var videoUpdateCallback: (() -> Void)?

    /// Callback for HDR detection
    var onHDRDetected: ((Bool, String?, String?) -> Void)?

    /// Callback for when video dimensions are detected
    var onVideoDimensionsDetected: ((Int, Int) -> Void)?

    // MARK: - Initialization

    init() {
        print("🎬 [MPV] Initializing MPVPlayerController (Phase 1 - Stub)")
        setupMPV()
    }

    private func setupMPV() {
        state = .initializing

        // 1. Create MPV handle
        mpvHandle = mpv_create()
        guard mpvHandle != nil else {
            print("❌ [MPV] Failed to create instance")
            state = .error(MPVError.initializationFailed)
            return
        }

        print("✅ [MPV] MPV instance created")

        // 2. Set options (BEFORE mpv_initialize)
        let optionsDict = options.toDictionary()
        for (key, value) in optionsDict {
            setOption(key, value: value)
        }

        // 3. Initialize MPV
        let result = mpv_initialize(mpvHandle)
        guard result >= 0 else {
            print("❌ [MPV] Failed to initialize: \(result)")
            mpv_terminate_destroy(mpvHandle)
            mpvHandle = nil
            state = .error(MPVError.initializationFailed)
            return
        }

        print("✅ [MPV] MPV initialized successfully")

        // Enable log messages for debugging (use "info" to see what MPV is doing)
        mpv_request_log_messages(mpvHandle, "info")
        print("✅ [MPV] Log messages enabled (level: info)")

        // 4. Observe basic properties
        observeProperty(MPVProperty.timePos.rawValue, format: Int32(MPV_FORMAT_DOUBLE.rawValue))
        observeProperty(MPVProperty.duration.rawValue, format: Int32(MPV_FORMAT_DOUBLE.rawValue))
        observeProperty(MPVProperty.pause.rawValue, format: Int32(MPV_FORMAT_FLAG.rawValue))
        observeProperty(MPVProperty.volume.rawValue, format: Int32(MPV_FORMAT_DOUBLE.rawValue))
        observeProperty(MPVProperty.mute.rawValue, format: Int32(MPV_FORMAT_FLAG.rawValue))

        // Observe video properties for HDR detection
        observeProperty(MPVProperty.videoPrimaries.rawValue, format: Int32(MPV_FORMAT_STRING.rawValue))
        observeProperty(MPVProperty.videoGamma.rawValue, format: Int32(MPV_FORMAT_STRING.rawValue))

        // Observe video dimensions for dynamic FBO sizing
        observeProperty("video-params/w", format: Int32(MPV_FORMAT_INT64.rawValue))
        observeProperty("video-params/h", format: Int32(MPV_FORMAT_INT64.rawValue))

        // 5. Start event loop
        startEventLoop()

        isInitialized = true
        state = .ready
    }

    // MARK: - Option Setting

    private func setOption(_ name: String, value: String) {
        guard let handle = mpvHandle else { return }
        let result = mpv_set_option_string(handle, name, value)
        if result < 0 {
            print("⚠️ [MPV] Failed to set option \(name)=\(value): \(result)")
        } else {
            print("✅ [MPV] Set option: \(name)=\(value)")
        }
    }

    // MARK: - Property Observation

    private func observeProperty(_ name: String, format: Int32) {
        guard let handle = mpvHandle else { return }
        let result = mpv_observe_property(
            handle,
            0,  // reply_userdata (unused)
            name,
            mpv_format(rawValue: UInt32(format))
        )
        if result < 0 {
            print("⚠️ [MPV] Failed to observe property \(name): \(result)")
        } else {
            print("✅ [MPV] Observing property: \(name)")
        }
    }

    // MARK: - Event Loop

    private func startEventLoop() {
        eventLoopQueue.async { [weak self] in
            guard let self = self, let handle = self.mpvHandle else { return }

            print("🔄 [MPV] Event loop started")

            while !self.shouldStopEventLoop {
                let event = mpv_wait_event(handle, 1.0)  // 1 second timeout
                guard let event = event?.pointee,
                      event.event_id != MPV_EVENT_NONE else {
                    continue
                }

                // Handle log messages synchronously in the event loop (pointers only valid here)
                if event.event_id == MPV_EVENT_LOG_MESSAGE, let data = event.data {
                    let logEvent = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee

                    // Copy strings immediately while pointers are valid
                    let prefix = logEvent.prefix != nil ? String(cString: logEvent.prefix!) : ""
                    let level = logEvent.level != nil ? String(cString: logEvent.level!) : ""
                    let text = logEvent.text != nil ? String(cString: logEvent.text!) : ""

                    // Print on main thread after copying data
                    if !text.isEmpty && level != "v" && level != "trace" {
                        Task { @MainActor in
                            print("📝 [MPV:\(prefix)] [\(level)] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                        }
                    }
                    continue  // Don't pass log messages to handleEvent
                }

                Task { @MainActor [weak self] in
                    self?.handleEvent(event)
                }
            }

            print("🛑 [MPV] Event loop stopped")
        }
    }

    private func handleEvent(_ event: mpv_event) {
        let eventId = event.event_id

        switch eventId {
        case MPV_EVENT_PROPERTY_CHANGE:
            if let data = event.data {
                let propEvent = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                handlePropertyChange(propEvent)
            }

        case MPV_EVENT_FILE_LOADED:
            print("✅ [MPV] Event: File loaded")
            state = .ready

            // Enable video track now that file is loaded (tracks are available)
            if renderContext != nil {
                setProperty("vid", value: "1")  // Try explicit track ID instead of "auto"
                print("✅ [MPV] Video track #1 enabled after file load")

                // Ensure playback is not paused
                setProperty(MPVProperty.pause.rawValue, value: false)
                print("▶️ [MPV] Explicitly unpaused playback")

                // Start rendering immediately (advanced control mode requires us to pull frames)
                isPlaybackActive = true
                print("🎬 [MPV] Playback active - starting render loop")

                // Trigger first render
                videoUpdateCallback?()
            }

            onEvent?("file-loaded")

        case MPV_EVENT_PLAYBACK_RESTART:
            print("▶️ [MPV] Event: Playback started")
            state = .playing
            isPlaybackActive = true  // Enable priming renders

            // Debug: Check actual property values
            if let vidValue = getProperty("vid", type: .string) {
                print("🔍 [MPV] Current vid property: \(vidValue)")
            }
            if let pauseValue = getProperty("pause", type: .string) {
                print("🔍 [MPV] Current pause property: \(pauseValue)")
            }
            if let hwdecValue = getProperty("hwdec-current", type: .string) {
                print("🔍 [MPV] Current hwdec: \(hwdecValue)")
            }

            // Manually query video dimensions (property observation might miss them)
            queryVideoDimensions()

            // Trigger a render now that playback is active
            videoUpdateCallback?()
            print("🔔 [MPV] Triggered render callback after playback start")

            onEvent?("playback-restart")

        case MPV_EVENT_END_FILE:
            print("✅ [MPV] Event: File ended")
            state = .stopped
            onEvent?("file-ended")

        case MPV_EVENT_START_FILE:
            print("📺 [MPV] Event: File started")
            state = .loading
            onEvent?("file-started")

        case MPV_EVENT_SEEK:
            print("⏩ [MPV] Event: Seek")
            state = .seeking
            onEvent?("seek")

        default:
            print("ℹ️ [MPV] Event: \(eventId)")
        }
    }

    private func handlePropertyChange(_ event: mpv_event_property) {
        guard let propertyName = String(validatingUTF8: event.name) else { return }

        let value: Any?
        switch event.format {
        case MPV_FORMAT_DOUBLE:
            value = event.data.assumingMemoryBound(to: Double.self).pointee

        case MPV_FORMAT_FLAG:
            value = event.data.assumingMemoryBound(to: Int32.self).pointee != 0

        case MPV_FORMAT_STRING:
            if let cStr = event.data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee {
                value = String(cString: cStr)
            } else {
                value = nil
            }

        case MPV_FORMAT_INT64:
            value = event.data.assumingMemoryBound(to: Int64.self).pointee

        default:
            value = nil
        }

        // Update published properties
        switch propertyName {
        case MPVProperty.timePos.rawValue:
            if let time = value as? Double {
                currentTime = time
            }

        case MPVProperty.duration.rawValue:
            if let dur = value as? Double {
                duration = dur
            }

        case MPVProperty.pause.rawValue:
            if let paused = value as? Bool {
                isPaused = paused
                state = paused ? .paused : .playing
            }

        case MPVProperty.volume.rawValue:
            if let vol = value as? Double {
                volume = vol
            }

        case MPVProperty.mute.rawValue:
            if let muted = value as? Bool {
                isMuted = muted
            }

        case MPVProperty.videoPrimaries.rawValue,
             MPVProperty.videoGamma.rawValue:
            // Detect HDR when video properties change
            detectHDR()

        case "video-params/w":
            if let width = value as? Int64 {
                videoWidth = Int(width)
                checkAndNotifyVideoDimensions()
            }

        case "video-params/h":
            if let height = value as? Int64 {
                videoHeight = Int(height)
                checkAndNotifyVideoDimensions()
            }

        default:
            break
        }

        // Call callback
        onPropertyChange?(propertyName, value)
    }

    // MARK: - Playback Control

    func loadFile(_ url: String) {
        print("📺 [MPV] Loading file: \(url)")

        guard isInitialized else {
            print("❌ [MPV] Not initialized")
            return
        }

        // If render context is not ready, defer loading
        if renderContext == nil {
            print("⏳ [MPV] Render context not ready, deferring file load")
            pendingFileURL = url
            state = .loading
            return
        }

        // Render context ready, load immediately
        let cmd = ["loadfile", url, "replace"]
        command(cmd)
        state = .loading
    }

    func play() {
        print("▶️ [MPV] Play")
        setProperty(MPVProperty.pause.rawValue, value: false)
    }

    func pause() {
        print("⏸️ [MPV] Pause")
        setProperty(MPVProperty.pause.rawValue, value: true)
    }

    func seek(to seconds: Double) {
        print("⏩ [MPV] Seek to: \(seconds)s")
        let cmd = ["seek", String(seconds), "absolute"]
        command(cmd)
    }

    func setVolume(_ volume: Double) {
        print("🔊 [MPV] Set volume: \(volume)")
        setProperty(MPVProperty.volume.rawValue, value: volume)
    }

    func setMute(_ muted: Bool) {
        print("🔇 [MPV] Set mute: \(muted)")
        setProperty(MPVProperty.mute.rawValue, value: muted)
    }

    func setSpeed(_ speed: Double) {
        print("⚡ [MPV] Set speed: \(speed)x")
        setProperty(MPVProperty.speed.rawValue, value: speed)
    }

    // MARK: - Command Execution

    /// Execute MPV command with array of arguments
    private func command(_ args: [String]) {
        guard let handle = mpvHandle else { return }

        // Create C string array
        let cStrings = args.map { strdup($0) }
        var cArgs = cStrings.map { UnsafePointer<CChar>($0) }
        cArgs.append(nil)  // NULL-terminated array

        // Execute command
        let result = cArgs.withUnsafeMutableBufferPointer { buffer in
            mpv_command(handle, buffer.baseAddress)
        }

        // Free allocated C strings
        for cString in cStrings {
            free(cString)
        }

        if result < 0 {
            print("⚠️ [MPV] Command failed: \(args) (\(result))")
        } else {
            print("✅ [MPV] Command executed: \(args)")
        }
    }

    /// Execute MPV command from string (e.g., "cycle pause", "seek 10")
    func command(_ commandString: String) {
        let args = commandString.split(separator: " ").map(String.init)
        command(args)
    }

    // MARK: - Property Setting

    private func setProperty(_ name: String, value: Any) {
        guard let handle = mpvHandle else { return }

        var result: Int32 = -1

        switch value {
        case let boolValue as Bool:
            var flag: Int32 = boolValue ? 1 : 0
            result = mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)

        case let doubleValue as Double:
            var val = doubleValue
            result = mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &val)

        case let intValue as Int64:
            var val = intValue
            result = mpv_set_property(handle, name, MPV_FORMAT_INT64, &val)

        case let stringValue as String:
            result = mpv_set_property_string(handle, name, stringValue)

        default:
            print("⚠️ [MPV] Unsupported property value type for: \(name)")
            return
        }

        if result < 0 {
            print("⚠️ [MPV] Failed to set property \(name): \(result)")
        }
    }

    // MARK: - Rendering Setup

    func initializeRendering(openGLBridge: MPVOpenGLBridge) {
        guard let mpv = mpvHandle else {
            print("❌ [MPV] Cannot initialize rendering: mpv not initialized")
            return
        }

        print("🔧 [MPV] Initializing OpenGL ES rendering")

        // Setup OpenGL init params for iOS/tvOS
        var openGLInitParams = mpv_opengl_init_params(
            get_proc_address: { ctx, name in
                guard let name = name else { return nil }
                let symbolName = CFStringCreateWithCString(
                    kCFAllocatorDefault,
                    name,
                    kCFStringEncodingASCII
                )
                let funcName = String(cString: name)

                // Use OpenGL ES framework on iOS/tvOS
                let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengles" as CFString)
                let funcPtr = CFBundleGetFunctionPointerForName(bundle, symbolName)

                if funcPtr == nil {
                    print("⚠️ [MPV] Failed to load OpenGL function: \(funcName)")
                } else {
                    // Only log first few to avoid spam
                    if funcName == "glGetString" || funcName == "glGetIntegerv" {
                        print("✅ [MPV] Loaded OpenGL function: \(funcName)")
                    }
                }

                return funcPtr
            },
            get_proc_address_ctx: nil
        )

        // Setup render params
        let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var advanced: CInt = 1  // Use advanced control so we can specify custom FBO

        withUnsafeMutablePointer(to: &openGLInitParams) { glInitParams in
            withUnsafeMutablePointer(to: &advanced) { advancedPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: glInitParams),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: advancedPtr),
                    mpv_render_param()
                ]

                let status = mpv_render_context_create(&renderContext, mpv, &params)
                if status < 0 {
                    print("❌ [MPV] Failed to create render context: \(status)")
                    return
                }

                // Set update callback
                mpv_render_context_set_update_callback(renderContext, { ctx in
                    guard let ctx = ctx else { return }
                    let controller = Unmanaged<MPVPlayerController>.fromOpaque(ctx).takeUnretainedValue()
                    DispatchQueue.main.async {
                        controller.videoUpdateCallback?()
                    }
                }, Unmanaged.passUnretained(self).toOpaque())

                print("✅ [MPV] OpenGL ES render context created")

                // If there's a pending file, load it now
                // (Video track will be enabled after file loads in MPV_EVENT_FILE_LOADED)
                if let pendingURL = self.pendingFileURL {
                    print("▶️ [MPV] Loading pending file: \(pendingURL)")
                    self.pendingFileURL = nil
                    let cmd = ["loadfile", pendingURL, "replace"]
                    self.command(cmd)
                }
            }
        }
    }

    private var renderCheckCount = 0
    private var lastRenderLogTime = Date()

    func shouldRenderUpdateFrame() -> Bool {
        guard let renderContext = renderContext else {
            print("⚠️ [MPV] No render context in shouldRenderUpdateFrame")
            return false
        }

        let flags = mpv_render_context_update(renderContext)
        let hasFrame = (flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue)) != 0

        // Log every 2 seconds for debugging
        renderCheckCount += 1
        let now = Date()
        if now.timeIntervalSince(lastRenderLogTime) >= 2.0 {
            print("🔍 [MPV] Render check: \(renderCheckCount) calls in 2s, hasFrame: \(hasFrame), flags: \(flags)")
            renderCheckCount = 0
            lastRenderLogTime = now
        }

        return hasFrame
    }

    func getRenderContext() -> OpaquePointer? {
        // TODO: Phase 2.5 - Return actual render context
        return renderContext
    }

    func reportSwap() {
        guard let renderContext = renderContext else { return }
        mpv_render_context_report_swap(renderContext)
    }

    private var renderCount = 0

    /// Render MPV frame to OpenGL FBO
    func renderToOpenGL(fbo: GLuint, width: Int32, height: Int32, flip: Bool = true) {
        guard let renderContext = renderContext else {
            print("⚠️ [MPV] No render context available")
            return
        }

        renderCount += 1
        let isFirstRender = renderCount == 1

        if isFirstRender {
            print("🎨 [MPV] First renderToOpenGL call - FBO: \(fbo), size: \(width)x\(height)")
        }

        // Use internal_format=0 to let MPV auto-detect
        // With videotoolbox-copy, MPV should output RGB correctly
        var fboData = mpv_opengl_fbo(
            fbo: Int32(fbo),
            w: width,
            h: height,
            internal_format: 0
        )

        var flipY: CInt = flip ? 1 : 0
        var bufferDepth: GLint = 16  // 16-bit color depth for HDR (was 8 for SDR)

        withUnsafeMutablePointer(to: &fboData) { fboPtr in
            withUnsafeMutablePointer(to: &flipY) { flipPtr in
                withUnsafeMutablePointer(to: &bufferDepth) { depthPtr in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_DEPTH, data: depthPtr),
                        mpv_render_param()
                    ]

                    let result = mpv_render_context_render(renderContext, &params)

                    if isFirstRender {
                        if result >= 0 {
                            print("✅ [MPV] First render succeeded (result: \(result))")
                        } else {
                            print("❌ [MPV] First render failed (result: \(result))")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Video Dimension Detection

    private func checkAndNotifyVideoDimensions() {
        // Only notify if we have valid dimensions
        guard videoWidth > 0 && videoHeight > 0 else {
            return
        }

        print("📐 [MPV] Video dimensions detected: \(videoWidth)x\(videoHeight)")
        onVideoDimensionsDetected?(videoWidth, videoHeight)
    }

    /// Manually query video dimensions from MPV
    private func queryVideoDimensions() {
        guard let handle = mpvHandle else { return }

        // Query width
        var width: Int64 = 0
        let widthResult = mpv_get_property(handle, "video-params/w", MPV_FORMAT_INT64, &width)

        // Query height
        var height: Int64 = 0
        let heightResult = mpv_get_property(handle, "video-params/h", MPV_FORMAT_INT64, &height)

        if widthResult == 0 && heightResult == 0 && width > 0 && height > 0 {
            print("📐 [MPV] Manually queried video dimensions: \(width)x\(height)")
            videoWidth = Int(width)
            videoHeight = Int(height)
            checkAndNotifyVideoDimensions()
        } else {
            print("⚠️ [MPV] Failed to query video dimensions (width result: \(widthResult), height result: \(heightResult))")
        }
    }

    // MARK: - HDR Detection & Configuration

    private func detectHDR() {
        // Get video properties
        guard let gamma = getProperty(MPVProperty.videoGamma.rawValue, type: .string),
              let primaries = getProperty(MPVProperty.videoPrimaries.rawValue, type: .string) else {
            return
        }

        // HDR videos use PQ (Perceptual Quantizer) or HLG (Hybrid Log-Gamma)
        let isHDR = gamma == "pq" || gamma == "hlg"

        if isHDR {
            print("🌈 [MPV] HDR detected! Gamma: \(gamma), Primaries: \(primaries)")
            hdrMode = .hdr
        } else {
            hdrMode = .sdr
        }

        // Notify via callback
        onHDRDetected?(isHDR, gamma, primaries)
    }

    func setHDRProperties(primaries: String) {
        guard mpvHandle != nil else { return }

        // Clear video filters for HDR (let MPV handle it natively)
        setProperty("vf", value: "")

        // Disable ICC profile for HDR
        setProperty("icc-profile-auto", value: false)

        // Enable native HDR output (no tone-mapping)
        // MPV will output HDR values directly in PQ/HLG transfer function
        setProperty("tone-mapping", value: "auto")  // Auto disables tone-mapping for HDR displays
        setProperty("target-trc", value: "auto")     // Auto-detect (will use PQ/HLG)
        setProperty("target-prim", value: primaries) // Preserve source primaries (bt.2020)
        setProperty("target-peak", value: "auto")    // Auto-detect display peak brightness
        setProperty("hdr-compute-peak", value: "yes") // Use video metadata

        print("✅ [MPV] Native HDR passthrough enabled (primaries: \(primaries), no tone-mapping)")
    }

    func setSDRProperties() {
        guard mpvHandle != nil else { return }

        // Clear video filters first
        setProperty("vf", value: "")

        // Set SDR color space explicitly (bt.709 is standard for HD SDR content)
        setProperty("vf", value: "format=colormatrix=bt.709")

        // Set auto properties for SDR
        setProperty("target-trc", value: "auto")
        setProperty("target-prim", value: "auto")
        setProperty("target-peak", value: "auto")
        setProperty("tone-mapping", value: "auto")

        print("✅ [MPV] SDR properties set (colormatrix=bt.709)")
    }

    private func getProperty(_ name: String, type: PropertyType) -> String? {
        guard let handle = mpvHandle else { return nil }

        switch type {
        case .string:
            let cstr = mpv_get_property_string(handle, name)
            let str = cstr == nil ? nil : String(cString: cstr!)
            mpv_free(cstr)
            return str
        default:
            return nil
        }
    }

    // MARK: - Shutdown

    func shutdown() {
        print("🛑 [MPV] Shutting down")

        shouldStopEventLoop = true

        // Clear callbacks first
        videoUpdateCallback = nil
        onPropertyChange = nil
        onEvent = nil
        onHDRDetected = nil
        onVideoDimensionsDetected = nil

        // Free render context before terminating MPV
        if let renderContext = renderContext {
            print("🛑 [MPV] Freeing render context...")
            mpv_render_context_set_update_callback(renderContext, nil, nil)
            mpv_render_context_free(renderContext)
            self.renderContext = nil
            print("✅ [MPV] Render context freed")
        }

        // Terminate MPV
        if let handle = mpvHandle {
            mpv_terminate_destroy(handle)
            mpvHandle = nil
        }

        isInitialized = false
        state = .uninitialized

        print("🧹 [MPV] Shutdown complete")
    }

    // MARK: - Deinitialization

    deinit {
        print("🗑️ [MPV] MPVPlayerController deinit")
        // Note: Cannot call @MainActor shutdown() from deinit
        // Resources are cleaned up automatically
        shouldStopEventLoop = true
    }
}

// MARK: - Supporting Types

enum PropertyType {
    case string
}

// MARK: - Phase 1 Testing Extension

extension MPVPlayerController {
    /// Phase 1: Test method to verify controller creation
    static func testCreation() -> Bool {
        let controller = MPVPlayerController()

        guard controller.state == .ready else {
            print("❌ [MPV Test] State is not ready: \(controller.state)")
            return false
        }

        print("✅ [MPV Test] Controller created successfully")
        return true
    }

    /// Phase 1: Test method to verify shutdown
    static func testShutdown() -> Bool {
        let controller = MPVPlayerController()
        controller.shutdown()

        guard controller.state == .uninitialized else {
            print("❌ [MPV Test] State is not uninitialized after shutdown")
            return false
        }

        print("✅ [MPV Test] Shutdown successful")
        return true
    }

    /// Phase 1: Test method to verify playback control stubs
    static func testPlaybackControls() -> Bool {
        let controller = MPVPlayerController()

        // Test load
        controller.loadFile("test://url")

        // Test play/pause
        controller.play()
        guard !controller.isPaused else {
            print("❌ [MPV Test] Play didn't update state")
            return false
        }

        controller.pause()
        guard controller.isPaused else {
            print("❌ [MPV Test] Pause didn't update state")
            return false
        }

        // Test seek
        controller.seek(to: 30.0)
        guard controller.currentTime == 30.0 else {
            print("❌ [MPV Test] Seek didn't update currentTime")
            return false
        }

        print("✅ [MPV Test] Playback controls work")
        return true
    }
}
