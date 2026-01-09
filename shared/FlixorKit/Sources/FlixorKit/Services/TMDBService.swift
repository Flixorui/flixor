//
//  TMDBService.swift
//  FlixorKit
//
//  Handles TMDB API calls
//  Reference: packages/core/src/services/TMDBService.ts
//

import Foundation

// MARK: - TMDBService

public class TMDBService {
    private let apiKey: String
    private let cache: CacheManager
    private let language: String

    private let baseUrl = "https://api.themoviedb.org/3"
    private let imageBaseUrl = "https://image.tmdb.org/t/p"

    public init(apiKey: String, cache: CacheManager, language: String = "en-US") {
        self.apiKey = apiKey
        self.cache = cache
        self.language = language
    }

    // MARK: - Generic Request

    private func get<T: Codable>(
        path: String,
        params: [String: String]? = nil,
        ttl: TimeInterval = CacheTTL.trending
    ) async throws -> T {
        var queryParams: [String: String] = [
            "api_key": apiKey,
            "language": language
        ]

        if let params = params {
            for (key, value) in params {
                queryParams[key] = value
            }
        }

        let queryString = queryParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }.joined(separator: "&")
        let urlString = "\(baseUrl)\(path)?\(queryString)"
        let cacheKey = "tmdb:\(urlString)"

        // Check cache first
        if ttl > 0 {
            if let cached: T = await cache.get(cacheKey) {
                return cached
            }
        }

        guard let url = URL(string: urlString) else {
            throw TMDBError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw TMDBError.httpError(statusCode: httpResponse.statusCode)
        }

        let result = try JSONDecoder().decode(T.self, from: data)

        // Cache the response
        if ttl > 0 {
            await cache.set(cacheKey, value: result, ttl: ttl)
        }

