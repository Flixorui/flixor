//
//  TopTenRow.swift
//  FlixorMac
//
//  A Streaming Availability Top 10 row: each poster with its rank as a large
//  outlined number beside it. Right-click a poster to open it on the service.
//

import SwiftUI
import AppKit

struct TopTenRow: View {
    let section: LibrarySection
    let onTap: (MediaItem) -> Void

    @ObservedObject private var profileSettings = ProfileSettings.shared
    @Environment(\.windowMetrics) private var metrics

    private var posterWidth: CGFloat {
        metrics.posterWidth(designWidth: 150, storedSize: profileSettings.posterSize)
    }
    private var numberWidth: CGFloat { posterWidth * 0.62 }

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
            rowHeight: posterWidth * 1.5 + 20
        ) { entry in
            HStack(alignment: .bottom, spacing: -numberWidth * 0.12) {
                TopTenNumber(rank: entry.rank, height: posterWidth * 1.5, width: numberWidth)
                    .zIndex(0)
                PosterCard(
                    item: entry.item,
                    width: posterWidth,
                    showTitle: false,
                    customImageURL: entry.item.thumb.flatMap(URL.init(string:)),
                    extraMenuActions: menuActions(for: entry.item),
                    onTap: { onTap(entry.item) }
                )
                .zIndex(1)
            }
        }
    }

    private func menuActions(for item: MediaItem) -> [CardMenuAction] {
        guard let link = StreamingAvailabilityStore.shared.links[item.id] else { return [] }
        return [CardMenuAction(title: String(localized: "Open in \(link.service.displayName)")) {
            NSWorkspace.shared.open(link.url)
        }]
    }
}

/// The rank as a tall outlined numeral (white outline, dark fill), sized so
/// it always fits its column: single digits by height, "10" by width.
private struct TopTenNumber: View {
    let rank: Int
    let height: CGFloat
    let width: CGFloat

    /// Rounded black digits are about 0.62 of the font size wide.
    private var fontSize: CGFloat {
        let digits = CGFloat(String(rank).count)
        let byWidth = width / (0.62 * digits - (digits > 1 ? 0.12 : 0))
        return min(height * 0.8, byWidth)
    }

    var body: some View {
        let font = Font.system(size: fontSize, weight: .black, design: .rounded)
        ZStack {
            // Outline: the numeral drawn slightly offset in eight directions.
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * .pi / 4
                Text("\(rank)")
                    .font(font)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .offset(x: cos(angle) * 1.5, y: sin(angle) * 1.5)
            }
            Text("\(rank)")
                .font(font)
                .foregroundStyle(Color(white: 0.05))
        }
        .kerning(rank >= 10 ? -fontSize * 0.12 : 0)
        .lineLimit(1)
        .fixedSize()
        .frame(width: width, height: height, alignment: .bottomTrailing)
        .offset(y: fontSize * 0.1)
        // Never spill onto the previous poster.
        .clipped()
        .accessibilityLabel(Text("Number \(rank)"))
    }
}
