//
//  TraktService+Sync.swift
//  FlixorKit
//
//  Trakt endpoints for watch state, ratings, playback progress, comments and
//  personal lists. Built on `TraktService.send`, which handles auth headers,
//  token refresh on 401 and one retry on 429.
//
//  Rate limits (Trakt, per user): POST/PUT/DELETE about 1 per second, GET about
//  1000 per 5 minutes. Batch items into one `TraktSyncItems` instead of looping.
//

import Foundation

// MARK: - Sync Request Body

/// Body for `/sync/history`, `/sync/ratings` (and their `/remove` variants) and
/// `/users/me/lists/{id}/items`. Empty arrays are omitted when encoded.
///
/// Ids reuse `TraktScrobbleIds` (any one of trakt/slug/imdb/tmdb/tvdb is enough).
/// Shows can nest seasons and episodes: a show with no seasons means "the whole
/// show", a season with no episodes means "the whole season".
public struct TraktSyncItems: Encodable {
    public var movies: [TraktSyncMovie]
    public var shows: [TraktSyncShow]
    /// Episodes addressed by their own ids (rarely needed; prefer nesting under `shows`).
    public var episodes: [TraktSyncEpisodeById]

    public init(movies: [TraktSyncMovie] = [], shows: [TraktSyncShow] = [], episodes: [TraktSyncEpisodeById] = []) {
        self.movies = movies
        self.shows = shows
        self.episodes = episodes
    }

    public var isEmpty: Bool { movies.isEmpty && shows.isEmpty && episodes.isEmpty }

    /// One movie. `watchedAt` is used by history adds, `rating` by rating adds.
    public static func movie(_ ids: TraktScrobbleIds, watchedAt: Date? = nil, rating: Int? = nil) -> TraktSyncItems {
        TraktSyncItems(movies: [TraktSyncMovie(ids: ids, watchedAt: watchedAt, rating: rating)])
    }

    /// A whole show.
    public static func show(_ ids: TraktScrobbleIds, watchedAt: Date? = nil, rating: Int? = nil) -> TraktSyncItems {
        TraktSyncItems(shows: [TraktSyncShow(ids: ids, watchedAt: watchedAt, rating: rating)])
    }

    /// A whole season of a show.
    public static func season(showIds: TraktScrobbleIds, season: Int, watchedAt: Date? = nil, rating: Int? = nil) -> TraktSyncItems {
        TraktSyncItems(shows: [TraktSyncShow(
            ids: showIds,
            seasons: [TraktSyncSeason(number: season, watchedAt: watchedAt, rating: rating)]
        )])
    }

    /// One episode, addressed by show ids + season/episode number.
    public static func episode(
        showIds: TraktScrobbleIds,
        season: Int,
        episode: Int,
        watchedAt: Date? = nil,
        rating: Int? = nil
    ) -> TraktSyncItems {
        TraktSyncItems(shows: [TraktSyncShow(
            ids: showIds,
            seasons: [TraktSyncSeason(
                number: season,
                episodes: [TraktSyncEpisode(number: episode, watchedAt: watchedAt, rating: rating)]
            )]
        )])
    }

    private enum CodingKeys: String, CodingKey { case movies, shows, episodes }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !movies.isEmpty { try container.encode(movies, forKey: .movies) }
        if !shows.isEmpty { try container.encode(shows, forKey: .shows) }
        if !episodes.isEmpty { try container.encode(episodes, forKey: .episodes) }
    }
}

public struct TraktSyncMovie: Encodable {
    public var ids: TraktScrobbleIds
    public var watchedAt: Date?
    public var rating: Int?

    public init(ids: TraktScrobbleIds, watchedAt: Date? = nil, rating: Int? = nil) {
        self.ids = ids
        self.watchedAt = watchedAt
        self.rating = rating
    }

    private enum CodingKeys: String, CodingKey {
        case ids, rating
        case watchedAt = "watched_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ids, forKey: .ids)
        try c.encodeIfPresent(watchedAt.map(traktDateString), forKey: .watchedAt)
        try c.encodeIfPresent(rating, forKey: .rating)
    }
}

