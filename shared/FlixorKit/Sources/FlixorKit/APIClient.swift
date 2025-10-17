import Foundation

@MainActor
public final class APIClient: ObservableObject {
    public static let shared = APIClient()

    @Published public private(set) var isAuthenticated = false

    public var baseURL: URL
    private var session: URLSession
    private var token: String?

    public init() {
        let baseURLString = UserDefaults.standard.string(forKey: "backendBaseURL") ?? "http://localhost:3001"
        self.baseURL = URL(string: baseURLString)!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config)

        self.token = KeychainHelper.shared.getToken()
        self.isAuthenticated = (token != nil)
    }

    // MARK: - Configuration
    public func setBaseURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        self.baseURL = url
        UserDefaults.standard.set(urlString, forKey: "backendBaseURL")
    }

    public func setToken(_ token: String?) {
        self.token = token
        self.isAuthenticated = (token != nil)
        if let token = token { KeychainHelper.shared.saveToken(token) } else { KeychainHelper.shared.deleteToken() }
    }

    // MARK: - Requests
    public func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil, bypassCache: Bool = false) async throws -> T {
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = queryItems
        guard let url = urlComponents?.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if bypassCache { request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData }
        addHeaders(to: &request)
        return try await performRequest(request)
    }

    public func post<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addHeaders(to: &request)
        if let body = body { request.httpBody = try JSONEncoder().encode(body) }
        return try await performRequest(request)
    }

    public func put<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        addHeaders(to: &request)
        if let body = body { request.httpBody = try JSONEncoder().encode(body) }
        return try await performRequest(request)
    }

    public func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addHeaders(to: &request)
        return try await performRequest(request)
    }

    // MARK: - Helpers
    private func addHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        #if DEBUG
        if let url = request.url { print("🌐 [API] \(request.httpMethod ?? "GET") \(url.absoluteString)") }
        #endif
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.serverError("Invalid response") }
            #if DEBUG
            print("📡 [API] status=\(httpResponse.statusCode)")
            #endif
            switch httpResponse.statusCode {
            case 200...299:
                break
            case 401:
                await MainActor.run { self.setToken(nil) }
                throw APIError.unauthorized
            case 400...499:
                let message = try? JSONDecoder().decode([String: String].self, from: data)
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: message?["message"] ?? message?["error"])
            case 500...599:
                let message = try? JSONDecoder().decode([String: String].self, from: data)
                throw APIError.serverError(message?["message"] ?? message?["error"] ?? "Unknown server error")
            default:
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .useDefaultKeys
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(T.self, from: data)
            #if DEBUG
            if let s = String(data: data, encoding: .utf8) { print("✅ [API] body: \(s.prefix(200))…") }
            #endif
            return decoded
        } catch let e as APIError {
            #if DEBUG
            print("❌ [API] error: \(e)")
            #endif
            throw e
        } catch {
            #if DEBUG
            print("❌ [API] network error: \(error)")
            #endif
            throw APIError.networkError(error)
        }
    }
}

