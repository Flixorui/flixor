//
//  IntroDBClient.swift
//  FlixorMac
//
//  IntroDB (https://introdb.app): community intro / recap / outro / post-credits
//  timings keyed by IMDb id (+ season/episode). Reads are anonymous and rate
//  limited; we only use the public read endpoint `GET /segments`.
//

import Foundation

struct IntroDBClient {
    static let baseURL = "https://api.introdb.app"

    /// Segments for one episode. `imdbId` is the SHOW's IMDb id.
    func episodeSegments(imdbId: String, season: Int, episode: Int) async throws -> [SkipSegment] {
        var components = URLComponents(string: "\(Self.baseURL)/segments")
        components?.queryItems = [
            URLQueryItem(name: "imdb_id", value: imdbId),
            URLQueryItem(name: "season", value: String(season)),
            URLQueryItem(name: "episode", value: String(episode)),
        ]
        guard let url = components?.url else { return [] }
        let json = try await SkipSegmentHTTP.getJSON(url)
        return Self.parse(json, isMovie: false)
    }

    /// Segments for a movie (credits and post-credits scene).
    func movieSegments(imdbId: String) async throws -> [SkipSegment] {
        var components = URLComponents(string: "\(Self.baseURL)/segments")
        components?.queryItems = [
            URLQueryItem(name: "imdb_id", value: imdbId),
            URLQueryItem(name: "is_movie", value: "true"),
        ]
        guard let url = components?.url else { return [] }
        let json = try await SkipSegmentHTTP.getJSON(url)
        return Self.parse(json, isMovie: true)
    }

    static func parse(_ json: Any, isMovie: Bool) -> [SkipSegment] {
        guard let object = json as? [String: Any] else { return [] }
        let fields: [(String, SkipSegmentType)] = [
            ("intro", .intro),
            ("recap", .recap),
            ("outro", .credits),
            ("post_credits", .postCredits),
        ]
        var segments: [SkipSegment] = fields.compactMap { key, type in
            guard let raw = object[key] as? [String: Any] else { return nil }
            let start = SkipSegmentHTTP.seconds(raw["start_sec"]) ?? SkipSegmentHTTP.seconds(raw["start_ms"]).map { $0 / 1000 }
            let end = SkipSegmentHTTP.seconds(raw["end_sec"]) ?? SkipSegmentHTTP.seconds(raw["end_ms"]).map { $0 / 1000 }
            guard let start, let end else { return nil }
            let segment = SkipSegment(type: type, start: start, end: end, provider: .introDB)
            return segment.isValid ? segment : nil
        }
        if isMovie {
            // Movies only use end credits and the post-credits scene.
            segments.removeAll { $0.type != .credits && $0.type != .postCredits }
        }
        return segments
    }
}
