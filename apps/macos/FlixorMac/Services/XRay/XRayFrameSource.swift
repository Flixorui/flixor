//
//  XRayFrameSource.swift
//  FlixorMac
//
//  A hidden, silent mpv that plays the same file as the player, ahead of it, and hands
//  X-Ray small frames (960 wide). Like the seek-bar thumbnail instance it renders into
//  an offscreen OpenGL framebuffer; unlike it, it plays forward instead of seeking for
//  every frame, so a stream is read once, in order.
//
//  Used from one thread only (XRayAnalyzer's), except `abort()`.
//

import Foundation
import AppKit
import OpenGL.GL
import OpenGL.GL3
import Libmpv

final class XRayFrameSource {
    struct Frame {
        let time: Double
        let image: CGImage
        /// RGBA, top row first.
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    enum Pump {
        case frame(Frame)
        /// A frame was shown but not wanted (between samples).
        case skipped
        case idle
        case ended
    }

    static let frameWidth = 960

    private var mpv: OpaquePointer?
    private var renderContext: OpaquePointer?
    private var glContext: CGLContextObj?
    private var fbo: GLuint = 0
    private var texture: GLuint = 0
    private var fboWidth = 0, fboHeight = 0
    private(set) var loadedURL: String?
    private var isShutDown = false
    /// Signalled by mpv when a new frame is ready (from mpv's thread).
    private let frameReady = DispatchSemaphore(value: 0)

    private let abortLock = NSLock()
    private var abortRequested = false
    private var isAborted: Bool {
        abortLock.lock(); defer { abortLock.unlock() }
        return abortRequested
    }

    /// `untimed`: decode as fast as possible (local and Plex files). Otherwise it plays
    /// at `speed`, which keeps a stream's extra download in check.
    init(untimed: Bool) {
        setupMPV(untimed: untimed)
        setupOpenGL()
    }

    deinit { shutdown() }

    // MARK: Setup

    private func setupMPV(untimed: Bool) {
        mpv = mpv_create()
        guard mpv != nil else { return }
        // No scripts or user config (see ThumbnailMPVPlayer: LuaJIT and the hardened runtime).
        setOption("config", "no")
        for option in MPVPlayerController.builtInScriptOptions { setOption(option, "no") }
        setOption("vo", "libmpv")
        setOption("gpu-api", "opengl")
        setOption("hwdec", "auto")
        setOption("pause", "yes")
        setOption("osd-level", "0")
        setOption("audio", "no")
        setOption("vid", "1")
        setOption("sub", "no")
        setOption("keep-open", "yes")
        setOption("idle", "yes")
        setOption("cache", "no")
        setOption("demuxer-max-bytes", "32MiB")
        setOption("demuxer-max-back-bytes", "0")
        setOption("demuxer-readahead-secs", "4")
        setOption("network-timeout", "30")
        // Cheaper decoding; a softer picture doesn't matter for faces at 960 wide.
        setOption("vd-lavc-skiploopfilter", "all")
        setOption("vd-lavc-fast", "yes")
        if untimed { setOption("untimed", "yes") }
        mpv_request_log_messages(mpv, "error")
        if mpv_initialize(mpv) < 0 {
            print("❌ [XRay] Hidden player failed to start")
            mpv_terminate_destroy(mpv)
            mpv = nil
        }
    }

