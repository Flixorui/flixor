//
//  DetailsTitleActionsModel.swift
//  FlixorMac
//
//  Title-level watch state and Trakt rating for the details hero: whether the
//  movie / show / season / episode on screen is watched (Plex viewCount or
//  viewedLeafCount when it has a Plex copy, otherwise the local store), mark
//  watched / unwatched with optimistic UI, and the user's Trakt rating.
//  All writes go through WatchStateService; the model refreshes itself on
//  `.watchStateDidChange`.
//
//  Kept out of DetailsViewModel on purpose: it is owned by DetailsView and handed
//  to the hero through the environment (`\.detailsTitleActions`).
//

import Foundation
import Combine
import SwiftUI
import FlixorKit

@MainActor
final class DetailsTitleActionsModel: ObservableObject {
    enum TitleKind: Equatable {
        case movie, episode, season, show

        /// Shows and seasons get a menu; movies and episodes a single toggle.
        var isCollection: Bool { self == .show || self == .season }
    }

    struct SeasonOption: Identifiable {
        let id: String
        let title: String
        let target: WatchStateTarget
    }

    // MARK: Published state

    @Published private(set) var target: WatchStateTarget?
    @Published private(set) var kind: TitleKind?
    /// nil while unknown.
    @Published private(set) var isWatched: Bool?
    /// Partially watched (movie/episode with a resume point, or some episodes of a show/season).
    @Published private(set) var isInProgress = false
    /// e.g. "3 of 10 episodes watched".
    @Published private(set) var progressText: String?
    @Published private(set) var seasonOptions: [SeasonOption] = []
    /// A watch-state action started here is running.
    @Published private(set) var isWorking = false

    @Published private(set) var canRate = false
    @Published private(set) var userRating: Int?
    @Published private(set) var isRatingWorking = false

    // MARK: Private

    private let service = WatchStateService.shared
    private var episodeTotalHint: Int?
    private var refreshTask: Task<Void, Never>?
    private var ratingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .watchStateDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let change = WatchStateChange(notification: note) else { return }
                self?.handle(change)
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    /// Rebuilds the target from the loaded details and refreshes state. Call after
    /// every `DetailsViewModel.load(for:)`.
    func configure(with vm: DetailsViewModel) {
        refreshTask?.cancel()
        ratingTask?.cancel()

        let built = Self.makeTarget(vm: vm)
        target = built?.target
        kind = built?.kind
        isWatched = nil
        isInProgress = false
        progressText = nil
        userRating = nil
        canRate = service.canRate && built != nil
        episodeTotalHint = vm.numberOfEpisodes ?? vm.episodeCount
        seasonOptions = built?.kind == .show ? Self.makeSeasonOptions(vm: vm, showTarget: built?.target) : []

        guard built != nil else { return }
        scheduleRefresh()
        loadRating()
    }

    // MARK: - Watched

