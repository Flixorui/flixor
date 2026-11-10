//
//  SearchRecentSearchesView.swift
//  FlixorMac
//
//  Recent searches shown above Trending when the search field is empty.
//

import SwiftUI

/// Shared layout values for the Search screen.
enum SearchLayout {
    /// Horizontal inset of the Search page. Matches the inset `CarouselRow`
    /// uses so the field, chips, grids and carousels line up.
    static let gutter: CGFloat = DS.Space.s20
    /// The search field is centred and stops growing past this width.
    static let fieldMaxWidth: CGFloat = 640
}

struct SearchRecentSearchesView: View {
    let searches: [String]
    let onSelect: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void

    @Environment(\.flixorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.itemGap) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.controlGap) {
                Text("Recent Searches")
                    .flixorFont(.title2)
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Button(action: onClear) {
                    Text("Clear")
                        .flixorFont(.callout, weight: .medium)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, DS.Space.s8)
                        .padding(.vertical, DS.Space.s4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear recent searches"))
            }

            SearchChipFlowLayout(spacing: DS.Space.controlGap) {
                ForEach(searches, id: \.self) { text in
                    RecentSearchChip(
                        text: text,
                        onSelect: { onSelect(text) },
                        onRemove: { onRemove(text) }
                    )
                }
            }
        }
        .padding(.horizontal, SearchLayout.gutter)
    }
}

// MARK: - Chip

private struct RecentSearchChip: View {
    let text: String
    let onSelect: () -> Void
    let onRemove: () -> Void

    @Environment(\.flixorTheme) private var theme
    @State private var isHovered = false
    @State private var isRemoveHovered = false

    var body: some View {
        HStack(spacing: DS.Space.s6) {
            Button(action: onSelect) {
                HStack(spacing: DS.Space.s6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.flixorIcon(DS.Icon.xs, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                    Text(text)
                        .flixorFont(.callout, weight: .medium)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Search for \(text)"))

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.flixor(.micro, weight: .bold))
                    .foregroundStyle(isRemoveHovered ? theme.textPrimary : theme.textTertiary)
                    .frame(width: DS.Space.s16, height: DS.Space.s16)
                    .background(
                        Circle().fill(isRemoveHovered ? theme.pressedFill : Color.clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isRemoveHovered = $0 }
            .help("Remove")
            .accessibilityLabel(Text("Remove \(text) from recent searches"))
        }
        .padding(.leading, DS.Space.s12)
        .padding(.trailing, DS.Space.s6)
        .padding(.vertical, DS.Space.s6)
        .background(
            Capsule(style: .continuous)
                .fill(isHovered ? theme.hoverFill : theme.surfaceOverlay)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(theme.separator, lineWidth: DS.Border.thin)
        )
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
    }
}

// MARK: - Flow layout

/// Wraps chips onto as many lines as needed (leading aligned).
struct SearchChipFlowLayout: Layout {
    var spacing: CGFloat = DS.Space.controlGap
    var lineSpacing: CGFloat = DS.Space.controlGap

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
