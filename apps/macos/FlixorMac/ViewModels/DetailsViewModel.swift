//
//  DetailsViewModel.swift
//  FlixorMac
//
//  ViewModel for Details page (web-parity subset)
//

import Foundation
import SwiftUI
import FlixorKit

@MainActor
class DetailsViewModel: ObservableObject {
    // API Client
    let api = APIClient.shared

    // Core
    @Published var isLoading = false
    @Published var error: String?

    // Metadata
    @Published var title: String = ""
    @Published var overview: String = ""
    @Published var year: String?
    @Published var editionTitle: String?
    @Published var runtime: Int?
    @Published var rating: String?
    @Published var genres: [String] = []
    @Published var badges: [String] = []
    @Published var moodTags: [String] = []

    // Media and visual
    @Published var logoURL: URL?
    @Published var backdropURL: URL?
    @Published var posterURL: URL?

    // Cast
    struct Person: Identifiable { let id: String; let name: String; let role: String?; let profile: URL? }
    struct CrewPerson: Identifiable { let id: String; let name: String; let job: String?; let profile: URL? }
    @Published var cast: [Person] = []
    @Published var crew: [CrewPerson] = []
    @Published var directors: [String] = []
    @Published var writers: [String] = []
    @Published var showAllCast: Bool = false
    var castShort: [Person] { Array(cast.prefix(4)) }
    var castMoreCount: Int { max(0, cast.count - 4) }

    // Rows
    @Published var related: [MediaItem] = []
    @Published var similar: [MediaItem] = []
    @Published var relatedBrowseContext: BrowseContext?
    @Published var similarBrowseContext: BrowseContext?
    // Episodes & Seasons
    @Published var seasons: [Season] = []
    @Published var selectedSeasonKey: String? = nil
    @Published var episodes: [Episode] = []
    @Published var episodesLoading: Bool = false
    @Published var onDeck: Episode?
    // Extras (trailers)
    @Published var extras: [Extra] = []
    // Versions / tracks
    @Published var versions: [VersionDetail] = []
    @Published var activeVersionId: String?
    @Published var audioTracks: [Track] = []
    @Published var subtitleTracks: [Track] = []
    @Published var externalRatings: ExternalRatings?
    @Published var plexRatingKey: String?
    @Published var plexGuid: String?

    // Context
    @Published var tmdbId: String?
    @Published var imdbId: String?
    @Published var mediaKind: String? // "movie" or "tv"
    @Published var playableId: String? // plex:<ratingKey> only

    // MDBList ratings
    @Published var mdblistRatings: MDBListRatings?

    // TMDB Trailers (videos)
    @Published var trailers: [Trailer] = []

    // Extended TMDB Info (for Details tab - matching mobile app)
    @Published var tagline: String?
    @Published var status: String?
    @Published var releaseDate: String?
    @Published var firstAirDate: String?
    @Published var lastAirDate: String?
    @Published var budget: Int?
    @Published var revenue: Int?
    @Published var originalLanguage: String?
    @Published var numberOfSeasons: Int?
    @Published var numberOfEpisodes: Int?
    @Published var creators: [String] = []

    // Production Companies / Networks
    struct ProductionCompany: Identifiable {
        let id: Int
        let name: String
        let logoURL: URL?
    }
    @Published var productionCompanies: [ProductionCompany] = []
    @Published var networks: [ProductionCompany] = []

    // Plex Collections
    @Published var collections: [String] = []

    // Studio
    @Published var studio: String?

    // Overseerr request status
    @Published var overseerrStatus: OverseerrMediaStatus?


    // Season-specific state
    @Published var isSeason: Bool = false           // Flag for season-only mode
    @Published var parentShowKey: String?           // Link to parent show
    @Published var episodeCount: Int?               // Total episodes
    @Published var watchedCount: Int?               // Watched episodes
    @Published var currentSeasonNumber: Int?        // Current season number for TMDB fallback

    // Episode-specific state
    @Published var isEpisode: Bool = false          // Flag for episode-only mode
    @Published var episodeNumber: Int?              // Episode number in season
    @Published var seasonNumber: Int?               // Season number
    @Published var showTitle: String?               // Parent show title
    @Published var showRatingKey: String?           // Parent show's Plex rating key
    @Published var episodeTitle: String?            // Original episode title (without show context)
    @Published var airDate: String?                 // Original air date
    @Published var tmdbRating: Double?              // TMDB vote average
    @Published var plexImdbRating: Double?          // Direct IMDb rating from Plex (fallback)
    @Published var plexAudienceRating: Int?         // Direct RT Audience rating from Plex (fallback)
    @Published var guestStars: [Person] = []        // Guest stars from TMDB
    @Published var episodeDirector: String?         // Episode director
    @Published var episodeWriter: String?           // Episode writer

    var lastFetchedRatingsKey: String?
    var lastLoadedItemId: String?

    struct ExternalRatings {
        struct IMDb { let score: Double?; let votes: Int? }
        struct RottenTomatoes { let critic: Int?; let audience: Int? }
        let imdb: IMDb?
        let rottenTomatoes: RottenTomatoes?
    }

