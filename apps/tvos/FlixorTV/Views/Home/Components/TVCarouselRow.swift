import SwiftUI
import FlixorKit
import Nuke

enum TVRowCardKind { case poster, landscape }

struct TVCarouselRow: View {
    let title: String
    let items: [MediaItem]
    let kind: TVRowCardKind
    var focusNS: Namespace.ID? = nil
    var defaultFocus: Bool = false
    var preferredFocusItemId: String? = nil
    var sectionId: String = ""
    var onSelect: ((MediaItem) -> Void)? = nil

    @FocusState private var focusedID: String?
    @State private var expandedID: String?
    @State private var scrollProxy: ScrollViewProxy?

    private var posterSize: CGSize { .init(width: UX.posterWidth, height: UX.posterHeight) }
    private var landscapeSize: CGSize { .init(width: UX.landscapeWidth, height: UX.landscapeHeight) }
    private var expandedWidth: CGFloat { UX.posterHeight * (16.0/9.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, UX.gridH)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UX.itemSpacing) {
                        ForEach(items, id: \.id) { item in
                            let isExpanded = kind == .poster && expandedID == item.id
                            let itemHeight = kind == .poster ? posterSize.height : landscapeSize.height
                            let itemWidth = (kind == .poster) ? (isExpanded ? expandedWidth : posterSize.width) : landscapeSize.width
                            let hasExpanded = kind == .poster && expandedID != nil
                            let neighborScale: CGFloat = (hasExpanded && !isExpanded) ? UX.neighborScale : 1.0
                            let neighborOpacity: Double = (hasExpanded && !isExpanded) ? UX.dimNeighborOpacity : 1.0

                            // Stable focusable wrapper - never changes identity
                            ZStack {
                                if kind == .poster {
                                    TVPosterCard(item: item, isFocused: focusedID == item.id)
                                        .opacity(isExpanded ? 0 : 1)
                                        .animation(.easeOut(duration: 0.15), value: isExpanded)

                                    if isExpanded {
                                        TVLandscapeCard(
                                            item: item,
                                            showBadges: true,
                                            outlined: true,
                                            heightOverride: itemHeight,
                                            overrideURL: ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540)
                                        )
                                        .transition(.opacity)
                                    }
                                } else {
                                    TVLandscapeCard(item: item, showBadges: false, isFocused: focusedID == item.id)
                                }
                            }
                            .frame(width: itemWidth, height: itemHeight, alignment: .bottom)
                            .animation(.easeOut(duration: 0.18), value: itemWidth)
                            .id(item.id)
                            .focusable(true)
                            .focused($focusedID, equals: item.id)
                            .onTapGesture { onSelect?(item) }
                            .modifier(DefaultFocusModifier(
                                ns: focusNS,
                                enabled: defaultFocus && item.id == (preferredFocusItemId ?? items.first?.id)
                            ))
                            .scaleEffect(neighborScale, anchor: .bottom)
                            .opacity(neighborOpacity)
                            .animation(.easeOut(duration: 0.18), value: neighborScale)
                            .animation(.easeOut(duration: 0.18), value: neighborOpacity)
                        }
                    }
                    .padding(.horizontal, UX.gridH)
                    .frame(height: (kind == .poster ? posterSize.height : landscapeSize.height), alignment: .bottom)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: focusedID) { newValue in
                    guard kind == .poster else { return }

                    // Handle focus loss - collapse expansion
                    guard let id = newValue else {
                        withAnimation(.easeOut(duration: 0.2)) { expandedID = nil }
                        return
                    }

                    // Scroll to focused item - use center for first item to avoid hiding under padding
                    if let sp = scrollProxy {
                        let isFirstItem = id == items.first?.id
                        sp.scrollTo(id, anchor: isFirstItem ? .center : .leading)
                    }

                    // Expand the focused item (using stable ZStack overlay approach)
                    withAnimation(.easeOut(duration: 0.18)) {
                        expandedID = id
                    }

                    // Prefetch next items (±2) to keep scroll smooth
                    if let idx = items.firstIndex(where: { $0.id == id }) {
                        let window = items.dropFirst(max(0, idx-1)).prefix(4)
                        let urls: [URL] = window.compactMap { item in
                            if kind == .poster {
                                return ImageService.shared.thumbURL(for: item, width: 360, height: 540)
                            } else {
                                return ImageService.shared.continueWatchingURL(for: item, width: 960, height: 540)
                            }
                        }
                        prefetchImages(urls)
                    }
                }
            }
            .frame(height: max((kind == .poster ? posterSize.height : landscapeSize.height), 340), alignment: .bottom)
            .padding(.bottom, kind == .poster ? 40 : 24)
            .focusSection()
            // Publish row focus state upwards (used for vertical snap)
            .preference(key: RowFocusKey.self, value: focusedID != nil ? sectionId : nil)
            // Publish focused item ID upwards (used for remembering scroll position)
            .preference(key: RowItemFocusKey.self, value: RowItemFocusValue(rowId: focusedID != nil ? sectionId : nil, itemId: focusedID))
            .onChange(of: defaultFocus) { newValue in
                // When this row becomes the default focus target, FORCE focus to preferred item
                if newValue {
                    let targetItemId = preferredFocusItemId ?? items.first?.id
                    if let targetId = targetItemId {
                        // Reset focus immediately, even if tvOS already set it to another item
                        DispatchQueue.main.async {
                            if focusedID != targetId {
                                focusedID = targetId
                                print("🎯 [TVCarousel] Programmatically corrected focus from \(focusedID ?? "nil") to: \(targetId) in row: \(sectionId)")
                            }
                        }
                    }
                }
            }
        }
    }
}

// Preference to propagate which row currently holds focus
struct RowFocusKey: PreferenceKey {
    static var defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) {
        let next = nextValue()
        if let next { value = next }
    }
}

// Preference to propagate which specific item is focused in which row
struct RowItemFocusValue: Equatable {
    let rowId: String?
    let itemId: String?
}

struct RowItemFocusKey: PreferenceKey {
    static var defaultValue = RowItemFocusValue(rowId: nil, itemId: nil)
    static func reduce(value: inout RowItemFocusValue, nextValue: () -> RowItemFocusValue) {
        let next = nextValue()
        if next.rowId != nil { value = next }
    }
}

private struct DefaultFocusModifier: ViewModifier {
    let ns: Namespace.ID?
    let enabled: Bool
    func body(content: Content) -> some View {
        if let ns, enabled {
            content.prefersDefaultFocus(true, in: ns)
        } else {
            content
        }
    }
}

// Lightweight prefetch to avoid external cross-file dependency issues
private func prefetchImages(_ urls: [URL]) {
    let prefetcher = ImagePrefetcher(pipeline: ImagePipeline.shared)
    prefetcher.startPrefetching(with: urls)
    // We don't keep a strong reference intentionally – Nuke will fetch quickly
}