        return result
    }

    // MARK: - Image URLs

    /// Get poster URL
    public func getPosterUrl(path: String?, size: String = "w500") -> String? {
        guard let path = path, !path.isEmpty else { return nil }
        return "\(imageBaseUrl)/\(size)\(path)"
    }

    /// Get backdrop URL
    public func getBackdropUrl(path: String?, size: String = "w1280") -> String? {
        guard let path = path, !path.isEmpty else { return nil }
        return "\(imageBaseUrl)/\(size)\(path)"
    }

    /// Get profile URL (for cast/crew)
    public func getProfileUrl(path: String?, size: String = "w185") -> String? {
        guard let path = path, !path.isEmpty else { return nil }
        return "\(imageBaseUrl)/\(size)\(path)"
    }

    // MARK: - Movies

    /// Get movie details
    public func getMovieDetails(id: Int) async throws -> TMDBMovieDetails {
        return try await get(
            path: "/movie/\(id)",
            params: ["append_to_response": "external_ids"],
            ttl: CacheTTL.trending
        )
    }

    /// Get movie credits (cast & crew)
    public func getMovieCredits(id: Int) async throws -> TMDBCredits {
        return try await get(path: "/movie/\(id)/credits", ttl: CacheTTL.trending)
    }

    /// Get movie external IDs (IMDB, etc.)
    public func getMovieExternalIds(id: Int) async throws -> TMDBExternalIds {
        return try await get(path: "/movie/\(id)/external_ids", ttl: CacheTTL.`static`)
    }

    /// Get movie images
    public func getMovieImages(id: Int) async throws -> TMDBImages {
        return try await get(
            path: "/movie/\(id)/images",
            params: ["include_image_language": "en,null"],
            ttl: CacheTTL.trending
        )
    }

    /// Get similar movies
    public func getSimilarMovies(id: Int, page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/movie/\(id)/similar",
            params: ["page": String(page)],
            ttl: CacheTTL.trending
        )
    }

    /// Get movie recommendations
    public func getMovieRecommendations(id: Int, page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/movie/\(id)/recommendations",
            params: ["page": String(page)],
            ttl: CacheTTL.trending
        )
    }

    /// Get movie videos (trailers, teasers, etc.)
    public func getMovieVideos(id: Int) async throws -> TMDBVideosResponse {
        return try await get(path: "/movie/\(id)/videos", ttl: CacheTTL.trending)
    }

    // MARK: - TV Shows

    /// Get TV show details
    public func getTVDetails(id: Int) async throws -> TMDBTVDetails {
        return try await get(
            path: "/tv/\(id)",
            params: ["append_to_response": "external_ids"],
            ttl: CacheTTL.trending
        )
    }

    /// Get TV show credits
    public func getTVCredits(id: Int) async throws -> TMDBCredits {
        return try await get(path: "/tv/\(id)/credits", ttl: CacheTTL.trending)
    }

    /// Get TV external IDs
    public func getTVExternalIds(id: Int) async throws -> TMDBExternalIds {
        return try await get(path: "/tv/\(id)/external_ids", ttl: CacheTTL.`static`)
    }

    /// Get TV images
    public func getTVImages(id: Int) async throws -> TMDBImages {
        return try await get(
            path: "/tv/\(id)/images",
            params: ["include_image_language": "en,null"],
            ttl: CacheTTL.trending
        )
    }

    /// Get similar TV shows
    public func getSimilarTV(id: Int, page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/tv/\(id)/similar",
            params: ["page": String(page)],
            ttl: CacheTTL.trending
        )
    }

    /// Get TV recommendations
    public func getTVRecommendations(id: Int, page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/tv/\(id)/recommendations",
            params: ["page": String(page)],
            ttl: CacheTTL.trending
        )
    }

    /// Get TV videos (trailers, teasers, etc.)
    public func getTVVideos(id: Int) async throws -> TMDBVideosResponse {
        return try await get(path: "/tv/\(id)/videos", ttl: CacheTTL.trending)
    }

    /// Get season details
    public func getSeasonDetails(tvId: Int, seasonNumber: Int) async throws -> TMDBSeason {
        return try await get(path: "/tv/\(tvId)/season/\(seasonNumber)", ttl: CacheTTL.dynamic)
    }

    /// Get episode details (includes guest_stars and crew)
    public func getEpisodeDetails(tvId: Int, seasonNumber: Int, episodeNumber: Int) async throws -> TMDBEpisodeDetails {
        return try await get(path: "/tv/\(tvId)/season/\(seasonNumber)/episode/\(episodeNumber)", ttl: CacheTTL.dynamic)
    }

    // MARK: - Generic Media

    /// Get images for movie or TV
    public func getImages(mediaType: String, id: Int) async throws -> TMDBImages {
        return try await get(
            path: "/\(mediaType)/\(id)/images",
            params: ["include_image_language": "en,null"],
            ttl: CacheTTL.trending
        )
    }

    /// Get external IDs for movie or TV
    public func getExternalIds(mediaType: String, id: Int) async throws -> TMDBExternalIds {
        return try await get(path: "/\(mediaType)/\(id)/external_ids", ttl: CacheTTL.`static`)
    }

    // MARK: - Discover & Trending

    /// Get trending movies
    public func getTrendingMovies(timeWindow: String = "week", page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/trending/movie/\(timeWindow)",
            params: ["page": String(page)],
            ttl: CacheTTL.trending
        )
    }

    /// Get trending TV shows
    public func getTrendingTV(timeWindow: String = "week", page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/trending/tv/\(timeWindow)",
            params: ["page": String(page)],
            ttl: CacheTTL.trending
        )
    }

    /// Get trending all (movies + TV)
    public func getTrendingAll(timeWindow: String = "week", page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/trending/all/\(timeWindow)",
            params: ["page": String(page)],
            ttl: CacheTTL.trending
        )
    }

    /// Get popular movies
    public func getPopularMovies(page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(path: "/movie/popular", params: ["page": String(page)], ttl: CacheTTL.trending)
    }

    /// Get popular TV shows
    public func getPopularTV(page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(path: "/tv/popular", params: ["page": String(page)], ttl: CacheTTL.trending)
    }

    /// Get top rated movies
    public func getTopRatedMovies(page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(path: "/movie/top_rated", params: ["page": String(page)], ttl: CacheTTL.trending)
    }

    /// Get top rated TV shows
    public func getTopRatedTV(page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(path: "/tv/top_rated", params: ["page": String(page)], ttl: CacheTTL.trending)
    }

    /// Get upcoming movies
    public func getUpcomingMovies(region: String? = nil, page: Int = 1) async throws -> TMDBResultsResponse {
        var params: [String: String] = ["page": String(page)]
        if let region = region {
            params["region"] = region
        }
        return try await get(path: "/movie/upcoming", params: params, ttl: CacheTTL.trending)
    }

    // MARK: - Discover

    /// Discover movies by genre and other filters
    public func discoverMovies(withGenres: String? = nil, sortBy: String = "popularity.desc", page: Int = 1) async throws -> TMDBResultsResponse {
        var params: [String: String] = [
            "sort_by": sortBy,
            "page": String(page)
        ]
        if let genres = withGenres {
            params["with_genres"] = genres
        }
        return try await get(path: "/discover/movie", params: params, ttl: CacheTTL.trending)
    }

    /// Discover TV shows by genre and other filters
    public func discoverTV(withGenres: String? = nil, sortBy: String = "popularity.desc", page: Int = 1) async throws -> TMDBResultsResponse {
        var params: [String: String] = [
            "sort_by": sortBy,
            "page": String(page)
        ]
        if let genres = withGenres {
            params["with_genres"] = genres
        }
        return try await get(path: "/discover/tv", params: params, ttl: CacheTTL.trending)
    }

    // MARK: - Search

    /// Search for movies, TV shows, and people
    public func searchMulti(query: String, page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/search/multi",
            params: ["query": query, "page": String(page)],
            ttl: CacheTTL.short
        )
    }

    /// Search for movies
    public func searchMovies(query: String, page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/search/movie",
            params: ["query": query, "page": String(page)],
            ttl: CacheTTL.short
        )
    }

    /// Search for TV shows
    public func searchTV(query: String, page: Int = 1) async throws -> TMDBResultsResponse {
        return try await get(
            path: "/search/tv",
            params: ["query": query, "page": String(page)],
            ttl: CacheTTL.short
        )
    }

    // MARK: - Person

    /// Get person details
    public func getPersonDetails(id: Int) async throws -> TMDBPersonDetails {
        return try await get(path: "/person/\(id)", ttl: CacheTTL.trending)
    }

    /// Get person combined credits
    public func getPersonCredits(id: Int) async throws -> TMDBPersonCredits {
        return try await get(path: "/person/\(id)/combined_credits", ttl: CacheTTL.trending)
    }
}

