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

/// Lightweight MPV instance dedicated to thumbnail generation
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
    private var isReady = false

    // Synchronization
    private let lock = NSLock()

    // MARK: - Initialization

    init() {
        setupMPV()
        setupOpenGL()
    }

    deinit {
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

        // Configure options for thumbnail generation
        setOption("vo", value: "libmpv")
        setOption("gpu-api", value: "opengl")
        setOption("hwdec", value: "auto")
        setOption("pause", value: "yes") // Always paused
        setOption("osd-level", value: "0")
        setOption("audio", value: "no") // No audio needed
        setOption("vid", value: "1") // Only first video track
        setOption("sub", value: "no") // No subtitles
        setOption("cache", value: "yes")
        setOption("demuxer-readahead-secs", value: "5")

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

    /// Load a video file for thumbnail generation
    func loadVideo(url: String) {
        guard let mpv = mpv else { return }

        lock.lock()
        defer { lock.unlock() }

        if currentVideoURL == url {
            // Already loaded
            return
        }

        print("📸 [ThumbnailMPV] Loading video: \(url)")

        let commandString = "loadfile \"\(url)\" replace"
        let status = mpv_command_string(mpv, commandString)

        if status < 0 {
            print("❌ [ThumbnailMPV] Failed to load file: \(String(cString: mpv_error_string(status)))")
            return
        }

        currentVideoURL = url

        // Wait for file to load
        waitForFileLoaded()
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

        // Seek to timestamp
        print("📸 [ThumbnailMPV] Seeking to \(time)s")
        var timeValue = time
        mpv_set_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &timeValue)

        // Wait for seek to complete
        Thread.sleep(forTimeInterval: 0.1)

        // Render frame to our offscreen FBO
        CGLLockContext(glContext)
        CGLSetCurrentContext(glContext)

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

        // Read pixels from framebuffer
        let image = readFramebuffer()

        CGLSetCurrentContext(nil)
        CGLUnlockContext(glContext)

        if image != nil {
            print("✅ [ThumbnailMPV] Generated thumbnail at \(time)s")
        } else {
            print("❌ [ThumbnailMPV] Failed to read framebuffer")
        }

        return image
    }

    // MARK: - Private Methods

    private func waitForFileLoaded() {
        guard let mpv = mpv else { return }

        // Simple polling for file loaded
        for _ in 0..<50 { // 500ms max wait
            var paused: Int64 = 0
            mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &paused)

            let cstr = mpv_get_property_string(mpv, "path")
            if cstr != nil {
                mpv_free(cstr)
                isReady = true
                print("✅ [ThumbnailMPV] File loaded")
                return
            }

            Thread.sleep(forTimeInterval: 0.01)
        }

        print("⚠️ [ThumbnailMPV] Timeout waiting for file load")
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

        if let glContext = openGLContext {
            CGLLockContext(glContext)
            CGLSetCurrentContext(glContext)

            if thumbnailFBO != 0 {
                glDeleteFramebuffers(1, &thumbnailFBO)
            }
            if thumbnailTexture != 0 {
                glDeleteTextures(1, &thumbnailTexture)
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
