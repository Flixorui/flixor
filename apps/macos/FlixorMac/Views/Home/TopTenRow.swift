//
//  TopTenRow.swift
//  FlixorMac
//
//  A Top 10 row (FlixPatrol or Streaming Availability): each poster with its
//  rank as a large outlined number beside it.
//

import SwiftUI

struct TopTenRow: View {
    let section: LibrarySection
    let onTap: (MediaItem) -> Void

    @ObservedObject private var profileSettings = ProfileSettings.shared
    @Environment(\.windowMetrics) private var metrics

    private var posterWidth: CGFloat {
        metrics.posterWidth(designWidth: 150, storedSize: profileSettings.posterSize)
    }
    private var numberWidth: CGFloat { posterWidth * 0.70 }
    /// "10" gets a wider column so it stands as tall as the single digits.
    private var wideNumberWidth: CGFloat { posterWidth * 1.10 }

    private func numberWidth(for rank: Int) -> CGFloat {
        rank >= 10 ? wideNumberWidth : numberWidth
    }

    private struct Ranked: Identifiable {
        let rank: Int
        let item: MediaItem
        var id: String { item.id }
    }

    var body: some View {
        let ranked = section.items.prefix(10).enumerated().map { Ranked(rank: $0.offset + 1, item: $0.element) }
        CarouselRow(
            title: section.title,
            items: ranked,
            itemWidth: numberWidth + posterWidth,
            spacing: DS.Space.s8,
            rowHeight: posterWidth * 1.5 + 20,
            widthForItem: { numberWidth(for: $0.rank) + posterWidth }
        ) { entry in
            HStack(alignment: .bottom, spacing: -numberWidth * 0.12) {
                TopTenNumber(rank: entry.rank, height: posterWidth * 1.5, width: numberWidth(for: entry.rank))
                    .zIndex(0)
                PosterCard(
                    item: entry.item,
                    width: posterWidth,
                    showTitle: false,
                    customImageURL: entry.item.thumb.flatMap(URL.init(string:)),
                    onTap: { onTap(entry.item) }
                )
                .zIndex(1)
            }
        }
    }

}

/// The rank as a tall outlined numeral (white outline, dark fill), sized so
/// it fits its column. "10" is drawn as two overlapping digits in a wider
/// column, so it stands about as tall as the single digits.
private struct TopTenNumber: View {
    let rank: Int
    let height: CGFloat
    let width: CGFloat

    /// How far each digit overlaps the one before it, as a share of the font size.
    private let digitOverlap: CGFloat = 0.16

    /// Space for the outline beyond the glyph's ink.
    private let outlineMargin: CGFloat = 3

    /// Measured on rounded black digits: from the right edge of the advance
    /// box to the left edge of the ink is at most 0.68 of the font size for
    /// one digit, and 1.05 for "1" + "0" with the overlap. Sizing by that
    /// keeps the left side of every digit inside the column.
    private var fontSize: CGFloat {
        let inkWidth: CGFloat = String(rank).count > 1 ? 1.05 : 0.68
        return min(height * 0.8, (width - outlineMargin) / inkWidth)
    }

    var body: some View {
        let font = Font.system(size: fontSize, weight: .black, design: .rounded)
        let digits = String(rank).map(String.init)
        let glyphs = HStack(spacing: -fontSize * digitOverlap) {
            ForEach(digits.indices, id: \.self) { Text(digits[$0]) }
        }
        ZStack {
            // Outline: the numeral drawn slightly offset in eight directions.
            // All outlines go under all fills, so overlapping digits merge.
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * .pi / 4
                glyphs
                    .foregroundStyle(Color.white.opacity(0.75))
                    .offset(x: cos(angle) * 1.5, y: sin(angle) * 1.5)
            }
            glyphs
                .foregroundStyle(Color(white: 0.05))
        }
        .font(font)
        .lineLimit(1)
        .fixedSize()
        .frame(width: width, height: height, alignment: .bottomTrailing)
        .offset(y: fontSize * 0.1)
        // Never spill onto the previous poster.
        .clipped()
        .accessibilityLabel(Text("Number \(rank)"))
    }
}
