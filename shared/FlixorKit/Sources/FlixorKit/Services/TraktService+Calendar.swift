//
//  TraktService+Calendar.swift
//  FlixorKit
//
//  The user's show calendar: episodes of shows they watch or follow, by air time.
//

import Foundation

/// One entry of `/calendars/my/shows`.
public struct TraktCalendarShowEntry: Decodable {
    /// UTC air time, ISO 8601.
    public let firstAired: String?
    public let episode: TraktEpisode
    public let show: TraktShow

    private enum CodingKeys: String, CodingKey {
        case episode, show
        case firstAired = "first_aired"
    }
}

/// Skips an element that fails to decode instead of failing the whole list.
private struct TraktCalendarLossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension TraktService {
    /// Episodes airing from `startDate` ("yyyy-MM-dd") for `days` days, for the
    /// shows the user watches or follows. Requires auth.
    public func getMyShowsCalendar(startDate: String, days: Int) async throws -> [TraktCalendarShowEntry] {
        let (data, _) = try await send(
            method: "GET",
            path: "/calendars/my/shows/\(startDate)/\(days)",
            params: ["extended": "full"],
            auth: true
        )
        return try JSONDecoder().decode([TraktCalendarLossy<TraktCalendarShowEntry>].self, from: data).compactMap(\.value)
    }
}
