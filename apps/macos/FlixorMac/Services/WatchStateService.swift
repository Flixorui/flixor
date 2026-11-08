//
//  WatchStateService.swift
//  FlixorMac
//
//  One place for "mark watched / unwatched", "remove from Continue Watching",
//  "start over" and Trakt ratings. Each action is applied to every backend that
//  owns state for the item:
//
//    Plex   - items with a Plex ratingKey, or a show key plus season/episode
//             numbers (the season/episode key is looked up). If the server can't be
//             reached (none connected, Stremio-only mode) a Plex failure is reported.
//    Trakt  - when Trakt is connected and "Auto-sync watched" is on (history and
//             playback progress). Ratings only need Trakt to be connected.
//    Local  - items without a Plex copy (Stremio-only mode, TMDB/Stremio items):
//             the watched index, watch history (Continue Watching) and resume points
//             kept on this Mac.
//
//  Every action returns a `WatchStateResult` for a toast and posts
//  `.watchStateDidChange` when anything changed.
//

import Foundation
import FlixorKit

// MARK: - Notification

extension Notification.Name {
    /// Posted on the main thread after a watch-state action changed something.
    /// `userInfo[WatchStateChange.userInfoKey]` holds a `WatchStateChange`; flat keys
    /// ("action", "itemId", "plexRatingKey", "tmdbId", "imdbId") are included too.
    static let watchStateDidChange = Notification.Name("watchStateDidChange")
}

/// Payload of `.watchStateDidChange`.
struct WatchStateChange {
    static let userInfoKey = "change"

    let action: WatchStateAction
    let target: WatchStateTarget
    /// New rating for `.rate`.
    let rating: Int?
    let backends: [WatchStateBackend]

    init(action: WatchStateAction, target: WatchStateTarget, rating: Int?, backends: [WatchStateBackend]) {
        self.action = action
        self.target = target
        self.rating = rating
        self.backends = backends
    }

    init?(notification: Notification) {
        guard let change = notification.userInfo?[Self.userInfoKey] as? WatchStateChange else { return nil }
        self = change
    }

    var userInfo: [String: Any] {
        var info: [String: Any] = [Self.userInfoKey: self, "action": action.rawValue, "kind": target.kind.label]
        if let id = target.sourceItemId { info["itemId"] = id }
        if let key = target.plexRatingKey { info["plexRatingKey"] = key }
        if let key = target.showPlexRatingKey { info["showPlexRatingKey"] = key }
        if let id = target.tmdbId { info["tmdbId"] = id }
        if let id = target.imdbId { info["imdbId"] = id }
        if let season = target.seasonNumber { info["season"] = season }
        if let episode = target.episodeNumber { info["episode"] = episode }
        if let rating { info["rating"] = rating }
        return info
    }
}

// MARK: - Result

enum WatchStateAction: String {
    case markWatched, markUnwatched, removeFromContinueWatching, startOver, rate, removeRating

    fileprivate var successText: String {
        switch self {
        case .markWatched: return String(localized: "Marked as watched")
        case .markUnwatched: return String(localized: "Marked as unwatched")
        case .removeFromContinueWatching: return String(localized: "Removed from Continue Watching")
        case .startOver: return String(localized: "Progress reset")
        case .rate: return String(localized: "Rating saved")
        case .removeRating: return String(localized: "Rating removed")
        }
    }

    fileprivate var failureText: String {
        switch self {
        case .markWatched: return String(localized: "Couldn't mark as watched")
        case .markUnwatched: return String(localized: "Couldn't mark as unwatched")
        case .removeFromContinueWatching: return String(localized: "Couldn't remove from Continue Watching")
        case .startOver: return String(localized: "Couldn't reset progress")
        case .rate: return String(localized: "Couldn't save rating")
        case .removeRating: return String(localized: "Couldn't remove rating")
        }
    }
}

enum WatchStateBackend: String {
    case plex, trakt, local

    var displayName: String {
        switch self {
        case .plex: return "Plex"
        case .trakt: return "Trakt"
        case .local: return String(localized: "this Mac")
        }
    }
}

struct WatchStateResult {
    struct Failure {
        let backend: WatchStateBackend?
        let message: String
    }

    let action: WatchStateAction
    let target: WatchStateTarget
    let succeeded: [WatchStateBackend]
    let failures: [Failure]
    /// Nothing needed changing (e.g. no saved progress to reset, or already in the
    /// requested state everywhere). Not an error: for `.startOver` the caller can
    /// still play from 0.
    let noChanges: Bool

    init(action: WatchStateAction, target: WatchStateTarget, succeeded: [WatchStateBackend], failures: [Failure], noChanges: Bool = false) {
        self.action = action
        self.target = target
        self.succeeded = succeeded
        self.failures = failures
        self.noChanges = noChanges
    }

    /// Everything that was attempted worked (at least one backend changed).
    var isSuccess: Bool { !succeeded.isEmpty && failures.isEmpty }
    /// Some backends worked, some failed.
    var isPartialSuccess: Bool { !succeeded.isEmpty && !failures.isEmpty }

