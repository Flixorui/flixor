//
//  MyBlurayModels.swift
//  FlixorMac
//
//  App-side models for the MyBluray v2 API. They decode straight from the API
//  (unknown keys are ignored) and are what the disk cache stores, so only the
//  fields Flixor uses are declared. Lists use `LossyArray`, so one odd element
//  never costs the whole response. Unknown values stay nil.
//

import Foundation

// MARK: - Envelope

struct MBEnvelope<T: Decodable>: Decodable {
    struct Links: Decodable {
        let next: String?
    }
    struct Meta: Decodable {
        struct Pagination: Decodable {
            let page: Int?
            let totalItems: Int?
            let hasMore: Bool?
        }
        let requestId: String?
        let pagination: Pagination?
    }

    let data: T
    let meta: Meta?
    let links: Links?
}

// MARK: - Lossy decoding

/// Decodes the elements that parse and skips the rest. A missing key or null is [].
@propertyWrapper
struct LossyArray<Element: Codable>: Codable {
    var wrappedValue: [Element]

    init(wrappedValue: [Element] = []) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        wrappedValue = elements
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }

    /// Accepts any JSON value without reading it, so the container moves past
    /// an element that failed to decode (a throwing decode would not advance).
    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

extension LossyArray: Equatable where Element: Equatable {}

extension KeyedDecodingContainer {
    func decode<T>(_ type: LossyArray<T>.Type, forKey key: Key) throws -> LossyArray<T> {
        (try? decodeIfPresent(type, forKey: key)) ?? LossyArray()
    }
}

// MARK: - Titles (Apple TV, JustWatch, Letterboxd)

/// `/v2/titles/imdb:{id}`: identity, ratings, Common Sense guidance,
/// certifications and the videos Flixor plays.
struct MBTitle: Codable, Equatable {
    let id: String
    let imdbId: String?
    let type: String?           // "movie" | "tv-show"
    let title: String?
    let year: Int?
    let status: String?         // "complete" | "partial" | "unavailable"
    let externalIds: MBExternalIds?
    @LossyArray var ratings: [MBRating]
    @LossyArray var parentalGuidance: [MBGuidance]
    @LossyArray var certifications: [MBCertification]
    @LossyArray var videos: [MBVideo]
    @LossyArray var sources: [MBSourceStatus]

    var isShow: Bool { type == "tv-show" }

    /// Drops what Flixor never plays so the cache stays small (a full response
    /// can carry 300+ video links): every Apple video, JustWatch MP4 clips that
    /// aren't vertical shorts, and the first YouTube trailers and teasers.
    func trimmedForStorage(youtubeLimit: Int = 10) -> MBTitle {
        var copy = self
        var youtube = 0
        copy.videos = videos.filter { video in
            switch video.host {
            case "apple-tv": return true
            case "justwatch": return video.playback == "direct-mp4" && video.kind != "vertical"
            case "youtube":
                guard video.kind == "trailer" || video.kind == "teaser", youtube < youtubeLimit else { return false }
                youtube += 1
                return true
            default: return false
            }
        }
        return copy
    }

    /// Apple trailers and bonus videos that play directly in AVPlayer, without
    /// repeats. Apple can list one trailer under two products (Spider-Man's
    /// theatrical and Extended versions), so videos with the same kind and
    /// length are treated as one.
    var directAppleVideos: [MBVideo] {
        var seenURLs = Set<String>()
        var seenCuts = Set<String>()
        return videos.filter { video in
            guard video.host == "apple-tv", video.playback == "direct-hls",
                  let url = video.playbackUrl, seenURLs.insert(url).inserted else { return false }
            if let duration = video.durationSeconds {
                let cut = "\(video.kind ?? ""):\(String(format: "%.2f", duration))"
                guard seenCuts.insert(cut).inserted else { return false }
            }
            return true
        }
    }
}

struct MBExternalIds: Codable, Equatable {
    let imdb: String?
    let tmdb: String?
    let justwatch: String?
    let appleTv: String?
    let letterboxd: String?
}

struct MBProvenance: Codable, Equatable {
    /// The catalog that supplied the record: "apple-tv", "justwatch" or "letterboxd".
    let provider: String?
    let sourceUrl: String?
}

/// One score on its original scale. `provider` is whose score it is (imdb,
/// rotten-tomatoes, letterboxd, tmdb, justwatch); `provenance.provider` is the
/// catalog that reported it.
struct MBRating: Codable, Equatable {
    let provider: String
    let kind: String            // community, critics-percentage, audience-percentage, critic-average, weighted-community, uninterpreted
    let value: Double?
    let scale: Double?
    let voteCount: Int?
    let freshness: String?      // e.g. "CertifiedFresh"
    let certifiedFresh: Bool?
    let freshReviews: Int?
    let rottenReviews: Int?
    let consensus: String?
    let websiteUrl: String?
    let provenance: MBProvenance?
}

