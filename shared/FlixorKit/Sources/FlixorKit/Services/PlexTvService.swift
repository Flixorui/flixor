//
//  PlexTvService.swift
//  FlixorKit
//
//  Handles Plex.tv features (watchlist, discover, etc.)
//  Reference: packages/core/src/services/PlexTvService.ts
//

import Foundation

// MARK: - PlexTvService

public class PlexTvService {
    private var token: String
    private let clientId: String
    private let productName: String
    private let productVersion: String
    private let platform: String

    private let plexTvMetadataUrl = "https://discover.provider.plex.tv"

    public init(
        token: String,
        clientId: String,
        productName: String = "Flixor",
        productVersion: String = "1.0.0",
        platform: String = "macOS"
    ) {
        self.token = token
        self.clientId = clientId
        self.productName = productName
        self.productVersion = productVersion
        self.platform = platform
    }

    /// Update token (e.g., after re-authentication)
    public func updateToken(_ newToken: String) {
        self.token = newToken
    }

    // MARK: - Headers

    private func getHeaders() -> [String: String] {
        return [
            "Accept": "application/json",
            "X-Plex-Token": token,
            "X-Plex-Client-Identifier": clientId,
            "X-Plex-Product": productName,
            "X-Plex-Version": productVersion,
            "X-Plex-Platform": platform
        ]
    }

    // MARK: - HTTP Methods

    private func get<T: Decodable>(url: String) async throws -> T {
        guard let requestUrl = URL(string: url) else {
            throw PlexTvError.invalidURL
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = "GET"

        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexTvError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw PlexTvError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Watchlist

    /// Get user's watchlist
    public func getWatchlist() async throws -> [PlexMediaItem] {
        let data: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            url: "\(plexTvMetadataUrl)/library/sections/watchlist/all"
        )
        return data.MediaContainer.Metadata ?? []
    }

    /// Get full metadata for a watchlist item (to extract TMDB ID)
    /// The `key` is the item's key path like "/library/metadata/123"
    public func getWatchlistItemMetadata(key: String) async throws -> PlexMediaItem? {
        let url = "\(plexTvMetadataUrl)\(key)"
        let data: PlexMediaContainerResponse<PlexMediaItem> = try await get(url: url)
        return data.MediaContainer.Metadata?.first
    }

    /// Extract TMDB ID from a watchlist item by fetching its full metadata
    public func getTMDBIdForWatchlistItem(_ item: PlexMediaItem) async -> String? {
        guard let key = item.key else { return nil }

        do {
            guard let fullItem = try await getWatchlistItemMetadata(key: key) else { return nil }

            // Look for TMDB guid in the Guid array
            for guid in fullItem.guids {
                if guid.hasPrefix("tmdb://") {
                    let tmdbId = guid.replacingOccurrences(of: "tmdb://", with: "")
                    let mediaType = item.type == "movie" ? "movie" : "tv"
                    return "tmdb:\(mediaType):\(tmdbId)"
                }
                if guid.hasPrefix("themoviedb://") {
                    let tmdbId = guid.replacingOccurrences(of: "themoviedb://", with: "")
                    let mediaType = item.type == "movie" ? "movie" : "tv"
                    return "tmdb:\(mediaType):\(tmdbId)"
                }
            }
        } catch {
            print("⚠️ [PlexTv] Failed to get metadata for \(item.title): \(error)")
        }

        return nil
    }

    /// Add item to watchlist
    public func addToWatchlist(ratingKey: String) async throws {
        guard let url = URL(string: "\(plexTvMetadataUrl)/library/sections/watchlist/items/\(ratingKey)") else {
            throw PlexTvError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexTvError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PlexTvError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Remove item from watchlist
    public func removeFromWatchlist(ratingKey: String) async throws {
        guard let url = URL(string: "\(plexTvMetadataUrl)/library/sections/watchlist/items/\(ratingKey)") else {
            throw PlexTvError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexTvError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PlexTvError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    /// Check if item is in watchlist
    public func isInWatchlist(ratingKey: String) async -> Bool {
        do {
            let watchlist = try await getWatchlist()
            return watchlist.contains { $0.ratingKey == ratingKey }
        } catch {
            return false
        }
    }

    // MARK: - Discover

    /// Get discover recommendations
    public func getDiscover() async throws -> [PlexMediaItem] {
        let data: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            url: "\(plexTvMetadataUrl)/library/sections/discover/all"
        )
        return data.MediaContainer.Metadata ?? []
    }

    /// Get trending items
    public func getTrending() async throws -> [PlexMediaItem] {
        let data: PlexMediaContainerResponse<PlexMediaItem> = try await get(
            url: "\(plexTvMetadataUrl)/library/sections/trending/all"
        )
        return data.MediaContainer.Metadata ?? []
    }

    // MARK: - Search

    /// Search Plex.tv (global search across all content)
    public func search(query: String) async throws -> [PlexMediaItem] {
        var components = URLComponents(string: "\(plexTvMetadataUrl)/library/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw PlexTvError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexTvError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw PlexTvError.httpError(statusCode: httpResponse.statusCode)
        }

        let container = try JSONDecoder().decode(PlexMediaContainerResponse<PlexMediaItem>.self, from: data)
        return container.MediaContainer.Metadata ?? []
    }

    // MARK: - Metadata Lookup

    /// Get metadata by GUID (TMDB, IMDB, etc.)
    public func getByGuid(_ guid: String) async throws -> PlexMediaItem? {
        var components = URLComponents(string: "\(plexTvMetadataUrl)/library/metadata/matches")
        components?.queryItems = [
            URLQueryItem(name: "guid", value: guid),
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]

        guard let url = components?.url else {
            throw PlexTvError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let container = try JSONDecoder().decode(PlexMediaContainerResponse<PlexMediaItem>.self, from: data)
            return container.MediaContainer.Metadata?.first
        } catch {
            return nil
        }
    }

    /// Get Plex.tv metadata for a specific item
    public func getMetadata(ratingKey: String) async throws -> PlexMediaItem? {
        do {
            let data: PlexMediaContainerResponse<PlexMediaItem> = try await get(
                url: "\(plexTvMetadataUrl)/library/metadata/\(ratingKey)"
            )
            return data.MediaContainer.Metadata?.first
        } catch {
            return nil
        }
    }
}

// MARK: - Errors

public enum PlexTvError: Error, LocalizedError {
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
