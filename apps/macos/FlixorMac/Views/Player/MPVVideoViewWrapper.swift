//
//  MPVVideoViewWrapper.swift
//  FlixorMac
//
//  Hosts the MPV video view in an NSViewController so it can be moved into the PiP window
//

import SwiftUI
import AppKit

// MARK: - MPV Video View Wrapper (for PiP support)

struct MPVVideoViewWrapper: NSViewControllerRepresentable {
    let mpvController: MPVPlayerController
    @Binding var isPiPActive: Bool
    @Binding var mpvPiPViewController: NSViewController?

    func makeNSViewController(context: Context) -> NSViewController {
        let viewController = MPVPiPViewController()
        viewController.mpvController = mpvController
        viewController.isPiPActiveBinding = $isPiPActive

        // Store the view controller for PiP control
        DispatchQueue.main.async {
            self.mpvPiPViewController = viewController
        }

        return viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        if let pipVC = nsViewController as? MPVPiPViewController {
            pipVC.mpvController = mpvController
        }
    }

    class MPVPiPViewController: NSViewController {
        var mpvController: MPVPlayerController?
        var isPiPActiveBinding: Binding<Bool>?
        private(set) var hostingView: NSHostingView<MPVVideoView>?

        override func loadView() {
            guard let mpvController = mpvController else {
                view = NSView()
                return
            }

            // Create the MPV video view hosting view
            let hosting = NSHostingView(rootView: MPVVideoView(mpvController: mpvController))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            self.hostingView = hosting
            view = hosting
        }

        // Extract the actual MPVNSView from the hosting view hierarchy
        func getMPVNSView() -> MPVNSView? {
            // The NSHostingView contains the MPVNSView as a subview
            return findMPVNSView(in: hostingView)
        }

        private func findMPVNSView(in view: NSView?) -> MPVNSView? {
            guard let view = view else { return nil }

            // Check if this is the MPVNSView
            if let mpvView = view as? MPVNSView {
                return mpvView
            }

            // Recursively search subviews
            for subview in view.subviews {
                if let mpvView = findMPVNSView(in: subview) {
                    return mpvView
                }
            }

            return nil
        }
    }
}
