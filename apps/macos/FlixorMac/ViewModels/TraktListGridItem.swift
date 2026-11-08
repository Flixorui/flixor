//
//  TraktListGridItem.swift
//  FlixorMac
//
//  One poster on a Trakt list: a movie, show, season or episode entry, with the
//  MediaItems the card and the details screen need and the Trakt ids to remove it.
//

import Foundation
import FlixorKit

struct TraktListGridItem: Identifiable {
    enum Kind {
        case movie
        case show
        case season(Int)
        case episode(season: Int, number: Int)
    }

    /// Trakt's list entry id: unique within the list, even when a show and one of
    /// its seasons are both on it.
    let id: Int
    let kind: Kind
    let title: String
    /// The show's title for season and episode entries, otherwise `title`.
    let parentTitle: String
    let year: Int?
    let rating: Double?
    let overview: String?
    let genres: [String]
    let runtimeMinutes: Int?
    let dateAdded: Date?
    /// Ids of the movie, or of the show for show/season/episode entries.
    let traktId: Int?
    let tmdbId: Int?
    let imdbId: String?
    var imageURL: URL?

    var mediaType: MyListViewModel.MediaType {
        if case .movie = kind { return .movie }
        return .show
    }

    /// Shown on the poster for entries that aren't a whole title.
    var badgeText: String? {
        switch kind {
        case .movie, .show:
            return nil
        case .season(let number):
            return "S\(number)"
        case .episode(let season, let number):
            return "S\(season) E\(number)"
        }
    }

    /// Key for the poster lookup; seasons and episodes use their show's poster.
    var posterKey: String? {
        guard let tmdbId else { return nil }
        return "\(mediaType == .movie ? "movie" : "tv")/\(tmdbId)"
    }

    /// Same id format as the merged My List view, so details and watchlist state match.
    private var canonicalId: String {
        let tmdbType = mediaType == .movie ? "movie" : "tv"
        if let tmdbId { return "tmdb:\(tmdbType):\(tmdbId)" }
        if let imdbId { return "imdb:\(imdbId)" }
        if let traktId { return "trakt:\(traktId)" }
        return "trakt-list-entry:\(id)"
    }

    /// The item on the card. Seasons and episodes keep their own type so the card's
    /// actions apply to that season or episode, not the whole show.
    var cardItem: MediaItem {
        var parentIndex: Int?
        var index: Int?
        var type = mediaType == .movie ? "movie" : "show"
        switch kind {
        case .movie, .show:
            break
        case .season(let number):
            type = "season"
            index = number
        case .episode(let season, let number):
            type = "episode"
            parentIndex = season
            index = number
        }
        let isEpisode = type == "episode"
        return makeMediaItem(
            title: title,
            type: type,
            parentIndex: parentIndex,
            index: index,
            grandparentTitle: isEpisode ? parentTitle : nil,
            parentTitle: type == "season" ? parentTitle : nil
        )
    }

    /// The item to open: the movie or show itself, for every kind of entry.
    var detailsItem: MediaItem {
        makeMediaItem(title: parentTitle, type: mediaType == .movie ? "movie" : "show")
    }

    private func makeMediaItem(
        title: String,
        type: String,
        parentIndex: Int? = nil,
        index: Int? = nil,
        grandparentTitle: String? = nil,
        parentTitle: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: canonicalId,
            title: title,
            type: type,
            thumb: imageURL?.absoluteString,
            art: nil,
            year: year,
            rating: rating,
            duration: runtimeMinutes.map { $0 * 60000 },
            viewOffset: nil,
            summary: overview,
            grandparentTitle: grandparentTitle,
            grandparentThumb: nil,
            grandparentArt: nil,
            grandparentRatingKey: nil,
            parentIndex: parentIndex,
            index: index,
            parentRatingKey: nil,
            parentTitle: parentTitle,
            leafCount: nil,
            viewedLeafCount: nil
        )
    }

    /// Sync body that removes this entry. Nil when the entry has no usable ids.
    var syncItems: TraktSyncItems? {
        guard traktId != nil || tmdbId != nil || imdbId != nil else { return nil }
        let ids = TraktScrobbleIds(trakt: traktId, imdb: imdbId, tmdb: tmdbId)
        switch kind {
        case .movie:
            return .movie(ids)
        case .show:
            return .show(ids)
        case .season(let number):
            return .season(showIds: ids, season: number)
        case .episode(let season, let number):
            return .episode(showIds: ids, season: season, episode: number)
        }
    }

    func matches(_ term: String) -> Bool {
        title.lowercased().contains(term)
            || parentTitle.lowercased().contains(term)
            || (overview?.lowercased().contains(term) ?? false)
            || genres.joined(separator: " ").lowercased().contains(term)
    }
}

// MARK: - Mapping

extension TraktListGridItem {
    /// Nil for entries the poster grid can't show (people).
    init?(entry: TraktListEntry) {
        switch entry.type {
        case "movie":
            guard let movie = entry.movie else { return nil }
            self.init(
                entry: entry,
                kind: .movie,
                title: movie.title,
                parentTitle: movie.title,
                year: movie.year,
                rating: movie.rating,
                overview: movie.overview,
                genres: movie.genres ?? [],
                runtimeMinutes: movie.runtime,
                ids: movie.ids
            )
        case "show":
            guard let show = entry.show else { return nil }
            self.init(entry: entry, show: show, kind: .show, title: show.title)
        case "season":
            guard let show = entry.show, let season = entry.season else { return nil }
            let name = season.number == 0 ? "Specials" : "Season \(season.number)"
            self.init(entry: entry, show: show, kind: .season(season.number), title: "\(show.title): \(name)")
        case "episode":
            guard let show = entry.show, let episode = entry.episode else { return nil }
            self.init(
                entry: entry,
                show: show,
                kind: .episode(season: episode.season, number: episode.number),
                title: episode.title ?? "Episode \(episode.number)"
            )
        default:
            return nil
        }
    }

    private init(entry: TraktListEntry, show: FlixorKit.TraktShow, kind: Kind, title: String) {
        self.init(
            entry: entry,
            kind: kind,
            title: title,
            parentTitle: show.title,
            year: show.year,
            rating: show.rating,
            overview: show.overview,
            genres: show.genres ?? [],
            runtimeMinutes: show.runtime,
            ids: show.ids
        )
    }

    private init(
        entry: TraktListEntry,
        kind: Kind,
        title: String,
        parentTitle: String,
        year: Int?,
        rating: Double?,
        overview: String?,
        genres: [String],
        runtimeMinutes: Int?,
        ids: TraktIds
    ) {
        self.init(
            id: entry.id,
            kind: kind,
            title: title,
            parentTitle: parentTitle,
            year: year,
            rating: rating,
            overview: overview,
            genres: genres,
            runtimeMinutes: runtimeMinutes,
            dateAdded: Self.parseDate(entry.listedAt),
            traktId: ids.trakt,
            tmdbId: ids.tmdb,
            imdbId: ids.imdb,
            imageURL: nil
        )
    }

    /// Trakt timestamps carry fractional seconds ("2024-05-01T10:00:00.000Z"),
    /// which a default ISO8601DateFormatter rejects.
    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalDateFormatter.date(from: value) ?? plainDateFormatter.date(from: value)
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainDateFormatter = ISO8601DateFormatter()
}
