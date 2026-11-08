//
//  HomeViewModel+Rows.swift
//  FlixorMac
//
//  Builds the home screen's row list: every kind of row (Continue Watching,
//  Plex libraries and collections, discovery, Trakt, Stremio catalogs) in one
//  list, with the user's order, custom titles and hidden rows applied, plus
//  loading placeholders and per-row error cards.
//

import Foundation

// MARK: - Row failures

/// A Stremio catalog, enough to fetch it again.
struct StremioCatalogRef: Equatable {
    let entryId: String
    let installationId: String
    let type: String
    let catalogId: String
    let displayName: String
    let addonName: String
    let supportsPaging: Bool
}

/// How to retry a failed row.
enum HomeRowRetry: Equatable {
    case continueWatching
    case recentlyAdded
    case collections
    case extras
    case stremioCatalog(StremioCatalogRef)
}

/// A row (or group of rows) that failed to load.
struct HomeRowFailure: Identifiable, Equatable {
    /// Row id when the failure is one row, else a group id.
    let id: String
    let title: String
    /// Which source failed, shown on the card ("AIOMetadata", "TMDB", "Plex", ...).
    let source: String
    let message: String
    let retry: HomeRowRetry
}

/// One entry of the discovery / catalog rows: a loaded row or a failure in its place.
enum HomeRowSlot: Identifiable {
    case section(LibrarySection)
    case failure(HomeRowFailure)

    var id: String {
        switch self {
        case .section(let section): return section.id
        case .failure(let failure): return failure.id
        }
    }

    var title: String {
        switch self {
        case .section(let section): return section.title
        case .failure(let failure): return failure.title
        }
    }

    var section: LibrarySection? {
        if case .section(let section) = self { return section }
        return nil
    }

    var failure: HomeRowFailure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}

// MARK: - Display rows

/// A row as rendered by HomeView.
struct HomeDisplayRow: Identifiable {
    enum Content {
        case continueWatching
        case section(LibrarySection)
        case skeleton(SkeletonCarouselRow.CardType)
        case failure(HomeRowFailure)
        /// Loads itself when it scrolls into view.
        case userCollection(id: String)
    }

    let id: String
    let title: String
    var caption: String?
    let content: Content

    var isPlaceholder: Bool {
        if case .skeleton = content { return true }
        return false
    }

    var isFailure: Bool {
        if case .failure = content { return true }
        return false
    }
}

