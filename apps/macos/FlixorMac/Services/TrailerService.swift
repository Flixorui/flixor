//
//  TrailerService.swift
//  FlixorMac
//
//  Finds trailers for a movie or show and returns the existing `Trailer`
//  model so TrailersRow / TrailerModal can show them directly:
//  - Apple TV trailers from MyBluray first, when a key is set up and "Apple TV
//    trailers first" is on. They are direct HLS streams that AVPlayer plays in
//    up to 4K HDR, with no YouTube involved.
//  - YouTube trailers from TMDB videos after them, the same source
//    DetailsViewModel.loadTMDBTrailers uses. They are also each Apple
//    trailer's fallback if its stream fails.
//
//  Results are cached in memory for the session and concurrent requests for the
//  same title share one fetch.
//

import Foundation
import FlixorKit

actor TrailerService {
    static let shared = TrailerService()

    private var cache: [String: [Trailer]] = [:]
    private var inFlight: [String: Task<(trailers: [Trailer], cacheable: Bool)?, Never>] = [:]
    private let maxResults = 20

    /// How long hover and hero playback wait for MyBluray before going ahead
    /// with YouTube. A title the server hasn't stored can take 9 s; the lookup
    /// keeps running and is saved, so the next time it is instant.
    private static let appleWaitSeconds: Double = 4

    // MARK: - Public API

    /// Ranked trailers for an item (best first). Episodes and seasons use
    /// their show. Empty when nothing is found or the id can't be resolved.
    func trailers(for item: MediaItem) async -> [Trailer] {
        guard let identity = await MediaIdentityResolver.shared.tmdbIdentity(for: item) else { return [] }
        return await trailers(tmdbId: identity.id, mediaType: identity.mediaType)
    }

    /// Ranked trailers for a TMDB movie or show (best first): Apple TV, then YouTube.
    func trailers(tmdbId: Int, mediaType: TMDBMediaType) async -> [Trailer] {
        let defaults = UserDefaults.standard
        let useApple = defaults.myblurayOptionActive(.appleTrailers)
        let bonus = useApple && defaults.myblurayOptionActive(.bonusVideos)
        let key = "\(mediaType.rawValue):\(tmdbId):\(useApple ? (bonus ? "apple+bonus" : "apple") : "youtube")"
        if let cached = cache[key] { return cached }

        let task: Task<(trailers: [Trailer], cacheable: Bool)?, Never>
        let ownsTask: Bool
        if let existing = inFlight[key] {
            task = existing
            ownsTask = false
        } else {
            let limit = maxResults
            task = Task {
                async let youtube = Self.fetch(tmdbId: tmdbId, mediaType: mediaType, limit: limit)
                async let apple: [Trailer]? = useApple
                    ? Self.withTimeout(Self.appleWaitSeconds) {
                        await Self.appleTrailers(tmdbId: tmdbId, mediaType: mediaType, includeBonus: bonus)
                    }
                    : []
                let (youtubeResult, appleResult) = await (youtube, apple)
                // nil = TMDB failed and Apple had nothing: don't pin that for the session.
                let direct = appleResult ?? []
                if youtubeResult == nil && direct.isEmpty { return nil }
                let merged = Self.merge(apple: direct, youtube: youtubeResult ?? [])
                // Keep a result that waited out MyBluray uncached, so the
                // next call picks up the saved Apple trailers.
                let complete = youtubeResult != nil && appleResult != nil
                return (Array(merged.prefix(limit)), complete)
            }
            inFlight[key] = task
            ownsTask = true
        }

        let result = await task.value
        if ownsTask { inFlight[key] = nil }
        guard let result else { return [] }
        if result.cacheable { cache[key] = result.trailers }
        return result.trailers
    }

    /// The best trailer for an item, if any.
    func bestTrailer(for item: MediaItem) async -> Trailer? {
        await trailers(for: item).first
    }

    /// The best trailer for a TMDB movie or show, if any.
    func bestTrailer(tmdbId: Int, mediaType: TMDBMediaType) async -> Trailer? {
        await trailers(tmdbId: tmdbId, mediaType: mediaType).first
    }

    /// YouTube key of the best YouTube trailer for an item, if any.
    func bestTrailerKey(for item: MediaItem) async -> String? {
        await trailers(for: item).first(where: { !$0.isDirect })?.key
    }

    /// YouTube key of the best YouTube trailer for a TMDB movie or show, if any.
    func bestTrailerKey(tmdbId: Int, mediaType: TMDBMediaType) async -> String? {
        await trailers(tmdbId: tmdbId, mediaType: mediaType).first(where: { !$0.isDirect })?.key
    }

    // MARK: - Apple TV (MyBluray)

    /// Apple TV trailers for a title when MyBluray is set up for them, without
    /// a time limit. Empty when it's off or Apple has none.
    func appleTrailers(tmdbId: Int, mediaType: TMDBMediaType) async -> [Trailer] {
        let defaults = UserDefaults.standard
        guard defaults.myblurayOptionActive(.appleTrailers) else { return [] }
        return await Self.appleTrailers(tmdbId: tmdbId, mediaType: mediaType,
                                        includeBonus: defaults.myblurayOptionActive(.bonusVideos))
    }

    /// Puts Apple trailers ahead of YouTube ones and gives each Apple trailer
    /// the best YouTube trailer as its fallback.
    static func merge(apple: [Trailer], youtube: [Trailer]) -> [Trailer] {
        let fallback = youtube.first?.key
        return apple.map { trailer in
            var copy = trailer
            copy.fallbackYouTubeKey = fallback
            return copy
        } + youtube
    }

    private static func appleTrailers(tmdbId: Int, mediaType: TMDBMediaType, includeBonus: Bool) async -> [Trailer] {
        guard let imdbId = await MediaIdentityResolver.shared.imdbId(tmdbId: tmdbId, isShow: mediaType == .tv) else {
            return []
        }
        let title: MBTitle?
        do {
            title = try await MyBlurayService.shared.title(imdbId: imdbId, allVideos: includeBonus)
        } catch {
            AppLogger.shared.debug("[Trailers] MyBluray unavailable", data: ["imdbId": imdbId, "error": "\(error)"])
            return []
        }
        guard let title else { return [] }

        let trailers = title.directAppleVideos.compactMap { video -> (rank: Int, trailer: Trailer)? in
            guard let raw = video.playbackUrl, let url = URL(string: raw) else { return nil }
            let kind = (video.kind ?? "trailer").lowercased()
            let label = (video.title ?? "").trimmingCharacters(in: .whitespaces)
            // Apple names some trailers after the film, and labels some teasers as trailers.
            let type = label.lowercased() == "teaser" ? "Teaser" : kind.capitalized
            let rank = typeRank(type)
            guard includeBonus || rank <= 1 else { return nil }
            let name = label.isEmpty || label.caseInsensitiveCompare(title.title ?? "") == .orderedSame ? type : label
            let id = video.providerId ?? raw
            return (rank, Trailer(
                id: "apple:\(id)",
                name: name,
                key: id,
                site: "Apple TV",
                type: type,
                official: true,
                publishedAt: nil,
                streamURL: url,
                imageURL: video.thumbnailUrl.flatMap(URL.init(string:)),
                durationSeconds: video.durationSeconds
            ))
        }
        // Trailers before teasers before bonus videos; Apple's order within each.
        return trailers.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map(\.element.trailer)
    }

    /// Runs `operation` and returns its result, or nil once `seconds` pass. The
    /// operation isn't cancelled, so work it started (and caches) finishes.
    private static func withTimeout<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
        let once = TrailerTimeoutGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            Task {
                let value = await operation()
                if once.claim() { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if once.claim() { continuation.resume(returning: nil) }
            }
        }
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

/// Lets exactly one of two racing tasks resume a continuation.
private final class TrailerTimeoutGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