    private func setupOpenGL() {
        guard mpv != nil else { return }
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAAccelerated,
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAColorSize, CGLPixelFormatAttribute(24),
            kCGLPFAAlphaSize, CGLPixelFormatAttribute(8),
            _CGLPixelFormatAttribute(rawValue: 0)
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        _ = attributes.withUnsafeBufferPointer { CGLChoosePixelFormat($0.baseAddress!, &pixelFormat, &count) }
        guard let pixelFormat else { return }
        defer { CGLDestroyPixelFormat(pixelFormat) }
        var context: CGLContextObj?
        CGLCreateContext(pixelFormat, nil, &context)
        guard let context else { return }
        glContext = context
        CGLLockContext(context)
        CGLSetCurrentContext(context)
        defer { CGLSetCurrentContext(nil); CGLUnlockContext(context) }

        var glInit = mpv_opengl_init_params(
            get_proc_address: { _, name in
                guard let name else { return nil }
                let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII)
                return CFBundleGetFunctionPointerForName(CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString), symbol)
            },
            get_proc_address_ctx: nil
        )
        let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var advanced: CInt = 1
        defer {
            // mpv calls this from its own threads; it may only signal.
            if let renderContext {
                mpv_render_context_set_update_callback(renderContext, { ctx in
                    guard let ctx else { return }
                    Unmanaged<DispatchSemaphore>.fromOpaque(ctx).takeUnretainedValue().signal()
                }, Unmanaged.passUnretained(frameReady).toOpaque())
            }
        }
        withUnsafeMutablePointer(to: &glInit) { glInitPtr in
            withUnsafeMutablePointer(to: &advanced) { advancedPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: glInitPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: advancedPtr),
                    mpv_render_param()
                ]
                if mpv_render_context_create(&renderContext, mpv, &params) < 0 {
                    print("❌ [XRay] Hidden player render context failed")
                }
            }
        }
    }

    /// (Re)creates the framebuffer at 960 wide and the video's aspect ratio. GL current.
    private func makeFramebuffer(width: Int, height: Int) {
        if fbo != 0 { glDeleteFramebuffers(1, &fbo); fbo = 0 }
        if texture != 0 { glDeleteTextures(1, &texture); texture = 0 }
        glGenFramebuffers(1, &fbo)
        glGenTextures(1, &texture)
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), nil)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), texture, 0)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        fboWidth = width
        fboHeight = height
    }

    private func setOption(_ name: String, _ value: String) {
        guard let mpv else { return }
        if mpv_set_option_string(mpv, name, value) < 0 {
            print("⚠️ [XRay] Hidden player option \(name) not accepted")
        }
    }

    // MARK: Control

    var isReady: Bool { mpv != nil && renderContext != nil && glContext != nil && !isShutDown }

    /// Opens the player's file with its network options. Blocking.
    func load(_ options: MPVNetworkLoadOptions) -> Bool {
        guard let mpv, isReady else { return false }
        if loadedURL == options.url { return true }
        loadedURL = nil
        for entry in UserDefaults.standard.getEnabledMpvConfigEntries()
        where MPVNetworkLoadOptions.networkConfigKeys.contains(entry.key) {
            mpv_set_property_string(mpv, entry.key, entry.value)
        }
        mpv_set_property_string(mpv, "tls-verify", options.verifyTLS ? "yes" : "no")
        if let caFile = MPVPlayerController.systemCAFile { mpv_set_property_string(mpv, "tls-ca-file", caFile) }
        if mpv_set_property_string(mpv, "stream-lavf-o", options.reconnectOptions) < 0 {
            mpv_set_property_string(mpv, "stream-lavf-o", MPVPlayerController.basicReconnectOptions)
        }
        mpv_set_property_string(mpv, "http-header-fields", options.headerFields)
        drainEvents()
        // The URL goes in as a separate argument (no quoting issues, never logged).
        var args: [UnsafePointer<CChar>?] = []
        let cmd = strdup("loadfile"), url = strdup(options.url), mode = strdup("replace")
        defer { free(cmd); free(url); free(mode) }
        args = [UnsafePointer(cmd), UnsafePointer(url), UnsafePointer(mode), nil]
        guard args.withUnsafeMutableBufferPointer({ mpv_command(mpv, $0.baseAddress) }) >= 0 else { return false }

        let deadline = Date().addingTimeInterval(30)
        var started = false
        while Date() < deadline, !isAborted {
            guard let event = mpv_wait_event(mpv, 0.25) else { return false }
            switch event.pointee.event_id {
            case MPV_EVENT_START_FILE: started = true
            case MPV_EVENT_FILE_LOADED:
                loadedURL = options.url
                return true
            case MPV_EVENT_END_FILE where started, MPV_EVENT_SHUTDOWN: return false
            default: continue
            }
        }
        return false
    }

    func seek(to time: Double) {
        guard let mpv else { return }
        // Keyframe seek: fast, and the analysis just starts from wherever it lands.
        mpv_command_string(mpv, "seek \(String(format: "%.2f", max(0, time))) absolute+keyframes")
    }

    func setPaused(_ paused: Bool) {
        guard let mpv else { return }
        mpv_set_property_string(mpv, "pause", paused ? "yes" : "no")
    }

    func setSpeed(_ speed: Double) {
        guard let mpv else { return }
        mpv_set_property_string(mpv, "speed", String(format: "%.2f", speed))
    }

    var position: Double? {
        guard let mpv else { return nil }
        var value: Double = 0
        return mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    func abort() {
        abortLock.lock(); abortRequested = true; abortLock.unlock()
    }

    // MARK: Frames

    /// Waits up to `timeout` for the next frame, renders it (mpv waits for that), and
    /// reads it back when `wants(time)` says so.
    func pump(timeout: Double, wants: (Double) -> Bool) -> Pump {
        guard let mpv, let renderContext, let glContext, isReady else { return .ended }
        while let event = mpv_wait_event(mpv, 0), event.pointee.event_id != MPV_EVENT_NONE {
            if event.pointee.event_id == MPV_EVENT_END_FILE || event.pointee.event_id == MPV_EVENT_SHUTDOWN { return .ended }
        }
        var eof: Int32 = 0
        if mpv_get_property(mpv, "eof-reached", MPV_FORMAT_FLAG, &eof) >= 0, eof != 0 { return .ended }

        _ = frameReady.wait(timeout: .now() + timeout)
        CGLLockContext(glContext)
        CGLSetCurrentContext(glContext)
        defer { CGLSetCurrentContext(nil); CGLUnlockContext(glContext) }

        guard mpv_render_context_update(renderContext) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 else { return .idle }
        let size = videoSize()
        if size.0 != fboWidth || size.1 != fboHeight { makeFramebuffer(width: size.0, height: size.1) }
        render(renderContext)
        guard let time = position, wants(time) else { return .skipped }
        guard let frame = readFrame(time: time) else { return .skipped }
        return .frame(frame)
    }

    /// 960 wide at the video's display aspect (even height).
    private func videoSize() -> (Int, Int) {
        guard let mpv else { return (Self.frameWidth, 540) }
        var w: Int64 = 0, h: Int64 = 0
        mpv_get_property(mpv, "dwidth", MPV_FORMAT_INT64, &w)
        mpv_get_property(mpv, "dheight", MPV_FORMAT_INT64, &h)
        guard w > 0, h > 0 else { return (Self.frameWidth, 540) }
        let height = max(2, Int((Double(Self.frameWidth) * Double(h) / Double(w) / 2).rounded()) * 2)
        return (Self.frameWidth, height)
    }

    private func render(_ renderContext: OpaquePointer) {
        var fboData = mpv_opengl_fbo(fbo: Int32(fbo), w: Int32(fboWidth), h: Int32(fboHeight), internal_format: 0)
        withUnsafeMutablePointer(to: &fboData) { fboPtr in
            var flip: Int32 = 1
            withUnsafeMutablePointer(to: &flip) { flipPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                    mpv_render_param()
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
    }

    private func readFrame(time: Double) -> Frame? {
        let w = fboWidth, h = fboHeight, rowBytes = w * 4
        guard w > 0, h > 0 else { return nil }
        var raw = [UInt8](repeating: 0, count: rowBytes * h)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glReadPixels(0, 0, GLsizei(w), GLsizei(h), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &raw)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        // OpenGL rows start at the bottom.
        var pixels = [UInt8](repeating: 0, count: rowBytes * h)
        raw.withUnsafeBytes { src in
            pixels.withUnsafeMutableBytes { dst in
                for y in 0..<h {
                    memcpy(dst.baseAddress! + (h - 1 - y) * rowBytes, src.baseAddress! + y * rowBytes, rowBytes)
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return Frame(time: time, image: image, pixels: pixels, width: w, height: h)
    }

    private func drainEvents() {
        guard let mpv else { return }
        while let event = mpv_wait_event(mpv, 0), event.pointee.event_id != MPV_EVENT_NONE {}
    }

    // MARK: Teardown

    /// Destroys mpv and the GL context. Blocking (mpv_terminate_destroy); never on main.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        loadedURL = nil
        if let glContext {
            CGLLockContext(glContext)
            CGLSetCurrentContext(glContext)
            if fbo != 0 { glDeleteFramebuffers(1, &fbo); fbo = 0 }
            if texture != 0 { glDeleteTextures(1, &texture); texture = 0 }
            // Freed with its GL context current, and before the semaphore it signals goes.
            if let renderContext { mpv_render_context_free(renderContext); self.renderContext = nil }
            CGLSetCurrentContext(nil)
            CGLUnlockContext(glContext)
        }
        if let renderContext { mpv_render_context_free(renderContext); self.renderContext = nil }
        if let mpv { mpv_terminate_destroy(mpv); self.mpv = nil }
        if let glContext { CGLDestroyContext(glContext); self.glContext = nil }
    }
}
