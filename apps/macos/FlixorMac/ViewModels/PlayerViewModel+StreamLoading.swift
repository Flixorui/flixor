//
//  PlayerViewModel+StreamLoading.swift
//  FlixorMac
//
//  Stremio/addon stream playback and source switching
//

import Foundation

extension PlayerViewModel {
    /// - Parameter resumeIsExact: The resume position continues a running playback
    ///   (source recovery or switch) rather than a saved one.
    func loadExternalStream(_ streamItem: StreamPlaybackItem, resumeIsExact: Bool = false) async {
        isLoading = true
        error = nil
        initialSeekApplied = false
        forcedResumeSeconds = TimeInterval(streamItem.resumePositionMs ?? 0) / 1000.0
        forcedResumeIsExact = resumeIsExact
        currentURLIsHLS = false
        isTranscoding = false
        resetStreamRecoveryForUserLoad()
        // Skip segments and next-episode data belong to the title, not the source:
        // keep them across source switches and recovery, reload for a new title.
        let isNewTitle = streamEngineContentKey != streamItem.contentKey
        if isNewTitle {
            nextEpisodeCountdownDismissed = false
            plexMarkersSnapshot = []
            resetCommunitySkipSegments()
            resetStreamNextEpisode()
            sourcesPickerDestination = nil
            markers = []
            currentMarker = nil
            nextEpisode = nil
            seasonEpisodes = []
        }
        nextEpisodeCountdown = nil
        availableExternalSubtitleOptions = streamItem.externalSubtitles
        availableStremioSources = streamItem.availableStreams
        currentStremioSourceId = streamItem.availableStreams.first(where: { $0.url == streamItem.uri && $0.addonId == streamItem.addonId })?.id
        selectedExternalSubtitleId = nil
        cleanupExternalSubtitleFiles()

        do {
            guard let mpvController = self.mpvController else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller not initialized"])
            }

            var waitCount = 0
            let maxWaitCount = 50
            while !mpvController.isInitialized && waitCount < maxWaitCount {
                try await Task.sleep(nanoseconds: 100_000_000)
                waitCount += 1
            }

            guard mpvController.isInitialized else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV failed to initialize"])
            }

            streamURL = URL(string: streamItem.uri)
            mpvController.loadFile(streamItem.uri, headers: Dictionary(uniqueKeysWithValues: streamItem.headers.map { ($0.name, $0.value) }))
            startProgressTracking()

            if isNewTitle {
                // Set only once the lookups start, so a failed first load retries them.
                streamEngineContentKey = streamItem.contentKey
                loadCommunitySkipSegments(for: streamItem)
                loadStreamNextEpisode(for: streamItem)
            }

            if UserDefaults.standard.useCachedStreams {
                let now = Date()
                await streamCache.save(
                    CachedPlaybackSource(
                        kind: "stream",
                        provider: StreamProvider.stremio.rawValue,
                        contentKey: streamItem.contentKey,
                        playbackItem: streamItem,
                        savedAt: now,
                        expiresAt: now.addingTimeInterval(TimeInterval(UserDefaults.standard.streamCacheTTL))
                    )
                )
            }

            AppLogger.shared.info("[Stremio] Starting macOS stream playback", data: [
                "contentKey": streamItem.contentKey,
                "uri": streamItem.uri,
                "addonId": streamItem.addonId ?? "",
                "addonName": streamItem.addonName ?? "",
            ])
        } catch {
            AppLogger.shared.error("[Stremio] Failed to load stream playback", data: [
                "contentKey": streamItem.contentKey,
                "uri": streamItem.uri,
                "error": error.localizedDescription,
            ])
            self.error = "Failed to load Stremio stream: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    /// The addon source currently playing (by id, else by URL).
    var currentStremioStream: StremioPlayableStream? {
        if let id = currentStremioSourceId, let stream = availableStremioSources.first(where: { $0.id == id }) {
            return stream
        }
        guard let uri = streamPlaybackItem?.uri else { return nil }
        return availableStremioSources.first { $0.url == uri }
    }

    var isStreamPlayback: Bool {
        sourceKind == .stream
    }

    var canSwitchStreamSources: Bool {
        availableStremioSources.count > 1
    }

    func switchStreamSource(_ stream: StremioPlayableStream) {
        guard sourceKind == .stream else { return }
        Task {
            await replaceCurrentStremioSource(with: stream)
        }
    }

    private func replaceCurrentStremioSource(with stream: StremioPlayableStream) async {
        guard let current = streamPlaybackItem,
              stream.id != currentStremioSourceId,
              let uri = stream.url else {
            return
        }

        await reportProgress()

        let resumePositionMs = Int(currentTime * 1000)
        let replacement = StreamPlaybackItem(
            id: "stremio-\(current.contentKey)-\(stream.id)",
            provider: .stremio,
            uri: uri,
            headers: mergedHeaders(for: stream),
            title: current.title,
            showTitle: current.showTitle,
            mediaType: current.mediaType,
            contentKey: current.contentKey,
            imdbId: current.imdbId,
            tmdbId: current.tmdbId,
            seasonNumber: current.seasonNumber,
            episodeNumber: current.episodeNumber,
            episodeTitle: current.episodeTitle,
            backdropURL: current.backdropURL,
            posterURL: current.posterURL,
            streamLabel: stream.title ?? stream.name ?? current.streamLabel,
            addonId: stream.addonId,
            addonName: stream.addonName,
            availableStreams: current.availableStreams,
            externalSubtitles: current.externalSubtitles,
            resumePositionMs: resumePositionMs
        )

        streamPlaybackItem = replacement
        forcedResumeSeconds = TimeInterval(resumePositionMs) / 1000.0
        initialSeekApplied = false
        currentStremioSourceId = stream.id
        selectedExternalSubtitleId = nil
        cleanupExternalSubtitleFiles()
        await loadExternalStream(replacement, resumeIsExact: true)
    }

    func mergedHeaders(for stream: StremioPlayableStream) -> [HTTPHeaderField] {
        var headers = stream.headers ?? [:]
        let proxy = stream.behaviorHints?.proxyHeaders?.request ?? [:]
        for (key, value) in proxy {
            headers[key] = value
        }
        return headers.keys.sorted().map { HTTPHeaderField(name: $0, value: headers[$0] ?? "") }
    }
}
