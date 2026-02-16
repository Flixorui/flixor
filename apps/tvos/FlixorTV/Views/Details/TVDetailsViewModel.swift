//
//  TVDetailsViewModel.swift
//  FlixorTV
//
//  ViewModel for Details page (ported from macOS)
//

import Foundation
import SwiftUI
import FlixorKit

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private enum FlexibleStringID {
    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> String? {
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        return nil
    }
}

@MainActor
class TVDetailsViewModel: ObservableObject {
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
    @Published var directors: [String] = []
    @Published var writers: [String] = []
    @Published var imdbId: String?
    @Published var studio: String?
    @Published var collections: [String] = []
    @Published var tmdbRating: Double?
    @Published var plexImdbRating: Double?
    @Published var plexAudienceRating: Int?

    // Media and visual
    @Published var logoURL: URL?
    @Published var backdropURL: URL?
    @Published var posterURL: URL?
    private var rawBackdropURL: String? // Unproxied URL for ultrablur API

    // Cast
    struct Person: Identifiable { let id: String; let name: String; let role: String?; let profile: URL? }
    struct CrewPerson: Identifiable { let id: String; let name: String; let job: String?; let profile: URL? }
    struct ProductionCompany: Identifiable {
        let id: Int
        let name: String
        let logoURL: URL?
    }
    @Published var cast: [Person] = []
    @Published var crew: [CrewPerson] = []
    @Published var guestStars: [Person] = []
    @Published var productionCompanies: [ProductionCompany] = []
    @Published var networks: [ProductionCompany] = []
    @Published var showAllCast: Bool = false
    var castShort: [Person] { Array(cast.prefix(4)) }
    var castMoreCount: Int { max(0, cast.count - 4) }

    // Rows
    @Published var related: [MediaItem] = []
    @Published var similar: [MediaItem] = []
    // TODO: Phase 3B - uncomment when BrowseContext is ported
    // @Published var relatedBrowseContext: BrowseContext?
    // @Published var similarBrowseContext: BrowseContext?
    // Episodes & Seasons
    @Published var seasons: [Season] = []
    @Published var selectedSeasonKey: String? = nil
    @Published var episodes: [Episode] = []
    @Published var episodesLoading: Bool = false
    @Published var onDeck: Episode?
    // Extras (trailers)
    @Published var extras: [Extra] = []
    @Published var trailers: [TVTrailer] = []
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
    @Published var mediaKind: String? // "movie" or "tv"
    @Published var playableId: String? // plex:... or mapped id

    // Season-specific state
    @Published var isSeason: Bool = false           // Flag for season-only mode
    @Published var isEpisode: Bool = false          // Flag for episode-only mode
    @Published var parentShowKey: String?           // Link to parent show
    @Published var episodeCount: Int?               // Total episodes
    @Published var watchedCount: Int?               // Watched episodes
    @Published var seasonNumber: Int?
    @Published var episodeNumber: Int?
    @Published var showTitle: String?
    @Published var showRatingKey: String?
    @Published var episodeTitle: String?
    @Published var airDate: String?
    @Published var episodeDirector: String?
    @Published var episodeWriter: String?

    // UltraBlur background colors
    @Published var ultraBlurColors: UltraBlurColors?

    private let api = APIClient.shared
    private var lastFetchedRatingsKey: String?
    private var ultraBlurCache: [String: UltraBlurColors] = [:]
    private var ultraBlurTask: Task<Void, Never>?

