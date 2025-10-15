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
    var sectionId: String = ""

    @FocusState private var focusedID: String?
    @State private var expandedID: String?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var lastHandledFocusId: String?

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

                            Group {
                                if kind == .poster && isExpanded {
                                    TVLandscapeCard(
                                        item: item,
                                        showBadges: true,
                                        outlined: true,
                                        heightOverride: itemHeight,
                                        overrideURL: ImageService.shared.artURL(for: item, width: 960, height: 540)
                                    )
                                } else if kind == .poster {
                                    TVPosterCard(item: item, isFocused: focusedID == item.id)
                                } else {
                                    TVLandscapeCard(item: item, showBadges: false, isFocused: focusedID == item.id)
                                }
                            }
                            .frame(width: itemWidth, height: itemHeight, alignment: .bottom)
                            .id(item.id)
                            .focusable(true)
                            .focused($focusedID, equals: item.id)
                            .modifier(DefaultFocusModifier(ns: focusNS, enabled: defaultFocus && item.id == items.first?.id))
                            .scaleEffect(neighborScale, anchor: .bottom)
                            .opacity(neighborOpacity)
                            .animation(.easeOut(duration: 0.25), value: expandedID)
                        }
                    }
                    .padding(.horizontal, UX.gridH)
                    .frame(height: (kind == .poster ? posterSize.height : landscapeSize.height), alignment: .bottom)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: focusedID) { newValue in
                    guard kind == .poster else { return }
                    guard let id = newValue else {
                        withAnimation(.easeOut(duration: 0.2)) { expandedID = nil }
                        return
                    }
                    if lastHandledFocusId == id { return }
                    lastHandledFocusId = id
                    if let sp = scrollProxy { withAnimation(nil) { sp.scrollTo(id, anchor: .leading) } }
                    withAnimation(.easeOut(duration: 0.25)) { expandedID = id }

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