    /// Marks the title (or one of its seasons) watched / unwatched. The title's
    /// state flips immediately and is rolled back if every backend failed.
    func setWatched(_ watched: Bool, season: SeasonOption? = nil) {
        guard let titleTarget = target, !isWorking else { return }
        let actionTarget = season?.target ?? titleTarget
        let affectsTitle = season == nil
        let previous = (isWatched, isInProgress, progressText)

        if affectsTitle {
            isWatched = watched
            isInProgress = false
            progressText = nil
        }
        isWorking = true
        refreshTask?.cancel()

        Task {
            let result = watched
                ? await service.markWatched(actionTarget)
                : await service.markUnwatched(actionTarget)
            isWorking = false
            Self.showToast(for: result)

            if Self.didFail(result) {
                if affectsTitle {
                    (isWatched, isInProgress, progressText) = previous
                }
            } else {
                scheduleRefresh()
            }
        }
    }

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refreshWatchState()
        }
    }

    private func refreshWatchState() async {
        guard let target, let kind else { return }

        // Plex copy: read the server's view counts (fresh, so changes made in the
        // player or elsewhere show up).
        if let key = target.plexRatingKey, !isStremioOnlyMode, let plex = FlixorCore.shared.plexServer {
            if let meta = try? await plex.getMetadata(ratingKey: key, bypassCache: true) {
                guard !Task.isCancelled, !isWorking else { return }
                apply(plexMeta: meta, kind: kind)
                return
            }
        }

        // No Plex copy: the local store (what WatchStateService writes for these).
        switch kind {
        case .movie, .episode:
            let watched = await service.isWatchedLocally(target)
            guard !Task.isCancelled, !isWorking else { return }
            isWatched = watched
            isInProgress = false
            progressText = nil
        case .show, .season:
            let resolvedSeason: Int? = kind == .season ? target.seasonNumber : nil
            if kind == .season && resolvedSeason == nil {
                guard !Task.isCancelled, !isWorking else { return }
                isWatched = false
                return
            }
            let watchedEpisodes = await service.locallyWatchedEpisodes(
                showTmdbId: target.tmdbId,
                showImdbId: target.imdbId,
                season: resolvedSeason
            )
            guard !Task.isCancelled, !isWorking else { return }
            let count = watchedEpisodes.count
            if kind == .show, let total = episodeTotalHint, total > 0 {
                isWatched = count >= total
                isInProgress = count > 0 && count < total
                progressText = isInProgress ? String(localized: "\(count) of \(total) episodes watched") : nil
            } else {
                isWatched = false
                isInProgress = count > 0
                progressText = count > 0 ? String(localized: "\(count) episodes watched") : nil
            }
        }
    }

    private func apply(plexMeta meta: FlixorKit.PlexMediaItem, kind: TitleKind) {
        switch kind {
        case .movie, .episode:
            let watched = (meta.viewCount ?? 0) > 0
            let offset = meta.viewOffset ?? 0
            isWatched = watched
            isInProgress = !watched && offset > 0
            progressText = isInProgress ? String(localized: "In progress") : nil
        case .show, .season:
            let total = meta.leafCount ?? 0
            let viewed = meta.viewedLeafCount ?? 0
            isWatched = total > 0 && viewed >= total
            isInProgress = viewed > 0 && viewed < total
            progressText = isInProgress ? String(localized: "\(viewed) of \(total) episodes watched") : nil
        }
    }

    // MARK: - Rating (Trakt)

    func loadRating() {
        ratingTask?.cancel()
        canRate = service.canRate && target != nil
        guard canRate, let target else {
            userRating = nil
            return
        }
        ratingTask = Task { [weak self] in
            guard let self else { return }
            let rating = await self.service.rating(for: target)
            guard !Task.isCancelled, !self.isRatingWorking else { return }
            self.userRating = rating
        }
    }

    func rate(_ value: Int) {
        guard let target, canRate, !isRatingWorking, (1...10).contains(value) else { return }
        let previous = userRating
        userRating = value
        isRatingWorking = true
        ratingTask?.cancel()
        Task {
            let result = await service.rate(target, rating: value)
            isRatingWorking = false
            Self.showToast(for: result)
            if Self.didFail(result) { userRating = previous }
        }
    }

    func removeRating() {
        guard let target, canRate, !isRatingWorking else { return }
        let previous = userRating
        userRating = nil
        isRatingWorking = true
        ratingTask?.cancel()
        Task {
            let result = await service.removeRating(target)
            isRatingWorking = false
            Self.showToast(for: result)
            if Self.didFail(result) { userRating = previous }
        }
    }

    // MARK: - Notifications

    private func handle(_ change: WatchStateChange) {
        guard let target, relates(change.target, to: target) else { return }
        switch change.action {
        case .rate, .removeRating:
            guard change.target.kind == target.kind || sameKindFamily(change.target.kind, target.kind) else { return }
            if !isRatingWorking {
                userRating = change.action == .rate ? change.rating : nil
            }
        default:
            if !isWorking { scheduleRefresh() }
        }
    }

    private func sameKindFamily(_ a: WatchStateTarget.Kind, _ b: WatchStateTarget.Kind) -> Bool {
        switch (a, b) {
        case (.season(let x), .season(let y)): return x == nil || y == nil || x == y
        case (.episode(let s1, let e1), .episode(let s2, let e2)):
            return (s1 == nil || s2 == nil || s1 == s2) && (e1 == nil || e2 == nil || e1 == e2)
        default: return false
        }
    }

    /// Whether a change to `other` can affect the title on screen (same item, one
    /// of its seasons/episodes, or its parent show).
    private func relates(_ other: WatchStateTarget, to mine: WatchStateTarget) -> Bool {
        if let key = mine.plexRatingKey, key == other.plexRatingKey || key == other.showPlexRatingKey { return true }
        if let show = mine.showPlexRatingKey, show == other.plexRatingKey { return true }
        if mine.isMovie != other.isMovie { return false }
        if let tmdb = mine.tmdbId, tmdb == other.tmdbId { return true }
        if let imdb = mine.imdbId?.lowercased(), imdb == other.imdbId?.lowercased() { return true }
        return false
    }

    // MARK: - Toast

    /// Nothing was applied and something went wrong. `noChanges` is not a failure:
    /// the item was already in the requested state.
    private static func didFail(_ result: WatchStateResult) -> Bool {
        !result.isSuccess && !result.isPartialSuccess && !result.noChanges
    }

    static func showToast(for result: WatchStateResult) {
        let type: ToastView.ToastType = result.isSuccess
            ? .success
            : (result.isPartialSuccess || result.noChanges ? .info : .error)
        ToastManager.shared.show(result.message, type: type)
    }

    // MARK: - Target building

    private static func makeTarget(vm: DetailsViewModel) -> (target: WatchStateTarget, kind: TitleKind)? {
        guard var target = vm.titleWatchTarget else { return nil }

        // titleWatchTarget reads plexRatingKey only; plain-id Plex loads set just
        // playableId. Without Plex (Stremio-only) the key must be absent so the
        // service writes to the local store.
        if isStremioOnlyMode {
            target.plexRatingKey = nil
            target.showPlexRatingKey = nil
            guard target.tmdbId != nil || target.imdbId != nil else { return nil }
        } else if target.plexRatingKey == nil {
            target.plexRatingKey = vm.heroPlexRatingKey
        }
        target.sourceItemId = target.plexRatingKey.map { "plex:\($0)" }

        let kind: TitleKind
        switch target.kind {
        case .movie: kind = .movie
        case .show: kind = .show
        case .season: kind = .season
        case .episode: kind = .episode
        }
        return (target, kind)
    }

    private static func makeSeasonOptions(vm: DetailsViewModel, showTarget: WatchStateTarget?) -> [SeasonOption] {
        guard let showTarget else { return [] }
        return vm.seasons.compactMap { season in
            let usesPlex = season.source == "plex" && !isStremioOnlyMode
            if usesPlex {
                let target = WatchStateTarget(
                    kind: .season(season.number),
                    plexRatingKey: season.id,
                    showPlexRatingKey: showTarget.plexRatingKey,
                    tmdbId: showTarget.tmdbId,
                    imdbId: showTarget.imdbId,
                    title: showTarget.title
                )
                return SeasonOption(id: season.id, title: season.title, target: target)
            }
            guard let number = season.number else { return nil }
            let target = WatchStateTarget.season(
                number,
                showTmdbId: showTarget.tmdbId,
                showImdbId: showTarget.imdbId,
                title: showTarget.title
            )
            return SeasonOption(id: season.id, title: season.title, target: target)
        }
    }
}

// MARK: - Environment

private struct DetailsTitleActionsKey: EnvironmentKey {
    static let defaultValue: DetailsTitleActionsModel? = nil
}

extension EnvironmentValues {
    /// Title watch-state / rating model for the details hero (set by DetailsView).
    var detailsTitleActions: DetailsTitleActionsModel? {
        get { self[DetailsTitleActionsKey.self] }
        set { self[DetailsTitleActionsKey.self] = newValue }
    }
}