/// Common Sense Media age advice as supplied by Apple.
struct MBGuidance: Codable, Equatable {
    struct Category: Codable, Equatable {
        let name: String
        let value: Double?
        let scale: Double?
    }
    let provider: String?
    let recommendedAge: Int?
    let summary: String?
    @LossyArray var categories: [Category]
}

struct MBCertification: Codable, Equatable {
    let system: String?         // e.g. "mpaa", "us-tv"
    let value: String?          // e.g. "PG-13"
    let explanation: String?
    let advisories: [String]?
}

struct MBVideo: Codable, Equatable {
    let providerId: String?
    let kind: String?           // trailer, teaser, clip, featurette, vertical
    let sourceLabel: String?
    let title: String?
    let durationSeconds: Double?
    let host: String            // apple-tv, justwatch, youtube, dailymotion
    let url: String?            // webpage (Apple TV clip page, YouTube watch page)
    let playbackUrl: String?    // direct HLS/MP4 when verified
    let playbackFormat: String? // hls | mp4
    let playback: String?       // direct-hls | direct-mp4 | provider-app | external-host
    let thumbnailUrl: String?
    let language: String?

    /// YouTube video id from the watch URL, for the existing YouTube player.
    var youtubeKey: String? {
        guard host == "youtube", let url, let components = URLComponents(string: url) else { return nil }
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        let last = components.path.split(separator: "/").last.map(String.init)
        return (last?.isEmpty == false) ? last : nil
    }
}

struct MBSourceStatus: Codable, Equatable {
    let provider: String
    let status: String          // available, unavailable, not-found, unsupported
    /// The title's page on that service (Apple TV, JustWatch, Letterboxd).
    var sourceUrl: String? = nil
}

// MARK: - IMDb parents guide

struct MBParentsGuide: Codable, Equatable {
    struct Certification: Codable, Equatable {
        let rating: String?
        let country: String?
        let reason: String?
    }
    struct Votes: Codable, Equatable {
        let none: Int?
        let mild: Int?
        let moderate: Int?
        let severe: Int?
    }
    struct Description: Codable, Equatable {
        let id: String?
        let text: String
        let isSpoiler: Bool?
    }
    struct Category: Codable, Equatable {
        let category: String    // sex-and-nudity, violence-and-gore, profanity, alcohol-drugs-and-smoking, frightening-and-intense-scenes
        let label: String?
        let severity: String?   // none, mild, moderate, severe
        let severityLabel: String?
        let totalVotes: Int?
        let votes: Votes?
        @LossyArray var descriptions: [Description]
    }

    let titleId: String?
    let title: String?
    let status: String?         // available | not-available
    let websiteUrl: String?
    let certification: Certification?
    @LossyArray var categories: [Category]
    let usageNotice: String?

    /// No community categories to show. IMDb may still report a certification
    /// such as "Not Rated" (Ready), which alone isn't worth a guidance card.
    var isEmpty: Bool { categories.isEmpty }
}

// MARK: - Blu-ray.com films and editions

struct MBMovie: Codable, Equatable {
    struct Score: Codable, Equatable {
        let value: Double?
        let scale: Double?
        let voteCount: Int?
    }
    let id: String              // "movie:18630"
    let title: String?
    let year: Int?
    let websiteUrl: String?
    let imdbId: String?
    let externalLinks: [String]?
    let runtimeMinutes: Int?
    let ageRating: String?
    let communityMovieScore: Score?
}

struct MBCountry: Codable, Hashable {
    let code: String?
    let name: String?
}

/// A row from a movie's edition list. Has cover and release date, not specs.
struct MBEditionSummary: Codable, Hashable, Identifiable {
    let id: String              // "bluray:187101"
    let title: String?
    let year: Int?
    let country: MBCountry?
    let websiteUrl: String?
    let coverImage: String?
    let releaseDate: String?    // yyyy-MM-dd
    let format: String?         // "4k" | "bluray"
    let bundle: Bool?
}

/// Full edition details (`/v2/editions/{id}`).
struct MBEdition: Codable, Equatable, Identifiable {
    struct VideoSpec: Codable, Equatable {
        let codec: String?
        let resolution: String?
        let hdr: String?
        let aspectRatio: String?
        let originalAspectRatio: String?
    }
    struct Screenshot: Codable, Equatable {
        struct Provenance: Codable, Equatable {
            let sourceFormat: String?
            let sourceResolution: String?
            let nativeToEdition: Bool?
            let note: String?
        }
        let url: String
        let thumbnailUrl: String?
        let provenance: Provenance?
    }
    struct ScoreSet: Codable, Equatable {
        let scale: Double?
        let scores: [String: Double]?   // movie, video4k, video2k, video, audio, extras, overall
        let voteCount: Int?
        let author: String?
        let date: String?
        let sourceUrl: String?

