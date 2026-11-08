//
//  PlayerViewModel+StreamNextEpisode.swift
//  FlixorMac
//
//  Next episode for addon (Stremio) series streams: episode list + next episode
//  from TMDB / addon meta, shown through the existing next-episode countdown,
//  hover card and episode list; on play-next a source is picked automatically
//  (same addon + binge group, else best ranked), else the sources picker opens.
//

import Foundation

extension PlayerViewModel {
    // MARK: - Episode data

    /// Loads the season's episodes and the next episode for a series stream.
    func loadStreamNextEpisode(for streamItem: StreamPlaybackItem) {
        guard let ref = StreamSeriesRef(item: streamItem) else { return }
        let contentKey = streamItem.contentKey
        streamNextEpisodeTask?.cancel()
        streamNextEpisodeTask = Task { [weak self] in
            let result = await StreamEpisodeNavigator.episodes(for: ref)
            guard !Task.isCancelled, let self, self.streamPlaybackItem?.contentKey == contentKey else { return }
            self.streamSeasonEpisodeInfos = result.seasonEpisodes
            self.streamNextEpisodeInfo = result.next
            self.seasonEpisodes = result.seasonEpisodes.map { $0.episodeMetadata(baseId: ref.baseId) }
            self.nextEpisode = result.next?.episodeMetadata(baseId: ref.baseId)
            print("📺 [Player] Stream next episode: \(result.next.map { "\($0.label) \($0.title)" } ?? "none")")
        }
    }

    /// Clears next-episode state (new title).
    func resetStreamNextEpisode() {
        streamNextEpisodeTask?.cancel()
        streamNextEpisodeTask = nil
        streamNextEpisodeInfo = nil
        streamSeasonEpisodeInfos = []
        nextEpisodeSourceTask?.cancel()
        nextEpisodeSourceTask = nil
        nextEpisodeSourceKey = nil
    }

    // MARK: - Play next

    /// Starts resolving the next episode's source ahead of time (countdown shown,
    /// or close to the trigger point), so play-next is instant.
    func prefetchNextEpisodeSourceIfNeeded() {
        guard sourceKind == .stream, let next = streamNextEpisodeInfo else { return }
        _ = episodeSourceTask(season: next.season, episode: next.episode, episodeTitle: next.title)
    }

    /// Play the next episode of a series stream.
    func playNextStreamEpisode() {
        guard let next = streamNextEpisodeInfo else { return }
        playStreamEpisode(season: next.season, episode: next.episode, episodeTitle: next.title)
    }

    /// Play a given episode of the current series stream (next episode or episode list).
    func playStreamEpisode(season: Int, episode: Int, episodeTitle: String?) {
        guard sourceKind == .stream, !isResolvingNextEpisode, mpvController?.isShutDown == false else { return }
        cancelCountdown()
        cancelAutoSkip()

        let label = "S\(season)E\(episode)"
        isResolvingNextEpisode = true
        streamEngineStatus = .findingNextEpisodeSource(episodeLabel: label)
        // Every outcome leaves this episode (new player, picker or error), so pause
        // and show the loading state while the lookup runs.
        mpvController?.pause()
        isPlaying = false
        isLoading = true
        let task = episodeSourceTask(season: season, episode: episode, episodeTitle: episodeTitle)

        Task { [weak self] in
            let outcome = await task.value
            guard let self else { return }
            self.isResolvingNextEpisode = false
            if case .findingNextEpisodeSource = self.streamEngineStatus { self.streamEngineStatus = nil }
            // The user closed the player during the lookup: don't navigate anywhere.
            guard self.mpvController?.isShutDown == false else { return }

            switch outcome {
            case .playable(let playbackItem):
                print("▶️ [Player] Play \(label) from \(playbackItem.addonName ?? "addon")")
                self.stopPlayback()
                self.onPlayNext?(.stream(playbackItem))
            case .needsPicker(let destination):
                print("⚠️ [Player] No source picked automatically for \(label); asking the user")
                self.sourcesPickerDestination = destination
                if self.onOpenStremioSources != nil {
                    self.openSourcesPicker()
                } else {
                    self.error = String(localized: "Couldn't pick a source for \(label) automatically. Close the player and choose one from the episode list.")
                    self.isLoading = false
                }
            case .unavailable(let message):
                self.error = message
                self.isLoading = false
            }
        }
    }

