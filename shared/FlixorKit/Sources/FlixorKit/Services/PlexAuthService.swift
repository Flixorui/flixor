//
//  PlexAuthService.swift
//  FlixorKit
//
//  Handles Plex.tv authentication (PIN flow)
//  Reference: packages/core/src/services/PlexAuthService.ts
//

import Foundation

// MARK: - Models

public struct PlexPin: Codable {
    public let id: Int
    public let code: String

    public var authUrl: String {
        "https://app.plex.tv/auth#?clientID=\(code)&code=\(code)&context%5Bdevice%5D%5Bproduct%5D=Flixor"
    }
}

public struct PlexPinResponse: Codable {
    public let id: Int
    public let code: String
    public let authToken: String?
}

public struct PlexUser: Codable {
    public let id: Int
    public let uuid: String
    public let username: String
    public let email: String?
    public let thumb: String?
    public let title: String?
}

/// Plex Home user (managed user or family member)
public struct PlexHomeUser: Codable, Identifiable {
    public let id: Int
    public let uuid: String
    public let title: String
    public let username: String?
    public let email: String?
    public let thumb: String?
    public let restricted: Bool      // true = managed/child account
    public let `protected`: Bool     // true = requires PIN
    public let admin: Bool
    public let guest: Bool
    public let home: Bool

    public init(id: Int, uuid: String, title: String, username: String?, email: String?, thumb: String?, restricted: Bool, protected: Bool, admin: Bool, guest: Bool, home: Bool) {
        self.id = id
        self.uuid = uuid
        self.title = title
        self.username = username
        self.email = email
        self.thumb = thumb
        self.restricted = restricted
        self.protected = `protected`
        self.admin = admin
        self.guest = guest
        self.home = home
    }
}

/// Response from home users API
private struct PlexHomeUsersResponse: Codable {
    let users: [PlexHomeUserRaw]?
}

/// Raw home user from API (before transformation)
private struct PlexHomeUserRaw: Codable {
    let id: Int
    let uuid: String
    let title: String?
    let username: String?
    let email: String?
    let thumb: String?
    let restricted: Bool?
    let `protected`: Bool?
    let admin: Bool?
    let guest: Bool?
    let home: Bool?
}

/// Response from switch user API
private struct PlexSwitchUserResponse: Codable {
    let authToken: String?
    let authenticationToken: String?
}

/// Active profile info
public struct ActiveProfile: Codable {
    public let userId: Int
    public let uuid: String
    public let title: String
    public let thumb: String?
    public let restricted: Bool
    public let `protected`: Bool

    public init(userId: Int, uuid: String, title: String, thumb: String?, restricted: Bool, protected: Bool) {
        self.userId = userId
        self.uuid = uuid
        self.title = title
        self.thumb = thumb
        self.restricted = restricted
        self.protected = `protected`
    }
}

// MARK: - PlexAuthService

public class PlexAuthService {
    private let clientId: String
    private let productName: String
    private let productVersion: String
    private let platform: String
    private let deviceName: String

    private let plexTvUrl = "https://plex.tv"

    public init(
        clientId: String,
        productName: String = "Flixor",
        productVersion: String = "1.0.0",
        platform: String = "macOS",
        deviceName: String = "Flixor Mac"
    ) {
        self.clientId = clientId
        self.productName = productName
        self.productVersion = productVersion
        self.platform = platform
        self.deviceName = deviceName
    }

    // MARK: - Headers

    private func getHeaders(token: String? = nil) -> [String: String] {
        var headers: [String: String] = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Plex-Client-Identifier": clientId,
            "X-Plex-Product": productName,
            "X-Plex-Version": productVersion,
            "X-Plex-Platform": platform,
            "X-Plex-Platform-Version": productVersion,
            "X-Plex-Device": platform,
            "X-Plex-Device-Name": deviceName
        ]

        if let token = token {
            headers["X-Plex-Token"] = token
        }

