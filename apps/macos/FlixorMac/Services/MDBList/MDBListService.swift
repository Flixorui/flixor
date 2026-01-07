//
//  MDBListService.swift
//  FlixorMac
//
//  MDBList API service for fetching ratings from multiple sources
//  Requires user to enable and provide API key in settings
//

import Foundation

// MARK: - API Response Models

private struct MDBListRatingResponse: Codable {
    let ratings: [MDBListRatingItem]?
}

private struct MDBListRatingItem: Codable {
    let id: String?
    let rating: Double?
}

// MARK: - MDBListService

@MainActor
class MDBListService: ObservableObject {
    // MARK: - Singleton

    static let shared = MDBListService()

    // MARK: - Configuration

    private let baseURL = "https://api.mdblist.com"
    private let cacheTTL: TimeInterval = 24 * 60 * 60 // 24 hours

    // MARK: - Cache

    private var cache: [String: (ratings: MDBListRatings?, timestamp: Date)] = [:]

    // MARK: - Computed Properties

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "mdblistEnabled")
    }

    private var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: "mdblistApiKey")
        return key?.isEmpty == false ? key : nil
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Check if MDBList is enabled and has an API key
    func isReady() -> Bool {
        return isEnabled && apiKey != nil
    }

    /// Fetch ratings from MDBList API
    /// - Parameters:
    ///   - imdbId: The IMDb ID (with or without "tt" prefix)
    ///   - mediaType: Either "movie" or "show"
    /// - Returns: MDBListRatings or nil if unavailable
    func fetchRatings(imdbId: String, mediaType: String) async -> MDBListRatings? {
        guard isEnabled else {
            print("[MDBListService] MDBList is disabled")
            return nil
        }

        guard let apiKey = apiKey else {
            print("[MDBListService] No API key configured")
            return nil
        }

        // Normalize IMDb ID
        let formattedImdbId = imdbId.hasPrefix("tt") ? imdbId : "tt\(imdbId)"
        guard formattedImdbId.range(of: "^tt\\d+$", options: .regularExpression) != nil else {
            print("[MDBListService] Invalid IMDb ID format: \(formattedImdbId)")
            return nil
        }

        // Check cache
        let cacheKey = "\(mediaType):\(formattedImdbId)"
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            print("[MDBListService] Cache hit for \(cacheKey): \(cached.ratings != nil ? "found" : "null")")
            return cached.ratings
        }

        print("[MDBListService] Fetching ratings for \(mediaType): \(formattedImdbId)")

        var ratings = MDBListRatings()
        let ratingTypes = ["imdb", "tmdb", "trakt", "letterboxd", "tomatoes", "audience", "metacritic"]

        // Fetch all rating types in parallel
        await withTaskGroup(of: (String, Double?).self) { group in
            for ratingType in ratingTypes {
                group.addTask {
                    await self.fetchSingleRating(
                        mediaType: mediaType,
                        ratingType: ratingType,
                        imdbId: formattedImdbId,
                        apiKey: apiKey
                    )
                }
            }

            for await (type, rating) in group {
                switch type {
                case "imdb": ratings.imdb = rating
                case "tmdb": ratings.tmdb = rating
                case "trakt": ratings.trakt = rating
                case "letterboxd": ratings.letterboxd = rating
                case "tomatoes": ratings.tomatoes = rating
                case "audience": ratings.audience = rating
                case "metacritic": ratings.metacritic = rating
                default: break
                }
            }
        }

        let hasAnyRating = ratings.hasAnyRating
        print("[MDBListService] Fetched ratings - hasAny: \(hasAnyRating)")

        // Cache the result (even if empty to avoid repeated failed requests)
        let finalResult = hasAnyRating ? ratings : nil
        cache[cacheKey] = (ratings: finalResult, timestamp: Date())

        return finalResult
    }

    /// Clear the ratings cache
    func clearCache() {
        cache.removeAll()
        print("[MDBListService] Cache cleared")
    }

    // MARK: - Private Helpers

    private func fetchSingleRating(
        mediaType: String,
        ratingType: String,
        imdbId: String,
        apiKey: String
    ) async -> (String, Double?) {
        let urlString = "\(baseURL)/rating/\(mediaType)/\(ratingType)?apikey=\(apiKey)"

        guard let url = URL(string: urlString) else {
            return (ratingType, nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "ids": [imdbId],
            "provider": "imdb"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return (ratingType, nil)
            }

            if httpResponse.statusCode == 403 {
                print("[MDBListService] Invalid API key")
                return (ratingType, nil)
            }

            if httpResponse.statusCode == 200 {
                let decoded = try JSONDecoder().decode(MDBListRatingResponse.self, from: data)
                if let rating = decoded.ratings?.first?.rating {
                    return (ratingType, rating)
                }
            }
        } catch {
            print("[MDBListService] Error fetching \(ratingType): \(error)")
        }

        return (ratingType, nil)
    }
}
