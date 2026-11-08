//
//  BrowseContext.swift
//  FlixorMac
//
//  Encapsulates data source descriptors for the Browse modal.
//

import Foundation

enum BrowseContext: Equatable {
    case plexDirectory(path: String, title: String?)
    case plexLibrary(key: String, title: String?)
    case plexWatchlist
    case plexCollection(ratingKey: String, title: String)
    case tmdb(kind: TMDBBrowseKind, media: TMDBMediaType, id: String?, displayTitle: String?)
    case trakt(kind: TraktBrowseKind)
    case stremioCatalog(StremioCatalogBrowse)
}

/// One addon catalog, as opened from its home row.
struct StremioCatalogBrowse: Equatable {
    let installationId: String
    let type: String
    let catalogId: String
    let title: String
    let addonName: String
    /// The catalog declares the `skip` extra, so more pages can be requested.
    let supportsPaging: Bool
}

enum TMDBBrowseKind: Equatable {
    case trending
    case recommendations
    case similar
    case popular
    case topRated
    case upcoming
    /// Discover by genre. The genre id travels in BrowseContext's `id`.
    case genre
}

enum TMDBMediaType: String, Equatable {
    case movie
    case tv
}

enum TraktBrowseKind: Equatable {
    case trendingMovies
    case trendingShows
    case watchlist
    case history
    case recommendations
    case popularShows
}
