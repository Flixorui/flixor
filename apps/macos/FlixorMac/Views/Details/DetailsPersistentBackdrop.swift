//
//  DetailsPersistentBackdrop.swift
//  FlixorMac
//
//  The title's artwork stays fixed behind the whole details page, and a tint
//  taken from it fades in as the page scrolls.
//

import SwiftUI

/// Scroll position as 0...1 (art clear ... fully tinted). Published in small
/// steps and observed only by the tint layer, so scrolling doesn't re-render the page.
final class DetailsBackdropScroll: ObservableObject {
    @Published private(set) var progress: CGFloat = 0

    private let fadeHeroFraction: CGFloat = 0.75
    private let steps: CGFloat = 50

    func update(scrollOffset: CGFloat, heroHeight: CGFloat) {
        guard heroHeight > 0 else { return }
        let raw = min(max(scrollOffset / (heroHeight * fadeHeroFraction), 0), 1)
        let stepped = (raw * steps).rounded() / steps
        if stepped != progress { progress = stepped }
    }

    func reset() {
        if progress != 0 { progress = 0 }
    }
}

struct DetailsPersistentBackdrop: View {
    let imageURL: URL?
    let scroll: DetailsBackdropScroll
    let heroTrailer: DetailsHeroTrailerController

    @Environment(\.flixorTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dominant: BackdropRGB?

    /// How much of the art the tint covers once the page has scrolled.
    private var maxTintAlpha: Double { theme.pureBlack ? 1 : 0.86 }

    private var tint: Color {
        if theme.pureBlack { return .black }
        guard let dominant, let background = BackdropRGB(theme.background) else { return theme.background }
        return dominant.pageTint(over: background).color
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                tint

                CachedAsyncImage(url: imageURL, contentMode: .fill) {
                    Color.clear
                }
                .frame(width: size.width, height: size.height)
                .clipped()

                DetailsHeroTrailerLayer(controller: heroTrailer, size: coverSize(for: size))
                    .frame(width: size.width, height: size.height)
                    .clipped()

                readabilityFades(size: size)

                DetailsBackdropTintLayer(
                    scroll: scroll,
                    tint: tint,
                    maxAlpha: maxTintAlpha,
                    heroHeight: DetailsLayoutMetrics(width: max(size.width, 640)).heroHeight,
                    windowHeight: size.height
                )
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.32), value: dominant)
        .task(id: imageURL) {
            guard let imageURL else {
                dominant = nil
                return
            }
            let color = await BackdropColorExtractor.dominantColor(for: imageURL)
            guard !Task.isCancelled else { return }
            dominant = color
        }
    }

    /// Smallest 16:9 box covering the window, so the trailer never letterboxes.
    private func coverSize(for size: CGSize) -> CGSize {
        let height = max(size.height, size.width * 9 / 16)
        return CGSize(width: max(size.width, height * 16 / 9), height: height)
    }

    @ViewBuilder
    private func readabilityFades(size: CGSize) -> some View {
        // Top, for navigation
        LinearGradient(
            colors: [Color.black.opacity(0.6), Color.black.opacity(0.1), .clear],
            startPoint: .top,
            endPoint: .center
        )

        // Bottom-left corner, for the hero text (Apple TV style): the rest of
        // the picture stays clear for the trailer.
        RadialGradient(
            colors: [
                Color.black.opacity(0.85),
                Color.black.opacity(0.6),
                Color.black.opacity(0.25),
                .clear
            ],
            center: .bottomLeading,
            startRadius: 0,
            endRadius: max(size.width * 0.72, size.height)
        )

        // Bottom edge, for the credits on the right
        LinearGradient(
            colors: [Color.black.opacity(0.55), .clear],
            startPoint: .bottom,
            endPoint: UnitPoint(x: 0.5, y: 0.7)
        )
    }
}

/// Below the hero the tint is always full; over the hero it follows the scroll.
private struct DetailsBackdropTintLayer: View {
    @ObservedObject var scroll: DetailsBackdropScroll
    let tint: Color
    let maxAlpha: Double
    let heroHeight: CGFloat
    let windowHeight: CGFloat

    var body: some View {
        let topAlpha = Double(scroll.progress) * maxAlpha
        let fadeEnd = windowHeight > 0 ? min(heroHeight / windowHeight, 1) : 1
        let fadeStart = fadeEnd * 0.55
        LinearGradient(
            stops: [
                .init(color: tint.opacity(topAlpha), location: 0),
                .init(color: tint.opacity(topAlpha), location: fadeStart),
                .init(color: tint.opacity(maxAlpha), location: fadeEnd),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
