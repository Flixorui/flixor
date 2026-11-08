//
//  AnimeIdMappingClient.swift
//  FlixorMac
//
//  Maps TMDB / IMDb / Kitsu ids to MyAnimeList and AniList ids using the public
//  ARM API (https://arm.haglund.dev, no key). Non-anime titles simply return
//  no match, so this also acts as the "is this anime?" check.
//

import Foundation

struct AnimeIds: Hashable {
    let malId: String?
    let anilistId: String?

    var isEmpty: Bool { malId == nil && anilistId == nil }
}

struct AnimeIdMappingClient {
    static let baseURL = "https://arm.haglund.dev/api/v2"

    private static let include = "myanimelist,anilist,themoviedb-season,thetvdb-season"

    /// Anime ids for one season of a show. TMDB/IMDb map one show to several anime
    /// entries (one per season or cour), so only an unambiguous match is returned:
    /// a single entry tagged with this season, or a single untagged entry for season 1.
    func idsForShow(tmdbId: Int?, imdbId: String?, season: Int) async throws -> AnimeIds? {
        var entries: [[String: Any]] = []
        if let tmdbId {
            entries = try await lookup(path: "themoviedb", id: String(tmdbId))
        }
        if entries.isEmpty, let imdbId {
            entries = try await lookup(path: "imdb", id: imdbId)
        }
        guard !entries.isEmpty else { return nil }

        let tagged = entries.filter {
            SkipSegmentHTTP.int($0["themoviedb-season"]) == season || SkipSegmentHTTP.int($0["thetvdb-season"]) == season
        }
        let match: [String: Any]?
        if tagged.count == 1 {
            match = tagged.first
        } else if tagged.isEmpty, entries.count == 1, season == 1 {
            match = entries.first
        } else {
            match = nil
        }
        guard let match else { return nil }
        let ids = AnimeIds(
            malId: SkipSegmentHTTP.string(match["myanimelist"]),
            anilistId: SkipSegmentHTTP.string(match["anilist"])
        )
        return ids.isEmpty ? nil : ids
    }

    /// Anime ids for an id from an anime database (kitsu, myanimelist).
    func ids(source: String, id: String) async throws -> AnimeIds? {
        guard var components = URLComponents(string: "\(Self.baseURL)/ids") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "source", value: source),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "include", value: "myanimelist,anilist"),
        ]
        guard let url = components.url,
              let object = try await SkipSegmentHTTP.getJSON(url) as? [String: Any] else { return nil }
        let ids = AnimeIds(
            malId: SkipSegmentHTTP.string(object["myanimelist"]),
            anilistId: SkipSegmentHTTP.string(object["anilist"])
        )
        return ids.isEmpty ? nil : ids
    }

    private func lookup(path: String, id: String) async throws -> [[String: Any]] {
        guard var components = URLComponents(string: "\(Self.baseURL)/\(path)") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "include", value: Self.include),
        ]
        guard let url = components.url else { return [] }
        let json = try await SkipSegmentHTTP.getJSON(url)
        if let array = json as? [[String: Any]] { return array }
        if let single = json as? [String: Any] { return [single] }
        return []
    }
}
