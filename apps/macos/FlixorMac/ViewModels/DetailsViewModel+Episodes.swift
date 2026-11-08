//
//  DetailsViewModel+Episodes.swift
//  FlixorMac
//
//  Seasons, episodes and extras loading
//

import Foundation
import SwiftUI
import FlixorKit

extension DetailsViewModel {
    func loadSeasonsAndEpisodes() async {
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
            struct M: Codable { let ratingKey: String; let title: String; let index: Int? }
            print("📡 [loadPlexSeasons] Fetching Plex seasons for show: \(showKey)")
            let ch: MC = try await api.get("/api/plex/dir/library/metadata/\(showKey)/children")
            let ss = (ch.Metadata ?? []).map { m in
                // Parse season number from title if index is missing (e.g., "Season 1" -> 1)
                let seasonNum = m.index ?? Int(m.title.replacingOccurrences(of: "Season ", with: ""))
                return Season(id: m.ratingKey, title: m.title, source: "plex", number: seasonNum)
            }
            print("📺 [loadPlexSeasons] Found \(ss.count) season(s): \(ss.map { $0.title }.joined(separator: ", "))")
            await MainActor.run {
                self.seasons = ss
                self.selectedSeasonKey = ss.first?.id
                self.currentSeasonNumber = ss.first?.number
            }
            await loadPlexEpisodes(seasonKey: ss.first?.id, seasonNumber: ss.first?.number)
            // Fetch technical details from first episode of first season
            await fetchTechnicalDetailsFromFirstEpisode()
            // On Deck
            do {
                let od: MC = try await api.get("/api/plex/dir/library/metadata/\(showKey)/onDeck")
                if let ep = od.Metadata?.first {
                    let image = ImageService.shared.plexImageURL(path: ep.ratingKey, width: 600, height: 338) // best-effort
                    await MainActor.run {
                        self.onDeck = Episode(id: "plex:\(ep.ratingKey)", title: ep.title, overview: nil, image: image, durationMin: nil, progressPct: nil, viewOffset: nil, seasonNumber: nil, episodeNumber: ep.index)
                    }
                }
            } catch {}
        } catch {
            print("❌ [loadPlexSeasons] Failed: \(error)")
        }
    }

    func loadPlexEpisodes(seasonKey: String?, seasonNumber: Int? = nil) async {
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
            struct ME: Codable { let ratingKey: String; let title: String; let summary: String?; let thumb: String?; let parentThumb: String?; let duration: Int?; let viewOffset: Int?; let viewCount: Int?; let index: Int? }
            print("📡 [loadPlexEpisodes] Fetching episodes for season: \(seasonKey)")
            let ch: MC = try await api.get("/api/plex/dir/library/metadata/\(seasonKey)/children?nocache=\(Date().timeIntervalSince1970)")

            // Fetch TMDB stills for fallback if we have a TMDB ID and season number
            var tmdbStills: [Int: String] = [:] // episode_number -> still_path
            if let tid = tmdbId, let sNum = seasonNumber {
                do {
                    struct TMDBSeasonData: Codable {
                        struct TMDBEp: Codable { let episode_number: Int?; let still_path: String? }
                        let episodes: [TMDBEp]?
                    }
                    print("📡 [loadPlexEpisodes] Fetching TMDB stills for season \(sNum) fallback...")
                    let tmdbSeason: TMDBSeasonData = try await api.get("/api/tmdb/tv/\(tid)/season/\(sNum)")
                    for ep in tmdbSeason.episodes ?? [] {
                        if let epNum = ep.episode_number, let still = ep.still_path {
                            tmdbStills[epNum] = still
                        }
                    }
                    print("✅ [loadPlexEpisodes] Cached \(tmdbStills.count) TMDB episode stills for fallback")
                } catch {
                    print("⚠️ [loadPlexEpisodes] Failed to fetch TMDB stills: \(error)")
                }
            }

            let eps: [Episode] = (ch.Metadata ?? []).map { e in
                // Determine image URL: TMDB still (preferred) > Plex thumb > Plex parentThumb
                // TMDB stills are typically official, curated images vs Plex auto-generated screen grabs
                var url: URL?
                if let epIndex = e.index, let stillPath = tmdbStills[epIndex] {
                    // Prefer TMDB still_path when available
                    url = URL(string: "https://image.tmdb.org/t/p/w780\(stillPath)")
                } else if let thumb = e.thumb {
                    url = ImageService.shared.plexImageURL(path: thumb, width: 600, height: 338)
                } else if let parentThumb = e.parentThumb {
                    url = ImageService.shared.plexImageURL(path: parentThumb, width: 600, height: 338)
                }

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
                return Episode(id: "plex:\(e.ratingKey)", title: e.title, overview: e.summary, image: url, durationMin: dur, progressPct: pct, viewOffset: e.viewOffset, seasonNumber: seasonNumber, episodeNumber: e.index)
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
            let mapped = ss.map { Season(id: "tmdb:season:\(tid):\($0)", title: "Season \($0)", source: "tmdb", number: $0) }
            await MainActor.run {
                self.seasons = mapped
                self.selectedSeasonKey = mapped.first?.id
                self.currentSeasonNumber = mapped.first?.number
            }
            if let first = mapped.first { await loadTMDBEpisodes(seasonId: first.id) }
        } catch {}
    }

    // Public episode reload when UI changes season
    func selectSeason(_ key: String) async {
        // Find the season number from our seasons array
        let seasonNumber = seasons.first(where: { $0.id == key })?.number
        await MainActor.run {
            self.selectedSeasonKey = key
            self.episodesLoading = true
            self.currentSeasonNumber = seasonNumber
        }
        if key.hasPrefix("tmdb:season:") {
            await loadTMDBEpisodes(seasonId: key)
        } else {
            await loadPlexEpisodes(seasonKey: key, seasonNumber: seasonNumber)
        }
        // Fetch technical details from first episode of this season
        await fetchTechnicalDetailsFromFirstEpisode()
        await MainActor.run { self.episodesLoading = false }
    }

    /// Fetch technical details (badges, versions) from the first episode of the current season
    /// This is used for TV shows to display technical info like resolution, HDR, Atmos
    private func fetchTechnicalDetailsFromFirstEpisode() async {
        // Only for Plex TV shows
        guard mediaKind == "tv", !episodes.isEmpty else {
            print("⚠️ [fetchTechnicalDetailsFromFirstEpisode] Skipping - not a TV show or no episodes")
            return
        }

        guard let firstEpisode = episodes.first,
              firstEpisode.id.hasPrefix("plex:") else {
            print("⚠️ [fetchTechnicalDetailsFromFirstEpisode] First episode is not from Plex")
            return
        }

        let ratingKey = firstEpisode.id.replacingOccurrences(of: "plex:", with: "")
        print("📺 [fetchTechnicalDetailsFromFirstEpisode] Fetching technical details from episode: \(ratingKey)")

        do {
            let meta: PlexMeta = try await api.get("/api/plex/metadata/\(ratingKey)")
            guard let media = meta.Media, !media.isEmpty else {
                print("⚠️ [fetchTechnicalDetailsFromFirstEpisode] No media found for episode")
                return
            }

            await MainActor.run {
                // Clear existing technical badges (keep non-technical ones like "Plex")
                self.badges = self.badges.filter { badge in
                    !["4K", "HDR", "Dolby Vision", "Atmos"].contains(badge)
                }
                // Add technical badges from episode
                self.appendTechnicalBadges(from: media)
                // Update versions
                self.hydrateVersions(from: media)
                print("✅ [fetchTechnicalDetailsFromFirstEpisode] Updated technical details from S\(self.currentSeasonNumber ?? 1)E1")
            }
        } catch {
            print("❌ [fetchTechnicalDetailsFromFirstEpisode] Failed to fetch episode metadata: \(error)")
        }
    }

    private func loadTMDBEpisodes(seasonId: String) async {
        // seasonId = tmdb:season:<tvId>:<S>
        let parts = seasonId.split(separator: ":")
        guard parts.count == 4, parts[0] == "tmdb", parts[1] == "season" else { return }
        let tvId = String(parts[2])
        guard let seasonNumber = Int(parts[3]) else { return }
        do {
            struct SD: Codable { let episodes: [SE]? }
            struct SE: Codable { let id: Int?; let name: String?; let overview: String?; let still_path: String?; let runtime: Int?; let episode_number: Int? }
            let data: SD = try await api.get("/api/tmdb/tv/\(tvId)/season/\(seasonNumber)")
            let eps: [Episode] = (data.episodes ?? []).map { e in
                let url = ImageService.shared.proxyImageURL(url: e.still_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }, width: 600, height: 338)
                return Episode(id: "tmdb:tv:\(e.id ?? 0)", title: e.name ?? "Episode", overview: e.overview, image: url, durationMin: e.runtime, progressPct: nil, viewOffset: nil, seasonNumber: seasonNumber, episodeNumber: e.episode_number)
            }
            await MainActor.run {
                self.episodes = eps
                self.episodesLoading = false
            }
        } catch {
            await MainActor.run { self.episodesLoading = false }
        }
    }

    func loadPlexExtras(ratingKey: String) async {
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
}

