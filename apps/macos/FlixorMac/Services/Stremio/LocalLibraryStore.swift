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

    /// Removes every history entry for a title (and season/episode, when given).
    /// `season == nil` matches all episodes of a show; `episode == nil` all episodes
    /// of the season. Returns the removed content keys.
    @discardableResult
    func removeHistory(
        mediaType: StreamMediaType,
        tmdbId: Int?,
        imdbId: String?,
        season: Int? = nil,
        episode: Int? = nil
    ) -> [String] {
        var index = defaults.getLocalWatchHistory()
        let normalizedImdb = imdbId?.lowercased()
        let removed = index.values.filter { entry in
            guard entry.mediaType == mediaType else { return false }
            let sameTitle = (tmdbId != nil && entry.tmdbId == tmdbId)
                || (normalizedImdb.map { !$0.isEmpty && entry.imdbId?.lowercased() == $0 } ?? false)
            guard sameTitle else { return false }
            if mediaType == .movie { return true }
            if let season, entry.seasonNumber != season { return false }
            if let episode, entry.episodeNumber != episode { return false }
            return true
        }.map(\.contentKey)

        guard !removed.isEmpty else { return [] }
        for key in removed { index.removeValue(forKey: key) }
        defaults.setLocalWatchHistory(index)
        notifyHistoryChanged()
        return removed
    }

    // MARK: - Watched (marked on this Mac)

    /// Everything marked watched locally, most recent first.
    func watchedEntries() -> [LocalWatchedEntry] {
        defaults.getLocalWatched().values.sorted { $0.watchedAt > $1.watchedAt }
    }

    /// Adds (or refreshes) watched entries in one write.
    func markWatched(_ entries: [LocalWatchedEntry]) {
        guard !entries.isEmpty else { return }
        var index = defaults.getLocalWatched()
        for entry in entries { index[entry.key] = entry }
        defaults.setLocalWatched(index)
    }

    /// Removes watched entries for a title (season/episode scoping as in
    /// `removeHistory`). Returns how many were removed.
    @discardableResult
    func removeWatched(
        mediaType: StreamMediaType,
        tmdbId: Int?,
        imdbId: String?,
        season: Int? = nil,
        episode: Int? = nil
    ) -> Int {
        var index = defaults.getLocalWatched()
        let keys = index.values
            .filter { $0.matches(mediaType: mediaType, tmdbId: tmdbId, imdbId: imdbId, season: season, episode: episode) }
            .map(\.key)
        guard !keys.isEmpty else { return 0 }
        for key in keys { index.removeValue(forKey: key) }
        defaults.setLocalWatched(index)
        return keys.count
    }

    /// Whether a movie or a specific episode is marked watched locally.
    func isWatched(mediaType: StreamMediaType, tmdbId: Int?, imdbId: String?, season: Int? = nil, episode: Int? = nil) -> Bool {
        if mediaType == .episode, season == nil || episode == nil { return false }
        return defaults.getLocalWatched().values.contains {
            $0.matches(mediaType: mediaType, tmdbId: tmdbId, imdbId: imdbId, season: season, episode: episode)
        }
    }

    /// Locally watched episodes of a show (optionally one season).
    func watchedEpisodes(tmdbId: Int?, imdbId: String?, season: Int? = nil) -> [LocalWatchedEntry] {
        defaults.getLocalWatched().values.filter {
            $0.matches(mediaType: .episode, tmdbId: tmdbId, imdbId: imdbId, season: season, episode: nil)
        }
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
