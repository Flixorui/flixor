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
                return "No stream-capable addons installed"
            case .noStreams:
                return "No streams found"
            case .unsupportedOnly:
                return "Only unsupported sources were returned"
            case .error:
                return "Failed to load Stremio sources"
            }
        }

        var message: String {
            switch self {
            case .none:
                return ""
            case .noAddons:
                return "Install at least one Stremio addon that provides streams for this title."
            case .noStreams:
                return "Installed addons responded, but none returned playable sources for this request."
            case .unsupportedOnly:
                return "The installed addons only returned source types that cannot be played in-app on macOS yet."
            case .error(let message):
                return message
            }
        }
    }

    @Published var isLoading = false
    @Published var groupedResults: [StremioAddonStreamResult] = []
    @Published var selectedProviderFilter = "all"
    @Published var emptyState: EmptyState = .none
    @Published var cachedSource: CachedPlaybackSource?
    @Published var alertMessage: String?

    let destination: StremioSourcesDestination

    private let profileSettings = ProfileSettings.shared
    private let service = StremioService.shared
    private let streamCache = StremioStreamCache.shared
    private let resumeStore = StremioResumeStore.shared

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

    func load() async {
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

        let results = await service.getStreams(identity: destination.identity)
        groupedResults = results
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
        let selector: StreamAutoSelector
        do {
            selector = try StreamAutoSelector(rules: action == .matchRules ? defaults.stremioStreamRules : nil)
        } catch {
            return .showSources(notice: "Your source rules have an invalid pattern. Fix it in Settings, or choose a source here.")
        }

        let timeLimit = defaults.stremioAutoPickTimeLimit
        let fetched = await service.getStreams(identity: destination.identity, timeLimit: TimeInterval(timeLimit)) { results, pending in
            selector.earlyPick(in: results, pending: pending) != nil
        }
        groupedResults = fetched.results

        guard let stream = selector.pick(in: fetched.results) else {
            return .showSources(notice: fallbackNotice(
                results: fetched.results,
                waitedSeconds: fetched.timedOut ? timeLimit : nil
            ))
        }
        guard let playback = await select(stream: stream, saveToCache: true, includeAlertOnFailure: false) else {
            return .showSources(notice: "The chosen source could not be started. Choose another one here.")
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
        let within = waitedSeconds.map { " within \($0) seconds" } ?? ""
        if results.contains(where: { $0.streams.contains(where: \.playable) }) {
            return "No source matched your rules\(within). Showing all sources."
        }
        return waitedSeconds == nil ? nil : "No playable source arrived\(within). Showing all sources."
    }

    var contentKey: String {
        StremioContentResolver.buildContentKey(identity: destination.identity)
    }

    func select(stream: StremioPlayableStream, saveToCache: Bool = true, includeAlertOnFailure: Bool = true) async -> PlayerDestination? {
        guard stream.playable, let uri = stream.url else {
            if includeAlertOnFailure {
                alertMessage = stream.disabledReason ?? "This stream type is not supported in-app."
            }
            return nil
        }

        let resumeMs = await resumeStore.get(contentKey: contentKey)?.positionMs
        let externalSubtitles = await mergedExternalSubtitles(for: stream)
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

    private func mergedExternalSubtitles(for stream: StremioPlayableStream) async -> [StremioSubtitleCandidate] {
        var subtitles: [StremioSubtitleCandidate] = stream.subtitles ?? []
        if profileSettings.stremioSubtitleAddonsEnabled {
            let fetched = await service.getSubtitles(identity: destination.identity)
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
        stream.title ?? stream.name ?? stream.description ?? "Stremio Source"
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
