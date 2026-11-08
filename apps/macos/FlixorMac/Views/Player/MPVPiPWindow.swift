//
//  MPVPiPWindow.swift
//  FlixorMac
//
//  Custom picture-in-picture window for the MPV player (window manager, AppKit controls overlay)
//

import SwiftUI
import AppKit

// MARK: - MPV PiP Window Manager

#if os(macOS)
extension Notification.Name {
    static let mpvPiPDidClose = Notification.Name("mpvPiPDidClose")
    static let mpvPiPRequestedPlayerClose = Notification.Name("mpvPiPRequestedPlayerClose")
}

class MPVPiPWindowManager {
    static let shared = MPVPiPWindowManager()

    private enum PersistenceKeys {
        static let frame = "mpvPiPWindowFrame"
    }

    private var pipWindow: NSWindow?
    private var windowDelegate: PiPWindowDelegate?
    private var mpvView: MPVNSView?
    private var originalParentView: NSView?
    private var originalConstraints: [NSLayoutConstraint] = []
    private var isPiPActive = false
    private var isClosing = false
    private var controlOverlay: PiPControlOverlay?
    private var isCleaningUp = false
    private var stateBinding: Binding<Bool>?
    private var currentAspectRatio = NSSize(width: 16, height: 9)

    private init() {}

    private func fallbackFrame(for visibleFrame: NSRect, aspectRatio: NSSize) -> NSRect {
        let maxWidth = min(560.0, visibleFrame.width * 0.34)
        let width = max(360.0, maxWidth)
        let height = width * (aspectRatio.height / aspectRatio.width)

        return NSRect(
            x: visibleFrame.maxX - width - 20,
            y: visibleFrame.maxY - height - 20,
            width: width,
            height: height
        )
    }

    private func persistedFrame() -> NSRect? {
        guard let frameString = UserDefaults.standard.string(forKey: PersistenceKeys.frame) else {
            return nil
        }

        return NSRectFromString(frameString)
    }