public struct TraktSyncShow: Encodable {
    public var ids: TraktScrobbleIds
    /// nil or empty = the whole show.
    public var seasons: [TraktSyncSeason]?
    public var watchedAt: Date?
    public var rating: Int?

    public init(ids: TraktScrobbleIds, seasons: [TraktSyncSeason]? = nil, watchedAt: Date? = nil, rating: Int? = nil) {
        self.ids = ids
        self.seasons = seasons
        self.watchedAt = watchedAt
        self.rating = rating
    }

    private enum CodingKeys: String, CodingKey {
        case ids, seasons, rating
        case watchedAt = "watched_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ids, forKey: .ids)
        if let seasons, !seasons.isEmpty { try c.encode(seasons, forKey: .seasons) }
        try c.encodeIfPresent(watchedAt.map(traktDateString), forKey: .watchedAt)
        try c.encodeIfPresent(rating, forKey: .rating)
    }
}

public struct TraktSyncSeason: Encodable {
    public var number: Int
    /// nil or empty = the whole season.
    public var episodes: [TraktSyncEpisode]?
    public var watchedAt: Date?
    public var rating: Int?

    public init(number: Int, episodes: [TraktSyncEpisode]? = nil, watchedAt: Date? = nil, rating: Int? = nil) {
        self.number = number
        self.episodes = episodes
        self.watchedAt = watchedAt
        self.rating = rating
    }

    private enum CodingKeys: String, CodingKey {
        case number, episodes, rating
        case watchedAt = "watched_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(number, forKey: .number)
        if let episodes, !episodes.isEmpty { try c.encode(episodes, forKey: .episodes) }
        try c.encodeIfPresent(watchedAt.map(traktDateString), forKey: .watchedAt)
        try c.encodeIfPresent(rating, forKey: .rating)
    }
}

public struct TraktSyncEpisode: Encodable {
    public var number: Int
    public var watchedAt: Date?
    public var rating: Int?

    public init(number: Int, watchedAt: Date? = nil, rating: Int? = nil) {
        self.number = number
        self.watchedAt = watchedAt
        self.rating = rating
    }

    private enum CodingKeys: String, CodingKey {
        case number, rating
        case watchedAt = "watched_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(number, forKey: .number)
        try c.encodeIfPresent(watchedAt.map(traktDateString), forKey: .watchedAt)
        try c.encodeIfPresent(rating, forKey: .rating)
    }
}

public struct TraktSyncEpisodeById: Encodable {
    public var ids: TraktScrobbleIds
    public var watchedAt: Date?
    public var rating: Int?

    public init(ids: TraktScrobbleIds, watchedAt: Date? = nil, rating: Int? = nil) {
        self.ids = ids
        self.watchedAt = watchedAt
        self.rating = rating
    }

    private enum CodingKeys: String, CodingKey {
        case ids, rating
        case watchedAt = "watched_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ids, forKey: .ids)
        try c.encodeIfPresent(watchedAt.map(traktDateString), forKey: .watchedAt)
        try c.encodeIfPresent(rating, forKey: .rating)
    }
}

