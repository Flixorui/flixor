//
//  ThumbnailMPVPlayer.swift
//  FlixorMac
//
//  Self-contained MPV instance for thumbnail generation
//

import Foundation
import AppKit
import OpenGL.GL
import OpenGL.GL3
import Libmpv

/// Lightweight MPV instance dedicated to thumbnail generation.
/// Created, used and shut down on MPVThumbnailGenerator's work queue, never on main:
/// `mpv_terminate_destroy` can block.
class ThumbnailMPVPlayer {
    // MARK: - Properties

    private var mpv: OpaquePointer?
    private var mpvRenderContext: OpaquePointer?
    private var openGLContext: CGLContextObj?
    private var thumbnailFBO: GLuint = 0
    private var thumbnailTexture: GLuint = 0

    private let thumbnailWidth: Int = 200
    private let thumbnailHeight: Int = 200

    private var currentVideoURL: String?
    private var isShutDown = false

    // Synchronization
    private let lock = NSLock()
    /// Set from any thread to end a load or seek wait early (player closing).
    private let abortLock = NSLock()
    private var abortRequested = false
    private var isAborted: Bool {
        abortLock.lock()
        defer { abortLock.unlock() }
        return abortRequested
    }

    // MARK: - Initialization

    init() {
        setupMPV()
        setupOpenGL()
    }

    deinit {
        // Normally already done by shutdown() on the work queue.
        cleanup()
    }

    // MARK: - Setup

    private func setupMPV() {
        // Create mpv instance
        mpv = mpv_create()
        guard mpv != nil else {
            print("❌ [ThumbnailMPV] Failed to create mpv instance")
            return
        }

        // No scripts and no user config. This mpv includes LuaJIT, whose compiled code
        // the hardened runtime kills the app for (it maps executable memory without
        // MAP_JIT). Each built-in script has its own switch; load-scripts only covers
        // script folders. Names not known to this mpv are rejected harmlessly.
        setOption("config", value: "no")
        for option in MPVPlayerController.builtInScriptOptions {
            setOption(option, value: "no")
        }

        // Configure options for thumbnail generation
        setOption("vo", value: "libmpv")
        setOption("gpu-api", value: "opengl")
        setOption("hwdec", value: "auto")
        setOption("pause", value: "yes") // Always paused
        setOption("osd-level", value: "0")
        setOption("audio", value: "no") // No audio needed
        setOption("vid", value: "1") // Only first video track
        setOption("sub", value: "no") // No subtitles
        // Small network footprint: playback has priority over previews. Seeks still
        // work over HTTP without the cache; mpv reads only what the next frame needs.
        setOption("cache", value: "no")
        setOption("demuxer-max-bytes", value: "8MiB")
        setOption("demuxer-max-back-bytes", value: "0")
        setOption("demuxer-readahead-secs", value: "0")
        setOption("network-timeout", value: "30")

        // Fast seeking for thumbnails
        setOption("hr-seek", value: "yes")

        // Disable logging
        mpv_request_log_messages(mpv, "error")

        // Initialize mpv
        let status = mpv_initialize(mpv)
        if status < 0 {
            print("❌ [ThumbnailMPV] Failed to initialize: \(String(cString: mpv_error_string(status)))")
            return
        }

        print("✅ [ThumbnailMPV] Initialized successfully")
    }

    private func setupOpenGL() {
        // Create OpenGL context for offscreen rendering
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAAccelerated,
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAColorSize, CGLPixelFormatAttribute(24),
            kCGLPFAAlphaSize, CGLPixelFormatAttribute(8),
            kCGLPFADepthSize, CGLPixelFormatAttribute(0),
            kCGLPFAStencilSize, CGLPixelFormatAttribute(0),
            _CGLPixelFormatAttribute(rawValue: 0)
        ]

        var pixelFormat: CGLPixelFormatObj?
        var numPixelFormats: GLint = 0

