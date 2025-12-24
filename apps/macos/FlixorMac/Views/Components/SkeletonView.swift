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

    @State private var shimmerOffset: CGFloat = -1.0

    init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { geometry in
            let actualWidth = width ?? geometry.size.width

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: actualWidth, height: height)
                .cornerRadius(cornerRadius)
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: actualWidth * 0.3)
                        .offset(x: shimmerOffset * actualWidth)
                        .cornerRadius(cornerRadius)
                )
                .clipped()
                .onAppear {
                    withAnimation(
                        Animation.linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                    ) {
                        shimmerOffset = 2.0
                    }
                }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Skeleton Card (Poster)

struct SkeletonPosterCard: View {
    let width: CGFloat

    private var height: CGFloat {
        width * 1.5 // 2:3 aspect ratio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonView(width: width, height: height, cornerRadius: 8)

            SkeletonView(width: width * 0.7, height: 14, cornerRadius: 4)
            SkeletonView(width: width * 0.4, height: 12, cornerRadius: 4)
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
        HStack(alignment: .top, spacing: 12) {
            SkeletonView(width: width, height: height, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonView(width: 200, height: 16, cornerRadius: 4)
                SkeletonView(width: 300, height: 12, cornerRadius: 4)
                SkeletonView(width: 250, height: 12, cornerRadius: 4)
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
        VStack(alignment: .leading, spacing: 12) {
            // Title skeleton
            SkeletonView(width: 200, height: 28, cornerRadius: 6)
                .padding(.horizontal, 20)

            // Cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(0..<itemCount, id: \.self) { _ in
                        switch cardType {
                        case .poster:
                            SkeletonPosterCard(width: itemWidth)
                        case .landscape:
                            SkeletonLandscapeCard(width: itemWidth)
                        }
                    }
                }
                .padding(.horizontal, 20)
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
        .padding(20)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 16) {
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
        .animation(.easeInOut(duration: 0.3), value: state)
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
    HStack(spacing: 12) {
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
