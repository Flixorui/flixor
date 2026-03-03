import SwiftUI
import FlixorKit

struct TVContinueWatchingRow: View {
    let items: [MediaItem]
    let kind: TVRowCardKind
    let focusNS: Namespace.ID
    let defaultFocus: Bool
    let preferredFocusItemId: String?
    let sectionId: String
    let onContinue: (MediaItem) -> Void
    let onRestart: (MediaItem) -> Void
    let onDetails: (MediaItem) -> Void
    let onRemove: (MediaItem) -> Void
    let onItemFocus: ((MediaItem) -> Void)?
    let previewTrailerProvider: ((MediaItem) async -> TVTrailer?)?
    let tailAction: TVRowTailAction?

    init(
        items: [MediaItem],
        kind: TVRowCardKind,
        focusNS: Namespace.ID,
        defaultFocus: Bool,
        preferredFocusItemId: String?,
        sectionId: String,
        onContinue: @escaping (MediaItem) -> Void,
        onRestart: @escaping (MediaItem) -> Void,
        onDetails: @escaping (MediaItem) -> Void,
        onRemove: @escaping (MediaItem) -> Void,
        onItemFocus: ((MediaItem) -> Void)? = nil,
        previewTrailerProvider: ((MediaItem) async -> TVTrailer?)? = nil,
        tailAction: TVRowTailAction? = nil
    ) {
        self.items = items
        self.kind = kind
        self.focusNS = focusNS
        self.defaultFocus = defaultFocus
        self.preferredFocusItemId = preferredFocusItemId
        self.sectionId = sectionId
        self.onContinue = onContinue
        self.onRestart = onRestart
        self.onDetails = onDetails
        self.onRemove = onRemove
        self.onItemFocus = onItemFocus
        self.previewTrailerProvider = previewTrailerProvider
        self.tailAction = tailAction
    }

    var body: some View {
        TVCarouselRow(
            title: "Continue Watching",
            items: items,
            kind: kind,
            focusNS: focusNS,
            defaultFocus: defaultFocus,
            preferredFocusItemId: preferredFocusItemId,
            sectionId: sectionId,
            landscapeFocusOutline: kind == .landscape,
            onSelect: onContinue,
            screenID: .home,
            tailAction: tailAction,
            menuActions: { item in
                [
                    TVRowMenuAction(
                        id: "continue-\(item.id)",
                        title: "Continue",
                        systemImage: "play.fill",
                        handler: { onContinue(item) }
                    ),
                    TVRowMenuAction(
                        id: "restart-\(item.id)",
                        title: "Start from Beginning",
                        systemImage: "backward.end.fill",
                        handler: { onRestart(item) }
                    ),
                    TVRowMenuAction(
                        id: "details-\(item.id)",
                        title: "Details",
                        systemImage: "info.circle",
                        handler: { onDetails(item) }
                    ),
                    TVRowMenuAction(
                        id: "remove-\(item.id)",
                        title: "Remove",
                        systemImage: "minus.circle",
                        role: .destructive,
                        handler: { onRemove(item) }
                    )
                ]
            },
            onItemFocus: onItemFocus,
            previewTrailerProvider: previewTrailerProvider
        )
    }
}
