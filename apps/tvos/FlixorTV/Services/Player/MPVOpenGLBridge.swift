//
//  MPVOpenGLBridge.swift
//  FlixorTV
//
//  OpenGL ES bridge for MPV rendering on tvOS
//  Creates EAGL context and manages OpenGL FBO backed by IOSurface
//  Phase 2.5: Option A - OpenGL ES + IOSurface Bridge
//

import Foundation
import GLKit
import OpenGLES
import IOSurface
import CoreVideo

class MPVOpenGLBridge {
    // MARK: - Properties

    private var eaglContext: EAGLContext?
    private var framebuffer: GLuint = 0
    private var colorRenderbuffer: GLuint = 0
    private var ioSurface: IOSurface?
    private var textureCache: CVOpenGLESTextureCache?
    private var texture: CVOpenGLESTexture?

    private var width: Int = 0
    private var height: Int = 0

    // Debug flags
    private var hasFBOVerified = false
    private var hasErrorChecked = false

    // Use BGRA format - the ONLY format reliably compatible with IOSurface on iOS/tvOS
    // HDR will be handled via colorspace configuration in Metal, not pixel format
    private let pixelFormat: OSType = kCVPixelFormatType_32BGRA

    // MARK: - Initialization

    init() {
        print("🔧 [OpenGLBridge] Initializing")
    }

    /// Setup OpenGL ES 3.0 context and resources
    func setupOpenGL(width: Int, height: Int) -> Bool {
        print("🔧 [OpenGLBridge] Setting up OpenGL ES context (\(width)x\(height))")

        self.width = width
        self.height = height

        // 1. Create OpenGL ES 3.0 context
        if let context = EAGLContext(api: .openGLES3) {
            self.eaglContext = context
            print("✅ [OpenGLBridge] Created OpenGL ES 3.0 context")
        } else {
            print("❌ [OpenGLBridge] Failed to create EAGL context (ES 3.0)")

            // Try ES 2.0 as fallback
            if let context2 = EAGLContext(api: .openGLES2) {
                print("⚠️ [OpenGLBridge] Using OpenGL ES 2.0 fallback")
                self.eaglContext = context2
            } else {
                print("❌ [OpenGLBridge] Failed to create EAGL context (ES 2.0)")
                return false
            }
        }

        // 2. Make context current
        guard EAGLContext.setCurrent(eaglContext) else {
            print("❌ [OpenGLBridge] Failed to set current EAGL context")
            return false
        }

        print("✅ [OpenGLBridge] EAGL context created (API: \(eaglContext!.api.rawValue))")

        // 3. Create texture cache
        let result = CVOpenGLESTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            eaglContext!,
            nil,
            &textureCache
        )

        guard result == kCVReturnSuccess, textureCache != nil else {
            print("❌ [OpenGLBridge] Failed to create texture cache: \(result)")
            return false
        }

        print("✅ [OpenGLBridge] OpenGL ES texture cache created")

        // 4. Create IOSurface-backed framebuffer
        if !createIOSurfaceFramebuffer() {
            print("❌ [OpenGLBridge] Failed to create IOSurface framebuffer")
            return false
        }

