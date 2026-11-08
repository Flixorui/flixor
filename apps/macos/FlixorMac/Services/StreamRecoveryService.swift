//
//  StreamRecoveryService.swift
//  FlixorMac
//
//  Helpers for addon-stream playback beyond the first source: re-fetching sources
//  for the same title (dead-link recovery) or another episode (play next), with a
//  hard timeout, and pruning dead URLs from the stream cache.
//

import Foundation

/// Status the player shows while the stream engine works in the background.
enum StreamEngineStatus: Equatable {
    /// The current source failed; looking for a replacement (attempt n of max).
    case recoveringSource(attempt: Int, maxAttempts: Int)
    /// Resolving a source for the next episode ("S1E2").
    case findingNextEpisodeSource(episodeLabel: String)

    /// Ready-to-show text for the loading overlay.
    var message: String {
        switch self {
        case .recoveringSource(let attempt, let maxAttempts):
            return maxAttempts > 1
                ? "Source stopped working. Finding a replacement (\(attempt) of \(maxAttempts))…"
                : "Source stopped working. Finding a replacement…"
        case .findingNextEpisodeSource(let label):
            return "Finding a source for \(label)…"
        }
    }
}

enum StreamRecoveryService {
    /// Upper bound for one source lookup (all addons in parallel).
    static let lookupTimeout: TimeInterval = 30

    /// Stremio identity for the title a StreamPlaybackItem plays, from its content key.
    static func identity(for item: StreamPlaybackItem, source: String) -> StremioContentIdentity? {
        if let series = StreamSeriesRef(item: item) {
            return series.identity(season: series.season, episode: series.episode, source: source)
        }
        let prefix = "\(StremioRequestType.movie.rawValue):"
        guard item.mediaType == .movie, item.contentKey.hasPrefix(prefix) else { return nil }
        let baseId = String(item.contentKey.dropFirst(prefix.count))
        guard !baseId.isEmpty else { return nil }
        return StremioContentIdentity(
            requestType: StremioRequestType.movie.rawValue,
            baseId: baseId,
            requestId: baseId,
            imdbId: item.imdbId,
            tmdbId: item.tmdbId,
            seasonNumber: nil,
            episodeNumber: nil,
            source: source
        )
    }

    /// Streams from all installed stream addons, or nil on timeout.
    static func fetchStreams(identity: StremioContentIdentity) async -> [StremioAddonStreamResult]? {
        await withTimeout(seconds: lookupTimeout) {
            await StremioService.shared.getStreams(identity: identity)
        }
    }

    /// Drops the cached playback source for `contentKey` when it points at `failedURL`.
    static func removeCachedSource(contentKey: String, failedURL: String) async {
        let cache = StremioStreamCache.shared
        guard let cached = await cache.get(contentKey: contentKey), cached.playbackItem.uri == failedURL else { return }
        await cache.remove(contentKey: contentKey)
        AppLogger.shared.info("[StreamRecovery] Removed dead source from stream cache", data: ["contentKey": contentKey])
    }

    /// Runs `operation`, returning nil if it takes longer than `seconds` (the operation is cancelled).
    static func withTimeout<T: Sendable>(seconds: TimeInterval, _ operation: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
