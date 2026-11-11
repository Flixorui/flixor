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
        episodesLoading = true
        // Prefer Plex if mapped
        if let showKey = plexShowKeyFromPlayableId {
            print("📺 [loadSeasonsAndEpisodes] Loading Plex seasons for showKey: \(showKey)")
            await loadPlexSeasons(showKey: showKey)
            if seasons.isEmpty {
                print("⚠️ [loadSeasonsAndEpisodes] Plex seasons empty, but we have Plex mapping - NOT falling back to TMDB")
                episodesLoading = false
            }
        } else {
            print("📺 [loadSeasonsAndEpisodes] No Plex mapping, loading TMDB seasons")
            await loadTMDBSeasons()
        }
    }

    private var plexShowKeyFromPlayableId: String? {
        guard let pid = playableId, pid.hasPrefix("plex:") else { return nil }
        return pid.split(separator: ":").last.map(String.init)
    }

    private func loadPlexSeasons(showKey: String) async {
        do {
            // Backend returns MediaContainer directly (not wrapped)
            struct MC: Codable {
                let Metadata: [M]?
                let size: Int?
            }
            struct M: Codable { let ratingKey: String; let title: String; let index: Int?; let thumb: String?; let leafCount: Int?; let viewedLeafCount: Int? }
            let ch: MC = try await api.get("/api/plex/dir/library/metadata/\(showKey)/children")
            let list = ch.Metadata ?? []
            let ss = list.map { m in
                // Parse season number from title if index is missing (e.g., "Season 1" -> 1)
                let seasonNum = m.index ?? Int(m.title.replacingOccurrences(of: "Season ", with: ""))
                return Season(id: m.ratingKey, title: m.title, source: "plex", number: seasonNum)
            }
            var info: [String: PlexSeasonInfo] = [:]
            for m in list {
                info[m.ratingKey] = PlexSeasonInfo(thumb: m.thumb, leafCount: m.leafCount, viewedLeafCount: m.viewedLeafCount)
            }
            plexSeasonInfo = info
            seasons = ss
            selectedSeasonKey = ss.first?.id
            currentSeasonNumber = ss.first?.number

            async let deck: Void = loadPlexOnDeck(showKey: showKey)
            await loadPlexEpisodes(seasonKey: ss.first?.id, seasonNumber: ss.first?.number)
            // Fetch technical details from first episode of first season
            await fetchTechnicalDetailsFromFirstEpisode()
            _ = await deck
        } catch {
            print("❌ [loadPlexSeasons] Failed: \(error)")
            loadHadPartialFailure = true
        }
    }

    /// On Deck for the show on screen (called again when returning to the page).
    func refreshPlexOnDeck() async {
        guard let showKey = plexShowKeyFromPlayableId else { return }
        await loadPlexOnDeck(showKey: showKey)
    }

    private func loadPlexOnDeck(showKey: String) async {
        struct MC: Codable { let Metadata: [M]? }
        struct M: Codable { let ratingKey: String; let title: String; let index: Int? }
        guard let od: MC = try? await api.get("/api/plex/dir/library/metadata/\(showKey)/onDeck") else { return }
        guard plexShowKeyFromPlayableId == showKey else { return }
        if let ep = od.Metadata?.first {
            let image = ImageService.shared.plexImageURL(path: ep.ratingKey, width: 600, height: 338) // best-effort
            onDeck = Episode(id: "plex:\(ep.ratingKey)", title: ep.title, overview: nil, image: image, durationMin: nil, progressPct: nil, viewOffset: nil, seasonNumber: nil, episodeNumber: ep.index)
        } else if onDeck != nil {
            onDeck = nil
        }
    }

    private struct PlexEpisodeRow: Codable { let ratingKey: String; let title: String; let summary: String?; let thumb: String?; let parentThumb: String?; let duration: Int?; let viewOffset: Int?; let viewCount: Int?; let index: Int? }

    private enum EpisodeListPart {
        case plex([PlexEpisodeRow]?)
        case stills([Int: String])
    }

    /// Plex episodes of a season. TMDB stills (preferred artwork) load alongside:
    /// the list is shown as soon as Plex answers and the stills fill in after.
    func loadPlexEpisodes(seasonKey: String?, seasonNumber: Int? = nil) async {
        guard let seasonKey = seasonKey else {
            print("⚠️ [loadPlexEpisodes] No season key provided")
            return
        }
        let stillsKey: String? = {
            guard let tid = tmdbId, let sNum = seasonNumber else { return nil }
            return "\(tid):\(sNum)"
        }()
        let token = loadToken
        let cachedStills = stillsKey.flatMap { tmdbStillsCache[$0] }
        let fetchesStills = stillsKey != nil && cachedStills == nil
        let tid = tmdbId

        var rows: [PlexEpisodeRow]?
        var stills = cachedStills ?? [:]
        var failed = false
        await withTaskGroup(of: EpisodeListPart.self) { group in
            group.addTask { [api] in
                // Backend returns MediaContainer directly (not wrapped)
                struct MC: Codable { let Metadata: [PlexEpisodeRow]? }
                let ch: MC? = try? await api.get("/api/plex/dir/library/metadata/\(seasonKey)/children?nocache=\(Date().timeIntervalSince1970)")
                return .plex(ch.map { $0.Metadata ?? [] })
            }
            if fetchesStills, let tid, let sNum = seasonNumber {
                group.addTask { [api] in
                    struct TMDBSeasonData: Codable {
                        struct TMDBEp: Codable { let episode_number: Int?; let still_path: String? }
                        let episodes: [TMDBEp]?
                    }
                    var found: [Int: String] = [:]
                    if let season: TMDBSeasonData = try? await api.get("/api/tmdb/tv/\(tid)/season/\(sNum)") {
                        for ep in season.episodes ?? [] {
                            if let epNum = ep.episode_number, let still = ep.still_path {
                                found[epNum] = still
                            }
                        }
                    }
                    return .stills(found)
                }
            }
            for await part in group {
                // A title opened in place since owns the list now.
                guard token == loadToken else { continue }
                switch part {
                case .plex(let list):
                    guard let list else {
                        failed = true
                        continue
                    }
                    rows = list
                    publishEpisodes(list, stills: stills, seasonKey: seasonKey, seasonNumber: seasonNumber)
                case .stills(let found):
                    if let stillsKey { tmdbStillsCache[stillsKey] = found }
                    guard !found.isEmpty else { continue }
                    stills = found
                    if let rows {
                        publishEpisodes(rows, stills: stills, seasonKey: seasonKey, seasonNumber: seasonNumber)
                    }
                }
            }
        }
        if failed && token == loadToken {
            loadHadPartialFailure = true
            print("❌ [loadPlexEpisodes] Failed to load episodes for season: \(seasonKey)")
            episodesLoading = false
        }
    }

    private func publishEpisodes(_ rows: [PlexEpisodeRow], stills: [Int: String], seasonKey: String, seasonNumber: Int?) {
        // A newer season selection owns the list.
        if let selected = selectedSeasonKey, selected != seasonKey { return }
        let eps: [Episode] = rows.map { e in
            // Determine image URL: TMDB still (preferred) > Plex thumb > Plex parentThumb
            // TMDB stills are typically official, curated images vs Plex auto-generated screen grabs
            var url: URL?
            if let epIndex = e.index, let stillPath = stills[epIndex] {
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
        episodes = eps
        if episodesLoading { episodesLoading = false }
    }

    private func loadTMDBSeasons() async {
        guard mediaKind == "tv", let tid = tmdbId else { return }
        // The details response already listed the seasons; fetch only if it didn't load.
        var numbers = tmdbSeasonInfo?.map(\.number)
        if numbers == nil {
            struct TV: Codable { let seasons: [TS]? }
            struct TS: Codable { let season_number: Int? }
            guard let tv: TV = try? await api.get("/api/tmdb/tv/\(tid)") else {
                loadHadPartialFailure = true
                episodesLoading = false
                return
            }
            numbers = (tv.seasons ?? []).compactMap { $0.season_number }
        }
        let ss = (numbers ?? []).filter { $0 > 0 }
        let mapped = ss.map { Season(id: "tmdb:season:\(tid):\($0)", title: String(localized: "Season \(String($0))"), source: "tmdb", number: $0) }
        seasons = mapped
        selectedSeasonKey = mapped.first?.id
        currentSeasonNumber = mapped.first?.number
        if let first = mapped.first {
            await loadTMDBEpisodes(seasonId: first.id)
        } else {
            episodesLoading = false
        }
    }

    // Public episode reload when UI changes season
    func selectSeason(_ key: String) async {
        // Find the season number from our seasons array
        let seasonNumber = seasons.first(where: { $0.id == key })?.number
        let token = loadToken
        selectedSeasonKey = key
        episodesLoading = true
        currentSeasonNumber = seasonNumber
        if key.hasPrefix("tmdb:season:") {
            await loadTMDBEpisodes(seasonId: key)
        } else {
            await loadPlexEpisodes(seasonKey: key, seasonNumber: seasonNumber)
        }
        guard token == loadToken else { return }
        // Fetch technical details from first episode of this season
        await fetchTechnicalDetailsFromFirstEpisode()
        if token == loadToken && selectedSeasonKey == key { episodesLoading = false }
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
        let token = loadToken

        do {
            let meta: PlexMeta = try await api.get("/api/plex/metadata/\(ratingKey)")
            guard token == loadToken else { return }
            guard let media = meta.Media, !media.isEmpty else {
                print("⚠️ [fetchTechnicalDetailsFromFirstEpisode] No media found for episode")
                return
            }

            // Clear existing technical badges (keep non-technical ones like "Plex")
            self.badges = self.badges.filter { badge in
                !["4K", "HDR", "Dolby Vision", "Atmos"].contains(badge)
            }
            // Add technical badges from episode
            self.appendTechnicalBadges(from: media)
            // Update versions
            self.hydrateVersions(from: media)
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
        let token = loadToken
        do {
            struct SD: Codable { let episodes: [SE]? }
            struct SE: Codable { let id: Int?; let name: String?; let overview: String?; let still_path: String?; let runtime: Int?; let episode_number: Int? }
            let data: SD = try await api.get("/api/tmdb/tv/\(tvId)/season/\(seasonNumber)")
            guard token == loadToken, selectedSeasonKey == seasonId else { return }
            let eps: [Episode] = (data.episodes ?? []).map { e in
                let url = ImageService.shared.proxyImageURL(url: e.still_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }, width: 600, height: 338)
                return Episode(id: "tmdb:tv:\(e.id ?? 0)", title: e.name ?? String(localized: "Episode"), overview: e.overview, image: url, durationMin: e.runtime, progressPct: nil, viewOffset: nil, seasonNumber: seasonNumber, episodeNumber: e.episode_number)
            }
            self.episodes = eps
            self.episodesLoading = false
        } catch {
            guard token == loadToken else { return }
            loadHadPartialFailure = true
            self.episodesLoading = false
        }
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
