//
//  TraktContinueWatchingService.swift
//  FlixorMac
//
//  Builds Continue Watching items from Trakt: paused movies and episodes, plus
//  the next episode of recently watched shows. One card per title, newest
//  activity wins. Results are cached briefly because Home reloads often.
//

import Foundation
import FlixorKit

struct TraktContinueWatchingEntry {
    let item: MediaItem
    let lastActivity: Date
    let isMovie: Bool
    let tmdbId: Int
    let imdbId: String?
    let positionMs: Int?
    let durationMs: Int?

    var rowKey: String { TraktContinueWatchingService.rowKey(for: item) }
}

actor TraktContinueWatchingService {
    static let shared = TraktContinueWatchingService()

    /// Home's poll reuses the cache; explicit refreshes call `invalidate()` first.
    private static let cacheLifetime: TimeInterval = 5 * 60
    /// Shows watched longer ago than this don't get a next-episode card.
    private static let nextUpWindow: TimeInterval = 90 * 24 * 60 * 60
    private static let maxNextUpShows = 20
    private static let maxEntries = 30
    private static let concurrency = 6

    private var cache: (entries: [TraktContinueWatchingEntry], fetchedAt: Date, profile: String)?
    private var inFlight: (task: Task<[TraktContinueWatchingEntry], Error>, profile: String)?
    private var generation = 0

    /// Identifies a card in the row: episodes of a show share one `MediaItem.id`.
    nonisolated static func rowKey(for item: MediaItem) -> String {
        guard item.type == "episode" else { return item.id }
        return "\(item.id):\(item.parentIndex ?? -1):\(item.index ?? -1)"
    }

    private func currentProfile() -> String { UserDefaults.standard.profileKey("traktContinueWatching") }

    func entries() async throws -> [TraktContinueWatchingEntry] {
        let profile = currentProfile()
        if let cache, cache.profile == profile, Date().timeIntervalSince(cache.fetchedAt) < Self.cacheLifetime {
            return cache.entries
        }
        if let inFlight, inFlight.profile == profile {
            return try await inFlight.task.value
        }

        let task = Task { try await Self.fetchEntries() }
        inFlight = (task, profile)
        let started = generation
        defer { if started == generation { inFlight = nil } }

        let entries = try await task.value
        if started == generation {
            cache = (entries, Date(), profile)
        }
        return entries
    }

    func invalidate() {
        generation += 1
        cache = nil
        inFlight = nil
    }

    /// Hands a Trakt resume point to local playback, unless local progress is newer.
    func seedResumePoint(for item: MediaItem) async {
        guard let entries = cache?.entries,
              let entry = entries.first(where: { $0.rowKey == Self.rowKey(for: item) }),
              let positionMs = entry.positionMs, positionMs > 0,
              let durationMs = entry.durationMs else { return }

        var baseIds = ["tmdb:\(entry.tmdbId)"]
        if let imdb = entry.imdbId { baseIds.insert(imdb, at: 0) }
        let keys: [String] = baseIds.map { base in
            if entry.isMovie { return "movie:\(base)" }
            return "series:\(base):\(item.parentIndex ?? 0):\(item.index ?? 0)"
        }

        let store = StremioResumeStore.shared
        for key in keys {
            if let existing = await store.get(contentKey: key), existing.updatedAt >= entry.lastActivity { continue }
            await store.save(ResumeState(
                contentKey: key,
                positionMs: positionMs,
                durationMs: durationMs,
                updatedAt: entry.lastActivity
            ))
        }
    }

    // MARK: - Fetching

    private struct Candidate {
        let isMovie: Bool
        let tmdbId: Int
        let imdbId: String?
        let title: String
        let year: Int?
        let episodeTitle: String?
        let season: Int?
        let episode: Int?
        let runtimeMinutes: Int?
        let progress: Double?
        let activity: Date
    }

    private static func fetchEntries() async throws -> [TraktContinueWatchingEntry] {
        let trakt = await FlixorCore.shared.trakt
        let paused = try await trakt.getPausedPlayback()
        var candidates = paused.compactMap(candidate(from:))

        // Next episodes are a bonus: losing them shouldn't lose the paused items.
        if let shows = try? await trakt.getWatchedShowSummaries() {
            candidates += await nextUpCandidates(shows: shows, trakt: trakt)
        }

        var newest: [String: Candidate] = [:]
        for candidate in candidates {
            let key = "\(candidate.isMovie ? "movie" : "tv"):\(candidate.tmdbId)"
            if let current = newest[key], current.activity >= candidate.activity { continue }
            newest[key] = candidate
        }

        let chosen = newest.values.sorted { $0.activity > $1.activity }.prefix(maxEntries)
        return await withArtwork(Array(chosen))
    }

    private static func candidate(from playback: TraktPlaybackItem) -> Candidate? {
        // Trakt counts 80%+ as watched; ignore accidental starts and finished items.
        guard playback.progress >= 1, playback.progress < 95,
              let activity = parseDate(playback.pausedAt) else { return nil }

        if let movie = playback.movie, playback.type == "movie" {
            guard let tmdbId = movie.ids.tmdb else { return nil }
            return Candidate(
                isMovie: true, tmdbId: tmdbId, imdbId: movie.ids.imdb, title: movie.title, year: movie.year,
                episodeTitle: nil, season: nil, episode: nil, runtimeMinutes: movie.runtime,
                progress: playback.progress, activity: activity
            )
        }
        if let show = playback.show, let episode = playback.episode, playback.type == "episode" {
            guard let tmdbId = show.ids.tmdb else { return nil }
            return Candidate(
                isMovie: false, tmdbId: tmdbId, imdbId: show.ids.imdb, title: show.title, year: show.year,
                episodeTitle: episode.title, season: episode.season, episode: episode.number,
                runtimeMinutes: episode.runtime ?? show.runtime, progress: playback.progress, activity: activity
            )
        }
        return nil
    }

    private static func nextUpCandidates(shows: [TraktWatchedShowSummary], trakt: TraktService) async -> [Candidate] {
        let cutoff = Date().addingTimeInterval(-nextUpWindow)
        let recent: [(show: FlixorKit.TraktShow, date: Date)] = shows
            .compactMap { summary -> (FlixorKit.TraktShow, Date)? in
                guard summary.show.ids.tmdb != nil, let date = parseDate(summary.lastWatchedAt), date > cutoff else { return nil }
                return (summary.show, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxNextUpShows)
            .map { (show: $0.0, date: $0.1) }

        var results: [Candidate] = []
        for batch in recent.chunked(into: concurrency) {
            await withTaskGroup(of: Candidate?.self) { group in
                for entry in batch {
                    group.addTask {
                        let show = entry.show
                        guard let showId = show.ids.trakt.map(String.init) ?? show.ids.slug,
                              let tmdbId = show.ids.tmdb,
                              let next = try? await trakt.getShowNextUp(showId: showId),
                              let episode = next.nextEpisode else { return nil }
                        return Candidate(
                            isMovie: false, tmdbId: tmdbId, imdbId: show.ids.imdb, title: show.title, year: show.year,
                            episodeTitle: episode.title, season: episode.season, episode: episode.number,
                            runtimeMinutes: episode.runtime ?? show.runtime, progress: nil, activity: entry.date
                        )
                    }
                }
                for await candidate in group {
                    if let candidate { results.append(candidate) }
                }
            }
        }
        return results
    }

    private static func withArtwork(_ candidates: [Candidate]) async -> [TraktContinueWatchingEntry] {
        let tmdb = await FlixorCore.shared.tmdb
        var entries: [TraktContinueWatchingEntry] = []
        for batch in candidates.chunked(into: concurrency) {
            await withTaskGroup(of: TraktContinueWatchingEntry.self) { group in
                for candidate in batch {
                    group.addTask {
                        var poster: String?
                        var backdrop: String?
                        if candidate.isMovie {
                            let details = try? await tmdb.getMovieDetails(id: candidate.tmdbId)
                            poster = details?.posterPath
                            backdrop = details?.backdropPath
                        } else {
                            let details = try? await tmdb.getTVDetails(id: candidate.tmdbId)
                            poster = details?.posterPath
                            backdrop = details?.backdropPath
                        }
                        return makeEntry(candidate, posterPath: poster, backdropPath: backdrop)
                    }
                }
                for await entry in group { entries.append(entry) }
            }
        }
        return entries.sorted { $0.lastActivity > $1.lastActivity }
    }

    private static func makeEntry(_ c: Candidate, posterPath: String?, backdropPath: String?) -> TraktContinueWatchingEntry {
        let poster = TMDBImageURL.url(posterPath, size: .w500)?.absoluteString
        let art = TMDBImageURL.url(backdropPath ?? posterPath, size: .w780)?.absoluteString
        let durationMs = c.runtimeMinutes.flatMap { $0 > 0 ? $0 * 60_000 : nil }
        let positionMs: Int? = {
            guard let progress = c.progress, let durationMs else { return nil }
            return Int(Double(durationMs) * progress / 100)
        }()
        let episodeLabel = c.episodeTitle?.isEmpty == false ? c.episodeTitle! : String(localized: "Episode \(String(c.episode ?? 0))")

        let item = MediaItem(
            id: c.isMovie ? "tmdb:movie:\(c.tmdbId)" : "tmdb:tv:\(c.tmdbId)",
            title: c.isMovie ? c.title : episodeLabel,
            type: c.isMovie ? "movie" : "episode",
            thumb: poster,
            art: art,
            year: c.year,
            rating: nil,
            duration: durationMs,
            viewOffset: positionMs,
            summary: nil,
            grandparentTitle: c.isMovie ? nil : c.title,
            grandparentThumb: c.isMovie ? nil : poster,
            grandparentArt: c.isMovie ? nil : art,
            grandparentRatingKey: nil,
            parentIndex: c.season,
            index: c.episode,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
        return TraktContinueWatchingEntry(
            item: item, lastActivity: c.activity, isMovie: c.isMovie, tmdbId: c.tmdbId,
            imdbId: c.imdbId, positionMs: positionMs, durationMs: durationMs
        )
    }

    private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalDateFormatter.date(from: value) ?? plainDateFormatter.date(from: value)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Merging

enum ContinueWatchingMerger {
    /// Folds Trakt entries into the Plex or local list. A title already in the
    /// list keeps one card: for local items the newer progress wins (Plex items
    /// have no activity date and always stay).
    static func merge(
        primary: [MediaItem],
        activity: [String: Date],
        trakt: [TraktContinueWatchingEntry],
        dismissals: [String: Double]
    ) -> [MediaItem] {
        var rows: [(item: MediaItem, date: Date?)] = primary.map { ($0, activity[$0.id]) }

        for entry in trakt {
            if let dismissed = dismissals[entry.rowKey], entry.lastActivity.timeIntervalSince1970 <= dismissed { continue }
            if let index = rows.firstIndex(where: { isSameTitle($0.item, entry.item) }) {
                if let date = rows[index].date, entry.lastActivity > date {
                    rows[index] = (entry.item, entry.lastActivity)
                }
                continue
            }
            rows.append((entry.item, entry.lastActivity))
        }

        // Items without a date (Plex) keep their server order at the front.
        let undated = rows.filter { $0.date == nil }.map(\.item)
        let dated = rows.filter { $0.date != nil }.sorted { $0.date! > $1.date! }.map(\.item)
        return undated + dated
    }

    private static func isSameTitle(_ a: MediaItem, _ b: MediaItem) -> Bool {
        if a.id == b.id { return true }
        guard (a.type == "movie") == (b.type == "movie") else { return false }
        return normalizedTitle(a) == normalizedTitle(b)
    }

    private static func normalizedTitle(_ item: MediaItem) -> String {
        let title = item.type == "movie" ? item.title : (item.grandparentTitle ?? item.title)
        return title.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
