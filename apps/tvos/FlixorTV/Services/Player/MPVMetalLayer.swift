//
//  MPVMetalLayer.swift
//  FlixorTV
//
//  CAMetalLayer for MPV video rendering on tvOS
//  Adapted from macOS OpenGL implementation
//

import UIKit
import Metal
import MetalKit
import CoreVideo
import IOSurface

class MPVMetalLayer: CAMetalLayer {
    weak var mpvController: MPVPlayerController?
    private var openGLBridge: MPVOpenGLBridge?

    private let metalDevice: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var bufferDepth: Int32 = 8

    // Metal texture cache for IOSurface
    private var metalTextureCache: CVMetalTextureCache?

    // Metal render pipeline for video rendering (replaces blit for swizzle support)
    private var renderPipelineState: MTLRenderPipelineState?

    // Debug counters
    private var updateCallbackCount = 0
    private var lastUpdateCallbackLog = Date()

    override init() {
        // Get default Metal device
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("❌ [MPVLayer] Failed to create Metal device")
        }

        self.metalDevice = metalDevice

        // Create command queue
        guard let queue = metalDevice.makeCommandQueue() else {
            fatalError("❌ [MPVLayer] Failed to create Metal command queue")
        }

        self.commandQueue = queue

        super.init()

        // Configure Metal layer for HDR support
        self.device = metalDevice
        self.pixelFormat = .bgra8Unorm   // 8-bit BGRA (only format supported by IOSurface on tvOS)
        self.framebufferOnly = false     // Allow reading back for screenshots

        // Configure layer properties
        isOpaque = true
        contentsScale = UIScreen.main.scale

