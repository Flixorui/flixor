//
//  LocalWatchedEntry.swift
//  FlixorMac
//
//  A title or episode marked watched on this Mac. Used when the item has no Plex
//  copy to scrobble (Stremio-only mode, or TMDB/Stremio items in Plex mode), so
//  "Mark as watched" still sticks without Plex or Trakt.
//

import Foundation

struct LocalWatchedEntry: Codable, Hashable, Identifiable {
    var id: String { key }

    /// Storage key, see `LocalWatchedEntry.key(...)`.
    let key: String
    /// `.movie` or `.episode`. Seasons and shows are stored as their episodes.
    let mediaType: StreamMediaType
    /// Movie TMDB id, or the SHOW's TMDB id for episodes.
    let tmdbId: Int?
    /// Movie IMDb id, or the SHOW's IMDb id for episodes.
    let imdbId: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let watchedAt: Date

    init?(
        mediaType: StreamMediaType,
        tmdbId: Int?,
        imdbId: String?,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        watchedAt: Date = Date()
    ) {
        guard let key = Self.key(
            mediaType: mediaType, tmdbId: tmdbId, imdbId: imdbId,
            seasonNumber: seasonNumber, episodeNumber: episodeNumber
        ) else { return nil }
        self.key = key
        self.mediaType = mediaType
        self.tmdbId = tmdbId
        self.imdbId = imdbId?.lowercased()
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.watchedAt = watchedAt
    }

    /// `movie:tmdb:603`, `movie:imdb:tt0133093`, `episode:tmdb:1399:1:2`, ...
    /// TMDB is preferred so the same title marked from different screens collapses
    /// to one entry. Nil when there is no usable id (or episode numbers are missing).
    static func key(
        mediaType: StreamMediaType,
        tmdbId: Int?,
        imdbId: String?,
        seasonNumber: Int?,
        episodeNumber: Int?
    ) -> String? {
        let idPart: String
        if let tmdbId {
            idPart = "tmdb:\(tmdbId)"
        } else if let imdbId, !imdbId.isEmpty {
            idPart = "imdb:\(imdbId.lowercased())"
        } else {
            return nil
        }
        switch mediaType {
        case .movie:
            return "movie:\(idPart)"
        case .episode:
            guard let seasonNumber, let episodeNumber else { return nil }
            return "episode:\(idPart):\(seasonNumber):\(episodeNumber)"
        }
    }

    /// True when this entry is for the given title (and season/episode, when given).
    /// `season == nil` matches every episode of a show; `episode == nil` every
    /// episode of the season.
    func matches(mediaType: StreamMediaType, tmdbId: Int?, imdbId: String?, season: Int?, episode: Int?) -> Bool {
        guard self.mediaType == mediaType else { return false }
        let sameTitle = (tmdbId != nil && self.tmdbId == tmdbId)
            || (imdbId.map { !$0.isEmpty && self.imdbId == $0.lowercased() } ?? false)
        guard sameTitle else { return false }
        if mediaType == .movie { return true }
        if let season, seasonNumber != season { return false }
        if let episode, episodeNumber != episode { return false }
        return true
    }
}
