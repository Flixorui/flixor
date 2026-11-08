//
//  TraktService+ContinueWatching.swift
//  FlixorKit
//
//  Reads what the user was watching on Trakt: paused playback entries and the
//  next unwatched episode of recently watched shows.
//

import Foundation

/// A show from `/sync/watched/shows`, with when it was last watched.
public struct TraktWatchedShowSummary: Decodable {
    public let lastWatchedAt: String?
    public let show: TraktShow

    private enum CodingKeys: String, CodingKey {
        case show
        case lastWatchedAt = "last_watched_at"
    }
}

/// The parts of `/shows/{id}/progress/watched` needed to find the next episode.
public struct TraktShowNextUp: Decodable {
    public let aired: Int
    public let completed: Int
    public let nextEpisode: TraktEpisode?

    private enum CodingKeys: String, CodingKey {
        case aired, completed
        case nextEpisode = "next_episode"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aired = try c.decodeIfPresent(Int.self, forKey: .aired) ?? 0
        completed = try c.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        nextEpisode = try? c.decodeIfPresent(TraktEpisode.self, forKey: .nextEpisode)
    }
}

/// Skips an element that fails to decode instead of failing the whole list.
private struct TraktLossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension TraktService {
    /// Paused movies and episodes with runtimes. Unreadable entries are skipped.
    /// Requires auth.
    public func getPausedPlayback() async throws -> [TraktPlaybackItem] {
        let (data, _) = try await send(
            method: "GET",
            path: "/sync/playback",
            params: ["extended": "full"],
            auth: true
        )
        return try JSONDecoder().decode([TraktLossy<TraktPlaybackItem>].self, from: data).compactMap(\.value)
    }

    /// Every show the user has watched, without per-episode data. Requires auth.
    public func getWatchedShowSummaries() async throws -> [TraktWatchedShowSummary] {
        let (data, _) = try await send(
            method: "GET",
            path: "/sync/watched/shows",
            params: ["extended": "noseasons"],
            auth: true
        )
        return try JSONDecoder().decode([TraktLossy<TraktWatchedShowSummary>].self, from: data).compactMap(\.value)
    }

    /// The next aired, unwatched episode of a show. `showId` may be a Trakt id,
    /// slug or IMDb id. Requires auth.
    public func getShowNextUp(showId: String) async throws -> TraktShowNextUp {
        let (data, _) = try await send(
            method: "GET",
            path: "/shows/\(showId)/progress/watched",
            params: ["hidden": "false", "specials": "false", "count_specials": "false", "extended": "full"],
            auth: true
        )
        return try JSONDecoder().decode(TraktShowNextUp.self, from: data)
    }
}
