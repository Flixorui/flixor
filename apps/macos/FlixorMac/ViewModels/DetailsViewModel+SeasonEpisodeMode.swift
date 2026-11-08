//
//  DetailsViewModel+SeasonEpisodeMode.swift
//  FlixorMac
//
//  Season-only and episode-only loading with TMDB enhancements
//

import Foundation
import SwiftUI
import FlixorKit

extension DetailsViewModel {
    // MARK: - Season Direct Load

    func loadSeasonDirect(meta: PlexMeta, ratingKey: String) async {
        print("🎬 [loadSeasonDirect] Loading season-only view for: \(meta.title ?? "Season")")

        isSeason = true
        mediaKind = "tv"

        // Basic metadata
        title = meta.title ?? String(localized: "Season")
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

    // MARK: - Episode Direct Loading

    func loadEpisodeDirect(meta: PlexMeta, ratingKey: String) async {
        print("🎬 [loadEpisodeDirect] Loading episode view for: \(meta.title ?? "Episode")")

        isEpisode = true
        mediaKind = "tv"

        // Basic metadata from Plex
        let originalEpisodeTitle = meta.title ?? String(localized: "Episode")
        episodeTitle = originalEpisodeTitle  // Store original title for player
        title = originalEpisodeTitle
        overview = meta.summary ?? ""
        episodeNumber = meta.index
        seasonNumber = meta.parentIndex
        showTitle = meta.grandparentTitle
        showRatingKey = meta.grandparentRatingKey
        rating = meta.contentRating
        if let ms = meta.duration { runtime = Int(ms/60000) } else { runtime = nil }
        airDate = meta.originallyAvailableAt

        // Build episode title with context (for display in details view only)
        if let showName = meta.grandparentTitle, let sNum = meta.parentIndex, let eNum = meta.index {
            title = "\(showName) - S\(sNum)E\(eNum) - \(originalEpisodeTitle)"
        } else if let showName = meta.grandparentTitle {
            title = "\(showName) - \(originalEpisodeTitle)"
        }

        // Images - prefer episode art, fallback to show art
        if let thumb = meta.thumb,
           let u = ImageService.shared.plexImageURL(path: thumb, width: 600, height: 338) {
            posterURL = u
        } else if let grandparentThumb = meta.grandparentThumb,
                  let u = ImageService.shared.plexImageURL(path: grandparentThumb, width: 600, height: 900) {
            posterURL = u
        }
        if let art = meta.art,
           let u = ImageService.shared.plexImageURL(path: art, width: 1920, height: 1080) {
            backdropURL = u
        } else if let grandparentArt = meta.grandparentArt,
                  let u = ImageService.shared.plexImageURL(path: grandparentArt, width: 1920, height: 1080) {
            backdropURL = u
        }

        // Technical details from media
        if let media = meta.Media, !media.isEmpty {
            appendTechnicalBadges(from: media)
            hydrateVersions(from: media)
            extractEditionTitle(from: media)
        }

        addBadge("Plex")
        playableId = "plex:\(ratingKey)"
        plexRatingKey = ratingKey

        // Try to find TMDB ID from the parent TV show
        // For episodes, we always want the SHOW's TMDB ID (not episode-specific IDs)
        var showTmdbId: String?

        // Helper to extract numeric TMDB ID from GUID string
        // Handles formats like: tmdb://12345, tmdb://tv/12345, themoviedb://tv/12345/season/1/episode/2
        func extractTmdbShowId(from guid: String) -> String? {
            guard let afterScheme = guid.components(separatedBy: "://").last else { return nil }
            // Split by "/" and find the first purely numeric component (the show ID)
            let components = afterScheme.components(separatedBy: "/")
            for component in components {
                // Check if this component is a valid numeric TMDB ID
                if !component.isEmpty && component.allSatisfy({ $0.isNumber }) {
                    return component
                }
            }
            return nil
        }

        // For episodes, prefer fetching from the parent show to ensure correct show ID
        if let showKey = meta.grandparentRatingKey {
            do {
                print("📡 [loadEpisodeDirect] Fetching show metadata for TMDB ID...")
                guard let plexServer = FlixorCore.shared.plexServer else {
                    throw NSError(domain: "DetailsVM", code: -1, userInfo: [NSLocalizedDescriptionKey: String(localized: "No Plex server")])
                }
                let showItem = try await plexServer.getMetadata(ratingKey: showKey)
                let showMeta = plexItemToMeta(showItem)
                if let tm = showMeta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
                   let tid = extractTmdbShowId(from: tm) {
                    showTmdbId = tid
                    tmdbId = tid
                    plexGuid = tm
                    print("✅ [loadEpisodeDirect] Found TMDB ID from show: \(tid)")
                }
            } catch {
                print("⚠️ [loadEpisodeDirect] Failed to get show metadata: \(error)")
            }
        }

        // Fallback: try episode's own GUID if we couldn't get from show
        if showTmdbId == nil {
            if let tm = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
               let tid = extractTmdbShowId(from: tm) {
                showTmdbId = tid
                tmdbId = tid
                plexGuid = tm
                print("✅ [loadEpisodeDirect] Found TMDB ID from episode GUID: \(tid)")
            }
        }

        // Fetch TMDB episode enhancements
        if let tid = showTmdbId, let sNum = seasonNumber, let eNum = episodeNumber {
            await fetchTMDBEpisodeEnhancements(showTmdbId: tid, seasonNumber: sNum, episodeNumber: eNum)
        }

        // Fetch TMDB TV series backdrop for hero section (overrides Plex art)
        if let tid = showTmdbId {
            await fetchTMDBSeriesBackdrop(showTmdbId: tid)
        }


        print("✅ [loadEpisodeDirect] Episode view loaded successfully")
    }

    // MARK: - TMDB Episode Enhancements

    private func fetchTMDBEpisodeEnhancements(showTmdbId: String, seasonNumber: Int, episodeNumber: Int) async {
        print("📡 [fetchTMDBEpisodeEnhancements] Fetching TMDB episode S\(seasonNumber)E\(episodeNumber) for show \(showTmdbId)")

        struct TMDBEpisodeDetail: Codable {
            let id: Int?
            let name: String?
            let overview: String?
            let air_date: String?
            let still_path: String?
            let vote_average: Double?
            let vote_count: Int?
            let runtime: Int?
            let guest_stars: [GuestStar]?
            let crew: [CrewMember]?

            struct GuestStar: Codable {
                let id: Int?
                let name: String?
                let character: String?
                let profile_path: String?
            }

            struct CrewMember: Codable {
                let id: Int?
                let name: String?
                let job: String?
                let department: String?
                let profile_path: String?
            }
        }

        do {
            let episode: TMDBEpisodeDetail = try await api.get("/api/tmdb/tv/\(showTmdbId)/season/\(seasonNumber)/episode/\(episodeNumber)")

            // Update air date
            if let date = episode.air_date, !date.isEmpty {
                airDate = date
                print("✅ [fetchTMDBEpisodeEnhancements] Air date: \(date)")
            }

            // Update rating
            if let rating = episode.vote_average, rating > 0 {
                tmdbRating = rating
                print("✅ [fetchTMDBEpisodeEnhancements] TMDB rating: \(rating)")
            }

            // Update overview if Plex didn't have one
            if (overview.isEmpty || overview.count < 50), let tmdbOverview = episode.overview, !tmdbOverview.isEmpty {
                overview = tmdbOverview
                print("✅ [fetchTMDBEpisodeEnhancements] Updated overview from TMDB")
            }

            // Update runtime if Plex didn't have one
            if runtime == nil, let tmdbRuntime = episode.runtime {
                runtime = tmdbRuntime
                print("✅ [fetchTMDBEpisodeEnhancements] Runtime: \(tmdbRuntime) min")
            }

            // Update still image (prefer TMDB over Plex screen grab)
            if let stillPath = episode.still_path {
                posterURL = URL(string: "https://image.tmdb.org/t/p/w780\(stillPath)")
                print("✅ [fetchTMDBEpisodeEnhancements] Updated still image from TMDB")
            }

            // Guest stars
            if let guests = episode.guest_stars, !guests.isEmpty {
                guestStars = guests.prefix(12).map { g in
                    let profileURL: URL? = g.profile_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") }
                    return Person(id: "\(g.id ?? 0)", name: g.name ?? "", role: g.character, profile: profileURL)
                }
                print("✅ [fetchTMDBEpisodeEnhancements] Loaded \(guestStars.count) guest star(s)")
            }

            // Director and Writer from crew
            if let crewList = episode.crew {
                if let director = crewList.first(where: { $0.job?.lowercased() == "director" }) {
                    episodeDirector = director.name
                    print("✅ [fetchTMDBEpisodeEnhancements] Director: \(director.name ?? "?")")
                }
                if let writer = crewList.first(where: { $0.job?.lowercased() == "writer" || $0.department?.lowercased() == "writing" }) {
                    episodeWriter = writer.name
                    print("✅ [fetchTMDBEpisodeEnhancements] Writer: \(writer.name ?? "?")")
                }
            }

            print("✅ [fetchTMDBEpisodeEnhancements] TMDB episode enhancements complete")
        } catch {
            print("⚠️ [fetchTMDBEpisodeEnhancements] Failed to fetch TMDB episode data: \(error)")
        }
    }

    // MARK: - TMDB Series Backdrop (for Episodes)

    /// Fetch TMDB TV series backdrop for episode details screen
    /// This ensures the hero section uses the series backdrop instead of episode still
    private func fetchTMDBSeriesBackdrop(showTmdbId: String) async {
        print("📡 [fetchTMDBSeriesBackdrop] Fetching TV series backdrop for show \(showTmdbId)")

        struct TMDBTVShow: Codable {
            let backdrop_path: String?
        }

        do {
            let show: TMDBTVShow = try await api.get("/api/tmdb/tv/\(showTmdbId)")

            if let backdropPath = show.backdrop_path {
                let tmdbBackdropUrl = "https://image.tmdb.org/t/p/original\(backdropPath)"
                if let url = URL(string: tmdbBackdropUrl) {
                    backdropURL = url
                    print("✅ [fetchTMDBSeriesBackdrop] Set TMDB series backdrop URL: \(url.absoluteString)")
                } else {
                    print("⚠️ [fetchTMDBSeriesBackdrop] Failed to create URL from: \(tmdbBackdropUrl)")
                }
            } else {
                print("⚠️ [fetchTMDBSeriesBackdrop] No backdrop_path in TMDB response")
            }
        } catch {
            print("⚠️ [fetchTMDBSeriesBackdrop] Failed to fetch TV series data: \(error)")
        }
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
}
