//
//  DetailsHeroSkeleton.swift
//  FlixorMac
//
//  Shimmering placeholder of the details hero (backdrop wash, logo/title block,
//  metadata lines, action buttons) shown while the title's metadata loads.
//

import SwiftUI

struct DetailsHeroSkeleton: View {
    let layout: DetailsLayoutMetrics

    @Environment(\.flixorTheme) private var theme

    private var logoBlockWidth: CGFloat {
        min(layout.width * 0.32, 420)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s32) {
            hero
            rowPlaceholder
                .padding(.horizontal, layout.contentPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading details")
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop stand-in: a soft surface wash with the same fades the real hero uses.
            ZStack {
                LinearGradient(
                    colors: [theme.surfaceElevated, theme.surface, theme.background],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                LinearGradient(
                    colors: [theme.scrim(DS.Opacity.scrimHeavy), theme.scrim(DS.Opacity.scrimLight), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [.clear, theme.scrim(DS.Opacity.scrimMedium)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: DS.Space.s16) {
                Spacer(minLength: 0)

                // Logo / title block
                block(width: logoBlockWidth, height: logoBlockWidth * 0.28, radius: DS.Radius.compactCard)

                // Type · genres · rating row
                HStack(spacing: DS.Space.s8) {
                    block(width: 64, height: 12)
                    block(width: 96, height: 12)
                    block(width: 72, height: 12)
                    block(width: 32, height: 16, radius: DS.Radius.badge)
                }

                // Overview (two lines)
                VStack(alignment: .leading, spacing: DS.Space.s8) {
                    block(width: min(layout.heroTextMaxWidth, 560), height: 12)
                    block(width: min(layout.heroTextMaxWidth, 560) * 0.72, height: 12)
                }

                // Technical metadata row
                HStack(spacing: DS.Space.s10) {
                    block(width: 44, height: 12)
                    block(width: 52, height: 12)
                    block(width: 36, height: 16, radius: DS.Radius.badge)
                    block(width: 56, height: 12)
                }

                // Action buttons
                HStack(spacing: DS.Space.s16) {
                    block(width: 128, height: 44, radius: DS.Radius.button)
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(placeholderFill)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .padding(.leading, layout.heroHorizontalPadding)
            .padding(.trailing, layout.heroHorizontalPadding)
            .padding(.top, layout.heroTopPadding)
            .padding(.bottom, layout.heroBottomPadding)
            .detailsShimmer()
        }
        .frame(maxWidth: .infinity, minHeight: layout.heroHeight, maxHeight: layout.heroHeight)
        .clipped()
    }

    private var rowPlaceholder: some View {
        VStack(alignment: .leading, spacing: DS.Space.s12) {
            block(width: 160, height: 14)
            HStack(spacing: DS.Space.itemGap) {
                ForEach(0..<6, id: \.self) { _ in
                    block(width: 240, height: 135, radius: DS.Radius.card)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .detailsShimmer()
    }

    // MARK: - Pieces

    private var placeholderFill: Color {
        Color.white.opacity(DS.Opacity.pressed)
    }

    private func block(width: CGFloat, height: CGFloat, radius: CGFloat = DS.Radius.r4) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(placeholderFill)
            .frame(width: width, height: height)
    }
}

// MARK: - Shimmer

/// Sweeps a soft highlight across the placeholder shapes it is applied to.
/// Static (no sweep) when Reduce Motion is on.
private struct DetailsShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.5

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(DS.Opacity.selected), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: phase * geo.size.width)
                }
                .mask(content)
                .opacity(reduceMotion ? 0 : 1)
                .allowsHitTesting(false)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.1
                }
            }
    }
}

extension View {
    /// Shimmer highlight for skeleton placeholders (respects Reduce Motion).
    func detailsShimmer() -> some View {
        modifier(DetailsShimmerModifier())
    }
}
