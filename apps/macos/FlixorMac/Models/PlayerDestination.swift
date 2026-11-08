//
//  PlayerDestination.swift
//  FlixorMac
//
//  Unified navigation route for all playback sources.
//

import Foundation

enum PlayerDestination: Hashable {
    case plex(MediaItem)
    case offline(OfflineMediaItem)
    case stream(StreamPlaybackItem)
}

struct StremioSourcesDestination: Hashable {
    let identity: StremioContentIdentity
    let title: String
    let backdropURL: String?
    let posterURL: String?
    let mediaType: StreamMediaType
    let imdbId: String?
    let tmdbId: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    /// Why automatic source selection fell back to this page, shown at the top of it.
    var autoSelectNotice: String? = nil
}