extension HomeViewModel {
    /// The ordered rows to show. Hidden rows are left out, custom titles applied,
    /// failures dropped when offline (the offline card covers them).
    func displayRows(store: HomeRowsStore, settings: ProfileSettings, isOnline: Bool) -> [HomeDisplayRow] {
        let cardType: SkeletonCarouselRow.CardType = settings.rowLayout == "poster" ? .poster : .landscape
        var rows: [HomeDisplayRow] = []

        func skeletons(_ prefix: String, count: Int) {
            for index in 0..<count {
                rows.append(HomeDisplayRow(id: "skeleton-\(prefix)-\(index)", title: "", content: .skeleton(cardType)))
            }
        }

        func add(_ section: LibrarySection) {
            let title = store.title(for: section.id, default: section.title)
            let renamed = title == section.title ? section : LibrarySection(
                id: section.id,
                title: title,
                items: section.items,
                totalCount: section.totalCount,
                libraryKey: section.libraryKey,
                browseContext: section.browseContext,
                isCollection: section.isCollection
            )
            rows.append(HomeDisplayRow(id: section.id, title: title, content: .section(renamed)))
        }

        func add(_ failure: HomeRowFailure) {
            let title = store.title(for: failure.id, default: failure.title)
            let renamed = HomeRowFailure(id: failure.id, title: title, source: failure.source, message: failure.message, retry: failure.retry)
            rows.append(HomeDisplayRow(id: failure.id, title: title, content: .failure(renamed)))
        }

        // Continue Watching
        if settings.showContinueWatching {
            let title = store.title(for: homeContinueWatchingRowId, default: String(localized: "Continue Watching"))
            switch continueWatchingState {
            case .idle, .loading, .loaded:
                rows.append(HomeDisplayRow(id: homeContinueWatchingRowId, title: title, content: .continueWatching))
            case .error(let message):
                add(HomeRowFailure(id: homeContinueWatchingRowId, title: title, source: isStremioOnlyMode ? String(localized: "Watch history") : "Plex",
                                   message: message, retry: .continueWatching))
            case .empty:
                break
            }
        }

        // Recently Added per library (Plex)
        switch recentlyAddedPerLibraryState {
        case .idle, .loading:
            skeletons("recent", count: 2)
        case .error(let message):
            add(HomeRowFailure(id: "recently-added", title: String(localized: "Recently Added"), source: "Plex", message: message, retry: .recentlyAdded))
        case .loaded, .empty:
            recentlyAddedSections.forEach(add)
        }

        // Plex collections
        if settings.showCollectionRows {
            switch collectionSectionsState {
            case .idle, .loading:
                skeletons("collections", count: 3)
            case .error(let message):
                add(HomeRowFailure(id: "collections", title: String(localized: "Collections"), source: "Plex", message: message, retry: .collections))
            case .loaded, .empty:
                collectionSections.forEach(add)
            }
        }

        // User-built collections
        for collection in UserCollectionsStore.shared.homeCollections {
            let title = store.title(for: collection.homeRowId, default: collection.name)
            rows.append(HomeDisplayRow(id: collection.homeRowId, title: title, content: .userCollection(id: collection.id)))
        }

        // Discovery, watchlist, Trakt and Stremio catalogs
        switch extraSectionsState {
        case .idle, .loading:
            skeletons("extra", count: expectedExtraSectionCountForMode)
        default:
            for slot in extraSlots {
                switch slot {
                case .section(let section): add(section)
                case .failure(let failure): add(failure)
                }
            }
        }

        var visible = rows.filter { row in
            if row.isPlaceholder { return true }
            if row.isFailure && !isOnline { return false }
            return !store.isHidden(row.id)
        }
        visible = HomeRowsStore.ordered(visible, id: \.id, userOrder: store.order)

        let captions = duplicateTitleCaptions(for: visible.filter { !$0.isPlaceholder }.map { ($0.id, $0.title) })
        for index in visible.indices {
            visible[index].caption = captions[visible[index].id]
        }
        return visible
    }

    /// Captions for rows whose (final) title is shared with another row.
    /// Only Stremio catalog rows get one: the addon name they come from.
    func duplicateTitleCaptions(for rows: [(id: String, title: String)]) -> [String: String] {
        var counts: [String: Int] = [:]
        for row in rows {
            counts[normalizedTitle(row.title), default: 0] += 1
        }
        var captions: [String: String] = [:]
        for row in rows where (counts[normalizedTitle(row.title)] ?? 0) > 1 {
            if let addon = catalogAddonNames[row.id] {
                captions[row.id] = addon
            }
        }
        return captions
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Row descriptors (Rows Settings)

    /// Descriptor for a discovery / catalog row, used by Rows Settings.
    func descriptor(for slot: HomeRowSlot) -> HomeRowDescriptor {
        let id = slot.id
        let kind: HomeRowKind
        if id.hasPrefix("stremio-catalog-") {
            kind = .stremioCatalog
        } else if id.hasPrefix("trakt-") {
            kind = .trakt
        } else if id.hasPrefix("genre-") || id.hasPrefix("tmdb-genre-") {
            kind = .genre
        } else if id == homeWatchlistRowId {
            kind = .watchlist
        } else {
            kind = .discovery
        }
        return HomeRowDescriptor(id: id, defaultTitle: slot.title, kind: kind, group: .extras, detail: catalogAddonNames[id])
    }
}
