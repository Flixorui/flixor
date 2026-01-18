//
//  MPVVideoView.swift
//  FlixorMac
//
//  MPV video rendering view using CAMetalLayer for gpu-next
//  Based on plezy implementation for Dolby Vision support
//

import SwiftUI
import AppKit

struct MPVVideoView: NSViewRepresentable {
    let mpvController: MPVPlayerController

    func makeNSView(context: Context) -> MPVNSView {
        let view = MPVNSView()
        view.mpvController = mpvController
        return view
    }

    func updateNSView(_ nsView: MPVNSView, context: Context) {
        // No updates needed
    }

    static func dismantleNSView(_ nsView: MPVNSView, coordinator: ()) {
        // Stop rendering BEFORE the view is deallocated
        nsView.stopRendering()
    }
}

class MPVNSView: NSView {
    var metalLayer: MPVMetalLayer? // Internal access for PiP controls
    weak var mpvController: MPVPlayerController?
    var isPiPTransitioning = false // Flag to prevent issues during PiP

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Ensure view has a layer (plezy pattern)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    private func createMetalLayer() -> MPVMetalLayer {
        let layer = MPVMetalLayer()
        layer.frame = bounds
        layer.framebufferOnly = true
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Set contents scale from window's screen
        if let screen = window?.screen ?? NSScreen.main {
            layer.contentsScale = screen.backingScaleFactor
        }

        return layer
    }

    func setupMPVRendering(controller: MPVPlayerController) {
        guard let window = window else {
            print("❌ [MPVVideoView] No window available for MPV setup")
            return
        }

        self.mpvController = controller

        // Create Metal layer and add as sublayer (plezy pattern)
        let layer = createMetalLayer()
        self.metalLayer = layer

        // Add Metal layer as sublayer to view's layer (NOT as backing layer)
        self.layer?.addSublayer(layer)

        print("✅ [MPVVideoView] Metal layer added as sublayer, frame: \(layer.frame)")

        // Initialize MPV with our Metal layer
        if !controller.initialize(in: window, layer: layer) {
            print("❌ [MPVVideoView] Failed to initialize MPV")
        }
    }

    func stopRendering() {
        mpvController?.shutdown()
        mpvController = nil
        metalLayer?.removeFromSuperlayer()
        metalLayer = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // Initialize MPV when we have a window
            if let controller = mpvController, !controller.isInitialized {
                setupMPVRendering(controller: controller)
            }
            updateLayerSize()
        }
    }

    override func layout() {
        super.layout()
        // Always update layer size on layout to handle PiP transitions
        updateLayerSize()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        // Also update when view is resized
        updateLayerSize()
    }

    // Force update layer size to match view bounds
    func updateLayerSize() {
        guard let layer = metalLayer else { return }

        let newBounds = CGRect(origin: .zero, size: bounds.size)

        CATransaction.begin()
        CATransaction.setDisableActions(true) // Disable implicit animations
        layer.frame = newBounds
        CATransaction.commit()

        // Update drawable size for Metal rendering
        if let screen = window?.screen ?? NSScreen.main {
            let scale = screen.backingScaleFactor
            layer.contentsScale = scale
            layer.drawableSize = CGSize(
                width: bounds.width * scale,
                height: bounds.height * scale
            )
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerSize()
    }

    // MARK: - Legacy Compatibility (for PiP and other systems)

    /// Provides access to the video layer for PiP and other features
    var videoLayer: CALayer? {
        return metalLayer
    }

    /// Force update for new bounds (used during PiP transitions)
    func forceUpdateForNewBounds(_ newBounds: CGRect) {
        guard let layer = metalLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layer.frame = newBounds

        if let screen = window?.screen ?? NSScreen.main {
            let scale = screen.backingScaleFactor
            layer.drawableSize = CGSize(
                width: newBounds.width * scale,
                height: newBounds.height * scale
            )
        }

        CATransaction.commit()
    }

    deinit {
        // mpvController cleanup is handled by stopRendering()
    }
}