// MARK: - TMDB Models

public struct TMDBResultsResponse: Codable {
    public let page: Int
    public let results: [TMDBMedia]
    public let totalPages: Int?
    public let totalResults: Int?

    private enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

public struct TMDBMedia: Codable, Identifiable {
    public let id: Int
    public let title: String?
    public let name: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let releaseDate: String?
    public let firstAirDate: String?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let mediaType: String?
    public let adult: Bool?
    public let genreIds: [Int]?

    private enum CodingKeys: String, CodingKey {
        case id, title, name, overview, adult
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case mediaType = "media_type"
        case genreIds = "genre_ids"
    }
}

public struct TMDBMovieDetails: Codable {
    public let id: Int
    public let title: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let releaseDate: String?
    public let runtime: Int?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let adult: Bool?
    public let genres: [TMDBGenre]
    public let externalIds: TMDBExternalIds?
    // Extended fields
    public let tagline: String?
    public let status: String?
    public let budget: Int?
    public let revenue: Int?
    public let originalLanguage: String?
    public let productionCompanies: [TMDBProductionCompany]?

    private enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, adult, genres, tagline, status, budget, revenue
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case externalIds = "external_ids"
        case originalLanguage = "original_language"
        case productionCompanies = "production_companies"
    }
}

public struct TMDBTVDetails: Codable {
    public let id: Int
    public let name: String?
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let firstAirDate: String?
    public let lastAirDate: String?
    public let numberOfSeasons: Int?
    public let numberOfEpisodes: Int?
    public let episodeRunTime: [Int]?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let genres: [TMDBGenre]
    public let seasons: [TMDBSeasonSummary]
    public let externalIds: TMDBExternalIds?
    // Extended fields
    public let tagline: String?
    public let status: String?
    public let originalLanguage: String?
    public let networks: [TMDBProductionCompany]?
    public let productionCompanies: [TMDBProductionCompany]?
    public let createdBy: [TMDBCreator]?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, genres, seasons, tagline, status
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case episodeRunTime = "episode_run_time"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case externalIds = "external_ids"
        case originalLanguage = "original_language"
        case networks
        case productionCompanies = "production_companies"
        case createdBy = "created_by"
    }
}

public struct TMDBGenre: Codable {
    public let id: Int
    public let name: String
}

public struct TMDBProductionCompany: Codable {
    public let id: Int?
    public let name: String?
    public let logoPath: String?
    public let originCountry: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
        case originCountry = "origin_country"
    }
}

