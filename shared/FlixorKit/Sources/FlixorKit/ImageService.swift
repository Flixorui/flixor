import Foundation

public final class ImageService {
    public static let shared = ImageService()
    private init() {}

    private var apiClient: APIClient { APIClient.shared }

    // MARK: - Plex Images via backend proxy
    @MainActor
    public func plexImageURL(path: String?, width: Int? = nil, height: Int? = nil, format: String = "webp", quality: Int? = nil) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        var components = URLComponents(string: apiClient.baseURL.absoluteString)
        components?.path = "/api/image/plex"

        var queryItems = [URLQueryItem(name: "path", value: path)]
        if let width = width { queryItems.append(URLQueryItem(name: "w", value: String(width))) }
        if let height = height { queryItems.append(URLQueryItem(name: "h", value: String(height))) }
        queryItems.append(URLQueryItem(name: "f", value: format))
        if let q = quality { queryItems.append(URLQueryItem(name: "q", value: String(q))) }
        components?.queryItems = queryItems
        return components?.url
    }

    // MARK: - Generic external image proxy (e.g., TMDB)
    @MainActor
    public func proxyImageURL(url: String?, width: Int? = nil, height: Int? = nil, format: String = "webp", quality: Int = 70) -> URL? {
        guard let url = url, !url.isEmpty else { return nil }
        var components = URLComponents(string: apiClient.baseURL.absoluteString)
        components?.path = "/api/image/proxy"
        var queryItems = [URLQueryItem(name: "url", value: url)]
        if let width = width { queryItems.append(URLQueryItem(name: "w", value: String(width))) }
        if let height = height { queryItems.append(URLQueryItem(name: "h", value: String(height))) }
        queryItems.append(URLQueryItem(name: "q", value: String(quality)))
        queryItems.append(URLQueryItem(name: "f", value: format))
        components?.queryItems = queryItems
        return components?.url
    }

    public func tmdbImageURL(path: String?, size: TMDBImageSize = .w500) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }

    @MainActor
    public func thumbURL(for item: MediaItem, width: Int = 300, height: Int = 450) -> URL? {
        if let t = item.thumb, t.hasPrefix("http") { return proxyImageURL(url: t, width: width, height: height) }
        return plexImageURL(path: item.thumb, width: width, height: height)
    }

    @MainActor
    public func artURL(for item: MediaItem, width: Int = 1920, height: Int = 1080) -> URL? {
        if let a = item.art, a.hasPrefix("http") { return proxyImageURL(url: a, width: width, height: height) }
        return plexImageURL(path: item.art, width: width, height: height)
    }

    @MainActor
    public func continueWatchingURL(for item: MediaItem, width: Int = 600, height: Int = 338) -> URL? {
        if item.type == "episode" {
            let path = item.grandparentArt ?? item.grandparentThumb ?? item.art ?? item.thumb
            if let p = path, p.hasPrefix("http") { return proxyImageURL(url: p, width: width, height: height) }
            return plexImageURL(path: path, width: width, height: height, quality: 70)
        }
        if item.type == "season" {
            let path = item.art
            if let p = path, p.hasPrefix("http") { return proxyImageURL(url: p, width: width, height: height) }
            return plexImageURL(path: path, width: width, height: height, quality: 70)
        }
        let path = item.art ?? item.thumb
        if let p = path, p.hasPrefix("http") { return proxyImageURL(url: p, width: width, height: height) }
        return plexImageURL(path: path, width: width, height: height, quality: 70)
    }
}

public enum TMDBImageSize: String { case w92, w154, w185, w342, w500, w780, original }
