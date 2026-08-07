//
//  LocalLibraryStore.swift
//  FlixorMac
//
//  Watch history and watchlist stored on this Mac.
//
//  In standalone Stremio mode there is no Plex server to own "on deck" and no
//  guarantee the user has linked Trakt, so Continue Watching and My List are backed
//  locally. When Trakt *is* linked, callers merge these entries with the Trakt ones
//  rather than replacing them.
//

import Foundation

extension Notification.Name {
    /// Posted after the local watch history changes, so Home can refresh its
    /// Continue Watching row when the player exits.
    static let localWatchHistoryDidChange = Notification.Name("localWatchHistoryDidChange")
}

actor LocalLibraryStore {
    static let shared = LocalLibraryStore()

    /// Treated as finished; drops out of Continue Watching.
    private let completionThreshold = 0.9
    /// Ignore the first few seconds so a title the user immediately backed out of
    /// doesn't clutter the row.
    private let minimumPositionMs = 15_000
    /// Progress is reported every few seconds; only rewrite the index once the
    /// position has actually moved this far, so playback doesn't churn the store
    /// (and Home) constantly.
    private let writeIntervalMs = 15_000

    private let defaults = UserDefaults.standard

    // MARK: - Watch History

    /// Most recently watched first.
    func watchHistory() -> [WatchHistoryEntry] {
        defaults.getLocalWatchHistory()
            .values
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func historyEntry(contentKey: String) -> WatchHistoryEntry? {
        defaults.getLocalWatchHistory()[contentKey]
    }

    /// Records progress for a stream. Removes the entry once it's effectively
    /// finished, and ignores trivially short positions.
    /// - Parameter force: bypasses the write interval; use when playback stops so the
    ///   final position is always persisted.
    func recordProgress(
        for item: StreamPlaybackItem,
        positionMs: Int,
        durationMs: Int,
        force: Bool = false
    ) {
        guard durationMs > 0 else { return }

        let fraction = Double(positionMs) / Double(durationMs)
        if fraction >= completionThreshold {
            removeHistory(contentKey: item.contentKey)
            return
        }
        guard positionMs >= minimumPositionMs else { return }

        var index = defaults.getLocalWatchHistory()
        if !force,
           let existing = index[item.contentKey],
           abs(positionMs - existing.positionMs) < writeIntervalMs {
            return
        }

        let entry = WatchHistoryEntry(
            contentKey: item.contentKey,
            mediaType: item.mediaType,
            // `item.title` is the episode title for episodes; prefer the series title.
            title: item.showTitle ?? item.title,
            episodeTitle: item.mediaType == .episode ? (item.episodeTitle ?? item.title) : nil,
            seasonNumber: item.seasonNumber,
            episodeNumber: item.episodeNumber,
            imdbId: item.imdbId,
            tmdbId: item.tmdbId,
            posterURL: item.posterURL,
            backdropURL: item.backdropURL,
            positionMs: positionMs,
            durationMs: durationMs,
            updatedAt: Date()
        )

        index[entry.contentKey] = entry
        defaults.setLocalWatchHistory(index)
        notifyHistoryChanged()
    }

    func removeHistory(contentKey: String) {
        var index = defaults.getLocalWatchHistory()
        guard index.removeValue(forKey: contentKey) != nil else { return }
        defaults.setLocalWatchHistory(index)
        notifyHistoryChanged()
    }

    func clearHistory() {
        defaults.setLocalWatchHistory([:])
        notifyHistoryChanged()
    }

    // MARK: - Watchlist

    /// Most recently added first.
    func watchlist() -> [LocalWatchlistEntry] {
        defaults.getLocalWatchlist()
            .values
            .sorted { $0.addedAt > $1.addedAt }
    }

    func isInWatchlist(id: String) -> Bool {
        defaults.getLocalWatchlist()[Self.normalize(id)] != nil
    }

    func addToWatchlist(_ entry: LocalWatchlistEntry) {
        var index = defaults.getLocalWatchlist()
        index[Self.normalize(entry.id)] = entry
        defaults.setLocalWatchlist(index)
    }

    func removeFromWatchlist(id: String) {
        var index = defaults.getLocalWatchlist()
        guard index.removeValue(forKey: Self.normalize(id)) != nil else { return }
        defaults.setLocalWatchlist(index)
    }

    // MARK: - Helpers

    /// Watchlist ids arrive from several places with inconsistent casing; keying on a
    /// normalized form keeps add/remove/contains in agreement.
    private static func normalize(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func notifyHistoryChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .localWatchHistoryDidChange, object: nil)
        }
    }
}
