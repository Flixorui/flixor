//
//  CardKeyboardFocus.swift
//  FlixorMac
//
//  Keyboard navigation for card rows (CarouselView):
//  - CardKeyboardModeTracker: is the user driving with the keyboard right now?
//    Focus rings only show then, so mouse users never see a stray ring.
//  - CardRowFocusHandle: one per row; geometry the registry needs plus the
//    open-details actions cards register.
//  - CardRowFocusRegistry: moves focus Up/Down to the nearest card of the
//    neighbouring row on the same page (same vertical scroll view).
//  - CardFocusContext: environment value a row gives each card (ring visibility
//    and a way to register its open action).
//

import AppKit
import SwiftUI

// MARK: - Keyboard mode

@MainActor
final class CardKeyboardModeTracker: ObservableObject {
    static let shared = CardKeyboardModeTracker()

    @Published private(set) var isKeyboardActive = false

    private var monitor: Any?

    /// Arrow keys, Tab, Return and Enter.
    private static let navigationKeyCodes: Set<UInt16> = [123, 124, 125, 126, 48, 36, 76]

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            if Self.navigationKeyCodes.contains(event.keyCode), !isKeyboardActive {
                isKeyboardActive = true
            }
            return
        }
        if isKeyboardActive { isKeyboardActive = false }

        // SwiftUI builds context menus without a reliable "will open" callback,
        // so the Trakt lists start loading on the click that opens one.
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            CardTraktListsCache.shared.loadIfNeeded()
        }
    }
}

// MARK: - Environment

/// What a row tells each of its cards. Nil outside a keyboard-navigable row.
struct CardFocusContext {
    /// The card has keyboard focus and the user is navigating with the keyboard.
    var isFocusRingVisible: Bool
    /// Cards call this (on appear) with their open-details action so Return can
    /// trigger it while the card is focused.
    var registerOpenAction: (@escaping () -> Void) -> Void
}

private struct CardFocusContextKey: EnvironmentKey {
    static let defaultValue: CardFocusContext? = nil
}

extension EnvironmentValues {
    var cardFocusContext: CardFocusContext? {
        get { self[CardFocusContextKey.self] }
        set { self[CardFocusContextKey.self] = newValue }
    }
}

// MARK: - Row handle

@MainActor
final class CardRowFocusHandle: ObservableObject {
    let id = UUID()

    /// Row-level anchor (background of the carousel) used for geometry.
    let anchorBox = CardAnchorBox()
    var anchorView: NSView? { anchorBox.view }

    var itemCount = 0
    var itemWidth: CGFloat = 0
    var spacing: CGFloat = 0
    /// Index and x (in the row's coordinate space) of the leftmost visible card.
    var firstVisibleIndex = 0
    var firstVisibleMinX: CGFloat = 0

    /// Set by the registry to move focus into this row; the row applies and clears it.
    @Published var requestedFocus: Int?

    /// Open-details actions keyed by item id.
    private var openActions: [AnyHashable: () -> Void] = [:]

    var stride: CGFloat { itemWidth + spacing }

    func registerOpenAction(_ action: @escaping () -> Void, for id: AnyHashable) {
        openActions[id] = action
    }

    func open(id: AnyHashable) {
        openActions[id]?()
    }

    /// Centre x of the card at `index`, in the anchor view's coordinates.
    func centerX(of index: Int) -> CGFloat {
        firstVisibleMinX + CGFloat(index - firstVisibleIndex) * stride + itemWidth / 2
    }

    /// The card whose centre is nearest to `x` (anchor coordinates).
    func nearestIndex(toX x: CGFloat) -> Int {
        guard itemCount > 0, stride > 0 else { return 0 }
        let offset = (x - itemWidth / 2 - firstVisibleMinX) / stride
        let index = firstVisibleIndex + Int(offset.rounded())
        return min(max(index, 0), itemCount - 1)
    }
}

// MARK: - Registry

@MainActor
final class CardRowFocusRegistry {
    static let shared = CardRowFocusRegistry()

    private final class WeakHandle {
        weak var handle: CardRowFocusHandle?
        init(_ handle: CardRowFocusHandle) { self.handle = handle }
    }

    private var rows: [UUID: WeakHandle] = [:]

    private init() {}

    func register(_ handle: CardRowFocusHandle) {
        rows[handle.id] = WeakHandle(handle)
    }

    func unregister(_ handle: CardRowFocusHandle) {
        rows[handle.id] = nil
    }

    /// Moves focus from card `index` of `source` to the nearest card in the row
    /// above (`up`) or below. Returns false when there is no such row.
    @discardableResult
    func moveVertically(from source: CardRowFocusHandle, index: Int, up: Bool) -> Bool {
        rows = rows.filter { $0.value.handle != nil }
        guard let sourceView = source.anchorView, let window = sourceView.window else { return false }
        let sourcePage = sourceView.enclosingScrollView
        let sourceFrame = sourceView.convert(sourceView.bounds, to: nil)
        let pointInSource = NSPoint(x: source.centerX(of: index), y: sourceView.bounds.midY)
        let pointInWindow = sourceView.convert(pointInSource, to: nil)

        var best: (handle: CardRowFocusHandle, distance: CGFloat)?
        for entry in rows.values {
            guard let candidate = entry.handle, candidate !== source, candidate.itemCount > 0,
                  let view = candidate.anchorView, view.window === window else { continue }
            // Same page only: hidden tabs stay in the hierarchy at the same frames.
            let page = view.enclosingScrollView
            guard page === sourcePage else { continue }
            let frame = view.convert(view.bounds, to: nil)
            // Window coordinates grow upwards.
            let distance = up ? frame.midY - sourceFrame.midY : sourceFrame.midY - frame.midY
            guard distance > 1 else { continue }
            if best == nil || distance < best!.distance {
                best = (candidate, distance)
            }
        }

        guard let target = best?.handle, let targetView = target.anchorView else { return false }
        let x = targetView.convert(pointInWindow, from: nil).x
        target.requestedFocus = target.nearestIndex(toX: x)
        return true
    }
}

// MARK: - NSView helpers

extension NSView {
    /// Document view of the nearest enclosing vertically scrolling NSScrollView.
    var flixorVerticalDocumentView: NSView? {
        var view = superview
        while let current = view {
            if let clip = current as? NSClipView, let document = clip.documentView,
               document.frame.height > clip.bounds.height + 1 {
                return document
            }
            view = current.superview
        }
        return nil
    }

    /// Scrolls the nearest vertically scrolling ancestor the minimum amount so
    /// this view (plus `margin`) is visible. No-op when there is none.
    func flixorScrollIntoViewVertically(margin: CGFloat) {
        guard let document = flixorVerticalDocumentView else { return }
        let rect = convert(bounds, to: document).insetBy(dx: 0, dy: -margin)
        document.scrollToVisible(rect)
    }
}

/// Zero-size-cost NSView that never takes mouse events; used as a geometry anchor.
final class CardAnchorNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}

/// Weak reference to an anchor view, safe to keep in SwiftUI @State.
final class CardAnchorBox {
    weak var view: NSView?
}

/// Background view that publishes its NSView into a `CardAnchorBox`.
struct CardAnchorView: NSViewRepresentable {
    let box: CardAnchorBox

    func makeNSView(context: Context) -> CardAnchorNSView {
        let view = CardAnchorNSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: CardAnchorNSView, context: Context) {
        box.view = nsView
    }
}

// MARK: - Focus effect

extension View {
    /// Hides the system focus effect (macOS 14+) where the app draws its own ring.
    @ViewBuilder
    func flixorSystemFocusEffectDisabled() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}
