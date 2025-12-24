//
//  TraktService.swift
//  FlixorKit
//
//  Handles Trakt API (device code OAuth + sync features)
//  Reference: packages/core/src/services/TraktService.ts
//

import Foundation

// MARK: - Cache TTL Constants

public enum CacheTTL {
    public static let short: TimeInterval = 60 * 5          // 5 minutes
    public static let dynamic: TimeInterval = 60 * 15       // 15 minutes
    public static let trending: TimeInterval = 60 * 30      // 30 minutes
    public static let `static`: TimeInterval = 60 * 60 * 24 // 24 hours
    public static let none: TimeInterval = 0                // No caching
}

// MARK: - Trakt Models

public struct TraktTokens: Codable {
    public let accessToken: String
    public let tokenType: String
    public let expiresIn: Int
    public let refreshToken: String
    public let scope: String
    public let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case createdAt = "created_at"
    }
}

public struct TraktDeviceCode: Codable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUrl: String
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUrl = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

public struct TraktIds: Codable {
    public let trakt: Int?
    public let slug: String?
    public let imdb: String?
    public let tmdb: Int?
    public let tvdb: Int?
}

public struct TraktMovie: Codable {
    public let title: String
    public let year: Int?
    public let ids: TraktIds
    public let tagline: String?
    public let overview: String?
    public let released: String?
    public let runtime: Int?
    public let country: String?
    public let trailer: String?
    public let homepage: String?
    public let status: String?
    public let rating: Double?
    public let votes: Int?
    public let commentCount: Int?
    public let updatedAt: String?
    public let language: String?
    public let genres: [String]?
    public let certification: String?

    enum CodingKeys: String, CodingKey {
        case title, year, ids, tagline, overview, released, runtime, country
        case trailer, homepage, status, rating, votes, language, genres, certification
        case commentCount = "comment_count"
        case updatedAt = "updated_at"
    }
}

public struct TraktShow: Codable {
    public let title: String
    public let year: Int?
    public let ids: TraktIds
    public let overview: String?
    public let firstAired: String?
    public let runtime: Int?
    public let certification: String?
    public let network: String?
    public let country: String?
    public let trailer: String?
    public let homepage: String?
    public let status: String?
    public let rating: Double?
    public let votes: Int?
    public let commentCount: Int?
    public let updatedAt: String?
    public let language: String?
    public let genres: [String]?
    public let airedEpisodes: Int?

    enum CodingKeys: String, CodingKey {
        case title, year, ids, overview, runtime, certification, network, country
        case trailer, homepage, status, rating, votes, language, genres
        case firstAired = "first_aired"
        case commentCount = "comment_count"
        case updatedAt = "updated_at"
        case airedEpisodes = "aired_episodes"
    }
}

public struct TraktSeason: Codable {
    public let number: Int
    public let ids: TraktIds
    public let rating: Double?
    public let votes: Int?
    public let episodeCount: Int?
    public let airedEpisodes: Int?
    public let title: String?
    public let overview: String?
    public let firstAired: String?
    public let network: String?

    enum CodingKeys: String, CodingKey {
        case number, ids, rating, votes, title, overview, network
        case episodeCount = "episode_count"
        case airedEpisodes = "aired_episodes"
        case firstAired = "first_aired"
    }
}

public struct TraktEpisode: Codable {
    public let season: Int
    public let number: Int
    public let title: String?
    public let ids: TraktIds
    public let overview: String?
    public let rating: Double?
    public let votes: Int?
    public let commentCount: Int?
    public let firstAired: String?
    public let runtime: Int?

    enum CodingKeys: String, CodingKey {
        case season, number, title, ids, overview, rating, votes, runtime
        case commentCount = "comment_count"
        case firstAired = "first_aired"
    }
}

public struct TraktTrendingMovie: Codable {
    public let watchers: Int
    public let movie: TraktMovie
}

public struct TraktTrendingShow: Codable {
    public let watchers: Int
    public let show: TraktShow
}

public struct TraktWatchlistItem: Codable {
    public let rank: Int?
    public let listedAt: String
    public let type: String
    public let movie: TraktMovie?
    public let show: TraktShow?
    public let season: TraktSeason?
    public let episode: TraktEpisode?

    enum CodingKeys: String, CodingKey {
        case rank, type, movie, show, season, episode
        case listedAt = "listed_at"
    }
}

