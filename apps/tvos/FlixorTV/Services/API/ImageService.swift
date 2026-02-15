//
//  ImageService.swift
//  FlixorTV
//
//  Service for building image URLs from Plex and TMDB
//

import Foundation
import FlixorKit

@MainActor
final class ImageService {
    static let shared = ImageService()

    private init() {}

    // MARK: - Plex Images

    func plexImageURL(path: String?, width: Int? = nil, height: Int? = nil, format: String = "webp", quality: Int? = nil) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }

        // Use FlixorCore's PlexServerService for image URLs.
        guard let plexServer = FlixorCore.shared.plexServer else {
            #if DEBUG
            print("⚠️ [ImageService] No plexServer while resolving image path: \(path)")
            #endif
            return nil
        }

        let urlString = plexServer.getImageUrl(path: path, width: width)
        #if DEBUG
        if let urlString, let url = URL(string: urlString) {
            print("🖼️ [ImageService] Plex image URL host=\(url.host ?? "nil") path=\(url.path)")
        }
        #endif
        return urlString.flatMap { URL(string: $0) }
    }

    // MARK: - Generic External Proxy (TMDB)

    /// For external images (TMDB), return the URL directly without proxy.
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
        if let thumb = item.thumb, thumb.hasPrefix("http") {
            return URL(string: thumb)
        }
        return plexImageURL(path: item.thumb, width: width, height: height)
    }

    // MARK: - Plex Art (Backdrop)

    func artURL(for item: MediaItem, width: Int = 1920, height: Int = 1080) -> URL? {
        if let art = item.art, art.hasPrefix("http") {
            return URL(string: art)
        }
        return plexImageURL(path: item.art, width: width, height: height)
    }

    // MARK: - Continue Watching Images (Backdrop style)

    func continueWatchingURL(for item: MediaItem, width: Int = 600, height: Int = 338) -> URL? {
        if item.type == "episode" {
            let path = item.grandparentArt ?? item.grandparentThumb ?? item.art ?? item.thumb
            if let p = path, p.hasPrefix("http") {
                return URL(string: p)
            }
            return plexImageURL(path: path, width: width, height: height, quality: 70)
        }

        if item.type == "season" {
            let path = item.art
            if let p = path, p.hasPrefix("http") {
                return URL(string: p)
            }
            return plexImageURL(path: path, width: width, height: height, quality: 70)
        }

        let path = item.art ?? item.thumb
        if let p = path, p.hasPrefix("http") {
            return URL(string: p)
        }
        return plexImageURL(path: path, width: width, height: height, quality: 70)
    }
}

enum TMDBImageSize: String {
    case w92
    case w154
    case w185
    case w342
    case w500
    case w780
    case original
}
