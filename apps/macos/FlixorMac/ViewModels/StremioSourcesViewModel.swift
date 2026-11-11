//
//  StremioSourcesViewModel.swift
//  FlixorMac
//
//  Resolves and groups playable Stremio sources for a title.
//

import Foundation
import SwiftUI

@MainActor
final class StremioSourcesViewModel: ObservableObject {
    enum EmptyState {
        case none
        case noAddons
        case noStreams
        case unsupportedOnly
        case error(String)

        var title: String {
            switch self {
            case .none:
                return ""
            case .noAddons:
                return String(localized: "No stream-capable addons installed")
            case .noStreams:
                return String(localized: "No streams found")
            case .unsupportedOnly:
                return String(localized: "Only unsupported sources were returned")
            case .error:
                return String(localized: "Failed to load Stremio sources")
            }
        }

        var message: String {
            switch self {
            case .none:
                return ""
            case .noAddons:
                return String(localized: "Install at least one Stremio addon that provides streams for this title.")
            case .noStreams:
                return String(localized: "Installed addons responded, but none returned playable sources for this request.")
            case .unsupportedOnly:
                return String(localized: "The installed addons only returned source types that cannot be played in-app on macOS yet.")
            case .error(let message):
                return message
            }
        }
    }

    @Published var isLoading = false
    @Published var groupedResults: [StremioAddonStreamResult] = [] {
        didSet { resultsVersion &+= 1 }
    }
    @Published var selectedProviderFilter = "all"
    @Published var emptyState: EmptyState = .none
    @Published var cachedSource: CachedPlaybackSource?
    @Published var alertMessage: String?

    let destination: StremioSourcesDestination

    private let profileSettings = ProfileSettings.shared
    private let service = StremioService.shared
    private let streamCache = StremioStreamCache.shared
    private let resumeStore = StremioResumeStore.shared

    /// Changes whenever `groupedResults` is assigned, so views can cache work derived from it.
    private(set) var resultsVersion = 0
    private var hasLoaded = false
    private var loadGeneration = 0

    init(destination: StremioSourcesDestination) {
        self.destination = destination
    }

    var providerFilters: [String] {
        let providers = groupedResults
            .filter { !$0.streams.isEmpty || $0.error != nil }
            .map(\.installationId)
        return ["all"] + providers
    }

    var filteredGroups: [StremioAddonStreamResult] {
        groupedResults.filter { result in
            selectedProviderFilter == "all" || result.installationId == selectedProviderFilter
        }
    }

    var playableGroups: [StremioAddonStreamResult] {
        filteredGroups
            .map { result in
                StremioAddonStreamResult(
                    addonId: result.addonId,
                    addonName: result.addonName,
                    installationId: result.installationId,
                    streams: result.streams.filter(\.playable),
                    error: result.error
                )
            }
            .filter { !$0.streams.isEmpty || $0.error != nil }
    }

    var unsupportedGroups: [StremioAddonStreamResult] {
        guard profileSettings.stremioUnsupportedSourceVisibility == .showDisabled else { return [] }

        return filteredGroups
            .map { result in
                StremioAddonStreamResult(
                    addonId: result.addonId,
                    addonName: result.addonName,
                    installationId: result.installationId,
                    streams: result.streams.filter { !$0.playable },
                    error: result.error
                )
            }
            .filter { !$0.streams.isEmpty }
    }

    /// True once any addon has returned a playable stream.
    var hasPlayableResults: Bool {
        groupedResults.contains { $0.streams.contains(where: \.playable) }
    }

    /// Loads once per page; returning from the player keeps the list.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
        if !Task.isCancelled {
            hasLoaded = true
        }
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        emptyState = .none

        await service.ensureInitialized(installDefaults: profileSettings.stremioPlaybackEnabled)

        let hasStreamProviders = await service.hasStreamProviders(
            requestType: StremioRequestType(rawValue: destination.identity.requestType)
        )
        guard hasStreamProviders else {
            emptyState = .noAddons
            groupedResults = []
            cachedSource = nil
            isLoading = false
            return
        }

        cachedSource = profileSettings.stremioPreferCachedSourceResume
            ? await streamCache.get(contentKey: contentKey)
            : nil

        let results = await service.getStreamsProgressively(identity: destination.identity) { [weak self] partial in
            await self?.applyPartialResults(partial, generation: generation)
        }
        guard generation == loadGeneration else { return }
        if groupedResults != results {
            groupedResults = results
        }
        isLoading = false

        let allStreams = results.flatMap(\.streams)
        let playable = allStreams.filter(\.playable)
        let unsupported = allStreams.filter { !$0.playable }

        if allStreams.isEmpty {
            emptyState = .noStreams
            return
        }

        if playable.isEmpty, !unsupported.isEmpty {
            emptyState = .unsupportedOnly
            return
        }

