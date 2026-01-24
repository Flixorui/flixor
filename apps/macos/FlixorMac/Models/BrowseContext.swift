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
}

enum TMDBBrowseKind: Equatable {
    case trending
    case recommendations
    case similar
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
