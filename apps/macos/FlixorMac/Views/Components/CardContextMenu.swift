//
//  CardContextMenu.swift
//  FlixorMac
//
//  Right-click menu for poster and landscape cards. Use it through
//  `.cardContextMenu(item:onOpen:)` (or `.cardInteractions(...)`, which adds it
//  together with hover scale and the hover preview).
//
//  Items: Open Details, Play (Plex movies/episodes only), Add to / Remove from
//  My List (movies and shows), Mark as Watched / Unwatched (movies and episodes;
//  shows and seasons get a confirmed "entire show/season" action), and an
//  "Add to Trakt List" submenu when Trakt is connected.
//

import SwiftUI
import FlixorKit

struct CardContextMenu: View {
    let item: MediaItem
    let onOpen: (() -> Void)?
    let onPlay: (() -> Void)?
    let watchlistController: WatchlistController?
    /// Called for shows/seasons with `true` (watched) or `false` (unwatched);
    /// the host asks for confirmation before acting.
    let onRequestWholeShowWatched: (Bool) -> Void

    @ObservedObject private var traktLists = CardTraktListsCache.shared

    var body: some View {
        if let onOpen {
            Button {
                onOpen()
            } label: {
                Label("Open Details", systemImage: "info.circle")
            }
        }

        if let onPlay {
            Button {
                onPlay()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
        }

        Divider()

        if CardActions.supportsWatchlist(item) {
            let inList = CardActions.isInWatchlist(item, controller: watchlistController)
            Button {
                let item = item
                let controller = watchlistController
                Task { await CardActions.toggleWatchlist(item, controller: controller) }
            } label: {
                if inList {
                    Label("Remove from My List", systemImage: "minus.circle")
                } else {
                    Label("Add to My List", systemImage: "plus.circle")
                }
            }
        }

        if CardActions.isWholeShowLike(item) {
            let noun = item.type.lowercased() == "season" ? "Season" : "Show"
            Button {
                onRequestWholeShowWatched(true)
            } label: {
                Label("Mark Entire \(noun) as Watched…", systemImage: "checkmark.circle")
            }
            Button {
                onRequestWholeShowWatched(false)
            } label: {
                Label("Mark Entire \(noun) as Unwatched…", systemImage: "circle")
            }
        } else if WatchStateTarget(item: item) != nil {
            Button {
                let item = item
                Task { await CardActions.setWatched(item, watched: true) }
            } label: {
                Label("Mark as Watched", systemImage: "checkmark.circle")
            }
            Button {
                let item = item
                Task { await CardActions.setWatched(item, watched: false) }
            } label: {
                Label("Mark as Unwatched", systemImage: "circle")
            }
        }

        if traktLists.isAvailable {
            Divider()
            Menu {
                traktListItems
            } label: {
                Label("Add to Trakt List", systemImage: "list.bullet")
            }
        }
    }

    @ViewBuilder
    private var traktListItems: some View {
        switch traktLists.state {
        case .loaded where traktLists.lists.isEmpty:
            Text("No lists yet")
        case .loaded:
            ForEach(traktLists.lists, id: \.id) { list in
                Button(list.name) {
                    let item = item
                    Task { await CardActions.addToTraktList(item, list: list) }
                }
            }
        case .failed:
            Button("Couldn't load lists. Try Again") {
                traktLists.loadIfNeeded()
            }
        case .idle, .loading:
            Text("Loading lists…")
                .onAppear { traktLists.loadIfNeeded() }
        }
    }
}

// MARK: - Confirmation for whole-show actions

/// Hosts the context menu plus the confirmation it may ask for.
private struct CardContextMenuModifier: ViewModifier {
    let item: MediaItem
    let onOpen: (() -> Void)?
    let onPlay: (() -> Void)?
    let watchlistController: WatchlistController?

    @State private var pendingWholeShowWatched: Bool?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                CardContextMenu(
                    item: item,
                    onOpen: onOpen,
                    onPlay: onPlay,
                    watchlistController: watchlistController,
                    onRequestWholeShowWatched: { watched in
                        // The menu may still be closing; present on the next turn.
                        DispatchQueue.main.async { pendingWholeShowWatched = watched }
                    }
                )
                .onAppear {
                    // Lists load lazily, the first time any card menu opens.
                    CardTraktListsCache.shared.loadIfNeeded()
                }
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: Binding(
                    get: { pendingWholeShowWatched != nil },
                    set: { if !$0 { pendingWholeShowWatched = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let watched = pendingWholeShowWatched {
                    Button(watched ? "Mark All Watched" : "Mark All Unwatched") {
                        let item = item
                        Task { await CardActions.setWatched(item, watched: watched) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
    }

    private var noun: String { item.type.lowercased() == "season" ? "season" : "show" }

    private var confirmationTitle: String {
        let title = CardActions.displayTitle(item)
        return pendingWholeShowWatched == false
            ? "Mark all of \(title) as unwatched?"
            : "Mark all of \(title) as watched?"
    }

    private var confirmationMessage: String {
        pendingWholeShowWatched == false
            ? "This clears the watched state of every episode in this \(noun)."
            : "This marks every episode in this \(noun) as watched."
    }
}

extension View {
    /// Adds the card context menu. `onPlay` should be non-nil only when the item
    /// maps onto the existing play flow (see `CardActions.playDestination(for:)`).
    func cardContextMenu(
        item: MediaItem,
        onOpen: (() -> Void)?,
        onPlay: (() -> Void)? = nil,
        watchlistController: WatchlistController?
    ) -> some View {
        modifier(CardContextMenuModifier(item: item, onOpen: onOpen, onPlay: onPlay, watchlistController: watchlistController))
    }
}