private func traktDateString(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

// MARK: - Sync Response

/// Response of the sync and list-item endpoints. Counts are keyed by
/// "movies", "shows", "seasons", "episodes".
public struct TraktSyncResult: Decodable {
    public let added: [String: Int]?
    public let deleted: [String: Int]?
    public let updated: [String: Int]?
    public let existing: [String: Int]?
    /// Number of submitted items Trakt couldn't match, across all buckets.
    public let notFoundCount: Int

    public var addedCount: Int { added?.values.reduce(0, +) ?? 0 }
    public var deletedCount: Int { deleted?.values.reduce(0, +) ?? 0 }
    public var existingCount: Int { existing?.values.reduce(0, +) ?? 0 }
    public var updatedCount: Int { updated?.values.reduce(0, +) ?? 0 }

    private enum CodingKeys: String, CodingKey {
        case added, deleted, updated, existing
        case notFound = "not_found"
    }

    private struct Ignored: Decodable {
        init(from decoder: Decoder) throws {}
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = try? c.decodeIfPresent([String: Int].self, forKey: .added)
        deleted = try? c.decodeIfPresent([String: Int].self, forKey: .deleted)
        updated = try? c.decodeIfPresent([String: Int].self, forKey: .updated)
        existing = try? c.decodeIfPresent([String: Int].self, forKey: .existing)
        let notFound = try? c.decodeIfPresent([String: [Ignored]].self, forKey: .notFound)
        notFoundCount = notFound?.values.reduce(0) { $0 + $1.count } ?? 0
    }
}

// MARK: - Playback Progress

/// An entry in `/sync/playback` (paused, partially watched item).
public struct TraktPlaybackItem: Decodable, Identifiable {
    /// Playback id, used to delete the entry.
    public let id: Int
    /// 0-100.
    public let progress: Double
    public let pausedAt: String?
    /// "movie" or "episode".
    public let type: String
    public let movie: TraktMovie?
    public let episode: TraktEpisode?
    public let show: TraktShow?

    private enum CodingKeys: String, CodingKey {
        case id, progress, type, movie, episode, show
        case pausedAt = "paused_at"
    }
}

// MARK: - Watched Progress

/// `/shows/{id}/progress/watched`: aired episodes and which ones the user has watched.
public struct TraktShowWatchedProgress: Decodable {
    public let aired: Int
    public let completed: Int
    public let seasons: [Season]

    public struct Season: Decodable {
        public let number: Int
        public let aired: Int
        public let completed: Int
        public let episodes: [Episode]

        private enum CodingKeys: String, CodingKey { case number, aired, completed, episodes }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            number = try c.decode(Int.self, forKey: .number)
            aired = try c.decodeIfPresent(Int.self, forKey: .aired) ?? 0
            completed = try c.decodeIfPresent(Int.self, forKey: .completed) ?? 0
            episodes = try c.decodeIfPresent([Episode].self, forKey: .episodes) ?? []
        }
    }

    public struct Episode: Decodable {
        public let number: Int
        public let completed: Bool
        public let lastWatchedAt: String?

        private enum CodingKeys: String, CodingKey {
            case number, completed
            case lastWatchedAt = "last_watched_at"
        }
    }

    private enum CodingKeys: String, CodingKey { case aired, completed, seasons }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aired = try c.decodeIfPresent(Int.self, forKey: .aired) ?? 0
        completed = try c.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        seasons = try c.decodeIfPresent([Season].self, forKey: .seasons) ?? []
    }
}

// MARK: - Comments

public enum TraktCommentSort: String, CaseIterable, Sendable {
    case newest, oldest, likes, replies, highest, lowest, plays
}

/// What to load comments for. Ids may be a Trakt id, Trakt slug or IMDb id
/// (`tt…`). TMDB ids are NOT accepted here; resolve them with `lookupByTmdb` first.
public enum TraktCommentTarget: Hashable, Sendable {
    case movie(id: String)
    case show(id: String)
    case season(showId: String, season: Int)
    case episode(showId: String, season: Int, episode: Int)

    var path: String {
        switch self {
        case .movie(let id): return "/movies/\(id)/comments"
        case .show(let id): return "/shows/\(id)/comments"
        case .season(let showId, let season): return "/shows/\(showId)/seasons/\(season)/comments"
        case .episode(let showId, let season, let episode):
            return "/shows/\(showId)/seasons/\(season)/episodes/\(episode)/comments"
        }
    }
}

public struct TraktComment: Decodable, Identifiable, Hashable {
    public let id: Int
    public let parentId: Int?
    public let createdAt: String?
    public let updatedAt: String?
    public let comment: String
    /// Comment contains spoilers; hide behind a reveal.
    public let spoiler: Bool
    /// Long-form review (200+ words).
    public let review: Bool
    public let replies: Int
    public let likes: Int
    /// The commenter's own rating of the title (1-10), if they rated it.
    public let userRating: Int?
    public let user: TraktCommentUser?