// MARK: - Health
public extension APIClient {
    func healthCheck() async throws -> [String: String] {
        let healthURL = baseURL.deletingLastPathComponent().appendingPathComponent("health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let r = response as? HTTPURLResponse, r.statusCode == 200 else { throw APIError.serverError("Health check failed") }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
}

// MARK: - Auth (Plex PIN)
public struct PlexPinInitResponse: Decodable { public let id: Int; public let code: String; public let clientId: String; public let authUrl: String }
public struct PlexPinStatusResponse: Decodable { public let authenticated: Bool?; public let user: User? }

public extension APIClient {
    func authPlexPinInit(clientId: String) async throws -> PlexPinInitResponse {
        struct Body: Encodable { let clientId: String }
        return try await post("/api/auth/plex/pin", body: Body(clientId: clientId))
    }

    func authPlexPinStatus(id: String, clientId: String) async throws -> PlexPinStatusResponse {
        return try await get("/api/auth/plex/pin/\(id)", queryItems: [URLQueryItem(name: "clientId", value: clientId)])
    }
}

// MARK: - TMDB & Plex.tv Watchlist
public struct TMDBTrendingResponse: Codable { public let results: [TMDBTitle] }
public struct TMDBTitle: Codable { public let id: Int; public let name: String?; public let title: String?; public let backdrop_path: String?; public let poster_path: String? }
public extension APIClient {
    func getTMDBTrending(mediaType: String, timeWindow: String, page: Int = 1) async throws -> TMDBTrendingResponse {
        try await get("/api/tmdb/trending/\(mediaType)/\(timeWindow)", queryItems: [URLQueryItem(name: "page", value: String(page))])
    }
}

public struct PlexWatchlistEnvelope: Codable { public let MediaContainer: PlexWatchlistMC }
public struct PlexWatchlistMC: Codable { public let Metadata: [MediaItemFull]? }
public extension APIClient {
    func getPlexTvWatchlist() async throws -> PlexWatchlistEnvelope { try await get("/api/plextv/watchlist") }
}

// MARK: - Plex markers
public struct PlexMarker: Decodable { public let id: String?; public let type: String?; public let startTimeOffset: Int?; public let endTimeOffset: Int? }
private struct PlexMarkersEnvelope: Decodable { let MediaContainer: PlexMarkersContainer? }
private struct PlexMarkersContainer: Decodable { let Metadata: [PlexMarkersMetadata]? }
private struct PlexMarkersMetadata: Decodable { let Marker: [PlexMarker]? }

public extension APIClient {
    func getPlexMarkers(ratingKey: String) async throws -> [PlexMarker] {
        let encoded = ratingKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ratingKey
        let path = "/api/plex/dir/library/metadata/\(encoded)"
        let env: PlexMarkersEnvelope = try await get(path, queryItems: [URLQueryItem(name: "includeMarkers", value: "1")])
        return env.MediaContainer?.Metadata?.first?.Marker ?? []
    }
}

// MARK: - Plex & external API method surface (subset)
public extension APIClient {
    func getPlexServers() async throws -> [PlexServer] { try await get("/api/plex/servers") }
    func getPlexConnections(serverId: String) async throws -> PlexConnectionsResponse {
        let encodedId = serverId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? serverId
        return try await get("/api/plex/servers/\(encodedId)/connections")
    }
    func getPlexLibraries() async throws -> [PlexLibrary] { try await get("/api/plex/libraries") }
    func getPlexContinueList() async throws -> [MediaItemFull] { try await get("/api/plex/continue") }
    func getPlexOnDeckList() async throws -> [MediaItemFull] { try await get("/api/plex/ondeck") }
    func getPlexRecentList(libraryKey: String? = nil) async throws -> [MediaItemFull] {
        var q: [URLQueryItem]? = nil
        if let libraryKey { q = [URLQueryItem(name: "library", value: libraryKey)] }
        return try await get("/api/plex/recent", queryItems: q)
    }
    func setCurrentPlexServer(serverId: String) async throws -> SimpleMessageResponse {
        struct Body: Encodable { let serverId: String }
        return try await post("/api/plex/servers/current", body: Body(serverId: serverId))
    }
}

// MARK: - UltraBlur Colors
public struct UltraBlurColors: Codable, Equatable {
    public let topLeft: String
    public let topRight: String
    public let bottomLeft: String
    public let bottomRight: String

    public init(topLeft: String, topRight: String, bottomLeft: String, bottomRight: String) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
}

public extension APIClient {
    func getUltraBlurColors(imageUrl: String) async throws -> UltraBlurColors {
        let queryItems = [URLQueryItem(name: "imageUrl", value: imageUrl)]
        return try await get("/api/plex/ultrablur/colors", queryItems: queryItems)
    }
}

// MARK: - Additional models used by endpoints
public struct PlexLibrary: Decodable { public let key: String; public let title: String?; public let type: String }
