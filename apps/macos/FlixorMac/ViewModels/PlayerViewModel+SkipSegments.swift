//
//  PlayerViewModel+SkipSegments.swift
//  FlixorMac
//
//  Community skip segments (IntroDB / AniSkip / Anime-Skip) for addon streams and
//  Plex items without markers, fed into the existing `markers` pipeline so the
//  skip button, auto-skip countdown and credits-based next-episode trigger work.
//

import Foundation

extension PlayerViewModel {
    // MARK: - Lookup

    /// Starts a background lookup for an addon stream (movie or episode).
    func loadCommunitySkipSegments(for streamItem: StreamPlaybackItem) {
        guard UserDefaults.standard.communitySkipSegmentsEnabled else { return }
        let contentKey = streamItem.contentKey
        let clientId = UserDefaults.standard.animeSkipClientId

        skipSegmentsTask?.cancel()
        skipSegmentsTask = Task { [weak self] in
            guard let request = await Self.skipSegmentRequest(for: streamItem, animeSkipClientId: clientId) else { return }
            let segments = await SkipSegmentService.shared.segments(for: request)
            guard !Task.isCancelled, let self, self.streamPlaybackItem?.contentKey == contentKey else { return }
            self.applyCommunitySkipSegments(segments)
        }
    }

    /// Starts a background lookup for a Plex item. Only runs when Plex returned
    /// no intro or no credits marker; community data then fills the missing types.
    func loadCommunitySkipSegmentsForPlexIfNeeded(ratingKey: String) {
        guard sourceKind == .plex, UserDefaults.standard.communitySkipSegmentsEnabled else { return }
        let plexTypes = Set(plexMarkersSnapshot.compactMap(\.segmentType))
        guard !(plexTypes.contains(.intro) && plexTypes.contains(.credits)) else { return }
        let clientId = UserDefaults.standard.animeSkipClientId
        let itemId = item.id

        skipSegmentsTask?.cancel()
        skipSegmentsTask = Task { [weak self] in
            guard let request = await Self.skipSegmentRequest(plexRatingKey: ratingKey, animeSkipClientId: clientId) else { return }
            let segments = await SkipSegmentService.shared.segments(for: request)
            guard !Task.isCancelled, let self, self.item.id == itemId else { return }
            self.applyCommunitySkipSegments(segments)
        }
    }

    func applyCommunitySkipSegments(_ segments: [SkipSegment]) {
        communitySkipSegments = segments
        rebuildMarkersFromSources()
        if !segments.isEmpty {
            print("🎬 [Player] Community skip segments: \(segments.map { "\($0.type.rawValue) \(Int($0.start))-\($0.end.map { String(Int($0)) } ?? "end")s via \($0.provider.displayName)" })")
        }
    }

    /// Clears community data (new title).
    func resetCommunitySkipSegments() {
        skipSegmentsTask?.cancel()
        skipSegmentsTask = nil
        communitySkipSegments = []
        communityMarkersAwaitDuration = false
    }

    // MARK: - Markers

    /// `markers` = Plex markers + community segments for types Plex didn't provide.
    func rebuildMarkersFromSources() {
        let plexTypes = Set(plexMarkersSnapshot.compactMap(\.segmentType))
        var result = plexMarkersSnapshot
        var awaitingDuration = false
        for segment in communitySkipSegments where !plexTypes.contains(segment.type) {
            if let marker = PlayerMarker(segment: segment, durationSeconds: duration) {
                result.append(marker)
            } else if segment.end == nil {
                awaitingDuration = true
            }
        }
        communityMarkersAwaitDuration = awaitingDuration
        markers = result.sorted { $0.startTimeOffset < $1.startTimeOffset }
    }

    /// Called on time updates: open-ended segments need the duration first.
    func refreshCommunityMarkersIfNeeded() {
        guard communityMarkersAwaitDuration, duration > 0 else { return }
        rebuildMarkersFromSources()
    }

    // MARK: - Requests

    private static func skipSegmentRequest(for streamItem: StreamPlaybackItem, animeSkipClientId: String) async -> SkipSegmentRequest? {
        if let series = StreamSeriesRef(item: streamItem) {
            var imdbId = series.imdbId
            if imdbId == nil, series.kitsuId == nil, series.malId == nil, let tmdbId = series.tmdbId {
                imdbId = await MediaIdentityResolver.shared.imdbId(tmdbId: tmdbId, isShow: true)
            }
            return SkipSegmentRequest(
                imdbId: imdbId,
                tmdbId: series.tmdbId,
                isMovie: false,
                season: series.season,
                episode: series.episode,
                kitsuId: series.kitsuId,
                malId: series.malId,
                animeSkipClientId: animeSkipClientId
            )
        }

        guard streamItem.mediaType == .movie else { return nil }
        let baseId = streamItem.contentKey.hasPrefix("movie:") ? String(streamItem.contentKey.dropFirst(6)) : ""
        var imdbId = streamItem.imdbId ?? (baseId.hasPrefix("tt") ? baseId : nil)
        let tmdbId = streamItem.tmdbId ?? (baseId.hasPrefix("tmdb:") ? Int(baseId.dropFirst(5)) : nil)
        if imdbId == nil, let tmdbId {
            imdbId = await MediaIdentityResolver.shared.imdbId(tmdbId: tmdbId, isShow: false)
        }
        guard let imdbId else { return nil }
        return SkipSegmentRequest(imdbId: imdbId, tmdbId: tmdbId, isMovie: true, animeSkipClientId: animeSkipClientId)
    }

    private static func skipSegmentRequest(plexRatingKey: String, animeSkipClientId: String) async -> SkipSegmentRequest? {
        let resolver = MediaIdentityResolver.shared
        guard let context = await resolver.plexContext(ratingKey: plexRatingKey) else { return nil }
        switch context.type {
        case "episode":
            guard let season = context.parentIndex, let episode = context.index,
                  let showIds = await resolver.titleIds(plexRatingKey: plexRatingKey) else { return nil }
            var imdbId = showIds.imdbId
            if imdbId == nil, let tmdbId = showIds.tmdbId {
                imdbId = await resolver.imdbId(tmdbId: tmdbId, isShow: true)
            }
            return SkipSegmentRequest(
                imdbId: imdbId,
                tmdbId: showIds.tmdbId,
                isMovie: false,
                season: season,
                episode: episode,
                animeSkipClientId: animeSkipClientId
            )
        case "movie":
            var imdbId = context.ids.imdbId
            if imdbId == nil, let tmdbId = context.ids.tmdbId {
                imdbId = await resolver.imdbId(tmdbId: tmdbId, isShow: false)
            }
            guard let imdbId else { return nil }
            return SkipSegmentRequest(imdbId: imdbId, tmdbId: context.ids.tmdbId, isMovie: true, animeSkipClientId: animeSkipClientId)
        default:
            return nil
        }
    }
}
