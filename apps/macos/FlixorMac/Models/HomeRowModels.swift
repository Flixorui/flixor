//
//  HomeRowModels.swift
//  FlixorMac
//
//  Value types for the customisable home screen: row descriptors (for
//  reorder / rename / hide), hero source and Continue Watching options.
//

import Foundation

// MARK: - Home rows

/// The kind of a home row; drives the icon in Rows Settings.
enum HomeRowKind: String, Codable {
    case continueWatching
    case recentlyAdded
    case collection
    case watchlist
    case discovery
    case genre
    case trakt
    case stremioCatalog
    case userCollection

    var iconName: String {
        switch self {
        case .continueWatching: return "play.circle.fill"
        case .recentlyAdded: return "clock.fill"
        case .collection: return "sparkles"
        case .watchlist: return "bookmark.fill"
        case .discovery: return "flame.fill"
        case .genre: return "theatermasks.fill"
        case .trakt: return "chart.bar.fill"
        case .stremioCatalog: return "puzzlepiece.extension.fill"
        case .userCollection: return "rectangle.stack.fill"
        }
    }

    var label: String {
        switch self {
        case .continueWatching: return "Continue Watching"
        case .recentlyAdded: return "Plex library"
        case .collection: return "Plex collection"
        case .watchlist: return "Watchlist"
        case .discovery: return "Discovery"
        case .genre: return "Genre"
        case .trakt: return "Trakt"
        case .stremioCatalog: return "Addon catalog"
        case .userCollection: return "Your collection"
        }
    }
}

/// Which loader produced a row. Rows of a group are replaced together when the
/// group reloads, so rows that no longer exist drop out of Rows Settings.
enum HomeRowGroup: String, Codable {
    case continueWatching
    case recentlyAdded
    case collections
    case userCollections
    case extras
}

/// A home row as listed in Rows Settings. Stored per profile so the list is
/// available before the home screen has loaded.
struct HomeRowDescriptor: Codable, Identifiable, Equatable {
    /// Stable row id (e.g. "continue-watching", "recently-added-3",
    /// "stremio-catalog-<installation>:<type>:<catalog>").
    let id: String
    /// Title the app gives the row (before any rename).
    let defaultTitle: String
    let kind: HomeRowKind
    let group: HomeRowGroup
    /// Source shown as a secondary line in settings (e.g. the addon name).
    var detail: String?
}

/// Stable id of the Continue Watching row.
let homeContinueWatchingRowId = "continue-watching"
/// Stable id of the combined Plex/Trakt watchlist row.
let homeWatchlistRowId = "combined-watchlist"

// MARK: - Hero source

/// What feeds the home hero (billboard / carousel).
enum HomeHeroSource: Equatable, Hashable {
    /// First available of Continue Watching, On Deck, Recently Added, then discovery rows.
    case automatic
    case continueWatching
    case myList
    /// A specific home row by id.
    case row(String)

    init(storageValue: String?) {
        switch storageValue {
        case nil, "", "default": self = .automatic
        case "continueWatching": self = .continueWatching
        case "myList": self = .myList
        case let value?:
            if value.hasPrefix("row:") {
                self = .row(String(value.dropFirst(4)))
            } else {
                self = .automatic
            }
        }
    }

    var storageValue: String {
        switch self {
        case .automatic: return "default"
        case .continueWatching: return "continueWatching"
        case .myList: return "myList"
        case .row(let id): return "row:\(id)"
        }
    }
}

// MARK: - Continue Watching

/// Continue Watching card style. Stored in the existing
/// `continueWatchingLayout` setting ("landscape" / "poster" / "wide").
enum ContinueWatchingCardStyle: String, CaseIterable, Identifiable {
    case landscape
    case poster
    case wide

    var id: String { rawValue }

    init(storageValue: String) {
        self = ContinueWatchingCardStyle(rawValue: storageValue) ?? .landscape
    }

    var title: String {
        switch self {
        case .landscape: return "Landscape"
        case .poster: return "Poster"
        case .wide: return "Wide"
        }
    }

