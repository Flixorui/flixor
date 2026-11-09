//
//  MPVVideoView.swift
//  FlixorMac
//
//  Hosts the layer mpv's vo_avfoundation renders into (plezy's setup)
//

import SwiftUI
import AppKit

struct MPVVideoView: NSViewRepresentable {
    let mpvController: MPVPlayerController

    func makeNSView(context: Context) -> MPVNSView {
        print("🎬 [MPVVideoView] makeNSView called")
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
    var videoLayer: MPVVideoLayer? // Internal access for PiP controls
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

    private func createVideoLayer() -> MPVVideoLayer {
        let layer = MPVVideoLayer()
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return layer
    }

    func setupMPVRendering(controller: MPVPlayerController) {
        guard let window = window else {
            print("❌ [MPVVideoView] No window available for MPV setup")
            return
        }

        self.mpvController = controller

        // The video layer is a sublayer, so mpv's subtitle layer can sit beside it
        let layer = createVideoLayer()
        self.videoLayer = layer
        self.layer?.addSublayer(layer)

        print("✅ [MPVVideoView] Video layer added as sublayer, frame: \(layer.frame)")

        // Initialize MPV with our video layer
        if !controller.initialize(in: window, layer: layer) {
            print("❌ [MPVVideoView] Failed to initialize MPV")
        }
    }

    /// Hides the video, then removes it only after mpv has let go of the layers and
    /// the hidden frame is on screen: on macOS 27, pulling a visible sample-buffer layer
    /// out while its video receiver is torn down can stop the display (plezy #2823).
    func stopRendering() {
        let layers = layer?.sublayers ?? []
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layers.forEach { $0.isHidden = true }
        CATransaction.commit()
        let remove = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                layers.forEach { $0.removeFromSuperlayer() }
            }
        }
        if let controller = mpvController {
            controller.shutdown(completion: remove)
        } else {
            remove()
        }
        mpvController = nil
        videoLayer = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        print("🪟 [MPVNSView] viewDidMoveToWindow called, window: \(window != nil ? "exists" : "nil")")

        if window != nil {
            // Initialize MPV when we have a window
            if let controller = mpvController, !controller.isInitialized {
                print("🔧 [MPVNSView] Calling setupMPVRendering")
                setupMPVRendering(controller: controller)
            } else if mpvController == nil {
                print("⚠️ [MPVNSView] mpvController is nil!")
            } else {
                print("✅ [MPVNSView] MPV already initialized")
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
        videoLayer?.forceUpdateForNewBounds(CGRect(origin: .zero, size: bounds.size))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerSize()
    }

    /// Force update for new bounds (used during PiP transitions)
    func forceUpdateForNewBounds(_ newBounds: CGRect) {
        videoLayer?.forceUpdateForNewBounds(newBounds)
    }

    deinit {
        // mpvController cleanup is handled by stopRendering()
    }
}
