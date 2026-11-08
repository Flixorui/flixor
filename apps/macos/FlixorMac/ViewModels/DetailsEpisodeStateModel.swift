//
//  DetailsEpisodeStateModel.swift
//  FlixorMac
//
//  Per-page episode extras for the details Episodes section: TMDB episode
//  ratings, watched state (Plex progress, locally watched episodes and
//  optimistic overrides), watched actions with toasts, spoiler reveals and
//  season poster art. Kept out of DetailsViewModel so it owns no stored state there.
//

import Foundation
import SwiftUI
import FlixorKit

@MainActor
final class DetailsEpisodeStateModel: ObservableObject {
    struct SeasonArt: Equatable {
        let posterURL: URL?
        let episodeCount: Int?
        let watchedCount: Int?
    }

    /// TMDB rating (0-10) by episode number, for `ratingsSeason`.
    @Published private(set) var ratings: [Int: Double] = [:]
    /// Locally watched (season, episode) pairs for the show.
    @Published private(set) var locallyWatched: Set<EpisodeNumber> = []
    /// Optimistic watched state by episode id until the list is refreshed.
    @Published private(set) var overrides: [String: Bool] = [:]
    /// Episodes the user revealed while spoiler protection is on.
    @Published private(set) var revealed: Set<String> = []
    /// Poster art and counts by season id (`DetailsViewModel.Season.id`).
    @Published private(set) var seasonArt: [String: SeasonArt] = [:]
    /// Season actions in flight (disables the season menu items).
    @Published private(set) var seasonActionInFlight = false

    /// Season the ratings and local watched set belong to (resolved for season pages).
    private(set) var contextSeason: Int?
    private var contextKey: String?
    private var seasonArtKey: String?
    private var refreshTask: Task<Void, Never>?

    // MARK: - Context (ratings + local watched)

    /// Loads ratings and locally watched episodes for the season on screen.
    func refreshContext(vm: DetailsViewModel, force: Bool = false) async {
        let key = Self.contextKey(vm)
        guard force || key != contextKey else { return }
        if key != contextKey {
            ratings = [:]
            overrides = [:]
            revealed = []
        }
        contextKey = key

        let ids = await showIds(vm: vm)
        guard contextKey == key, !Task.isCancelled else { return }
        contextSeason = ids.season

        async let local = WatchStateService.shared.locallyWatchedEpisodes(
            showTmdbId: ids.tmdb, showImdbId: ids.imdb, season: ids.season
        )
        var fetched: [Int: Double] = [:]
        if let tmdb = ids.tmdb, let season = ids.season {
            for rating in await EpisodeRatingsService.shared.ratings(tmdbShowId: tmdb, season: season) {
                fetched[rating.episode] = rating.rating
            }
        }
        let localSet = await local
        guard contextKey == key else { return }
        ratings = fetched
        locallyWatched = localSet
    }

    private static func contextKey(_ vm: DetailsViewModel) -> String {
        [
            vm.tmdbId ?? "-", vm.imdbId ?? "-", vm.plexRatingKey ?? "-",
            vm.selectedSeasonKey ?? "-", vm.currentSeasonNumber.map(String.init) ?? "-",
            vm.isSeason ? "season" : "show"
        ].joined(separator: "|")
    }

    /// Show TMDB/IMDb ids and the season number on screen. Season-only pages
    /// resolve them from Plex (their own GUID is the season's).
    private func showIds(vm: DetailsViewModel) async -> (tmdb: Int?, imdb: String?, season: Int?) {
        if vm.isSeason {
            guard let target = vm.titleWatchTarget else { return (nil, nil, nil) }
            let resolved = await WatchStateService.shared.resolve(target, needTitleIds: true)
            return (resolved.tmdbId, resolved.imdbId, resolved.seasonNumber)
        }
        let season = vm.currentSeasonNumber
            ?? vm.seasons.first(where: { $0.id == vm.selectedSeasonKey })?.number
        return (vm.tmdbId.flatMap { Int($0) }, vm.imdbId, season)
    }

    // MARK: - Queries

    func rating(for episode: DetailsViewModel.Episode) -> Double? {
        guard let number = episode.episodeNumber else { return nil }
        if let season = episode.seasonNumber, let contextSeason, season != contextSeason { return nil }
        return ratings[number]
    }

    func isWatched(_ episode: DetailsViewModel.Episode) -> Bool {
        if let override = overrides[episode.id] { return override }
        if (episode.progressPct ?? 0) >= 85 { return true }
        guard let number = episode.episodeNumber,
              let season = episode.seasonNumber ?? contextSeason else { return false }
        return locallyWatched.contains(EpisodeNumber(season: season, episode: number))
    }

    func isRevealed(_ episode: DetailsViewModel.Episode) -> Bool {
        revealed.contains(episode.id)
    }

    func toggleRevealed(_ episode: DetailsViewModel.Episode) {
        if revealed.contains(episode.id) {
            revealed.remove(episode.id)
        } else {
            revealed.insert(episode.id)
        }
    }

    // MARK: - Watched actions

    func setWatched(_ episode: DetailsViewModel.Episode, watched: Bool, vm: DetailsViewModel) async {
        let target = vm.watchTarget(for: episode)
        let previous = overrides[episode.id]
        withAnimation(DS.Motion.quick) { overrides[episode.id] = watched }

        let service = WatchStateService.shared
        let result = watched ? await service.markWatched(target) : await service.markUnwatched(target)
        if !result.isSuccess && !result.isPartialSuccess {
            withAnimation(DS.Motion.quick) { overrides[episode.id] = previous }
        }
        Self.showToast(for: result)
    }

