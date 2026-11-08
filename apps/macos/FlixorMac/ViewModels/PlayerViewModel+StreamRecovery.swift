//
//  PlayerViewModel+StreamRecovery.swift
//  FlixorMac
//
//  Dead-link recovery for addon streams: when the source fails (at load or mid
//  playback) the streams for the same title are re-fetched once, the closest
//  match (same addon + binge group, same quality, ...) is played from the saved
//  position, and the dead URL is dropped from the stream cache. At most
//  `maxStreamRecoveryAttempts` replacements per playback; never loops.
//

import Foundation

extension PlayerViewModel {
    /// Starts a recovery attempt for a failed addon stream. Returns false when no
    /// attempt is possible (attempts used up, or the title can't be looked up),
    /// in which case the caller shows the error.
    func attemptStreamRecovery(early: Bool) -> Bool {
        guard sourceKind == .stream, let failed = streamPlaybackItem, mpvController?.isShutDown == false else { return false }
        // A second failure event for the same file while we are already recovering.
        if isPerformingStreamRecovery { return true }
        guard streamRecoveryAttempts < maxStreamRecoveryAttempts,
              let identity = StreamRecoveryService.identity(for: failed, source: "player-recovery") else { return false }

        streamRecoveryAttempts += 1
        failedStreamURLs.insert(failed.uri)
        let failedStream = currentStremioStream
        // Resume where playback stopped, or where this load was meant to start.
        let resumeSeconds = currentTime > 1 ? currentTime : TimeInterval(failed.resumePositionMs ?? 0) / 1000.0

        print("🛟 [Player] Stream failed (early: \(early)); recovery attempt \(streamRecoveryAttempts)/\(maxStreamRecoveryAttempts) from \(Int(resumeSeconds))s")
        AppLogger.shared.warn("[StreamRecovery] Source failed, looking for a replacement", data: [
            "contentKey": failed.contentKey,
            "addonName": failed.addonName ?? "",
            "attempt": streamRecoveryAttempts,
            "early": early,
        ])

        isPerformingStreamRecovery = true
        streamRecoveryFailed = false
        streamEngineStatus = .recoveringSource(attempt: streamRecoveryAttempts, maxAttempts: maxStreamRecoveryAttempts)
        error = nil
        isLoading = true
        isPlaying = false
        fileStartTime = nil
        if !early {
            Task { await self.reportProgress() }
        }

        Task { [weak self] in
            await self?.performStreamRecovery(
                failed: failed,
                failedStream: failedStream,
                identity: identity,
                resumeSeconds: resumeSeconds,
                early: early
            )
        }
        return true
    }

    private func performStreamRecovery(
        failed: StreamPlaybackItem,
        failedStream: StremioPlayableStream?,
        identity: StremioContentIdentity,
        resumeSeconds: TimeInterval,
        early: Bool
    ) async {
        await StreamRecoveryService.removeCachedSource(contentKey: failed.contentKey, failedURL: failed.uri)

        // Re-fetch the title's streams once per playback; later attempts reuse them.
        if streamRecoveryResults == nil {
            streamRecoveryResults = await StreamRecoveryService.fetchStreams(identity: identity)
        }

        // The user may have closed the player or switched source meanwhile.
        guard streamPlaybackItem?.id == failed.id, mpvController?.isShutDown == false else {
            isPerformingStreamRecovery = false
            streamEngineStatus = nil
            return
        }

        let pool = recoveryCandidatePool()
        guard let match = StremioSourceRanking.bestMatch(for: failedStream, in: pool, excludingURLs: failedStreamURLs),
              let uri = match.stream.url else {
            finishStreamRecoveryFailed(early: early)
            return
        }

        print("🛟 [Player] Replacement source: \(match.stream.addonName ?? "addon") (\(match.tier.rawValue))")
        AppLogger.shared.info("[StreamRecovery] Playing replacement source", data: [
            "contentKey": failed.contentKey,
            "addonName": match.stream.addonName ?? "",
            "match": match.tier.rawValue,
        ])

        let freshStreams = pool.flatMap(\.streams).filter { $0.playable && !failedStreamURLs.contains($0.url ?? "") }
        let resumeMs = Int(resumeSeconds * 1000)
        let replacement = StreamPlaybackItem(
            id: "stremio-\(failed.contentKey)-\(match.stream.id)",
            provider: .stremio,
            uri: uri,
            headers: mergedHeaders(for: match.stream),
            title: failed.title,
            showTitle: failed.showTitle,
            mediaType: failed.mediaType,
            contentKey: failed.contentKey,
            imdbId: failed.imdbId,
            tmdbId: failed.tmdbId,
            seasonNumber: failed.seasonNumber,
            episodeNumber: failed.episodeNumber,
            episodeTitle: failed.episodeTitle,
            backdropURL: failed.backdropURL,
            posterURL: failed.posterURL,
            streamLabel: match.stream.title ?? match.stream.name ?? failed.streamLabel,
            addonId: match.stream.addonId,
            addonName: match.stream.addonName,
            availableStreams: freshStreams.isEmpty ? failed.availableStreams : freshStreams,
            externalSubtitles: failed.externalSubtitles,
            resumePositionMs: resumeMs
        )

        streamPlaybackItem = replacement
        // isPerformingStreamRecovery stays set so loadExternalStream keeps the attempt count.
        await loadExternalStream(replacement, resumeIsExact: true)
        isPerformingStreamRecovery = false
        // Status clears once the replacement file loads (applyInitialSeekIfNeeded).
    }