public struct TraktHistoryItem: Codable {
    public let id: Int
    public let watchedAt: String
    public let action: String
    public let type: String
    public let movie: TraktMovie?
    public let show: TraktShow?
    public let episode: TraktEpisode?

    enum CodingKeys: String, CodingKey {
        case id, action, type, movie, show, episode
        case watchedAt = "watched_at"
    }
}

public struct TraktUserProfile: Codable {
    public let username: String
    public let name: String?
    public let ids: TraktUserIds

    public struct TraktUserIds: Codable {
        public let slug: String?
        public let uuid: String?
    }
}

public struct TraktCollectionItem: Codable {
    public let collectedAt: String
    public let movie: TraktMovie?
    public let show: TraktShow?

    enum CodingKeys: String, CodingKey {
        case movie, show
        case collectedAt = "collected_at"
    }
}

public struct TraktRatingItem: Codable {
    public let ratedAt: String
    public let rating: Int
    public let type: String
    public let movie: TraktMovie?
    public let show: TraktShow?
    public let season: TraktSeason?
    public let episode: TraktEpisode?

    enum CodingKeys: String, CodingKey {
        case rating, type, movie, show, season, episode
        case ratedAt = "rated_at"
    }
}

public struct TraktUserIds: Codable {
    public let slug: String
    public let uuid: String?
}

public struct TraktUserImages: Codable {
    public let avatar: TraktAvatar?
}

public struct TraktAvatar: Codable {
    public let full: String?
}

public struct TraktUser: Codable {
    public let username: String
    public let `private`: Bool
    public let name: String?
    public let vip: Bool?
    public let vipEp: Bool?
    public let ids: TraktUserIds
    public let joinedAt: String?
    public let location: String?
    public let about: String?
    public let gender: String?
    public let age: Int?
    public let images: TraktUserImages?

    enum CodingKeys: String, CodingKey {
        case username, name, vip, ids, location, about, gender, age, images
        case `private` = "private"
        case vipEp = "vip_ep"
        case joinedAt = "joined_at"
    }
}

public struct TraktMovieStats: Codable {
    public let plays: Int
    public let watched: Int
    public let minutes: Int
    public let collected: Int
    public let ratings: Int
    public let comments: Int
}

public struct TraktShowStats: Codable {
    public let watched: Int
    public let collected: Int
    public let ratings: Int
    public let comments: Int
}

public struct TraktSeasonStats: Codable {
    public let ratings: Int
    public let comments: Int
}

public struct TraktEpisodeStats: Codable {
    public let plays: Int
    public let watched: Int
    public let minutes: Int
    public let collected: Int
    public let ratings: Int
    public let comments: Int
}

public struct TraktStats: Codable {
    public let movies: TraktMovieStats
    public let shows: TraktShowStats
    public let seasons: TraktSeasonStats
    public let episodes: TraktEpisodeStats
}

public struct TraktSearchMovieResult: Codable {
    public let movie: TraktMovie
}

public struct TraktSearchShowResult: Codable {
    public let show: TraktShow
}

public struct TraktLookupResult: Codable {
    public let movie: TraktMovie?
    public let show: TraktShow?
}

// MARK: - Scrobble Models

/// IDs for scrobble requests (simplified, only needs one valid ID)
public struct TraktScrobbleIds: Codable {
    public let trakt: Int?
    public let slug: String?
    public let imdb: String?
    public let tmdb: Int?
    public let tvdb: Int?

    public init(trakt: Int? = nil, slug: String? = nil, imdb: String? = nil, tmdb: Int? = nil, tvdb: Int? = nil) {
        self.trakt = trakt
        self.slug = slug
        self.imdb = imdb
        self.tmdb = tmdb
        self.tvdb = tvdb
    }
}

/// Movie info for scrobble
public struct TraktScrobbleMovie: Codable {
    public let title: String?
    public let year: Int?
    public let ids: TraktScrobbleIds

    public init(title: String? = nil, year: Int? = nil, ids: TraktScrobbleIds) {
        self.title = title
        self.year = year
        self.ids = ids
    }
}

/// Show info for scrobble
public struct TraktScrobbleShow: Codable {
    public let title: String?
    public let year: Int?
    public let ids: TraktScrobbleIds

    public init(title: String? = nil, year: Int? = nil, ids: TraktScrobbleIds) {
        self.title = title
        self.year = year
        self.ids = ids
    }
}

