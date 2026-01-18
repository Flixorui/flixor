//
//  MPVVideoLayer.swift
//  FlixorMac
//
//  DEPRECATED: CAOpenGLLayer for MPV video rendering
//  This file is kept for reference but is no longer used.
//  Use MPVMetalLayer.swift instead for gpu-next rendering.
//

import Cocoa
import OpenGL.GL
import OpenGL.GL3
import Libmpv

class MPVVideoLayer: CAOpenGLLayer {
    weak var mpvController: MPVPlayerController?

    private let cglContext: CGLContextObj
    private let cglPixelFormat: CGLPixelFormatObj
    private var bufferDepth: GLint = 8
    // Simple, AppKit-driven rendering to avoid jitter.

    override init() {
        // Try 10-bit float context first (IINA approach), fallback to standard 8-bit.
        // HDR will be handled by NSView-level wantsExtendedDynamicRangeOpenGLSurface
        let baseAttrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer
        ]
        let tenBitAttrs: [CGLPixelFormatAttribute] = [
            kCGLPFAColorSize, CGLPixelFormatAttribute(64), kCGLPFAColorFloat
        ]
        let terminator: [CGLPixelFormatAttribute] = [CGLPixelFormatAttribute(0)]

        func choosePixelFormat(_ attrs: [CGLPixelFormatAttribute]) -> (CGLPixelFormatObj?, GLint) {
            var pix: CGLPixelFormatObj?
            var npix: GLint = 0
            var attrsTerminated = attrs + terminator
            CGLChoosePixelFormat(attrsTerminated, &pix, &npix)
            if let pf = pix { return (pf, attrs.contains(kCGLPFAColorFloat) ? 16 : 8) }
            return (nil, 8)
        }

        var pix: CGLPixelFormatObj?
        var depth: GLint = 8
        let attempt10 = choosePixelFormat(baseAttrs + tenBitAttrs)
        if let pf = attempt10.0 {
            pix = pf
            depth = attempt10.1
        } else {
            let attempt8 = choosePixelFormat(baseAttrs)
            pix = attempt8.0
            depth = attempt8.1
        }

        guard let pixelFormat = pix else {
            fatalError("❌ [MPVLayer] Failed to create pixel format")
        }

        self.cglPixelFormat = pixelFormat
        self.bufferDepth = depth

        // Create OpenGL context
        var ctx: CGLContextObj?
        CGLCreateContext(pixelFormat, nil, &ctx)

        guard let context = ctx else {
            fatalError("❌ [MPVLayer] Failed to create OpenGL context")
        }

