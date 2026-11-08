//
//  AniSkipClient.swift
//  FlixorMac
//
//  AniSkip (https://aniskip.com): community opening / ending / recap timings for
//  anime, keyed by MyAnimeList id and episode number. Public, no key required.
//

import Foundation

struct AniSkipClient {
    static let baseURL = "https://api.aniskip.com/v2"

    func segments(malId: String, episode: Int) async throws -> [SkipSegment] {
        guard var components = URLComponents(string: "\(Self.baseURL)/skip-times/\(malId)/\(episode)") else { return [] }
        components.queryItems = ["op", "ed", "recap", "mixed-op", "mixed-ed"].map {
            URLQueryItem(name: "types", value: $0)
        } + [URLQueryItem(name: "episodeLength", value: "0")]
        guard let url = components.url else { return [] }
        let json = try await SkipSegmentHTTP.getJSON(url)
        return Self.parse(json)
    }

    static func parse(_ json: Any) -> [SkipSegment] {
        guard let object = json as? [String: Any],
              (object["found"] as? Bool) == true,
              let results = object["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { result in
            guard let skipType = (result["skipType"] as? String)?.lowercased(),
                  let interval = result["interval"] as? [String: Any],
                  let start = SkipSegmentHTTP.seconds(interval["startTime"]),
                  let end = SkipSegmentHTTP.seconds(interval["endTime"]) else { return nil }
            let type: SkipSegmentType
            switch skipType {
            case "op", "mixed-op": type = .intro
            case "ed", "mixed-ed": type = .credits
            case "recap": type = .recap
            default: return nil
            }
            let segment = SkipSegment(type: type, start: start, end: end, provider: .aniSkip)
            return segment.isValid ? segment : nil
        }
    }
}