    /// Short text for a toast.
    var message: String {
        if noChanges { return action.noChangeText }
        if isSuccess { return action.successText }
        if isPartialSuccess {
            let failed = failures.map { f in f.backend.map { "\($0.displayName): \(f.message)" } ?? f.message }
            return String(localized: "\(action.successText), but \(failed.joined(separator: "; "))")
        }
        let reason = failures.first.map { f in f.backend.map { "\($0.displayName): \(f.message)" } ?? f.message } ?? String(localized: "Nothing to update")
        return "\(action.failureText): \(reason)"
    }
}

private extension WatchStateAction {
    var noChangeText: String {
        switch self {
        case .markWatched: return String(localized: "Already watched")
        case .markUnwatched: return String(localized: "Already unwatched")
        case .removeFromContinueWatching: return String(localized: "Not in Continue Watching")
        case .startOver: return String(localized: "No saved progress")
        case .rate, .removeRating: return String(localized: "Nothing to update")
        }
    }

    /// Actions that write whole-show watch state when the target is a show.
    var isWatchStateWrite: Bool {
        switch self {
        case .markWatched, .markUnwatched, .removeFromContinueWatching, .startOver: return true
        case .rate, .removeRating: return false
        }
    }
}

// MARK: - Service

@MainActor
final class WatchStateService: ObservableObject {
    static let shared = WatchStateService()

    /// `WatchStateTarget.actionKey`s with an action running. Any second action on the
    /// same target (including the opposite action, e.g. unwatch while watch is
    /// running) is rejected until the first finishes; UI can disable buttons.
    @Published private(set) var inFlight: Set<String> = []

    private let resolver = MediaIdentityResolver.shared
    private let localStore = LocalLibraryStore.shared
    private let resumeStore = StremioResumeStore.shared

    /// Cached Trakt ratings by type ("movies", "shows", "seasons", "episodes").
    private var ratingsCache: [String: (fetchedAt: Date, items: [TraktRatingItem])] = [:]
    private var ratingsInFlight: [String: Task<[TraktRatingItem], Error>] = [:]
    private let ratingsTTL: TimeInterval = 5 * 60

    /// Trakt allows about one write (POST/PUT/DELETE) per second per user.
    private let traktWriteSpacingNs: UInt64 = 1_100_000_000

    private init() {}

    // MARK: - Capabilities

    /// Trakt is linked (needed for ratings).
    var isTraktConnected: Bool { FlixorCore.shared.isTraktAuthenticated }

    /// Watch history/progress changes are pushed to Trakt.
    var isTraktWatchSyncEnabled: Bool { isTraktConnected && UserDefaults.standard.traktAutoSyncWatched }

    /// Ratings can be read and written.
    var canRate: Bool { isTraktConnected }

    private var plexServer: PlexServerService? {
        isStremioOnlyMode ? nil : FlixorCore.shared.plexServer
    }

    // MARK: - Watched

    /// Marks a MediaItem watched.
    ///
    /// - Important: Do not pass the grouped "Recently added" series cards built by
    ///   `HomeViewModel.groupEpisodesBySeries` (a `"show"` item keyed by the series
    ///   ratingKey, summary "N new episode(s)"). They stand for new episodes, not the
    ///   whole show. Such cards are detected by their summary and refused with a
    ///   failure result; open the show and act on specific episodes instead.
    func markWatched(_ item: MediaItem) async -> WatchStateResult {
        guard let target = WatchStateTarget(item: item) else { return unsupported(.markWatched, item: item) }
        return await markWatched(target)
    }

    /// Marks a MediaItem unwatched. Same restriction as `markWatched(_ item:)` for
    /// "Recently added" new-episode cards.
    func markUnwatched(_ item: MediaItem) async -> WatchStateResult {
        guard let target = WatchStateTarget(item: item) else { return unsupported(.markUnwatched, item: item) }
        return await markUnwatched(target)
    }

    /// Marks a movie, episode, season or whole show watched on Plex, Trakt and/or
    /// locally, and clears resume points. On Trakt only aired episodes that aren't
    /// already watched are added, so repeated taps don't add duplicate plays.
    func markWatched(_ target: WatchStateTarget) async -> WatchStateResult {
        await perform(.markWatched, target) { t, outcome in
            await self.applyPlex(t, outcome) { plex, key in
                try await plex.markWatched(ratingKey: key)
            }

            if self.isTraktWatchSyncEnabled {
                await self.addTraktHistory(t, outcome)
            }

            if !self.isPlexItem(t) {
                do {
                    try await self.markLocallyWatched(t)
                    outcome.succeed(.local)
                } catch {
                    outcome.fail(.local, error)
                }
            }

            await self.clearLocalProgress(for: t)
        }
    }