    private func persistFrame(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: PersistenceKeys.frame)
    }

    private func normalizedFrame(_ frame: NSRect, aspectRatio: NSSize, visibleFrame: NSRect) -> NSRect {
        let safeAspect = max(aspectRatio.width, 1) / max(aspectRatio.height, 1)
        let minWidth: CGFloat = 320
        let maxWidth = max(minWidth, min(visibleFrame.width - 40, 720))

        var width = min(max(frame.width, minWidth), maxWidth)
        var height = width / safeAspect

        let maxHeight = max(180.0, visibleFrame.height - 40)
        if height > maxHeight {
            height = maxHeight
            width = height * safeAspect
        }

        var originX = frame.origin.x
        var originY = frame.origin.y

        if originX < visibleFrame.minX + 12 {
            originX = visibleFrame.minX + 12
        }
        if originY < visibleFrame.minY + 12 {
            originY = visibleFrame.minY + 12
        }
        if originX + width > visibleFrame.maxX - 12 {
            originX = visibleFrame.maxX - width - 12
        }
        if originY + height > visibleFrame.maxY - 12 {
            originY = visibleFrame.maxY - height - 12
        }

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func preferredAspectRatio(explicitAspectRatio: CGSize?, mpvView: MPVNSView) -> NSSize {
        if let explicitAspectRatio, explicitAspectRatio.width > 0, explicitAspectRatio.height > 0 {
            return NSSize(width: explicitAspectRatio.width, height: explicitAspectRatio.height)
        }

        let bounds = mpvView.bounds.size
        if bounds.width > 0, bounds.height > 0 {
            return NSSize(width: bounds.width, height: bounds.height)
        }

        return NSSize(width: 16, height: 9)
    }

    func enterPiP(
        mpvViewController: MPVVideoViewWrapper.MPVPiPViewController,
        stateBinding: Binding<Bool>? = nil,
        title: String,
        subtitle: String?,
        aspectRatio: CGSize?,
        isPlaying: Bool
    ) {
        self.stateBinding = stateBinding
        guard !isPiPActive else {
            return
        }

        guard !isCleaningUp else {
            return
        }

        // Clear any stale references from previous PiP session
        self.mpvView = nil
        self.originalParentView = nil
        self.originalConstraints = []

        // Extract the actual MPVNSView from the hosting view hierarchy
        guard let mpvView = mpvViewController.getMPVNSView() else {
            showError(message: "Unable to find MPV video view")
            return
        }

        currentAspectRatio = preferredAspectRatio(explicitAspectRatio: aspectRatio, mpvView: mpvView)

        // Store the original parent view and capture a weak reference to mpvView
        self.originalParentView = mpvView.superview
        self.mpvView = mpvView

        // Set flag to prevent display link from stopping during transition
        mpvView.isPiPTransitioning = true

        // Remove all existing constraints
        mpvView.removeConstraints(mpvView.constraints)
        originalConstraints = mpvView.superview?.constraints.filter { constraint in
            constraint.firstItem as? NSView == mpvView || constraint.secondItem as? NSView == mpvView
        } ?? []

        // Deactivate constraints
        NSLayoutConstraint.deactivate(originalConstraints)

        // Remove from parent (display link won't stop due to flag)
        mpvView.removeFromSuperview()

        // Reuse existing window or create new one
        let window: NSPanel
        if let existingWindow = self.pipWindow as? NSPanel {
            window = existingWindow
        } else {
            let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
            let initialFrame = normalizedFrame(
                fallbackFrame(for: visibleFrame, aspectRatio: currentAspectRatio),
                aspectRatio: currentAspectRatio,
                visibleFrame: visibleFrame
            )

            window = NSPanel(
                contentRect: initialFrame,
                styleMask: [.borderless, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            window.level = .floating
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.aspectRatio = currentAspectRatio
            window.minSize = NSSize(width: 320, height: 180)
            window.hasShadow = true
            window.isOpaque = false
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = true
            window.alphaValue = 0.0

            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 10
                contentView.layer?.masksToBounds = true
            }

            self.pipWindow = window
        }

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let preferredFrame = persistedFrame() ?? window.frame
        let targetFrame = normalizedFrame(preferredFrame, aspectRatio: currentAspectRatio, visibleFrame: visibleFrame)
        window.aspectRatio = currentAspectRatio
        window.setFrame(targetFrame, display: true)

        // Set delegate
        let delegate = PiPWindowDelegate()
        window.delegate = delegate
        self.windowDelegate = delegate

        // Add MPV view to PiP window with constraints (like IINA does)
        if let contentView = window.contentView {
            mpvView.removeFromSuperview() // Ensure clean state
            contentView.addSubview(mpvView)

            // Use Auto Layout instead of manual frame management
            mpvView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                mpvView.topAnchor.constraint(equalTo: contentView.topAnchor),
                mpvView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                mpvView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                mpvView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])

            // Force layout to apply constraints immediately
            contentView.layoutSubtreeIfNeeded()


            // CRITICAL: Force layer to update for PiP bounds
            if let layer = mpvView.layer as? MPVMetalLayer {
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.contentsScale = window.backingScaleFactor

                let pipBounds = CGRect(origin: .zero, size: mpvView.bounds.size)
                layer.forceUpdateForNewBounds(pipBounds)
            }

            let overlay: PiPControlOverlay
            if let existingOverlay = controlOverlay {
                overlay = existingOverlay
            } else {
                overlay = PiPControlOverlay(frame: contentView.bounds)
                overlay.translatesAutoresizingMaskIntoConstraints = false
                controlOverlay = overlay
            }

            if overlay.superview !== contentView {
                overlay.removeFromSuperview()
                contentView.addSubview(overlay, positioned: .above, relativeTo: mpvView)
                NSLayoutConstraint.activate([
                    overlay.topAnchor.constraint(equalTo: contentView.topAnchor),
                    overlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                    overlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    overlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
                ])
            }

            overlay.setTitle(title, subtitle: subtitle)
            overlay.updatePlayPauseState(isPlaying: isPlaying)
            overlay.setReturnAction { [weak self] in
                self?.exitPiP()
            }
            overlay.setCloseAction { [weak self] in
                self?.exitPiP()
                NotificationCenter.default.post(name: .mpvPiPRequestedPlayerClose, object: nil)
            }
            overlay.setPlayPauseAction { [weak self] in
                self?.togglePlayPause()
            }
            overlay.setSkipBackAction { [weak self] in
                self?.skip(seconds: -10)
            }
            overlay.setSkipForwardAction { [weak self] in
                self?.skip(seconds: 10)
            }
            overlay.primeForPresentation()
        }

        // Clear flag after transition is complete
        mpvView.isPiPTransitioning = false

        // pipWindow was already set above when creating or reusing
        self.isPiPActive = true

        // Update SwiftUI state
        DispatchQueue.main.async { [weak self] in
            self?.stateBinding?.wrappedValue = true
        }

        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 1.0
        }

        DispatchQueue.main.async {
            mpvView.layer?.setNeedsDisplay()
            mpvView.layer?.displayIfNeeded()
            mpvView.needsDisplay = true
            mpvView.display()
        }

    }

    func exitPiP() {
        guard isPiPActive else {
            return
        }

        // Prevent re-entry
        guard !isClosing else {
            return
        }

        isClosing = true

        // CRITICAL: Set flag BEFORE closing window to prevent display link from stopping
        mpvView?.isPiPTransitioning = true

        // Close the window - this will trigger windowWillClose delegate
        pipWindow?.close()
    }

    // Called by window delegate when PiP window is closing
    fileprivate func restoreVideoView() {
        guard let mpvView = self.mpvView else {
            return
        }

        if let window = pipWindow {
            persistFrame(window.frame)
            window.alphaValue = 0.0
        }

        mpvView.isPiPTransitioning = true

        mpvView.removeFromSuperview()

        // Restore to original parent
        if let originalParent = originalParentView {
            originalParent.addSubview(mpvView)

            if !originalConstraints.isEmpty {
                NSLayoutConstraint.activate(originalConstraints)
                mpvView.translatesAutoresizingMaskIntoConstraints = false
            } else {
                mpvView.translatesAutoresizingMaskIntoConstraints = true
                mpvView.autoresizingMask = [.width, .height]
                mpvView.frame = originalParent.bounds
            }

            originalParent.layoutSubtreeIfNeeded()

            if let layer = mpvView.layer as? MPVMetalLayer,
               let mainWindow = originalParent.window {
                layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                layer.contentsScale = mainWindow.backingScaleFactor

                let restoredBounds = CGRect(origin: .zero, size: mpvView.bounds.size)
                layer.forceUpdateForNewBounds(restoredBounds)
            }

            mpvView.isPiPTransitioning = false

            DispatchQueue.main.async {
                mpvView.layer?.setNeedsDisplay()
                mpvView.layer?.displayIfNeeded()
                mpvView.needsDisplay = true
                mpvView.display()
                originalParent.needsDisplay = true
                originalParent.needsLayout = true
                originalParent.layout()
            }
        }

        stateBinding?.wrappedValue = false

        NotificationCenter.default.post(name: .mpvPiPDidClose, object: nil)

        self.isPiPActive = false
        self.isClosing = false
        self.isCleaningUp = false

        self.originalParentView = nil
        self.originalConstraints = []
        self.stateBinding = nil

        if let window = self.pipWindow {
            window.contentView?.subviews.forEach { $0.removeFromSuperview() }
            window.delegate = nil
            window.orderOut(nil)
        }

        self.windowDelegate = nil

    }

    func togglePiP(
        mpvViewController: MPVVideoViewWrapper.MPVPiPViewController,
        stateBinding: Binding<Bool>,
        title: String,
        subtitle: String?,
        aspectRatio: CGSize?,
        isPlaying: Bool
    ) {
        if isPiPActive {
            exitPiP()
        } else {
            enterPiP(
                mpvViewController: mpvViewController,
                stateBinding: stateBinding,
                title: title,
                subtitle: subtitle,
                aspectRatio: aspectRatio,
                isPlaying: isPlaying
            )
        }
    }

    func updatePlaybackState(isPlaying: Bool) {
        controlOverlay?.updatePlayPauseState(isPlaying: isPlaying)
    }

    private func skip(seconds: Double) {
        guard let mpvController = mpvView?.mpvController else {
            return
        }

        mpvController.seekRelative(seconds: seconds)
    }

    private func togglePlayPause() {
        print("🎬 [PiP] togglePlayPause called")

        // Get the MPV controller from the view
        guard let mpvView = mpvView else {
            print("❌ [PiP] mpvView is nil")
            return
        }

        print("✅ [PiP] mpvView exists: \(mpvView)")

        guard let mpvController = mpvView.mpvController else {
            print("❌ [PiP] mpvController is nil")
            return
        }

        print("✅ [PiP] mpvController exists, calling togglePlayPause()")

        // Toggle play/pause using MPV's built-in toggle
        mpvController.togglePlayPause()

        print("✅ [PiP] togglePlayPause() called on controller")

        // Get current state and update UI
        // Note: We get the state after toggle, so if it was paused it's now playing
        if let isPaused: Bool = mpvController.getProperty("pause", type: .flag) {
            print("✅ [PiP] Current pause state: \(isPaused), updating UI to isPlaying: \(!isPaused)")
            controlOverlay?.updatePlayPauseState(isPlaying: !isPaused)
        } else {
            print("⚠️ [PiP] Could not get pause state from MPV")
        }
    }

    private func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Picture-in-Picture Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // Custom PiP control overlay view
    private class PiPControlOverlay: NSView {
        private let closeButton = NSButton()
        private let returnButton = NSButton()
        private let skipBackButton = NSButton()
        private let playPauseButton = NSButton()
        private let skipForwardButton = NSButton()
        private let controlsContainer = NSView()
        private let topBar = NSVisualEffectView()
        private let bottomBar = NSVisualEffectView()
        private let titleLabel = NSTextField(labelWithString: "")
        private let subtitleLabel = NSTextField(labelWithString: "")
        private var trackingArea: NSTrackingArea?
        private var isPlaying = true
        private var hideTimer: Timer?
        private var closeAction: (() -> Void)?
        private var returnAction: (() -> Void)?
        private var playPauseAction: (() -> Void)?
        private var skipBackAction: (() -> Void)?
        private var skipForwardAction: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool {
            true
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setupUI()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupUI() {
            wantsLayer = true
            controlsContainer.wantsLayer = true
            controlsContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
            controlsContainer.alphaValue = 0.0
            controlsContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(controlsContainer)

            configureBar(topBar)
            configureBar(bottomBar)
            controlsContainer.addSubview(topBar)
            controlsContainer.addSubview(bottomBar)

            configureSmallButton(returnButton, symbolName: "arrow.down.forward.and.arrow.up.backward", description: "Return to player")
            configureSmallButton(closeButton, symbolName: "xmark", description: "Close player")
            configureTransportButton(skipBackButton, symbolName: "gobackward.10", description: "Skip back 10 seconds", diameter: 34)
            configureTransportButton(playPauseButton, symbolName: "pause.fill", description: "Pause", diameter: 52)
            configureTransportButton(skipForwardButton, symbolName: "goforward.10", description: "Skip forward 10 seconds", diameter: 34)

            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            titleLabel.textColor = .white
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.maximumNumberOfLines = 1

            subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.72)
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.maximumNumberOfLines = 1

            let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
            titleStack.orientation = .vertical
            titleStack.alignment = .leading
            titleStack.spacing = 1
            titleStack.translatesAutoresizingMaskIntoConstraints = false

            let topStack = NSStackView(views: [returnButton, titleStack, closeButton])
            topStack.orientation = .horizontal
            topStack.alignment = .centerY
            topStack.spacing = 10
            topStack.translatesAutoresizingMaskIntoConstraints = false
            topBar.addSubview(topStack)

            let transportStack = NSStackView(views: [skipBackButton, playPauseButton, skipForwardButton])
            transportStack.orientation = .horizontal
            transportStack.alignment = .centerY
            transportStack.spacing = 14
            transportStack.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(transportStack)

            NSLayoutConstraint.activate([
                controlsContainer.topAnchor.constraint(equalTo: topAnchor),
                controlsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                controlsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
                controlsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

                topBar.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 10),
                topBar.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 10),
                topBar.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -10),
                topBar.heightAnchor.constraint(equalToConstant: 44),

                bottomBar.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
                bottomBar.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -14),
                bottomBar.heightAnchor.constraint(equalToConstant: 58),

                topStack.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 8),
                topStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
                topStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 10),
                topStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -10),
                titleStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

                transportStack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 10),
                transportStack.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -10),
                transportStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 14),
                transportStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -14)
            ])

            updateTrackingAreas()
            hideControls(immediately: true)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea = trackingArea {
                removeTrackingArea(trackingArea)
            }

            trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )

            if let trackingArea = trackingArea {
                addTrackingArea(trackingArea)
            }
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            showControls(resetAutoHide: true)
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            showControls(resetAutoHide: true)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            scheduleHide(after: 0.45)
        }

        private func configureBar(_ view: NSVisualEffectView) {
            view.material = .hudWindow
            view.blendingMode = .withinWindow
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = 14
            view.layer?.masksToBounds = true
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        private func configureSmallButton(_ button: NSButton, symbolName: String, description: String) {
            configureTransportButton(button, symbolName: symbolName, description: description, diameter: 28)
            button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        }

        private func configureTransportButton(_ button: NSButton, symbolName: String, description: String, diameter: CGFloat) {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            button.isBordered = false
            button.bezelStyle = .shadowlessSquare
            button.imagePosition = .imageOnly
            button.contentTintColor = .white
            button.imageScaling = .scaleProportionallyDown
            button.translatesAutoresizingMaskIntoConstraints = false
            button.wantsLayer = true
            button.layer?.cornerRadius = diameter / 2
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(symbolName == "pause.fill" ? 0.18 : 0.10).cgColor
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            button.layer?.borderWidth = 1
            button.widthAnchor.constraint(equalToConstant: diameter).isActive = true
            button.heightAnchor.constraint(equalToConstant: diameter).isActive = true
        }

        private func showControls(resetAutoHide: Bool) {
            hideTimer?.invalidate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                controlsContainer.animator().alphaValue = 1.0
            }
            if resetAutoHide {
                scheduleHide(after: 2.2)
            }
        }

        private func hideControls(immediately: Bool = false) {
            hideTimer?.invalidate()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = immediately ? 0.0 : 0.2
                context.allowsImplicitAnimation = true
                controlsContainer.animator().alphaValue = 0.0
            }
        }

        private func scheduleHide(after delay: TimeInterval) {
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.hideControls()
            }
        }

        func primeForPresentation() {
            showControls(resetAutoHide: true)
        }

        func setTitle(_ title: String, subtitle: String?) {
            titleLabel.stringValue = title
            subtitleLabel.stringValue = subtitle ?? ""
            subtitleLabel.isHidden = subtitle == nil || subtitle?.isEmpty == true
        }

        func setCloseAction(_ action: @escaping () -> Void) {
            closeButton.target = self
            closeButton.action = #selector(handleClose)
            self.closeAction = action
        }

        func setReturnAction(_ action: @escaping () -> Void) {
            returnButton.target = self
            returnButton.action = #selector(handleReturn)
            self.returnAction = action
        }

        func setPlayPauseAction(_ action: @escaping () -> Void) {
            playPauseButton.target = self
            playPauseButton.action = #selector(handlePlayPause)
            self.playPauseAction = action
        }

        func setSkipBackAction(_ action: @escaping () -> Void) {
            skipBackButton.target = self
            skipBackButton.action = #selector(handleSkipBack)
            self.skipBackAction = action
        }

        func setSkipForwardAction(_ action: @escaping () -> Void) {
            skipForwardButton.target = self
            skipForwardButton.action = #selector(handleSkipForward)
            self.skipForwardAction = action
        }

        func updatePlayPauseState(isPlaying: Bool) {
            self.isPlaying = isPlaying
            let imageName = isPlaying ? "pause.fill" : "play.fill"
            playPauseButton.image = NSImage(systemSymbolName: imageName, accessibilityDescription: isPlaying ? "Pause" : "Play")
            playPauseButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(isPlaying ? 0.18 : 0.24).cgColor
        }

        @objc private func handleClose() {
            showControls(resetAutoHide: false)
            closeAction?()
        }

        @objc private func handleReturn() {
            showControls(resetAutoHide: false)
            returnAction?()
        }

        @objc private func handlePlayPause() {
            showControls(resetAutoHide: true)
            playPauseAction?()
        }

        @objc private func handleSkipBack() {
            showControls(resetAutoHide: true)
            skipBackAction?()
        }

        @objc private func handleSkipForward() {
            showControls(resetAutoHide: true)
            skipForwardAction?()
        }

        deinit {
            hideTimer?.invalidate()
        }
    }

    // Window delegate to handle close event
    private class PiPWindowDelegate: NSObject, NSWindowDelegate {
        private var hasHandledClose = false

        func windowWillClose(_ notification: Notification) {
            guard !hasHandledClose else {
                return
            }
            hasHandledClose = true

            // Guard against double-close by checking if view still exists
            guard MPVPiPWindowManager.shared.mpvView != nil else {
                return
            }
            // Restore the video view to the main window
            MPVPiPWindowManager.shared.restoreVideoView()
        }

        func windowDidMove(_ notification: Notification) {
            if let window = notification.object as? NSWindow {
                MPVPiPWindowManager.shared.persistFrame(window.frame)
            }
        }

        func windowDidEndLiveResize(_ notification: Notification) {
            if let window = notification.object as? NSWindow {
                MPVPiPWindowManager.shared.persistFrame(window.frame)
            }
        }
    }
}
#endif
