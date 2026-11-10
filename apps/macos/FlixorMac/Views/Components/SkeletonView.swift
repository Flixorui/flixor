//
//  SkeletonView.swift
//  FlixorMac
//
//  Loading skeleton components with shimmer animation
//

import SwiftUI

struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay {
                if !reduceMotion {
                    SkeletonShimmer()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// A soft highlight sweeping left to right. Its position comes from the clock
/// and the view's place in the window, so every placeholder on screen shares
/// one sweep that travels across the whole row (no per-view animation state,
/// which lazy rows reset and left as a stuck stripe in the middle).
private struct SkeletonShimmer: View {
    /// Seconds for one sweep across the window, plus a short pause.
    private static let period: Double = 1.8
    /// Distance the sweep travels (wider than any window, so it starts and ends off screen).
    private static let travel: CGFloat = 3200
    private static let bandWidth: CGFloat = 360

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = CGFloat(t.truncatingRemainder(dividingBy: Self.period) / Self.period)
                // Band centre in window coordinates, then relative to this view.
                let center = -Self.bandWidth + phase * (Self.travel + Self.bandWidth * 2)
                let x = center - frame.minX
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.09), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.bandWidth, height: proxy.size.height)
                .offset(x: x - Self.bandWidth / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Skeleton Card (Poster)

struct SkeletonPosterCard: View {
    let width: CGFloat

    private var height: CGFloat {
        width * 1.5 // 2:3 aspect ratio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s8) {
            SkeletonView(width: width, height: height, cornerRadius: DS.Radius.r8)

            SkeletonView(width: width * 0.7, height: 14, cornerRadius: DS.Radius.r4)
            SkeletonView(width: width * 0.4, height: 12, cornerRadius: DS.Radius.r4)
        }
    }
}

// MARK: - Skeleton Card (Landscape)

struct SkeletonLandscapeCard: View {
    let width: CGFloat

    private var height: CGFloat {
        width * 0.5625 // 16:9 aspect ratio
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s12) {
            SkeletonView(width: width, height: height, cornerRadius: DS.Radius.r8)

            VStack(alignment: .leading, spacing: DS.Space.s8) {
                SkeletonView(width: 200, height: 16, cornerRadius: DS.Radius.r4)
                SkeletonView(width: 300, height: 12, cornerRadius: DS.Radius.r4)
                SkeletonView(width: 250, height: 12, cornerRadius: DS.Radius.r4)
            }
        }
    }
}

// MARK: - Skeleton Row

struct SkeletonCarouselRow: View {
    let itemWidth: CGFloat
    let itemCount: Int
    let cardType: CardType

    enum CardType {
        case poster
        case landscape
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            // Title skeleton
            SkeletonView(width: 200, height: 28, cornerRadius: DS.Radius.r6)
                .padding(.horizontal, DS.Space.s20)

            // Cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DS.Space.s12) {
                    ForEach(0..<itemCount, id: \.self) { _ in
                        switch cardType {
                        case .poster:
                            SkeletonPosterCard(width: itemWidth)
                        case .landscape:
                            SkeletonLandscapeCard(width: itemWidth)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s20)
            }
        }
    }
}

// MARK: - Skeleton Grid

struct SkeletonGrid: View {
    let columns: Int
    let rows: Int
    let itemWidth: CGFloat

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns),
            spacing: 12
        ) {
            ForEach(0..<(columns * rows), id: \.self) { _ in
                SkeletonPosterCard(width: itemWidth)
            }
        }
        .padding(DS.Space.s20)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var message: String = String(localized: "Loading...")

    var body: some View {
        VStack(spacing: DS.Space.s16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.5))
    }
}

// MARK: - Section Container (Modular Skeleton Support)

/// A container that shows skeleton while loading and smoothly transitions to content
/// Uses fixed height to prevent layout shift/jutter during loading
struct SectionContainer<Content: View, Skeleton: View>: View {
    let state: SectionLoadState
    let expectedHeight: CGFloat?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let skeleton: () -> Skeleton

    init(
        state: SectionLoadState,
        expectedHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder skeleton: @escaping () -> Skeleton
    ) {
        self.state = state
        self.expectedHeight = expectedHeight
        self.content = content
        self.skeleton = skeleton
    }

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                skeleton()
            case .loaded:
                content()
                    .transition(.opacity)
            case .empty:
                EmptyView()
            case .error:
                // Could show error state, but for rows we just hide
                EmptyView()
            }
        }
        .frame(height: expectedHeight)
        .animation(DS.Motion.emphasized, value: state)
    }
}

// MARK: - Row Heights Constants

enum RowHeights {
    static let landscape: CGFloat = (420 * 0.5625) + 56 + 40 // card + title + padding
    static let poster: CGFloat = (150 * 1.5) + 56 + 40 // card + title + padding
    static let hero: CGFloat = 600
}

#if DEBUG && canImport(PreviewsMacros)
#Preview("Skeleton Poster") {
    HStack(spacing: DS.Space.s12) {
        SkeletonPosterCard(width: 150)
        SkeletonPosterCard(width: 150)
        SkeletonPosterCard(width: 150)
    }
    .padding()
    .background(Color.black)
}

#Preview("Skeleton Row") {
    SkeletonCarouselRow(itemWidth: 150, itemCount: 8, cardType: .poster)
        .background(Color.black)
}

#Preview("Skeleton Grid") {
    SkeletonGrid(columns: 6, rows: 3, itemWidth: 150)
        .background(Color.black)
}

#Preview("Loading View") {
    LoadingView(message: "Loading your library...")
}
#endif