public struct TMDBCreator: Codable {
    public let id: Int?
    public let name: String?
    public let profilePath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case profilePath = "profile_path"
    }
}

public struct TMDBSeasonSummary: Codable {
    public let id: Int
    public let name: String?
    public let overview: String?
    public let posterPath: String?
    public let seasonNumber: Int?
    public let episodeCount: Int?
    public let airDate: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview
        case posterPath = "poster_path"
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case airDate = "air_date"
    }
}

public struct TMDBSeason: Codable {
    public let id: Int
    public let name: String?
    public let overview: String?
    public let posterPath: String?
    public let seasonNumber: Int?
    public let airDate: String?
    public let episodes: [TMDBEpisode]

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, episodes
        case posterPath = "poster_path"
        case seasonNumber = "season_number"
        case airDate = "air_date"
    }
}

public struct TMDBEpisode: Codable, Identifiable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let stillPath: String?
    public let airDate: String?
    public let episodeNumber: Int?
    public let seasonNumber: Int?
    public let runtime: Int?
    public let voteAverage: Double?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case stillPath = "still_path"
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case voteAverage = "vote_average"
    }
}

/// Full episode details including guest stars and crew
public struct TMDBEpisodeDetails: Codable, Identifiable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let stillPath: String?
    public let airDate: String?
    public let episodeNumber: Int?
    public let seasonNumber: Int?
    public let runtime: Int?
    public let voteAverage: Double?
    public let voteCount: Int?
    public let guestStars: [TMDBGuestStar]?
    public let crew: [TMDBCrewMember]?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime, crew
        case stillPath = "still_path"
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case guestStars = "guest_stars"
    }
}

public struct TMDBGuestStar: Codable, Identifiable {
    public let id: Int
    public let name: String?
    public let character: String?
    public let profilePath: String?
    public let order: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
    }
}

public struct TMDBCredits: Codable {
    public let id: Int?
    public let cast: [TMDBCastMember]
    public let crew: [TMDBCrewMember]
}

public struct TMDBCastMember: Codable, Identifiable {
    public let id: Int
    public let name: String
    public let character: String?
    public let profilePath: String?
    public let order: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
    }
}

public struct TMDBCrewMember: Codable, Identifiable {
    public let id: Int
    public let name: String
    public let job: String?
    public let department: String?
    public let profilePath: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, job, department
        case profilePath = "profile_path"
    }
}

public struct TMDBExternalIds: Codable {
    public let imdbId: String?
    public let tvdbId: Int?
    public let facebookId: String?
    public let instagramId: String?
    public let twitterId: String?

    private enum CodingKeys: String, CodingKey {
        case imdbId = "imdb_id"
        case tvdbId = "tvdb_id"
        case facebookId = "facebook_id"
        case instagramId = "instagram_id"
        case twitterId = "twitter_id"
    }
}

public struct TMDBImages: Codable {
    public let id: Int?
    public let backdrops: [TMDBImage]
    public let posters: [TMDBImage]
    public let logos: [TMDBImage]
}

public struct TMDBImage: Codable {
    public let filePath: String?
    public let width: Int?
    public let height: Int?
    public let aspectRatio: Double?
    public let voteAverage: Double?
    public let iso6391: String?

    private enum CodingKeys: String, CodingKey {
        case width, height
        case filePath = "file_path"
        case aspectRatio = "aspect_ratio"
        case voteAverage = "vote_average"
        case iso6391 = "iso_639_1"
    }
}

public struct TMDBPersonDetails: Codable {
    public let id: Int
    public let name: String
    public let biography: String?
    public let birthday: String?
    public let deathday: String?
    public let placeOfBirth: String?
    public let profilePath: String?
    public let knownForDepartment: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, deathday
        case placeOfBirth = "place_of_birth"
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
    }
}

public struct TMDBPersonCredits: Codable {
    public let id: Int
    public let cast: [TMDBMedia]
    public let crew: [TMDBMedia]
}

// MARK: - Videos

public struct TMDBVideosResponse: Codable {
    public let id: Int?
    public let results: [TMDBVideo]
}

public struct TMDBVideo: Codable, Identifiable {
    public let id: String
    public let key: String?
    public let name: String?
    public let site: String?
    public let type: String?
    public let official: Bool?
    public let publishedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, key, name, site, type, official
        case publishedAt = "published_at"
    }
}

// MARK: - Errors

public enum TMDBError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        }
    }
}