    /// Opens the Stremio sources picker for `sourcesPickerDestination` (or the
    /// current title) and leaves the player. No-op when the view didn't wire
    /// `onOpenStremioSources`.
    func openSourcesPicker() {
        guard let open = onOpenStremioSources,
              let destination = sourcesPickerDestination ?? currentTitleSourcesDestination() else { return }
        stopPlayback()
        open(destination)
    }

    /// Sources-picker destination for the title currently playing.
    func currentTitleSourcesDestination() -> StremioSourcesDestination? {
        guard let current = streamPlaybackItem,
              let identity = StreamRecoveryService.identity(for: current, source: "player") else { return nil }
        return StremioSourcesDestination(
            identity: identity,
            title: current.mediaType == .episode ? (current.showTitle ?? item.grandparentTitle ?? current.title) : current.title,
            backdropURL: current.backdropURL,
            posterURL: current.posterURL,
            mediaType: current.mediaType,
            imdbId: identity.imdbId,
            tmdbId: identity.tmdbId,
            seasonNumber: current.seasonNumber,
            episodeNumber: current.episodeNumber,
            episodeTitle: current.episodeTitle
        )
    }

    // MARK: - Source resolution

    /// One shared lookup per episode (prefetch and play-next reuse it).
    private func episodeSourceTask(season: Int, episode: Int, episodeTitle: String?) -> Task<StreamEpisodeSourceOutcome, Never> {
        let key = "\(season):\(episode)"
        if let task = nextEpisodeSourceTask, nextEpisodeSourceKey == key {
            return task
        }
        nextEpisodeSourceTask?.cancel()
        let task = Task { [weak self] () -> StreamEpisodeSourceOutcome in
            guard let self else { return .unavailable(String(localized: "Playback was closed.")) }
            return await self.resolveStreamSource(season: season, episode: episode, episodeTitle: episodeTitle)
        }
        nextEpisodeSourceTask = task
        nextEpisodeSourceKey = key
        return task
    }

    private func resolveStreamSource(season: Int, episode: Int, episodeTitle: String?) async -> StreamEpisodeSourceOutcome {
        guard let current = streamPlaybackItem, let ref = StreamSeriesRef(item: current) else {
            return .unavailable(String(localized: "This episode can't be looked up from the current source."))
        }
        let identity = ref.identity(season: season, episode: episode, source: "player-next-episode")
        let destination = StremioSourcesDestination(
            identity: identity,
            title: current.showTitle ?? item.grandparentTitle ?? current.title,
            backdropURL: current.backdropURL,
            posterURL: current.posterURL,
            mediaType: .episode,
            imdbId: identity.imdbId,
            tmdbId: identity.tmdbId,
            seasonNumber: season,
            episodeNumber: episode,
            episodeTitle: episodeTitle
        )

        guard let results = await StreamRecoveryService.fetchStreams(identity: identity) else {
            AppLogger.shared.warn("[StreamNext] Source lookup timed out", data: ["requestId": identity.requestId])
            return .needsPicker(destination)
        }
        guard let match = StremioSourceRanking.bestMatch(
            for: currentStremioStream,
            in: results,
            tiers: .nextEpisode
        ) else {
            return .needsPicker(destination)
        }

        // Reuse the picker's selection logic (headers, subtitles, resume position).
        let sources = StremioSourcesViewModel(destination: destination)
        sources.groupedResults = results
        guard let selected = await sources.select(stream: match.stream, saveToCache: false, includeAlertOnFailure: false),
              case .stream(let playbackItem) = selected else {
            return .needsPicker(destination)
        }
        AppLogger.shared.info("[StreamNext] Picked next-episode source", data: [
            "requestId": identity.requestId,
            "match": match.tier.rawValue,
            "addonName": match.stream.addonName ?? "",
        ])
        return .playable(playbackItem)
    }
}
