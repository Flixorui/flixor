//
//  EpisodeRatingsService.swift
//  FlixorMac
//
//  Per-episode ratings for a show (e.g. a season heatmap or a rating badge on
//  each episode row).
//
//  Source: TMDB episode `vote_average` (0-10) from the season endpoints. Nuvio
//  reads IMDb episode ratings from two self-hosted endpoints whose base URLs come
//  from private build config, not a free public API, so they aren't used here.
//  Episodes with no votes are omitted.
//

import Foundation
import FlixorKit

struct EpisodeRating: Hashable, Identifiable {
    var id: EpisodeNumber { EpisodeNumber(season: season, episode: episode) }
    let season: Int
    let episode: Int
    /// 0-10 (TMDB vote average).
    let rating: Double
    let title: String?
}

actor EpisodeRatingsService {
    static let shared = EpisodeRatingsService()

    private struct Entry {
        let ratings: [EpisodeRating]
        let fetchedAt: Date
    }

    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<[EpisodeRating]?, Never>] = [:]
    private let ttl: TimeInterval = 30 * 60

    /// Ratings for one season, ordered by episode number.
    func ratings(tmdbShowId: Int, season: Int) async -> [EpisodeRating] {
        let key = "\(tmdbShowId):\(season)"
        if let entry = cache[key], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.ratings
        }

        let task: Task<[EpisodeRating]?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            task = Task { await Self.fetch(tmdbShowId: tmdbShowId, season: season) }
            inFlight[key] = task
        }
        let result = await task.value
        inFlight[key] = nil
        guard let result else { return [] }
        cache[key] = Entry(ratings: result, fetchedAt: Date())
        return result
    }

    /// Ratings for several seasons (all regular seasons when `seasons` is nil),
    /// keyed by season/episode. Seasons are fetched in parallel.
    func ratings(tmdbShowId: Int, seasons: [Int]? = nil) async -> [EpisodeNumber: EpisodeRating] {
        var seasonNumbers = seasons ?? []
        if seasons == nil {
            guard let details = try? await FlixorCore.shared.tmdb.getTVDetails(id: tmdbShowId) else { return [:] }
            seasonNumbers = details.seasons.compactMap(\.seasonNumber).filter { $0 > 0 }
        }

        var all: [EpisodeNumber: EpisodeRating] = [:]
        await withTaskGroup(of: [EpisodeRating].self) { group in
            for season in seasonNumbers {
                group.addTask { await self.ratings(tmdbShowId: tmdbShowId, season: season) }
            }
            for await list in group {
                for rating in list { all[rating.id] = rating }
            }
        }
        return all
    }

    /// Same as above for a show known only by IMDb id.
    func ratings(imdbShowId: String, seasons: [Int]? = nil) async -> [EpisodeNumber: EpisodeRating] {
        guard let tmdb = await MediaIdentityResolver.shared.tmdbId(imdbId: imdbShowId, isShow: true) else { return [:] }
        return await ratings(tmdbShowId: tmdb, seasons: seasons)
    }

    private static func fetch(tmdbShowId: Int, season: Int) async -> [EpisodeRating]? {
        do {
            let details = try await FlixorCore.shared.tmdb.getSeasonDetails(tvId: tmdbShowId, seasonNumber: season)
            return details.episodes.compactMap { ep -> EpisodeRating? in
                guard let number = ep.episodeNumber, let vote = ep.voteAverage, vote > 0 else { return nil }
                return EpisodeRating(season: ep.seasonNumber ?? season, episode: number, rating: vote, title: ep.name)
            }
            .sorted { $0.episode < $1.episode }
        } catch {
            return nil
        }
    }
}
