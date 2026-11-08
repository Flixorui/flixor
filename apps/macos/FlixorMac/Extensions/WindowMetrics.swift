//
//  WindowMetrics.swift
//  FlixorMac
//
//  Window size and size class for responsive layout.
//
//  Injected once per window by `.trackWindowMetrics()` (FlixorMacApp). Read it
//  in any view:
//
//      @Environment(\.windowMetrics) private var metrics
//      ...
//      .frame(height: metrics.heroHeight(for: .billboard))
//      PosterCard(item: item, width: metrics.posterWidth(base: 160))
//      .padding(.horizontal, metrics.pageGutter)
//
//  Updates are cheap: the size class changes immediately when a breakpoint is
//  crossed; exact width/height updates are debounced while the user drags the
//  window edge. Only views that read `\.windowMetrics` re-render.
//
//  Sheets inherit the metrics of the window that presents them.
//

import SwiftUI

// MARK: - Size class

/// Coarse window width classes. Thresholds are in points of window content
/// width; the main window's minimum width is 1024.
enum WindowSizeClass: Int, Comparable, CaseIterable {
    /// < 1280: minimum-size windows, half of a laptop screen.
    case compact
    /// 1280 ..< 1728: a typical maximised laptop window (reference 1440).
    case regular
    /// 1728 ..< 2400: large external displays.
    case wide
    /// >= 2400, or a very wide aspect ratio (21:9 and up) at >= 1900.
    case ultrawide

    static func < (lhs: WindowSizeClass, rhs: WindowSizeClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func classify(width: CGFloat, height: CGFloat) -> WindowSizeClass {
        let aspect = height > 0 ? width / height : 0
        if width >= 2400 || (width >= 1900 && aspect >= 2.1) { return .ultrawide }
        if width >= 1728 { return .wide }
        if width >= 1280 { return .regular }
        return .compact
    }
}

// MARK: - Metrics

struct WindowMetrics: Equatable {
    /// Window content width in points (full window, including the area under
    /// the hidden title bar / toolbar).
    let width: CGFloat
    /// Window content height in points (same basis as `width`).
    let height: CGFloat
    let sizeClass: WindowSizeClass

    init(width: CGFloat, height: CGFloat) {
        self.width = width.rounded()
        self.height = height.rounded()
        self.sizeClass = WindowSizeClass.classify(width: self.width, height: self.height)
    }

