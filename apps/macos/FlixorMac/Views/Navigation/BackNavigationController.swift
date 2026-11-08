//
//  BackNavigationController.swift
//  FlixorMac
//
//  Back / forward navigation for the main window: the mouse back and forward
//  buttons, Esc, and the Go menu (⌘[ / ⌘]) pop or restore the current tab's
//  navigation path. MainView registers its router, tab state and window.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class BackNavigationController: ObservableObject {
    static let shared = BackNavigationController()

    /// True when the current tab has something to pop and nothing blocks it.
    @Published private(set) var canGoBack = false
    /// True when Back was used and the page it left can be restored.
    @Published private(set) var canGoForward = false

    private weak var router: NavigationRouter?
    private weak var mainViewState: MainViewState?
    private weak var mainWindow: NSWindow?
    private var eventMonitor: Any?
    private var observers: Set<AnyCancellable> = []

    /// A path Back left behind, valid while the tab still shows `after`.
    private struct ForwardEntry {
        let before: NavigationPath
        let after: NavigationPath
    }
    private var forwardStacks: [NavItem: [ForwardEntry]] = [:]
    private let maxForwardEntries = 20

    /// An overlay inside a page (not a sheet). Back and Esc close it before they
    /// touch the page. Tab and depth say which page it sits on, since hidden tabs
    /// stay alive with their overlays still open.
    private struct InPageModal {
        let id: UUID
        let tab: NavItem
        let depth: Int
        let dismiss: () -> Void
    }
    private var inPageModals: [InPageModal] = []

    /// Last left click in the main window, used to anchor the push animation.
    private var lastClick: (anchor: UnitPoint, time: Date)?

    private enum MouseButton {
        static let back = 3
        static let forward = 4
    }
    private let escapeKeyCode: UInt16 = 53

    private init() {}

    // MARK: - Registration

    /// Called by MainView. Installs the event monitor once.
    func register(router: NavigationRouter, mainViewState: MainViewState) {
        if self.router !== router || self.mainViewState !== mainViewState {
            self.router = router
            self.mainViewState = mainViewState
            forwardStacks.removeAll()
            observeState()
        }
        installMonitorIfNeeded()
        refreshAvailability()
    }

    /// The window that hosts MainView. Events from other windows (Settings,
    /// sheets, popovers) are ignored.
    func registerWindow(_ window: NSWindow?) {
        guard let window else { return }
        mainWindow = window
    }

    /// Registers an in-page overlay on the page showing now. See `inPageModal(onDismiss:)`.
    func registerInPageModal(id: UUID, dismiss: @escaping () -> Void) {
        guard let tab = mainViewState?.selectedTab, let depth = currentPath()?.count else { return }
        inPageModals.removeAll { $0.id == id }
        inPageModals.append(InPageModal(id: id, tab: tab, depth: depth, dismiss: dismiss))
    }

    func unregisterInPageModal(id: UUID) {
        inPageModals.removeAll { $0.id == id }
    }

    /// The topmost overlay on the page the user is looking at.
    private var activeInPageModal: InPageModal? {
        guard let tab = mainViewState?.selectedTab, let depth = currentPath()?.count else { return nil }
        return inPageModals.last { $0.tab == tab && $0.depth == depth }
    }

    private func observeState() {
        observers.removeAll()
        guard let router, let mainViewState else { return }
        // objectWillChange fires before the value changes; hop to the next
        // run loop turn so the new value is read.
        Publishers.Merge3(
            router.objectWillChange.map { _ in () },
            mainViewState.objectWillChange.map { _ in () },
            PlaybackCommandState.shared.objectWillChange.map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refreshAvailability() }
        .store(in: &observers)
    }

    private func refreshAvailability() {
        let blocked = PlaybackCommandState.shared.isPlayerActive
        let back = !blocked && !(currentPath()?.isEmpty ?? true)
        var forward = false
        if !blocked, let tab = mainViewState?.selectedTab,
           let entry = forwardStacks[tab]?.last, let path = currentPath() {
            forward = entry.after == path
        }
        if canGoBack != back { canGoBack = back }
        if canGoForward != forward { canGoForward = forward }
    }

    // MARK: - Actions

    /// Closes the page's in-page overlay if one is open, else pops the current
    /// tab's top page. Returns false when there was nothing to do or navigation
    /// is blocked (player, sheet, modal).
    @discardableResult
    func goBack() -> Bool {
        guard isNavigationAllowed(in: mainWindow),
              let router, let tab = mainViewState?.selectedTab else { return false }
        if let modal = activeInPageModal {
            modal.dismiss()
            return true
        }
        let binding = router.pathBinding(for: tab)
        var path = binding.wrappedValue
        guard !path.isEmpty else { return false }
        let before = path
        path.removeLast()
        var stack = forwardStacks[tab] ?? []
        stack.append(ForwardEntry(before: before, after: path))
        if stack.count > maxForwardEntries { stack.removeFirst(stack.count - maxForwardEntries) }
        forwardStacks[tab] = stack
        binding.wrappedValue = path
        return true
    }

    /// Restores the page the last Back left, if the user has not navigated
    /// somewhere else since.
    @discardableResult
    func goForward() -> Bool {
        guard isNavigationAllowed(in: mainWindow), activeInPageModal == nil,
              let router, let tab = mainViewState?.selectedTab,
              var stack = forwardStacks[tab], let entry = stack.last else { return false }
        let binding = router.pathBinding(for: tab)
        guard binding.wrappedValue == entry.after else {
            // The user pushed or popped elsewhere: the forward history is stale.
            forwardStacks[tab] = nil
            refreshAvailability()
            return false
        }
        stack.removeLast()
        forwardStacks[tab] = stack
        binding.wrappedValue = entry.before
        return true
    }

    /// Anchor of a click made in the last moment, or `.center` (keyboard
    /// activation, programmatic pushes).
    func recentClickAnchor(within interval: TimeInterval = 0.8) -> UnitPoint {
        guard let lastClick, Date().timeIntervalSince(lastClick.time) <= interval else { return .center }
        return lastClick.anchor
    }

    // MARK: - Event monitor

    private func installMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown, .leftMouseDown]) { event in
            // Local monitors are always called on the main thread. NSEvent is
            // not Sendable, so only a Bool crosses into the isolated closure.
            nonisolated(unsafe) let unsafeEvent = event
            let consumed = MainActor.assumeIsolated {
                BackNavigationController.shared.consumes(unsafeEvent)
            }
            return consumed ? nil : event
        }
    }

    /// Returns true when the event was handled and must not propagate.
    private func consumes(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            recordClick(event)
            return false

        case .otherMouseDown:
            // The preview usually sits under the pointer, so the event can be its panel's.
            guard let window = event.window, window === mainWindow || window is HoverPreviewPanel else { return false }
            switch event.buttonNumber {
            case MouseButton.back:
                let hadPreview = dismissHoverPreview()
                return goBack() || hadPreview
            case MouseButton.forward:
                let hadPreview = dismissHoverPreview()
                return goForward() || hadPreview
            default: return false
            }

        case .keyDown:
            guard event.keyCode == escapeKeyCode,
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  let window = event.window, window === mainWindow else { return false }
            // The preview is the frontmost thing: Esc closes only that.
            if dismissHoverPreview() { return true }
            guard !isEditingText(in: window) else { return false }
            return goBack()

        default:
            return false
        }
    }

    /// Returns true when a hover preview was showing.
    private func dismissHoverPreview() -> Bool {
        guard HoverPreviewController.shared.isShowingPreview else { return false }
        HoverPreviewController.shared.dismiss(animated: false)
        return true
    }

    private func recordClick(_ event: NSEvent) {
        guard let window = event.window, window === mainWindow,
              let content = window.contentView, content.bounds.width > 0, content.bounds.height > 0 else { return }
        let point = event.locationInWindow // bottom-left origin
        let x = min(max(point.x / content.bounds.width, 0), 1)
        let y = min(max(1 - point.y / content.bounds.height, 0), 1)
        lastClick = (UnitPoint(x: x, y: y), Date())
    }

    // MARK: - Guards

    /// Back/forward only act on the main window when no player, sheet, modal
    /// or popover is in front of it. The player handles Esc itself.
    private func isNavigationAllowed(in window: NSWindow?) -> Bool {
        guard let window, window === mainWindow else { return false }
        if PlaybackCommandState.shared.isPlayerActive { return false }
        if NSApp.modalWindow != nil { return false }
        if window.attachedSheet != nil || !window.sheets.isEmpty { return false }
        // A popover or other panel took key status.
        if !window.isKeyWindow { return false }
        // The hover preview is a child window too, but it doesn't take over the page.
        if window.childWindows?.contains(where: { $0.isVisible && !($0 is HoverPreviewPanel) }) == true { return false }
        return true
    }

    /// True while a text field or text view in `window` is being edited
    /// (the field editor is the first responder).
    private func isEditingText(in window: NSWindow) -> Bool {
        window.firstResponder is NSText
    }

    private func currentPath() -> NavigationPath? {
        guard let router, let tab = mainViewState?.selectedTab else { return nil }
        return router.pathBinding(for: tab).wrappedValue
    }
}

// MARK: - In-page modals

extension View {
    /// Marks this view as an overlay inside a page (not a sheet): while it is on
    /// screen, Esc, the mouse back button and Back call `onDismiss` instead of
    /// popping the page. Apply it to the content shown only while the overlay is open.
    func inPageModal(onDismiss: @escaping () -> Void) -> some View {
        modifier(InPageModalModifier(onDismiss: onDismiss))
    }
}

private struct InPageModalModifier: ViewModifier {
    let onDismiss: () -> Void
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { BackNavigationController.shared.registerInPageModal(id: id, dismiss: onDismiss) }
            .onDisappear { BackNavigationController.shared.unregisterInPageModal(id: id) }
    }
}

// MARK: - Window reader

/// Reports the NSWindow hosting the view (used to register the main window).
struct HostingWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class WindowReportingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
