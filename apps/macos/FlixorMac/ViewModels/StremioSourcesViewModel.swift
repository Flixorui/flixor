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
    @Published var autoPlayDestination: PlayerDestination?

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
        autoPlayDestination = nil

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

        if profileSettings.stremioAutoPlayBestSource,
           let best = bestPlayableStream(in: results),
           let destination = await select(stream: best, saveToCache: true, includeAlertOnFailure: false) {
            autoPlayDestination = destination
        }
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

    private func bestPlayableStream(in results: [StremioAddonStreamResult]) -> StremioPlayableStream? {
        let grouped = results.flatMap(\.streams).filter(\.playable)
        return grouped.max { lhs, rhs in
            score(for: lhs) < score(for: rhs)
        }
    }

    private func score(for stream: StremioPlayableStream) -> Int {
        var score = 0
        if stream.playable { score += 1_000_000 }
        if stream.behaviorHints?.cached == true { score += 100_000 }
        if stream.isDebrid == true { score += 50_000 }
        score += qualityScore(stream.quality)
        score += min((stream.size ?? 0) / 1_000_000, 9_999)

        if let groupIndex = groupedResults.firstIndex(where: { $0.installationId == stream.addonInstallationId }) {
            score += max(0, 1_000 - groupIndex)
        }

        score += max(0, 500 - stream.streamIndex)
        return score
    }

    private func qualityScore(_ quality: String?) -> Int {
        guard let quality = quality?.lowercased() else { return 0 }
        if quality.contains("2160") || quality.contains("4k") { return 20_000 }
        if quality.contains("1080") { return 15_000 }
        if quality.contains("720") { return 10_000 }
        if quality.contains("480") { return 5_000 }
        return 0
    }
}