        return headers
    }

    // MARK: - PIN Authentication

    /// Create a new PIN for authentication
    /// User should visit plex.tv/link and enter the code
    public func createPin() async throws -> PlexPin {
        guard let url = URL(string: "\(plexTvUrl)/api/v2/pins?strong=true") else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Use form-urlencoded content type for PIN creation
        var headers = getHeaders()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        headers["X-Plex-Model"] = "hosted"

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let responseStr = String(data: data, encoding: .utf8) ?? ""
            print("❌ [PlexAuth] PIN creation failed: \(httpResponse.statusCode) - \(responseStr)")
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }

        let pinResponse = try JSONDecoder().decode(PlexPinResponse.self, from: data)
        return PlexPin(id: pinResponse.id, code: pinResponse.code)
    }

    /// Check if PIN has been authorized
    /// Returns authToken if authorized, nil if still pending
    public func checkPin(id: Int) async throws -> String? {
        guard let url = URL(string: "\(plexTvUrl)/api/v2/pins/\(id)") else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw PlexAuthError.pinExpired
        }

        guard httpResponse.statusCode == 200 else {
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }

        let pinResponse = try JSONDecoder().decode(PlexPinResponse.self, from: data)
        return pinResponse.authToken
    }

    /// Poll for PIN authorization with timeout
    public func waitForPin(
        id: Int,
        intervalMs: Int = 2000,
        timeoutMs: Int = 300000,
        onPoll: (() -> Void)? = nil
    ) async throws -> String {
        let startTime = Date()
        let timeoutSeconds = TimeInterval(timeoutMs) / 1000.0

        while Date().timeIntervalSince(startTime) < timeoutSeconds {
            onPoll?()

            if let token = try await checkPin(id: id) {
                return token
            }

            try await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
        }

        throw PlexAuthError.pinTimeout
    }

    // MARK: - User & Servers

    /// Get authenticated user information
    public func getUser(token: String) async throws -> PlexUser {
        guard let url = URL(string: "\(plexTvUrl)/api/v2/user") else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw PlexAuthError.invalidToken
        }

        guard httpResponse.statusCode == 200 else {
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(PlexUser.self, from: data)
    }

    /// Get available Plex servers for the authenticated user
    public func getServers(token: String) async throws -> [PlexServerResource] {
        guard let url = URL(string: "\(plexTvUrl)/api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1") else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }

        let resources = try JSONDecoder().decode([PlexResource].self, from: data)

        // Filter to only Plex Media Servers with valid access tokens and connections
        return resources
            .filter { $0.provides == "server" && $0.accessToken != nil && $0.connections != nil && !$0.connections!.isEmpty }
            .compactMap { resource -> PlexServerResource? in
                guard let accessToken = resource.accessToken,
                      let connections = resource.connections,
                      !connections.isEmpty else { return nil }
                return PlexServerResource(
                    id: resource.clientIdentifier,
                    name: resource.name,
                    owned: resource.owned ?? false,
                    accessToken: accessToken,
                    publicAddress: resource.publicAddress,
                    presence: resource.presence,
                    connections: connections.map { conn in
                        PlexConnectionResource(
                            uri: conn.uri,
                            `protocol`: conn.protocol,
                            local: conn.local,
                            relay: conn.relay,
                            IPv6: conn.IPv6
                        )
                    }
                )
            }
    }

    /// Test a server connection
    /// Returns true if connection is valid and accessible
    public func testConnection(_ connection: PlexConnectionResource, token: String) async throws -> Bool {
        guard let url = URL(string: "\(connection.uri)/identity") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0

        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    /// Sign out - revoke the token
    public func signOut(token: String) async {
        guard let url = URL(string: "\(plexTvUrl)/api/v2/tokens/\(token)") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Plex Home / Profile Management

    /// Get list of Plex Home users
    /// Returns empty array if user is not part of a Plex Home
    public func getHomeUsers(token: String) async throws -> [PlexHomeUser] {
        guard let url = URL(string: "\(plexTvUrl)/api/v2/home/users") else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }

        // 403 means user is not part of a Plex Home
        if httpResponse.statusCode == 403 {
            return []
        }

        guard httpResponse.statusCode == 200 else {
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }

        // Try to decode as object with users array first, then as direct array
        let users: [PlexHomeUserRaw]
        if let responseObj = try? JSONDecoder().decode(PlexHomeUsersResponse.self, from: data) {
            users = responseObj.users ?? []
        } else if let directArray = try? JSONDecoder().decode([PlexHomeUserRaw].self, from: data) {
            users = directArray
        } else {
            return []
        }

        return users.map { raw in
            PlexHomeUser(
                id: raw.id,
                uuid: raw.uuid,
                title: raw.title ?? raw.username ?? "Unknown",
                username: raw.username,
                email: raw.email,
                thumb: raw.thumb,
                restricted: raw.restricted ?? false,
                protected: raw.protected ?? false,
                admin: raw.admin ?? false,
                guest: raw.guest ?? false,
                home: raw.home ?? false
            )
        }
    }

    /// Switch to a different Plex Home user
    /// - Parameters:
    ///   - token: Main account token
    ///   - userUuid: Target user UUID to switch to
    ///   - pin: PIN if the user is protected (has PIN set)
    /// - Returns: New authentication token for the switched user
    public func switchHomeUser(token: String, userUuid: String, pin: String? = nil) async throws -> String {
        var urlString = "\(plexTvUrl)/api/v2/home/users/\(userUuid)/switch"
        if let pin = pin {
            urlString += "?pin=\(pin)"
        }

        guard let url = URL(string: urlString) else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        for (key, value) in getHeaders(token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAuthError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw PlexAuthError.invalidPin
        }

        if httpResponse.statusCode == 403 {
            throw PlexAuthError.notAuthorizedToSwitch
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw PlexAuthError.httpError(statusCode: httpResponse.statusCode)
        }

        let switchResponse = try JSONDecoder().decode(PlexSwitchUserResponse.self, from: data)

        guard let authToken = switchResponse.authToken ?? switchResponse.authenticationToken else {
            throw PlexAuthError.noAuthTokenInResponse
        }

        return authToken
    }
}