        attributes.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            CGLChoosePixelFormat(baseAddress, &pixelFormat, &numPixelFormats)
        }

        guard let pixelFormat = pixelFormat else {
            print("❌ [ThumbnailMPV] Failed to create pixel format")
            return
        }

        defer { CGLDestroyPixelFormat(pixelFormat) }

        var context: CGLContextObj?
        CGLCreateContext(pixelFormat, nil, &context)

        guard let context = context else {
            print("❌ [ThumbnailMPV] Failed to create OpenGL context")
            return
        }

        self.openGLContext = context

        // Make context current and setup render context
        CGLLockContext(context)
        CGLSetCurrentContext(context)

        setupRenderContext()
        createFramebuffer()

        CGLSetCurrentContext(nil)
        CGLUnlockContext(context)

        print("✅ [ThumbnailMPV] OpenGL context created")
    }

    private func setupRenderContext() {
        guard let mpv = mpv, let glContext = openGLContext else { return }

        var openGLInitParams = mpv_opengl_init_params(
            get_proc_address: { ctx, name in
                guard let name = name else { return nil }
                let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII)
                let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
                return CFBundleGetFunctionPointerForName(bundle, symbolName)
            },
            get_proc_address_ctx: nil
        )

        let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var advanced: CInt = 1

        withUnsafeMutablePointer(to: &openGLInitParams) { glInitParams in
            withUnsafeMutablePointer(to: &advanced) { advancedPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: glInitParams),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: advancedPtr),
                    mpv_render_param()
                ]

                let status = mpv_render_context_create(&mpvRenderContext, mpv, &params)
                if status < 0 {
                    print("❌ [ThumbnailMPV] Failed to create render context: \(String(cString: mpv_error_string(status)))")
                    return
                }

                print("✅ [ThumbnailMPV] Render context created")
            }
        }
    }

    private func createFramebuffer() {
        // Create framebuffer and texture for offscreen rendering
        glGenFramebuffers(1, &thumbnailFBO)
        glGenTextures(1, &thumbnailTexture)

        glBindTexture(GLenum(GL_TEXTURE_2D), thumbnailTexture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(thumbnailWidth), GLsizei(thumbnailHeight), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), thumbnailFBO)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), thumbnailTexture, 0)

        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            print("❌ [ThumbnailMPV] Framebuffer not complete: \(status)")
        }

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)

        print("✅ [ThumbnailMPV] Framebuffer created: \(thumbnailWidth)x\(thumbnailHeight)")
    }

    private func setOption(_ name: String, value: String) {
        guard let mpv = mpv else { return }
        let status = mpv_set_option_string(mpv, name, value)
        if status < 0 {
            print("⚠️ [ThumbnailMPV] Failed to set option \(name)=\(value): \(String(cString: mpv_error_string(status)))")
        }
    }

    // MARK: - Public Methods

    /// The URL loaded by the last successful `loadVideo`.
    var loadedURL: String? {
        lock.lock()
        defer { lock.unlock() }
        return currentVideoURL
    }

    /// Opens the file with the main player's network options (headers, TLS, reconnect)
    /// and waits until it has loaded. Blocking; returns false on failure or timeout.
    func loadVideo(options: MPVNetworkLoadOptions) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let mpv = mpv, !isShutDown else { return false }

        if currentVideoURL == options.url {
            // Already loaded
            return true
        }
        currentVideoURL = nil

        print("📸 [ThumbnailMPV] Loading video")
        for entry in UserDefaults.standard.getEnabledMpvConfigEntries()
        where MPVNetworkLoadOptions.networkConfigKeys.contains(entry.key) {
            mpv_set_property_string(mpv, entry.key, entry.value)
        }
        mpv_set_property_string(mpv, "tls-verify", options.verifyTLS ? "yes" : "no")
        if let caFile = MPVPlayerController.systemCAFile {
            mpv_set_property_string(mpv, "tls-ca-file", caFile)
        }
        if mpv_set_property_string(mpv, "stream-lavf-o", options.reconnectOptions) < 0 {
            mpv_set_property_string(mpv, "stream-lavf-o", MPVPlayerController.basicReconnectOptions)
        }
        mpv_set_property_string(mpv, "http-header-fields", options.headerFields)

        drainEvents(mpv)
        let status = mpv_command_string(mpv, "loadfile \"\(options.url)\" replace")
        if status < 0 {
            print("❌ [ThumbnailMPV] Failed to load file: \(String(cString: mpv_error_string(status)))")
            return false
        }

        guard waitForFileLoaded(mpv, timeout: 20) else {
            print("⚠️ [ThumbnailMPV] Timeout or error waiting for file load")
            return false
        }
        currentVideoURL = options.url
        print("✅ [ThumbnailMPV] File loaded")
        return true
    }

    /// Ends a running load or seek wait soon. Any thread.
    func abort() {
        abortLock.lock()
        abortRequested = true
        abortLock.unlock()
    }

    /// Destroys mpv and the GL context. Call off the main thread. Idempotent.
    func shutdown() {
        cleanup()
    }

    /// Generate a thumbnail at a specific timestamp
    func generateThumbnail(at time: Double) -> NSImage? {
        guard let mpv = mpv, let renderContext = mpvRenderContext, let glContext = openGLContext else {
            print("❌ [ThumbnailMPV] Not initialized")
            return nil
        }

        guard currentVideoURL != nil else {
            print("❌ [ThumbnailMPV] No video loaded")
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        CGLLockContext(glContext)
        CGLSetCurrentContext(glContext)
        defer {
            CGLSetCurrentContext(nil)
            CGLUnlockContext(glContext)
        }

        // Hand over a frame mpv may still be holding, so it can't count as the new one.
        drainEvents(mpv)
        if hasNewFrame(renderContext) { renderFrame(renderContext) }

        // Keyframe seek: much faster than an exact one, and close enough for a preview.
        let status = mpv_command_string(mpv, "seek \(String(format: "%.3f", time)) absolute+keyframes")
        if status < 0 {
            print("❌ [ThumbnailMPV] Seek failed: \(String(cString: mpv_error_string(status)))")
            return nil
        }

        // Wait for the seek to finish and its frame to arrive, instead of a fixed sleep
        // that could capture the previous position's frame on a slow (network) seek.
        // mpv waits for each frame to be rendered, so frames are rendered as they come.
        let deadline = Date().addingTimeInterval(2.5)
        var seekStarted = false
        var restarted = false
        var renderedNewFrame = false
        while !(restarted && renderedNewFrame) {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, !isAborted else {
                print("⚠️ [ThumbnailMPV] Seek to \(time)s timed out")
                return nil
            }
            if let event = mpv_wait_event(mpv, min(0.01, remaining)) {
                switch event.pointee.event_id {
                case MPV_EVENT_SEEK:
                    seekStarted = true
                case MPV_EVENT_PLAYBACK_RESTART:
                    restarted = true
                case MPV_EVENT_END_FILE, MPV_EVENT_SHUTDOWN:
                    return nil
                default:
                    break
                }
            }
            if hasNewFrame(renderContext) {
                // Frames before the seek started are rendered too, so mpv isn't held up,
                // but only a later one counts as the new position.
                renderFrame(renderContext)
                if seekStarted { renderedNewFrame = true }
            }
            if restarted && !renderedNewFrame {
                // mpv sends playback-restart only once the new frame has been shown, so
                // the current frame is the new one even if it was rendered just before.
                renderFrame(renderContext)
                renderedNewFrame = true
            }
        }

        // Read pixels from framebuffer
        let image = readFramebuffer()

        if image != nil {
            print("✅ [ThumbnailMPV] Generated thumbnail at \(time)s")
        } else {
            print("❌ [ThumbnailMPV] Failed to read framebuffer")
        }

        return image
    }

    // MARK: - Private Methods

    /// Waits for the new file's file-loaded event. The previous file's end comes
    /// before the new start, so an end only counts once the new file has started.
    /// Call with `lock` held.
    private func waitForFileLoaded(_ mpv: OpaquePointer, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var started = false
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, !isShutDown, !isAborted else { return false }
            guard let event = mpv_wait_event(mpv, min(0.25, remaining)) else { return false }
            switch event.pointee.event_id {
            case MPV_EVENT_START_FILE:
                started = true
            case MPV_EVENT_FILE_LOADED:
                return true
            case MPV_EVENT_END_FILE where started, MPV_EVENT_SHUTDOWN:
                return false
            default:
                continue
            }
        }
    }

    /// Discards queued events. Nothing else reads this instance's events; call with `lock` held.
    private func drainEvents(_ mpv: OpaquePointer) {
        while let event = mpv_wait_event(mpv, 0), event.pointee.event_id != MPV_EVENT_NONE {}
    }

    /// True when mpv has a frame waiting to be rendered. GL context current, `lock` held.
    private func hasNewFrame(_ renderContext: OpaquePointer) -> Bool {
        mpv_render_context_update(renderContext) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0
    }

    /// Renders mpv's current frame into the thumbnail FBO. GL context current, `lock` held.
    private func renderFrame(_ renderContext: OpaquePointer) {
        // MPV requires mpv_opengl_fbo struct, not just the FBO ID
        var fboData = mpv_opengl_fbo(
            fbo: Int32(thumbnailFBO),
            w: Int32(thumbnailWidth),
            h: Int32(thumbnailHeight),
            internal_format: 0 // 0 means GL_RGBA or GL_RGBA8
        )

        withUnsafeMutablePointer(to: &fboData) { fboPtr in
            var flipY: Int32 = 1
            withUnsafeMutablePointer(to: &flipY) { flipPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                    mpv_render_param()
                ]

                mpv_render_context_render(renderContext, &params)
            }
        }
    }

    private func readFramebuffer() -> NSImage? {
        // Read pixels from the framebuffer
        let bufferSize = thumbnailWidth * thumbnailHeight * 4
        var pixels = [UInt8](repeating: 0, count: bufferSize)

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), thumbnailFBO)
        glReadPixels(0, 0, GLsizei(thumbnailWidth), GLsizei(thumbnailHeight), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)

        // Flip the image vertically (OpenGL has origin at bottom-left, images at top-left)
        var flippedPixels = [UInt8](repeating: 0, count: bufferSize)
        let bytesPerRow = thumbnailWidth * 4
        for y in 0..<thumbnailHeight {
            let srcOffset = y * bytesPerRow
            let dstOffset = (thumbnailHeight - 1 - y) * bytesPerRow
            flippedPixels.withUnsafeMutableBytes { dstPtr in
                pixels.withUnsafeBytes { srcPtr in
                    let src = srcPtr.baseAddress!.advanced(by: srcOffset)
                    let dst = dstPtr.baseAddress!.advanced(by: dstOffset)
                    memcpy(dst, src, bytesPerRow)
                }
            }
        }

        // Create NSImage from flipped pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: NSData(bytes: flippedPixels, length: bufferSize)) else {
            return nil
        }

        guard let cgImage = CGImage(
            width: thumbnailWidth,
            height: thumbnailHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: thumbnailWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        let size = NSSize(width: thumbnailWidth, height: thumbnailHeight)
        return NSImage(cgImage: cgImage, size: size)
    }

    private func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        guard !isShutDown else { return }
        isShutDown = true
        currentVideoURL = nil

        if let glContext = openGLContext {
            CGLLockContext(glContext)
            CGLSetCurrentContext(glContext)

            if thumbnailFBO != 0 {
                glDeleteFramebuffers(1, &thumbnailFBO)
                thumbnailFBO = 0
            }
            if thumbnailTexture != 0 {
                glDeleteTextures(1, &thumbnailTexture)
                thumbnailTexture = 0
            }

            CGLSetCurrentContext(nil)
            CGLUnlockContext(glContext)
        }

        if let renderContext = mpvRenderContext {
            mpv_render_context_free(renderContext)
            mpvRenderContext = nil
        }

        if let mpv = mpv {
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }

        if let glContext = openGLContext {
            CGLDestroyContext(glContext)
            openGLContext = nil
        }

        print("✅ [ThumbnailMPV] Cleanup complete")
    }
}
