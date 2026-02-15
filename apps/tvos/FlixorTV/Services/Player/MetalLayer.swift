import Foundation
import UIKit

final class MetalLayer: CAMetalLayer {
    /// workaround for a MoltenVK that sets the drawableSize to 1x1 to forcefully complete
    /// the presentation, this causes flicker and the drawableSize possibly staying at 1x1
    /// https://github.com/mpv-player/mpv/pull/13651
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1, Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    #if !os(tvOS)
        /// Hack for fix [target-colorspace-hint] option:
        /// Update wantsExtendedDynamicRangeContent need run in main thread to activate screen EDR mode, other thread
        /// can't activate
        override var wantsExtendedDynamicRangeContent: Bool {
            get {
                super.wantsExtendedDynamicRangeContent
            }
            set {
                if Thread.isMainThread {
                    super.wantsExtendedDynamicRangeContent = newValue
                } else {
                    DispatchQueue.main.sync {
                        super.wantsExtendedDynamicRangeContent = newValue
                    }
                }
            }
        }
    #endif
}
