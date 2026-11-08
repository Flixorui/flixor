//
//  WatchStateTarget.swift
//  FlixorMac
//
//  What a watch-state action applies to: a movie, a show, a season or an episode,
//  with whichever ids the caller already has. Built from the app's existing
//  identity formats rather than replacing them:
//
//    MediaItem.id  "plex:<ratingKey>" or a bare ratingKey  -> Plex item
//                  "tmdb:movie:<id>" / "tmdb:tv:<id>"       -> TMDB (for type
//                                                              "episode" the tv id is
//                                                              the SHOW, as written by
//                                                              local Continue Watching)
//                  "stremio:<type>:<addonId>"               -> IMDb id when addonId is tt…
//    DetailsViewModel.Episode.id "plex:<ratingKey>" (TMDB episode ids are ignored;
//                  the show id + season/episode numbers identify the episode)
//
//  `WatchStateService` fills in missing ids (e.g. TMDB/IMDb from Plex GUIDs) before
//  talking to Trakt.
//

import Foundation

struct WatchStateTarget: Hashable {
    enum Kind: Hashable {
        case movie
        case show
        /// Season number may be unknown for a bare Plex season; it is then read
        /// from Plex metadata.
        case season(Int?)
        case episode(season: Int?, episode: Int?)

        var label: String {
            switch self {
            case .movie: return "movie"
            case .show: return "show"
            case .season: return "season"
            case .episode: return "episode"
            }
        }
    }

    var kind: Kind
    /// The item's own Plex ratingKey (movie, show, season or episode).
    var plexRatingKey: String?
    /// The parent show's ratingKey for seasons/episodes.
    var showPlexRatingKey: String?
    /// Movie TMDB id, or the SHOW's TMDB id for show/season/episode.
    var tmdbId: Int?
    /// Movie IMDb id, or the SHOW's IMDb id for show/season/episode.
    var imdbId: String?
    /// Show TVDB id (Plex GUIDs often carry it), helps Trakt matching.
    var tvdbId: Int?
    var title: String?
    /// The `MediaItem.id` this target was built from, echoed in notifications so
    /// rows can find the card to update.
    var sourceItemId: String?

    init(
        kind: Kind,
        plexRatingKey: String? = nil,
        showPlexRatingKey: String? = nil,
        tmdbId: Int? = nil,
        imdbId: String? = nil,
        tvdbId: Int? = nil,
        title: String? = nil,
        sourceItemId: String? = nil
    ) {
        self.kind = kind
        self.plexRatingKey = plexRatingKey.flatMap { $0.isEmpty ? nil : $0 }
        self.showPlexRatingKey = showPlexRatingKey.flatMap { $0.isEmpty ? nil : $0 }
        self.tmdbId = tmdbId
        self.imdbId = imdbId.flatMap { $0.isEmpty ? nil : $0 }
        self.tvdbId = tvdbId
        self.title = title
        self.sourceItemId = sourceItemId
    }

    // MARK: - Factories

    static func movie(tmdbId: Int?, imdbId: String? = nil, plexRatingKey: String? = nil, title: String? = nil) -> WatchStateTarget {
        WatchStateTarget(kind: .movie, plexRatingKey: plexRatingKey, tmdbId: tmdbId, imdbId: imdbId, title: title)
    }

    static func show(tmdbId: Int?, imdbId: String? = nil, plexRatingKey: String? = nil, title: String? = nil) -> WatchStateTarget {
        WatchStateTarget(kind: .show, plexRatingKey: plexRatingKey, tmdbId: tmdbId, imdbId: imdbId, title: title)
    }

    /// A season. `plexRatingKey` is the season's own key, `showPlexRatingKey` the show's.
    static func season(
        _ number: Int,
        showTmdbId: Int?,
        showImdbId: String? = nil,
        plexRatingKey: String? = nil,
        showPlexRatingKey: String? = nil,
        title: String? = nil
    ) -> WatchStateTarget {
        WatchStateTarget(
            kind: .season(number), plexRatingKey: plexRatingKey, showPlexRatingKey: showPlexRatingKey,
            tmdbId: showTmdbId, imdbId: showImdbId, title: title
        )
    }