    func fetchUltraBlurColors() async {
        guard let rawURL = rawBackdropURL ?? backdropURL?.absoluteString else {
            return
        }
        if let cached = ultraBlurCache[rawURL] {
            ultraBlurColors = cached
            return
        }
        ultraBlurTask?.cancel()
        ultraBlurTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            if let colors = try? await api.getUltraBlurColors(imageUrl: rawURL) {
                guard !Task.isCancelled else { return }
                ultraBlurCache[rawURL] = colors
                ultraBlurColors = colors
            }
        }
    }

    struct ExternalRatings {
        struct IMDb { let score: Double?; let votes: Int? }
        struct RottenTomatoes { let critic: Int?; let audience: Int? }
        let imdb: IMDb?
        let rottenTomatoes: RottenTomatoes?
    }
    
    struct PlexTag: Codable { let tag: String? }
    struct PlexRole: Codable { let tag: String?; let thumb: String? }
    struct PlexGuid: Codable { let id: String? }
    struct PlexRating: Codable {
        let image: String?
        let value: Double?
        let type: String?
    }
    struct PlexMedia: Decodable {
        let id: String?
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
        let Part: [PlexPart]?

        private enum CodingKeys: String, CodingKey {
            case id, width, height, duration, bitrate, videoCodec, videoProfile, audioChannels, audioCodec, audioProfile, container, Part
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = FlexibleStringID.decode(container, forKey: .id)
            width = try container.decodeIfPresent(Int.self, forKey: .width)
            height = try container.decodeIfPresent(Int.self, forKey: .height)
            duration = try container.decodeIfPresent(Int.self, forKey: .duration)
            bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
            videoCodec = try container.decodeIfPresent(String.self, forKey: .videoCodec)
            videoProfile = try container.decodeIfPresent(String.self, forKey: .videoProfile)
            audioChannels = try container.decodeIfPresent(Int.self, forKey: .audioChannels)
            audioCodec = try container.decodeIfPresent(String.self, forKey: .audioCodec)
            audioProfile = try container.decodeIfPresent(String.self, forKey: .audioProfile)
            self.container = try container.decodeIfPresent(String.self, forKey: .container)
            Part = try container.decodeIfPresent([PlexPart].self, forKey: .Part)
        }
    }
    struct PlexPart: Decodable {
        let id: String?
        let size: Int?
        let key: String?
        let file: String?
        let Stream: [PlexStream]?

        private enum CodingKeys: String, CodingKey {
            case id, size, key, file, Stream
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = FlexibleStringID.decode(container, forKey: .id)
            size = try container.decodeIfPresent(Int.self, forKey: .size)
            key = try container.decodeIfPresent(String.self, forKey: .key)
            file = try container.decodeIfPresent(String.self, forKey: .file)
            Stream = try container.decodeIfPresent([PlexStream].self, forKey: .Stream)
        }
    }
    struct PlexStream: Decodable {
        let id: String?
        let streamType: Int?
        let displayTitle: String?
        let language: String?
        let languageTag: String?

        private enum CodingKeys: String, CodingKey {
            case id, streamType, displayTitle, language, languageTag
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = FlexibleStringID.decode(container, forKey: .id)
            streamType = try container.decodeIfPresent(Int.self, forKey: .streamType)
            displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
            language = try container.decodeIfPresent(String.self, forKey: .language)
            languageTag = try container.decodeIfPresent(String.self, forKey: .languageTag)
        }
    }
    struct PlexMeta: Decodable {
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
        let Collection: [PlexTag]?
        let studio: String?
        let Rating: [PlexRating]?
        let rating: Double?
        let audienceRating: Double?

        // Season-specific fields
        let parentRatingKey: String?     // Parent show
        let parentTitle: String?          // Show name
        let index: Int?                   // Season number
        let leafCount: Int?               // Episode count
        let viewedLeafCount: Int?         // Watched count
        let key: String?                  // Children endpoint
        let parentIndex: Int?
        let grandparentRatingKey: String?
        let grandparentTitle: String?
        let grandparentThumb: String?
        let grandparentArt: String?
        let originallyAvailableAt: String?
    }

    func load(for item: MediaItem) async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        error = nil
        badges = []
        externalRatings = nil
        lastFetchedRatingsKey = nil
        tmdbId = nil
        imdbId = nil
        mediaKind = nil
        playableId = nil
        logoURL = nil
        posterURL = nil
        backdropURL = nil
        rawBackdropURL = nil
        ultraBlurColors = nil
        cast = []
        crew = []
        guestStars = []
        moodTags = []
        related = []
        similar = []
        // TODO: Phase 3B - uncomment when BrowseContext is ported
        // relatedBrowseContext = nil
        // similarBrowseContext = nil
        seasons = []
        selectedSeasonKey = nil
        episodes = []
        onDeck = nil
        extras = []
        trailers = []
        versions = []
        activeVersionId = nil
        audioTracks = []
        subtitleTracks = []
        plexRatingKey = nil
        plexGuid = nil
        isSeason = false
        isEpisode = false
        parentShowKey = nil
        episodeCount = nil
        watchedCount = nil
        seasonNumber = nil
        episodeNumber = nil
        showTitle = nil
        showRatingKey = nil
        episodeTitle = nil
        airDate = nil
        episodeDirector = nil
        episodeWriter = nil
        tagline = nil
        status = nil
        releaseDate = nil
        firstAirDate = nil
        lastAirDate = nil
        budget = nil
        revenue = nil
        originalLanguage = nil
        numberOfSeasons = nil
        numberOfEpisodes = nil
        creators = []
        directors = []
        writers = []
        productionCompanies = []
        networks = []
        studio = nil
        collections = []
        tmdbRating = nil
        plexImdbRating = nil
        plexAudienceRating = nil
        editionTitle = nil


        do {
            if item.id.hasPrefix("tmdb:") {
                let parts = item.id.split(separator: ":")
                if parts.count == 3 {
                    let media = (parts[1] == "movie") ? "movie" : "tv"
                    let tid = String(parts[2])
                    mediaKind = media
                    tmdbId = tid
                    try await fetchTMDBDetails(media: media, id: tid, skipPlexMapping: false)
                }
            } else {
                let isPrefixed = item.id.hasPrefix("plex:")
                let rk = isPrefixed ? String(item.id.dropFirst(5)) : item.id
                do {
                    try await loadPlexMetadata(ratingKey: rk, fallbackItem: item)
                } catch {
                    throw error
                }
            }

            // Fetch UltraBlur colors after all data is loaded
            await fetchUltraBlurColors()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPlexMetadata(ratingKey rk: String, fallbackItem item: MediaItem) async throws {
        let meta: PlexMeta = try await api.get("/api/plex/metadata/\(rk)")

        // Check if type is season
        if meta.type == "season" {
            await loadSeasonDirect(meta: meta, ratingKey: rk)
            return
        }

        // Check if type is episode
        if meta.type == "episode" {
            await loadEpisodeDirect(meta: meta, ratingKey: rk)
            return
        }

        mediaKind = (meta.type == "movie") ? "movie" : "tv"
        title = meta.title ?? item.title
        overview = meta.summary ?? ""
        if let y = meta.year { year = String(y) } else { year = nil }
        rating = meta.contentRating
        if let ms = meta.duration { runtime = Int(ms/60000) } else { runtime = nil }
        if meta.type != "movie" {
            episodeCount = meta.leafCount
        }
        let gs = (meta.Genre ?? []).compactMap { $0.tag }.filter { !$0.isEmpty }
        if !gs.isEmpty {
            genres = gs
            moodTags = deriveTags(from: gs)
        } else {
            genres = []
            moodTags = []
        }
        if let roles = meta.Role, !roles.isEmpty {
            cast = roles.prefix(12).map { r in
                let name = r.tag ?? ""
                return Person(id: name, name: name, role: nil, profile: ImageService.shared.plexImageURL(path: r.thumb, width: 200, height: 200))
            }
        }
        if let art = meta.art,
           let u = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) {
            backdropURL = u
            rawBackdropURL = u.absoluteString
        }
        if let thumb = meta.thumb,
           let u = ImageService.shared.plexImageURL(path: thumb, width: 600, height: 900) {
            posterURL = u
        }
        if let media = meta.Media, !media.isEmpty {
            appendTechnicalBadges(from: media)
            hydrateVersions(from: media)
            extractEditionTitle(from: media)
        }
        collections = (meta.Collection ?? []).compactMap { $0.tag }.filter { !$0.isEmpty }
        studio = meta.studio
        parseRatingsFromPlexMeta(meta)
        extractImdbId(from: meta.Guid)
        addBadge("Plex")
        plexRatingKey = rk
        playableId = "plex:\(rk)"
        await fetchExternalRatings(ratingKey: rk)

        // If we have a TMDB GUID, fetch TMDB enhancements (logo, recommendations)
        // but DON'T try to map back to Plex (we already have it!)
        if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { s in s.contains("tmdb://") || s.contains("themoviedb://") }),
           let tid = tm.components(separatedBy: "://").last {
            tmdbId = tid
            plexGuid = tm
            try await fetchTMDBDetails(media: mediaKind ?? "movie", id: tid, skipPlexMapping: true)
        }

        if trailers.isEmpty {
            await loadTMDBTrailers()
        }

        await loadPlexExtras(ratingKey: rk)

        // Load seasons/episodes for TV shows
        if mediaKind == "tv" {
            await loadSeasonsAndEpisodes()
        }
    }

    private func fetchTMDBDetails(media: String, id: String, skipPlexMapping: Bool = false) async throws {
        // Details
        struct TDetails: Codable {
            let title: String?
            let name: String?
            let overview: String?
            let backdrop_path: String?
            let poster_path: String?
            let release_date: String?
            let first_air_date: String?
            let last_air_date: String?
            let genres: [TGenre]?
            let runtime: Int?
            let episode_run_time: [Int]?
            let adult: Bool?
            let tagline: String?
            let status: String?
            let budget: Int?
            let revenue: Int?
            let original_language: String?
            let number_of_seasons: Int?
            let number_of_episodes: Int?
            let production_companies: [TProductionCompany]?
            let networks: [TProductionCompany]?
            let created_by: [TCreator]?
            let vote_average: Double?
        }
        struct TGenre: Codable { let name: String }
        struct TProductionCompany: Codable { let id: Int?; let name: String?; let logo_path: String? }
        struct TCreator: Codable { let name: String? }
        let d: TDetails = try await api.get("/api/tmdb/\(media)/\(id)")
        self.title = d.title ?? d.name ?? self.title
        self.overview = d.overview ?? self.overview
        // Store raw TMDB URL for ultrablur API
        if let path = d.backdrop_path {
            self.rawBackdropURL = "https://image.tmdb.org/t/p/original\(path)"
        }
        self.backdropURL = ImageService.shared.proxyImageURL(url: d.backdrop_path.flatMap { "https://image.tmdb.org/t/p/original\($0)" })
        self.posterURL = ImageService.shared.proxyImageURL(url: d.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" })
        if let y = (d.release_date ?? d.first_air_date)?.prefix(4) { self.year = String(y) }
        self.genres = (d.genres ?? []).map { $0.name }
        self.moodTags = deriveTags(from: self.genres)
        let rt = d.runtime ?? d.episode_run_time?.first
        self.runtime = rt
        self.rating = (d.adult ?? false) ? "18+" : self.rating
        self.tagline = d.tagline?.isEmpty == false ? d.tagline : nil
        self.status = d.status
        self.releaseDate = d.release_date
        self.firstAirDate = d.first_air_date
        self.lastAirDate = d.last_air_date
        self.budget = (d.budget ?? 0) > 0 ? d.budget : nil
        self.revenue = (d.revenue ?? 0) > 0 ? d.revenue : nil
        self.originalLanguage = d.original_language
        self.numberOfSeasons = d.number_of_seasons
        self.numberOfEpisodes = d.number_of_episodes
        self.creators = (d.created_by ?? []).compactMap { $0.name }
        self.tmdbRating = (d.vote_average ?? 0) > 0 ? d.vote_average : nil

        // Images (logo preferred en)
        struct TImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }
        struct TImages: Codable { let logos: [TImage]?; let backdrops: [TImage]? }
        let imgs: TImages = try await api.get("/api/tmdb/\(media)/\(id)/images", queryItems: [URLQueryItem(name: "include_image_language", value: "en,hi,ja,ko,zh,es,fr,de,pt,it,ru,ar,null")])
        if let logo = (imgs.logos ?? []).first(where: { $0.iso_639_1 == "en" }) ?? (imgs.logos ?? []).first(where: { ($0.iso_639_1 ?? "").isEmpty }) ?? imgs.logos?.first,
           let p = logo.file_path {
            self.logoURL = ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w500\(p)")
        }

        // Credits (cast top 12)
        struct TCast: Codable { let id: Int?; let name: String?; let character: String?; let profile_path: String? }
        struct TCrew: Codable { let id: Int?; let name: String?; let job: String?; let department: String?; let profile_path: String? }
        struct TCredits: Codable { let cast: [TCast]?; let crew: [TCrew]? }
        let cr: TCredits = try await api.get("/api/tmdb/\(media)/\(id)/credits")
        self.cast = (cr.cast ?? []).prefix(12).map { c in
            Person(id: String(c.id ?? 0), name: c.name ?? "", role: c.character, profile: ImageService.shared.proxyImageURL(url: c.profile_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }))
        }
        self.crew = (cr.crew ?? []).prefix(12).map { x in
            CrewPerson(id: String(x.id ?? 0), name: x.name ?? "", job: x.job, profile: ImageService.shared.proxyImageURL(url: x.profile_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }))
        }
        let allCrew = cr.crew ?? []
        self.directors = allCrew
            .filter { ($0.job?.lowercased() ?? "").contains("director") && ($0.department?.lowercased() ?? "") == "directing" }
            .compactMap { $0.name }
            .removingDuplicates()
        self.writers = allCrew
            .filter {
                let job = ($0.job?.lowercased() ?? "")
                return job.contains("writer") || job.contains("screenplay") || job.contains("story")
            }
            .compactMap { $0.name }
            .removingDuplicates()

        self.productionCompanies = (d.production_companies ?? []).compactMap { company in
            guard let id = company.id, let name = company.name, !name.isEmpty else { return nil }
            let logo = company.logo_path.flatMap { ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w185\($0)") }
            return ProductionCompany(id: id, name: name, logoURL: logo)
        }
        self.networks = (d.networks ?? []).compactMap { network in
            guard let id = network.id, let name = network.name, !name.isEmpty else { return nil }
            let logo = network.logo_path.flatMap { ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w185\($0)") }
            return ProductionCompany(id: id, name: name, logoURL: logo)
        }

        struct ExternalIDs: Codable {
            let imdb_id: String?
        }
        if let ext: ExternalIDs = try? await api.get("/api/tmdb/\(media)/\(id)/external_ids"),
           let imdb = ext.imdb_id,
           !imdb.isEmpty {
            imdbId = imdb
        }

        // Recommendations + Similar (rows)
        struct TRes: Codable { let results: [TResItem]? }
        struct TResItem: Codable { let id: Int?; let title: String?; let name: String?; let backdrop_path: String?; let poster_path: String? }
        let recs: TRes = try await api.get("/api/tmdb/\(media)/\(id)/recommendations")
        let sim: TRes = try await api.get("/api/tmdb/\(media)/\(id)/similar")
        self.related = (recs.results ?? []).prefix(12).map { i in
            MediaItem(
                id: "tmdb:\(media):\(i.id ?? 0)",
                title: i.title ?? i.name ?? "",
                type: media == "movie" ? "movie" : "show",
                thumb: i.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                art: i.backdrop_path.map { "https://image.tmdb.org/t/p/w780\($0)" },
                year: nil,
                rating: nil,
                duration: nil,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil,
                parentRatingKey: nil,
                parentTitle: nil,
                leafCount: nil,
                viewedLeafCount: nil
            )
        }
        self.similar = (sim.results ?? []).prefix(12).map { i in
            MediaItem(
                id: "tmdb:\(media):\(i.id ?? 0)",
                title: i.title ?? i.name ?? "",
                type: media == "movie" ? "movie" : "show",
                thumb: i.poster_path.map { "https://image.tmdb.org/t/p/w500\($0)" },
                art: i.backdrop_path.map { "https://image.tmdb.org/t/p/w780\($0)" },
                year: nil,
                rating: nil,
                duration: nil,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil,
                parentRatingKey: nil,
                parentTitle: nil,
                leafCount: nil,
                viewedLeafCount: nil
            )
        }
        // TODO: Phase 3B - uncomment when BrowseContext is ported
        // let mediaType: TMDBMediaType = (media == "movie") ? .movie : .tv
        // self.relatedBrowseContext = .tmdb(kind: .recommendations, media: mediaType, id: id, displayTitle: self.title)
        // self.similarBrowseContext = .tmdb(kind: .similar, media: mediaType, id: id, displayTitle: self.title)

        await loadTMDBTrailers()

        // Attempt Plex source mapping (GUIDs + external IDs + title search)
        // Skip if we already have Plex data (native Plex items requesting TMDB enhancements)
        if !skipPlexMapping {
            do {
                try await self.mapToPlex(media: media, tmdbId: id, title: self.title, year: self.year)
            } catch {
                // If mapping fails, surface "No local source" badge for clarity
                self.addBadge("No local source")
            }
        } else {
        }

        // Load seasons/episodes
        if media == "tv" {
            await self.loadSeasonsAndEpisodes()
        }
    }

    // MARK: - TMDB -> Plex mapping (web parity)
    private func mapToPlex(media: String, tmdbId: String, title: String, year: String?) async throws {

        // First: Title search (as requested)
        struct SearchResponse: Decodable {
            let MediaContainer: SearchContainer?
            let Metadata: [SearchItem]?

            init(from decoder: Decoder) throws {
                // First, try to decode as a plain array (some call paths return this shape)
                if let array = try? decoder.singleValueContainer().decode([SearchItem].self) {
                    self.MediaContainer = nil
                    self.Metadata = array
                    return
                }

                // Otherwise, decode as a dictionary with MediaContainer or Metadata fields
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let mc = try? container.decode(SearchContainer.self, forKey: .MediaContainer) {
                    self.MediaContainer = mc
                } else {
                    self.MediaContainer = nil
                }
                if let array = try? container.decode([SearchItem].self, forKey: .Metadata) {
                    self.Metadata = array
                } else if let single = try? container.decode(SearchItem.self, forKey: .Metadata) {
                    self.Metadata = [single]
                } else {
                    self.Metadata = nil
                }
            }
            private enum CodingKeys: String, CodingKey { case MediaContainer, Metadata }
        }
        struct SearchContainer: Decodable {
            let Metadata: [SearchItem]

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let items = try? container.decode([SearchItem].self, forKey: .Metadata) {
                    self.Metadata = items
                } else if let single = try? container.decode(SearchItem.self, forKey: .Metadata) {
                    self.Metadata = [single]
                } else {
                    self.Metadata = []
                }
            }

            private enum CodingKeys: String, CodingKey { case Metadata }
        }
        struct SearchItem: Decodable {
            let ratingKey: String
            let title: String?
            let grandparentTitle: String?
            let year: Int?
            let summary: String?
            let art: String?
            let thumb: String?
            let parentThumb: String?
            let grandparentThumb: String?
            let type: String?
            let Guid: [PlexGuid]?
            let Media: [PlexMedia]?
            let Role: [PlexRole]?
        }

        let t = (media == "movie") ? 1 : 2
        var candidates: [SearchItem] = []
        do {
            let res: SearchResponse = try await api.get("/api/plex/search", queryItems: [URLQueryItem(name: "query", value: title), URLQueryItem(name: "type", value: String(t))])
            let merged = (res.MediaContainer?.Metadata ?? []) + (res.Metadata ?? [])
            if !merged.isEmpty {
                var seen = Set<String>()
                candidates = merged.filter { seen.insert($0.ratingKey).inserted }
            } else {
            }
        } catch {
        }

        func norm(_ s: String) -> String { s.lowercased().replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression) }
        func score(_ it: SearchItem) -> Int {
            let ht = norm(it.title ?? it.grandparentTitle ?? "")
            let qt = norm(title)
            var s = 0
            if ht == qt { s += 100 } else if ht.contains(qt) || qt.contains(ht) { s += 60 }
            if let y = year, let iy = it.year, String(iy) == y { s += 30 }
            if let kind = it.type?.lowercased() {
                if media == "movie" && kind.contains("movie") { s += 20 }
                if media == "tv" && (kind.contains("show") || kind.contains("episode")) { s += 20 }
            }
            return s
        }
        // Gather GUID-based matches and merge into candidates for scoring
        var pool = candidates
        // Build GUID list
        var guids = ["tmdb://\(tmdbId)", "themoviedb://\(tmdbId)"]
        do {
            struct Ext: Codable { let imdb_id: String?; let tvdb_id: Int? }
            let ex: Ext = try await api.get("/api/tmdb/\(media)/\(tmdbId)/external_ids")
            if let imdb = ex.imdb_id, !imdb.isEmpty { guids.append("imdb://\(imdb)") }
            if media == "tv", let tvdb = ex.tvdb_id { guids.append("tvdb://\(tvdb)") }
        } catch {
        }
        var guidHits: [SearchItem] = []
        for g in guids {
            do {
                let res: SearchResponse = try await api.get("/api/plex/findByGuid", queryItems: [URLQueryItem(name: "guid", value: g), URLQueryItem(name: "type", value: String(t))])
                let matches = res.MediaContainer?.Metadata ?? res.Metadata ?? []
                if !matches.isEmpty {
                    guidHits.append(contentsOf: matches)
                }
            } catch {
            }
        }
        if !guidHits.isEmpty {
            var seen = Set(pool.map { $0.ratingKey })
            for item in guidHits {
                if seen.insert(item.ratingKey).inserted {
                    pool.append(item)
                }
            }
        } else {
        }

        guard !pool.isEmpty else {
            throw NSError(domain: "map", code: 404)
        }

        // Prefer exact TMDB GUID match
        var match: SearchItem? = pool.first(where: { item in
            let guids = item.Guid?.compactMap { $0.id?.lowercased() } ?? []
            return guids.contains("tmdb://\(tmdbId)") || guids.contains("themoviedb://\(tmdbId)")
        })

        if let exactMatch = match {
        }

        // Score-based fallback
        if match == nil {
            var bestScore = -1
            for c in pool {
                let sc = score(c)
                if sc > bestScore {
                    bestScore = sc
                    match = c
                }
            }
            if let scoreMatch = match {
            }
        }

        guard let match = match else {
            throw NSError(domain: "map", code: 404)
        }

        // Update VM with Plex mapping
        let rk = match.ratingKey
        self.playableId = "plex:\(rk)"
        self.plexRatingKey = rk
        if let firstGuid = match.Guid?.compactMap({ $0.id }).first {
            self.plexGuid = firstGuid
        }
        self.addBadge("Plex")
        // Prefer Plex backdrop
        let art = match.art ?? match.thumb ?? match.parentThumb ?? match.grandparentThumb ?? ""
        if let u = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) {
            self.backdropURL = u
            self.rawBackdropURL = u.absoluteString
        }
        if posterURL == nil {
            let poster = match.thumb ?? match.parentThumb ?? match.grandparentThumb
            if let poster = poster,
               let posterURL = ImageService.shared.plexImageURL(path: poster, width: 600, height: 900) {
                self.posterURL = posterURL
            }
        }
        if let matchYear = match.year {
            self.year = String(matchYear)
        }
        if let summary = match.summary, !summary.isEmpty {
            self.overview = summary
        }
        // Prefer Plex cast roles
        if let roles = match.Role, !roles.isEmpty {
            self.cast = roles.prefix(12).map { r in
                let name = r.tag ?? ""
                return Person(id: name, name: name, role: nil, profile: ImageService.shared.plexImageURL(path: r.thumb, width: 200, height: 200))
            }
        }
        // Versions
        if let mediaArr = match.Media {
            appendTechnicalBadges(from: mediaArr)
            hydrateVersions(from: mediaArr)
        } else {
        }
        await fetchExternalRatings(ratingKey: rk)
        await loadPlexExtras(ratingKey: rk)
    }

    private func loadEpisodeDirect(meta: PlexMeta, ratingKey: String) async {
        isEpisode = true
        mediaKind = "tv"

        episodeTitle = meta.title
        title = meta.title ?? "Episode"
        overview = meta.summary ?? ""
        year = meta.year.map(String.init)
        rating = meta.contentRating
        runtime = meta.duration.map { Int($0 / 60000) }
        seasonNumber = meta.parentIndex
        episodeNumber = meta.index
        showTitle = meta.grandparentTitle
        showRatingKey = meta.grandparentRatingKey
        airDate = meta.originallyAvailableAt

        if let art = meta.art ?? meta.grandparentArt,
           let url = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) {
            backdropURL = url
            rawBackdropURL = url.absoluteString
        }
        if let thumb = meta.thumb ?? meta.grandparentThumb,
           let url = ImageService.shared.plexImageURL(path: thumb, width: 600, height: 900) {
            posterURL = url
        }
        if let media = meta.Media, !media.isEmpty {
            appendTechnicalBadges(from: media)
            hydrateVersions(from: media)
            extractEditionTitle(from: media)
        }

        parseRatingsFromPlexMeta(meta)
        extractImdbId(from: meta.Guid)
        addBadge("Plex")
        plexRatingKey = ratingKey
        playableId = "plex:\(ratingKey)"
        await fetchExternalRatings(ratingKey: ratingKey)

        if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = tm.components(separatedBy: "://").last {
            tmdbId = tid
            plexGuid = tm
            do {
                try await fetchTMDBEpisodeEnhancements(tvId: tid, season: meta.parentIndex, episode: meta.index)
            } catch {
            }
        }
    }

    private func fetchTMDBEpisodeEnhancements(tvId: String, season: Int?, episode: Int?) async throws {
        guard let season, let episode else { return }
        struct EpisodeDetails: Codable {
            let name: String?
            let overview: String?
            let air_date: String?
            let crew: [EpisodeCrew]?
            let guest_stars: [EpisodeGuest]?
        }
        struct EpisodeCrew: Codable { let job: String?; let name: String? }
        struct EpisodeGuest: Codable { let id: Int?; let name: String?; let character: String?; let profile_path: String? }
        let details: EpisodeDetails = try await api.get("/api/tmdb/tv/\(tvId)/season/\(season)/episode/\(episode)")
        if let name = details.name, !name.isEmpty {
            title = name
            episodeTitle = name
        }
        if let summary = details.overview, !summary.isEmpty {
            overview = summary
        }
        if let airDate = details.air_date, !airDate.isEmpty {
            self.airDate = airDate
        }
        episodeDirector = details.crew?.first(where: { ($0.job ?? "").localizedCaseInsensitiveContains("director") })?.name
        episodeWriter = details.crew?.first(where: {
            let job = ($0.job ?? "").lowercased()
            return job.contains("writer") || job.contains("screenplay") || job.contains("story")
        })?.name
        guestStars = (details.guest_stars ?? []).prefix(12).map { guest in
            Person(
                id: String(guest.id ?? 0),
                name: guest.name ?? "",
                role: guest.character,
                profile: ImageService.shared.proxyImageURL(url: guest.profile_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" })
            )
        }
    }

    private func extractEditionTitle(from media: [PlexMedia]) {
        guard editionTitle == nil else { return }
        for item in media {
            if let file = item.Part?.first?.file, !file.isEmpty {
                let url = URL(fileURLWithPath: file)
                let fileName = url.deletingPathExtension().lastPathComponent
                let trimmed = fileName.replacingOccurrences(of: ".", with: " ")
                if !trimmed.isEmpty {
                    editionTitle = trimmed
                    return
                }
            }
        }
    }

    private func parseRatingsFromPlexMeta(_ meta: PlexMeta) {
        var imdbScore: Double?
        var rtCritic: Int?
        var rtAudience: Int?

        for rating in (meta.Rating ?? []) {
            let image = (rating.image ?? "").lowercased()
            guard let value = rating.value, value > 0 else { continue }

            if image.contains("imdb://image.rating") || (image.contains("imdb") && image.contains("rating")) {
                imdbScore = value
            } else if image.contains("rottentomatoes://image.rating.ripe")
                || image.contains("rottentomatoes://image.rating.rotten")
                || image.contains("rottentomatoes://image.rating.certified")
                || (image.contains("rottentomatoes") && (image.contains("ripe") || image.contains("rotten") || image.contains("certified"))) {
                rtCritic = Int(value * 10)
            } else if image.contains("rottentomatoes://image.rating.upright")
                || image.contains("rottentomatoes://image.rating.spilled")
                || (image.contains("rottentomatoes") && (image.contains("upright") || image.contains("spilled") || image.contains("audience"))) {
                rtAudience = Int(value * 10)
            }
        }

        if imdbScore == nil, let value = meta.rating, value > 0 {
            imdbScore = value
        }
        if rtAudience == nil, let value = meta.audienceRating, value > 0 {
            rtAudience = Int(round(value * 10))
        }

        plexImdbRating = imdbScore
        plexAudienceRating = rtAudience
        if imdbScore != nil || rtCritic != nil || rtAudience != nil {
            externalRatings = ExternalRatings(
                imdb: imdbScore.map { ExternalRatings.IMDb(score: $0, votes: nil) },
                rottenTomatoes: ExternalRatings.RottenTomatoes(critic: rtCritic, audience: rtAudience)
            )
        }
    }

    private func extractImdbId(from guids: [PlexGuid]?) {
        guard let guids else { return }
        if let imdb = guids.compactMap({ $0.id }).first(where: { $0.hasPrefix("imdb://") }) {
            imdbId = imdb.replacingOccurrences(of: "imdb://", with: "")
        }
    }

    func loadTMDBTrailers() async {
        guard let tid = tmdbId, let media = mediaKind else { return }

        do {
            struct VideosResponse: Codable {
                let results: [VideoResult]?
            }
            struct VideoResult: Codable {
                let id: String?
                let key: String?
                let name: String?
                let site: String?
                let type: String?
                let official: Bool?
                let published_at: String?
            }

            let response: VideosResponse = try await api.get("/api/tmdb/\(media)/\(tid)/videos")
            let videos = (response.results ?? [])
                .filter { ($0.site?.lowercased() ?? "") == "youtube" && ($0.key?.isEmpty == false) }

            let sorted = videos.sorted { a, b in
                let aTrailer = (a.type?.lowercased() ?? "") == "trailer"
                let bTrailer = (b.type?.lowercased() ?? "") == "trailer"
                if aTrailer != bTrailer { return aTrailer }
                let aOfficial = a.official ?? false
                let bOfficial = b.official ?? false
                if aOfficial != bOfficial { return aOfficial }
                return (a.name ?? "") < (b.name ?? "")
            }

            trailers = sorted.prefix(10).compactMap { video in
                guard let key = video.key else { return nil }
                return TVTrailer(
                    id: video.id ?? key,
                    name: video.name ?? "Video",
                    key: key,
                    site: video.site ?? "YouTube",
                    type: video.type ?? "Video",
                    official: video.official,
                    publishedAt: video.published_at
                )
            }
        } catch {
        }
    }

    private func addBadge(_ badge: String) {
        guard !badge.isEmpty else { return }
        if !badges.contains(badge) {
            badges.append(badge)
        }
    }

    private func addBadges(_ list: [String]) {
        for badge in list where !badge.isEmpty {
            addBadge(badge)
        }
    }

    private func appendTechnicalBadges(from media: [PlexMedia]) {
        guard let first = media.first else { return }
        var extra: [String] = []
        let width = first.width ?? 0
        let height = first.height ?? 0
        if width >= 3800 || height >= 2100 {
            extra.append("4K")
        }
        let profile = (first.videoProfile ?? "").lowercased()
        var hasHDR = false
        var hasDV = false

        if profile.contains("dv") || profile.contains("dolby vision") || profile.contains("dovi") {
            hasDV = true
        }
        if profile.contains("hdr") || profile.contains("hlg") || profile.contains("pq")
            || profile.contains("smpte2084") || profile.contains("main 10") || profile.contains("main10") {
            hasHDR = true
        }

        if let part = first.Part?.first, let streams = part.Stream {
            for stream in streams where stream.streamType == 1 {
                let displayTitle = (stream.displayTitle ?? "").lowercased()
                if displayTitle.contains("dolby vision") || displayTitle.contains("dovi") || displayTitle.contains(" dv") {
                    hasDV = true
                }
                if displayTitle.contains("hdr") || displayTitle.contains("hlg") {
                    hasHDR = true
                }
            }
        }

        if hasDV {
            extra.append("Dolby Vision")
        } else if hasHDR {
            extra.append("HDR")
        }

        let audioProfile = (first.audioProfile ?? "").lowercased()
        let audioCodec = (first.audioCodec ?? "").lowercased()
        if audioProfile.contains("atmos") || audioCodec.contains("atmos") || audioCodec.contains("truehd") {
            extra.append("Atmos")
        }
        addBadges(extra)
    }

    private func hydrateVersions(from media: [PlexMedia]) {
        var vds: [VersionDetail] = []
        for (idx, mm) in media.enumerated() {
            let id = mm.id ?? String(idx)
            let width = mm.width ?? 0
            let height = mm.height ?? 0
            let resoLabel: String? = {
                if width >= 3800 || height >= 2100 { return "4K" }
                if width >= 1900 || height >= 1000 { return "1080p" }
                if width >= 1260 || height >= 700 { return "720p" }
                if width > 0 && height > 0 { return "\(width)x\(height)" }
                return nil
            }()
            let vcodec = (mm.videoCodec ?? "").uppercased()
            let ach = mm.audioChannels.map { "\($0)CH" } ?? ""
            let labelParts = [resoLabel, vcodec.isEmpty ? nil : vcodec, ach.isEmpty ? nil : ach].compactMap { $0 }
            let part = mm.Part?.first
            let streams = part?.Stream ?? []
            let audio = streams.enumerated().filter { $0.element.streamType == 2 }.map { offset, stream -> Track in
                let name = stream.displayTitle ?? stream.languageTag ?? stream.language ?? "Audio \(offset + 1)"
                return Track(id: stream.id ?? String(offset), name: name, language: stream.languageTag ?? stream.language)
            }
            let subs = streams.enumerated().filter { $0.element.streamType == 3 }.map { offset, stream -> Track in
                let name = stream.displayTitle ?? stream.languageTag ?? stream.language ?? "Sub \(offset + 1)"
                return Track(id: stream.id ?? String(offset), name: name, language: stream.languageTag ?? stream.language)
            }
            let videoDisplayTitle = streams.first { $0.streamType == 1 }?.displayTitle
            let sizeMB = part?.size.map { Double($0) / (1024.0 * 1024.0) }
            let tech = VersionDetail.TechnicalInfo(
                resolution: (width > 0 && height > 0) ? "\(width)x\(height)" : nil,
                videoCodec: mm.videoCodec,
                videoProfile: mm.videoProfile,
                videoDisplayTitle: videoDisplayTitle,
                audioCodec: mm.audioCodec,
                audioChannels: mm.audioChannels,
                bitrate: mm.bitrate,
                fileSizeMB: sizeMB,
                durationMin: mm.duration.map { Int($0 / 60000) },
                subtitleCount: subs.count,
                container: mm.container
            )
            let label = labelParts.isEmpty ? "Version \(idx + 1)" : labelParts.joined(separator: " ")
            vds.append(VersionDetail(id: id, label: label, technical: tech, audioTracks: audio, subtitleTracks: subs))
        }
        if !vds.isEmpty {
            versions = vds
            if activeVersionId == nil {
                activeVersionId = vds.first?.id
            }
            audioTracks = vds.first?.audioTracks ?? []
            subtitleTracks = vds.first?.subtitleTracks ?? []

            if !subtitleTracks.isEmpty {
                addBadges(["CC"])
            }
            if subtitleTracks.contains(where: { track in
                let name = track.name.uppercased()
                return name.contains("SDH") || name.contains("DEAF") || name.contains("HARD OF HEARING")
            }) {
                addBadges(["SDH"])
            }
            if audioTracks.contains(where: { track in
                let name = track.name.uppercased()
                return name.contains("AUDIO DESC") || name.contains("DESCRIPTIVE") || name.contains(" AD")
            }) {
                addBadges(["AD"])
            }
        } else {
        }
    }

    private func fetchExternalRatings(ratingKey: String) async {
        guard ratingKey != lastFetchedRatingsKey else { return }
        lastFetchedRatingsKey = ratingKey
        struct RatingsResponse: Codable {
            let imdb: IMDb?
            let rottenTomatoes: RottenTomatoes?
            struct IMDb: Codable { let rating: Double?; let votes: Int? }
            struct RottenTomatoes: Codable { let critic: Int?; let audience: Int? }
        }
        do {
            let res: RatingsResponse = try await api.get("/api/plex/ratings/\(ratingKey)")
            let fetchedIMDb = res.imdb.map { ExternalRatings.IMDb(score: $0.rating, votes: $0.votes) }
            let fetchedRT = res.rottenTomatoes.map { ExternalRatings.RottenTomatoes(critic: $0.critic, audience: $0.audience) }

            let mergedIMDb = ExternalRatings.IMDb(
                score: externalRatings?.imdb?.score ?? fetchedIMDb?.score,
                votes: externalRatings?.imdb?.votes ?? fetchedIMDb?.votes
            )
            let mergedRT = ExternalRatings.RottenTomatoes(
                critic: externalRatings?.rottenTomatoes?.critic ?? fetchedRT?.critic,
                audience: externalRatings?.rottenTomatoes?.audience ?? fetchedRT?.audience
            )

            let hasIMDb = mergedIMDb.score != nil || mergedIMDb.votes != nil
            let hasRT = mergedRT.critic != nil || mergedRT.audience != nil
            if hasIMDb || hasRT {
                externalRatings = ExternalRatings(
                    imdb: hasIMDb ? mergedIMDb : nil,
                    rottenTomatoes: hasRT ? mergedRT : nil
                )
            }
        } catch {
        }
    }

    // MARK: - Season Direct Load

    private func loadSeasonDirect(meta: PlexMeta, ratingKey: String) async {

        isSeason = true
        isEpisode = false
        mediaKind = "tv"
        seasonNumber = meta.index

        // Basic metadata
        title = meta.title ?? "Season"
        overview = meta.summary ?? ""
        parentShowKey = meta.parentRatingKey
        episodeCount = meta.leafCount
        watchedCount = meta.viewedLeafCount

        // Parent show title for better context
        if let parentTitle = meta.parentTitle {
            title = "\(parentTitle) - \(meta.title ?? "Season")"
        }

        // Images
        if let thumb = meta.thumb,
           let u = ImageService.shared.plexImageURL(path: thumb, width: 600, height: 900) {
            posterURL = u
        }
        if let art = meta.art,
           let u = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) {
            backdropURL = u
            rawBackdropURL = u.absoluteString
        }

        addBadge("Plex")
        playableId = "plex:\(ratingKey)"
        plexRatingKey = ratingKey

        // TMDB enhancement (optional)
        if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = tm.components(separatedBy: "://").last {
            tmdbId = tid
            plexGuid = tm
            do {
                try await fetchTMDBSeasonEnhancements(tmdbId: tid, seasonNumber: meta.index)
            } catch {
            }
        }

        await loadTMDBTrailers()

        // Load episodes directly (NO season picker)
        seasons = []
        selectedSeasonKey = nil  // Null = season-only mode
        await loadPlexEpisodes(seasonKey: ratingKey)

    }

    // MARK: - TMDB Season Enhancements

    private func fetchTMDBSeasonEnhancements(tmdbId: String, seasonNumber: Int?) async throws {
        guard let num = seasonNumber else { return }

        // Fetch TMDB season details
        struct TMDBSeason: Codable {
            let name: String?
            let overview: String?
            let poster_path: String?
            let episodes: [TMDBEpisode]?
        }
        struct TMDBEpisode: Codable {
            let episode_number: Int
            let name: String
            let overview: String?
            let still_path: String?
        }

        let season: TMDBSeason = try await api.get("/api/tmdb/tv/\(tmdbId)/season/\(num)")

        // Use TMDB data if better
        if let name = season.name, !name.isEmpty {
            title = title.replacingOccurrences(of: "Season \(num)", with: name)
        }
        if let overview = season.overview, !overview.isEmpty {
            self.overview = overview
        }
        if let poster = season.poster_path {
            posterURL = ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w500\(poster)")
        }
    }

    // MARK: - Seasons / Episodes
    struct Season: Identifiable { let id: String; let title: String; let source: String } // source: plex/tmdb
    struct Episode: Identifiable { let id: String; let title: String; let overview: String?; let image: URL?; let durationMin: Int?; let progressPct: Int?; let viewOffset: Int? }
    struct Extra: Identifiable { let id: String; let title: String; let image: URL?; let durationMin: Int? }
    struct Track: Identifiable { let id: String; let name: String; let language: String? }
    struct VersionDetail: Identifiable {
        struct TechnicalInfo {
            let resolution: String?
            let videoCodec: String?
            let videoProfile: String?
            let videoDisplayTitle: String?
            let audioCodec: String?
            let audioChannels: Int?
            let bitrate: Int?
            let fileSizeMB: Double?
            let durationMin: Int?
            let subtitleCount: Int?
            let container: String?

            var hdrFormat: String? {
                let profile = (videoProfile ?? "").lowercased()
                let displayTitle = (videoDisplayTitle ?? "").lowercased()

                if profile.contains("dolby vision") || profile.contains("dovi")
                    || displayTitle.contains("dolby vision") || displayTitle.contains("dovi") || displayTitle.contains(" dv") {
                    return "Dolby Vision"
                }
                if profile.contains("hdr10+") || displayTitle.contains("hdr10+") {
                    return "HDR10+"
                }
                if profile.contains("hdr10") || profile.contains("hdr 10")
                    || displayTitle.contains("hdr10") || displayTitle.contains("hdr 10") {
                    return "HDR10"
                }
                if profile.contains("hlg") || displayTitle.contains("hlg") {
                    return "HLG"
                }
                if profile.contains("hdr") || displayTitle.contains("hdr")
                    || profile.contains("main 10") || profile.contains("main10")
                    || profile.contains("pq") || profile.contains("smpte2084") {
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

    private func loadSeasonsAndEpisodes() async {
        await MainActor.run { self.episodesLoading = true }
        // Prefer Plex if mapped
        if let pid = playableId, pid.hasPrefix("plex:"), let showKey = pid.split(separator: ":").last.map(String.init) {
            await loadPlexSeasons(showKey: showKey)
            if seasons.isEmpty {
                await MainActor.run { self.episodesLoading = false }
            } else {
            }
        } else {
            await loadTMDBSeasons()
        }
    }

    private func loadPlexSeasons(showKey: String) async {
        do {
            // Backend returns MediaContainer directly (not wrapped)
            struct MC: Codable {
                let Metadata: [M]?
                let size: Int?
            }
            struct M: Codable { let ratingKey: String; let title: String }
            let ch: MC = try await api.get("/api/plex/dir/library/metadata/\(showKey)/children")
            let ss = (ch.Metadata ?? []).map { Season(id: $0.ratingKey, title: $0.title, source: "plex") }
            await MainActor.run {
                self.seasons = ss
                self.selectedSeasonKey = ss.first?.id
            }
            await loadPlexEpisodes(seasonKey: ss.first?.id)
            // On Deck
            do {
                let od: MC = try await api.get("/api/plex/dir/library/metadata/\(showKey)/onDeck")
                if let ep = od.Metadata?.first {
                    let image = ImageService.shared.plexImageURL(path: ep.ratingKey, width: 600, height: 338) // best-effort
                    await MainActor.run {
                        self.onDeck = Episode(id: "plex:\(ep.ratingKey)", title: ep.title, overview: nil, image: image, durationMin: nil, progressPct: nil, viewOffset: nil)
                    }
                }
            } catch {}
        } catch {
        }
    }

    private func loadPlexEpisodes(seasonKey: String?) async {
        guard let seasonKey = seasonKey else {
            return
        }
        do {
            // Backend returns MediaContainer directly (not wrapped)
            struct MC: Codable {
                let Metadata: [ME]?
                let size: Int?
            }
            struct ME: Codable { let ratingKey: String; let title: String; let summary: String?; let thumb: String?; let parentThumb: String?; let duration: Int?; let viewOffset: Int?; let viewCount: Int? }
            let ch: MC = try await api.get("/api/plex/dir/library/metadata/\(seasonKey)/children?nocache=\(Date().timeIntervalSince1970)")
            let eps: [Episode] = (ch.Metadata ?? []).map { e in
                let url = ImageService.shared.plexImageURL(path: e.thumb ?? e.parentThumb, width: 600, height: 338)
                let dur = e.duration.map { Int($0/60000) }
                let pct: Int? = {
                    guard let d = e.duration, d > 0 else { return nil }

                    // If fully watched (viewCount > 0 and viewOffset is nil or near end), show 100%
                    if let vc = e.viewCount, vc > 0 {
                        if let o = e.viewOffset {
                            let progress = Double(o) / Double(d)
                            // If within last 2% or viewOffset is very small, treat as fully watched
                            if progress < 0.02 {
                                return 100
                            }
                            return Int(round(progress * 100))
                        } else {
                            // viewCount > 0 but no viewOffset = fully watched
                            return 100
                        }
                    }

                    // Partially watched - calculate from viewOffset
                    guard let o = e.viewOffset else { return nil }
                    return Int(round((Double(o)/Double(d))*100))
                }()
                return Episode(id: "plex:\(e.ratingKey)", title: e.title, overview: e.summary, image: url, durationMin: dur, progressPct: pct, viewOffset: e.viewOffset)
            }
            await MainActor.run {
                self.episodes = eps
                self.episodesLoading = false
            }
        } catch {
            await MainActor.run { self.episodesLoading = false }
        }
    }

    private func loadTMDBSeasons() async {
        guard mediaKind == "tv", let tid = tmdbId else { return }
        do {
            // Fetch TV details again to get seasons list
            struct TV: Codable { let seasons: [TS]? }
            struct TS: Codable { let season_number: Int? }
            let tv: TV = try await api.get("/api/tmdb/tv/\(tid)")
            let ss = (tv.seasons ?? []).compactMap { $0.season_number }.filter { $0 > 0 }
            let mapped = ss.map { Season(id: "tmdb:season:\(tid):\($0)", title: "Season \($0)", source: "tmdb") }
            await MainActor.run {
                self.seasons = mapped
                self.selectedSeasonKey = mapped.first?.id
            }
            if let first = mapped.first { await loadTMDBEpisodes(seasonId: first.id) }
        } catch {}
    }

    // Public episode reload when UI changes season
    func selectSeason(_ key: String) async {
        await MainActor.run { self.selectedSeasonKey = key; self.episodesLoading = true }
        if key.hasPrefix("tmdb:season:") {
            await loadTMDBEpisodes(seasonId: key)
        } else {
            await loadPlexEpisodes(seasonKey: key)
        }
        await MainActor.run { self.episodesLoading = false }
    }

    private func loadTMDBEpisodes(seasonId: String) async {
        // seasonId = tmdb:season:<tvId>:<S>
        let parts = seasonId.split(separator: ":")
        guard parts.count == 4, parts[0] == "tmdb", parts[1] == "season" else { return }
        let tvId = String(parts[2])
        guard let seasonNumber = Int(parts[3]) else { return }
        do {
            struct SD: Codable { let episodes: [SE]? }
            struct SE: Codable { let id: Int?; let name: String?; let overview: String?; let still_path: String?; let runtime: Int? }
            let data: SD = try await api.get("/api/tmdb/tv/\(tvId)/season/\(seasonNumber)")
            let eps: [Episode] = (data.episodes ?? []).map { e in
                let url = ImageService.shared.proxyImageURL(url: e.still_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }, width: 600, height: 338)
                return Episode(id: "tmdb:tv:\(e.id ?? 0)", title: e.name ?? "Episode", overview: e.overview, image: url, durationMin: e.runtime, progressPct: nil, viewOffset: nil)
            }
            await MainActor.run {
                self.episodes = eps
                self.episodesLoading = false
            }
        } catch {
            await MainActor.run { self.episodesLoading = false }
        }
    }

    private func loadPlexExtras(ratingKey: String) async {
        do {
            struct MC: Codable { let MediaContainer: C }
            struct C: Codable { let Metadata: [M]? }
            struct M: Codable { let Extras: E? }
            struct E: Codable { let Metadata: [EM]? }
            struct EM: Codable { let ratingKey: String; let title: String?; let thumb: String?; let duration: Int? }
            let ex: MC = try await api.get("/api/plex/metadata/\(ratingKey)", queryItems: [URLQueryItem(name: "includeExtras", value: "1")])
            let list = ex.MediaContainer.Metadata?.first?.Extras?.Metadata ?? []
            let mapped: [Extra] = list.map { em in
                Extra(id: em.ratingKey, title: em.title ?? "Trailer", image: ImageService.shared.plexImageURL(path: em.thumb, width: 400, height: 225), durationMin: em.duration.map { Int($0/60000) })
            }
            await MainActor.run { self.extras = mapped }
        } catch {}
    }

    // MARK: - Mood tags mapping (port of web deriveTags)
    private func deriveTags(from genres: [String]) -> [String] {
        let lower = Set(genres.map { $0.lowercased() })
        var tags: [String] = []
        if lower.contains("horror") { tags.append(contentsOf: ["Scary", "Suspenseful"]) }
        if lower.contains("mystery") { tags.append("Mystery") }
        if lower.contains("action") { tags.append("Exciting") }
        if lower.contains("comedy") { tags.append("Funny") }
        if lower.contains("drama") { tags.append("Emotional") }
        if lower.contains("thriller") { tags.append("Suspenseful") }
        if lower.contains("sci-fi") || lower.contains("science fiction") { tags.append("Mind-bending") }
        // Dedupe and limit
        var seen = Set<String>()
        let out = tags.filter { seen.insert($0).inserted }
        return Array(out.prefix(4))
    }
}
