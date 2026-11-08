//
//  CarouselView.swift
//  FlixorMac
//
//  Horizontal scrolling carousel component
//

import SwiftUI

struct CarouselView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    let spacing: CGFloat
    let rowHeight: CGFloat?
    let content: (Item) -> Content

    @State private var currentIndex: Int = 0
    @State private var isHovered = false
    @State private var showLeftArrow = false
    @State private var showRightArrow = true
    @State private var scrollProxy: ScrollViewProxy?

    init(
        items: [Item],
        itemWidth: CGFloat = 150,
        spacing: CGFloat = 12,
        rowHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.itemWidth = itemWidth
        self.spacing = spacing
        self.rowHeight = rowHeight
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: spacing) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                content(item)
                                    .frame(width: itemWidth)
                                    .id(index)
                                    .background(
                                        GeometryReader { itemGeometry in
                                            Color.clear
                                                .preference(
                                                    key: FirstVisiblePreferenceKey.self,
                                                    value: FirstVisibleItem(
                                                        index: index,
                                                        minX: itemGeometry.frame(in: .named("scrollView")).minX
                                                    )
                                                )
                                        }
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .coordinateSpace(name: "scrollView")
                    .onPreferenceChange(FirstVisiblePreferenceKey.self) { firstVisible in
                        // Update current index based on the leftmost visible item
                        // This ensures manual scrolling updates the index
                        currentIndex = firstVisible.index
                        updateArrows(viewWidth: geometry.size.width)
                    }
                    .onAppear {
                        scrollProxy = proxy
                        updateArrows(viewWidth: geometry.size.width)
                    }
                }

                // Navigation arrows overlaid on top
                if isHovered && (showLeftArrow || showRightArrow) {
                    HStack(spacing: 0) {
                        // Left arrow
                        if showLeftArrow {
                            navButton(direction: .left, geometry: geometry)
                                .padding(.leading, 8)
                        } else {
                            Color.clear.frame(width: 60, height: 44)
                        }

                        Spacer()

                        // Right arrow
                        if showRightArrow {
                            navButton(direction: .right, geometry: geometry)
                                .padding(.trailing, 8)
                        } else {
                            Color.clear.frame(width: 60, height: 44)
                        }
                    }
                    .allowsHitTesting(true)
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }

    private func navButton(direction: ScrollDirection, geometry: GeometryProxy) -> some View {
        Button(action: {
            scroll(direction: direction, geometry: geometry)
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )

                Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }

    private func scroll(direction: ScrollDirection, geometry: GeometryProxy) {
        guard let proxy = scrollProxy else { return }

        let visibleWidth = geometry.size.width - 40 // Account for padding
        let itemsPerPage = max(1, Int(visibleWidth / (itemWidth + spacing)))

        // Calculate target index based on current index
        let targetIndex: Int
        if direction == .left {
            // Scroll back by one page
            targetIndex = max(0, currentIndex - itemsPerPage)
        } else {
            // Scroll forward by one page
            // Make sure we don't scroll past the last item that would fill the screen
            let maxStartIndex = max(0, items.count - itemsPerPage)
            targetIndex = min(maxStartIndex, currentIndex + itemsPerPage)
        }

        // Don't update currentIndex here - let the preference change handle it
        // This ensures consistency between manual scrolling and arrow navigation

        // Scroll to target with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(targetIndex, anchor: .leading)
        }
    }

    private func updateArrows(viewWidth: CGFloat) {
        // Left arrow shows when not at the start
        showLeftArrow = currentIndex > 0

        // Right arrow shows when there's more content to the right
        // Calculate how many items can fit in one view
        let visibleWidth = viewWidth - 40
        let itemsPerView = Int(visibleWidth / (itemWidth + spacing))

        showRightArrow = currentIndex + itemsPerView < items.count
    }

    enum ScrollDirection {
        case left, right
    }
}

// MARK: - First Visible Item Preference Key

struct FirstVisibleItem: Equatable {
    let index: Int
    let minX: CGFloat
}

struct FirstVisiblePreferenceKey: PreferenceKey {
    static var defaultValue = FirstVisibleItem(index: 0, minX: 0)