    private enum CodingKeys: String, CodingKey {
        case id, comment, spoiler, review, replies, likes, user
        case parentId = "parent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userRating = "user_rating"
        case userStats = "user_stats"
    }

    private struct UserStats: Decodable {
        let rating: Int?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        parentId = try c.decodeIfPresent(Int.self, forKey: .parentId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        comment = try c.decodeIfPresent(String.self, forKey: .comment) ?? ""
        spoiler = try c.decodeIfPresent(Bool.self, forKey: .spoiler) ?? false
        review = try c.decodeIfPresent(Bool.self, forKey: .review) ?? false
        replies = try c.decodeIfPresent(Int.self, forKey: .replies) ?? 0
        likes = try c.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        let stats = try? c.decodeIfPresent(UserStats.self, forKey: .userStats)
        userRating = stats?.rating ?? (try? c.decodeIfPresent(Int.self, forKey: .userRating)) ?? nil
        user = try? c.decodeIfPresent(TraktCommentUser.self, forKey: .user)
    }
}

public struct TraktCommentUser: Decodable, Hashable {
    public let username: String
    public let name: String?
    public let isPrivate: Bool
    public let vip: Bool
    public let slug: String?
    public let avatarURL: String?

    private enum CodingKeys: String, CodingKey {
        case username, name, vip, ids, images
        case isPrivate = "private"
    }

    private struct Ids: Decodable { let slug: String? }
    private struct Images: Decodable {
        struct Avatar: Decodable { let full: String? }
        let avatar: Avatar?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name)
        isPrivate = try c.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        vip = try c.decodeIfPresent(Bool.self, forKey: .vip) ?? false
        slug = (try? c.decodeIfPresent(Ids.self, forKey: .ids))?.slug
        avatarURL = (try? c.decodeIfPresent(Images.self, forKey: .images))?.avatar?.full
    }
}

/// One page of a paginated Trakt endpoint, with totals from the
/// `X-Pagination-*` headers.
public struct TraktPage<Item> {
    public let items: [Item]
    public let page: Int
    public let limit: Int
    public let pageCount: Int
    public let itemCount: Int

    public var hasMore: Bool { page < pageCount }
}

// MARK: - Lists

public enum TraktListPrivacy: String, Codable, CaseIterable, Sendable {
    case `private`, link, friends, `public`
}

/// A user's personal list.
public struct TraktUserList: Decodable, Identifiable, Hashable {
    /// Trakt numeric id (use with the list endpoints).
    public let id: Int
    public let slug: String?
    public let name: String
    public let description: String?
    public let privacy: String?
    public let shareLink: String?
    public let displayNumbers: Bool?
    public let allowComments: Bool?
    public let sortBy: String?
    public let sortHow: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let itemCount: Int
    public let commentCount: Int?
    public let likes: Int?

    private enum CodingKeys: String, CodingKey {
        case name, description, privacy, ids, likes
        case shareLink = "share_link"
        case displayNumbers = "display_numbers"
        case allowComments = "allow_comments"
        case sortBy = "sort_by"
        case sortHow = "sort_how"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case itemCount = "item_count"
        case commentCount = "comment_count"
    }

    private struct Ids: Decodable {
        let trakt: Int
        let slug: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ids = try c.decode(Ids.self, forKey: .ids)
        id = ids.trakt
        slug = ids.slug
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description)
        privacy = try c.decodeIfPresent(String.self, forKey: .privacy)
        shareLink = try c.decodeIfPresent(String.self, forKey: .shareLink)
        displayNumbers = try c.decodeIfPresent(Bool.self, forKey: .displayNumbers)
        allowComments = try c.decodeIfPresent(Bool.self, forKey: .allowComments)
        sortBy = try c.decodeIfPresent(String.self, forKey: .sortBy)
        sortHow = try c.decodeIfPresent(String.self, forKey: .sortHow)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        itemCount = try c.decodeIfPresent(Int.self, forKey: .itemCount) ?? 0
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount)
        likes = try c.decodeIfPresent(Int.self, forKey: .likes)
    }
}

