//
//  StreamingAvailabilityModels.swift
//  FlixorMac
//
//  Movie of the Night "Streaming Availability" API (v4): the parts Flixor
//  reads. Unknown fields are ignored, missing ones are optional.
//

import Foundation

/// A service Flixor can show a Top 10 list for (the API's /shows/top supports these).
enum StreamingService: String, CaseIterable, Identifiable, Codable {
    case netflix, prime, disney, apple, hbo
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .netflix: return "Netflix"
        case .prime: return "Prime Video"
        case .disney: return "Disney+"
        case .apple: return "Apple TV+"
        case .hbo: return "Max"
        }
    }

    /// Brand colour for the settings icon.
    var colorHex: String {
        switch self {
        case .netflix: return "E50914"
        case .prime: return "00A8E1"
        case .disney: return "113CCF"
        case .apple: return "1C1C1E"
        case .hbo: return "002BE7"
        }
    }
}

struct SAImage: Codable, Hashable {
    let w240: String?
    let w360: String?
    let w480: String?
    let w600: String?
    let w720: String?
}

struct SAImageSet: Codable, Hashable {
    let verticalPoster: SAImage?
    let horizontalPoster: SAImage?
    let horizontalBackdrop: SAImage?
}

struct SAServiceInfo: Codable, Hashable {
    let id: String
    let name: String?
}

struct SAStreamingOption: Codable, Hashable {
    let service: SAServiceInfo
    let type: String?
    let link: String?
    let videoLink: String?
    let expiresSoon: Bool?
    let expiresOn: Int?
    let availableSince: Int?
}

struct SAShow: Codable, Hashable, Identifiable {
    let id: String
    let showType: String
    let title: String
    let overview: String?
    let releaseYear: Int?
    let firstAirYear: Int?
    let imdbId: String?
    /// "movie/123" or "tv/456".
    let tmdbId: String?
    let rating: Int?
    let imageSet: SAImageSet?
    /// Options per country code.
    let streamingOptions: [String: [SAStreamingOption]]?

    var year: Int? { releaseYear ?? firstAirYear }
    var isSeries: Bool { showType == "series" }

    /// Flixor's id for the details pipeline ("tmdb:movie:123"), or nil without a TMDB id.
    var flixorId: String? {
        guard let tmdbId, let slash = tmdbId.firstIndex(of: "/") else { return nil }
        let kind = tmdbId[..<slash] == "tv" ? "tv" : "movie"
        return "tmdb:\(kind):\(tmdbId[tmdbId.index(after: slash)...])"
    }

    func link(service: StreamingService, country: String) -> URL? {
        streamingOptions?[country]?.first { $0.service.id == service.rawValue }?.link.flatMap(URL.init(string:))
    }

    var posterURL: String? {
        imageSet?.verticalPoster.flatMap { $0.w480 ?? $0.w360 ?? $0.w600 ?? $0.w240 }
    }

    var backdropURL: String? {
        imageSet?.horizontalBackdrop.flatMap { $0.w720 ?? $0.w600 ?? $0.w480 }
    }
}

struct SAChange: Codable, Hashable {
    let changeType: String
    let itemType: String?
    let showId: String
    let showType: String?
    let service: SAServiceInfo?
    /// "subscription", "addon", "rent", "buy" or "free".
    let streamingOptionType: String?
    let timestamp: Int?
    let link: String?
}

struct SAChangesResult: Codable {
    let changes: [SAChange]
    let shows: [String: SAShow]
    let hasMore: Bool?
    let nextCursor: String?
}

struct SACountry: Codable {
    let countryCode: String
    let name: String
    let services: [SAServiceInfo]
}

/// Quota reported by the API on every response.
struct SAQuota: Codable, Equatable {
    var used: Int
    var granted: Int
    var resetsAt: Date?
    var observedAt: Date

    var remaining: Int { max(0, granted - used) }
}