/// Episode info for scrobble
public struct TraktScrobbleEpisode: Codable {
    public let season: Int
    public let number: Int
    public let title: String?
    public let ids: TraktScrobbleIds?

    public init(season: Int, number: Int, title: String? = nil, ids: TraktScrobbleIds? = nil) {
        self.season = season
        self.number = number
        self.title = title
        self.ids = ids
    }
}

/// Request body for scrobble API calls
public struct TraktScrobbleRequest: Encodable {
    public let movie: TraktScrobbleMovie?
    public let show: TraktScrobbleShow?
    public let episode: TraktScrobbleEpisode?
    public let progress: Double
    public let appVersion: String
    public let appDate: String

    enum CodingKeys: String, CodingKey {
        case movie, show, episode, progress
        case appVersion = "app_version"
        case appDate = "app_date"
    }

    public init(movie: TraktScrobbleMovie, progress: Double) {
        self.movie = movie
        self.show = nil
        self.episode = nil
        self.progress = progress
        self.appVersion = "1.0.0"
        self.appDate = ISO8601DateFormatter().string(from: Date())
    }

    public init(show: TraktScrobbleShow, episode: TraktScrobbleEpisode, progress: Double) {
        self.movie = nil
        self.show = show
        self.episode = episode
        self.progress = progress
        self.appVersion = "1.0.0"
        self.appDate = ISO8601DateFormatter().string(from: Date())
    }
}

/// Response from scrobble API
public struct TraktScrobbleResponse: Decodable {
    public let id: Int?
    public let action: String  // "start", "pause", "stop", "scrobble" (when >80%)
    public let progress: Double
    public let sharing: TraktScrobbleSharing?
    public let movie: TraktMovie?
    public let show: TraktShow?
    public let episode: TraktEpisode?
}

public struct TraktScrobbleSharing: Decodable {
    public let twitter: Bool?
    public let mastodon: Bool?
    public let tumblr: Bool?
}

// MARK: - TraktService

public class TraktService {
    private let clientId: String
    private let clientSecret: String
    private var tokens: TraktTokens?

    private let traktApiUrl = "https://api.trakt.tv"

    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    // MARK: - Headers