    /// Reverses `markWatched` on every backend.
    func markUnwatched(_ target: WatchStateTarget) async -> WatchStateResult {
        await perform(.markUnwatched, target) { t, outcome in
            await self.applyPlex(t, outcome) { plex, key in
                try await plex.markUnwatched(ratingKey: key)
            }

            if self.isTraktWatchSyncEnabled {
                if let items = self.traktItems(for: t) {
                    do {
                        try await FlixorCore.shared.trakt.removeFromHistory(items)
                        outcome.succeed(.trakt)
                    } catch {
                        outcome.fail(.trakt, error)
                    }
                } else {
                    outcome.fail(.trakt, message: String(localized: "couldn't match on Trakt"))
                }
            }

            if !self.isPlexItem(t) {
                if await self.removeLocallyWatched(t) > 0 {
                    outcome.succeed(.local)
                } else {
                    outcome.unchanged()
                }
            }
        }
    }

    /// Whether a movie or episode is marked watched in the local store (items
    /// without a Plex copy). Plex items carry their own `viewCount`/`viewedLeafCount`.
    func isWatchedLocally(_ target: WatchStateTarget) async -> Bool {
        let t = await resolve(target, needTitleIds: true)
        switch t.kind {
        case .movie:
            return await localStore.isWatched(mediaType: .movie, tmdbId: t.tmdbId, imdbId: t.imdbId)
        case .episode(let s, let e):
            return await localStore.isWatched(mediaType: .episode, tmdbId: t.tmdbId, imdbId: t.imdbId, season: s, episode: e)
        default:
            return false
        }
    }

    /// Locally watched episode numbers of a show, as (season, episode) pairs.
    func locallyWatchedEpisodes(showTmdbId: Int?, showImdbId: String?, season: Int? = nil) async -> Set<EpisodeNumber> {
        let entries = await localStore.watchedEpisodes(tmdbId: showTmdbId, imdbId: showImdbId, season: season)
        return Set(entries.compactMap { entry in
            guard let s = entry.seasonNumber, let e = entry.episodeNumber else { return nil }
            return EpisodeNumber(season: s, episode: e)
        })
    }

    // MARK: - Continue Watching

    /// Removes an item from Continue Watching: Plex hub action, Trakt playback
    /// entry, and the local history/resume entry. Watched state is unchanged.
    func removeFromContinueWatching(_ item: MediaItem) async -> WatchStateResult {
        guard let target = WatchStateTarget(item: item) else { return unsupported(.removeFromContinueWatching, item: item) }
        return await removeFromContinueWatching(target)
    }

    func removeFromContinueWatching(_ target: WatchStateTarget) async -> WatchStateResult {
        await perform(.removeFromContinueWatching, target) { t, outcome in
            await self.applyPlex(t, outcome) { plex, key in
                try await plex.removeFromContinueWatching(ratingKey: key)
            }

            if self.isTraktWatchSyncEnabled {
                let removal = await self.removeTraktPlayback(for: t, afterWrite: false)
                self.record(removal, in: outcome)
            }

            if await self.clearLocalProgress(for: t) > 0 {
                outcome.succeed(.local)
            }
        }
    }

    // MARK: - Start Over

    /// Resets saved progress on Plex, Trakt and locally so the caller can play
    /// from 0. Watched state is unchanged. A result with `noChanges` means there
    /// was no saved progress anywhere; playing from 0 is still correct.
    func startOver(_ item: MediaItem) async -> WatchStateResult {
        guard let target = WatchStateTarget(item: item) else { return unsupported(.startOver, item: item) }
        return await startOver(target)
    }

    func startOver(_ target: WatchStateTarget) async -> WatchStateResult {
        await perform(.startOver, target) { t, outcome in
            switch t.kind {
            case .movie, .episode:
                await self.applyPlex(t, outcome) { plex, key in
                    try await plex.resetProgress(ratingKey: key)
                }
            default:
                break
            }

            if self.isTraktWatchSyncEnabled {
                let removal = await self.removeTraktPlayback(for: t, afterWrite: false)
                self.record(removal, in: outcome)
            }

            if await self.clearLocalProgress(for: t) > 0 {
                outcome.succeed(.local)
            }
        }
    }

    // MARK: - Ratings (Trakt)

    /// Rates a movie, show, season or episode on Trakt (1-10). Needs Trakt connected.
    func rate(_ item: MediaItem, rating: Int) async -> WatchStateResult {
        guard let target = WatchStateTarget(item: item) else { return unsupported(.rate, item: item) }
        return await rate(target, rating: rating)
    }