    init(size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    /// Value used before the first measurement (and outside a tracked window):
    /// the reference size, so fixed layouts look as they always have.
    static let reference = WindowMetrics(size: DS.Layout.referenceWindow)

    var size: CGSize { CGSize(width: width, height: height) }
    var aspectRatio: CGFloat { height > 0 ? width / height : 16.0 / 10.0 }

    var isCompact: Bool { sizeClass == .compact }
    var isWideOrLarger: Bool { sizeClass >= .wide }

    // MARK: Scale factors

    /// Continuous layout scale relative to the 1440 x 900 reference window,
    /// limited to 0.85 ... 1.5. Uses the tighter of the two axes so a short
    /// but wide window does not blow up vertical sizes.
    var layoutScale: CGFloat {
        let ref = DS.Layout.referenceWindow
        let raw = min(width / ref.width, height / ref.height)
        return min(max(raw, 0.85), 1.5)
    }

    /// Stepped scale for item sizes (posters, cards). Stepped rather than
    /// continuous so rows do not re-layout on every pixel of a resize.
    var itemScale: CGFloat {
        switch sizeClass {
        case .compact: return 0.9
        case .regular: return 1.0
        case .wide: return 1.12
        case .ultrawide: return 1.25
        }
    }

    // MARK: Helpers

    /// Horizontal page inset that grows with the window.
    var pageGutter: CGFloat {
        switch sizeClass {
        case .compact: return DS.Space.s32
        case .regular: return DS.Space.s40
        case .wide: return DS.Space.s60
        case .ultrawide: return DS.Space.s80
        }
    }

    /// Poster width for a design-time `base` width (the value used at the
    /// reference window, e.g. 150 or 160). Height is `width * DS.Layout.posterAspect`.
    func posterWidth(base: CGFloat) -> CGFloat {
        (base * itemScale).rounded()
    }

    /// Poster height matching `posterWidth(base:)`.
    func posterHeight(base: CGFloat) -> CGFloat {
        (posterWidth(base: base) * DS.Layout.posterAspect).rounded()
    }

    /// Landscape card width for a design-time `base` width (e.g. 260 or 380).
    func cardWidth(base: CGFloat) -> CGFloat {
        (base * itemScale).rounded()
    }

    /// Hero height for a hero style. At the reference window each style
    /// returns the fixed height it uses today; it scales with `layoutScale`
    /// and never exceeds what the window can show sensibly.
    func heroHeight(for style: HeroHeightStyle) -> CGFloat {
        let value: CGFloat
        switch style {
        case .billboard:
            // Today: BillboardView 1000pt fixed.
            value = 1000 * layoutScale
        case .carousel:
            // Today: HeroCarousel 580pt fixed.
            value = min(580 * layoutScale, height * 0.8)
        case .spotlight:
            // Today: NewPopularHero 700pt fixed.
            value = min(700 * layoutScale, height * 0.9)
        case .details:
            // Backdrop area of a details page.
            value = min(max(height * 0.75, 520), 1100)
        case let .fraction(fraction, minimum, maximum):
            value = min(max(height * fraction, minimum), maximum)
        }
        return value.rounded()
    }

    /// Number of grid columns that fit `minItemWidth` wide items separated by
    /// `spacing` inside the window minus page gutters.
    func columns(minItemWidth: CGFloat, spacing: CGFloat = DS.Space.itemGap) -> Int {
        let available = width - pageGutter * 2
        guard minItemWidth > 0, available > 0 else { return 1 }
        return max(1, Int((available + spacing) / (minItemWidth + spacing)))
    }
}

/// Hero styles for `WindowMetrics.heroHeight(for:)`.
enum HeroHeightStyle: Equatable {
    /// Full-bleed home billboard.
    case billboard
    /// Home hero carousel.
    case carousel
    /// New & Popular spotlight hero.
    case spotlight
    /// Details page backdrop.
    case details
    /// `fraction` of the window height, clamped to `minimum ... maximum`.
    case fraction(CGFloat, minimum: CGFloat, maximum: CGFloat)
}

// MARK: - Environment

private struct WindowMetricsKey: EnvironmentKey {
    static let defaultValue = WindowMetrics.reference
}

extension EnvironmentValues {
    /// Size of the window this view is in. Injected by `.trackWindowMetrics()`.
    var windowMetrics: WindowMetrics {
        get { self[WindowMetricsKey.self] }
        set { self[WindowMetricsKey.self] = newValue }
    }
}

// MARK: - Tracking

/// Measures the window and publishes debounced metrics.
@MainActor
final class WindowMetricsTracker: ObservableObject {
    @Published private(set) var metrics = WindowMetrics.reference

    private var hasMeasured = false
    private var debounceTask: Task<Void, Never>?
    /// Trailing debounce for exact-size updates within one size class.
    private let debounceNanoseconds: UInt64 = 120_000_000

    func update(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let next = WindowMetrics(size: size)
        guard next != metrics else {
            debounceTask?.cancel()
            return
        }

        // First measurement and breakpoint crossings apply immediately so
        // layouts never sit in the wrong size class.
        if !hasMeasured || next.sizeClass != metrics.sizeClass {
            hasMeasured = true
            debounceTask?.cancel()
            metrics = next
            return
        }

        debounceTask?.cancel()
        let delay = debounceNanoseconds
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.metrics = next
        }
    }
}

private struct WindowMetricsInjector: ViewModifier {
    @StateObject private var tracker = WindowMetricsTracker()

    func body(content: Content) -> some View {
        content
            .environment(\.windowMetrics, tracker.metrics)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { tracker.update(size: proxy.size) }
                        .onChange(of: proxy.size) { tracker.update(size: $0) }
                }
                .ignoresSafeArea()
            )
    }
}

extension View {
    /// Measures this view (use at the root of a window) and injects
    /// `\.windowMetrics` for everything inside it.
    func trackWindowMetrics() -> some View {
        modifier(WindowMetricsInjector())
    }
}
