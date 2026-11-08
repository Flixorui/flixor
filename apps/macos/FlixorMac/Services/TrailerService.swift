//
//  TrailerService.swift
//  FlixorMac
//
//  Finds YouTube trailers for a movie or show from TMDB videos, the same source
//  DetailsViewModel.loadTMDBTrailers uses, and returns the existing `Trailer`
//  model so TrailersRow / TrailerModal can show them directly.
//
//  Results are cached in memory for the session and concurrent requests for the
//  same title share one fetch.
//

import Foundation
import FlixorKit

actor TrailerService {
    static let shared = TrailerService()

    private var cache: [String: [Trailer]] = [:]
    private var inFlight: [String: Task<[Trailer]?, Never>] = [:]
    private let maxResults = 20

    // MARK: - Public API

    /// Ranked YouTube videos for an item (best first). Episodes and seasons use
    /// their show. Empty when nothing is found or the id can't be resolved.
    func trailers(for item: MediaItem) async -> [Trailer] {
        guard let identity = await MediaIdentityResolver.shared.tmdbIdentity(for: item) else { return [] }
        return await trailers(tmdbId: identity.id, mediaType: identity.mediaType)
    }

    /// Ranked YouTube videos for a TMDB movie or show (best first).
    func trailers(tmdbId: Int, mediaType: TMDBMediaType) async -> [Trailer] {
        let key = "\(mediaType.rawValue):\(tmdbId)"
        if let cached = cache[key] { return cached }

        let task: Task<[Trailer]?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            let limit = maxResults
            task = Task { await Self.fetch(tmdbId: tmdbId, mediaType: mediaType, limit: limit) }
            inFlight[key] = task
        }

        let result = await task.value
        inFlight[key] = nil
        // nil = the request failed: don't pin that for the session, let a later call retry.
        guard let result else { return [] }
        cache[key] = result
        return result
    }

    /// YouTube key of the best trailer for an item, if any.
    func bestTrailerKey(for item: MediaItem) async -> String? {
        await trailers(for: item).first?.key
    }

    /// YouTube key of the best trailer for a TMDB movie or show, if any.
    func bestTrailerKey(tmdbId: Int, mediaType: TMDBMediaType) async -> String? {
        await trailers(tmdbId: tmdbId, mediaType: mediaType).first?.key
    }

    /// Drops cached results (e.g. after the TMDB language changes).
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Fetch & Rank

    /// Nil when TMDB couldn't be reached (so the empty result isn't cached).
    private static func fetch(tmdbId: Int, mediaType: TMDBMediaType, limit: Int) async -> [Trailer]? {
        let tmdb = await FlixorCore.shared.tmdb
        let isMovie = mediaType == .movie

        var videos: [FlixorKit.TMDBVideo] = []
        var localizedFailed = false
        do {
            let localized = isMovie
                ? try await tmdb.getMovieVideos(id: tmdbId)
                : try await tmdb.getTVVideos(id: tmdbId)
            videos = localized.results
        } catch {
            AppLogger.shared.warn("[Trailers] TMDB videos failed", data: [
                "tmdbId": tmdbId, "media": mediaType.rawValue, "error": error.localizedDescription,
            ])
            localizedFailed = true
        }

        // Many non-English titles only have trailers outside the UI language.
        if !videos.contains(where: { isYouTube($0) && typeRank($0.type) <= 1 }) {
            if let all = try? await (isMovie
                ? tmdb.getMovieVideosAllLanguages(id: tmdbId)
                : tmdb.getTVVideosAllLanguages(id: tmdbId)) {
                let seen = Set(videos.compactMap(\.key))
                videos += all.results.filter { !seen.contains($0.key ?? "") }
            } else if localizedFailed {
                return nil
            }
        }

        let ranked = videos
            .filter(isYouTube)
            .enumerated()
            .sorted { lhs, rhs in isRankedBefore(lhs.element, lhs.offset, rhs.element, rhs.offset) }
            .map(\.element)

        var seenKeys = Set<String>()
        return ranked.compactMap { video -> Trailer? in
            guard let key = video.key, seenKeys.insert(key).inserted else { return nil }
            return Trailer(
                id: video.id,
                name: video.name ?? "Video",
                key: key,
                site: video.site ?? "YouTube",
                type: video.type ?? "Video",
                official: video.official,
                publishedAt: video.publishedAt
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func isYouTube(_ video: FlixorKit.TMDBVideo) -> Bool {
        (video.site?.lowercased() ?? "") == "youtube" && !(video.key ?? "").isEmpty
    }

    /// Trailer < Teaser < Clip < Featurette < Behind the Scenes < anything else.
    private static func typeRank(_ type: String?) -> Int {
        switch (type ?? "").lowercased() {
        case "trailer": return 0
        case "teaser": return 1
        case "clip": return 2
        case "featurette": return 3
        case "behind the scenes": return 4
        default: return 5
        }
    }

    /// Order: type rank, official first, names that say "official trailer", newest,
    /// then TMDB order (offset; localized results come before all-language ones).
    private static func isRankedBefore(_ a: FlixorKit.TMDBVideo, _ aIndex: Int, _ b: FlixorKit.TMDBVideo, _ bIndex: Int) -> Bool {
        let ta = typeRank(a.type), tb = typeRank(b.type)
        if ta != tb { return ta < tb }
        let oa = a.official ?? false, ob = b.official ?? false
        if oa != ob { return oa }
        let na = (a.name ?? "").lowercased().contains("official trailer")
        let nb = (b.name ?? "").lowercased().contains("official trailer")
        if na != nb { return na }
        let pa = a.publishedAt ?? "", pb = b.publishedAt ?? ""
        if pa != pb { return pa > pb }
        return aIndex < bIndex
    }
}