    func rate(_ target: WatchStateTarget, rating: Int) async -> WatchStateResult {
        guard (1...10).contains(rating) else {
            return WatchStateResult(action: .rate, target: target, succeeded: [], failures: [.init(backend: .trakt, message: String(localized: "rating must be 1-10"))])
        }
        guard canRate else { return traktRequired(.rate, target) }
        return await perform(.rate, target, rating: rating) { t, outcome in
            guard let items = self.traktItems(for: t, rating: rating) else {
                outcome.fail(.trakt, message: String(localized: "couldn't match on Trakt"))
                return
            }
            do {
                let result = try await FlixorCore.shared.trakt.addRatings(items)
                if result.addedCount == 0, result.notFoundCount > 0 {
                    outcome.fail(.trakt, message: String(localized: "couldn't match on Trakt"))
                } else {
                    outcome.succeed(.trakt)
                }
            } catch {
                outcome.fail(.trakt, error)
            }
            self.ratingsCache[Self.ratingType(for: t.kind)] = nil
        }
    }

    func removeRating(_ item: MediaItem) async -> WatchStateResult {
        guard let target = WatchStateTarget(item: item) else { return unsupported(.removeRating, item: item) }
        return await removeRating(target)
    }

    func removeRating(_ target: WatchStateTarget) async -> WatchStateResult {
        guard canRate else { return traktRequired(.removeRating, target) }
        return await perform(.removeRating, target) { t, outcome in
            guard let items = self.traktItems(for: t) else {
                outcome.fail(.trakt, message: String(localized: "couldn't match on Trakt"))
                return
            }
            do {
                try await FlixorCore.shared.trakt.removeRatings(items)
                outcome.succeed(.trakt)
            } catch {
                outcome.fail(.trakt, error)
            }
            self.ratingsCache[Self.ratingType(for: t.kind)] = nil
        }
    }

    /// The user's Trakt rating (1-10) for an item, nil when unrated, Trakt isn't
    /// connected or the lookup fails. Ratings are fetched per type and cached 5 min.
    func rating(for item: MediaItem) async -> Int? {
        guard let target = WatchStateTarget(item: item) else { return nil }
        return await rating(for: target)
    }

    func rating(for target: WatchStateTarget) async -> Int? {
        guard canRate else { return nil }
        let t = await resolve(target, needTitleIds: true)
        guard t.tmdbId != nil || t.imdbId != nil || t.tvdbId != nil else { return nil }
        let type = Self.ratingType(for: t.kind)
        guard let items = try? await ratings(type: type) else { return nil }

        return items.first { item in
            switch t.kind {
            case .movie:
                return item.movie.map { idsMatch($0.ids, t) } ?? false
            case .show:
                return item.show.map { idsMatch($0.ids, t) } ?? false
            case .season(let n):
                guard let n, let show = item.show, idsMatch(show.ids, t) else { return false }
                return item.season?.number == n
            case .episode(let s, let e):
                guard let s, let e, let show = item.show, idsMatch(show.ids, t), let ep = item.episode else { return false }
                return ep.season == s && ep.number == e
            }
        }?.rating
    }

    // MARK: - Trakt id helpers (also used by TraktListsService)

    /// Trakt ids of the movie/show behind a resolved target.
    func traktIds(for target: WatchStateTarget) -> TraktScrobbleIds? {
        guard target.tmdbId != nil || target.imdbId != nil || target.tvdbId != nil else { return nil }
        return TraktScrobbleIds(
            imdb: target.imdbId,
            tmdb: target.tmdbId,
            tvdb: target.isMovie ? nil : target.tvdbId
        )
    }

    /// Sync body for a resolved target. Nil when there is no usable id or the
    /// season/episode numbers are unknown.
    func traktItems(for target: WatchStateTarget, rating: Int? = nil) -> TraktSyncItems? {
        guard let ids = traktIds(for: target) else { return nil }
        switch target.kind {
        case .movie:
            return .movie(ids, rating: rating)
        case .show:
            return .show(ids, rating: rating)
        case .season(let n):
            guard let n else { return nil }
            return .season(showIds: ids, season: n, rating: rating)
        case .episode(let s, let e):
            guard let s, let e else { return nil }
            return .episode(showIds: ids, season: s, episode: e, rating: rating)
        }
    }

