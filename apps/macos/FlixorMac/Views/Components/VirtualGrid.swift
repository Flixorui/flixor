//
//  VirtualGrid.swift
//  FlixorMac
//
//  Virtual grid layout with lazy loading
//

import SwiftUI

struct VirtualGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    let content: (Item) -> Content

    init(
        items: [Item],
        columns: Int = 6,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.columns = columns
        self.spacing = spacing
        self.content = content
    }

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridItems, spacing: spacing) {
                ForEach(items) { item in
                    content(item)
                        .modifier(RaiseOnHoverModifier())
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Poster Grid (specialized for posters)

struct PosterGridView: View {
    let items: [MediaItem]
    var columns: Int = 6
    var spacing: CGFloat = 12
    var onItemTap: ((MediaItem) -> Void)?

    @State private var hoveredItemId: String?

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (CGFloat(columns + 1) * spacing) - 40 // padding
            let itemWidth = availableWidth / CGFloat(columns)

            VirtualGrid(
                items: items,
                columns: columns,
                spacing: spacing
            ) { item in
                PosterCard(
                    item: item,
                    width: itemWidth,
                    showProgress: item.viewOffset != nil && item.viewOffset! > 0,
                    onTap: {
                        onItemTap?(item)
                    }
                )
            }
        }
    }
}

// MARK: - Responsive Grid (adjusts columns based on width)

struct ResponsiveGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let minItemWidth: CGFloat
    let spacing: CGFloat
    let content: (Item) -> Content

    init(
        items: [Item],
        minItemWidth: CGFloat = 150,
        spacing: CGFloat = 12,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.minItemWidth = minItemWidth
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let columns = max(1, Int((geometry.size.width - 40) / (minItemWidth + spacing)))

            VirtualGrid(
                items: items,
                columns: columns,
                spacing: spacing,
                content: content
            )
        }
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview("Fixed Grid") {
    let sampleItems = (1...30).map { i in
        MediaItem(
            id: "\(i)",
            title: "Movie \(i)",
            type: "movie",
            thumb: "/library/metadata/\(i)/thumb/123456",
            art: nil,
            year: 2020 + (i % 5),
            rating: 7.0 + Double(i % 3),
            duration: 7200000,
            viewOffset: i % 3 == 0 ? 3600000 : nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil
        )
    }

    PosterGridView(items: sampleItems, columns: 6)
        .background(Color.black)
}

#Preview("Responsive Grid") {
    let sampleItems = (1...30).map { i in
        MediaItem(
            id: "\(i)",
            title: "Movie \(i)",
            type: "movie",
            thumb: "/library/metadata/\(i)/thumb/123456",
            art: nil,
            year: 2020 + (i % 5),
            rating: 7.0 + Double(i % 3),
            duration: 7200000,
            viewOffset: i % 3 == 0 ? 3600000 : nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil
        )
    }

    ResponsiveGrid(items: sampleItems, minItemWidth: 150) { item in
        PosterCard(item: item, width: 150, showProgress: item.viewOffset != nil)
    }
    .background(Color.black)
}
#endif
