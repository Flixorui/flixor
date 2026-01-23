//
//  OverseerrService.swift
//  FlixorMac
//
//  Overseerr API service for requesting media
//  Requires user to enable and provide URL + API key or Plex auth in settings
//

import Foundation
import FlixorKit

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
        UserDefaults.standard.overseerrEnabled
    }

    private var serverUrl: String? {
        let url = UserDefaults.standard.overseerrUrl
        return url.isEmpty ? nil : url
    }

    private var authMethod: OverseerrAuthMethod {
        UserDefaults.standard.overseerrAuthMethod
    }

    private var apiKey: String? {
        let key = UserDefaults.standard.overseerrApiKey
        return key.isEmpty ? nil : key
    }

    private var sessionCookie: String? {
        let cookie = UserDefaults.standard.overseerrSessionCookie
        return cookie.isEmpty ? nil : cookie
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Check if Overseerr is enabled and properly configured
    /// For API key auth: needs URL + API key
    /// For Plex auth: needs URL + session cookie
    func isReady() -> Bool {
        guard isEnabled, serverUrl != nil else { return false }

        switch authMethod {
        case .apiKey:
            return apiKey != nil
        case .plex:
            return sessionCookie != nil
        }
    }

    /// Validate Overseerr connection with API key
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

    /// Authenticate with Overseerr using Plex token
    func authenticateWithPlex(url: String) async -> OverseerrConnectionResult {
        do {
            // Get the Plex token from FlixorCore
            guard let plexToken = FlixorCore.shared.plexToken else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Not signed in to Plex")
            }

            let normalizedUrl = normalizeUrl(url)

            // First, check if the server is reachable
            guard let statusUrl = URL(string: "\(normalizedUrl)/api/v1/status") else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Invalid URL")
            }

            var statusRequest = URLRequest(url: statusUrl)
            statusRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (_, statusResponse) = try await URLSession.shared.data(for: statusRequest)
            guard let httpStatusResponse = statusResponse as? HTTPURLResponse,
                  httpStatusResponse.statusCode == 200 else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Unable to connect to Overseerr server")
            }

            // Authenticate with Plex token
            guard let authUrl = URL(string: "\(normalizedUrl)/api/v1/auth/plex") else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Invalid URL")
            }

            var authRequest = URLRequest(url: authUrl)
            authRequest.httpMethod = "POST"
            authRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            authRequest.httpBody = try JSONEncoder().encode(["authToken": plexToken])

            let (authData, authResponse) = try await URLSession.shared.data(for: authRequest)

            guard let httpAuthResponse = authResponse as? HTTPURLResponse else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Invalid response")
            }

            if httpAuthResponse.statusCode == 401 || httpAuthResponse.statusCode == 403 {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Plex account not authorized on this Overseerr server")
            }

            if httpAuthResponse.statusCode < 200 || httpAuthResponse.statusCode >= 300 {
                print("[OverseerrService] Plex auth error: \(httpAuthResponse.statusCode)")
                return OverseerrConnectionResult(valid: false, username: nil, error: "Authentication failed (\(httpAuthResponse.statusCode))")
            }

            // Extract session cookie from response headers
            var sessionCookie: String?
            if let allHeaders = httpAuthResponse.allHeaderFields as? [String: String],
               let setCookieHeader = allHeaders["Set-Cookie"] ?? allHeaders["set-cookie"] {
                // Parse the connect.sid cookie
                if let cookieMatch = setCookieHeader.range(of: "connect\\.sid=([^;]+)", options: .regularExpression) {
                    let fullMatch = String(setCookieHeader[cookieMatch])
                    sessionCookie = fullMatch
                }
            }

            // Get user info from response
            let user = try JSONDecoder().decode(OverseerrUser.self, from: authData)
            let username = user.username ?? user.plexUsername ?? user.email ?? "Plex User"

            // Store the session cookie and username
            if let cookie = sessionCookie {
                UserDefaults.standard.overseerrSessionCookie = cookie
                UserDefaults.standard.overseerrPlexUsername = username
                print("[OverseerrService] Plex auth successful, session stored")
                return OverseerrConnectionResult(valid: true, username: username, error: nil)
            } else {
                // Session might be stored differently - save username and try to verify
                UserDefaults.standard.overseerrPlexUsername = username
                print("[OverseerrService] No cookie in response, authentication may have failed")
                return OverseerrConnectionResult(valid: false, username: nil, error: "Session cookie not received")
            }
        } catch {
            print("[OverseerrService] Plex authentication error: \(error)")
            return OverseerrConnectionResult(valid: false, username: nil, error: "Authentication failed")
        }
    }

    /// Validate existing Plex session
    func validatePlexSession(url: String) async -> OverseerrConnectionResult {
        guard let cookie = sessionCookie else {
            return OverseerrConnectionResult(valid: false, username: nil, error: "No session found")
        }

        do {
            let normalizedUrl = normalizeUrl(url)
            guard let requestUrl = URL(string: "\(normalizedUrl)/api/v1/auth/me") else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Invalid URL")
            }

            var request = URLRequest(url: requestUrl)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(cookie, forHTTPHeaderField: "Cookie")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Invalid response")
            }

            if httpResponse.statusCode == 401 {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Session expired")
            }

            if httpResponse.statusCode != 200 {
                return OverseerrConnectionResult(valid: false, username: nil, error: "Server error (\(httpResponse.statusCode))")
            }

            let user = try JSONDecoder().decode(OverseerrUser.self, from: data)
            let username = user.username ?? user.plexUsername ?? user.email ?? "user"
            return OverseerrConnectionResult(valid: true, username: username, error: nil)
        } catch {
            print("[OverseerrService] Session validation error: \(error)")
            return OverseerrConnectionResult(valid: false, username: nil, error: "Connection failed")
        }
    }

    /// Sign out of Overseerr (clear stored credentials)
    func signOut() {
        UserDefaults.standard.clearOverseerrAuth()
        clearCache()
        print("[OverseerrService] Signed out and cleared cache")
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
                status = parseMediaStatus(mediaInfo: details.mediaInfo, seasons: nil)
            } else {
                let details = try JSONDecoder().decode(OverseerrTvDetails.self, from: data)
                // For TV shows, get seasons from mediaInfo (which has per-season status)
                // Fall back to details.seasons if mediaInfo.seasons is not available
                let seasons = details.mediaInfo?.seasons ?? details.seasons
                status = parseMediaStatus(mediaInfo: details.mediaInfo, seasons: seasons)
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
    /// - Parameters:
    ///   - tmdbId: TMDB ID of the media
    ///   - mediaType: "movie" or "tv"
    ///   - seasons: Specific season numbers to request (for TV only). If nil, requests all available seasons.
    ///   - is4k: Whether to request 4K version
    func requestMedia(tmdbId: Int, mediaType: String, seasons: [Int]? = nil, is4k: Bool = false) async -> OverseerrRequestResult {
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
                let seasonsToRequest: [Int]
                if let specificSeasons = seasons, !specificSeasons.isEmpty {
                    // Use the specific seasons provided
                    seasonsToRequest = specificSeasons
                } else {
                    // Request all available seasons
                    seasonsToRequest = await getTvSeasons(tmdbId: tmdbId)
                }

                if seasonsToRequest.isEmpty {
                    return OverseerrRequestResult(success: false, requestId: nil, status: nil, error: "No seasons available to request")
                }
                requestBody["seasons"] = seasonsToRequest
                print("[OverseerrService] Requesting seasons: \(seasonsToRequest)")
            }

            let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
            let data = try await makeRequest(endpoint: "/request", method: "POST", body: bodyData)

            // Debug: Log raw response
            if let responseString = String(data: data, encoding: .utf8) {
                print("[OverseerrService] Raw response: \(responseString)")
            }

            // Try to decode the response - Overseerr returns different structures
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Check for error message in response (Overseerr returns 202 with message for some errors)
                if let message = json["message"] as? String {
                    print("[OverseerrService] API returned message: \(message)")
                    return OverseerrRequestResult(success: false, requestId: nil, status: nil, error: message)
                }

                // Clear cache for this item on success
                let cacheKey = "\(mediaType):\(tmdbId)"
                cache.removeValue(forKey: cacheKey)

                // Try to get request ID from response
                let requestId = json["id"] as? Int

                // Check status if available
                var status: OverseerrStatus = .pending
                if let statusCode = json["status"] as? Int {
                    if statusCode == MediaRequestStatusCode.approved.rawValue {
                        status = .approved
                    }
                }

                print("[OverseerrService] Request created successfully (id: \(requestId?.description ?? "unknown"))")
                return OverseerrRequestResult(success: true, requestId: requestId, status: status, error: nil)
            }

            // If we can't parse the response, assume success based on HTTP status
            let cacheKey = "\(mediaType):\(tmdbId)"
            cache.removeValue(forKey: cacheKey)
            print("[OverseerrService] Request created (response not parsed)")
            return OverseerrRequestResult(success: true, requestId: nil, status: .pending, error: nil)
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
        guard let serverUrl = serverUrl else {
            throw NSError(domain: "OverseerrService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Overseerr not configured"])
        }

        let normalizedUrl = normalizeUrl(serverUrl)
        guard let url = URL(string: "\(normalizedUrl)/api/v1\(endpoint)") else {
            throw NSError(domain: "OverseerrService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Set authentication header based on auth method
        switch authMethod {
        case .apiKey:
            guard let key = apiKey else {
                throw NSError(domain: "OverseerrService", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key not configured"])
            }
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        case .plex:
            guard let cookie = sessionCookie else {
                throw NSError(domain: "OverseerrService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Session expired. Please sign in again."])
            }
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OverseerrService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        // Handle session expiry for Plex auth
        if httpResponse.statusCode == 401 && authMethod == .plex {
            UserDefaults.standard.overseerrSessionCookie = ""
            throw NSError(domain: "OverseerrService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired. Please sign in again."])
        }

        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OverseerrService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Overseerr API error (\(httpResponse.statusCode)): \(errorText)"])
        }

        return data
    }

    private func parseMediaStatus(mediaInfo: OverseerrMediaInfo?, seasons: [OverseerrSeason]?) -> OverseerrMediaStatus {
        guard let mediaInfo = mediaInfo else {
            return OverseerrMediaStatus(status: .notRequested, canRequest: true, seasons: seasons)
        }

        // Check media availability status first
        switch mediaInfo.status {
        case MediaInfoStatusCode.available.rawValue:
            return OverseerrMediaStatus(status: .available, canRequest: false, seasons: seasons)
        case MediaInfoStatusCode.partiallyAvailable.rawValue:
            // For partially available, allow opening the picker if there are any unavailable seasons
            // (even if they're all partially available - we'll show an explanation)
            let unavailableSeasons = (seasons ?? []).filter { !$0.isAvailable && $0.seasonNumber > 0 }
            return OverseerrMediaStatus(status: .partiallyAvailable, canRequest: !unavailableSeasons.isEmpty, seasons: seasons)
        case MediaInfoStatusCode.processing.rawValue:
            return OverseerrMediaStatus(status: .processing, canRequest: false, seasons: seasons)
        default:
            break
        }

        // Check request status if media not available
        if let latestRequest = mediaInfo.requests?.first {
            switch latestRequest.status {
            case MediaRequestStatusCode.pending.rawValue:
                return OverseerrMediaStatus(status: .pending, requestId: latestRequest.id, canRequest: false, seasons: seasons)
            case MediaRequestStatusCode.approved.rawValue:
                return OverseerrMediaStatus(status: .approved, requestId: latestRequest.id, canRequest: false, seasons: seasons)
            case MediaRequestStatusCode.declined.rawValue:
                return OverseerrMediaStatus(status: .declined, requestId: latestRequest.id, canRequest: true, seasons: seasons)
            default:
                break
            }
        }

        // Default to not requested
        if mediaInfo.status == MediaInfoStatusCode.pending.rawValue {
            return OverseerrMediaStatus(status: .pending, canRequest: false, seasons: seasons)
        }

        return OverseerrMediaStatus(status: .notRequested, canRequest: true, seasons: seasons)
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
