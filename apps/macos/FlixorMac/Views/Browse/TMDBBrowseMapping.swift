//
//  TMDBBrowseMapping.swift
//  FlixorMac
//
//  Helpers shared by the person and company/network pages: TMDB image URLs
//  and TMDB results mapped to the app's MediaItem (ids "tmdb:movie:<id>" and
//  "tmdb:tv:<id>", which DetailsView resolves in Plex and Stremio-only mode).
//

import Foundation
import FlixorKit

enum TMDBImageURL {
    /// URL for a TMDB image path ("/abc.jpg"). Full http(s) URLs are passed
    /// through, so callers can hand over either form (routes carry both).
    static func url(_ pathOrURL: String?, size: TMDBImageSize) -> URL? {
        guard let raw = pathOrURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        let path = raw.hasPrefix("/") ? raw : "/" + raw
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }
}

extension MediaItem {
    /// A TMDB movie or show as a MediaItem that opens DetailsView.
    static func fromTMDB(
        id: Int,
        isTV: Bool,
        title: String,
        posterPath: String?,
        backdropPath: String?,
        date: String?,
        voteAverage: Double?,
        overview: String?
    ) -> MediaItem {
        let year: Int? = {
            guard let date, date.count >= 4 else { return nil }
            return Int(date.prefix(4))
        }()
        return MediaItem(
            id: "tmdb:\(isTV ? "tv" : "movie"):\(id)",
            title: title,
            type: isTV ? "show" : "movie",
            thumb: TMDBImageURL.url(posterPath, size: .w500)?.absoluteString,
            art: TMDBImageURL.url(backdropPath ?? posterPath, size: .w780)?.absoluteString,
            year: year,
            rating: (voteAverage ?? 0) > 0 ? voteAverage : nil,
            duration: nil,
            viewOffset: nil,
            summary: overview,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
    }

    static func fromTMDB(_ credit: TMDBPersonCredit) -> MediaItem {
        fromTMDB(
            id: credit.id,
            isTV: credit.mediaType == "tv",
            title: credit.displayTitle,
            posterPath: credit.posterPath,
            backdropPath: credit.backdropPath,
            date: credit.date,
            voteAverage: credit.voteAverage,
            overview: credit.overview
        )
    }

    static func fromTMDB(_ media: TMDBMedia, mediaType: TMDBDiscoverMediaType) -> MediaItem {
        let isTV = mediaType == .tv
        let date = isTV ? (media.firstAirDate ?? media.releaseDate) : (media.releaseDate ?? media.firstAirDate)
        return fromTMDB(
            id: media.id,
            isTV: isTV,
            title: media.title ?? media.name ?? "",
            posterPath: media.posterPath,
            backdropPath: media.backdropPath,
            date: date.flatMap { $0.isEmpty ? nil : $0 },
            voteAverage: media.voteAverage,
            overview: media.overview
        )
    }
}

/// Column count and exact item width for a poster grid filling `availableWidth`.
struct PosterGridLayout: Equatable {
    let columns: Int
    let itemWidth: CGFloat
    let spacing: CGFloat

    init(availableWidth: CGFloat, minItemWidth: CGFloat, spacing: CGFloat) {
        let width = max(availableWidth, minItemWidth)
        let count = max(1, Int((width + spacing) / (minItemWidth + spacing)))
        self.columns = count
        self.spacing = spacing
        self.itemWidth = ((width - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
    }
}

/// User-facing text for a failed TMDB request.
enum TMDBErrorMessage {
    static func message(for error: Error, fallback: String) -> String {
        if let kitError = error as? FlixorKit.APIError {
            switch kitError {
            case .unauthorized:
                return String(localized: "TMDB rejected the request: the TMDB API key is missing or invalid.")
            case .httpError(let status, _) where status == 401:
                return String(localized: "TMDB rejected the request: the TMDB API key is missing or invalid.")
            case .httpError(let status, _) where status == 404:
                return String(localized: "TMDB has no entry for this.")
            case .networkError:
                return String(localized: "Check your internet connection and try again.")
            default:
                break
            }
        }
        if error is URLError {
            return String(localized: "Check your internet connection and try again.")
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return fallback
    }
}
