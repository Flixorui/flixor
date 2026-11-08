//
//  SkipSegmentModels.swift
//  FlixorMac
//
//  Provider-neutral skip segments (intro, recap, credits, preview, post-credits)
//  and the request used to look them up from community databases.
//

import Foundation

/// Kind of segment, normalized across providers. The raw value is also the
/// `PlayerMarker.type` string the player uses.
enum SkipSegmentType: String, Codable, CaseIterable, Hashable {
    case intro
    case recap
    case credits
    /// Next-episode preview after the ending (common in anime).
    case preview
    /// A scene after the credits. It is content, so it is never skipped; it only
    /// moves the credits skip target and the next-episode trigger.
    case postCredits = "postcredits"

    /// Marker `type` string used by `PlayerMarker` and the player UI.
    var markerType: String { rawValue }

    /// Whether the player offers a skip action for this segment.
    var isSkippable: Bool { self != .postCredits }

    var displayName: String {
        switch self {
        case .intro: return String(localized: "Intro")
        case .recap: return String(localized: "Recap")
        case .credits: return String(localized: "Credits")
        case .preview: return String(localized: "Preview")
        case .postCredits: return String(localized: "Post-Credits Scene")
        }
    }

    init?(markerType: String) {
        self.init(rawValue: markerType.lowercased())
    }
}

/// Where a segment came from. Order of `priority` decides which provider wins
/// when several report the same segment type.
enum SkipSegmentProvider: String, Codable, Hashable {
    case plex
    case introDB = "introdb"
    case aniSkip = "aniskip"
    case animeSkip = "animeskip"

    var displayName: String {
        switch self {
        case .plex: return "Plex"
        case .introDB: return "IntroDB"
        case .aniSkip: return "AniSkip"
        case .animeSkip: return "Anime-Skip"
        }
    }
}

struct SkipSegment: Codable, Hashable {
    let type: SkipSegmentType
    /// Seconds from the start of the file.
    let start: TimeInterval
    /// Seconds from the start of the file; nil when the segment runs to the end
    /// of the file (Anime-Skip only gives start times for the last segment).
    let end: TimeInterval?
    let provider: SkipSegmentProvider

    /// Basic sanity check for provider data.
    var isValid: Bool {
        guard start.isFinite, start >= 0 else { return false }
        if let end { return end.isFinite && end > start }
        return true
    }
}

/// Identifies one movie or episode for a community segment lookup.
struct SkipSegmentRequest: Hashable {
    /// IMDb id of the movie, or of the SHOW for episodes.
    var imdbId: String?
    /// TMDB id of the movie, or of the SHOW for episodes.
    var tmdbId: Int?
    var isMovie: Bool
    var season: Int?
    var episode: Int?
    /// Anime database ids when the item itself is keyed by one (Stremio `kitsu:` / `mal:` ids).
    var kitsuId: String?
    var malId: String?
    /// User-provided Anime-Skip client id; Anime-Skip is skipped when empty.
    var animeSkipClientId: String = ""

    /// Cache key: one entry per movie / episode.
    var cacheKey: String {
        if isMovie {
            return "movie:\(imdbId ?? tmdbId.map { "tmdb\($0)" } ?? "?")"
        }
        let base: String
        if let malId { base = "mal\(malId)" }
        else if let kitsuId { base = "kitsu\(kitsuId)" }
        else if let imdbId { base = imdbId }
        else if let tmdbId { base = "tmdb\(tmdbId)" }
        else { base = "?" }
        return "episode:\(base):\(season ?? 0):\(episode ?? 0)"
    }

    /// True when there is enough information to ask any provider.
    var isLookupPossible: Bool {
        if isMovie { return imdbId != nil }
        guard let episode, episode > 0 else { return false }
        if kitsuId != nil || malId != nil { return true }
        return season != nil && (imdbId != nil || tmdbId != nil)
    }
}