        // Enable vsync and multi-threaded GL engine (IINA parity)
        var swapInterval: GLint = 1
        CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval)
        CGLEnable(context, kCGLCEMPEngine)

        self.cglContext = context

        super.init()

        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
        isAsynchronous = false
        isOpaque = true

        if bufferDepth > 8 {
            contentsFormat = .RGBA16Float
        }

        // Don't set wantsExtendedDynamicRangeContent here - IINA sets it dynamically when HDR detected
        // Don't set colorspace - let MPV handle it internally

        print("✅ [MPVLayer] Initialized with standard pixel format (EDR handled by NSView)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(layer: Any) {
        let previousLayer = layer as! MPVVideoLayer
        mpvController = previousLayer.mpvController
        cglPixelFormat = previousLayer.cglPixelFormat
        cglContext = previousLayer.cglContext
        super.init(layer: layer)
    }

    func setupMPVRendering(controller: MPVPlayerController) {
        self.mpvController = controller

        // Initialize MPV rendering with our CGL context
        CGLLockContext(cglContext)
        CGLSetCurrentContext(cglContext)

        controller.initializeRendering(openGLContext: cglContext)

        // Set update callback
        controller.videoUpdateCallback = { [weak self] in
            DispatchQueue.main.async { self?.setNeedsDisplay() }
        }

        // DEPRECATED: HDR detection callback has changed signature
        // This file is not used anymore - use MPVMetalLayer instead

        CGLUnlockContext(cglContext)

        print("✅ [MPVLayer] MPV rendering setup complete")
    }

    // Force the layer to update its internal state for new bounds
    func forceUpdateForNewBounds(_ newBounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update bounds and frame
        bounds = newBounds
        frame = newBounds

        // Force the layer to invalidate its cached rendering state
        setNeedsLayout()
        setNeedsDisplay()

        CATransaction.commit()

        // Force immediate layout
        layoutIfNeeded()
    }

    // No custom update/display queue; rely on AppKit calling draw.

    private func handleHDRDetection(isHDR: Bool, gamma: String?, primaries: String?) {
        guard #available(macOS 10.15, *) else { return }

        // For HDR path, do not use ICC auto; IINA disables ICC for HDR and uses target PQ.

        if isHDR {
            // Enable EDR on the layer for HDR content
            wantsExtendedDynamicRangeContent = true

            // Set appropriate colorspace based on primaries (IINA approach)
            if let primaries = primaries {
                let colorspaceName: CFString?
                switch primaries {
                case "bt.2020":
                    // BT.2020 - Standard HDR color space
                    colorspaceName = CGColorSpace.itur_2100_PQ
                case "display-p3":
                    // Display P3 - Wide gamut
                    if #available(macOS 10.15.4, *) {
                        colorspaceName = CGColorSpace.displayP3_PQ
                    } else {
                        colorspaceName = CGColorSpace.displayP3_PQ_EOTF
                    }
                default:
                    colorspaceName = nil
                }

                if let name = colorspaceName, let cs = CGColorSpace(name: name) {
                    colorspace = cs
                    print("🌈 [MPVLayer] HDR enabled with colorspace: \(primaries)")
                }

                // Set HDR properties in MPV controller (IINA approach: native EDR, no tone mapping)
                mpvController?.setHDRProperties(primaries: primaries)
            }
        } else {
            // Disable EDR for SDR content
            wantsExtendedDynamicRangeContent = false
            // Set SDR colorspace to screen space (usually sRGB) and enable ICC auto in mpv.
            let sdrColorSpace = self.delegateScreen()?.colorSpace?.cgColorSpace
                ?? CGColorSpace(name: CGColorSpace.sRGB)
            colorspace = sdrColorSpace
            if let nsCS = self.delegateScreen()?.colorSpace {
                mpvController?.setRenderICCProfile(nsCS)
            }
            mpvController?.setSDRProperties()
            print("📺 [MPVLayer] SDR mode")
        }
    }

    /// Fetch ICC profile path for the window's screen.
    /// Placeholder: returning nil avoids linking ColorSync, keeping build simple.
    private func currentScreenICCProfilePath() -> String? { return nil }

    /// Obtain the most relevant screen for this layer.
    private func delegateScreen() -> NSScreen? {
        if let w = self.delegate as? NSView { return w.window?.screen }
        return nil
    }

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                         forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        guard let mpvController = mpvController else {
            return false
        }
        return mpvController.shouldRenderUpdateFrame()
    }

    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                      forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        guard let mpvController = mpvController,
              let renderContext = mpvController.getRenderContext() else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }

        // CRITICAL: Use the CALayer-provided context, not our own
        // This ensures we're rendering to the correct window
        CGLLockContext(ctx)
        CGLSetCurrentContext(ctx)

        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        // CRITICAL: Override viewport to match current layer bounds
        // CAOpenGLLayer may have calculated viewport before bounds were updated
        let width = Int32(bounds.size.width * contentsScale)
        let height = Int32(bounds.size.height * contentsScale)

        // Always set viewport to ensure it matches current bounds
        glViewport(0, 0, width, height)

        // Get framebuffer info
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &fbo)

        // Create FBO structure with our calculated viewport dimensions
        var data = mpv_opengl_fbo(
            fbo: Int32(fbo != 0 ? fbo : 1),
            w: width,
            h: height,
            internal_format: 0
        )

        var flip: CInt = 1
        var bufferDepth = self.bufferDepth

        withUnsafeMutablePointer(to: &data) { dataPtr in
            withUnsafeMutablePointer(to: &flip) { flipPtr in
                withUnsafeMutablePointer(to: &bufferDepth) { depthPtr in
                    var params: [mpv_render_param] = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: .init(dataPtr)),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: .init(flipPtr)),
                        mpv_render_param(type: MPV_RENDER_PARAM_DEPTH, data: .init(depthPtr)),
                        mpv_render_param()
                    ]

                    mpv_render_context_render(renderContext, &params)
                }
            }
        }

        glFlush()
        mpvController.reportSwap()

        CGLUnlockContext(ctx)
    }

    // Do not override display(); avoid potential scheduling jitter.

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        return cglPixelFormat
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        return cglContext
    }
}
