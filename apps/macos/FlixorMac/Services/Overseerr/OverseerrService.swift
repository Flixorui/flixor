//
//  OverseerrService.swift
//  FlixorMac
//
//  Overseerr API service for requesting media
//  Requires user to enable and provide URL + API key in settings
//

import Foundation

@MainActor
class OverseerrService: ObservableObject {
    // MARK: - Singleton

    static let shared = OverseerrService()

    // MARK: - Configuration

    private let cacheTTL: TimeInterval = 5 * 60 // 5 minutes

    // MARK: - Cache

    private var cache: [String: (status: OverseerrMediaStatus, timestamp: Date)] = [:]

    // MARK: - Computed Properties

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "overseerrEnabled")
    }

    private var serverUrl: String? {
        let url = UserDefaults.standard.string(forKey: "overseerrUrl")
        return url?.isEmpty == false ? url : nil
    }

    private var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: "overseerrApiKey")
        return key?.isEmpty == false ? key : nil
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Check if Overseerr is enabled and has URL + API key configured
    func isReady() -> Bool {
        return isEnabled && serverUrl != nil && apiKey != nil
    }

    /// Validate Overseerr connection with provided credentials
    func validateConnection(url: String, apiKey: String) async -> OverseerrConnectionResult {
        do {
            let normalizedUrl = normalizeUrl(url)
            guard let requestUrl = URL(string: "\(normalizedUrl)/api/v1/auth/me") else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Invalid URL")
            }

            var request = URLRequest(url: requestUrl)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Invalid response")
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Invalid API key")
            }

            if httpResponse.statusCode != 200 {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Server error (\(httpResponse.statusCode))")
            }

            let user = try JSONDecoder().decode(OverseerrUser.self, from: data)
            let username = user.username ?? user.email ?? "user"
            return OverseerrConnectionResult(valid: true, username: username, error: nil)
        } catch {
            print("[OverseerrService] Connection validation error: \(error)")
            return OverseerrConnectionResult(valid: false, username: nil, error: "Connection failed")
        }
    }

    /// Get media request status from Overseerr
    func getMediaStatus(tmdbId: Int, mediaType: String) async -> OverseerrMediaStatus {
        guard isReady() else {
            return .notConfigured
        }

        // Check cache
        let cacheKey = "\(mediaType):\(tmdbId)"
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            print("[OverseerrService] Cache hit for \(cacheKey)")
            return cached.status
        }

        do {
            print("[OverseerrService] Fetching status for \(mediaType):\(tmdbId)")

            let endpoint = mediaType == "movie" ? "/movie/\(tmdbId)" : "/tv/\(tmdbId)"
            let data = try await makeRequest(endpoint: endpoint)

            let status: OverseerrMediaStatus
            if mediaType == "movie" {
                let details = try JSONDecoder().decode(OverseerrMovieDetails.self, from: data)
                status = parseMediaStatus(mediaInfo: details.mediaInfo)
            } else {
                let details = try JSONDecoder().decode(OverseerrTvDetails.self, from: data)
                status = parseMediaStatus(mediaInfo: details.mediaInfo)
            }

            // Cache the result
            cache[cacheKey] = (status: status, timestamp: Date())

            print("[OverseerrService] Status for \(cacheKey): \(status.status.rawValue)")
            return status
        } catch {
            print("[OverseerrService] Error fetching status: \(error)")
            return OverseerrMediaStatus(status: .unknown, canRequest: true)
        }
    }

    /// Request media through Overseerr
    func requestMedia(tmdbId: Int, mediaType: String, is4k: Bool = false) async -> OverseerrRequestResult {
        guard isReady() else {
            return OverseerrRequestResult(success: false, requestId: nil, status: nil, error: "Overseerr not configured")
        }

        do {
            print("[OverseerrService] Requesting \(mediaType):\(tmdbId) (4K: \(is4k))")

            // Build request body
            var requestBody: [String: Any] = [
                "mediaType": mediaType,
                "mediaId": tmdbId
            ]

            if is4k {
                requestBody["is4k"] = true
            }

            // For TV shows, we need to specify which seasons to request
            if mediaType == "tv" {
                let seasons = await getTvSeasons(tmdbId: tmdbId)
                if seasons.isEmpty {
                    return OverseerrRequestResult(success: false, requestId: nil, status: nil, error: "Could not determine available seasons")
                }
                requestBody["seasons"] = seasons
                print("[OverseerrService] Requesting seasons: \(seasons)")
            }

            let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
            let data = try await makeRequest(endpoint: "/request", method: "POST", body: bodyData)

            // Clear cache for this item
            let cacheKey = "\(mediaType):\(tmdbId)"
            cache.removeValue(forKey: cacheKey)

            let response = try JSONDecoder().decode(OverseerrMediaRequest.self, from: data)
            print("[OverseerrService] Request created: \(response.id)")

            // Determine status from response
            var status: OverseerrStatus = .pending
            if response.status == MediaRequestStatusCode.approved.rawValue {
                status = .approved
            }

            return OverseerrRequestResult(success: true, requestId: response.id, status: status, error: nil)
        } catch {
            print("[OverseerrService] Error creating request: \(error)")
            return OverseerrRequestResult(success: false, requestId: nil, status: nil, error: error.localizedDescription)
        }
    }

    /// Clear the status cache
    func clearCache() {
        cache.removeAll()
        print("[OverseerrService] Cache cleared")
    }

    /// Clear cache for a specific item
    func clearCacheItem(tmdbId: Int, mediaType: String) {
        let cacheKey = "\(mediaType):\(tmdbId)"
        cache.removeValue(forKey: cacheKey)
        print("[OverseerrService] Cache cleared for \(cacheKey)")
    }

    // MARK: - Private Helpers

    private func normalizeUrl(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("/") {
            normalized = String(normalized.dropLast())
        }
        return normalized
    }

    private func makeRequest(endpoint: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let serverUrl = serverUrl, let apiKey = apiKey else {
            throw NSError(domain: "OverseerrService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Overseerr not configured"])
        }

        let normalizedUrl = normalizeUrl(serverUrl)
        guard let url = URL(string: "\(normalizedUrl)/api/v1\(endpoint)") else {
            throw NSError(domain: "OverseerrService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OverseerrService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OverseerrService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Overseerr API error (\(httpResponse.statusCode)): \(errorText)"])
        }

        return data
    }

    private func parseMediaStatus(mediaInfo: OverseerrMediaInfo?) -> OverseerrMediaStatus {
        guard let mediaInfo = mediaInfo else {
            return OverseerrMediaStatus(status: .notRequested, canRequest: true)
        }

        // Check media availability status first
        switch mediaInfo.status {
        case MediaInfoStatusCode.available.rawValue:
            return OverseerrMediaStatus(status: .available, canRequest: false)
        case MediaInfoStatusCode.partiallyAvailable.rawValue:
            return OverseerrMediaStatus(status: .partiallyAvailable, canRequest: true)
        case MediaInfoStatusCode.processing.rawValue:
            return OverseerrMediaStatus(status: .processing, canRequest: false)
        default:
            break
        }

        // Check request status if media not available
        if let latestRequest = mediaInfo.requests?.first {
            switch latestRequest.status {
            case MediaRequestStatusCode.pending.rawValue:
                return OverseerrMediaStatus(status: .pending, requestId: latestRequest.id, canRequest: false)
            case MediaRequestStatusCode.approved.rawValue:
                return OverseerrMediaStatus(status: .approved, requestId: latestRequest.id, canRequest: false)
            case MediaRequestStatusCode.declined.rawValue:
                return OverseerrMediaStatus(status: .declined, requestId: latestRequest.id, canRequest: true)
            default:
                break
            }
        }

        // Default to not requested
        if mediaInfo.status == MediaInfoStatusCode.pending.rawValue {
            return OverseerrMediaStatus(status: .pending, canRequest: false)
        }

        return OverseerrMediaStatus(status: .notRequested, canRequest: true)
    }

    private func getTvSeasons(tmdbId: Int) async -> [Int] {
        do {
            let data = try await makeRequest(endpoint: "/tv/\(tmdbId)")
            let details = try JSONDecoder().decode(OverseerrTvDetails.self, from: data)
            // Filter out season 0 (specials) and return season numbers
            return (details.seasons ?? [])
                .map { $0.seasonNumber }
                .filter { $0 > 0 }
        } catch {
            print("[OverseerrService] Error fetching TV seasons: \(error)")
            return []
        }
    }
}
