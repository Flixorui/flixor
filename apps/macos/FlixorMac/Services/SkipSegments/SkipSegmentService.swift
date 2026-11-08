//
//  SkipSegmentService.swift
//  FlixorMac
//
//  Looks up community skip segments for items without Plex markers.
//  Sources, in priority order: IntroDB (IMDb id + season/episode, also movies),
//  AniSkip (MyAnimeList id), Anime-Skip (AniList id, only with a user client id).
//  Results are merged per segment type (first provider wins) and cached per
//  movie / episode for the session. Every failure degrades to "no segments".
//

import Foundation

actor SkipSegmentService {
    static let shared = SkipSegmentService()

    private struct CacheEntry {
        let segments: [SkipSegment]
        let expiresAt: Date
    }

    private let introDB = IntroDBClient()
    private let aniSkip = AniSkipClient()
    private let idMapper = AnimeIdMappingClient()

    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<[SkipSegment], Never>] = [:]
    /// Anime ids per show/season or per anime-db id. `nil` value = known not anime.
    private var animeIdCache: [String: AnimeIds?] = [:]
    private var animeSkipShowIds: [String: [String]] = [:]
    /// Providers that answered 429, and until when we leave them alone.
    private var blockedUntil: [SkipSegmentProvider: Date] = [:]

    private let foundTTL: TimeInterval = 6 * 3600
    private let emptyTTL: TimeInterval = 30 * 60

    /// Merged segments for one movie or episode (empty when nothing is known).
    func segments(for request: SkipSegmentRequest) async -> [SkipSegment] {
        guard request.isLookupPossible else { return [] }
        let key = request.cacheKey
        if let entry = cache[key], entry.expiresAt > Date() {
            return entry.segments
        }
        if let running = inFlight[key] {
            return await running.value
        }
        let task = Task { await self.fetch(request) }
        inFlight[key] = task
        let segments = await task.value
        inFlight[key] = nil
        cache[key] = CacheEntry(
            segments: segments,
            expiresAt: Date().addingTimeInterval(segments.isEmpty ? emptyTTL : foundTTL)
        )
        if !segments.isEmpty {
            AppLogger.shared.info("[SkipSegments] Found community segments", data: [
                "key": key,
                "segments": segments.map { "\($0.type.rawValue)@\(Int($0.start))s(\($0.provider.rawValue))" },
            ])
        }
        return segments
    }

    func clearCache() {
        cache.removeAll()
        animeIdCache.removeAll()
        animeSkipShowIds.removeAll()
    }

    // MARK: - Fetch

    private func fetch(_ request: SkipSegmentRequest) async -> [SkipSegment] {
        if request.isMovie {
            guard let imdbId = request.imdbId else { return [] }
            let segments = await guarded(.introDB) { try await self.introDB.movieSegments(imdbId: imdbId) }
            return Self.merge([segments])
        }

        guard let episode = request.episode else { return [] }

        async let introDBSegments: [SkipSegment] = fetchIntroDB(request)
        let animeIds = await resolveAnimeIds(request)

        async let aniSkipSegments: [SkipSegment] = fetchAniSkip(malId: animeIds?.malId, episode: episode)
        async let animeSkipSegments: [SkipSegment] = fetchAnimeSkip(
            anilistId: animeIds?.anilistId,
            episode: episode,
            clientId: request.animeSkipClientId
        )

        return Self.merge([await introDBSegments, await aniSkipSegments, await animeSkipSegments])
    }

    private func fetchIntroDB(_ request: SkipSegmentRequest) async -> [SkipSegment] {
        guard let imdbId = request.imdbId, let season = request.season, let episode = request.episode,
              request.kitsuId == nil, request.malId == nil else { return [] }
        return await guarded(.introDB) {
            try await self.introDB.episodeSegments(imdbId: imdbId, season: season, episode: episode)
        }
    }

    private func fetchAniSkip(malId: String?, episode: Int) async -> [SkipSegment] {
        guard let malId else { return [] }
        return await guarded(.aniSkip) { try await self.aniSkip.segments(malId: malId, episode: episode) }
    }

    private func fetchAnimeSkip(anilistId: String?, episode: Int, clientId: String) async -> [SkipSegment] {
        let clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let anilistId, !clientId.isEmpty else { return [] }
        let client = AnimeSkipClient(clientId: clientId)
        return await guarded(.animeSkip) {
            let showIds: [String]
            if let cached = self.animeSkipShowIds[anilistId] {
                showIds = cached
            } else {
                showIds = try await client.showIds(anilistId: anilistId)
                self.animeSkipShowIds[anilistId] = showIds
            }
            for showId in showIds.prefix(3) {
                let segments = try await client.segments(showId: showId, episode: episode)
                if !segments.isEmpty { return segments }
            }
            return []
        }
    }

    /// MAL/AniList ids for the request, cached per show+season (or anime-db id).
    private func resolveAnimeIds(_ request: SkipSegmentRequest) async -> AnimeIds? {
        let key: String
        if let malId = request.malId {
            key = "mal:\(malId)"
        } else if let kitsuId = request.kitsuId {
            key = "kitsu:\(kitsuId)"
        } else {
            key = "show:\(request.tmdbId.map(String.init) ?? request.imdbId ?? "?"):\(request.season ?? 0)"
        }
        if let cached = animeIdCache[key] { return cached }

        let ids: AnimeIds?
        do {
            if let malId = request.malId {
                // MAL id given: still ask ARM for the AniList id, but MAL alone is enough for AniSkip.
                ids = (try? await idMapper.ids(source: "myanimelist", id: malId)) ?? AnimeIds(malId: malId, anilistId: nil)
            } else if let kitsuId = request.kitsuId {
                ids = try await idMapper.ids(source: "kitsu", id: kitsuId)
            } else if let season = request.season {
                ids = try await idMapper.idsForShow(tmdbId: request.tmdbId, imdbId: request.imdbId, season: season)
            } else {
                ids = nil
            }
        } catch {
            // Transient failure: don't cache, try again next episode.
            return nil
        }
        animeIdCache[key] = .some(ids)
        return ids
    }

    /// Runs one provider call; maps errors (including 429 back-off) to an empty result.
    private func guarded(
        _ provider: SkipSegmentProvider,
        _ operation: () async throws -> [SkipSegment]
    ) async -> [SkipSegment] {
        if let until = blockedUntil[provider], until > Date() { return [] }
        do {
            return try await operation()
        } catch SkipSegmentHTTPError.rateLimited(let retryAfter) {
            let until = min(retryAfter ?? Date().addingTimeInterval(60), Date().addingTimeInterval(15 * 60))
            blockedUntil[provider] = until
            AppLogger.shared.warn("[SkipSegments] Rate limited", data: ["provider": provider.rawValue])
            return []
        } catch {
            if !(error is CancellationError) {
                AppLogger.shared.debug("[SkipSegments] Lookup failed", data: [
                    "provider": provider.rawValue,
                    "error": error.localizedDescription,
                ])
            }
            return []
        }
    }

    // MARK: - Merge

    /// One segment per type, first list wins (lists are passed in priority order).
    /// Credits are trimmed so skipping them never jumps over a post-credits scene.
    static func merge(_ lists: [[SkipSegment]]) -> [SkipSegment] {
        var chosen: [SkipSegmentType: SkipSegment] = [:]
        for list in lists {
            for segment in list where segment.isValid && chosen[segment.type] == nil {
                chosen[segment.type] = segment
            }
        }
        if let credits = chosen[.credits], let scene = chosen[.postCredits],
           scene.start >= credits.start, scene.start < (credits.end ?? .greatestFiniteMagnitude) {
            let trimmed = SkipSegment(type: .credits, start: credits.start, end: scene.start, provider: credits.provider)
            chosen[.credits] = trimmed.isValid ? trimmed : nil
        }
        return chosen.values.sorted { $0.start < $1.start }
    }
}
