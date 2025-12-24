//
//  ImageService.swift
//  FlixorMac
//
//  Service for building image URLs from Plex and TMDB
//  Updated to use FlixorCore for standalone operation
//

import Foundation
import FlixorKit

@MainActor
class ImageService {
    static let shared = ImageService()

    private init() {}

    // MARK: - Plex Images

    func plexImageURL(path: String?, width: Int? = nil, height: Int? = nil, format: String = "webp", quality: Int? = nil) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }

        // Use FlixorCore's PlexServerService for image URLs
        guard let plexServer = FlixorCore.shared.plexServer else { return nil }

        let urlString = plexServer.getImageUrl(path: path, width: width)
        return urlString.flatMap { URL(string: $0) }
    }

    // MARK: - Generic External Proxy (TMDB)

    /// For external images (TMDB), return the URL directly without proxy
    /// Since we're standalone, we don't need to proxy through backend
    func proxyImageURL(url: String?, width: Int? = nil, height: Int? = nil, format: String = "webp", quality: Int = 70) -> URL? {
        guard let url = url, !url.isEmpty else { return nil }
        return URL(string: url)
    }

    // MARK: - TMDB Images

    func tmdbImageURL(path: String?, size: TMDBImageSize = .w500) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }

    // MARK: - TMDB Image URLs via FlixorCore

    func tmdbPosterURL(path: String?, size: String = "w500") -> URL? {
        guard let path = path else { return nil }
        guard let urlString = FlixorCore.shared.tmdb.getPosterUrl(path: path, size: size) else { return nil }
        return URL(string: urlString)
    }

    func tmdbBackdropURL(path: String?, size: String = "w1280") -> URL? {
        guard let path = path else { return nil }
        guard let urlString = FlixorCore.shared.tmdb.getBackdropUrl(path: path, size: size) else { return nil }
        return URL(string: urlString)
    }

    // MARK: - Plex Thumb

    func thumbURL(for item: MediaItem, width: Int = 300, height: Int = 450) -> URL? {
        plexImageURL(path: item.thumb, width: width, height: height)
    }

    // MARK: - Plex Art (Backdrop)

    func artURL(for item: MediaItem, width: Int = 1920, height: Int = 1080) -> URL? {
        plexImageURL(path: item.art, width: width, height: height)
    }

    // MARK: - Continue Watching Images (Backdrop style)

    /// Returns a backdrop-style image for continue watching cards.
    /// For episodes, uses the show's backdrop (grandparentArt/grandparentThumb).
    /// For seasons, uses the show's backdrop (art should contain parent show's art).
    /// For movies/shows, uses the regular backdrop (art/thumb).
    func continueWatchingURL(for item: MediaItem, width: Int = 600, height: Int = 338) -> URL? {
        // For episodes, use show's backdrop (grandparent)
        if item.type == "episode" {
            // Priority: grandparentArt > grandparentThumb > art > thumb
            let path = item.grandparentArt ?? item.grandparentThumb ?? item.art ?? item.thumb
            if let p = path, p.hasPrefix("http") {
                return URL(string: p)
            }
            return plexImageURL(path: path, width: width, height: height, quality: 70)
        }

        // For seasons, use parent show's backdrop (should be in art field)
        // If art is missing, we can't fall back to thumb as that would be the season poster
        if item.type == "season" {
            let path = item.art
            if let p = path, p.hasPrefix("http") {
                return URL(string: p)
            }
            return plexImageURL(path: path, width: width, height: height, quality: 70)
        }

        // For movies/shows, use regular backdrop
        // Priority: art > thumb
        let path = item.art ?? item.thumb
        if let p = path, p.hasPrefix("http") {
            return URL(string: p)
        }
        return plexImageURL(path: path, width: width, height: height, quality: 70)
    }
}

// MARK: - TMDB Image Sizes

enum TMDBImageSize: String {
    case w92
    case w154
    case w185
    case w342
    case w500
    case w780
    case original
}

// MARK: - Media Item Model (will be expanded later)

struct MediaItem: Identifiable, Codable {
    let id: String // ratingKey
    let title: String
    let type: String // movie, show, episode, season
    let thumb: String?
    let art: String?
    let year: Int?
    let rating: Double?
    let duration: Int?
    let viewOffset: Int?
    let summary: String?

    // TV Show specific fields
    let grandparentTitle: String?
    let grandparentThumb: String?
    let grandparentArt: String?
    let parentIndex: Int?
    let index: Int?

    // Season specific fields
    let parentRatingKey: String?     // Parent show ID
    let parentTitle: String?          // Parent show name
    let leafCount: Int?               // Episode count
    let viewedLeafCount: Int?         // Watched episode count

    enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title
        case type
        case thumb
        case art
        case year
        case rating
        case duration
        case viewOffset
        case summary
        case grandparentTitle
        case grandparentThumb
        case grandparentArt
        case parentIndex
        case index
        case parentRatingKey
        case parentTitle
        case leafCount
        case viewedLeafCount
    }
}
