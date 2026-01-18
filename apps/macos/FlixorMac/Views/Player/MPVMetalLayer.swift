//
//  MPVMetalLayer.swift
//  FlixorMac
//
//  Custom CAMetalLayer for MPV gpu-next rendering with Dolby Vision support
//  Based on: https://github.com/mpv-player/mpv/pull/13651
//

import Cocoa
import Metal

/// Custom CAMetalLayer with MoltenVK flicker workaround and EDR thread safety
/// This layer is passed to MPV via the "wid" option for gpu-next rendering
class MPVMetalLayer: CAMetalLayer {

    // MARK: - MoltenVK Flicker Workaround

    /// Workaround for MoltenVK drawable size issues that cause flicker
    /// Prevents invalid sizes (0x0 or 1x1) from being set
    override var drawableSize: CGSize {
        get { return super.drawableSize }
        set {
            // Only set valid sizes to prevent flicker
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    // MARK: - EDR Thread Safety

    /// Fix for target-colorspace-hint - EDR property must be set on main thread
    /// MPV may call this from background threads during HDR detection
    override var wantsExtendedDynamicRangeContent: Bool {
        get { return super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.async {
                    super.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        commonInit()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // CRITICAL: Set Metal device - required for Vulkan/MoltenVK
        device = MTLCreateSystemDefaultDevice()

        // Configure layer for optimal MPV rendering
        framebufferOnly = true
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Use BGRA pixel format (most compatible)
        pixelFormat = .bgra8Unorm

        // Use main screen's scale factor initially
        if let screen = NSScreen.main {
            contentsScale = screen.backingScaleFactor
        }

        print("✅ [MPVMetalLayer] Initialized for gpu-next rendering, device: \(device?.name ?? "nil")")
    }

    // MARK: - PiP Compatibility

    /// Force update for new bounds (used during PiP transitions)
    func forceUpdateForNewBounds(_ newBounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Update bounds and frame
        bounds = newBounds
        frame = newBounds

        // Update drawable size with scale
        if let window = (delegate as? NSView)?.window {
            let scale = window.backingScaleFactor
            drawableSize = CGSize(
                width: newBounds.width * scale,
                height: newBounds.height * scale
            )
        } else if let screen = NSScreen.main {
            let scale = screen.backingScaleFactor
            drawableSize = CGSize(
                width: newBounds.width * scale,
                height: newBounds.height * scale
            )
        }

        // Force redraw
        setNeedsLayout()
        setNeedsDisplay()

        CATransaction.commit()

        // Force immediate layout
        layoutIfNeeded()
    }
}