    /// An episode. `plexRatingKey` is the episode's own key, `showPlexRatingKey` the show's.
    static func episode(
        season: Int,
        episode: Int,
        showTmdbId: Int?,
        showImdbId: String? = nil,
        plexRatingKey: String? = nil,
        showPlexRatingKey: String? = nil,
        title: String? = nil
    ) -> WatchStateTarget {
        WatchStateTarget(
            kind: .episode(season: season, episode: episode), plexRatingKey: plexRatingKey,
            showPlexRatingKey: showPlexRatingKey, tmdbId: showTmdbId, imdbId: showImdbId, title: title
        )
    }

    /// An episode row from the details screen. Pass the show's ids from the
    /// DetailsViewModel (`tmdbId`, `imdbId`, `plexRatingKey`/`showRatingKey`).
    static func episode(
        _ episode: DetailsViewModel.Episode,
        showTmdbId: String?,
        showImdbId: String?,
        showPlexRatingKey: String?
    ) -> WatchStateTarget {
        let plexKey = episode.id.hasPrefix("plex:") ? String(episode.id.dropFirst(5)) : nil
        return WatchStateTarget(
            kind: .episode(season: episode.seasonNumber, episode: episode.episodeNumber),
            plexRatingKey: plexKey,
            showPlexRatingKey: showPlexRatingKey,
            tmdbId: showTmdbId.flatMap(Int.init),
            imdbId: showImdbId,
            title: episode.title,
            sourceItemId: episode.id
        )
    }

    /// Builds a target from any MediaItem the app produces. Nil for types that
    /// can't be watched (collections, people, unknown ids).
    init?(item: MediaItem) {
        let type = item.type.lowercased()
        let kind: Kind
        switch type {
        case "movie":
            kind = .movie
        case "show", "series", "tv":
            kind = .show
        case "season":
            kind = .season(item.index ?? item.parentIndex)
        case "episode":
            kind = .episode(season: item.parentIndex, episode: item.index)
        default:
            return nil
        }

        var plexKey: String?
        var tmdb: Int?
        var imdb: String?
        let id = item.id

        if id.hasPrefix("plex:") {
            plexKey = String(id.dropFirst(5))
        } else if id.hasPrefix("tmdb:") {
            let parts = id.split(separator: ":")
            if parts.count == 3 { tmdb = Int(parts[2]) }
        } else if id.hasPrefix("stremio:") {
            // stremio:<type>:<addonId>; addonId may itself contain ':'.
            let parts = id.split(separator: ":", maxSplits: 2)
            if parts.count == 3 {
                let addonId = String(parts[2])
                if addonId.lowercased().hasPrefix("tt") {
                    imdb = String(addonId.split(separator: ":").first ?? Substring(addonId))
                } else if addonId.hasPrefix("tmdb:") {
                    tmdb = Int(addonId.split(separator: ":").last ?? "")
                }
            }
        } else if !id.isEmpty, id.allSatisfy(\.isNumber) {
            plexKey = id
        }

        guard plexKey != nil || tmdb != nil || imdb != nil else { return nil }

        var showKey: String?
        if case .episode = kind { showKey = item.grandparentRatingKey }
        if case .season = kind { showKey = item.parentRatingKey }

        self.init(
            kind: kind,
            plexRatingKey: plexKey,
            showPlexRatingKey: plexKey != nil ? showKey : nil,
            tmdbId: tmdb,
            imdbId: imdb,
            title: type == "episode" ? (item.grandparentTitle ?? item.title) : item.title,
            sourceItemId: item.id
        )
    }

    // MARK: - Helpers

    var seasonNumber: Int? {
        switch kind {
        case .season(let n): return n
        case .episode(let s, _): return s
        default: return nil
        }
    }

    var episodeNumber: Int? {
        if case .episode(_, let e) = kind { return e }
        return nil
    }

    var isMovie: Bool { kind == .movie }

    /// Stable key for de-duplicating in-flight actions.
    var actionKey: String {
        let ids = plexRatingKey.map { "plex:\($0)" }
            ?? tmdbId.map { "tmdb:\($0)" }
            ?? imdbId.map { "imdb:\($0.lowercased())" }
            ?? "unknown"
        switch kind {
        case .movie: return "movie:\(ids)"
        case .show: return "show:\(ids)"
        case .season(let n): return "season:\(ids):\(n.map(String.init) ?? "?")"
        case .episode(let s, let e):
            return "episode:\(ids):\(s.map(String.init) ?? "?"):\(e.map(String.init) ?? "?")"
        }
    }
}