/// An item on a personal list.
public struct TraktListEntry: Decodable, Identifiable {
    /// List item id (unique within the list).
    public let id: Int
    public let rank: Int?
    public let listedAt: String?
    public let notes: String?
    /// "movie", "show", "season", "episode" or "person".
    public let type: String
    public let movie: TraktMovie?
    public let show: TraktShow?
    public let season: TraktSeason?
    public let episode: TraktEpisode?

    private enum CodingKeys: String, CodingKey {
        case id, rank, notes, type, movie, show, season, episode
        case listedAt = "listed_at"
    }
}

// MARK: - Endpoints

extension TraktService {

    // MARK: History

    /// Adds plays to the user's history (marks watched). Requires auth.
    @discardableResult
    public func addToHistory(_ items: TraktSyncItems) async throws -> TraktSyncResult {
        try await sync(path: "/sync/history", items: items)
    }

    /// Removes all plays of the given items from history (marks unwatched). Requires auth.
    @discardableResult
    public func removeFromHistory(_ items: TraktSyncItems) async throws -> TraktSyncResult {
        try await sync(path: "/sync/history/remove", items: items)
    }

    /// Watched progress for a show: every aired episode with a `completed` flag.
    /// `showId` may be a Trakt id, slug or IMDb id. Specials excluded by default.
    /// Requires auth.
    public func getShowWatchedProgress(showId: String, includeSpecials: Bool = false) async throws -> TraktShowWatchedProgress {
        let (data, _) = try await send(
            method: "GET",
            path: "/shows/\(showId)/progress/watched",
            params: [
                "hidden": "false",
                "specials": includeSpecials ? "true" : "false",
                "count_specials": includeSpecials ? "true" : "false",
            ],
            auth: true
        )
        return try JSONDecoder().decode(TraktShowWatchedProgress.self, from: data)
    }

    /// The user's plays of one item (`type`: "movies", "shows", "seasons", "episodes";
    /// `traktId`: numeric Trakt id). Use `limit: 1` to test "already watched". Requires auth.
    public func getItemHistory(type: String, traktId: Int, limit: Int = 1) async throws -> [TraktHistoryItem] {
        let (data, _) = try await send(
            method: "GET",
            path: "/sync/history/\(type)/\(traktId)",
            params: ["limit": String(limit)],
            auth: true
        )
        return try JSONDecoder().decode([TraktHistoryItem].self, from: data)
    }

    // MARK: Ratings

    /// Rates items (each item carries its own `rating`, 1-10). Requires auth.
    @discardableResult
    public func addRatings(_ items: TraktSyncItems) async throws -> TraktSyncResult {
        try await sync(path: "/sync/ratings", items: items)
    }

    /// Removes ratings for items. Requires auth.
    @discardableResult
    public func removeRatings(_ items: TraktSyncItems) async throws -> TraktSyncResult {
        try await sync(path: "/sync/ratings/remove", items: items)
    }

    /// All of the user's ratings of one type ("movies", "shows", "seasons",
    /// "episodes"), without extended metadata (fast). Requires auth.
    public func getUserRatings(type: String) async throws -> [TraktRatingItem] {
        let (data, _) = try await send(method: "GET", path: "/sync/ratings/\(type)", auth: true)
        return try JSONDecoder().decode([TraktRatingItem].self, from: data)
    }

    // MARK: Playback Progress

    /// Paused playback entries ("movies" or "episodes"; nil for both). Requires auth.
    public func getPlaybackProgress(type: String? = nil) async throws -> [TraktPlaybackItem] {
        let path = type.map { "/sync/playback/\($0)" } ?? "/sync/playback"
        let (data, _) = try await send(method: "GET", path: path, auth: true)
        return try JSONDecoder().decode([TraktPlaybackItem].self, from: data)
    }

    /// Deletes one paused playback entry by its playback id. Requires auth.
    public func removePlaybackProgress(id: Int) async throws {
        _ = try await send(method: "DELETE", path: "/sync/playback/\(id)", auth: true)
    }

    // MARK: Comments (public)