    func setSeasonWatched(_ watched: Bool, vm: DetailsViewModel) async {
        guard !seasonActionInFlight, let target = seasonTarget(vm: vm) else { return }
        seasonActionInFlight = true
        defer { seasonActionInFlight = false }

        let episodes = vm.episodes
        let previous = Dictionary(uniqueKeysWithValues: episodes.map { ($0.id, overrides[$0.id]) })
        withAnimation(DS.Motion.quick) {
            for episode in episodes { overrides[episode.id] = watched }
        }

        let service = WatchStateService.shared
        let result = watched ? await service.markWatched(target) : await service.markUnwatched(target)
        if !result.isSuccess && !result.isPartialSuccess {
            withAnimation(DS.Motion.quick) {
                for (id, value) in previous { overrides[id] = value }
            }
        }
        Self.showToast(for: result)
    }

    func isInFlight(_ episode: DetailsViewModel.Episode, vm: DetailsViewModel) -> Bool {
        WatchStateService.shared.inFlight.contains(vm.watchTarget(for: episode).actionKey)
    }

    /// The season on screen as a watch-state target.
    func seasonTarget(vm: DetailsViewModel) -> WatchStateTarget? {
        if vm.isSeason { return vm.titleWatchTarget }
        guard let seasonKey = vm.selectedSeasonKey else { return nil }
        let plexKey = seasonKey.hasPrefix("tmdb:") ? nil : seasonKey
        let number = vm.currentSeasonNumber ?? vm.seasons.first(where: { $0.id == seasonKey })?.number
        guard plexKey != nil || number != nil else { return nil }
        return WatchStateTarget(
            kind: .season(number),
            plexRatingKey: plexKey,
            showPlexRatingKey: plexKey != nil ? vm.showPlexKeyForEpisodes : nil,
            tmdbId: vm.tmdbId.flatMap { Int($0) },
            imdbId: vm.imdbId,
            title: vm.title
        )
    }

    private static func showToast(for result: WatchStateResult) {
        let type: ToastView.ToastType = result.isSuccess ? .success : (result.isPartialSuccess ? .info : .error)
        ToastManager.shared.show(result.message, type: type)
    }

    // MARK: - Refresh after changes

    /// Reloads the episode list (Plex view counts) and local watched state after
    /// a watch-state change, then drops the optimistic overrides.
    func handleWatchStateChange(_ change: WatchStateChange?, vm: DetailsViewModel) {
        if let change, change.target.kind == .movie { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if let seasonKey = Self.plexSeasonKey(vm: vm) {
                await vm.loadPlexEpisodes(seasonKey: seasonKey, seasonNumber: vm.currentSeasonNumber)
            }
            guard !Task.isCancelled else { return }
            await self.refreshContext(vm: vm, force: true)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.quick) { self.overrides = [:] }
            if self.seasonArtKey != nil {
                self.seasonArtKey = nil
                await self.loadSeasonArt(vm: vm)
            }
        }
    }

    /// Plex ratingKey of the season whose episodes are listed, if they come from Plex.
    private static func plexSeasonKey(vm: DetailsViewModel) -> String? {
        if vm.isSeason { return vm.plexRatingKey }
        guard let key = vm.selectedSeasonKey, !key.hasPrefix("tmdb:") else { return nil }
        return key
    }

    // MARK: - Season art (poster picker)

    /// Loads season posters and episode counts: Plex season children for Plex
    /// shows, TMDB season summaries otherwise (and for missing Plex posters).
    func loadSeasonArt(vm: DetailsViewModel) async {
        let seasons = vm.seasons
        guard !seasons.isEmpty else { return }
        let key = seasons.map(\.id).joined(separator: ",")
        guard key != seasonArtKey else { return }
        seasonArtKey = key

        var art: [String: SeasonArt] = [:]

        // Plex: one request for all seasons of the show.
        if seasons.contains(where: { $0.source == "plex" }), let showKey = vm.showPlexKeyForEpisodes {
            struct MC: Decodable { let Metadata: [M]? }
            struct M: Decodable { let ratingKey: String; let thumb: String?; let leafCount: Int?; let viewedLeafCount: Int? }
            if let container: MC = try? await vm.api.get("/api/plex/dir/library/metadata/\(showKey)/children", bypassCache: true) {
                for m in container.Metadata ?? [] {
                    art[m.ratingKey] = SeasonArt(
                        posterURL: ImageService.shared.plexImageURL(path: m.thumb, width: 300, height: 450),
                        episodeCount: m.leafCount,
                        watchedCount: m.viewedLeafCount
                    )
                }
            }
        }

        // TMDB: fill seasons without art (and every season for TMDB-sourced lists).
        let missing = seasons.filter { art[$0.id]?.posterURL == nil }
        if !missing.isEmpty, let tmdb = vm.tmdbId.flatMap({ Int($0) }), !vm.isSeason,
           let details = try? await FlixorCore.shared.tmdb.getTVDetails(id: tmdb) {
            var byNumber: [Int: TMDBSeasonSummary] = [:]
            for summary in details.seasons {
                if let n = summary.seasonNumber { byNumber[n] = summary }
            }
            for season in missing {
                guard let n = season.number, let summary = byNumber[n] else { continue }
                let existing = art[season.id]
                art[season.id] = SeasonArt(
                    posterURL: ImageService.shared.tmdbImageURL(path: summary.posterPath, size: .w342),
                    episodeCount: existing?.episodeCount ?? summary.episodeCount,
                    watchedCount: existing?.watchedCount
                )
            }
        }

        guard seasonArtKey == key else { return }
        seasonArt = art
    }
}
