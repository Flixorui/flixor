//
//  LiveTVModels.swift
//  FlixorMac
//
//  Personal build only (FLIXOR_LIVE_TV). Data types for Xtream Live TV,
//  mirroring xtream-web's src/lib/types.ts, stream-sources.ts and
//  feed-evidence.ts so the curated lineup behaves the same.
//

#if FLIXOR_LIVE_TV
import Foundation

// MARK: - Accounts

/// The Xtream Codes account. Stored as one JSON item in the Keychain.
struct LiveTVAccount: Codable, Equatable {
    var name: String
    var serverURL: String
    var username: String
    var password: String

    /// Normalized base URL with a trailing slash, or nil when invalid.
    var baseURL: URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.hasSuffix("/") ? trimmed : trimmed + "/"),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    var isComplete: Bool {
        baseURL != nil && !username.isEmpty && !password.isEmpty
    }
}

/// The deployed xtream-web server that serves the merged guide.
struct LiveTVGuideServer: Codable, Equatable {
    var url: String
    var password: String

    var origin: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = parsed.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = parsed.port
        return components.url
    }

    var isComplete: Bool { origin != nil && !password.isEmpty }
}

/// What `player_api.php` reports about the account.
struct LiveTVAccountStatus: Equatable {
    var status: String
    var expiresAt: Date?
    var maxConnections: Int?
    var activeConnections: Int?
}

// MARK: - Raw provider data

struct XtreamRawCategory: Equatable {
    let categoryId: String
    let categoryName: String
}

struct XtreamRawStream: Equatable {
    let streamId: String
    let name: String
    let categoryId: String
    let epgChannelId: String?
    let streamIcon: String?
    /// `Number(is_adult ?? 0)` in xtream-web; NaN is represented by nil.
    let adultFlag: Double?
}

extension XtreamRawCategory {
    init?(json: [String: Any]) {
        guard let id = LiveTVJSON.string(json["category_id"]),
              let name = json["category_name"] as? String else { return nil }
        self.init(categoryId: id, categoryName: name)
    }
}

extension XtreamRawStream {
    init?(json: [String: Any]) {
        guard let id = LiveTVJSON.string(json["stream_id"]) else { return nil }
        self.init(
            streamId: id,
            name: json["name"] as? String ?? "",
            categoryId: LiveTVJSON.string(json["category_id"]) ?? "",
            epgChannelId: json["epg_channel_id"] as? String,
            streamIcon: json["stream_icon"] as? String,
            adultFlag: LiveTVJSON.number(json["is_adult"])
        )
    }

    var isAdult: Bool { adultFlag == 1 }
}

/// JavaScript-style coercions used by xtream-web (`String(x)`, `Number(x)`).
enum LiveTVJSON {
    static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return n.stringValue
        default: return nil
        }
    }

    /// `Number(value ?? 0)`: nil/NSNull -> 0, "" -> 0, numeric strings parse, others NaN (nil).
    static func number(_ value: Any?) -> Double? {
        switch value {
        case nil, is NSNull: return 0
        case let n as NSNumber: return n.doubleValue
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return 0 }
            return Double(t)
        default: return nil
        }
    }
}

// MARK: - Curated lineup rules (exported from xtream-web)

struct FeedEvidence: Codable, Equatable {
    var name: String?
    var status: String
    var note: String
    var checkedAt: String
    var source: String?
    var scheduleChannel: String?
    var zone: String?
}

struct VerifiedSource: Codable, Equatable, Identifiable {
    var id: String
    var channelId: String?
    var channel: String
    var region: String
    var language: String
    var coast: String
    var quality: String
    var checkedAt: String
    var evidence: String
}

struct IndianFeedObservation: Codable, Equatable {
    var id: String
    var name: String
    var language: String
    var genre: String
    var checkedAt: String
    var note: String
    var regionVerified: Bool?
    var quality: String
}

struct StationLocation: Codable, Equatable {
    var callsign: String
    var city: String
    var state: String
    var market: String
}

struct CuratedLineupRules: Codable {
    var schemaVersion: Int
    var generatedAt: String
    var referenceLineup: [String]
    var aliases: [String: [String]]
    var callsigns: [String: String]
    var priority: [String]
    var feedEvidence: [String: FeedEvidence]
    var indianFeeds: [IndianFeedObservation]
    var stations: [StationLocation]
    var verifiedSources: [VerifiedSource]
    /// logo-manifest.json as ordered [name, path] pairs (schema 2+).
    var logos: [[String]]?
    /// The alias table in logos.ts (schema 2+).
    var logoAliases: [String: String]?
}

// MARK: - Channels and guide

enum LiveTVMarket: String, Codable, CaseIterable, Identifiable {
    case us = "US"
    case india = "IN"
    var id: String { rawValue }
    var title: String { self == .us ? "United States" : "India" }
}

struct LiveChannel: Identifiable, Hashable {
    var id: String
    var name: String
    var originalName: String
    var category: String
    var categoryId: String
    var genre: String
    var epgId: String
    var quality: String
    var feed: String
    var core: Bool
    var market: LiveTVMarket = .us
    var language: String?
    var referenceName: String?
    var location: StationLocation?
    var premium: Bool = false
    var evidence: FeedEvidence?
    var sources: [VerifiedSource] = []
    var variants: Int
    /// Provider `stream_icon` (used when no guide server is set up).
    var logoURL: String?
    /// xtream-web's logo for this channel, a path on the guide server
    /// (`/logos/…` or `/api/image/{id}`), chosen exactly as logos.ts does.
    var logoPath: String?

    /// `nameOf` in tv-app.tsx.
    var displayName: String { referenceName ?? name }

    /// Playable provider ids in failover order (the channel id when it has no verified group).
    var sourceIds: [String] { sources.isEmpty ? [id] : sources.map(\.id) }

    static func == (lhs: LiveChannel, rhs: LiveChannel) -> Bool {
        lhs.id == rhs.id && lhs.referenceName == rhs.referenceName
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(referenceName)
    }
}

extension StationLocation: Hashable {}
extension FeedEvidence: Hashable {}
extension VerifiedSource: Hashable {}

struct LiveProgram: Identifiable, Equatable, Codable {
    var id: String
    var title: String
    var description: String
    var metadata: String?
    var start: Date
    var end: Date

    func isAiring(at date: Date) -> Bool { start <= date && end > date }
}

struct LiveGuideEntry: Equatable {
    var programs: [LiveProgram]
    var unavailable: Bool
    var source: String?

    func current(at date: Date) -> LiveProgram? { programs.first { $0.isAiring(at: date) } }

    /// One program per time slot. Provider EPGs can merge two guide feeds for
    /// the same channel, giving near-duplicate rows a few minutes apart
    /// (e.g. 7:23–8:18 and 7:25–8:19). Keeps the earliest of any overlap.
    func normalized() -> LiveGuideEntry {
        var kept: [LiveProgram] = []
        for p in programs.sorted(by: { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }) {
            if let last = kept.last, p.start < last.end.addingTimeInterval(-60) { continue }
            kept.append(p)
        }
        return LiveGuideEntry(programs: kept, unavailable: unavailable, source: source)
    }
    func next(after date: Date) -> LiveProgram? { programs.first { $0.start >= date } }
}
#endif