    /// Fills in show keys, season/episode numbers and the item's own ratingKey
    /// (from Plex), and title-level external ids (from Plex GUIDs, or TMDB<->IMDb).
    func resolve(_ target: WatchStateTarget, needTitleIds: Bool) async -> WatchStateTarget {
        var t = target

        // Season/episode numbers and the show key from the item's own Plex key.
        if let key = t.plexRatingKey {
            let needsStructure: Bool
            switch t.kind {
            case .season(let n): needsStructure = n == nil || t.showPlexRatingKey == nil
            case .episode(let s, let e): needsStructure = s == nil || e == nil || t.showPlexRatingKey == nil
            default: needsStructure = false
            }
            if needsStructure, let context = await resolver.plexContext(ratingKey: key) {
                switch t.kind {
                case .season(let n):
                    t.kind = .season(n ?? context.index)
                    t.showPlexRatingKey = t.showPlexRatingKey ?? context.parentRatingKey
                case .episode(let s, let e):
                    t.kind = .episode(season: s ?? context.parentIndex, episode: e ?? context.index)
                    t.showPlexRatingKey = t.showPlexRatingKey ?? context.grandparentRatingKey
                default:
                    break
                }
            }
        }

        // Only the show's key is known: find the season (and episode) under it.
        if t.plexRatingKey == nil, let showKey = t.showPlexRatingKey {
            switch t.kind {
            case .season(let n?):
                t.plexRatingKey = await resolver.plexChildRatingKey(parentRatingKey: showKey, index: n)
            case .episode(let s?, let e?):
                if let seasonKey = await resolver.plexChildRatingKey(parentRatingKey: showKey, index: s) {
                    t.plexRatingKey = await resolver.plexChildRatingKey(parentRatingKey: seasonKey, index: e)
                }
            default:
                break
            }
        }

        if needTitleIds, t.tmdbId == nil, t.imdbId == nil,
           let key = t.showPlexRatingKey ?? t.plexRatingKey,
           let ids = await resolver.titleIds(plexRatingKey: key) {
            t.tmdbId = ids.tmdbId
            t.imdbId = ids.imdbId
            t.tvdbId = t.tvdbId ?? ids.tvdbId
        }

        if needTitleIds {
            let isShow = !t.isMovie
            if t.tmdbId == nil, let imdb = t.imdbId {
                t.tmdbId = await resolver.tmdbId(imdbId: imdb, isShow: isShow)
            }
            if t.imdbId == nil, let tmdb = t.tmdbId {
                t.imdbId = await resolver.imdbId(tmdbId: tmdb, isShow: isShow)
            }
        }
        return t
    }

    // MARK: - Private: action runner

    private final class Outcome {
        var succeeded: [WatchStateBackend] = []
        var failures: [WatchStateResult.Failure] = []
        /// Something was checked and found already in the requested state.
        var sawUnchanged = false

        func succeed(_ backend: WatchStateBackend) {
            if !succeeded.contains(backend) { succeeded.append(backend) }
        }

        func unchanged() {
            sawUnchanged = true
        }

        func fail(_ backend: WatchStateBackend, _ error: Error) {
            fail(backend, message: Self.describe(error))
        }

        func fail(_ backend: WatchStateBackend, message: String) {
            failures.append(.init(backend: backend, message: message))
        }

        private static func describe(_ error: Error) -> String {
            if let trakt = error as? TraktError {
                switch trakt {
                case .authenticationRequired: return String(localized: "sign-in expired")
                case .httpError(429): return String(localized: "rate limited, try again shortly")
                case .httpError(404): return String(localized: "couldn't match on Trakt")
                case .httpError(let code): return String(localized: "error \(code)")
                default: return trakt.localizedDescription
                }
            }
            if let plex = error as? PlexServerError, case .httpError(let code) = plex {
                return code == 404 ? String(localized: "not supported by this server") : String(localized: "error \(code)")
            }
            return error.localizedDescription
        }
    }

    private func perform(
        _ action: WatchStateAction,
        _ target: WatchStateTarget,
        rating: Int? = nil,
        body: (WatchStateTarget, Outcome) async -> Void
    ) async -> WatchStateResult {
        if action.isWatchStateWrite, target.kind == .show, target.isNewEpisodesCard {
            return WatchStateResult(action: action, target: target, succeeded: [], failures: [
                .init(backend: nil, message: String(localized: "this card is for new episodes; open the show to pick episodes")),
            ])
        }

        // Keyed by target only, so opposite actions on one item can't interleave.
        let key = target.actionKey
        guard !inFlight.contains(key) else {
            return WatchStateResult(action: action, target: target, succeeded: [], failures: [
                .init(backend: nil, message: String(localized: "another change to this item is in progress")),
            ])
        }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let needsIds = isTraktConnected || !isPlexItem(target)
        let resolved = await resolve(target, needTitleIds: needsIds)
        let outcome = Outcome()
        await body(resolved, outcome)

        let noChanges = outcome.succeeded.isEmpty && outcome.failures.isEmpty
        if noChanges, !outcome.sawUnchanged, action != .startOver, action != .removeFromContinueWatching {
            outcome.failures.append(.init(backend: nil, message: String(localized: "nothing to update for this item")))
        }

        let result = WatchStateResult(
            action: action,
            target: resolved,
            succeeded: outcome.succeeded,
            failures: outcome.failures,
            noChanges: outcome.succeeded.isEmpty && outcome.failures.isEmpty
        )
        if !result.succeeded.isEmpty {
            let change = WatchStateChange(action: action, target: resolved, rating: rating, backends: result.succeeded)
            NotificationCenter.default.post(name: .watchStateDidChange, object: nil, userInfo: change.userInfo)
        }
        AppLogger.shared.info("[WatchState] \(action.rawValue) \(resolved.actionKey)", data: [
            "succeeded": result.succeeded.map(\.rawValue).joined(separator: ","),
            "failures": result.failures.map(\.message).joined(separator: "; "),
            "noChanges": result.noChanges,
        ])
        return result
    }

