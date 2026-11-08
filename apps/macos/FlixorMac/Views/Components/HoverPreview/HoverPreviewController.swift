//
//  HoverPreviewController.swift
//  FlixorMac
//
//  Shows at most one hover preview at a time, in a borderless child panel of
//  the app window. A child window is never clipped by row scroll views and
//  needs no host view in the screen hierarchy.
//
//  Rules:
//  - Appears after the configured delay while the pointer rests on a card;
//    never while (or just after) the user scrolls, never with VoiceOver on
//    (the context menu covers the same actions), never over a sheet.
//  - Positioned centred over the card and clamped inside the window.
//  - Dismissed when the pointer leaves both the preview and the card for a
//    short grace period, on scroll, when the window loses key status, moves to
//    another size, or the card disappears. While fading out it ignores the
//    mouse, so clicks reach the cards underneath.
//  - Dismissing cancels metadata/trailer work and tears down the player.
//

import AppKit
import SwiftUI

struct HoverPreviewRequest {
    /// Identity of the card instance asking (stable for the card's lifetime).
    let token: UUID
    let item: MediaItem
    let anchor: CardAnchorBox
    var onOpen: (() -> Void)?
    var onPlay: (() -> Void)?
    var watchlistController: WatchlistController?
}

@MainActor
final class HoverPreviewController {
    static let shared = HoverPreviewController()

    /// Pointer must stay out of preview and card this long before it closes.
    private let dismissGrace: TimeInterval = 0.15
    /// No preview within this long after a scroll event.
    private let scrollQuietPeriod: TimeInterval = 0.35
    private let edgeMargin: CGFloat = DS.Space.s12

    private var candidate: HoverPreviewRequest?
    private var showTask: Task<Void, Never>?

    private var current: HoverPreviewRequest?
    private var model: HoverPreviewModel?
    private var panel: HoverPreviewPanel?
    private var hostingView: HoverPreviewHostingView?
    private var previewRect: NSRect = .zero
    private weak var parentWindow: NSWindow?

    private var trackingTimer: Timer?
    private var outsideSince: Date?
    private var lastScrollAt: Date = .distantPast
    private var scrollMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    var isShowingPreview: Bool { current != nil }

    // MARK: - Card events

