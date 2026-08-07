//
//  StremioModels.swift
//  FlixorMac
//
//  Shared model types for native macOS Stremio integration.
//

import Foundation

enum StreamProvider: String, Codable, Hashable {
    case stremio
}

enum StreamMediaType: String, Codable, Hashable {
    case movie
    case episode
}

enum StremioRequestType: String, Codable, Hashable {
    case movie
    case series
}

enum StremioSourceType: String, Codable, Hashable {
    case url
    case externalUrl
    case ytId
    case infoHash
    case nzbUrl
    case archive
    case unknown
}

enum StremioUnsupportedSourceVisibility: String, Codable, CaseIterable, Hashable {
    case showDisabled
    case hide

    var description: String {
        switch self {
        case .showDisabled:
            return "Show Disabled Sources"
        case .hide:
            return "Hide Unsupported Sources"
        }
    }
}

enum SubtitleSourcePreference: String, Codable, CaseIterable, Hashable {
    case `internal`
    case external
    case any

    var description: String {
        switch self {
        case .internal:
            return "Prefer Internal"
        case .external:
            return "Prefer External"
        case .any:
            return "Any Source"
        }
    }
}

struct HTTPHeaderField: Codable, Hashable {
    let name: String
    let value: String
}

struct StremioResourceObject: Codable, Hashable {
    let name: String
    let types: [String]?
    let idPrefixes: [String]?
}

struct StremioAddonBehaviorHints: Codable, Hashable {
    let configurable: Bool?
    let configurationRequired: Bool?
    let configurationURL: String?
    let adult: Bool?
    let p2p: Bool?
}

struct StremioAddonConfigOption: Codable, Hashable {
    let key: String
    let type: String
    let defaultValue: String?
    let title: String?
    let options: [String]?
    let required: Bool?

    enum CodingKeys: String, CodingKey {
        case key
        case type
        case defaultValue = "default"
        case title
        case options
        case required
    }
}

// MARK: - Catalogs

/// An `extra` parameter a catalog accepts, e.g. `search`, `genre` or `skip`.
struct StremioCatalogExtra: Codable, Hashable {
    let name: String
    let isRequired: Bool
    let options: [String]?
    let optionsLimit: Int?
}

/// One catalog advertised by an addon's manifest (`manifest.catalogs`).
struct StremioCatalogDefinition: Codable, Hashable, Identifiable {
    /// Stremio content type: "movie", "series", ...
    let type: String
    /// The addon's own catalog id, e.g. "top", "year".
    let catalogId: String
    let name: String?
    let extra: [StremioCatalogExtra]?

    var id: String { "\(type):\(catalogId)" }

    enum CodingKeys: String, CodingKey {
        case type
        case catalogId = "id"
        case name
        case extra
    }

    var supportsSearch: Bool {
        extra?.contains { $0.name == "search" } ?? false
    }

    /// Catalogs with a required extra other than `skip` can't be listed as a plain
    /// home row - they need user input first (a search term, a genre, ...).
    var isBrowsable: Bool {
        let required = extra?.filter(\.isRequired).map(\.name) ?? []
        return required.allSatisfy { $0 == "skip" }
    }

    var displayName: String {
        let base = name ?? catalogId.capitalized
        return type == "series" ? "\(base) (TV)" : base
    }
}

// MARK: - Meta

/// A catalog row entry. Ids are usually IMDb (`tt…`) but may be addon-specific.
struct StremioMetaPreview: Codable, Hashable, Identifiable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    /// Free-form in the spec: "2019", "2019-2021", "2019-".
    let releaseInfo: String?
    let imdbRating: String?

    /// First four-digit year in `releaseInfo`, if any.
    var year: Int? {
        guard let releaseInfo else { return nil }
        return Int(releaseInfo.prefix(4))
    }

    var imdbId: String? {
        id.hasPrefix("tt") ? id : nil
    }
}

struct StremioMetaVideo: Codable, Hashable, Identifiable {
    let id: String
    let title: String?
    let season: Int?
    let episode: Int?
    let released: String?
    let thumbnail: String?
    let overview: String?
}

struct StremioMetaDetail: Codable, Hashable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?
    let videos: [StremioMetaVideo]?
}

struct StremioAddonManifest: Codable, Hashable, Identifiable {
    let id: String
    let installationId: String
    let name: String
    let version: String
    let description: String?
    let url: String?
    let originalURL: String?
    let transportURL: String?
    let resources: [StremioResourceObject]?
    let types: [String]?
    let idPrefixes: [String]?
    let behaviorHints: StremioAddonBehaviorHints?
    let config: [StremioAddonConfigOption]?
    /// Optional so addon manifests persisted before catalog support still decode.
    let catalogs: [StremioCatalogDefinition]?

    enum CodingKeys: String, CodingKey {
        case id
        case installationId
        case name
        case version
        case description
        case url
        case originalURL
        case transportURL
        case resources
        case types
        case idPrefixes
        case behaviorHints
        case config
        case catalogs
    }
}

struct StremioSubtitleCandidate: Codable, Hashable, Identifiable {
    let id: String
    let url: String
    let lang: String
    let format: String?
    let addonId: String?
    let addonName: String?
}

struct StremioStreamProxyHeaders: Codable, Hashable {
    let request: [String: String]?
    let response: [String: String]?
}