    private func unsupported(_ action: WatchStateAction, item: MediaItem) -> WatchStateResult {
        let target = WatchStateTarget(kind: .movie, title: item.title, sourceItemId: item.id)
        return WatchStateResult(action: action, target: target, succeeded: [], failures: [.init(backend: nil, message: String(localized: "unsupported item"))])
    }

    private func traktRequired(_ action: WatchStateAction, _ target: WatchStateTarget) -> WatchStateResult {
        WatchStateResult(action: action, target: target, succeeded: [], failures: [.init(backend: .trakt, message: String(localized: "connect Trakt in Settings"))])
    }

    // MARK: - Private: Plex

    /// The item lives on Plex (it has its own or its show's ratingKey). Such items
    /// are never written to the local store.
    private func isPlexItem(_ t: WatchStateTarget) -> Bool {
        t.plexRatingKey != nil || t.showPlexRatingKey != nil
    }

    /// Runs a Plex action for Plex items, recording a failure (never a silent skip)
    /// when the server isn't available or the season/episode key can't be found.
    private func applyPlex(
        _ t: WatchStateTarget,
        _ outcome: Outcome,
        _ action: (PlexServerService, String) async throws -> Void
    ) async {
        guard isPlexItem(t) else { return }
        guard let plex = plexServer else {
            outcome.fail(.plex, message: isStremioOnlyMode ? String(localized: "not used in Stremio-only mode") : String(localized: "no server connected"))
            return
        }
        guard let key = t.plexRatingKey else {
            outcome.fail(.plex, message: Self.notOnServerMessage(for: t.kind))
            return
        }
        do {
            try await action(plex, key)
            outcome.succeed(.plex)
        } catch {
            outcome.fail(.plex, error)
        }
        await plex.invalidateWatchStateCache(ratingKeys: [key, t.showPlexRatingKey].compactMap { $0 })
    }

    // MARK: - Private: Trakt

    /// Adds only what isn't already watched on Trakt: for shows/seasons the aired,
    /// unwatched episodes (from Trakt watched progress); for an episode or movie,
    /// nothing when it's already watched. Records a failure when Trakt should have
    /// been updated but couldn't be.
    private func addTraktHistory(_ t: WatchStateTarget, _ outcome: Outcome) async {
        guard let ids = traktIds(for: t) else {
            outcome.fail(.trakt, message: String(localized: "couldn't match on Trakt"))
            return
        }
        let trakt = FlixorCore.shared.trakt
        let items: TraktSyncItems

        do {
            switch t.kind {
            case .movie:
                guard let traktId = await resolver.traktId(tmdbId: t.tmdbId, imdbId: t.imdbId, isShow: false) else {
                    outcome.fail(.trakt, message: String(localized: "couldn't match on Trakt"))
                    return
                }
                let history = try await trakt.getItemHistory(type: "movies", traktId: traktId, limit: 1)
                if !history.isEmpty {
                    outcome.unchanged()
                    return
                }
                items = .movie(ids)

            case .show, .season, .episode:
                guard let showId = await traktShowId(for: t) else {
                    outcome.fail(.trakt, message: String(localized: "couldn't match on Trakt"))
                    return
                }
                let progress = try await trakt.getShowWatchedProgress(showId: showId)
                guard let missing = Self.unwatchedEpisodes(in: progress, for: t.kind) else {
                    outcome.fail(.trakt, message: String(localized: "season/episode not known yet"))
                    return
                }
                if missing.isEmpty {
                    if progress.aired == 0, t.kind == .show {
                        outcome.fail(.trakt, message: String(localized: "no aired episodes on Trakt"))
                    } else {
                        outcome.unchanged()
                    }
                    return
                }
                let seasons = Dictionary(grouping: missing, by: \.season)
                    .sorted { $0.key < $1.key }
                    .map { season, episodes in
                        TraktSyncSeason(number: season, episodes: episodes.map { TraktSyncEpisode(number: $0.episode) })
                    }
                items = TraktSyncItems(shows: [TraktSyncShow(ids: ids, seasons: seasons)])
            }
        } catch {
            outcome.fail(.trakt, error)
            return
        }

        do {
            let result = try await trakt.addToHistory(items)
            if result.addedCount == 0, result.notFoundCount > 0 {
                outcome.fail(.trakt, message: String(localized: "couldn't match on Trakt"))
                return
            }
            outcome.succeed(.trakt)
        } catch {
            outcome.fail(.trakt, error)
            return
        }

        let removal = await removeTraktPlayback(for: t, afterWrite: true)
        if removal.failed > 0 || removal.fetchFailed {
            outcome.fail(.trakt, message: String(localized: "couldn't clear saved progress"))
        }
    }

    /// Id accepted by Trakt's show endpoints: IMDb id when known, else Trakt id.
    private func traktShowId(for t: WatchStateTarget) async -> String? {
        if let imdb = t.imdbId, imdb.lowercased().hasPrefix("tt") { return imdb }
        return await resolver.traktId(tmdbId: t.tmdbId, imdbId: nil, isShow: true).map(String.init)
    }