// MARK: - Watch-state / Trakt targets

extension DetailsViewModel {
    /// The parent show's Plex ratingKey for the episodes on screen: the show
    /// itself on show pages, the parent show on season and episode pages.
    var showPlexKeyForEpisodes: String? {
        if isEpisode { return showRatingKey }
        if isSeason { return parentShowKey }
        return showRatingKey ?? plexRatingKey
    }

    /// The show's TMDB id when it's known for sure. Season-only pages carry the
    /// season's Plex GUID, so their ids are left for WatchStateService to resolve.
    var showTmdbIdForEpisodes: String? {
        isSeason ? nil : tmdbId
    }

    /// Target for an episode row (watched actions).
    func watchTarget(for episode: Episode) -> WatchStateTarget {
        .episode(
            episode,
            showTmdbId: showTmdbIdForEpisodes,
            showImdbId: isSeason || isEpisode ? nil : imdbId,
            showPlexRatingKey: showPlexKeyForEpisodes
        )
    }

    /// Target for the title on screen (movie, show, season or episode), e.g. for
    /// Trakt comments. Nil until the page has an id to work with.
    var titleWatchTarget: WatchStateTarget? {
        let tmdb = tmdbId.flatMap { Int($0) }
        let plexKey = plexRatingKey
        if isEpisode {
            guard plexKey != nil || tmdb != nil else { return nil }
            return WatchStateTarget(
                kind: .episode(season: seasonNumber, episode: episodeNumber),
                plexRatingKey: plexKey,
                showPlexRatingKey: showRatingKey,
                tmdbId: tmdb,
                title: showTitle
            )
        }
        if isSeason {
            guard plexKey != nil else { return nil }
            return WatchStateTarget(
                kind: .season(currentSeasonNumber),
                plexRatingKey: plexKey,
                showPlexRatingKey: parentShowKey,
                title: title
            )
        }
        guard plexKey != nil || tmdb != nil || imdbId != nil else { return nil }
        if mediaKind == "movie" {
            return .movie(tmdbId: tmdb, imdbId: imdbId, plexRatingKey: plexKey, title: title)
        }
        if mediaKind == "tv" {
            return .show(tmdbId: tmdb, imdbId: imdbId, plexRatingKey: plexKey, title: title)
        }
        return nil
    }
}