    struct PlexTag: Codable { let tag: String? }
    struct PlexRole: Codable { let tag: String?; let thumb: String? }
    struct PlexGuid: Codable { let id: String? }
    struct PlexMedia: Codable {
        let id: String?  // Can be Int or String from different Plex APIs
        let width: Int?
        let height: Int?
        let duration: Int?
        let bitrate: Int?
        let videoCodec: String?
        let videoProfile: String?
        let audioChannels: Int?
        let audioCodec: String?
        let audioProfile: String?
        let container: String?
        let editionTitle: String?  // Edition title (e.g., "Director's Cut")
        let Part: [PlexPart]?
    }
    struct PlexPart: Codable {
        let id: String?  // Can be Int or String from different Plex APIs
        let size: Int?
        let key: String?
        let file: String?  // File path for edition parsing
        let Stream: [PlexStream]?
    }
    struct PlexStream: Codable {
        let id: String?  // Can be Int or String from different Plex APIs
        let streamType: Int?
        let displayTitle: String?
        let language: String?
        let languageTag: String?
    }
    struct PlexRating: Codable {
        let image: String?
        let value: Double?
        let type: String?
    }

    struct PlexMeta: Codable {
        let ratingKey: String?
        let type: String?
        let title: String?
        let summary: String?
        let year: Int?
        let contentRating: String?
        let duration: Int?
        let thumb: String?
        let art: String?
        let Guid: [PlexGuid]?
        let Genre: [PlexTag]?
        let Role: [PlexRole]?
        let Media: [PlexMedia]?
        let Collection: [PlexTag]?       // Plex collections
        let studio: String?              // Studio name

        // Ratings from Plex metadata
        let Rating: [PlexRating]?
        let rating: Double?           // IMDb fallback
        let audienceRating: Double?   // RT Audience fallback

        // Season-specific fields
        let parentRatingKey: String?     // Parent show/season
        let parentTitle: String?          // Show/season name
        let index: Int?                   // Season/episode number
        let leafCount: Int?               // Episode count
        let viewedLeafCount: Int?         // Watched count
        let key: String?                  // Children endpoint

        // Episode-specific fields
        let parentIndex: Int?             // Season number (for episodes)
        let grandparentRatingKey: String? // Show's rating key (for episodes)
        let grandparentTitle: String?     // Show title (for episodes)
        let grandparentThumb: String?     // Show poster (for episodes)
        let grandparentArt: String?       // Show backdrop (for episodes)
        let originallyAvailableAt: String? // Air date
    }

    // MARK: - Seasons / Episodes
    struct Season: Identifiable { let id: String; let title: String; let source: String; let number: Int? } // source: plex/tmdb
    struct Episode: Identifiable { let id: String; let title: String; let overview: String?; let image: URL?; let durationMin: Int?; let progressPct: Int?; let viewOffset: Int?; let seasonNumber: Int?; let episodeNumber: Int? }
    struct Extra: Identifiable { let id: String; let title: String; let image: URL?; let durationMin: Int? }
    struct Track: Identifiable { let id: String; let name: String; let language: String? }
    struct VersionDetail: Identifiable {
        struct TechnicalInfo {
            let resolution: String?
            let videoCodec: String?
            let videoProfile: String?
            let videoDisplayTitle: String?  // From video stream displayTitle
            let audioCodec: String?
            let audioChannels: Int?
            let bitrate: Int?
            let fileSizeMB: Double?
            let durationMin: Int?
            let subtitleCount: Int?
            let container: String?

            /// Detects HDR format from video profile and displayTitle
            var hdrFormat: String? {
                let profile = (videoProfile ?? "").lowercased()
                let displayTitle = (videoDisplayTitle ?? "").lowercased()

                // Check both profile and displayTitle for Dolby Vision
                if profile.contains("dolby vision") || profile.contains("dovi") ||
                   displayTitle.contains("dolby vision") || displayTitle.contains("dovi") || displayTitle.contains(" dv") {
                    return "Dolby Vision"
                }

                // Check for HDR variants
                if profile.contains("hdr10+") || displayTitle.contains("hdr10+") {
                    return "HDR10+"
                }
                if profile.contains("hdr10") || profile.contains("hdr 10") ||
                   displayTitle.contains("hdr10") || displayTitle.contains("hdr 10") {
                    return "HDR10"
                }
                if profile.contains("hlg") || displayTitle.contains("hlg") {
                    return "HLG"
                }
                // Generic HDR detection
                if profile.contains("hdr") || displayTitle.contains("hdr") ||
                   profile.contains("main 10") || profile.contains("main10") ||
                   profile.contains("pq") || profile.contains("smpte2084") {
                    return "HDR"
                }
                return nil
            }
        }
        let id: String
        let label: String
        let technical: TechnicalInfo
        let audioTracks: [Track]
        let subtitleTracks: [Track]
    }

    var activeVersionDetail: VersionDetail? {
        if let active = versions.first(where: { $0.id == activeVersionId }) { return active }
        return versions.first
    }
}