    private func getHeaders(includeAuth: Bool = false) -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "trakt-api-version": "2",
            "trakt-api-key": clientId
        ]

        if includeAuth, let accessToken = tokens?.accessToken {
            headers["Authorization"] = "Bearer \(accessToken)"
        }

        return headers
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(
        path: String,
        params: [String: String]? = nil,
        auth: Bool = false
    ) async throws -> T {
        var components = URLComponents(string: "\(traktApiUrl)\(path)")
        if let params = params {
            components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = components?.url else {
            throw TraktError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders(includeAuth: auth) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraktError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            if auth, tokens?.refreshToken != nil {
                try await refreshTokens()
                return try await get(path: path, params: params, auth: auth)
            }
            throw TraktError.authenticationRequired
        }

        guard httpResponse.statusCode == 200 else {
            throw TraktError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(
        path: String,
        body: Encodable? = nil,
        auth: Bool = false
    ) async throws -> T {
        guard let url = URL(string: "\(traktApiUrl)\(path)") else {
            throw TraktError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        for (key, value) in getHeaders(includeAuth: auth) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraktError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TraktError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postNoResponse(
        path: String,
        body: Encodable? = nil,
        auth: Bool = false
    ) async throws {
        guard let url = URL(string: "\(traktApiUrl)\(path)") else {
            throw TraktError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        for (key, value) in getHeaders(includeAuth: auth) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraktError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw TraktError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Authentication

    /// Set tokens from external source (e.g., SecureStorage)
    public func setTokens(_ tokens: TraktTokens?) {
        self.tokens = tokens
    }

    /// Get current tokens
    public func getTokens() -> TraktTokens? {
        return tokens
    }

    /// Check if authenticated
    public var isAuthenticated: Bool {
        return tokens != nil
    }

    /// Check if tokens are expired
    public func areTokensExpired() -> Bool {
        guard let tokens = tokens else { return true }
        let expiresAt = TimeInterval(tokens.createdAt + tokens.expiresIn)
        return Date().timeIntervalSince1970 > expiresAt
    }

    /// Generate device code for authentication
    public func generateDeviceCode() async throws -> TraktDeviceCode {
        struct DeviceCodeRequest: Encodable {
            let clientId: String

            enum CodingKeys: String, CodingKey {
                case clientId = "client_id"
            }
        }

        return try await post(
            path: "/oauth/device/code",
            body: DeviceCodeRequest(clientId: clientId)
        )
    }

    /// Poll for device code authorization
    public func pollDeviceCode(_ deviceCode: String) async throws -> TraktTokens? {
        struct PollRequest: Encodable {
            let code: String
            let clientId: String
            let clientSecret: String

            enum CodingKeys: String, CodingKey {
                case code
                case clientId = "client_id"
                case clientSecret = "client_secret"
            }
        }

        do {
            let tokens: TraktTokens = try await post(
                path: "/oauth/device/token",
                body: PollRequest(
                    code: deviceCode,
                    clientId: clientId,
                    clientSecret: clientSecret
                )
            )
            self.tokens = tokens
            return tokens
        } catch TraktError.httpError(let statusCode) where statusCode == 400 {
            // Still waiting for authorization
            return nil
        }
    }

    /// Wait for device code authorization with polling
    public func waitForDeviceCode(
        _ deviceCode: TraktDeviceCode,
        onPoll: (() -> Void)? = nil
    ) async throws -> TraktTokens {
        let startTime = Date()
        let expiresAt = startTime.addingTimeInterval(TimeInterval(deviceCode.expiresIn))

        while Date() < expiresAt {
            onPoll?()

            if let tokens = try await pollDeviceCode(deviceCode.deviceCode) {
                return tokens
            }

            try await Task.sleep(nanoseconds: UInt64(deviceCode.interval) * 1_000_000_000)
        }

        throw TraktError.deviceCodeTimeout
    }

    /// Refresh access tokens
    public func refreshTokens() async throws {
        guard let refreshToken = tokens?.refreshToken else {
            throw TraktError.noRefreshToken
        }

        struct RefreshRequest: Encodable {
            let refreshToken: String
            let clientId: String
            let clientSecret: String
            let redirectUri: String
            let grantType: String

            enum CodingKeys: String, CodingKey {
                case refreshToken = "refresh_token"
                case clientId = "client_id"
                case clientSecret = "client_secret"
                case redirectUri = "redirect_uri"
                case grantType = "grant_type"
            }
        }

        let newTokens: TraktTokens = try await post(
            path: "/oauth/token",
            body: RefreshRequest(
                refreshToken: refreshToken,
                clientId: clientId,
                clientSecret: clientSecret,
                redirectUri: "urn:ietf:wg:oauth:2.0:oob",
                grantType: "refresh_token"
            )
        )

        self.tokens = newTokens
    }

    /// Sign out - revoke tokens
    public func signOut() async {
        guard let accessToken = tokens?.accessToken else { return }

        struct RevokeRequest: Encodable {
            let token: String
            let clientId: String
            let clientSecret: String

            enum CodingKeys: String, CodingKey {
                case token
                case clientId = "client_id"
                case clientSecret = "client_secret"
            }
        }

        try? await postNoResponse(
            path: "/oauth/revoke",
            body: RevokeRequest(
                token: accessToken,
                clientId: clientId,
                clientSecret: clientSecret
            )
        )

        tokens = nil
    }

    // MARK: - User

    /// Get authenticated user profile
    public func getProfile() async throws -> TraktUser {
        return try await get(path: "/users/me", auth: true)
    }

    /// Get user stats
    public func getStats() async throws -> TraktStats {
        return try await get(path: "/users/me/stats", auth: true)
    }

    // MARK: - Trending & Popular

    /// Get trending movies
    public func getTrendingMovies(page: Int = 1, limit: Int = 20) async throws -> [TraktTrendingMovie] {
        return try await get(
            path: "/movies/trending",
            params: ["page": String(page), "limit": String(limit), "extended": "full"]
        )
    }

    /// Get trending shows
    public func getTrendingShows(page: Int = 1, limit: Int = 20) async throws -> [TraktTrendingShow] {
        return try await get(
            path: "/shows/trending",
            params: ["page": String(page), "limit": String(limit), "extended": "full"]
        )
    }

    /// Get popular movies
    public func getPopularMovies(page: Int = 1, limit: Int = 20) async throws -> [TraktMovie] {
        return try await get(
            path: "/movies/popular",
            params: ["page": String(page), "limit": String(limit), "extended": "full"]
        )
    }

    /// Get popular shows
    public func getPopularShows(page: Int = 1, limit: Int = 20) async throws -> [TraktShow] {
        return try await get(
            path: "/shows/popular",
            params: ["page": String(page), "limit": String(limit), "extended": "full"]
        )
    }

    /// Get recommended movies (personalized)
    public func getRecommendedMovies(page: Int = 1, limit: Int = 20) async throws -> [TraktMovie] {
        return try await get(
            path: "/recommendations/movies",
            params: ["page": String(page), "limit": String(limit), "extended": "full"],
            auth: true
        )
    }

    /// Get recommended shows (personalized)
    public func getRecommendedShows(page: Int = 1, limit: Int = 20) async throws -> [TraktShow] {
        return try await get(
            path: "/recommendations/shows",
            params: ["page": String(page), "limit": String(limit), "extended": "full"],
            auth: true
        )
    }

    // MARK: - User Profile

    /// Get current user's profile
    public func getUserProfile() async throws -> TraktUserProfile {
        return try await get(path: "/users/me", params: [:], auth: true)
    }

    // MARK: - Watchlist

    /// Get user's watchlist
    public func getWatchlist(type: String? = nil) async throws -> [TraktWatchlistItem] {
        let path = type != nil ? "/users/me/watchlist/\(type!)" : "/users/me/watchlist"
        return try await get(path: path, params: ["extended": "full"], auth: true)
    }

    /// Add movie to watchlist
    public func addMovieToWatchlist(tmdbId: Int? = nil, imdbId: String? = nil) async throws {
        struct WatchlistRequest: Encodable {
            let movies: [[String: [String: Any]]]

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                var moviesContainer = container.nestedUnkeyedContainer(forKey: .movies)
                for movie in movies {
                    var movieContainer = moviesContainer.nestedContainer(keyedBy: MovieKeys.self)
                    if let ids = movie["ids"] {
                        var idsContainer = movieContainer.nestedContainer(keyedBy: IdsKeys.self, forKey: .ids)
                        if let tmdb = ids["tmdb"] as? Int {
                            try idsContainer.encode(tmdb, forKey: .tmdb)
                        }
                        if let imdb = ids["imdb"] as? String {
                            try idsContainer.encode(imdb, forKey: .imdb)
                        }
                    }
                }
            }

            enum CodingKeys: String, CodingKey { case movies }
            enum MovieKeys: String, CodingKey { case ids }
            enum IdsKeys: String, CodingKey { case tmdb, imdb }
        }

        var ids: [String: Any] = [:]
        if let tmdbId = tmdbId { ids["tmdb"] = tmdbId }
        if let imdbId = imdbId { ids["imdb"] = imdbId }

        try await postNoResponse(
            path: "/sync/watchlist",
            body: WatchlistRequest(movies: [["ids": ids]]),
            auth: true
        )
    }

    /// Add show to watchlist
    public func addShowToWatchlist(tmdbId: Int? = nil, imdbId: String? = nil) async throws {
        struct WatchlistRequest: Encodable {
            let shows: [[String: [String: Any]]]

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                var showsContainer = container.nestedUnkeyedContainer(forKey: .shows)
                for show in shows {
                    var showContainer = showsContainer.nestedContainer(keyedBy: ShowKeys.self)
                    if let ids = show["ids"] {
                        var idsContainer = showContainer.nestedContainer(keyedBy: IdsKeys.self, forKey: .ids)
                        if let tmdb = ids["tmdb"] as? Int {
                            try idsContainer.encode(tmdb, forKey: .tmdb)
                        }
                        if let imdb = ids["imdb"] as? String {
                            try idsContainer.encode(imdb, forKey: .imdb)
                        }
                    }
                }
            }

            enum CodingKeys: String, CodingKey { case shows }
            enum ShowKeys: String, CodingKey { case ids }
            enum IdsKeys: String, CodingKey { case tmdb, imdb }
        }

        var ids: [String: Any] = [:]
        if let tmdbId = tmdbId { ids["tmdb"] = tmdbId }
        if let imdbId = imdbId { ids["imdb"] = imdbId }

        try await postNoResponse(
            path: "/sync/watchlist",
            body: WatchlistRequest(shows: [["ids": ids]]),
            auth: true
        )
    }

    /// Add item to watchlist (convenience method)
    public func addToWatchlist(tmdbId: Int, type: String) async throws {
        if type == "movie" || type == "movies" {
            try await addMovieToWatchlist(tmdbId: tmdbId)
        } else {
            try await addShowToWatchlist(tmdbId: tmdbId)
        }
    }

    /// Remove movie from watchlist
    public func removeMovieFromWatchlist(tmdbId: Int? = nil, imdbId: String? = nil) async throws {
        struct RemoveRequest: Encodable {
            let movies: [[String: [String: Any]]]

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                var moviesContainer = container.nestedUnkeyedContainer(forKey: .movies)
                for movie in movies {
                    var movieContainer = moviesContainer.nestedContainer(keyedBy: MovieKeys.self)
                    if let ids = movie["ids"] {
                        var idsContainer = movieContainer.nestedContainer(keyedBy: IdsKeys.self, forKey: .ids)
                        if let tmdb = ids["tmdb"] as? Int {
                            try idsContainer.encode(tmdb, forKey: .tmdb)
                        }
                        if let imdb = ids["imdb"] as? String {
                            try idsContainer.encode(imdb, forKey: .imdb)
                        }
                    }
                }
            }

            enum CodingKeys: String, CodingKey { case movies }
            enum MovieKeys: String, CodingKey { case ids }
            enum IdsKeys: String, CodingKey { case tmdb, imdb }
        }

        var ids: [String: Any] = [:]
        if let tmdbId = tmdbId { ids["tmdb"] = tmdbId }
        if let imdbId = imdbId { ids["imdb"] = imdbId }

        try await postNoResponse(
            path: "/sync/watchlist/remove",
            body: RemoveRequest(movies: [["ids": ids]]),
            auth: true
        )
    }

    /// Remove show from watchlist
    public func removeShowFromWatchlist(tmdbId: Int? = nil, imdbId: String? = nil) async throws {
        struct RemoveRequest: Encodable {
            let shows: [[String: [String: Any]]]

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                var showsContainer = container.nestedUnkeyedContainer(forKey: .shows)
                for show in shows {
                    var showContainer = showsContainer.nestedContainer(keyedBy: ShowKeys.self)
                    if let ids = show["ids"] {
                        var idsContainer = showContainer.nestedContainer(keyedBy: IdsKeys.self, forKey: .ids)
                        if let tmdb = ids["tmdb"] as? Int {
                            try idsContainer.encode(tmdb, forKey: .tmdb)
                        }
                        if let imdb = ids["imdb"] as? String {
                            try idsContainer.encode(imdb, forKey: .imdb)
                        }
                    }
                }
            }

            enum CodingKeys: String, CodingKey { case shows }
            enum ShowKeys: String, CodingKey { case ids }
            enum IdsKeys: String, CodingKey { case tmdb, imdb }
        }

        var ids: [String: Any] = [:]
        if let tmdbId = tmdbId { ids["tmdb"] = tmdbId }
        if let imdbId = imdbId { ids["imdb"] = imdbId }

        try await postNoResponse(
            path: "/sync/watchlist/remove",
            body: RemoveRequest(shows: [["ids": ids]]),
            auth: true
        )
    }

    // MARK: - History / Watched

    /// Get watch history
    public func getHistory(type: String? = nil, page: Int = 1, limit: Int = 20) async throws -> [TraktHistoryItem] {
        let path = type != nil ? "/users/me/history/\(type!)" : "/users/me/history"
        return try await get(
            path: path,
            params: ["page": String(page), "limit": String(limit), "extended": "full"],
            auth: true
        )
    }

    /// Mark movie as watched
    public func markMovieWatched(tmdbId: Int? = nil, imdbId: String? = nil, watchedAt: Date? = nil) async throws {
        let dateString = (watchedAt ?? Date()).ISO8601Format()

        struct WatchedRequest: Encodable {
            struct Movie: Encodable {
                struct Ids: Encodable {
                    let tmdb: Int?
                    let imdb: String?
                }
                let ids: Ids
                let watchedAt: String

                enum CodingKeys: String, CodingKey {
                    case ids
                    case watchedAt = "watched_at"
                }
            }
            let movies: [Movie]
        }

        try await postNoResponse(
            path: "/sync/history",
            body: WatchedRequest(movies: [
                WatchedRequest.Movie(
                    ids: WatchedRequest.Movie.Ids(tmdb: tmdbId, imdb: imdbId),
                    watchedAt: dateString
                )
            ]),
            auth: true
        )
    }

    /// Mark episode as watched
    public func markEpisodeWatched(
        showTmdbId: Int? = nil,
        showImdbId: String? = nil,
        season: Int,
        episode: Int,
        watchedAt: Date? = nil
    ) async throws {
        let dateString = (watchedAt ?? Date()).ISO8601Format()

        struct WatchedRequest: Encodable {
            struct Show: Encodable {
                struct Ids: Encodable {
                    let tmdb: Int?
                    let imdb: String?
                }
                struct Season: Encodable {
                    struct Episode: Encodable {
                        let number: Int
                        let watchedAt: String

                        enum CodingKeys: String, CodingKey {
                            case number
                            case watchedAt = "watched_at"
                        }
                    }
                    let number: Int
                    let episodes: [Episode]
                }
                let ids: Ids
                let seasons: [Season]
            }
            let shows: [Show]
        }

        try await postNoResponse(
            path: "/sync/history",
            body: WatchedRequest(shows: [
                WatchedRequest.Show(
                    ids: WatchedRequest.Show.Ids(tmdb: showTmdbId, imdb: showImdbId),
                    seasons: [
                        WatchedRequest.Show.Season(
                            number: season,
                            episodes: [
                                WatchedRequest.Show.Season.Episode(number: episode, watchedAt: dateString)
                            ]
                        )
                    ]
                )
            ]),
            auth: true
        )
    }

    // MARK: - Collection

    /// Get user's collection
    public func getCollection(type: String) async throws -> [TraktCollectionItem] {
        return try await get(
            path: "/users/me/collection/\(type)",
            params: ["extended": "full"],
            auth: true
        )
    }

    // MARK: - Ratings

    /// Get user's ratings
    public func getRatings(type: String? = nil) async throws -> [TraktRatingItem] {
        let path = type != nil ? "/users/me/ratings/\(type!)" : "/users/me/ratings"
        return try await get(path: path, params: ["extended": "full"], auth: true)
    }

    /// Rate a movie
    public func rateMovie(tmdbId: Int? = nil, imdbId: String? = nil, rating: Int) async throws {
        struct RatingRequest: Encodable {
            struct Movie: Encodable {
                struct Ids: Encodable {
                    let tmdb: Int?
                    let imdb: String?
                }
                let ids: Ids
                let rating: Int
            }
            let movies: [Movie]
        }

        try await postNoResponse(
            path: "/sync/ratings",
            body: RatingRequest(movies: [
                RatingRequest.Movie(
                    ids: RatingRequest.Movie.Ids(tmdb: tmdbId, imdb: imdbId),
                    rating: rating
                )
            ]),
            auth: true
        )
    }

    /// Rate a show
    public func rateShow(tmdbId: Int? = nil, imdbId: String? = nil, rating: Int) async throws {
        struct RatingRequest: Encodable {
            struct Show: Encodable {
                struct Ids: Encodable {
                    let tmdb: Int?
                    let imdb: String?
                }
                let ids: Ids
                let rating: Int
            }
            let shows: [Show]
        }

        try await postNoResponse(
            path: "/sync/ratings",
            body: RatingRequest(shows: [
                RatingRequest.Show(
                    ids: RatingRequest.Show.Ids(tmdb: tmdbId, imdb: imdbId),
                    rating: rating
                )
            ]),
            auth: true
        )
    }

    // MARK: - Metadata Lookup

    /// Get movie by ID
    public func getMovie(id: String) async throws -> TraktMovie {
        return try await get(path: "/movies/\(id)", params: ["extended": "full"])
    }

    /// Get show by ID
    public func getShow(id: String) async throws -> TraktShow {
        return try await get(path: "/shows/\(id)", params: ["extended": "full"])
    }

    /// Get show seasons
    public func getSeasons(showId: String) async throws -> [TraktSeason] {
        return try await get(path: "/shows/\(showId)/seasons", params: ["extended": "full"])
    }

    /// Get season episodes
    public func getSeasonEpisodes(showId: String, seasonNumber: Int) async throws -> [TraktEpisode] {
        return try await get(
            path: "/shows/\(showId)/seasons/\(seasonNumber)",
            params: ["extended": "full"]
        )
    }

    // MARK: - Search

    /// Search for movies
    public func searchMovies(query: String, page: Int = 1, limit: Int = 20) async throws -> [TraktSearchMovieResult] {
        return try await get(
            path: "/search/movie",
            params: ["query": query, "page": String(page), "limit": String(limit), "extended": "full"]
        )
    }

    /// Search for shows
    public func searchShows(query: String, page: Int = 1, limit: Int = 20) async throws -> [TraktSearchShowResult] {
        return try await get(
            path: "/search/show",
            params: ["query": query, "page": String(page), "limit": String(limit), "extended": "full"]
        )
    }

    /// Lookup by IMDB ID
    public func lookupByImdb(imdbId: String, type: String) async throws -> TraktLookupResult? {
        let results: [TraktLookupResult] = try await get(
            path: "/search/imdb/\(imdbId)",
            params: ["type": type, "extended": "full"]
        )
        return results.first
    }

    /// Lookup by TMDB ID
    public func lookupByTmdb(tmdbId: Int, type: String) async throws -> TraktLookupResult? {
        let results: [TraktLookupResult] = try await get(
            path: "/search/tmdb/\(tmdbId)",
            params: ["type": type, "extended": "full"]
        )
        return results.first
    }

    // MARK: - Scrobbling

    /// Start scrobbling a movie
    /// Call when playback starts or resumes
    public func scrobbleStart(movie: TraktScrobbleMovie, progress: Double) async throws -> TraktScrobbleResponse {
        print("📺 [Trakt] Scrobble START movie: \(movie.title ?? "unknown") at \(Int(progress))%")
        let request = TraktScrobbleRequest(movie: movie, progress: progress)
        return try await post(path: "/scrobble/start", body: request, auth: true)
    }

    /// Start scrobbling a TV episode
    /// Call when playback starts or resumes
    public func scrobbleStart(show: TraktScrobbleShow, episode: TraktScrobbleEpisode, progress: Double) async throws -> TraktScrobbleResponse {
        print("📺 [Trakt] Scrobble START episode: \(show.title ?? "unknown") S\(episode.season)E\(episode.number) at \(Int(progress))%")
        let request = TraktScrobbleRequest(show: show, episode: episode, progress: progress)
        return try await post(path: "/scrobble/start", body: request, auth: true)
    }

    /// Pause scrobbling a movie
    /// Call when playback is paused
    public func scrobblePause(movie: TraktScrobbleMovie, progress: Double) async throws -> TraktScrobbleResponse {
        print("⏸️ [Trakt] Scrobble PAUSE movie: \(movie.title ?? "unknown") at \(Int(progress))%")
        let request = TraktScrobbleRequest(movie: movie, progress: progress)
        return try await post(path: "/scrobble/pause", body: request, auth: true)
    }

    /// Pause scrobbling a TV episode
    /// Call when playback is paused
    public func scrobblePause(show: TraktScrobbleShow, episode: TraktScrobbleEpisode, progress: Double) async throws -> TraktScrobbleResponse {
        print("⏸️ [Trakt] Scrobble PAUSE episode: \(show.title ?? "unknown") S\(episode.season)E\(episode.number) at \(Int(progress))%")
        let request = TraktScrobbleRequest(show: show, episode: episode, progress: progress)
        return try await post(path: "/scrobble/pause", body: request, auth: true)
    }

    /// Stop scrobbling a movie
    /// Call when playback stops. If progress >= 80%, Trakt marks as watched
    public func scrobbleStop(movie: TraktScrobbleMovie, progress: Double) async throws -> TraktScrobbleResponse {
        print("⏹️ [Trakt] Scrobble STOP movie: \(movie.title ?? "unknown") at \(Int(progress))%")
        let request = TraktScrobbleRequest(movie: movie, progress: progress)
        return try await post(path: "/scrobble/stop", body: request, auth: true)
    }

    /// Stop scrobbling a TV episode
    /// Call when playback stops. If progress >= 80%, Trakt marks as watched
    public func scrobbleStop(show: TraktScrobbleShow, episode: TraktScrobbleEpisode, progress: Double) async throws -> TraktScrobbleResponse {
        print("⏹️ [Trakt] Scrobble STOP episode: \(show.title ?? "unknown") S\(episode.season)E\(episode.number) at \(Int(progress))%")
        let request = TraktScrobbleRequest(show: show, episode: episode, progress: progress)
        return try await post(path: "/scrobble/stop", body: request, auth: true)
    }
}

// MARK: - Errors

public enum TraktError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case authenticationRequired
    case noRefreshToken
    case deviceCodeTimeout

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .authenticationRequired:
            return "Authentication required"
        case .noRefreshToken:
            return "No refresh token available"
        case .deviceCodeTimeout:
            return "Device code authorization timed out"
        }
    }
}
