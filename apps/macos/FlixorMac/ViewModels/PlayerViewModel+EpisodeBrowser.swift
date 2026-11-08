//
//  PlayerViewModel+EpisodeBrowser.swift
//  FlixorMac
//
//  The player's episode panel: browse other seasons (Plex and addon streams),
//  and the addon sources list for switching source during playback.
//

import Foundation
import FlixorKit

extension PlayerViewModel {
    // MARK: - Episode browser

    /// `EpisodeMetadata.ratingKey` of the episode playing now.
    var currentEpisodeListKey: String {
        if let current = streamPlaybackItem, let ref = StreamSeriesRef(item: current) {
            return "stream-episode:\(ref.baseId):\(ref.season):\(ref.episode)"
        }
        return item.id.replacingOccurrences(of: "plex:", with: "")
    }

    private var currentEpisodeSeason: Int? {
        if let current = streamPlaybackItem, let ref = StreamSeriesRef(item: current) { return ref.season }
        return item.parentIndex
    }

    /// Episodes the panel shows: the season being browsed, else the current one.
    var episodesForBrowser: [EpisodeMetadata] {
        episodeBrowserEpisodes.isEmpty ? seasonEpisodes : episodeBrowserEpisodes
    }

    /// Resets the panel to the playing season and loads the list of seasons.
    func prepareEpisodeBrowser() {
        episodeBrowserTask?.cancel()
        episodeBrowserSeason = currentEpisodeSeason
        episodeBrowserEpisodes = seasonEpisodes
        guard episodeBrowserSeasons.isEmpty else { return }

        episodeBrowserTask = Task { [weak self] in
            guard let self else { return }
            let seasons: [Int]
            if let current = self.streamPlaybackItem, let ref = StreamSeriesRef(item: current) {
                seasons = await StreamEpisodeNavigator.seasonNumbers(for: ref)
            } else {
                seasons = await self.loadPlexSeasonNumbers()
            }
            guard !Task.isCancelled else { return }
            self.episodeBrowserSeasons = seasons
        }
    }

    func selectEpisodeBrowserSeason(_ season: Int) {
        guard season != episodeBrowserSeason else { return }
        episodeBrowserTask?.cancel()
        episodeBrowserSeason = season

        // The playing season is already loaded.
        if season == currentEpisodeSeason, !seasonEpisodes.isEmpty {
            episodeBrowserEpisodes = seasonEpisodes
            isLoadingEpisodeBrowser = false
            return
        }

        isLoadingEpisodeBrowser = true
        episodeBrowserTask = Task { [weak self] in
            guard let self else { return }
            let episodes: [EpisodeMetadata]
            if let current = self.streamPlaybackItem, let ref = StreamSeriesRef(item: current) {
                episodes = await StreamEpisodeNavigator.episodes(for: ref, season: season)
                    .map { $0.episodeMetadata(baseId: ref.baseId) }
            } else {
                episodes = await self.loadPlexEpisodes(season: season)
            }
            guard !Task.isCancelled, self.episodeBrowserSeason == season else { return }
            self.episodeBrowserEpisodes = episodes
            self.isLoadingEpisodeBrowser = false
        }
    }

    private func loadPlexSeasonNumbers() async -> [Int] {
        guard let showKey = item.grandparentRatingKey?.replacingOccurrences(of: "plex:", with: ""),
              !showKey.isEmpty,
              let plex = FlixorCore.shared.plexServer,
              let children = try? await plex.getChildren(ratingKey: showKey) else { return [] }
        var keys: [Int: String] = [:]
        for season in children {
            if let index = season.index { keys[index] = season.ratingKey }
        }
        episodeBrowserPlexSeasonKeys = keys
        return keys.keys.sorted()
    }

    private func loadPlexEpisodes(season: Int) async -> [EpisodeMetadata] {
        guard let key = episodeBrowserPlexSeasonKeys[season] else { return [] }
        struct EpisodeResponse: Decodable { let Metadata: [EpisodeMetadata]? }
        let response: EpisodeResponse? = try? await api.get("/api/plex/dir/library/metadata/\(key)/children")
        return response?.Metadata ?? []
    }

    // MARK: - Sources

    /// Refreshes the list the first time the panel opens for a title: playback can
    /// start from a cached source or before slower addons have answered.
    func refreshStreamSourcesIfNeeded() {
        guard let key = streamPlaybackItem?.contentKey, streamSourcesRefreshedKey != key else { return }
        streamSourcesRefreshedKey = key
        refreshStreamSources()
    }

    /// Fetches every addon's sources for the current title.
    func refreshStreamSources() {
        guard sourceKind == .stream, !isLoadingStreamSources,
              let current = streamPlaybackItem,
              let identity = StreamRecoveryService.identity(for: current, source: "player-sources") else { return }
        isLoadingStreamSources = true
        Task { [weak self] in
            let results = await StreamRecoveryService.fetchStreams(identity: identity)
            guard let self else { return }
            self.isLoadingStreamSources = false
            let streams = (results ?? []).flatMap(\.streams).filter(\.playable)
            guard !streams.isEmpty else { return }
            self.availableStremioSources = streams
            if let uri = self.streamPlaybackItem?.uri,
               let playing = streams.first(where: { $0.url == uri }) {
                self.currentStremioSourceId = playing.id
            }
        }
    }
}
