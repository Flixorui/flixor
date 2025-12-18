//
//  TVDetailsViewModel.swift
//  FlixorTV
//
//  ViewModel for Details page (ported from macOS)
//

import Foundation
import SwiftUI
import FlixorKit

@MainActor
class TVDetailsViewModel: ObservableObject {
    // Core
    @Published var isLoading = false
    @Published var error: String?

    // Metadata
    @Published var title: String = ""
    @Published var overview: String = ""
    @Published var year: String?
    @Published var runtime: Int?
    @Published var rating: String?
    @Published var genres: [String] = []
    @Published var badges: [String] = []
    @Published var moodTags: [String] = []

    // Media and visual
    @Published var logoURL: URL?
    @Published var backdropURL: URL?
    @Published var posterURL: URL?
    private var rawBackdropURL: String? // Unproxied URL for ultrablur API

    // Cast
    struct Person: Identifiable { let id: String; let name: String; let profile: URL? }
    struct CrewPerson: Identifiable { let id: String; let name: String; let job: String?; let profile: URL? }
    @Published var cast: [Person] = []
    @Published var crew: [CrewPerson] = []
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
    @Published var parentShowKey: String?           // Link to parent show
    @Published var episodeCount: Int?               // Total episodes
    @Published var watchedCount: Int?               // Watched episodes

    // UltraBlur background colors
    @Published var ultraBlurColors: UltraBlurColors?

    private let api = APIClient.shared
    private var lastFetchedRatingsKey: String?