    /// Aired episodes not yet watched that the target covers. Nil when the target's
    /// season/episode numbers are unknown. An episode Trakt doesn't list as aired is
    /// returned as-is (the user is asserting they watched it).
    private static func unwatchedEpisodes(in progress: TraktShowWatchedProgress, for kind: WatchStateTarget.Kind) -> [EpisodeNumber]? {
        func incomplete(_ season: TraktShowWatchedProgress.Season) -> [EpisodeNumber] {
            season.episodes.filter { !$0.completed }.map { EpisodeNumber(season: season.number, episode: $0.number) }
        }
        switch kind {
        case .movie:
            return []
        case .show:
            return progress.seasons.filter { $0.number > 0 }.flatMap(incomplete)
        case .season(let n):
            guard let n else { return nil }
            return progress.seasons.first { $0.number == n }.map(incomplete) ?? []
        case .episode(let s, let e):
            guard let s, let e else { return nil }
            let listed = progress.seasons.first { $0.number == s }?.episodes.first { $0.number == e }
            if let listed, listed.completed { return [] }
            return [EpisodeNumber(season: s, episode: e)]
        }
    }

    private struct PlaybackRemoval {
        var removed = 0
        var failed = 0
        var fetchFailed = false
    }

    private static func notOnServerMessage(for kind: WatchStateTarget.Kind) -> String {
        switch kind {
        case .movie: return String(localized: "couldn't find this movie on the server")
        case .show: return String(localized: "couldn't find this show on the server")
        case .season: return String(localized: "couldn't find this season on the server")
        case .episode: return String(localized: "couldn't find this episode on the server")
        }
    }

    private func record(_ removal: PlaybackRemoval, in outcome: Outcome) {
        if removal.fetchFailed {
            outcome.fail(.trakt, message: String(localized: "couldn't read saved progress"))
        } else if removal.failed > 0 {
            outcome.fail(.trakt, message: String(localized: "couldn't remove \(removal.failed) saved progress entries"))
        }
        if removal.removed > 0 { outcome.succeed(.trakt) }
    }

    /// Deletes Trakt playback (paused) entries that exactly match the target
    /// (a show matches all its episodes; a season with unknown number matches
    /// nothing). Deletes are spaced ~1 s apart for Trakt's write limit.
    private func removeTraktPlayback(for t: WatchStateTarget, afterWrite: Bool) async -> PlaybackRemoval {
        var removal = PlaybackRemoval()
        guard isTraktWatchSyncEnabled, traktIds(for: t) != nil else { return removal }
        let type = t.isMovie ? "movies" : "episodes"
        let entries: [TraktPlaybackItem]
        do {
            entries = try await FlixorCore.shared.trakt.getPlaybackProgress(type: type)
        } catch {
            removal.fetchFailed = true
            return removal
        }

        let matching = entries.filter { entry in
            switch t.kind {
            case .movie:
                return entry.movie.map { idsMatch($0.ids, t) } ?? false
            case .show:
                return entry.show.map { idsMatch($0.ids, t) } ?? false
            case .season(let n):
                guard let n, let show = entry.show, idsMatch(show.ids, t) else { return false }
                return entry.episode?.season == n
            case .episode(let s, let e):
                guard let s, let e, let show = entry.show, idsMatch(show.ids, t), let ep = entry.episode else { return false }
                return ep.season == s && ep.number == e
            }
        }

        var needsSpacing = afterWrite
        for entry in matching {
            if needsSpacing {
                try? await Task.sleep(nanoseconds: traktWriteSpacingNs)
            }
            needsSpacing = true
            do {
                try await FlixorCore.shared.trakt.removePlaybackProgress(id: entry.id)
                removal.removed += 1
            } catch {
                removal.failed += 1
                AppLogger.shared.warn("[WatchState] Trakt playback delete failed", data: [
                    "id": entry.id, "error": error.localizedDescription,
                ])
            }
        }
        return removal
    }

    private func ratings(type: String) async throws -> [TraktRatingItem] {
        if let cached = ratingsCache[type], Date().timeIntervalSince(cached.fetchedAt) < ratingsTTL {
            return cached.items
        }
        if let task = ratingsInFlight[type] {
            return try await task.value
        }
        let trakt = FlixorCore.shared.trakt
        let task = Task { try await trakt.getUserRatings(type: type) }
        ratingsInFlight[type] = task
        defer { ratingsInFlight[type] = nil }
        let items = try await task.value
        ratingsCache[type] = (Date(), items)
        return items
    }

    private static func ratingType(for kind: WatchStateTarget.Kind) -> String {
        switch kind {
        case .movie: return "movies"
        case .show: return "shows"
        case .season: return "seasons"
        case .episode: return "episodes"
        }
    }

    // MARK: - Private: local

