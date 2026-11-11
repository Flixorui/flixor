//
//  DetailsViewModel+TMDB.swift
//  FlixorMac
//
//  TMDB details and trailers
//

import Foundation
import SwiftUI
import FlixorKit

// MARK: - Array Extension for deduplication
private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension DetailsViewModel {
    /// TMDB details for a title. Everything that needs only the TMDB id runs at
    /// once, each request filling its own part of the page; Plex mapping (for
    /// TMDB items) starts alongside, and the seasons follow as soon as it's known
    /// whether the show is in Plex. Throws only when the details request failed.
    func fetchTMDBDetails(media: String, id: String, skipPlexMapping: Bool = false, plexBackdrop: URL? = nil) async throws {
        let mapsToPlex = !skipPlexMapping && !AppModeStore.shared.isStremioOnly
        let guidLookup = mapsToPlex ? startPlexGuidLookup(media: media, tmdbId: id) : nil

        async let logo: Void = loadTMDBLogo(media: media, id: id)
        async let credits: Void = loadTMDBCredits(media: media, id: id)
        async let rows: Void = loadTMDBRows(media: media, id: id)
        async let trailers: Void = loadTMDBTrailers()
        async let overseerr: Void = loadOverseerrStatus()

        var detailsError: Error?
        var tmdbBackdrop: URL?
        do {
            tmdbBackdrop = try await loadTMDBMainDetails(media: media, id: id)
        } catch {
            detailsError = error
        }

        if mapsToPlex {
            // Plex art wins over TMDB's for mapped titles, so the backdrop waits
            // for the mapping instead of loading both.
            do {
                let match = try await mapToPlex(media: media, tmdbId: id, title: self.title, year: self.year, guidLookup: guidLookup)
                setBackdrop(match.backdrop ?? tmdbBackdrop)
                markTitleIdsReady()
                async let ratings: Void = loadPlexMatchRatings(match)
                async let seasons: Void = loadSeasonsAndEpisodesIfTV(media: media)
                _ = await (ratings, seasons)
            } catch {
                // If mapping fails, surface "No local source" badge for clarity
                addBadge("No local source")
                setBackdrop(tmdbBackdrop)
                markTitleIdsReady()
                await loadSeasonsAndEpisodesIfTV(media: media)
            }
        } else {
            setBackdrop(tmdbBackdrop ?? plexBackdrop)
            markTitleIdsReady()
            if !skipPlexMapping {
                await loadSeasonsAndEpisodesIfTV(media: media)
            }
        }

        _ = await (logo, credits, rows, trailers, overseerr)
        if let detailsError { throw detailsError }
    }

    private func loadSeasonsAndEpisodesIfTV(media: String) async {
        guard media == "tv" else { return }
        await loadSeasonsAndEpisodes()
    }

    /// The main details request. Returns the TMDB backdrop for the caller to
    /// choose between it and Plex art.
    private func loadTMDBMainDetails(media: String, id: String) async throws -> URL? {
        // Details - expanded struct for all the info we need
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
            // Extended info
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
            let seasons: [TSeason]?
            // Ratings
            let vote_average: Double?
            let vote_count: Int?
        }
        struct TGenre: Codable { let name: String }
        struct TProductionCompany: Codable { let id: Int?; let name: String?; let logo_path: String? }
        struct TCreator: Codable { let name: String? }
        struct TSeason: Codable { let season_number: Int?; let poster_path: String?; let episode_count: Int? }

        let d: TDetails = try await api.get("/api/tmdb/\(media)/\(id)")
        self.title = d.title ?? d.name ?? self.title
        self.overview = d.overview ?? self.overview
        self.posterURL = ImageService.shared.proxyImageURL(url: d.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" })
        if let y = (d.release_date ?? d.first_air_date)?.prefix(4) { self.year = String(y) }
        self.genres = (d.genres ?? []).map { $0.name }
        self.moodTags = deriveTags(from: self.genres)
        let rt = d.runtime ?? d.episode_run_time?.first
        self.runtime = rt
        self.rating = (d.adult ?? false) ? "18+" : self.rating

        // Extended TMDB info
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
        if media == "tv", let seasons = d.seasons {
            self.tmdbSeasonInfo = seasons.compactMap { s in
                s.season_number.map { TMDBSeasonInfo(number: $0, posterPath: s.poster_path, episodeCount: s.episode_count) }
            }
        }

        // TMDB Rating (used as fallback if Plex/MDBList don't have ratings)
        if let rating = d.vote_average, rating > 0 {
            self.tmdbRating = rating
        }

        // Production companies (for movies)
        self.productionCompanies = (d.production_companies ?? []).compactMap { pc in
            guard let id = pc.id, let name = pc.name, !name.isEmpty else { return nil }
            let logoURL = pc.logo_path.flatMap { ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w185\($0)") }
            return ProductionCompany(id: id, name: name, logoURL: logoURL)
        }

        // Networks (for TV shows)
        self.networks = (d.networks ?? []).compactMap { n in
            guard let id = n.id, let name = n.name, !name.isEmpty else { return nil }
            let logoURL = n.logo_path.flatMap { ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w185\($0)") }
            return ProductionCompany(id: id, name: name, logoURL: logoURL)
        }

        // The "More Like This" browse pages are titled after this title.
        let mediaType: TMDBMediaType = (media == "movie") ? .movie : .tv
        self.relatedBrowseContext = .tmdb(kind: .recommendations, media: mediaType, id: id, displayTitle: self.title)
        self.similarBrowseContext = .tmdb(kind: .similar, media: mediaType, id: id, displayTitle: self.title)

        return ImageService.shared.proxyImageURL(url: d.backdrop_path.flatMap { "https://image.tmdb.org/t/p/original\($0)" })
    }

    private func loadTMDBLogo(media: String, id: String) async {
        // Images (logo - prioritize English, then any other language)
        struct TImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }
        struct TImages: Codable { let logos: [TImage]?; let backdrops: [TImage]? }
        do {
            // Fetch logos - include many languages for better coverage (Hindi, Japanese, Korean, Chinese, etc.)
            let imgs: TImages = try await api.get("/api/tmdb/\(media)/\(id)/images", queryItems: [
                URLQueryItem(name: "include_image_language", value: "en,hi,ja,ko,zh,es,fr,de,pt,it,ru,ar,null")
            ])
            // Priority: 1) English logo, 2) No language (null), 3) Any other language logo
            let logos = imgs.logos ?? []
            let englishLogo = logos.first(where: { $0.iso_639_1 == "en" })
            let nullLogo = logos.first(where: { $0.iso_639_1 == nil || $0.iso_639_1 == "" })
            let anyLogo = logos.first
            if let logo = englishLogo ?? nullLogo ?? anyLogo, let p = logo.file_path {
                self.logoURL = ImageService.shared.proxyImageURL(url: "https://image.tmdb.org/t/p/w500\(p)")
            } else {
                print("⚠️ [Details] No logo found for \(media)/\(id)")
            }
        } catch {
            print("⚠️ [Details] TMDB images failed: \(error)")
            loadHadPartialFailure = true
        }
    }

    private func loadTMDBCredits(media: String, id: String) async {
        // Credits (cast top 12 with character names, crew with directors/writers)
        struct TCast: Codable { let id: Int?; let name: String?; let character: String?; let profile_path: String? }
        struct TCrew: Codable { let id: Int?; let name: String?; let job: String?; let department: String?; let profile_path: String? }
        struct TCredits: Codable { let cast: [TCast]?; let crew: [TCrew]? }
        do {
            let cr: TCredits = try await api.get("/api/tmdb/\(media)/\(id)/credits")
            // A Plex match's cast is preferred when it has one.
            if !castFromPlexMatch {
                self.cast = (cr.cast ?? []).prefix(12).map { c in
                    Person(id: String(c.id ?? 0), name: c.name ?? "", role: c.character, profile: ImageService.shared.proxyImageURL(url: c.profile_path.flatMap { "https://image.tmdb.org/t/p/w185\($0)" }))
                }
            }
            self.crew = (cr.crew ?? []).prefix(12).map { x in
                CrewPerson(id: String(x.id ?? 0), name: x.name ?? "", job: x.job, profile: ImageService.shared.proxyImageURL(url: x.profile_path.flatMap { "https://image.tmdb.org/t/p/w185\($0)" }))
            }

            // Extract Directors and Writers from crew
            let allCrew = cr.crew ?? []
            self.directors = allCrew.filter { ($0.job?.lowercased() ?? "").contains("director") && $0.department?.lowercased() == "directing" }
                .compactMap { $0.name }
                .removingDuplicates()
            self.writers = allCrew.filter {
                let job = ($0.job?.lowercased() ?? "")
                return job.contains("writer") || job.contains("screenplay") || job.contains("story")
            }
                .compactMap { $0.name }
                .removingDuplicates()
        } catch {
            print("⚠️ [Details] TMDB credits failed: \(error)")
            loadHadPartialFailure = true
        }
    }

    private func loadTMDBRows(media: String, id: String) async {
        // Recommendations + Similar (rows)
        struct TRes: Codable { let results: [TResItem]? }
        struct TResItem: Codable { let id: Int?; let title: String?; let name: String?; let backdrop_path: String?; let poster_path: String? }
        func items(_ res: TRes) -> [MediaItem] {
            (res.results ?? []).prefix(12).map { i in
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
                    grandparentRatingKey: nil,
                    parentIndex: nil,
                    index: nil,
                    parentRatingKey: nil,
                    parentTitle: nil,
                    leafCount: nil,
                    viewedLeafCount: nil
                )
            }
        }
        async let recsResult: TRes? = try? api.get("/api/tmdb/\(media)/\(id)/recommendations")
        async let simResult: TRes? = try? api.get("/api/tmdb/\(media)/\(id)/similar")
        let (recs, sim) = await (recsResult, simResult)
        if recs == nil || sim == nil { loadHadPartialFailure = true }
        // One assignment pass, so the row is built once.
        if let recs { self.related = items(recs) }
        if let sim { self.similar = items(sim) }
    }

    // MARK: - TMDB Trailers

    func loadTMDBTrailers() async {
        guard let tid = tmdbId, let media = mediaKind else {
            print("⚠️ [loadTMDBTrailers] No TMDB ID or media kind available")
            return
        }

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

            print("📹 [loadTMDBTrailers] Fetching videos for \(media)/\(tid)")
            let response: VideosResponse = try await api.get("/api/tmdb/\(media)/\(tid)/videos")

            // Filter to YouTube videos and prioritize trailers
            let videos = (response.results ?? [])
                .filter { ($0.site?.lowercased() ?? "") == "youtube" && $0.key != nil }

            // Sort: official trailers first, then by type
            let sorted = videos.sorted { a, b in
                let aIsTrailer = (a.type?.lowercased() ?? "") == "trailer"
                let bIsTrailer = (b.type?.lowercased() ?? "") == "trailer"
                let aOfficial = a.official ?? false
                let bOfficial = b.official ?? false

                if aIsTrailer != bIsTrailer { return aIsTrailer }
                if aOfficial != bOfficial { return aOfficial }
                return false
            }

            let mapped: [Trailer] = sorted.prefix(10).compactMap { v in
                guard let key = v.key else { return nil }
                return Trailer(
                    id: v.id ?? key,
                    name: v.name ?? String(localized: "Video"),
                    key: key,
                    site: v.site ?? "YouTube",
                    type: v.type ?? "Video",
                    official: v.official,
                    publishedAt: v.published_at
                )
            }

            await MainActor.run {
                self.trailers = mapped
                print("✅ [loadTMDBTrailers] Loaded \(mapped.count) trailer(s)")
            }
        } catch {
            print("❌ [loadTMDBTrailers] Failed: \(error)")
        }
    }
}
