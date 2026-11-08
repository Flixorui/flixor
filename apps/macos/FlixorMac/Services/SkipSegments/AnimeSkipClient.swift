//
//  AnimeSkipClient.swift
//  FlixorMac
//
//  Anime-Skip (https://anime-skip.com): community timestamps for anime via its
//  public GraphQL API. Its terms require each app to use its own client id, so
//  this client only runs when the user has entered one (no shared id is shipped).
//

import Foundation

struct AnimeSkipClient {
    static let endpoint = URL(string: "https://api.anime-skip.com/graphql")!

    let clientId: String

    /// Anime-Skip show ids linked to an AniList id.
    func showIds(anilistId: String) async throws -> [String] {
        guard anilistId.allSatisfy(\.isNumber) else { return [] }
        let query = "{ findShowsByExternalId(service: ANILIST, serviceId: \"\(anilistId)\") { id } }"
        let data = try await run(query)
        let shows = data?["findShowsByExternalId"] as? [[String: Any]] ?? []
        return shows.compactMap { SkipSegmentHTTP.string($0["id"]) }
    }

    /// Segments for one episode number of a show. Several community entries can
    /// exist for the same episode; the one covering the most segment types wins.
    func segments(showId: String, episode: Int) async throws -> [SkipSegment] {
        guard showId.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return [] }
        let query = "{ findEpisodesByShowId(showId: \"\(showId)\") { season number baseDuration timestamps { at type { name } } } }"
        let data = try await run(query)
        let episodes = data?["findEpisodesByShowId"] as? [[String: Any]] ?? []
        let candidates = episodes
            .filter { SkipSegmentHTTP.int($0["number"]) == episode }
            .map { entry -> [SkipSegment] in
                let timestamps = (entry["timestamps"] as? [[String: Any]] ?? []).compactMap { raw -> (at: Double, name: String)? in
                    guard let at = SkipSegmentHTTP.seconds(raw["at"]),
                          let name = (raw["type"] as? [String: Any])?["name"] as? String else { return nil }
                    return (at: at, name: name)
                }
                return Self.segments(from: timestamps, baseDuration: SkipSegmentHTTP.seconds(entry["baseDuration"]))
            }
            .filter { !$0.isEmpty }
        return candidates.max { lhs, rhs in
            let l = Set(lhs.map(\.type)).count, r = Set(rhs.map(\.type)).count
            return l == r ? lhs.count < rhs.count : l < r
        } ?? []
    }

    /// Anime-Skip stores only where each segment starts; a segment ends where the
    /// next one begins. Only an ending/preview in the second half may run to the
    /// end of the file; an open-ended intro or recap is dropped.
    static func segments(from timestamps: [(at: Double, name: String)], baseDuration: Double?) -> [SkipSegment] {
        let sorted = timestamps.sorted { $0.at < $1.at }
        var result: [SkipSegment] = []
        for (index, stamp) in sorted.enumerated() {
            let type: SkipSegmentType
            switch stamp.name.lowercased() {
            case "intro", "new intro", "mixed intro": type = .intro
            case "credits", "new credits", "mixed credits": type = .credits
            case "recap": type = .recap
            case "preview": type = .preview
            default: continue
            }
            let end: Double?
            if index + 1 < sorted.count {
                let next = sorted[index + 1].at
                guard next > stamp.at else { continue }
                end = next
            } else if type == .credits || type == .preview, baseDuration == nil || stamp.at >= (baseDuration ?? 0) / 2 {
                end = nil
            } else {
                continue
            }
            let segment = SkipSegment(type: type, start: stamp.at, end: end, provider: .animeSkip)
            if segment.isValid { result.append(segment) }
        }
        return result
    }

    private func run(_ query: String) async throws -> [String: Any]? {
        let json = try await SkipSegmentHTTP.postJSON(
            Self.endpoint,
            body: ["query": query],
            headers: ["X-Client-ID": clientId]
        )
        return (json as? [String: Any])?["data"] as? [String: Any]
    }
}