    static func reduce(value: inout FirstVisibleItem, nextValue: () -> FirstVisibleItem) {
        let next = nextValue()
        // Keep the item that's closest to position 20 (left edge after padding)
        // Items to the left of the viewport have minX < 0
        // Items visible have minX around 20
        // Items to the right have minX > viewport width

        // If current value is far left (< 10) and next is closer to visible area, use next
        if value.minX < 10 && next.minX >= 10 {
            value = next
        }
        // If next is closer to the left edge (around 20), use it
        else if next.minX >= 10 && next.minX < value.minX {
            value = next
        }
        // If both are in visible range, use the one with lower index (leftmost item)
        else if value.minX >= 10 && next.minX >= 10 && next.index < value.index {
            value = next
        }
    }
}

// MARK: - Carousel Row (with title)

struct CarouselRow<Item: Identifiable, Content: View>: View {
    let title: String
    let items: [Item]
    let itemWidth: CGFloat
    let spacing: CGFloat
    let rowHeight: CGFloat?
    let content: (Item) -> Content
    let browseAction: (() -> Void)?
    let browseLabel: String

    @State private var isHeaderHovered = false
    @FocusState private var browseFocused: Bool
    @Environment(\.rowTitleCaption) private var titleCaption

    init(
        title: String,
        items: [Item],
        itemWidth: CGFloat = 150,
        spacing: CGFloat = 12,
        rowHeight: CGFloat? = nil,
        browseAction: (() -> Void)? = nil,
        browseLabel: String = "Browse",
        @ViewBuilder content: @escaping (Item) -> Content,
    ) {
        self.title = title
        self.items = items
        self.itemWidth = itemWidth
        self.spacing = spacing
        self.rowHeight = rowHeight
        self.content = content
        self.browseAction = browseAction
        self.browseLabel = browseLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)

                if let titleCaption {
                    RowTitleCaptionText(caption: titleCaption)
                }

                if let browseAction {
                    Button(action: browseAction) {
                        HStack(spacing: 4) {
                            Text(browseLabel)
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(isHeaderHovered || browseFocused ? 0.12 : 0))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHeaderHovered || browseFocused ? 1 : 0)
                    .offset(x: isHeaderHovered || browseFocused ? 4 : 0)
                    .animation(.easeOut(duration: 0.24), value: isHeaderHovered)
                    .animation(.easeOut(duration: 0.24), value: browseFocused)
                    .allowsHitTesting(isHeaderHovered || browseFocused)
                    .focusable(true)
                    .focused($browseFocused)
                    .accessibilityLabel(Text("\(browseLabel) \(title)"))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .onHover { hovering in
                updateHoverState(hovering: hovering)
            }
            .contentShape(Rectangle())

            // Carousel
            CarouselView(
                items: items,
                itemWidth: itemWidth,
                spacing: spacing,
                rowHeight: rowHeight,
                content: content
            )
            .frame(height: rowHeight ?? (itemWidth * 1.8)) // Approximate fallback for poster cards
        }
    }

    private func updateHoverState(hovering: Bool) {
        withAnimation(.easeOut(duration: 0.2)) {
            isHeaderHovered = hovering
            if !hovering && !browseFocused {
                // keep button visible when focused via keyboard
                isHeaderHovered = false
            }
        }
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    let sampleItems = (1...10).map { i in
        MediaItem(
            id: "\(i)",
            title: "Movie \(i)",
            type: "movie",
            thumb: "/library/metadata/\(i)/thumb/123456",
            art: nil,
            year: 2020 + i,
            rating: 8.0,
            duration: 7200000,
            viewOffset: nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil
        )
    }

    VStack(spacing: 40) {
        CarouselRow(
            title: "Popular Movies",
            items: sampleItems,
            itemWidth: 150
        ) { item in
            PosterCard(item: item, width: 150)
        }

        CarouselRow(
            title: "Continue Watching",
            items: Array(sampleItems.prefix(5)),
            itemWidth: 350,
            spacing: 16,
            rowHeight: (350 * 0.5) + 80 // approx backdrop + text
        ) { item in
            LandscapeCard(item: item, width: 350, showProgressBar: true)
        }
    }
    .padding(.vertical)
    .background(Color.black)
}
#endif