    /// Removes local resume points and history entries (Continue Watching).
    /// Returns how many entries were removed.
    @discardableResult
    private func clearLocalProgress(for t: WatchStateTarget) async -> Int {
        guard t.tmdbId != nil || t.imdbId != nil else { return 0 }
        let isMovie = t.isMovie
        let season = t.seasonNumber
        let episode = t.episodeNumber
        if case .episode = t.kind, season == nil || episode == nil { return 0 }
        if case .season = t.kind, season == nil { return 0 }

        let resume = await resumeStore.removeAll(isMovie: isMovie, tmdbId: t.tmdbId, imdbId: t.imdbId, season: season, episode: episode)
        let history = await localStore.removeHistory(
            mediaType: isMovie ? .movie : .episode,
            tmdbId: t.tmdbId, imdbId: t.imdbId, season: season, episode: episode
        )
        return resume.count + history.count
    }

    private enum LocalWatchError: LocalizedError {
        case missingIds, noEpisodes
        var errorDescription: String? {
            switch self {
            case .missingIds: return String(localized: "no TMDB or IMDb id")
            case .noEpisodes: return String(localized: "no aired episodes found")
            }
        }
    }

    private func markLocallyWatched(_ t: WatchStateTarget) async throws {
        guard t.tmdbId != nil || t.imdbId != nil else { throw LocalWatchError.missingIds }
        let now = Date()
        var entries: [LocalWatchedEntry] = []

        switch t.kind {
        case .movie:
            entries = [LocalWatchedEntry(mediaType: .movie, tmdbId: t.tmdbId, imdbId: t.imdbId, watchedAt: now)].compactMap { $0 }
        case .episode(let s, let e):
            entries = [LocalWatchedEntry(mediaType: .episode, tmdbId: t.tmdbId, imdbId: t.imdbId, seasonNumber: s, episodeNumber: e, watchedAt: now)].compactMap { $0 }
        case .season(let n):
            guard let tmdb = t.tmdbId, let n else { throw LocalWatchError.missingIds }
            let numbers = try await airedEpisodes(tvId: tmdb, season: n)
            entries = numbers.compactMap {
                LocalWatchedEntry(mediaType: .episode, tmdbId: tmdb, imdbId: t.imdbId, seasonNumber: n, episodeNumber: $0, watchedAt: now)
            }
        case .show:
            guard let tmdb = t.tmdbId else { throw LocalWatchError.missingIds }
            let details = try await FlixorCore.shared.tmdb.getTVDetails(id: tmdb)
            let seasons = details.seasons.compactMap(\.seasonNumber).filter { $0 > 0 }
            for season in seasons {
                try Task.checkCancellation()
                let numbers = (try? await airedEpisodes(tvId: tmdb, season: season)) ?? []
                entries += numbers.compactMap {
                    LocalWatchedEntry(mediaType: .episode, tmdbId: tmdb, imdbId: t.imdbId, seasonNumber: season, episodeNumber: $0, watchedAt: now)
                }
            }
        }

        guard !entries.isEmpty else { throw LocalWatchError.noEpisodes }
        await localStore.markWatched(entries)
    }

    /// Returns how many local watched entries were removed.
    private func removeLocallyWatched(_ t: WatchStateTarget) async -> Int {
        switch t.kind {
        case .movie:
            return await localStore.removeWatched(mediaType: .movie, tmdbId: t.tmdbId, imdbId: t.imdbId)
        case .show:
            return await localStore.removeWatched(mediaType: .episode, tmdbId: t.tmdbId, imdbId: t.imdbId)
        case .season(let n):
            guard let n else { return 0 }
            return await localStore.removeWatched(mediaType: .episode, tmdbId: t.tmdbId, imdbId: t.imdbId, season: n)
        case .episode(let s, let e):
            guard let s, let e else { return 0 }
            return await localStore.removeWatched(mediaType: .episode, tmdbId: t.tmdbId, imdbId: t.imdbId, season: s, episode: e)
        }
    }

    /// Episode numbers of a season that have aired (air date today or earlier).
    private func airedEpisodes(tvId: Int, season: Int) async throws -> [Int] {
        let details = try await FlixorCore.shared.tmdb.getSeasonDetails(tvId: tvId, seasonNumber: season)
        let today = Self.dayFormatter.string(from: Date())
        return details.episodes.compactMap { ep in
            guard let number = ep.episodeNumber else { return nil }
            guard let air = ep.airDate, !air.isEmpty, air <= today else { return nil }
            return number
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// A season/episode pair.
struct EpisodeNumber: Hashable {
    let season: Int
    let episode: Int
}

private func idsMatch(_ ids: TraktIds, _ t: WatchStateTarget) -> Bool {
    if let tmdb = t.tmdbId, ids.tmdb == tmdb { return true }
    if let imdb = t.imdbId, let other = ids.imdb, other.caseInsensitiveCompare(imdb) == .orderedSame { return true }
    if !t.isMovie, let tvdb = t.tvdbId, ids.tvdb == tvdb { return true }
    return false
}