    /// Fresh results when the re-fetch worked, else the sources we already had.
    private func recoveryCandidatePool() -> [StremioAddonStreamResult] {
        if let results = streamRecoveryResults, results.contains(where: { $0.streams.contains(where: \.playable) }) {
            return results
        }
        // Group the known sources by addon, keeping their order (ranking uses addon order).
        var order: [String] = []
        var grouped: [String: [StremioPlayableStream]] = [:]
        for stream in availableStremioSources {
            let key = stream.addonInstallationId ?? stream.addonId ?? "unknown"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(stream)
        }
        return order.map { key in
            let streams = grouped[key] ?? []
            return StremioAddonStreamResult(
                addonId: streams.first?.addonId ?? key,
                addonName: streams.first?.addonName ?? key,
                installationId: key,
                streams: streams,
                error: nil
            )
        }
    }

    /// Recovery gave up: show the error with a "Choose another source" path.
    func finishStreamRecoveryFailed(early: Bool) {
        isPerformingStreamRecovery = false
        streamEngineStatus = nil
        streamRecoveryFailed = true
        sourcesPickerDestination = currentTitleSourcesDestination()
        AppLogger.shared.warn("[StreamRecovery] No working replacement found", data: [
            "contentKey": streamPlaybackItem?.contentKey ?? "",
            "attempts": streamRecoveryAttempts,
        ])
        failPlayback(early
            ? "This source couldn't be loaded and no working replacement was found. Choose another source."
            : "The stream stopped and no working replacement was found. Choose another source.")
    }

    /// Clears the "recovering" status once a replacement has loaded.
    func clearStreamRecoveryStatusIfLoaded() {
        if case .recoveringSource = streamEngineStatus, !isPerformingStreamRecovery {
            streamEngineStatus = nil
        }
    }

    /// Called by non-recovery loads (first load, Retry, manual source switch):
    /// a user action starts a fresh recovery budget.
    func resetStreamRecoveryForUserLoad() {
        guard !isPerformingStreamRecovery else { return }
        streamRecoveryAttempts = 0
        failedStreamURLs = []
        streamRecoveryResults = nil
        streamRecoveryFailed = false
        if case .recoveringSource = streamEngineStatus { streamEngineStatus = nil }
    }

    /// Playable sources other than the ones that failed, best first. For a
    /// "Choose another source" list in the error overlay.
    var alternativeStreamSources: [StremioPlayableStream] {
        let order = availableStremioSources.compactMap(\.addonInstallationId)
        return availableStremioSources
            .filter { $0.playable && $0.url != nil && !failedStreamURLs.contains($0.url ?? "") && $0.id != currentStremioSourceId }
            .sorted {
                StremioSourceRanking.score(for: $0, addonOrder: order) > StremioSourceRanking.score(for: $1, addonOrder: order)
            }
    }
}