    func cardHoverBegan(_ request: HoverPreviewRequest) {
        installScrollMonitorIfNeeded()
        if current?.token == request.token {
            outsideSince = nil
            return
        }
        guard CardStyleStore.shared.hoverPreviewEnabled,
              !NSWorkspace.shared.isVoiceOverEnabled else { return }

        candidate = request
        showTask?.cancel()
        let delay = CardStyleStore.shared.hoverPreviewDelay
        showTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            // Wait for scrolling to settle.
            while let self, !Task.isCancelled {
                let sinceScroll = Date().timeIntervalSince(self.lastScrollAt)
                if sinceScroll >= self.scrollQuietPeriod { break }
                try? await Task.sleep(nanoseconds: UInt64((self.scrollQuietPeriod - sinceScroll) * 1_000_000_000))
            }
            guard let self, !Task.isCancelled, self.candidate?.token == request.token else { return }
            self.present(request)
        }
    }

    func cardHoverEnded(token: UUID) {
        if candidate?.token == token {
            showTask?.cancel()
            showTask = nil
            candidate = nil
        }
        // A visible preview is closed by the tracking timer (the pointer is
        // usually moving into the preview, which covers the card).
    }

    func cardDisappeared(token: UUID) {
        cardHoverEnded(token: token)
        if current?.token == token { dismiss(animated: false) }
    }

    // MARK: - Present

    private func present(_ request: HoverPreviewRequest) {
        candidate = nil
        guard let anchorView = request.anchor.view,
              let window = anchorView.window,
              window.isVisible, window.isKeyWindow, window.attachedSheet == nil,
              NSApp.isActive else { return }

        let cardRect = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        guard cardRect.width > 1, cardRect.contains(NSEvent.mouseLocation) else { return }

        dismiss(animated: false)

        let style = CardStyleStore.shared
        let width = Self.previewWidth(forCardWidth: cardRect.width)
        let model = HoverPreviewModel(item: request.item, trailerMode: style.hoverTrailerMode)
        let actions = HoverPreviewActions(
            onOpen: request.onOpen,
            onPlay: request.onPlay,
            watchlistController: request.watchlistController,
            dismiss: { [weak self] in self?.dismiss(animated: false) }
        )

        let root = AnyView(
            HoverPreviewCard(model: model, width: width, actions: actions)
                .flixorAppearance()
                .environment(\.colorScheme, .dark)
        )

        let panel = self.panel ?? HoverPreviewPanel()
        self.panel = panel
        let hosting: HoverPreviewHostingView
        if let existing = hostingView {
            existing.rootView = root
            hosting = existing
        } else {
            hosting = HoverPreviewHostingView(rootView: root)
            hostingView = hosting
            panel.contentView = hosting
        }

        let fitting = hosting.fittingSize
        let inset = HoverPreviewCard.shadowInset
        let size = NSSize(width: width, height: max(fitting.height - inset * 2, width * 9 / 16))

        let bounds = window.convertToScreen(window.contentLayoutRect).insetBy(dx: edgeMargin, dy: edgeMargin)
        var origin = NSPoint(x: cardRect.midX - size.width / 2, y: cardRect.midY - size.height / 2)
        origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        previewRect = NSRect(origin: origin, size: size)

        panel.setFrame(previewRect.insetBy(dx: -inset, dy: -inset), display: false)
        panel.ignoresMouseEvents = false
        // Zero-length group so it also overrides a fade-out still in flight.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)

        current = request
        self.model = model
        parentWindow = window
        outsideSince = nil
        observe(window)
        startTracking()
    }

    /// Wider than the card, within comfortable reading limits.
    static func previewWidth(forCardWidth cardWidth: CGFloat) -> CGFloat {
        min(max(cardWidth * 1.5, 340), 460).rounded()
    }

    // MARK: - Dismiss

    func dismiss(animated: Bool = true) {
        showTask?.cancel()
        showTask = nil
        candidate = nil
        guard current != nil, let panel else { return }

        current = nil
        model?.cancel()
        model = nil
        stopTracking()
        removeObservers()
        panel.ignoresMouseEvents = true

        let finish: () -> Void = { [weak self, weak panel] in
            guard let panel else { return }
            // A newer preview may already be using the panel.
            guard self?.current == nil else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            // Drop the SwiftUI tree so the trailer's web view stops right away.
            self?.hostingView?.rootView = AnyView(EmptyView())
        }

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = DS.Motion.quickDuration
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { finish() }
            })
        } else {
            finish()
        }
    }

    // MARK: - Tracking

    private func startTracking() {
        stopTracking()
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func tick() {
        guard let request = current, let panel else { return }
        guard let window = parentWindow, window.isKeyWindow, window.attachedSheet == nil, NSApp.isActive else {
            dismiss(animated: false)
            return
        }

        let mouse = NSEvent.mouseLocation
        var inside = previewRect.contains(mouse)
        if !inside, let view = request.anchor.view, let anchorWindow = view.window {
            inside = anchorWindow.convertToScreen(view.convert(view.bounds, to: nil)).contains(mouse)
        }

        if inside {
            if outsideSince != nil {
                outsideSince = nil
                panel.ignoresMouseEvents = false
            }
        } else if let since = outsideSince {
            if Date().timeIntervalSince(since) >= dismissGrace { dismiss() }
        } else {
            outsideSince = Date()
            // Let clicks through to neighbouring cards during the grace period.
            panel.ignoresMouseEvents = true
        }
    }

    private func installScrollMonitorIfNeeded() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastScrollAt = Date()
                if self.current != nil { self.dismiss(animated: false) }
            }
            return event
        }
    }

    private func observe(_ window: NSWindow) {
        removeObservers()
        let center = NotificationCenter.default
        let names: [(Notification.Name, AnyObject?)] = [
            (NSWindow.didResignKeyNotification, window),
            (NSWindow.didResizeNotification, window),
            (NSWindow.willCloseNotification, window),
            (NSApplication.didResignActiveNotification, NSApp),
        ]
        observers = names.map { name, object in
            center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(animated: false) }
            }
        }
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}

// MARK: - Panel

/// Borderless, non-activating panel that never becomes key, so keyboard focus
/// stays in the main window.
final class HoverPreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        animationBehavior = .none
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .transient]
        appearance = NSAppearance(named: .darkAqua)
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that takes the first click even though its window is not key.
final class HoverPreviewHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
