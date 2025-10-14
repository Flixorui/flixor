import SwiftUI
import FlixorKit

enum TVRowCardKind { case poster, landscape }

struct TVCarouselRow: View {
    let title: String
    let items: [MediaItem]
    let kind: TVRowCardKind
    var focusNS: Namespace.ID? = nil
    var defaultFocus: Bool = false

    @Namespace private var ns
    @FocusState private var focusedID: String?
    @State private var expanded: MediaItem?

    private var itemSize: CGSize {
        switch kind {
        case .poster: return CGSize(width: 180, height: 270)
        case .landscape: return CGSize(width: 560, height: 315) // 16:9
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)

            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(items, id: \.id) { item in
                            let isFirst = item.id == items.first?.id
                            let base = card(for: item)
                                .frame(width: itemSize.width, height: itemSize.height)
                                .focusable(true)
                                .focused($focusedID, equals: item.id)
                                .onChange(of: focusedID) { newValue in
                                    if newValue == item.id { expanded = item }
                                }

                            if let ns = focusNS, defaultFocus && isFirst {
                                base.prefersDefaultFocus(true, in: ns)
                            } else {
                                base
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }

                if let expanded, kind == .poster {
                    TVExpandedPreviewCard(item: expanded)
                        .matchedGeometryEffect(id: "card-\(expanded.id)", in: ns)
                        .frame(width: 800)
                        .offset(x: 40, y: -330)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: max(itemSize.height, 340))
            .padding(.bottom, kind == .poster ? 40 : 16)
            .focusSection()
        }
    }

    @ViewBuilder
    private func card(for item: MediaItem) -> some View {
        let focused = focusedID == item.id
        switch kind {
        case .poster:
            TVPosterCard(item: item, isFocused: focused)
                .matchedGeometryEffect(id: "card-\(item.id)", in: ns, isSource: true)
        case .landscape:
            TVLandscapeCard(item: item, showBadges: false)
                .scaleEffect(focused ? 1.04 : 1.0)
                .animation(.easeOut(duration: 0.18), value: focused)
        }
    }
}
