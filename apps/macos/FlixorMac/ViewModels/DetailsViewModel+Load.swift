//
//  DetailsViewModel+Load.swift
//  FlixorMac
//
//  Entry point load(for:), Overseerr status, mood tags
//

import Foundation
import SwiftUI
import FlixorKit

extension DetailsViewModel {
    func load(for item: MediaItem) async {
        // `.task` re-runs this for the same item when returning from the player
        // or a pushed page: keep the page and refresh only what can change.
        if hasLoadedContent(for: item) {
            await refreshLoadedContent()
            return
        }
        guard !isLoading else {
            print("⚠️ [Details] Already loading, skipping duplicate request")
            return
        }
        isLoading = true
        defer { isLoading = false }
        error = nil
        // Switching to another title in place: clear the hero text so the loading
        // skeleton covers it instead of the previous title's metadata. Reloading
        // the same item (an earlier load failed) keeps the text.
        if lastLoadedItemId != item.id {
            title = ""
            overview = ""
            year = nil
            editionTitle = nil
            runtime = nil
            rating = nil
            genres = []
        }
        lastLoadedItemId = item.id
        loadedContentItemId = nil
        resetLoadedState()
        beginLoadProgress()

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
                    markIdentityReady()
                    try await fetchTMDBDetails(media: media, id: tid, skipPlexMapping: false)
                }
            } else if item.id.hasPrefix("plex:") {
                print("📀 [Details] Loading native Plex item (prefixed)")
                let rk = String(item.id.dropFirst(5))
                plexRatingKey = rk
                guard let plexServer = FlixorCore.shared.plexServer else {
                    throw NSError(domain: "DetailsVM", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "No Plex server connected")])
                }
                let plexItem = try await plexServer.getMetadata(ratingKey: rk)
                let meta = plexItemToMeta(plexItem)
                try await loadNativePlex(meta: meta, item: item, ratingKey: rk, playableId: item.id, keepsPlexGuid: true)
            } else {
                // Treat plain IDs (like "37357") as Plex ratingKeys
                print("📀 [Details] Loading native Plex item (plain ID)")
                let rk = item.id
                let meta: PlexMeta = try await api.get("/api/plex/metadata/\(rk)")
                try await loadNativePlex(meta: meta, item: item, ratingKey: rk, playableId: "plex:\(rk)", keepsPlexGuid: false)
            }
        } catch {
            print("❌ [Details] Load failed: \(error)")
            self.error = error.localizedDescription
        }

        // Steps that failed early still let the page configure itself.
        markIdentityReady()
        releaseTitleIds()
        markTitleIdsReady()
        if error == nil && !Task.isCancelled {
            loadedContentItemId = item.id
        }
    }

    /// Native Plex movie or show (seasons and episodes have their own loaders).
    /// Plex data is applied at once; TMDB enhancements, MDBList and episodes then
    /// load side by side.
    private func loadNativePlex(meta: PlexMeta, item: MediaItem, ratingKey rk: String, playableId pid: String, keepsPlexGuid: Bool) async throws {
        if meta.type == "season" {
            await loadSeasonDirect(meta: meta, ratingKey: rk)
            return
        }
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
        let plexArt = meta.art.flatMap { ImageService.shared.plexImageURL(path: $0, width: 1920, height: 1080) }
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

        addBadge("Plex")
        playableId = pid
        print("✅ [Details] Plex metadata loaded, playableId set to: \(playableId ?? "nil")")
        parseRatingsFromPlexMeta(meta)

        // Extract IMDB ID from Guids for MDBList lookup
        extractImdbId(from: meta.Guid)

        // A TMDB GUID brings TMDB enhancements (logo, recommendations); no Plex
        // mapping, the item is already from Plex.
        var tmdbGuidId: String?
        if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { s in s.contains("tmdb://") || s.contains("themoviedb://") }),
           let tid = tm.components(separatedBy: "://").last {
            tmdbId = tid
            if keepsPlexGuid { plexGuid = tm }
            tmdbGuidId = tid
        }
        markIdentityReady()
        if tmdbGuidId == nil {
            setBackdrop(plexArt)
            markTitleIdsReady()
        } else if imdbId == nil && MDBListService.shared.isReady() {
            // loadMDBListRatings looks the IMDb id up; the watch target and the
            // comments wait for it rather than being set up without it.
            holdTitleIds()
        }

        async let tmdbFailure = tmdbEnhancementsFailure(media: mediaKind ?? "movie", id: tmdbGuidId, plexBackdrop: plexArt)
        async let mdblist: Void = loadMDBListRatings()
        async let episodes: Void = loadSeasonsAndEpisodesIfShow()
        let failure = await tmdbFailure
        _ = await (mdblist, episodes)
        if let failure {
            throw NSError(domain: "DetailsVM", code: -2, userInfo: [NSLocalizedDescriptionKey: failure])
        }
    }

    /// TMDB enhancements for a native Plex item; the error message if they failed.
    private func tmdbEnhancementsFailure(media: String, id: String?, plexBackdrop: URL?) async -> String? {
        guard let id else { return nil }
        print("📺 [Details] Found TMDB GUID: \(id), fetching enhancements (skip Plex mapping)")
        do {
            try await fetchTMDBDetails(media: media, id: id, skipPlexMapping: true, plexBackdrop: plexBackdrop)
            return nil
        } catch {
            print("❌ [Details] TMDB enhancements failed: \(error)")
            return error.localizedDescription
        }
    }

    private func loadSeasonsAndEpisodesIfShow() async {
        guard mediaKind == "tv" else { return }
        await loadSeasonsAndEpisodes()
    }

    /// Back on a loaded page: episode progress for the season on screen and On
    /// Deck. Title watch state is refreshed by the view.
    func refreshLoadedContent() async {
        guard !isRefreshingContent else { return }
        isRefreshingContent = true
        defer { isRefreshingContent = false }
        // loadPlexEpisodes and the On Deck request drop their results if a
        // title is opened in place meanwhile (loadToken / playableId checks).

        if isSeason {
            if let key = plexRatingKey { await loadPlexEpisodes(seasonKey: key) }
            return
        }
        guard mediaKind == "tv", !isEpisode,
              let key = selectedSeasonKey, !key.hasPrefix("tmdb:") else { return }
        async let episodes: Void = loadPlexEpisodes(seasonKey: key, seasonNumber: currentSeasonNumber)
        async let deck: Void = refreshPlexOnDeck()
        _ = await (episodes, deck)
    }

    private func resetLoadedState() {
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
        castFromPlexMatch = false
        plexSeasonInfo = nil
        tmdbSeasonInfo = nil
    }

    // MARK: - Overseerr Status

    func loadOverseerrStatus() async {
        // The load resets the status, so a new title never shows the old one.
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
        guard !Task.isCancelled, tmdbId == tid else { return }
        self.overseerrStatus = status
        print("✅ [loadOverseerrStatus] Status: \(status.status.rawValue)")
    }

    // MARK: - Mood tags mapping (port of web deriveTags)
    func deriveTags(from genres: [String]) -> [String] {
        let lower = Set(genres.map { $0.lowercased() })
        var tags: [String] = []
        if lower.contains("horror") { tags.append(contentsOf: [String(localized: "Scary"), String(localized: "Suspenseful")]) }
        if lower.contains("mystery") { tags.append(String(localized: "Mystery")) }
        if lower.contains("action") { tags.append(String(localized: "Exciting")) }
        if lower.contains("comedy") { tags.append(String(localized: "Funny")) }
        if lower.contains("drama") { tags.append(String(localized: "Emotional")) }
        if lower.contains("thriller") { tags.append(String(localized: "Suspenseful")) }
        if lower.contains("sci-fi") || lower.contains("science fiction") { tags.append(String(localized: "Mind-bending")) }
        // Dedupe and limit
        var seen = Set<String>()
        let out = tags.filter { seen.insert($0).inserted }
        return Array(out.prefix(4))
    }
}
