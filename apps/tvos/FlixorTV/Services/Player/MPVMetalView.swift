//
//  MPVMetalView.swift
//  FlixorTV
//
//  MPV video rendering view using CAMetalLayer for tvOS
//  Adapted from macOS implementation
//

import SwiftUI
import UIKit

struct MPVMetalView: UIViewRepresentable {
    let mpvController: MPVPlayerController

    func makeUIView(context: Context) -> MPVUIView {
        let view = MPVUIView()
        view.setupMPVRendering(controller: mpvController)
        return view
    }

    func updateUIView(_ uiView: MPVUIView, context: Context) {
        // No updates needed
    }

    static func dismantleUIView(_ uiView: MPVUIView, coordinator: ()) {
        // Stop rendering BEFORE the view is deallocated
        uiView.stopRendering()
    }
}

class MPVUIView: UIView {
    private var displayLink: CADisplayLink?
    var metalLayer: MPVMetalLayer?
    private var openGLBridge: MPVOpenGLBridge?
    private var mpvController: MPVPlayerController?
    private var isRenderingInitialized = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        // Create and setup the Metal layer
        let layer = MPVMetalLayer()
        self.layer.addSublayer(layer)
        self.metalLayer = layer

        // Configure the view
        backgroundColor = .black
    }

    func setupMPVRendering(controller: MPVPlayerController) {
        // Store controller reference
        self.mpvController = controller

        // Listen for video dimension changes to resize FBO dynamically
        controller.onVideoDimensionsDetected = { [weak self] width, height in
            guard let self = self else { return }
            print("📐 [MPVView] Video dimensions detected: \(width)x\(height)")

            // Resize FBO to match video resolution EXACTLY (no downscaling!)
            // Apple TV 4K can handle full 4K (3840x2160) and even 8K if needed
            let targetWidth = width   // Use native resolution
            let targetHeight = height // Use native resolution

            print("📐 [MPVView] Resizing FBO to \(targetWidth)x\(targetHeight) (native resolution, no scaling)")

            // Resize the OpenGL bridge
            self.openGLBridge?.resize(width: targetWidth, height: targetHeight)

            // Update Metal drawable size
            DispatchQueue.main.async {
                self.updateLayerSize()
            }
        }

        // Actual initialization will happen in layoutSubviews when we have valid bounds
        print("🔧 [MPVView] MPV controller assigned, waiting for layout")
    }

    private func initializeRenderingIfNeeded() {
        guard !isRenderingInitialized,
              let mpvController = mpvController,
              let metalLayer = metalLayer,
              bounds.width > 0 && bounds.height > 0 else {
            return
        }

        isRenderingInitialized = true

        // Create OpenGL bridge with default resolution
        // Will be resized automatically when video dimensions are detected
        let bridge = MPVOpenGLBridge()
        let width = 1920  // Default: 1080p width (will auto-resize for 4K)
        let height = 1080  // Default: 1080p height (will auto-resize for 4K)

        print("🔧 [MPVView] Initializing rendering with default FBO size: \(width)x\(height) (will auto-resize for 4K)")

        guard bridge.setupOpenGL(width: width, height: height) else {
            print("❌ [MPVView] Failed to setup OpenGL bridge")
            isRenderingInitialized = false
            return
        }

        self.openGLBridge = bridge
        print("✅ [MPVView] OpenGL bridge created (\(width)x\(height))")

        // Setup Metal layer with bridge
        metalLayer.setupMPVRendering(controller: mpvController, openGLBridge: bridge)

        startDisplayLink()
    }

    func stopRendering() {
        stopDisplayLink()
        metalLayer?.mpvController = nil
        openGLBridge?.cleanup()
        openGLBridge = nil
        print("🛑 [MPVView] Rendering stopped and OpenGL bridge cleaned up")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Initialize rendering once we have valid bounds
        initializeRenderingIfNeeded()

        updateLayerSize()
    }

    // Update layer size to match view bounds
    func updateLayerSize() {
        guard let metalLayer = metalLayer,
              let openGLBridge = openGLBridge else { return }

        // Get current FBO size from OpenGL bridge
        let size = openGLBridge.getSize()

        CATransaction.begin()
        CATransaction.setDisableActions(true)  // Disable implicit animations

        metalLayer.frame = bounds
        // Set drawable size to match FBO size
        // CAMetalLayer will automatically scale to fill the view bounds
        metalLayer.drawableSize = CGSize(width: size.width, height: size.height)

        CATransaction.commit()

        print("📐 [MPVView] Updated drawable size to \(size.width)x\(size.height)")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil {
            // Start display link when added to window
            if displayLink == nil {
                startDisplayLink()
            }
            updateLayerSize()
        } else {
            // Stop display link when removed from window
            stopDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }

        // Create display link targeting the main screen
        let link = CADisplayLink(target: self, selector: #selector(displayLinkCallbackWithLogging))
        link.preferredFramesPerSecond = 60  // Match TV refresh rate
        link.add(to: .main, forMode: .common)

        displayLink = link
        print("✅ [MPVView] Display link started")
    }

    @objc private func displayLinkCallback() {
        // Trigger render on the Metal layer
        metalLayer?.setNeedsDisplay()
    }

    private var frameCount = 0
    private var lastLogTime = Date()

    @objc private func displayLinkCallbackWithLogging() {
        frameCount += 1
        let now = Date()
        if now.timeIntervalSince(lastLogTime) >= 2.0 {
            print("🖼️ [MPVView] Display link active (\(frameCount) frames in 2s)")
            frameCount = 0
            lastLogTime = now
        }
        // Call render synchronously for real-time video playback
        metalLayer?.render()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        print("🛑 [MPVView] Display link stopped")
    }

    deinit {
        stopDisplayLink()
    }
}