    var iconName: String {
        switch self {
        case .landscape: return "rectangle.fill"
        case .poster: return "rectangle.portrait.fill"
        case .wide: return "rectangle.inset.filled"
        }
    }
}

/// Order of the Continue Watching row.
enum ContinueWatchingSort: String, CaseIterable, Identifiable {
    /// Server / history order (most recently watched first).
    case recent
    /// Up-next episodes (not started yet) first, then the rest by recency.
    case nextEpisodeFirst
    /// Alphabetical by show or movie title.
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recently watched"
        case .nextEpisodeFirst: return "Next episode first"
        case .title: return "Title"
        }
    }

    func apply(to items: [MediaItem]) -> [MediaItem] {
        switch self {
        case .recent:
            return items
        case .nextEpisodeFirst:
            let upNext = items.filter(\.isUpNextEpisode)
            let started = items.filter { !$0.isUpNextEpisode }
            return upNext + started
        case .title:
            return items.sorted {
                $0.continueWatchingSortTitle.localizedStandardCompare($1.continueWatchingSortTitle) == .orderedAscending
            }
        }
    }
}

/// Actions offered by the Continue Watching "…" menu and context menu.
enum ContinueWatchingAction: String, CaseIterable, Identifiable {
    case resume
    case startOver
    case markWatched
    case remove
    case details

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resume: return "Resume"
        case .startOver: return "Start Over"
        case .markWatched: return "Mark as Watched"
        case .remove: return "Remove from Continue Watching"
        case .details: return "Go to Details"
        }
    }

    var iconName: String {
        switch self {
        case .resume: return "play.fill"
        case .startOver: return "arrow.counterclockwise"
        case .markWatched: return "checkmark.circle"
        case .remove: return "xmark.circle"
        case .details: return "info.circle"
        }
    }

    /// Actions that change watch state (disabled while one is in flight).
    var changesWatchState: Bool {
        switch self {
        case .startOver, .markWatched, .remove: return true
        case .resume, .details: return false
        }
    }
}

extension MediaItem {
    /// An episode in Continue Watching that has not been started yet (Plex
    /// "next up"). Its still can spoil, so it can be blurred.
    var isUpNextEpisode: Bool {
        type == "episode" && (viewOffset ?? 0) <= 0
    }

    /// A "Recently Added" card that stands in for several (or one) new episodes
    /// of a show (HomeViewModel.groupEpisodesBySeries). Its id is the show's,
    /// so watch-state actions on it would hit the whole show: never offer
    /// "Mark as watched" / "Remove from Continue Watching" for these.
    var isGroupedRecentlyAddedShow: Bool {
        type == "show" && leafCount != nil && (summary?.hasSuffix("new episode") == true || summary?.hasSuffix("new episodes") == true)
    }

    /// Whether Continue Watching watch-state actions (start over, mark watched,
    /// remove) may target this item: only a real movie or episode.
    var supportsContinueWatchingStateActions: Bool {
        (type == "movie" || type == "episode") && !isGroupedRecentlyAddedShow
    }

    /// Title used for alphabetical sorting: the show for episodes.
    var continueWatchingSortTitle: String {
        type == "episode" ? (grandparentTitle ?? title) : title
    }

    /// Copy with the resume point cleared, for "Start Over".
    func withoutResumePoint() -> MediaItem {
        MediaItem(
            id: id, title: title, type: type, thumb: thumb, art: art, year: year,
            rating: rating, duration: duration, viewOffset: nil, summary: summary,
            grandparentTitle: grandparentTitle, grandparentThumb: grandparentThumb,
            grandparentArt: grandparentArt, grandparentRatingKey: grandparentRatingKey,
            parentIndex: parentIndex, index: index, parentRatingKey: parentRatingKey,
            parentTitle: parentTitle, leafCount: leafCount, viewedLeafCount: viewedLeafCount,
            mediaIndex: mediaIndex, media: media, editionTitle: editionTitle
        )
    }
}
