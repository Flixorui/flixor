//
//  ContinueWatchingMenu.swift
//  FlixorMac
//
//  Actions for a Continue Watching card, shared by the "…" button and the
//  right-click context menu of every Continue Watching card style.
//

import SwiftUI

/// Called with the chosen action and the card's item.
typealias ContinueWatchingActionHandler = (ContinueWatchingAction, MediaItem) -> Void

/// Menu items: Resume, Start Over | Mark as Watched, Remove | Go to Details.
/// Watch-state actions are disabled while one is in flight for the item, and
/// for items that are not a real movie or episode.
struct ContinueWatchingMenuItems: View {
    let item: MediaItem
    var isBusy: Bool = false
    let onAction: ContinueWatchingActionHandler

    var body: some View {
        button(.resume)
        button(.startOver)
        Divider()
        button(.markWatched)
        button(.remove)
        Divider()
        button(.details)
    }

    private func button(_ action: ContinueWatchingAction) -> some View {
        Button {
            onAction(action, item)
        } label: {
            Label(action.title, systemImage: action.iconName)
        }
        .disabled(action.changesWatchState && (isBusy || !item.supportsContinueWatchingStateActions))
    }
}

/// The "…" button on a Continue Watching card. 28 x 28 pt hit target.
struct ContinueWatchingMoreButton: View {
    let item: MediaItem
    var isBusy: Bool = false
    let onAction: ContinueWatchingActionHandler

    @State private var isHovered = false

    private var titleForAccessibility: String {
        item.type == "episode" ? (item.grandparentTitle ?? item.title) : item.title
    }

    var body: some View {
        Menu {
            ContinueWatchingMenuItems(item: item, isBusy: isBusy, onAction: onAction)
        } label: {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.flixorIcon(DS.Icon.sm, weight: .semibold))
                }
            }
            .foregroundStyle(.white.opacity(isHovered ? DS.Opacity.visible : DS.Opacity.strong))
            .frame(width: 28, height: 28)
            .background(
                Circle().fill(Color.white.opacity(isHovered ? DS.Opacity.pressed : 0))
            )
            .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(DS.Motion.quick) { isHovered = hovering }
        }
        .help("More actions")
        .accessibilityLabel(Text("More actions for \(titleForAccessibility)"))
    }
}

extension View {
    /// Adds the Continue Watching right-click menu to a card.
    func continueWatchingContextMenu(
        item: MediaItem,
        isBusy: Bool,
        onAction: ContinueWatchingActionHandler?
    ) -> some View {
        contextMenu {
            if let onAction {
                ContinueWatchingMenuItems(item: item, isBusy: isBusy, onAction: onAction)
            }
        }
    }
}
