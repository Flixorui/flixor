//
//  MPVVideoLayer.swift
//  FlixorMac
//
//  The layer mpv's vo_avfoundation renders into. It is passed to mpv as "wid";
//  mpv adds its subtitle (OSD) layer beside it in the same superlayer.
//

import AppKit
import AVFoundation

final class MPVVideoLayer: AVSampleBufferDisplayLayer {
    override init() {
        super.init()
        commonInit()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        videoGravity = .resizeAspect
        backgroundColor = NSColor.black.cgColor
        isOpaque = true
    }

    /// No implicit animations: AppKit resizes the layer with its view, and a fade or
    /// slide would trail the video.
    override func action(forKey event: String) -> CAAction? { nil }

    /// Sizes the layer through bounds and position, without animation.
    func forceUpdateForNewBounds(_ newBounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bounds = CGRect(origin: .zero, size: newBounds.size)
        position = CGPoint(x: newBounds.midX, y: newBounds.midY)
        CATransaction.commit()
    }
}
