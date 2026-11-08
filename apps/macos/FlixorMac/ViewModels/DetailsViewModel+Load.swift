//
//  DetailsViewModel+Load.swift
//  FlixorMac
//
//  Entry point load(for:), UltraBlur colors, Overseerr status, mood tags
//

import Foundation
import SwiftUI
import FlixorKit

extension DetailsViewModel {
    func load(for item: MediaItem) async {
        guard !isLoading else {
            print("⚠️ [Details] Already loading, skipping duplicate request")
            return
        }
        isLoading = true
        defer { isLoading = false }
        error = nil
        badges = []
        externalRatings = nil
        plexImdbRating = nil
        plexAudienceRating = nil
        lastFetchedRatingsKey = nil
        tmdbId = nil
        imdbId = nil
        mdblistRatings = nil
        mediaKind = nil
        playableId = nil
        logoURL = nil
        posterURL = nil
        backdropURL = nil
        cast = []
        crew = []
        directors = []
        writers = []
        moodTags = []
        related = []
        similar = []
        relatedBrowseContext = nil
        similarBrowseContext = nil
        seasons = []
        selectedSeasonKey = nil
        episodes = []
        onDeck = nil
        extras = []
        trailers = []
        overseerrStatus = nil
        heroColors = nil
        plexArtPath = nil
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
        productionCompanies = []
        networks = []
        collections = []
        studio = nil
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
        isEpisode = false
        episodeNumber = nil
        seasonNumber = nil
        showTitle = nil
        showRatingKey = nil
        episodeTitle = nil
        airDate = nil
        tmdbRating = nil
        guestStars = []
        episodeDirector = nil
        episodeWriter = nil

        print("🎬 [Details] Loading details for item: \(item.id), title: \(item.title)")

        do {
            if item.id.hasPrefix("tmdb:") {
                print("📺 [Details] Loading TMDB item")
                let parts = item.id.split(separator: ":")
                if parts.count == 3 {
                    let media = (parts[1] == "movie") ? "movie" : "tv"
                    let tid = String(parts[2])
                    mediaKind = media
                    tmdbId = tid
                    try await fetchTMDBDetails(media: media, id: tid, skipPlexMapping: false)
                }
            } else if item.id.hasPrefix("plex:") {
                print("📀 [Details] Loading native Plex item (prefixed)")
                let rk = String(item.id.dropFirst(5))
                plexRatingKey = rk
                do {
                    print("📦 [Details] Fetching Plex metadata for ratingKey: \(rk)")
                    guard let plexServer = FlixorCore.shared.plexServer else {
                        throw NSError(domain: "DetailsVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Plex server connected"])
                    }
                    let plexItem = try await plexServer.getMetadata(ratingKey: rk)
                    let meta = plexItemToMeta(plexItem)

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
                    // Episode count for TV shows
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
                        plexArtPath = art
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
                    // Extract collections
                    collections = (meta.Collection ?? []).compactMap { $0.tag }.filter { !$0.isEmpty }
                    // Extract studio
                    studio = meta.studio

                    addBadge("Plex")
                    playableId = item.id // Set playableId FIRST
                    print("✅ [Details] Plex metadata loaded, playableId set to: \(playableId ?? "nil")")
                    parseRatingsFromPlexMeta(meta)

                    // Extract IMDB ID from Guids for MDBList lookup
                    extractImdbId(from: meta.Guid)

                    // If we have a TMDB GUID, fetch TMDB enhancements (logo, recommendations)
                    // but DON'T try to map back to Plex (we already have it!)
                    if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { s in s.contains("tmdb://") || s.contains("themoviedb://") }),
                       let tid = tm.components(separatedBy: "://").last {
                        tmdbId = tid
                        plexGuid = tm
                        print("📺 [Details] Found TMDB GUID: \(tid), fetching enhancements (skip Plex mapping)")
                        try await fetchTMDBDetails(media: mediaKind ?? "movie", id: tid, skipPlexMapping: true)
                    }

                    // Load MDBList ratings (if enabled)
                    await loadMDBListRatings()

                    // Load TMDB trailers (if not already loaded via fetchTMDBDetails)
                    if trailers.isEmpty && tmdbId != nil {
                        await loadTMDBTrailers()
                    }

                    // Load seasons/episodes for TV shows
                    if mediaKind == "tv" {
                        print("📺 [Details] Loading seasons for Plex show: \(rk)")
                        await loadSeasonsAndEpisodes()
                    }
                } catch {
                    print("❌ [Details] Failed to load Plex metadata: \(error)")
                    throw error
                }
            } else {
                // Treat plain IDs (like "37357") as Plex ratingKeys
                print("📀 [Details] Loading native Plex item (plain ID)")
                let rk = item.id
                do {
                    print("📦 [Details] Fetching Plex metadata for ratingKey: \(rk)")
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
                    // Episode count for TV shows
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
                        plexArtPath = art
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
                    // Extract collections
                    collections = (meta.Collection ?? []).compactMap { $0.tag }.filter { !$0.isEmpty }
                    // Extract studio
                    studio = meta.studio

                    addBadge("Plex")
                    playableId = "plex:\(rk)" // Set playableId with prefix
                    print("✅ [Details] Plex metadata loaded, playableId set to: \(playableId ?? "nil")")
                    parseRatingsFromPlexMeta(meta)

                    // Extract IMDB ID from Guids for MDBList lookup
                    extractImdbId(from: meta.Guid)

                    // If we have a TMDB GUID, fetch TMDB enhancements (logo, recommendations)
                    if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { s in s.contains("tmdb://") || s.contains("themoviedb://") }),
                       let tid = tm.components(separatedBy: "://").last {
                        tmdbId = tid
                        print("📺 [Details] Found TMDB GUID: \(tid), fetching enhancements (skip Plex mapping)")
                        try await fetchTMDBDetails(media: mediaKind ?? "movie", id: tid, skipPlexMapping: true)
                    }

                    // Load MDBList ratings (if enabled)
                    await loadMDBListRatings()

                    // Load TMDB trailers (if not already loaded via fetchTMDBDetails)
                    if trailers.isEmpty && tmdbId != nil {
                        await loadTMDBTrailers()
                    }

                    // Load seasons/episodes for TV shows
                    if mediaKind == "tv" {
                        print("📺 [Details] Loading seasons for Plex show: \(rk)")
                        await loadSeasonsAndEpisodes()
                    }
                } catch {
                    print("❌ [Details] Failed to load Plex metadata: \(error)")
                    throw error
                }
            }
        } catch {
            print("❌ [Details] Load failed: \(error)")
            self.error = error.localizedDescription
        }

        // Fetch UltraBlur colors for dynamic background
        await fetchUltraBlurColors()

        // Always fetch Overseerr status at the end (ensures it's updated for new items)
        await loadOverseerrStatus()
    }

    /// Fetch UltraBlur colors for dynamic background gradients
    /// Prefers TMDB backdrop (matches hero section display) over Plex art
    func fetchUltraBlurColors() async {
        guard let plexServer = FlixorCore.shared.plexServer else {
            print("⚠️ [Details] No Plex server for UltraBlur colors")
            return
        }

        // Determine the image URL to use:
        // 1. Prefer TMDB backdrop URL (matches what hero section displays)
        // 2. Fall back to Plex art path
        var imageUrl: String?

        if let backdrop = backdropURL?.absoluteString, !backdrop.isEmpty {
            imageUrl = backdrop
            print("🎨 [Details] Using TMDB backdrop for UltraBlur: \(backdrop)")
        } else if let artPath = plexArtPath, !artPath.isEmpty {
            imageUrl = ImageService.shared.plexImageURL(path: artPath, width: 1920, height: 1080)?.absoluteString
            print("🎨 [Details] Using Plex art path for UltraBlur: \(artPath)")
        }

        guard let finalImageUrl = imageUrl else {
            print("⚠️ [Details] No image URL available for UltraBlur")
            return
        }

        do {
            if let colors = try await plexServer.getUltraBlurColors(imageUrl: finalImageUrl) {
                withAnimation(.easeInOut(duration: 0.8)) {
                    self.heroColors = colors
                }
                print("✅ [Details] UltraBlur colors fetched for: \(title)")
            }
        } catch {
            print("❌ [Details] Failed to fetch UltraBlur colors: \(error)")
        }
    }

    // MARK: - Overseerr Status

    func loadOverseerrStatus() async {
        // Always clear old status first to prevent stale data from previous item
        await MainActor.run {
            self.overseerrStatus = nil
        }

        guard OverseerrService.shared.isReady() else {
            print("⚠️ [loadOverseerrStatus] Overseerr not configured")
            return
        }
        guard let tid = tmdbId, let media = mediaKind else {
            print("⚠️ [loadOverseerrStatus] No TMDB ID or media kind available")
            return
        }

        guard let tmdbIdInt = Int(tid) else {
            print("⚠️ [loadOverseerrStatus] Invalid TMDB ID: \(tid)")
            return
        }

        print("📡 [loadOverseerrStatus] Fetching Overseerr status for \(media)/\(tid)")
        let status = await OverseerrService.shared.getMediaStatus(tmdbId: tmdbIdInt, mediaType: media)
        await MainActor.run {
            self.overseerrStatus = status
            print("✅ [loadOverseerrStatus] Status: \(status.status.rawValue)")
        }
    }

    // MARK: - Mood tags mapping (port of web deriveTags)
    func deriveTags(from genres: [String]) -> [String] {
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