        // Default to HDR colorspace (will be set properly when content loads)
        // On tvOS, EDR is automatically enabled when using correct colorspace
        // HDR is achieved via colorspace configuration, not pixel format
        if let hdrColorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ) {
            self.colorspace = hdrColorspace
        }

        print("✅ [MPVLayer] Initialized with BGRA8 + HDR colorspace for native HDR playback (tvOS auto-EDR)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func setupMPVRendering(controller: MPVPlayerController, openGLBridge: MPVOpenGLBridge) {
        self.mpvController = controller
        self.openGLBridge = openGLBridge

        // Create Metal texture cache for IOSurface
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            metalDevice,
            nil,
            &metalTextureCache
        )

        if result != kCVReturnSuccess || metalTextureCache == nil {
            print("❌ [MPVLayer] Failed to create Metal texture cache: \(result)")
            return
        }

        print("✅ [MPVLayer] Metal texture cache created")

        // Create render pipeline for video rendering (replaces blit for swizzle support)
        setupRenderPipeline()

        // Initialize MPV rendering with OpenGL bridge
        controller.initializeRendering(openGLBridge: openGLBridge)

        // Set update callback with logging
        controller.videoUpdateCallback = { [weak self] in
            guard let self = self else { return }

            self.updateCallbackCount += 1
            let now = Date()
            if now.timeIntervalSince(self.lastUpdateCallbackLog) >= 2.0 {
                print("🔔 [MPVLayer] MPV update callback triggered \(self.updateCallbackCount) times in 2s")
                self.updateCallbackCount = 0
                self.lastUpdateCallbackLog = now
            }

            DispatchQueue.main.async {
                self.setNeedsDisplay()
            }
        }

        // Set HDR detection callback (IINA approach)
        controller.onHDRDetected = { [weak self] isHDR, gamma, primaries in
            self?.handleHDRDetection(isHDR: isHDR, gamma: gamma, primaries: primaries)
        }

        print("✅ [MPVLayer] MPV rendering setup complete")
    }

    @MainActor
    private func handleHDRDetection(isHDR: Bool, gamma: String?, primaries: String?) {
        if isHDR {
            // HDR content detected - display native HDR (no tone-mapping)
            if let gamma = gamma {
                print("🌈 [MPVLayer] HDR content detected (gamma: \(gamma), primaries: \(primaries ?? "unknown"))")

                // Set HDR colorspace based on transfer function
                let colorspaceName: CFString
                switch gamma {
                case "pq":
                    // PQ (Perceptual Quantizer) - HDR10, HDR10+, Dolby Vision
                    colorspaceName = CGColorSpace.itur_2100_PQ
                    print("🌈 [MPVLayer] Using ITU-R BT.2100 PQ colorspace (HDR10/Dolby Vision)")

                case "hlg":
                    // HLG (Hybrid Log-Gamma) - BBC/NHK HDR standard
                    colorspaceName = CGColorSpace.itur_2100_HLG
                    print("🌈 [MPVLayer] Using ITU-R BT.2100 HLG colorspace")

                default:
                    // Fallback to PQ for unknown HDR types
                    colorspaceName = CGColorSpace.itur_2100_PQ
                    print("⚠️ [MPVLayer] Unknown HDR gamma '\(gamma)', defaulting to BT.2100 PQ")
                }

                if let cs = CGColorSpace(name: colorspaceName) {
                    colorspace = cs
                }

                // Configure MPV for native HDR output (no tone-mapping)
                mpvController?.setHDRProperties(primaries: primaries ?? "bt.2020")
            }
        } else {
            // SDR content - use standard sRGB colorspace
            if let cs = CGColorSpace(name: CGColorSpace.sRGB) {
                colorspace = cs
                print("📺 [MPVLayer] SDR mode (sRGB colorspace)")
            }
            mpvController?.setSDRProperties()
        }
    }

    @MainActor
    private func setupRenderPipeline() {
        // Load shader library
        guard let library = metalDevice.makeDefaultLibrary() else {
            print("❌ [MPVLayer] Failed to create shader library")
            return
        }

        // Load shader functions
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            print("❌ [MPVLayer] Failed to load shader functions")
            return
        }

        // Create render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm  // Match IOSurface format

        // Create render pipeline state
        do {
            renderPipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            print("✅ [MPVLayer] Metal render pipeline created (BGRA8 with HDR colorspace)")
        } catch {
            print("❌ [MPVLayer] Failed to create render pipeline: \(error)")
        }
    }

    @MainActor
    private func createMetalTextureFromIOSurface() -> MTLTexture? {
        guard let ioSurface = openGLBridge?.getIOSurface() else {
            // No IOSurface available, use fallback
            return nil
        }

        let width = IOSurfaceGetWidth(ioSurface)
        let height = IOSurfaceGetHeight(ioSurface)

        // Create Metal texture descriptor (must match IOSurface format: BGRA8)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,  // Match BGRA8 format from OpenGL ES IOSurface
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]

        // Create Metal texture from IOSurface
        // MPV writes RGBA → IOSurface stores as BGRA (R↔B swapped)
        // We need to swizzle to correct the channel order
        guard let baseTexture = metalDevice.makeTexture(
            descriptor: descriptor,
            iosurface: ioSurface,
            plane: 0
        ) else {
            print("❌ [MPVLayer] Failed to create Metal texture from IOSurface")
            return nil
        }

        // Create texture view with swizzle to fix R↔B swap
        // BGRA in IOSurface → swap to RGBA for correct display
        let swizzle = MTLTextureSwizzleChannels(
            red: .blue,    // R channel reads from B
            green: .green, // G channel reads from G
            blue: .red,    // B channel reads from R
            alpha: .alpha  // A channel reads from A
        )

        guard let texture = baseTexture.makeTextureView(
            pixelFormat: .bgra8Unorm,
            textureType: .type2D,
            levels: 0..<1,
            slices: 0..<1,
            swizzle: swizzle
        ) else {
            print("❌ [MPVLayer] Failed to create texture view with swizzle")
            return baseTexture  // Return base texture as fallback
        }

        return texture
    }

    @MainActor
    private func createMetalTextureFromPixels(pixelData: Data, width: Int, height: Int) -> MTLTexture? {
        // glReadPixels returns RGBA data, but drawable is BGRA
        // We need to swap R and B channels
        var convertedData = pixelData
        convertedData.withUnsafeMutableBytes { ptr in
            let pixels = ptr.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: pixels.count, by: 4) {
                // Swap R and B: RGBA -> BGRA
                let r = pixels[i]
                pixels[i] = pixels[i + 2]      // R = B
                pixels[i + 2] = r              // B = R
            }
        }

        // Create Metal texture descriptor (BGRA to match drawable)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,  // Match drawable format
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .shared

        guard let metalTexture = metalDevice.makeTexture(descriptor: descriptor) else {
            print("❌ [MPVLayer] Failed to create Metal texture")
            return nil
        }

        // Upload converted pixel data
        let bytesPerRow = width * 4
        convertedData.withUnsafeBytes { ptr in
            metalTexture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow
            )
        }

        return metalTexture
    }

    private var renderCount = 0
    private var fpsCounter = 0
    private var lastRenderLog = Date()
    private var isFirstRender = true

    @MainActor
    func render() {
        guard let mpvController = mpvController,
              let openGLBridge = openGLBridge else {
            print("⚠️ [MPVLayer] Render called but missing controller or bridge")
            return
        }

        // Only allow rendering after playback is active
        guard mpvController.isPlaybackActive else {
            return  // Playback hasn't started yet
        }

        // In advanced control mode, we must call update() to tell MPV we're ready for frames
        // This triggers MPV's internal decoding pipeline
        let hasUpdate = mpvController.shouldRenderUpdateFrame()

        renderCount += 1
        fpsCounter += 1

        if isFirstRender {
            print("🎬 [MPVLayer] Starting continuous rendering")
            isFirstRender = false
        }

        // Log frame rate every 2 seconds
        let now = Date()
        if now.timeIntervalSince(lastRenderLog) >= 2.0 {
            let fps = Double(fpsCounter) / now.timeIntervalSince(lastRenderLog)
            print("🎬 [MPVLayer] Rendering at \(String(format: "%.1f", fps)) fps (\(renderCount) total frames, hasUpdate: \(hasUpdate))")
            fpsCounter = 0
            lastRenderLog = now
        }

        // Get OpenGL framebuffer size (this is the actual video size)
        let size = openGLBridge.getSize()
        let fboWidth = Int32(size.width)
        let fboHeight = Int32(size.height)

        // Get OpenGL framebuffer
        let fbo = openGLBridge.getFramebuffer()

        // Bind OpenGL framebuffer
        openGLBridge.bindFramebuffer()

        // Render MPV frame to OpenGL FBO
        // flip=false: Don't flip (Metal handles coordinate system differently than OpenGL layer)
        mpvController.renderToOpenGL(fbo: fbo, width: fboWidth, height: fboHeight, flip: false)

        // Finish OpenGL rendering
        openGLBridge.finishRendering()
        openGLBridge.unbindFramebuffer()

        // Try to create Metal texture from IOSurface (zero-copy)
        var metalTexture = createMetalTextureFromIOSurface()

        // If IOSurface not available, use glReadPixels fallback
        if metalTexture == nil {
            guard let pixelData = openGLBridge.readPixels() else {
                if renderCount <= 5 {
                    print("⚠️ [MPVLayer] Failed to read pixels from OpenGL (frame \(renderCount))")
                }
                return
            }

            metalTexture = createMetalTextureFromPixels(
                pixelData: pixelData,
                width: size.width,
                height: size.height
            )

            if renderCount <= 5 {
                if metalTexture != nil {
                    // Sample some pixels to verify we're getting actual video data
                    let sampledPixels = pixelData.withUnsafeBytes { ptr -> [UInt8] in
                        let bytes = ptr.bindMemory(to: UInt8.self)
                        // Sample pixels from center, top-left, and a few other spots
                        let centerOffset = (size.height / 2) * size.width * 4 + (size.width / 2) * 4
                        let topLeftOffset = 0
                        let samples = [
                            bytes[topLeftOffset], bytes[topLeftOffset + 1], bytes[topLeftOffset + 2],
                            bytes[centerOffset], bytes[centerOffset + 1], bytes[centerOffset + 2]
                        ]
                        return samples
                    }
                    print("✅ [MPVLayer] Created Metal texture from glReadPixels (\(size.width)x\(size.height), frame \(renderCount))")
                    print("   Pixel samples - TopLeft(R:\(sampledPixels[0]) G:\(sampledPixels[1]) B:\(sampledPixels[2])) Center(R:\(sampledPixels[3]) G:\(sampledPixels[4]) B:\(sampledPixels[5]))")
                } else {
                    print("⚠️ [MPVLayer] Failed to create Metal texture from pixels (frame \(renderCount))")
                }
            }

            guard metalTexture != nil else {
                return
            }
        }

        guard let sourceTexture = metalTexture else {
            if renderCount <= 5 {
                print("⚠️ [MPVLayer] No Metal texture available (frame \(renderCount))")
            }
            return
        }

        // Use texture directly (both IOSurface and drawable are BGRA)
        let finalTexture = sourceTexture

        // Get Metal drawable
        guard let drawable = nextDrawable() else {
            if renderCount <= 5 {
                print("⚠️ [MPVLayer] No drawable available (frame \(renderCount))")
            }
            return
        }

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            if renderCount <= 5 {
                print("⚠️ [MPVLayer] Failed to create command buffer (frame \(renderCount))")
            }
            return
        }

        // Use render pass instead of blit (for texture swizzle support)
        guard let renderPipelineState = renderPipelineState else {
            if renderCount <= 5 {
                print("⚠️ [MPVLayer] Render pipeline not ready (frame \(renderCount))")
            }
            return
        }

        // Create render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Create render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            if renderCount <= 5 {
                print("⚠️ [MPVLayer] Failed to create render encoder (frame \(renderCount))")
            }
            return
        }

        // Set render pipeline and texture
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setFragmentTexture(finalTexture, index: 0)

        // Draw fullscreen quad (4 vertices for triangle strip)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        renderEncoder.endEncoding()

        if renderCount <= 5 {
            print("✅ [MPVLayer] Presenting frame \(renderCount) (texture: \(size.width)x\(size.height), drawable: \(Int(drawableSize.width))x\(Int(drawableSize.height)))")
        }

        // Present drawable
        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Report swap to MPV
        mpvController.reportSwap()
    }
}