    func fetchUltraBlurColors() async {
        guard let rawURL = rawBackdropURL else {
            print("⚠️ [TVDetails] No raw backdrop URL for ultrablur colors")
            return
        }
        do {
            print("🎨 [TVDetails] Fetching ultrablur colors for: \(rawURL)")
            let colors = try await api.getUltraBlurColors(imageUrl: rawURL)
            await MainActor.run {
                self.ultraBlurColors = colors
            }
            print("✅ [TVDetails] UltraBlur colors fetched: TL=\(colors.topLeft) TR=\(colors.topRight)")
        } catch {
            print("⚠️ [TVDetails] Failed to fetch ultrablur colors: \(error)")
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
    struct PlexMedia: Codable {
        let id: Int?
        let width: Int?
        let height: Int?
        let duration: Int?
        let bitrate: Int?
        let videoCodec: String?
        let videoProfile: String?
        let audioChannels: Int?
        let audioCodec: String?
        let audioProfile: String?
        let Part: [PlexPart]?
    }
    struct PlexPart: Codable {
        let id: Int?
        let size: Int?
        let key: String?
        let Stream: [PlexStream]?
    }
    struct PlexStream: Codable {
        let id: Int?
        let streamType: Int?
        let displayTitle: String?
        let language: String?
        let languageTag: String?
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

        // Season-specific fields
        let parentRatingKey: String?     // Parent show
        let parentTitle: String?          // Show name
        let index: Int?                   // Season number
        let leafCount: Int?               // Episode count
        let viewedLeafCount: Int?         // Watched count
        let key: String?                  // Children endpoint
    }

    func load(for item: MediaItem) async {
        guard !isLoading else {
            print("⚠️ [TVDetails] Already loading, skipping duplicate request")
            return
        }
        isLoading = true
        defer { isLoading = false }
        error = nil
        badges = []
        externalRatings = nil
        lastFetchedRatingsKey = nil
        tmdbId = nil
        mediaKind = nil
        playableId = nil
        logoURL = nil
        posterURL = nil
        backdropURL = nil
        rawBackdropURL = nil
        ultraBlurColors = nil
        cast = []
        crew = []
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
        versions = []
        activeVersionId = nil
        audioTracks = []
        subtitleTracks = []
        plexRatingKey = nil
        plexGuid = nil
        isSeason = false
        parentShowKey = nil
        episodeCount = nil
        watchedCount = nil

        print("🎬 [TVDetails] Loading details for item: \(item.id), title: \(item.title)")

        do {
            if item.id.hasPrefix("tmdb:") {
                print("📺 [TVDetails] Loading TMDB item")
                let parts = item.id.split(separator: ":")
                if parts.count == 3 {
                    let media = (parts[1] == "movie") ? "movie" : "tv"
                    let tid = String(parts[2])
                    mediaKind = media
                    tmdbId = tid
                    playableId = item.id // may be remapped later
                    try await fetchTMDBDetails(media: media, id: tid, skipPlexMapping: false)
                }
            } else if item.id.hasPrefix("plex:") {
                print("📀 [TVDetails] Loading native Plex item (prefixed)")
                let rk = String(item.id.dropFirst(5))
                plexRatingKey = rk
                do {
                    print("📦 [TVDetails] Fetching Plex metadata for ratingKey: \(rk)")
                    let meta: PlexMeta = try await api.get("/api/plex/metadata/\(rk)")

                    // Check if type is season
                    if meta.type == "season" {
                        await loadSeasonDirect(meta: meta, ratingKey: rk)
                        return
                    }

                    mediaKind = (meta.type == "movie") ? "movie" : "tv"
                    title = meta.title ?? item.title
                    overview = meta.summary ?? ""
                    if let y = meta.year { year = String(y) } else { year = nil }
                    rating = meta.contentRating
                    if let ms = meta.duration { runtime = Int(ms/60000) } else { runtime = nil }
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
                            return Person(id: name, name: name, profile: ImageService.shared.plexImageURL(path: r.thumb, width: 200, height: 200))
                        }
                    }
                    if let art = meta.art,
                       let u = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) {
                        backdropURL = u
                    }
                    if let thumb = meta.thumb,
                       let u = ImageService.shared.plexImageURL(path: thumb, width: 600, height: 900) {
                        posterURL = u
                    }
                    if let media = meta.Media, !media.isEmpty {
                        appendTechnicalBadges(from: media)
                        hydrateVersions(from: media)
                    }
                    addBadge("Plex")
                    playableId = item.id // Set playableId FIRST
                    print("✅ [TVDetails] Plex metadata loaded, playableId set to: \(playableId ?? "nil")")
                    await fetchExternalRatings(ratingKey: rk)

                    // If we have a TMDB GUID, fetch TMDB enhancements (logo, recommendations)
                    // but DON'T try to map back to Plex (we already have it!)
                    if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { s in s.contains("tmdb://") || s.contains("themoviedb://") }),
                       let tid = tm.components(separatedBy: "://").last {
                        tmdbId = tid
                        plexGuid = tm
                        print("📺 [TVDetails] Found TMDB GUID: \(tid), fetching enhancements (skip Plex mapping)")
                        try await fetchTMDBDetails(media: mediaKind ?? "movie", id: tid, skipPlexMapping: true)
                    }

                    // Load seasons/episodes for TV shows
                    if mediaKind == "tv" {
                        print("📺 [TVDetails] Loading seasons for Plex show: \(rk)")
                        await loadSeasonsAndEpisodes()
                    }
                } catch {
                    print("❌ [TVDetails] Failed to load Plex metadata: \(error)")
                    throw error
                }
            } else {
                // Treat plain IDs (like "37357") as Plex ratingKeys
                print("📀 [TVDetails] Loading native Plex item (plain ID)")
                let rk = item.id
                do {
                    print("📦 [TVDetails] Fetching Plex metadata for ratingKey: \(rk)")
                    let meta: PlexMeta = try await api.get("/api/plex/metadata/\(rk)")

                    // Check if type is season
                    if meta.type == "season" {
                        await loadSeasonDirect(meta: meta, ratingKey: rk)
                        return
                    }

                    mediaKind = (meta.type == "movie") ? "movie" : "tv"
                    title = meta.title ?? item.title
                    overview = meta.summary ?? ""
                    if let y = meta.year { year = String(y) } else { year = nil }
                    rating = meta.contentRating
                    if let ms = meta.duration { runtime = Int(ms/60000) } else { runtime = nil }
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
                            return Person(id: name, name: name, profile: ImageService.shared.plexImageURL(path: r.thumb, width: 200, height: 200))
                        }
                    }
                    if let art = meta.art,
                       let u = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) {
                        backdropURL = u
                    }
                    if let thumb = meta.thumb,
                       let u = ImageService.shared.plexImageURL(path: thumb, width: 600, height: 900) {
                        posterURL = u
                    }
                    if let media = meta.Media, !media.isEmpty {
                        appendTechnicalBadges(from: media)
                        hydrateVersions(from: media)
                    }
                    addBadge("Plex")
                    playableId = "plex:\(rk)" // Set playableId with prefix
                    plexRatingKey = rk // Set plexRatingKey for playback
                    print("✅ [TVDetails] Plex metadata loaded, playableId set to: \(playableId ?? "nil"), plexRatingKey set to: \(rk)")
                    await fetchExternalRatings(ratingKey: rk)

                    // If we have a TMDB GUID, fetch TMDB enhancements (logo, recommendations)
                    if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { s in s.contains("tmdb://") || s.contains("themoviedb://") }),
                       let tid = tm.components(separatedBy: "://").last {
                        tmdbId = tid
                        print("📺 [TVDetails] Found TMDB GUID: \(tid), fetching enhancements (skip Plex mapping)")
                        try await fetchTMDBDetails(media: mediaKind ?? "movie", id: tid, skipPlexMapping: true)
                    }

                    // Load seasons/episodes for TV shows
                    if mediaKind == "tv" {
                        print("📺 [TVDetails] Loading seasons for Plex show: \(rk)")
                        await loadSeasonsAndEpisodes()
                    }
                } catch {
                    print("❌ [TVDetails] Failed to load Plex metadata: \(error)")
                    throw error
                }
            }

            // Fetch UltraBlur colors after all data is loaded
            await fetchUltraBlurColors()
        } catch {
            print("❌ [TVDetails] Load failed: \(error)")
            self.error = error.localizedDescription
        }
    }

    private func fetchTMDBDetails(media: String, id: String, skipPlexMapping: Bool = false) async throws {
        // Details
        struct TDetails: Codable { let title: String?; let name: String?; let overview: String?; let backdrop_path: String?; let poster_path: String?; let release_date: String?; let first_air_date: String?; let genres: [TGenre]?; let runtime: Int?; let episode_run_time: [Int]?; let adult: Bool? }
        struct TGenre: Codable { let name: String }
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

        // Images (logo preferred en)
        struct TImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }
        struct TImages: Codable { let logos: [TImage]?; let backdrops: [TImage]? }
        let imgs: TImages = try await api.get("/api/tmdb/\(media)/\(id)/images", queryItems: [URLQueryItem(name: "language", value: "en,hi,null")])
        if let logo = (imgs.logos ?? []).first(where: { $0.iso_639_1 == "en" || $0.iso_639_1 == "hi" }) ?? imgs.logos?.first,
           let p = logo.file_path {
            self.logoURL = ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w500\(p)")
        }

        // Credits (cast top 12)
        struct TCast: Codable { let id: Int?; let name: String?; let profile_path: String? }
        struct TCrew: Codable { let id: Int?; let name: String?; let job: String?; let profile_path: String? }
        struct TCredits: Codable { let cast: [TCast]?; let crew: [TCrew]? }
        let cr: TCredits = try await api.get("/api/tmdb/\(media)/\(id)/credits")
        self.cast = (cr.cast ?? []).prefix(12).map { c in
            Person(id: String(c.id ?? 0), name: c.name ?? "", profile: ImageService.shared.proxyImageURL(url: c.profile_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }))
        }
        self.crew = (cr.crew ?? []).prefix(12).map { x in
            CrewPerson(id: String(x.id ?? 0), name: x.name ?? "", job: x.job, profile: ImageService.shared.proxyImageURL(url: x.profile_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }))
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
            print("⏭️ [TVDetails] Skipping Plex mapping (already have native Plex data)")
        }

        // Load seasons/episodes
        if media == "tv" {
            await self.loadSeasonsAndEpisodes()
        }
    }

    // MARK: - TMDB -> Plex mapping (web parity)
    private func mapToPlex(media: String, tmdbId: String, title: String, year: String?) async throws {
        print("🔍 [mapToPlex] Starting TMDB → Plex mapping for '\(title)' (year: \(year ?? "nil"), tmdbId: \(tmdbId), media: \(media))")

        // First: Title search (as requested)
        struct SearchResponse: Codable {
            let MediaContainer: SearchContainer?
            let Metadata: [SearchItem]?

            init(from decoder: Decoder) throws {
                // First, try to decode as a plain array (backend sometimes returns this)
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

            init(MediaContainer: SearchContainer?, Metadata: [SearchItem]?) {
                self.MediaContainer = MediaContainer
                self.Metadata = Metadata
            }

            private enum CodingKeys: String, CodingKey { case MediaContainer, Metadata }
        }
        struct SearchContainer: Codable {
            let Metadata: [SearchItem]

            init(Metadata: [SearchItem]) {
                self.Metadata = Metadata
            }

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

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(Metadata, forKey: .Metadata)
            }

            private enum CodingKeys: String, CodingKey { case Metadata }
        }
        struct SearchItem: Codable {
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
                print("📋 [mapToPlex] Title search found \(candidates.count) candidates: \(candidates.map { "\($0.title ?? "?") (\($0.ratingKey))" }.joined(separator: ", "))")
            } else {
                print("⚠️ [mapToPlex] Title search returned no results")
            }
        } catch {
            print("❌ [mapToPlex] Title search failed: \(error)")
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
            print("⚠️ [mapToPlex] Failed to fetch external IDs")
        }
        print("🔑 [mapToPlex] GUID list: \(guids.joined(separator: ", "))")
        var guidHits: [SearchItem] = []
        for g in guids {
            do {
                let res: SearchResponse = try await api.get("/api/plex/findByGuid", queryItems: [URLQueryItem(name: "guid", value: g), URLQueryItem(name: "type", value: String(t))])
                let matches = res.MediaContainer?.Metadata ?? res.Metadata ?? []
                if !matches.isEmpty {
                    print("✅ [mapToPlex] GUID '\(g)' found \(matches.count) match(es): \(matches.map { "\($0.title ?? "?") (\($0.ratingKey))" }.joined(separator: ", "))")
                    guidHits.append(contentsOf: matches)
                }
            } catch {
                print("❌ [mapToPlex] GUID lookup failed for '\(g)': \(error)")
            }
        }
        if !guidHits.isEmpty {
            var seen = Set(pool.map { $0.ratingKey })
            for item in guidHits {
                if seen.insert(item.ratingKey).inserted {
                    pool.append(item)
                }
            }
            print("🔀 [mapToPlex] Merged GUID hits into pool. Total pool size: \(pool.count)")
        } else {
            print("⚠️ [mapToPlex] No GUID matches found")
        }

        guard !pool.isEmpty else {
            print("❌ [mapToPlex] No candidates in pool, mapping failed")
            throw NSError(domain: "map", code: 404)
        }

        // Prefer exact TMDB GUID match
        var match: SearchItem? = pool.first(where: { item in
            let guids = item.Guid?.compactMap { $0.id?.lowercased() } ?? []
            return guids.contains("tmdb://\(tmdbId)") || guids.contains("themoviedb://\(tmdbId)")
        })

        if let exactMatch = match {
            print("🎯 [mapToPlex] Found exact TMDB GUID match: '\(exactMatch.title ?? "?")' (ratingKey: \(exactMatch.ratingKey))")
        }

        // Score-based fallback
        if match == nil {
            print("🔢 [mapToPlex] No exact GUID match, using score-based matching...")
            var bestScore = -1
            for c in pool {
                let sc = score(c)
                print("   - '\(c.title ?? "?")' (\(c.ratingKey)): score \(sc)")
                if sc > bestScore {
                    bestScore = sc
                    match = c
                }
            }
            if let scoreMatch = match {
                print("🏆 [mapToPlex] Best score match: '\(scoreMatch.title ?? "?")' (ratingKey: \(scoreMatch.ratingKey), score: \(bestScore))")
            }
        }

        guard let match = match else {
            print("❌ [mapToPlex] No suitable match found in pool")
            throw NSError(domain: "map", code: 404)
        }

        // Update VM with Plex mapping
        let rk = match.ratingKey
        self.playableId = "plex:\(rk)"
        self.plexRatingKey = rk
        if let firstGuid = match.Guid?.compactMap({ $0.id }).first {
            self.plexGuid = firstGuid
        }
        print("✨ [mapToPlex] Setting playableId to: \(self.playableId ?? "nil")")
        self.addBadge("Plex")
        // Prefer Plex backdrop
        let art = match.art ?? match.thumb ?? match.parentThumb ?? match.grandparentThumb ?? ""
        if let u = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) { self.backdropURL = u }
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
                return Person(id: name, name: name, profile: ImageService.shared.plexImageURL(path: r.thumb, width: 200, height: 200))
            }
        }
        // Versions
        if let mediaArr = match.Media {
            appendTechnicalBadges(from: mediaArr)
            hydrateVersions(from: mediaArr)
            print("📊 [mapToPlex] Loaded \(mediaArr.count) media version(s) for technical details")
        } else {
            print("⚠️ [mapToPlex] No media versions found in Plex match")
        }
        await fetchExternalRatings(ratingKey: rk)
        await loadPlexExtras(ratingKey: rk)
        print("✅ [mapToPlex] TMDB → Plex mapping complete for '\(match.title ?? title)' (ratingKey: \(rk))")
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
        if profile.contains("hdr") || profile.contains("hlg") {
            extra.append("HDR")
        }
        if profile.contains("dv") || profile.contains("dolby vision") {
            extra.append("Dolby Vision")
        }
        let audioProfile = (first.audioProfile ?? "").lowercased()
        let audioCodec = (first.audioCodec ?? "").lowercased()
        if audioProfile.contains("atmos") || audioCodec.contains("atmos") || audioCodec.contains("truehd") {
            extra.append("Atmos")
        }
        addBadges(extra)
    }

    private func hydrateVersions(from media: [PlexMedia]) {
        print("🎞️ [hydrateVersions] Processing \(media.count) media item(s)")
        var vds: [VersionDetail] = []
        for (idx, mm) in media.enumerated() {
            let id = String(mm.id ?? idx)
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
                return Track(id: String(stream.id ?? offset), name: name, language: stream.languageTag ?? stream.language)
            }
            let subs = streams.enumerated().filter { $0.element.streamType == 3 }.map { offset, stream -> Track in
                let name = stream.displayTitle ?? stream.languageTag ?? stream.language ?? "Sub \(offset + 1)"
                return Track(id: String(stream.id ?? offset), name: name, language: stream.languageTag ?? stream.language)
            }
            let sizeMB = part?.size.map { Double($0) / (1024.0 * 1024.0) }
            let tech = VersionDetail.TechnicalInfo(
                resolution: (width > 0 && height > 0) ? "\(width)x\(height)" : nil,
                videoCodec: mm.videoCodec,
                videoProfile: mm.videoProfile,
                audioCodec: mm.audioCodec,
                audioChannels: mm.audioChannels,
                bitrate: mm.bitrate,
                fileSizeMB: sizeMB,
                durationMin: mm.duration.map { Int($0 / 60000) },
                subtitleCount: subs.count
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
            print("✅ [hydrateVersions] Successfully populated \(vds.count) version(s): \(vds.map { $0.label }.joined(separator: ", "))")
            print("   Active version: \(activeVersionId ?? "nil"), \(audioTracks.count) audio track(s), \(subtitleTracks.count) subtitle(s)")
        } else {
            print("⚠️ [hydrateVersions] No versions created from media array")
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
            let imdbModel = res.imdb.map { ExternalRatings.IMDb(score: $0.rating, votes: $0.votes) }
            let rtModel = res.rottenTomatoes.map { ExternalRatings.RottenTomatoes(critic: $0.critic, audience: $0.audience) }
            externalRatings = ExternalRatings(imdb: imdbModel, rottenTomatoes: rtModel)
        } catch {
            print("⚠️ [TVDetails] Ratings fetch failed: \(error)")
        }
    }

    // MARK: - Season Direct Load

    private func loadSeasonDirect(meta: PlexMeta, ratingKey: String) async {
        print("🎬 [loadSeasonDirect] Loading season-only view for: \(meta.title ?? "Season")")

        isSeason = true
        mediaKind = "tv"

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
        }

        addBadge("Plex")
        playableId = "plex:\(ratingKey)"
        plexRatingKey = ratingKey

        // TMDB enhancement (optional)
        if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = tm.components(separatedBy: "://").last {
            tmdbId = tid
            plexGuid = tm
            print("📺 [loadSeasonDirect] Found TMDB GUID: \(tid), fetching enhancements")
            do {
                try await fetchTMDBSeasonEnhancements(tmdbId: tid, seasonNumber: meta.index)
            } catch {
                print("⚠️ [loadSeasonDirect] TMDB enhancements failed: \(error)")
            }
        }

        // Load episodes directly (NO season picker)
        seasons = []
        selectedSeasonKey = nil  // Null = season-only mode
        await loadPlexEpisodes(seasonKey: ratingKey)

        print("✅ [loadSeasonDirect] Season-only view loaded successfully")
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

        print("📡 [fetchTMDBSeasonEnhancements] Fetching TMDB season \(num) for show \(tmdbId)")
        let season: TMDBSeason = try await api.get("/api/tmdb/tv/\(tmdbId)/season/\(num)")

        // Use TMDB data if better
        if let name = season.name, !name.isEmpty {
            title = title.replacingOccurrences(of: "Season \(num)", with: name)
            print("✅ [fetchTMDBSeasonEnhancements] Updated title from TMDB: \(name)")
        }
        if let overview = season.overview, !overview.isEmpty {
            self.overview = overview
            print("✅ [fetchTMDBSeasonEnhancements] Updated overview from TMDB")
        }
        if let poster = season.poster_path {
            posterURL = ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w500\(poster)")
            print("✅ [fetchTMDBSeasonEnhancements] Updated poster from TMDB")
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
            let audioCodec: String?
            let audioChannels: Int?
            let bitrate: Int?
            let fileSizeMB: Double?
            let durationMin: Int?
            let subtitleCount: Int?
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
            print("📺 [loadSeasonsAndEpisodes] Loading Plex seasons for showKey: \(showKey)")
            await loadPlexSeasons(showKey: showKey)
            if seasons.isEmpty {
                print("⚠️ [loadSeasonsAndEpisodes] Plex seasons empty, but we have Plex mapping - NOT falling back to TMDB")
                await MainActor.run { self.episodesLoading = false }
            } else {
                print("✅ [loadSeasonsAndEpisodes] Loaded \(seasons.count) Plex season(s)")
            }
        } else {
            print("📺 [loadSeasonsAndEpisodes] No Plex mapping, loading TMDB seasons")
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
            print("📡 [loadPlexSeasons] Fetching Plex seasons for show: \(showKey)")
            let ch: MC = try await api.get("/api/plex/dir/library/metadata/\(showKey)/children")
            let ss = (ch.Metadata ?? []).map { Season(id: $0.ratingKey, title: $0.title, source: "plex") }
            print("📺 [loadPlexSeasons] Found \(ss.count) season(s): \(ss.map { $0.title }.joined(separator: ", "))")
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
            print("❌ [loadPlexSeasons] Failed: \(error)")
        }
    }

    private func loadPlexEpisodes(seasonKey: String?) async {
        guard let seasonKey = seasonKey else {
            print("⚠️ [loadPlexEpisodes] No season key provided")
            return
        }
        do {
            // Backend returns MediaContainer directly (not wrapped)
            struct MC: Codable {
                let Metadata: [ME]?
                let size: Int?
            }
            struct ME: Codable { let ratingKey: String; let title: String; let summary: String?; let thumb: String?; let parentThumb: String?; let duration: Int?; let viewOffset: Int?; let viewCount: Int? }
            print("📡 [loadPlexEpisodes] Fetching episodes for season: \(seasonKey)")
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
            print("✅ [loadPlexEpisodes] Loaded \(eps.count) episode(s) with Plex IDs")
            await MainActor.run {
                self.episodes = eps
                self.episodesLoading = false
            }
        } catch {
            print("❌ [loadPlexEpisodes] Failed: \(error)")
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