        enum CodingKeys: String, CodingKey { case scale, scores, voteCount, author, date, sourceUrl }

        /// Scores not given yet come as null (box sets often have no review);
        /// they are left out rather than failing the whole edition.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            scale = try? c.decodeIfPresent(Double.self, forKey: .scale)
            let raw = (try? c.decodeIfPresent([String: Double?].self, forKey: .scores)) ?? nil
            let present = raw?.compactMapValues { $0 }
            scores = (present?.isEmpty ?? true) ? nil : present
            voteCount = try? c.decodeIfPresent(Int.self, forKey: .voteCount)
            author = try? c.decodeIfPresent(String.self, forKey: .author)
            date = try? c.decodeIfPresent(String.self, forKey: .date)
            sourceUrl = try? c.decodeIfPresent(String.self, forKey: .sourceUrl)
        }
    }
    struct ReviewScores: Codable, Equatable {
        let critic: ScoreSet?
        let communityReviews: ScoreSet?
        let communityRatings: ScoreSet?
    }
    struct DigitalCopy: Codable, Equatable {
        struct Platform: Codable, Equatable {
            let value: String?
            let label: String?
        }
        let included: Bool?
        let resolution: String?
        @LossyArray var platforms: [Platform]
    }
    struct Artwork: Codable, Equatable {
        let type: String?       // front-cover, back-cover, slipcover-front, slipcover-back, packaging-overview
        let url: String
    }
    struct RetailOffer: Codable, Equatable {
        let purchaseUrl: String?
        let currency: String?
        let price: String?
        let listPrice: String?
        let newPrice: String?
        let availability: String?
    }
    struct Metadata: Codable, Equatable {
        let studio: String?
        let synopsis: String?
        let runtime: Int?
        let amazon: RetailOffer?
    }

    let id: String
    let title: String?
    let editionTitle: String?
    let year: Int?
    let country: MBCountry?
    let websiteUrl: String?
    let coverImage: String?
    let coverImages: [String]?
    let releaseDate: String?
    let format: String?
    let exclusive: String?
    let region: [String]?
    let video: VideoSpec?
    let audio: [String]?
    let subtitles: String?
    let discs: [String]?
    let packaging: [String]?
    @LossyArray var screenshots: [Screenshot]
    let reviewScores: ReviewScores?
    let digitalCopy: DigitalCopy?
    @LossyArray var artwork: [Artwork]
    let metadata: Metadata?
    let detailsStatus: String?  // complete | partial | error
}

// MARK: - Collection (needs a Blu-ray.com login attached to the key)

struct MBCollectionList: Codable, Equatable, Identifiable {
    let id: String              // "bluray:1"
    let name: String?
    let alias: String?          // "owned" | "wishlist" for system lists
    let system: Bool?
    let displayOrder: Int?
}

struct MBCollectionEntry: Codable, Equatable, Identifiable {
    struct ListRef: Codable, Equatable {
        let id: String?
        let alias: String?
        let name: String?
    }
    let id: String              // "bluray:187101"
    let title: String?
    let year: Int?
    let country: MBCountry?
    let coverImage: String?
    let releaseDate: String?
    let format: String?
    let list: ListRef?
    let addedAt: String?
}

/// Body for adding or updating a collection entry. Send `list` (an alias such
/// as "owned") or `listId`, never both. Nil fields are left out.
struct MBCollectionChange: Encodable {
    var productId: String?
    var list: String?
    var listId: String?
    var note: String?
    var watched: Bool?
    var purchasePrice: String?
    var purchaseStore: String?
    var addedAt: String?
}

// MARK: - Providers

struct MBProvider: Codable, Equatable {
    let id: String              // imdb, apple-tv, justwatch, letterboxd
    let name: String?
    let capabilities: [String]?
}

// MARK: - Key check

/// What a key can reach, from `MyBlurayService.checkKey`.
struct MyBlurayAccess: Equatable {
    enum State: Equatable { case yes, no, unknown }

    static let appleTV = "apple-tv"
    static let justWatch = "justwatch"
    static let letterboxd = "letterboxd"
    static let imdb = "imdb"
    static let bluray = "bluray"
    static let collection = "collection"

    /// Sources that answer through `/v2/titles` and report themselves in `sources`.
    static let titleSources = [appleTV, justWatch, letterboxd]

    var states: [String: State] = [:]

    func state(_ id: String) -> State { states[id] ?? .unknown }
}