struct StremioStreamBehaviorHints: Codable, Hashable {
    let bingeGroup: String?
    let notWebReady: Bool?
    let countryWhitelist: [String]?
    let cached: Bool?
    let proxyHeaders: StremioStreamProxyHeaders?
    let videoHash: String?
    let videoSize: Int?
    let filename: String?
}

struct StremioArchiveSource: Codable, Hashable {
    let url: String
    let bytes: Int?
}

struct StremioPlayableStream: Codable, Hashable, Identifiable {
    let id: String
    let url: String?
    let externalUrl: String?
    let ytId: String?
    let infoHash: String?
    let nzbUrl: String?
    let rarUrls: [StremioArchiveSource]?
    let zipUrls: [StremioArchiveSource]?
    let sevenZipUrls: [StremioArchiveSource]?
    let tgzUrls: [StremioArchiveSource]?
    let tarUrls: [StremioArchiveSource]?
    let fileIdx: Int?
    let fileMustInclude: String?
    let servers: [String]?
    let name: String?
    let title: String?
    let description: String?
    let addonId: String?
    let addonName: String?
    let addonInstallationId: String?
    let size: Int?
    let isFree: Bool?
    let isDebrid: Bool?
    let quality: String?
    let headers: [String: String]?
    let subtitles: [StremioSubtitleCandidate]?
    let sources: [String]?
    let behaviorHints: StremioStreamBehaviorHints?
    let streamIndex: Int
    let sourceType: StremioSourceType
    let playable: Bool
    let disabledReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case externalUrl
        case ytId
        case infoHash
        case nzbUrl
        case rarUrls
        case zipUrls
        case sevenZipUrls = "sevenZipUrls"
        case tgzUrls
        case tarUrls
        case fileIdx
        case fileMustInclude
        case servers
        case name
        case title
        case description
        case addonId
        case addonName
        case addonInstallationId
        case size
        case isFree
        case isDebrid
        case quality
        case headers
        case subtitles
        case sources
        case behaviorHints
        case streamIndex
        case sourceType
        case playable
        case disabledReason
    }
}

struct StremioAddonStreamResult: Codable, Hashable, Identifiable {
    var id: String { installationId }

    let addonId: String
    let addonName: String
    let installationId: String
    let streams: [StremioPlayableStream]
    let error: String?
}

struct StremioAddonSummary: Codable, Hashable, Identifiable {
    var id: String { installationId }

    let addonId: String
    let installationId: String
    let name: String
    let manifestURL: String?
    let configureURL: String?
    let streamCapable: Bool
    let subtitleCapable: Bool
    let catalogCapable: Bool
    let configurationRequired: Bool
}

struct StremioContentIdentity: Codable, Hashable {
    let requestType: String
    let baseId: String
    let requestId: String
    let imdbId: String?
    let tmdbId: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let source: String
}

struct StreamPlaybackItem: Identifiable, Codable, Hashable {
    let id: String
    let provider: StreamProvider
    let uri: String
    let headers: [HTTPHeaderField]
    let title: String
    /// Series title for episodes. `title` holds the episode title in that case, so
    /// this is what watch history and Continue Watching display.
    /// Optional so previously cached playback items still decode.
    let showTitle: String?
    let mediaType: StreamMediaType
    let contentKey: String
    let imdbId: String?
    let tmdbId: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    let backdropURL: String?
    let posterURL: String?
    let streamLabel: String?
    let addonId: String?
    let addonName: String?
    let availableStreams: [StremioPlayableStream]
    let externalSubtitles: [StremioSubtitleCandidate]
    let resumePositionMs: Int?
}

struct CachedPlaybackSource: Codable, Hashable {
    let kind: String
    let provider: String
    let contentKey: String
    let playbackItem: StreamPlaybackItem
    let savedAt: Date
    let expiresAt: Date
}

struct ResumeState: Codable, Hashable {
    let contentKey: String
    let positionMs: Int
    let durationMs: Int
    let updatedAt: Date
}

// MARK: - Local Library

/// A watched title, stored on this Mac. Carries enough metadata to render a
/// Continue Watching card without a Plex server or any linked account.
/// Kept separate from `ResumeState` so existing stored resume blobs keep decoding.
struct WatchHistoryEntry: Codable, Hashable, Identifiable {
    var id: String { contentKey }

    let contentKey: String
    let mediaType: StreamMediaType
    /// Movie title, or the series title for episodes.
    let title: String
    let episodeTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let imdbId: String?
    let tmdbId: Int?
    let posterURL: String?
    let backdropURL: String?
    let positionMs: Int
    let durationMs: Int
    let updatedAt: Date

    /// Navigable id for the details screen. Episodes point at their series.
    var mediaItemId: String? {
        guard let tmdbId else { return nil }
        return mediaType == .movie ? "tmdb:movie:\(tmdbId)" : "tmdb:tv:\(tmdbId)"
    }
}

/// A watchlist entry stored on this Mac, so My List works with no Plex and no Trakt.
struct LocalWatchlistEntry: Codable, Hashable, Identifiable {
    /// Canonical media id, e.g. `tmdb:movie:123`.
    let id: String
    let title: String
    /// "movie" or "show", matching MediaItem.type.
    let type: String
    let posterURL: String?
    let backdropURL: String?
    let year: Int?
    let imdbId: String?
    let tmdbId: Int?
    let addedAt: Date
}