    /// One page of comments. Works without login (client id header only).
    /// - Parameters:
    ///   - limit: page size, Trakt allows up to 100 (default 10).
    public func getComments(
        for target: TraktCommentTarget,
        sort: TraktCommentSort = .likes,
        page: Int = 1,
        limit: Int = 10
    ) async throws -> TraktPage<TraktComment> {
        let (data, response) = try await send(
            method: "GET",
            path: "\(target.path)/\(sort.rawValue)",
            params: ["page": String(page), "limit": String(limit), "extended": "full"]
        )
        let items = try JSONDecoder().decode([TraktComment].self, from: data)
        return Self.page(items, response: response, page: page, limit: limit)
    }

    /// Replies to a comment (public).
    public func getCommentReplies(commentId: Int, page: Int = 1, limit: Int = 10) async throws -> TraktPage<TraktComment> {
        let (data, response) = try await send(
            method: "GET",
            path: "/comments/\(commentId)/replies",
            params: ["page": String(page), "limit": String(limit), "extended": "full"]
        )
        let items = try JSONDecoder().decode([TraktComment].self, from: data)
        return Self.page(items, response: response, page: page, limit: limit)
    }

    // MARK: Lists

    /// The user's personal lists. Requires auth.
    public func getMyLists() async throws -> [TraktUserList] {
        let (data, _) = try await send(method: "GET", path: "/users/me/lists", auth: true)
        return try JSONDecoder().decode([TraktUserList].self, from: data)
    }

    /// Items on one of the user's lists. `type` filters to "movies", "shows",
    /// "seasons" or "episodes" (nil = all). Requires auth.
    public func getListItems(listId: Int, type: String? = nil) async throws -> [TraktListEntry] {
        var path = "/users/me/lists/\(listId)/items"
        if let type { path += "/\(type)" }
        let (data, _) = try await send(method: "GET", path: path, params: ["extended": "full"], auth: true)
        return try JSONDecoder().decode([TraktListEntry].self, from: data)
    }

    /// Creates a personal list and returns it. Requires auth.
    public func createList(
        name: String,
        description: String? = nil,
        privacy: TraktListPrivacy = .private
    ) async throws -> TraktUserList {
        struct Body: Encodable {
            let name: String
            let description: String?
            let privacy: String
        }
        let (data, _) = try await send(
            method: "POST",
            path: "/users/me/lists",
            body: Body(name: name, description: description, privacy: privacy.rawValue),
            auth: true
        )
        return try JSONDecoder().decode(TraktUserList.self, from: data)
    }

    /// Deletes a personal list. Requires auth.
    public func deleteList(listId: Int) async throws {
        _ = try await send(method: "DELETE", path: "/users/me/lists/\(listId)", auth: true)
    }

    /// Adds items to a personal list. Requires auth.
    @discardableResult
    public func addToList(listId: Int, items: TraktSyncItems) async throws -> TraktSyncResult {
        try await sync(path: "/users/me/lists/\(listId)/items", items: items)
    }

    /// Removes items from a personal list. Requires auth.
    @discardableResult
    public func removeFromList(listId: Int, items: TraktSyncItems) async throws -> TraktSyncResult {
        try await sync(path: "/users/me/lists/\(listId)/items/remove", items: items)
    }

    // MARK: Helpers

    private func sync(path: String, items: TraktSyncItems) async throws -> TraktSyncResult {
        let (data, _) = try await send(method: "POST", path: path, body: items, auth: true)
        return try JSONDecoder().decode(TraktSyncResult.self, from: data)
    }

    private static func page<Item>(_ items: [Item], response: HTTPURLResponse, page: Int, limit: Int) -> TraktPage<Item> {
        func header(_ name: String) -> Int? {
            response.value(forHTTPHeaderField: name).flatMap { Int($0) }
        }
        let resolvedPage = header("X-Pagination-Page") ?? page
        return TraktPage(
            items: items,
            page: resolvedPage,
            limit: header("X-Pagination-Limit") ?? limit,
            pageCount: header("X-Pagination-Page-Count") ?? resolvedPage,
            itemCount: header("X-Pagination-Item-Count") ?? items.count
        )
    }
}
