//
//  NewPopularData.swift
//  FlixorMac
//
//  Models for New & Popular screen API responses
//

import Foundation

// MARK: - TMDB Models

struct TMDBTrendingResponse: Codable {
    let page: Int?
    let results: [TMDBMediaItem]
    let total_pages: Int?
    let total_results: Int?
}

struct TMDBMoviesResponse: Codable {
    let page: Int?
    let results: [TMDBMediaItem]
    let total_pages: Int?
    let total_results: Int?
}

struct TMDBMediaItem: Codable {
    let id: Int
    let title: String?
    let name: String?
    let poster_path: String?
    let backdrop_path: String?
    let vote_average: Double?
    let release_date: String?
    let first_air_date: String?
    let overview: String?
    let media_type: String?
    let genre_ids: [Int]?
}

struct TMDBMovieDetails: Codable {
    let id: Int
    let title: String
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let vote_average: Double?
    let release_date: String?
    let runtime: Int?
    let genres: [TMDBGenre]?
}

struct TMDBTVDetails: Codable {
    let id: Int
    let name: String
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let vote_average: Double?
    let first_air_date: String?
    let episode_run_time: [Int]?
    let genres: [TMDBGenre]?
}

struct TMDBGenre: Codable {
    let id: Int
    let name: String
}

struct TMDBVideosResponse: Codable {
    let results: [TMDBVideo]
}

struct TMDBVideo: Codable {
    let key: String
    let type: String
    let site: String
    let name: String?
}

struct TMDBImagesResponse: Codable {
    let logos: [TMDBImage]?
    let backdrops: [TMDBImage]?
    let posters: [TMDBImage]?
}

struct TMDBImage: Codable {
    let file_path: String
    let iso_639_1: String?
    let width: Int?
    let height: Int?
}

// MARK: - Trakt Models

typealias TraktWatchedResponse = [TraktWatchedItem]

struct TraktWatchedItem: Codable {
    let watcher_count: Int?
    let play_count: Int?
    let collected_count: Int?
    let movie: TraktMovie?
    let show: TraktShow?
}

typealias TraktAnticipatedResponse = [TraktAnticipatedItem]

struct TraktAnticipatedItem: Codable {
    let list_count: Int
    let movie: TraktMovie?
    let show: TraktShow?
}

// Trakt types for API responses
struct NewPopularTraktIDs: Codable {
    let tmdb: Int?
    let trakt: Int?
    let imdb: String?
    let tvdb: Int?
}

struct TraktMovie: Codable {
    let title: String
    let year: Int?
    let ids: NewPopularTraktIDs
}

struct TraktShow: Codable {
    let title: String
    let year: Int?
    let ids: NewPopularTraktIDs
}

// MARK: - Hero Data

struct HeroData {
    let id: String
    let title: String
    let overview: String
    let backdropURL: URL?
    let posterURL: URL?
    let rating: String?
    let year: String?
    let runtime: Int?
    let genres: [String]
    let ytKey: String?
    let logoURL: URL?
    let canPlay: Bool
    let mediaType: String // "movie" or "tv"
}

// MARK: - Display Item (for rows)

struct DisplayMediaItem: Identifiable {
    let id: String
    let title: String
    let imageURL: URL?
    let subtitle: String?
    let badge: String?
    let rank: Int?
    let mediaType: String // "movie" or "tv"

    // Convert to MediaItem for navigation
    func toMediaItem() -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            type: mediaType == "tv" ? "show" : "movie",
            thumb: nil, // Image URL is handled separately
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil,
            parentRatingKey: nil,
            parentTitle: nil,
            leafCount: nil,
            viewedLeafCount: nil
        )
    }
}