// MARK: - Supporting Models

public struct PlexResource: Codable {
    public let name: String
    public let product: String?
    public let productVersion: String?
    public let platform: String?
    public let platformVersion: String?
    public let device: String?
    public let clientIdentifier: String
    public let createdAt: String?
    public let lastSeenAt: String?
    public let provides: String
    public let owned: Bool?
    public let accessToken: String?
    public let publicAddress: String?
    public let httpsRequired: Bool?
    public let synced: Bool?
    public let relay: Bool?
    public let dnsRebindingProtection: Bool?
    public let natLoopbackSupported: Bool?
    public let publicAddressMatches: Bool?
    public let presence: Bool?
    public let connections: [PlexResourceConnection]?
}

public struct PlexResourceConnection: Codable {
    public let `protocol`: String
    public let address: String
    public let port: Int
    public let uri: String
    public let local: Bool
    public let relay: Bool
    public let IPv6: Bool
}

public struct PlexServerResource: Codable, Identifiable {
    public let id: String
    public let name: String
    public let owned: Bool
    public let accessToken: String
    public let publicAddress: String?
    public let presence: Bool?
    public let connections: [PlexConnectionResource]

    public init(id: String, name: String, owned: Bool, accessToken: String, publicAddress: String?, presence: Bool?, connections: [PlexConnectionResource]) {
        self.id = id
        self.name = name
        self.owned = owned
        self.accessToken = accessToken
        self.publicAddress = publicAddress
        self.presence = presence
        self.connections = connections
    }
}

public struct PlexConnectionResource: Codable, Identifiable {
    public let uri: String
    public let `protocol`: String
    public let local: Bool
    public let relay: Bool
    public let IPv6: Bool

    public var id: String { uri }

    public init(uri: String, protocol: String, local: Bool, relay: Bool, IPv6: Bool) {
        self.uri = uri
        self.protocol = `protocol`
        self.local = local
        self.relay = relay
        self.IPv6 = IPv6
    }
}

// MARK: - Errors

public enum PlexAuthError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case pinExpired
    case pinTimeout
    case invalidToken
    case invalidPin
    case notAuthorizedToSwitch
    case noAuthTokenInResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .pinExpired:
            return "PIN expired or not found"
        case .pinTimeout:
            return "PIN authorization timed out"
        case .invalidToken:
            return "Invalid or expired token"
        case .invalidPin:
            return "Invalid PIN"
        case .notAuthorizedToSwitch:
            return "Not authorized to switch to this user"
        case .noAuthTokenInResponse:
            return "No authentication token in response"
        }
    }
}