        print("✅ [OpenGLBridge] OpenGL ES setup complete")
        return true
    }

    // MARK: - Framebuffer Creation

    private func createSimpleFramebuffer() -> Bool {
        print("🔧 [OpenGLBridge] Creating simple renderbuffer (fallback, no IOSurface)")

        guard EAGLContext.setCurrent(eaglContext) else {
            print("❌ [OpenGLBridge] Failed to set current context")
            return false
        }

        // Create framebuffer
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        // Create and attach renderbuffer
        glGenRenderbuffers(1, &colorRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)

        // Allocate storage for renderbuffer
        glRenderbufferStorage(
            GLenum(GL_RENDERBUFFER),
            GLenum(GL_RGBA8),
            GLsizei(width),
            GLsizei(height)
        )

        // Attach renderbuffer to framebuffer
        glFramebufferRenderbuffer(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_RENDERBUFFER),
            colorRenderbuffer
        )

        // Check framebuffer status
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            print("❌ [OpenGLBridge] Framebuffer incomplete: \(status)")
            return false
        }

        // Setup viewport
        glViewport(0, 0, GLsizei(width), GLsizei(height))

        // Unbind
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), 0)

        print("✅ [OpenGLBridge] Simple framebuffer created (FBO: \(framebuffer), RBO: \(colorRenderbuffer))")
        print("⚠️ [OpenGLBridge] Warning: No IOSurface - will need glReadPixels for Metal transfer")

        return true
    }

    private func createIOSurfaceFramebuffer() -> Bool {
        print("🔧 [OpenGLBridge] Creating IOSurface-backed framebuffer")

        guard EAGLContext.setCurrent(eaglContext) else {
            print("❌ [OpenGLBridge] Failed to set current context")
            return false
        }

        // 1. Create IOSurface with proper alignment for OpenGL ES
        // BGRA = 4 bytes per pixel (8-bit × 4 channels)
        let bytesPerPixel = 4
        let bytesPerRow = ((width * bytesPerPixel) + 63) & ~63  // 64-byte alignment
        let surfaceAttributes: [String: Any] = [
            kIOSurfaceWidth as String: width,
            kIOSurfaceHeight as String: height,
            kIOSurfaceBytesPerElement as String: bytesPerPixel,
            kIOSurfaceBytesPerRow as String: bytesPerRow,
            kIOSurfacePixelFormat as String: pixelFormat,
            kIOSurfaceIsGlobal as String: true  // Allow sharing with Metal
        ]

        guard let surface = IOSurfaceCreate(surfaceAttributes as CFDictionary) else {
            print("❌ [OpenGLBridge] Failed to create IOSurface")
            return false
        }

        self.ioSurface = surface
        print("✅ [OpenGLBridge] IOSurface created (\(width)x\(height), format: BGRA8, aligned: \(bytesPerRow) bytes/row, HDR via colorspace)")

        // 2. Create CVPixelBuffer from IOSurface with OpenGL ES compatibility
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferOpenGLESCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var unmanagedPixelBuffer: Unmanaged<CVPixelBuffer>?
        let pbResult = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            surface,
            pixelBufferAttributes as CFDictionary,
            &unmanagedPixelBuffer
        )

        guard pbResult == kCVReturnSuccess, let unmanagedPB = unmanagedPixelBuffer else {
            print("❌ [OpenGLBridge] Failed to create CVPixelBuffer from IOSurface: \(pbResult)")
            return false
        }

        let pixelBuffer = unmanagedPB.takeRetainedValue()

        // Verify pixel buffer properties
        let pbWidth = CVPixelBufferGetWidth(pixelBuffer)
        let pbHeight = CVPixelBufferGetHeight(pixelBuffer)
        let pbFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isOpenGLCompatible = CVPixelBufferGetPixelFormatType(pixelBuffer) != 0

        print("✅ [OpenGLBridge] CVPixelBuffer created: \(pbWidth)x\(pbHeight), format: \(String(format: "0x%X", pbFormat)), OpenGL compatible: \(isOpenGLCompatible)")

        // Check OpenGL ES texture size limits
        var maxTextureSize: GLint = 0
        glGetIntegerv(GLenum(GL_MAX_TEXTURE_SIZE), &maxTextureSize)
        print("ℹ️ [OpenGLBridge] OpenGL ES max texture size: \(maxTextureSize)")

        if width > Int(maxTextureSize) || height > Int(maxTextureSize) {
            print("❌ [OpenGLBridge] Requested size (\(width)x\(height)) exceeds max texture size (\(maxTextureSize))")
            return false
        }

        // 3. Create OpenGL ES texture from CVPixelBuffer
        // IOSurface is BGRA (only iOS/tvOS format compatible with IOSurface)
        // MPV renders RGBA → stored as BGRA in IOSurface (R↔B swapped)
        // We'll fix with Metal texture swizzle when reading IOSurface

        var textureRef: CVOpenGLESTexture?
        let result = CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache!,
            pixelBuffer,  // CVPixelBuffer backed by IOSurface (BGRA format)
            nil,
            GLenum(GL_TEXTURE_2D),
            GLint(GL_RGBA),             // Internal: GL_RGBA (what MPV writes)
            GLsizei(width),
            GLsizei(height),
            GLenum(GL_RGBA),            // Source: GL_RGBA (matches MPV output)
            GLenum(GL_UNSIGNED_BYTE),   // Type: 8-bit unsigned byte
            0,
            &textureRef
        )

        guard result == kCVReturnSuccess, let textureRef = textureRef else {
            print("❌ [OpenGLBridge] Failed to create texture from IOSurface-backed CVPixelBuffer: \(result)")
            print("⚠️ [OpenGLBridge] Falling back to simple renderbuffer approach (no IOSurface)")

            // Clear IOSurface since we can't use it
            self.ioSurface = nil

            // Fallback: Create a simple renderbuffer (no IOSurface)
            return createSimpleFramebuffer()
        }

        self.texture = textureRef
        let textureID = CVOpenGLESTextureGetName(textureRef)
        print("✅ [OpenGLBridge] OpenGL texture created from CVPixelBuffer+IOSurface (ID: \(textureID))")

        // 4. Create framebuffer
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        // 5. Attach texture to framebuffer
        glFramebufferTexture2D(
            GLenum(GL_FRAMEBUFFER),
            GLenum(GL_COLOR_ATTACHMENT0),
            GLenum(GL_TEXTURE_2D),
            textureID,
            0
        )

        // 6. Check framebuffer status
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        if status != GLenum(GL_FRAMEBUFFER_COMPLETE) {
            print("❌ [OpenGLBridge] Framebuffer incomplete: \(status)")
            return false
        }

        // 7. Setup viewport
        glViewport(0, 0, GLsizei(width), GLsizei(height))

        // Unbind framebuffer
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)

        print("✅ [OpenGLBridge] Framebuffer created and configured (FBO: \(framebuffer))")
        return true
    }

    // MARK: - Rendering

    /// Get OpenGL framebuffer for MPV rendering
    func getFramebuffer() -> GLuint {
        return framebuffer
    }

    /// Get IOSurface for Metal texture creation
    func getIOSurface() -> IOSurface? {
        return ioSurface
    }

    /// Bind framebuffer for rendering
    func bindFramebuffer() {
        guard EAGLContext.setCurrent(eaglContext) else {
            print("⚠️ [OpenGLBridge] Failed to set current context")
            return
        }
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        // Verify framebuffer is complete (only log once)
        if !hasFBOVerified {
            let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
            if status == GLenum(GL_FRAMEBUFFER_COMPLETE) {
                print("✅ [OpenGLBridge] FBO is complete and ready for rendering")
            } else {
                print("❌ [OpenGLBridge] FBO is NOT complete! Status: 0x\(String(format: "%X", status))")
            }
            hasFBOVerified = true
        }
    }

    /// Unbind framebuffer after rendering
    func unbindFramebuffer() {
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    /// Finish rendering and ensure GPU commands complete
    func finishRendering() {
        glFinish()

        // Check for OpenGL errors after rendering (only log once)
        if !hasErrorChecked {
            let error = glGetError()
            if error != GLenum(GL_NO_ERROR) {
                print("❌ [OpenGLBridge] OpenGL error after rendering: 0x\(String(format: "%X", error))")
            } else {
                print("✅ [OpenGLBridge] No OpenGL errors after rendering")
            }
            hasErrorChecked = true
        }
    }

    /// Read pixels from framebuffer (fallback when IOSurface not available)
    func readPixels() -> Data? {
        guard framebuffer != 0 else {
            print("⚠️ [OpenGLBridge] No framebuffer available")
            return nil
        }

        guard EAGLContext.setCurrent(eaglContext) else {
            print("⚠️ [OpenGLBridge] Failed to set current context")
            return nil
        }

        // Bind framebuffer
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)

        // Allocate buffer for pixel data (BGRA, 4 bytes per pixel)
        let dataSize = width * height * 4
        var pixelData = Data(count: dataSize)

        // Read pixels from framebuffer
        // Use RGBA for simple renderbuffer (fallback), BGRA would only work with IOSurface
        let GL_BGRA_EXT: GLenum = 0x80E1
        pixelData.withUnsafeMutableBytes { ptr in
            glReadPixels(
                0, 0,
                GLsizei(width),
                GLsizei(height),
                GLenum(GL_RGBA),  // Use RGBA for compatibility with simple renderbuffer
                GLenum(GL_UNSIGNED_BYTE),
                ptr.baseAddress
            )
        }

        // Check for OpenGL errors
        let error = glGetError()
        if error != GLenum(GL_NO_ERROR) {
            print("❌ [OpenGLBridge] glReadPixels error: \(error)")
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
            return nil
        }

        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
        return pixelData
    }

    /// Get framebuffer dimensions
    func getSize() -> (width: Int, height: Int) {
        return (width, height)
    }

    // MARK: - Resize

    func resize(width: Int, height: Int) {
        guard self.width != width || self.height != height else {
            return  // No change
        }

        print("🔧 [OpenGLBridge] Resizing (\(self.width)x\(self.height) → \(width)x\(height))")

        // Cleanup old resources
        cleanup()

        // Recreate with new size
        _ = setupOpenGL(width: width, height: height)
    }

    // MARK: - Cleanup

    func cleanup() {
        print("🧹 [OpenGLBridge] Cleaning up")

        guard EAGLContext.setCurrent(eaglContext) else {
            print("⚠️ [OpenGLBridge] Failed to set current context for cleanup")
            return
        }

        // Delete framebuffer
        if framebuffer != 0 {
            glDeleteFramebuffers(1, &framebuffer)
            framebuffer = 0
        }

        // Delete renderbuffer (if using fallback)
        if colorRenderbuffer != 0 {
            glDeleteRenderbuffers(1, &colorRenderbuffer)
            colorRenderbuffer = 0
        }

        // Release texture
        texture = nil

        // Flush texture cache
        if let cache = textureCache {
            CVOpenGLESTextureCacheFlush(cache, 0)
        }

        // Release IOSurface
        ioSurface = nil

        print("✅ [OpenGLBridge] Cleanup complete")
    }

    deinit {
        cleanup()
        print("🗑️ [OpenGLBridge] Deinitialized")
    }
}