        emptyState = .none
    }

    private func applyPartialResults(_ partial: [StremioAddonStreamResult], generation: Int) {
        guard generation == loadGeneration, isLoading else { return }
        groupedResults = partial
    }

    // MARK: - Automatic selection

    enum AutoSelectionOutcome {
        case play(PlayerDestination)
        /// Open the sources page, with an explanation when there is one to give.
        case showSources(notice: String?)
    }

    /// Chooses a stream for an automatic Play without showing the sources page.
    func findAutomaticSource(action: StremioPlayAction) async -> AutoSelectionOutcome {
        await service.ensureInitialized(installDefaults: profileSettings.stremioPlaybackEnabled)

        guard await service.hasStreamProviders(
            requestType: StremioRequestType(rawValue: destination.identity.requestType)
        ) else {
            return .showSources(notice: nil)
        }

        if let resumed = await cachedResumeDestination() {
            return .play(resumed)
        }

        let defaults = UserDefaults.standard
        let addonOrder = action == .addonOrder ? await service.getInstalledAddons().map(\.installationId) : nil
        let selector: StreamAutoSelector
        do {
            selector = try StreamAutoSelector(rules: action == .matchRules ? defaults.stremioStreamRules : nil, addonOrder: addonOrder)
        } catch {
            return .showSources(notice: String(localized: "Your source rules have an invalid pattern. Fix it in Settings, or choose a source here."))
        }

        let timeLimit = defaults.stremioAutoPickTimeLimit
        let deadline = Date().addingTimeInterval(TimeInterval(timeLimit))
        let fetched = await service.getStreams(identity: destination.identity, timeLimit: TimeInterval(timeLimit)) { results, pending in
            await selector.shouldStopWaiting(in: results, pending: pending)
        }
        groupedResults = fetched.results

        let picked = await selector.pickOffActor(in: fetched.results)
        if selector.rulesTimedOut {
            return .showSources(notice: String(localized: "Your include pattern took too long to check. Simplify it in Settings, or choose a source here."))
        }
        guard let stream = picked else {
            return .showSources(notice: fallbackNotice(
                results: fetched.results,
                waitedSeconds: fetched.timedOut ? timeLimit : nil
            ))
        }
        guard let playback = await select(stream: stream, saveToCache: true, includeAlertOnFailure: false, subtitleDeadline: deadline) else {
            return .showSources(notice: String(localized: "The chosen source could not be started. Choose another one here."))
        }

        AppLogger.shared.info("[Stremio] Auto-selected source", data: [
            "contentKey": contentKey,
            "action": action.rawValue,
            "addonName": stream.addonName ?? "",
            "timedOut": fetched.timedOut,
        ])
        return .play(playback)
    }

    /// The cached source when this Play is a resume, under the same setting as the
    /// "Resume Cached Source" card on the sources page.
    private func cachedResumeDestination() async -> PlayerDestination? {
        guard profileSettings.stremioPreferCachedSourceResume,
              let cached = await streamCache.get(contentKey: contentKey),
              let resume = await resumeStore.get(contentKey: contentKey),
              resume.positionMs > 0 else { return nil }
        cachedSource = cached
        return await resumeCachedPlayback()
    }

    /// Nil when no addon had anything playable and all answered: the page's empty state explains that.
    private func fallbackNotice(results: [StremioAddonStreamResult], waitedSeconds: Int?) -> String? {
        if results.contains(where: { $0.streams.contains(where: \.playable) }) {
            if let waitedSeconds {
                return String(localized: "No source matched your rules within \(waitedSeconds) seconds. Showing all sources.")
            }
            return String(localized: "No source matched your rules. Showing all sources.")
        }
        guard let waitedSeconds else { return nil }
        return String(localized: "No playable source arrived within \(waitedSeconds) seconds. Showing all sources.")
    }

    var contentKey: String {
        StremioContentResolver.buildContentKey(identity: destination.identity)
    }

    /// - Parameter subtitleDeadline: Stop waiting on subtitle addons at this time.
    func select(
        stream: StremioPlayableStream,
        saveToCache: Bool = true,
        includeAlertOnFailure: Bool = true,
        subtitleDeadline: Date? = nil
    ) async -> PlayerDestination? {
        guard stream.playable, let uri = stream.url else {
            if includeAlertOnFailure {
                alertMessage = stream.disabledReason ?? String(localized: "This stream type is not supported in-app.")
            }
            return nil
        }

        let resumeMs = await resumeStore.get(contentKey: contentKey)?.positionMs
        let externalSubtitles = await mergedExternalSubtitles(for: stream, deadline: subtitleDeadline)
        let playbackItem = StreamPlaybackItem(
            id: "stremio-\(destination.identity.requestId)-\(stream.id)",
            provider: .stremio,
            uri: uri,
            headers: mergedHeaders(for: stream),
            title: displayPlaybackTitle,
            showTitle: destination.mediaType == .episode ? destination.title : nil,
            mediaType: destination.mediaType,
            contentKey: contentKey,
            imdbId: destination.imdbId,
            tmdbId: destination.tmdbId,
            seasonNumber: destination.seasonNumber,
            episodeNumber: destination.episodeNumber,
            episodeTitle: destination.episodeTitle,
            backdropURL: destination.backdropURL,
            posterURL: destination.posterURL,
            streamLabel: streamLabel(for: stream),
            addonId: stream.addonId,
            addonName: stream.addonName,
            availableStreams: groupedResults.flatMap(\.streams).filter(\.playable),
            externalSubtitles: externalSubtitles,
            resumePositionMs: resumeMs
        )

        if saveToCache, profileSettings.useCachedStreams {
            let now = Date()
            let cached = CachedPlaybackSource(
                kind: "stream",
                provider: StreamProvider.stremio.rawValue,
                contentKey: contentKey,
                playbackItem: playbackItem,
                savedAt: now,
                expiresAt: now.addingTimeInterval(TimeInterval(profileSettings.streamCacheTTL))
            )
            await streamCache.save(cached)
        }

        AppLogger.shared.info("[Stremio] Selected source", data: [
            "contentKey": contentKey,
            "streamId": stream.id,
            "addonId": stream.addonId ?? "",
            "addonName": stream.addonName ?? "",
            "uri": uri,
        ])

        return .stream(playbackItem)
    }

    func resumeCachedPlayback() async -> PlayerDestination? {
        guard let cached = cachedSource else { return nil }
        let resumeMs = await resumeStore.get(contentKey: cached.contentKey)?.positionMs
        let playback = StreamPlaybackItem(
            id: cached.playbackItem.id,
            provider: cached.playbackItem.provider,
            uri: cached.playbackItem.uri,
            headers: cached.playbackItem.headers,
            title: cached.playbackItem.title,
            showTitle: cached.playbackItem.showTitle ?? (cached.playbackItem.mediaType == .episode ? destination.title : nil),
            mediaType: cached.playbackItem.mediaType,
            contentKey: cached.playbackItem.contentKey,
            imdbId: cached.playbackItem.imdbId,
            tmdbId: cached.playbackItem.tmdbId,
            seasonNumber: cached.playbackItem.seasonNumber,
            episodeNumber: cached.playbackItem.episodeNumber,
            episodeTitle: cached.playbackItem.episodeTitle,
            backdropURL: cached.playbackItem.backdropURL,
            posterURL: cached.playbackItem.posterURL,
            streamLabel: cached.playbackItem.streamLabel,
            addonId: cached.playbackItem.addonId,
            addonName: cached.playbackItem.addonName,
            availableStreams: cached.playbackItem.availableStreams,
            externalSubtitles: cached.playbackItem.externalSubtitles,
            resumePositionMs: resumeMs ?? cached.playbackItem.resumePositionMs
        )
        return .stream(playback)
    }

    /// Subtitle addon results, or nothing if they don't arrive by `deadline`.
    private func addonSubtitles(deadline: Date?) async -> [StremioSubtitleCandidate] {
        let service = self.service
        let identity = destination.identity
        guard let deadline else { return await service.getSubtitles(identity: identity) }

        let wait = deadline.timeIntervalSinceNow
        guard wait > 0 else { return [] }
        // Returns at the deadline even if a subtitle addon is slow to give up.
        let fetch = Task { await service.getSubtitles(identity: identity) }
        guard let subtitles = await awaitResult(of: fetch, within: wait) else {
            fetch.cancel()
            return []
        }
        return subtitles
    }

    private func mergedExternalSubtitles(for stream: StremioPlayableStream, deadline: Date?) async -> [StremioSubtitleCandidate] {
        var subtitles: [StremioSubtitleCandidate] = stream.subtitles ?? []
        if profileSettings.stremioSubtitleAddonsEnabled {
            let fetched = await addonSubtitles(deadline: deadline)
            subtitles.append(contentsOf: fetched)
        }

        var deduped: [String: StremioSubtitleCandidate] = [:]
        for subtitle in subtitles {
            deduped[subtitle.url] = subtitle
        }
        return Array(deduped.values).sorted {
            $0.lang.localizedCaseInsensitiveCompare($1.lang) == .orderedAscending
        }
    }

    private var displayPlaybackTitle: String {
        if destination.mediaType == .episode {
            return destination.episodeTitle ?? destination.title
        }
        return destination.title
    }

    private func streamLabel(for stream: StremioPlayableStream) -> String {
        stream.title ?? stream.name ?? stream.description ?? String(localized: "Stremio Source")
    }

    private func mergedHeaders(for stream: StremioPlayableStream) -> [HTTPHeaderField] {
        var headers = stream.headers ?? [:]
        let proxyHeaders = stream.behaviorHints?.proxyHeaders?.request ?? [:]
        for (key, value) in proxyHeaders {
            headers[key] = value
        }

        return headers.keys.sorted().map { key in
            HTTPHeaderField(name: key, value: headers[key] ?? "")
        }
    }
}
